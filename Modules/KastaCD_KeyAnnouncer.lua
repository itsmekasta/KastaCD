-- =============================================================
-- KastaCD_KeyAnnouncer.lua
--
-- Backported from the standalone "MythicKeyAnnouncer" addon (Anahkas) -
-- responds to "keys please" in party/raid/instance/guild chat (or /kcdkeys)
-- by announcing your currently-owned Mythic Keystone's dungeon and
-- level. Lives in the Keystone Helper section (KastaCD_Options.lua)
-- alongside Ready Check/Pull Timer/Mob Count.
--
-- MythicKeyAnnouncer targets modern retail (C_MythicPlus namespace,
-- which doesn't exist in Legion 7.3.5) and detects keystones via the
-- |Hkeystone: link type introduced in a later expansion. Legion's
-- Mythic Keystone is a plain item instead (a shared base item ID with
-- per-dungeon bonus data), so detection reuses
-- KastaCD_Keystone.lua's existing FindKeystoneBagSlot() (name-substring
-- match, not a hardcoded ID) and derives the dungeon name from the
-- item's own display name ("Keystone: <Dungeon>").
--
-- The keystone LEVEL isn't exposed by any Legion API the way retail's
-- C_MythicPlus.GetOwnedKeystoneLevel() does, so it's read from the
-- item's own tooltip text instead (best-effort pattern match on a
-- "Level %d" line, matching the wording shown on the Font of Power
-- keystone frame itself). Run /kcdkeysdebug while holding a keystone to
-- dump every tooltip line if the level ever comes back wrong/missing,
-- so the pattern can be corrected against what this server's client
-- actually shows instead of guessing further.
--
-- Depends on: KastaCD_Keystone.lua (FindKeystoneBagSlot, GetKeystoneDB).
-- =============================================================

function GetKeyAnnouncerDB()
    KastaCDDB = KastaCDDB or {}
    local db = KastaCDDB.keyAnnouncer
    if not db then
        db = {}
        KastaCDDB.keyAnnouncer = db
    end
    if db.enabled         == nil then db.enabled         = true  end
    if db.triggerEnabled  == nil then db.triggerEnabled  = true  end
    if db.mode            == nil then db.mode            = "AUTO" end   -- AUTO | SEMI | MANUAL
    if db.channel         == nil then db.channel         = "AUTO" end   -- AUTO | PARTY | RAID | INSTANCE | GUILD
    if db.cooldown        == nil then db.cooldown        = 15    end
    if db.colorFormatting == nil then db.colorFormatting = true  end
    return db
end

-- "keys please" (the original MythicKeyAnnouncer trigger) doesn't work on this
-- server - confirmed live: sending it produced a "no such command" reply,
-- meaning the server itself intercepts "!"-prefixed chat as a custom
-- command attempt before it ever reaches other players as normal chat,
-- so nobody's CHAT_MSG_PARTY handler ever saw it. Plain words with no
-- special prefix character pass through fine.
local TRIGGER_TEXT = "keys please"

-- -------------------------------------------------------------
-- Keystone info (dungeon name + level)
-- -------------------------------------------------------------
local hiddenTooltip = CreateFrame("GameTooltip", "KastaCDKeyAnnouncerTooltip", nil, "GameTooltipTemplate")
hiddenTooltip:SetOwner(UIParent, "ANCHOR_NONE")

-- Reads BOTH the dungeon name and the level from a single tooltip scan.
-- GetItemInfo(link) was tried first for the name, but it can return nil
-- on a fresh session before the server has answered the async item-info
-- request (a well-known WoW quirk) - confirmed live: the level parsed
-- fine from the tooltip while GetItemInfo's name lookup came back nil at
-- the same moment. The tooltip itself doesn't have that problem (SetBagItem
-- forces a render), so the item's own display name (tooltip line 1,
-- "Keystone: <Dungeon>") is used for the name too instead of relying on
-- a second, less reliable source.
local function ScanKeystoneTooltip(bag, slot)
    hiddenTooltip:ClearLines()
    hiddenTooltip:SetBagItem(bag, slot)

    local dungeonName, level
    for i = 1, hiddenTooltip:NumLines() do
        local fs = _G["KastaCDKeyAnnouncerTooltipTextLeft" .. i]
        local text = fs and fs:GetText()
        if text then
            if i == 1 then
                dungeonName = text:match("^Keystone:%s*(.+)$") or text
            end
            if not level then
                level = text:match("Level (%d+)") or text:match("^%+(%d+)")
            end
        end
    end
    return dungeonName, level and tonumber(level)
end

function GetOwnedKeystoneInfo()
    local bag, slot = FindKeystoneBagSlot()
    if not bag then return nil end

    local link = GetContainerItemLink(bag, slot)
    local dungeonName, level = ScanKeystoneTooltip(bag, slot)

    return {
        dungeonName = dungeonName or "Unknown Dungeon",
        level = level,
        itemLink = link,
    }
end

-- -------------------------------------------------------------
-- Message building / sending
-- -------------------------------------------------------------
local function BuildAnnounceMessage()
    local info = GetOwnedKeystoneInfo()
    if not info then
        return "I don't currently have a Mythic Keystone."
    end
    local levelText = info.level and ("+" .. info.level) or "?"
    if GetKeyAnnouncerDB().colorFormatting then
        return string.format("|cff00ff98%s|r |cffffff00%s|r", info.dungeonName, levelText)
    end
    return string.format("%s %s", info.dungeonName, levelText)
end

local function ResolveChannel(preferred)
    local channel = preferred or GetKeyAnnouncerDB().channel or "AUTO"

    if channel == "AUTO" then
        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
        if IsInRaid() then return "RAID" end
        if IsInGroup() then return "PARTY" end
        return nil, "No valid announce channel is available right now."
    end

    if channel == "INSTANCE" then
        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) or (IsInGroup() and IsInInstance()) then
            return "INSTANCE_CHAT"
        end
        return nil, "Instance chat is not currently available."
    end

    if channel == "PARTY" then
        if IsInGroup() and not IsInRaid() then return "PARTY" end
        return nil, "Party chat is not currently available."
    end

    if channel == "RAID" then
        if IsInRaid() then return "RAID" end
        return nil, "Raid chat is not currently available."
    end

    if channel == "GUILD" then
        if IsInGuild() then return "GUILD" end
        return nil, "Guild chat is not currently available."
    end

    return nil, "Unknown announce channel."
end

function AnnounceKeystone(force, preferredChannel)
    local db = GetKeyAnnouncerDB()
    if not db.enabled and not force then return end

    local chatType, err = ResolveChannel(preferredChannel)
    if not chatType then
        print("|cffff8000KastaCD:|r " .. tostring(err))
        return
    end

    SendChatMessage(BuildAnnounceMessage(), chatType)
end

-- -------------------------------------------------------------
-- "keys please" chat trigger + cooldown/spam protection - one combined
-- cooldown applied both globally and per-sender (simpler than the
-- original's three separate cooldown knobs; KastaCD's other trackers
-- follow the same "fewer knobs" convention).
-- -------------------------------------------------------------
local lastGlobalAnnounce = 0
local lastSenderAnnounce = {}   -- [senderShort] = time

local function CanRespondTo(senderShort)
    local db = GetKeyAnnouncerDB()
    local now = GetTime()
    if (now - lastGlobalAnnounce) < db.cooldown then return false end
    local last = lastSenderAnnounce[senderShort]
    if last and (now - last) < db.cooldown then return false end
    return true
end

local function MarkResponded(senderShort)
    local now = GetTime()
    lastGlobalAnnounce = now
    lastSenderAnnounce[senderShort] = now
end

-- -------------------------------------------------------------
-- Semi-auto confirmation prompt - shown instead of auto-announcing when
-- Response Mode is "Semi-Auto", so you can confirm before your keystone
-- gets broadcast. Auto-dismisses after 10s.
-- -------------------------------------------------------------
local promptFrame

local function HidePrompt()
    if promptFrame then promptFrame:Hide() end
end

local function ShowPrompt(senderShort)
    if not promptFrame then
        local f = CreateFrame("Frame", "KastaCDKeyAnnouncerPrompt", UIParent)
        f:SetSize(300, 100)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12, insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        f:SetBackdropColor(0, 0, 0, 0.9)

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.title:SetPoint("TOP", 0, -12)
        f.title:SetText("Keystone Request")

        f.message = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.message:SetPoint("TOP", f.title, "BOTTOM", 0, -10)
        f.message:SetWidth(260)
        f.message:SetJustifyH("CENTER")

        f.announceBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.announceBtn:SetSize(100, 22)
        f.announceBtn:SetPoint("BOTTOMLEFT", 30, 16)
        f.announceBtn:SetText("Announce")

        f.ignoreBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.ignoreBtn:SetSize(100, 22)
        f.ignoreBtn:SetPoint("BOTTOMRIGHT", -30, 16)
        f.ignoreBtn:SetText("Ignore")
        f.ignoreBtn:SetScript("OnClick", HidePrompt)

        f:Hide()
        promptFrame = f
    end

    promptFrame.message:SetText(tostring(senderShort) .. " requested keys please.")
    promptFrame.announceBtn:SetScript("OnClick", function()
        AnnounceKeystone(true)
        HidePrompt()
    end)
    promptFrame:Show()

    C_Timer.After(10, function()
        if promptFrame and promptFrame:IsShown() then HidePrompt() end
    end)
end

-- -------------------------------------------------------------
-- Login reminder - the trigger phrase otherwise only appears in options
-- tooltips, which nobody sees without deliberately hovering each one.
-- Printed once per login (not on every zone change) so it's visible
-- without ever having to open the settings menu at all.
-- -------------------------------------------------------------
local remindedThisSession = false
local function PrintLoginReminder()
    if remindedThisSession then return end
    remindedThisSession = true
    local db = GetKeyAnnouncerDB()
    if not db.enabled or not db.triggerEnabled then return end
    print(("|cff71d5ffKastaCD Key Announcer:|r type |cffffd200%s|r in party/raid/instance/guild chat (no slash, just plain text) to have it announce your Mythic Keystone."):format(TRIGGER_TEXT))
end

-- -------------------------------------------------------------
-- Events
-- -------------------------------------------------------------
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
for _, e in ipairs({
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_GUILD",
}) do
    watcher:RegisterEvent(e)
end
-- Matches "keys please" ANYWHERE in the message (not an exact full-message
-- match) - a private server can relay chat with extra whitespace/
-- punctuation intact, and an exact match would silently miss those.
-- Anything that doesn't contain it at all is ignored completely with no
-- output, so normal chat traffic doesn't get spammed with prints below.
watcher:SetScript("OnEvent", function(_, event, message, sender)
    if event == "PLAYER_ENTERING_WORLD" then
        PrintLoginReminder()
        return
    end
    if not message or not message:lower():find(TRIGGER_TEXT, 1, true) then return end

    local db = GetKeyAnnouncerDB()
    local senderShort = (Ambiguate and Ambiguate(sender, "short")) or sender

    -- From here on, "keys please" was definitely seen - print WHY it did or
    -- didn't get a response instead of failing silently, so a "why isn't
    -- this working" report has an immediate, concrete answer.
    if not db.enabled or not db.triggerEnabled then
        print(("|cffff8000KastaCD KeyAnnouncer:|r saw \"keys please\" from %s but the announcer or its chat trigger is disabled in Settings."):format(tostring(senderShort)))
        return
    end

    if not CanRespondTo(senderShort) then
        print(("|cffff8000KastaCD KeyAnnouncer:|r saw keys please from %s but still on cooldown (%ds)."):format(tostring(senderShort), db.cooldown))
        return
    end

    if db.mode == "MANUAL" then
        print(("|cffff8000KastaCD KeyAnnouncer:|r saw keys please from %s but Response Mode is Manual - use /kcdkeys to announce."):format(tostring(senderShort)))
        return
    elseif db.mode == "SEMI" then
        MarkResponded(senderShort)
        ShowPrompt(senderShort)
    else -- AUTO
        MarkResponded(senderShort)
        AnnounceKeystone(true)
    end
end)

-- -------------------------------------------------------------
-- /kcdkeys - manual announce. /kcdkeys guild forces guild chat.
-- /kcdkeys test previews the message without sending it.
-- /kcdkeys ask actually SENDS the literal "keys please" text to chat, so
-- everyone else's KastaCD trigger fires - plain /kcdkeys only ever
-- announces YOUR OWN key, it was never the thing that asks others.
-- -------------------------------------------------------------
SLASH_KASTACDKEYS1 = "/kcdkeys"
SlashCmdList["KASTACDKEYS"] = function(msg)
    local arg = (msg or ""):match("^%s*(.-)%s*$"):lower()
    if arg == "guild" then
        AnnounceKeystone(true, "GUILD")
    elseif arg == "test" then
        print("|cff44ff44KastaCD:|r Preview: " .. BuildAnnounceMessage())
    elseif arg == "ask" then
        local chatType, err = ResolveChannel()
        if not chatType then
            print("|cffff8000KastaCD:|r " .. tostring(err))
            return
        end
        SendChatMessage(TRIGGER_TEXT, chatType)
    else
        AnnounceKeystone(true)
    end
end

-- =============================================================
-- Debug helper: /kcdkeysdebug - dumps every line of the owned
-- keystone's tooltip, so the level-parsing pattern above can be
-- corrected against what this server's client actually shows instead of
-- guessing further.
-- =============================================================
SLASH_KASTACDKEYSDEBUG1 = "/kcdkeysdebug"
SlashCmdList["KASTACDKEYSDEBUG"] = function()
    local bag, slot = FindKeystoneBagSlot()
    if not bag then
        print("|cff00ff00KastaCD KeyAnnouncer Debug|r -- no keystone found in bags")
        return
    end
    print(("|cff00ff00KastaCD KeyAnnouncer Debug|r -- bag=%d slot=%d"):format(bag, slot))
    local link = GetContainerItemLink(bag, slot)
    print("  item link: " .. tostring(link))
    print("  GetItemInfo name: " .. tostring(link and GetItemInfo(link)))

    hiddenTooltip:ClearLines()
    hiddenTooltip:SetBagItem(bag, slot)
    for i = 1, hiddenTooltip:NumLines() do
        local fs = _G["KastaCDKeyAnnouncerTooltipTextLeft" .. i]
        print(("  line %d: %s"):format(i, tostring(fs and fs:GetText())))
    end

    local dungeonName, level = ScanKeystoneTooltip(bag, slot)
    print("  Parsed dungeon: " .. tostring(dungeonName))
    print("  Parsed level: " .. tostring(level))
    print("  Built message: " .. BuildAnnounceMessage())
end
