-- =============================================================
-- KastaCD_Keystone.lua
--
-- Adds "Ready Check" and "Pull Timer" buttons to the Mythic+ keystone
-- frame (ChallengesKeystoneFrame, shown when interacting with a Font of
-- Power), and best-effort auto-inserts the player's keystone into that
-- frame as soon as it opens.
--
-- NOTE on the auto-insert piece: WoW's item-movement APIs are among the
-- most taint-sensitive in the game. Rather than manually dragging the
-- item onto the frame's slot (which requires knowing that slot's exact
-- internal name and risks taint if done outside a hardware event), this
-- uses UseContainerItem() on the keystone while the frame is already
-- open - this is the same insecure, everyday "right-click to use" action
-- players take normally, and it's what the default UI's own quest/key
-- item click-to-slot handling relies on for frames like this. It's
-- wrapped in pcall and gated by its own toggle in case it doesn't behave
-- as expected on a live client.
-- =============================================================

-- Each dungeon's Mythic Keystone has its own item name/ID (e.g. "Keystone:
-- Maw of Souls"), so detection matches on the shared "Keystone" name
-- substring rather than one hardcoded item ID.

function GetKeystoneDB()
    KastaCDDB = KastaCDDB or {}
    local db = KastaCDDB.keystone
    if not db then
        db = {}
        KastaCDDB.keystone = db
    end
    if db.enabled == nil then db.enabled = true end
    if db.autoInsert == nil then db.autoInsert = true end
    if db.pullTimerSeconds == nil then db.pullTimerSeconds = 10 end
    return db
end

local function IsKeystoneHelperEnabled()
    return GetKeystoneDB().enabled == true
end

local function RunSlashCommand(msg)
    local editBox = (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox) or ChatFrame1EditBox
    if not editBox then return end
    editBox:SetText(msg)
    ChatEdit_SendText(editBox, 0)
end

local function CreateKeystoneButtons(frame)
    if frame.kastaCDButtonsAdded then return end
    frame.kastaCDButtonsAdded = true

    local readyBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    readyBtn:SetSize(112, 26)
    readyBtn:SetText("Ready Check")
    readyBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 18)
    readyBtn:SetFrameStrata(frame:GetFrameStrata())
    readyBtn:SetScript("OnClick", function()
        if not IsKeystoneHelperEnabled() then return end
        if IsInGroup() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
            DoReadyCheck()
        else
            print("|cffff8000KastaCD:|r You must be the group leader or an assistant to start a ready check.")
        end
    end)

    local pullBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    pullBtn:SetSize(112, 26)
    pullBtn:SetText("Pull Timer")
    pullBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 18)
    pullBtn:SetFrameStrata(frame:GetFrameStrata())
    pullBtn:SetScript("OnClick", function()
        if not IsKeystoneHelperEnabled() then return end
        RunSlashCommand("/rt pull timer " .. tostring(GetKeystoneDB().pullTimerSeconds))
    end)

    frame.kastaCDReadyBtn = readyBtn
    frame.kastaCDPullBtn = pullBtn
end

-- Global (not local) - also used by KastaCD_KeyAnnouncer.lua so it
-- doesn't need its own separate bag-scan for the same item.
function FindKeystoneBagSlot()
    for bag = 0, NUM_BAG_SLOTS do
        local slots = GetContainerNumSlots(bag)
        for slot = 1, slots do
            local link = GetContainerItemLink(bag, slot)
            if link and link:find("Keystone") then
                return bag, slot
            end
        end
    end
    return nil
end

local function TryAutoSlotKeystone(frame)
    if not IsKeystoneHelperEnabled() then return end
    if not GetKeystoneDB().autoInsert then return end
    if not frame:IsShown() then return end

    local bag, slot = FindKeystoneBagSlot()
    if not bag then return end

    UseContainerItem(bag, slot)
end

local function RaiseKeystoneFrameStrata(f)
    -- Font of Power interaction can spawn this frame low enough in the UI
    -- stack to clip behind action bars - TOOLTIP is the highest strata WoW
    -- has, guaranteeing it always draws on top.
    f:SetFrameStrata("TOOLTIP")
end

local function HookKeystoneFrame(frame)
    RaiseKeystoneFrameStrata(frame)
    CreateKeystoneButtons(frame)
    frame:HookScript("OnShow", function(f)
        RaiseKeystoneFrameStrata(f)
        CreateKeystoneButtons(f)
        C_Timer.After(0.2, function()
            local ok, err = pcall(TryAutoSlotKeystone, f)
            if not ok then
                print("|cffff8000KastaCD:|r Keystone auto-insert failed: " .. tostring(err))
            end
        end)
    end)
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_LOADED")
watcher:SetScript("OnEvent", function(self, _, name)
    if name ~= "Blizzard_ChallengesUI" then return end
    if not _G.ChallengesKeystoneFrame then return end
    self:UnregisterEvent("ADDON_LOADED")
    HookKeystoneFrame(_G.ChallengesKeystoneFrame)
end)

-- Blizzard_ChallengesUI may already be loaded (e.g. reload while standing
-- at a Font of Power) by the time this file runs - handle that directly.
if _G.ChallengesKeystoneFrame then
    watcher:UnregisterEvent("ADDON_LOADED")
    HookKeystoneFrame(_G.ChallengesKeystoneFrame)
end

-- =============================================================
-- Debug helper: /kcdks - run this while the Font of Power keystone frame
-- is open on screen. Prints (1) every global frame whose name mentions
-- "Keystone"/"Challenge" plus whether it's currently shown, and (2) every
-- bag item whose name/link mentions "Keystone" plus its exact item ID.
-- This is how we find the real frame name and item ID instead of
-- guessing - delete this block once the feature is confirmed working.
-- =============================================================
SLASH_KASTACDKEYSTONEDEBUG1 = "/kcdks"
SlashCmdList["KASTACDKEYSTONEDEBUG"] = function()
    print("|cff00ff00KastaCD Keystone Debug|r -- frames:")
    local found = false
    for k, v in pairs(_G) do
        if type(k) == "string" and (k:find("Keystone") or k:find("Challenge"))
            and type(v) == "table" and v.GetObjectType and v:GetObjectType()
        then
            found = true
            local ok, shown = pcall(function() return v:IsShown() end)
            print(("  %s (shown=%s)"):format(k, ok and tostring(shown) or "?"))
        end
    end
    if not found then print("  (none found - Blizzard_ChallengesUI may not be loaded yet)") end

    print("|cff00ff00KastaCD Keystone Debug|r -- bag items:")
    found = false
    for bag = 0, NUM_BAG_SLOTS do
        local slots = GetContainerNumSlots(bag)
        for slot = 1, slots do
            local link = GetContainerItemLink(bag, slot)
            local name = link and GetItemInfo(link)
            if (name and name:find("Keystone")) or (link and link:find("Keystone")) then
                found = true
                local itemID = GetContainerItemID(bag, slot)
                print(("  bag=%d slot=%d itemID=%s name=%s"):format(bag, slot, tostring(itemID), tostring(name or link)))
            end
        end
    end
    if not found then print("  (no keystone found in bags)") end

    print("|cff00ff00KastaCD Keystone Debug|r -- IsAddOnLoaded(Blizzard_ChallengesUI) = "
        .. tostring(IsAddOnLoaded and IsAddOnLoaded("Blizzard_ChallengesUI")))

    print("|cff00ff00KastaCD Keystone Debug|r -- child buttons of ChallengesKeystoneFrame:")
    local ksFrame = _G.ChallengesKeystoneFrame
    if ksFrame then
        found = false
        for _, child in ipairs({ ksFrame:GetChildren() }) do
            if child.GetObjectType and child:GetObjectType() == "Button" then
                found = true
                print(("  %s size=%.0fx%.0f"):format(
                    tostring(child:GetName()), child:GetWidth(), child:GetHeight()))
            end
        end
        if not found then print("  (no button children found)") end
    else
        print("  (ChallengesKeystoneFrame not found)")
    end
end
