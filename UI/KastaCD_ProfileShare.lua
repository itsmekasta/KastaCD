-- KastaCD_ProfileShare.lua - "Post to Chat" profile sharing: posts a
-- short chat message with a /kcdimport instruction and a best-effort
-- clickable link, since the full export string is too long for one chat
-- message. The full profile is broadcast as chunked addon messages
-- alongside it, cached locally by every listening KastaCD client so
-- /kcdimport works even after the sender logs off.
-- /kcdimport is the guaranteed path - some servers strip |H...|h escape
-- sequences, silently turning the link into inert text.
-- No channel picker - posts to whatever chat type was last used
-- (tracked via a SendChatMessage hook). Say/Yell/Emote have no
-- addon-message equivalent, so they fall back to a group/guild channel
-- for the data itself (see ResolveAddonChannel).
-- Purely additional to the existing plain Export/Import text boxes in
-- KastaCD_Options.lua - that copy-paste flow is unchanged.
-- Depends on: KastaCD_DB.lua, KastaCD_Options.lua (SerializeProfile /
--             DeserializeProfile must be global)

local ADDON_PREFIX = "KASTACD"
local CHUNK_SIZE    = 200   -- chars per addon message, safely under the ~255 limit
local MAX_CHUNKS     = 50   -- sanity cap (~10KB) - real profiles are far smaller

-- [senderName] = { data = "<reassembled string>", receivedAt = time }
-- Only the most recent completed transfer per sender is kept.
local receivedProfiles = {}
local lastReceivedSender = nil -- for /kcdimport with no argument

-- In-progress reassembly: [senderName][transferId] = { total, have, parts={} }
local pendingTransfers = {}

if RegisterAddonMessagePrefix then
    RegisterAddonMessagePrefix(ADDON_PREFIX)
end

-- Sending

-- Tracks the last chat type/target the player actually sent to, since
-- the chat edit box isn't open/focused when a Settings button is clicked.
-- hooksecurefunc, not a reassignment, so secure-macro callers still work.
local lastChatType, lastChatTarget = "SAY", nil
hooksecurefunc("SendChatMessage", function(msg, chatType, language, target)
    lastChatType   = chatType or "SAY"
    lastChatTarget = target
end)

-- SAY/YELL/EMOTE have no addon-message equivalent (no defined recipient
-- set); the rest map straight across. Unmapped types fall back to
-- whatever group channel is available so the data still rides along.
local function ResolveAddonChannel(chatType, target)
    if chatType == "PARTY" or chatType == "RAID" or chatType == "INSTANCE_CHAT"
    or chatType == "GUILD" or chatType == "OFFICER" then
        return chatType
    end
    if chatType == "WHISPER" and target then return "WHISPER", target end
    if chatType == "CHANNEL"  and target then return "CHANNEL",  target end

    if IsInRaid and IsInRaid() then return "RAID", nil, true end
    if IsInGroup and IsInGroup() then return "PARTY", nil, true end
    if IsInGuild and IsInGuild() then return "GUILD", nil, true end
    return nil
end

-- Broadcasts the profile as chunked addon messages, then posts the
-- short clickable link. Returns true on success (with a warning if the
-- channel can't carry the data), or false + error string on failure.
function BroadcastProfileToChat(profile)
    if type(profile) ~= "table" then return false, "No profile data." end
    if type(SerializeProfile) ~= "function" then return false, "Export unavailable." end
    if not SendAddonMessage then return false, "This client doesn't support addon messages." end

    local chatType, target = lastChatType, lastChatTarget
    local addonChannel, addonTarget = ResolveAddonChannel(chatType, target)

    local data = SerializeProfile(profile)
    local total = math.ceil(#data / CHUNK_SIZE)
    if total > MAX_CHUNKS then
        return false, "Profile is too large to share this way."
    end

    if addonChannel then
        -- transferId: cheap uniqueness so quick successive posts don't mix chunks.
        local transferId = tostring(math.random(100000, 999999))
        SendAddonMessage(ADDON_PREFIX, "H:" .. transferId .. ":" .. total, addonChannel, addonTarget)
        for i = 1, total do
            local chunk = data:sub((i - 1) * CHUNK_SIZE + 1, i * CHUNK_SIZE)
            SendAddonMessage(ADDON_PREFIX, "D:" .. transferId .. ":" .. i .. ":" .. chunk, addonChannel, addonTarget)
        end
    end

    -- /kcdimport is the guaranteed payload; the link is a best-effort bonus
    -- since some servers strip |H...|h escape sequences from chat text.
    local playerName = UnitName("player")
    local link = string.format(
        "|cff71d5ff|Hkastacd:%s|h[Click to Import]|h|r", playerName)
    local msg = string.format(
        "KastaCD profile shared - type /kcdimport %s to get it (or %s)", playerName, link)
    local ok = pcall(SendChatMessage, msg, chatType, nil, target)
    if not ok then
        return false, "Couldn't post to " .. tostring(chatType) .. " - try chatting there first so KastaCD knows it's valid."
    end

    if not addonChannel then
        return true, tostring(chatType) .. " can't carry the profile data itself, and you're not in a " ..
            "group or guild to fall back to - clicking the link won't import anything unless you " ..
            "share the profile another way too."
    end
    return true
end

-- Receiving

local function HandleAddonMessage(prefix, message, _, sender)
    if prefix ~= ADDON_PREFIX then return end
    -- Strip realm suffix to match UnitName("player")'s unqualified form.
    local senderShort = sender and sender:match("^([^-]+)") or sender

    local kind, transferId, rest = message:match("^(%a):([^:]+):?(.*)$")
    if kind == "H" then
        local total = tonumber(rest)
        if not total or total < 1 or total > MAX_CHUNKS then return end
        pendingTransfers[senderShort] = pendingTransfers[senderShort] or {}
        pendingTransfers[senderShort][transferId] = { total = total, have = 0, parts = {} }
    elseif kind == "D" then
        local index, chunk = rest:match("^(%d+):(.*)$")
        index = tonumber(index)
        local byTransfer = pendingTransfers[senderShort]
        local t = byTransfer and byTransfer[transferId]
        if not t or not index or t.parts[index] then return end
        t.parts[index] = chunk or ""
        t.have = t.have + 1
        if t.have >= t.total then
            local full = table.concat(t.parts, "", 1, t.total)
            receivedProfiles[senderShort] = { data = full, receivedAt = GetTime() }
            lastReceivedSender = senderShort
            byTransfer[transferId] = nil
            -- Addon messages never show in chat, so print a confirmation.
            -- Only fires on other players' clients - no self-echo.
            print("|cff71d5ffKastaCD:|r Received " .. tostring(senderShort) ..
                "'s shared profile - type |cffffd200/kcdimport|r to import it (or |cffffd200/kcdimport " ..
                tostring(senderShort) .. "|r if you've received more than one).")
        end
    end
end

local shareFrame = CreateFrame("Frame")
shareFrame:RegisterEvent("CHAT_MSG_ADDON")
shareFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then HandleAddonMessage(...) end
end)

-- Click handling

-- Imports the profile data broadcast by senderName, naming the new
-- profile after them (deduped with a numeric suffix).
function ImportProfileFromChatShare(senderName)
    local entry = receivedProfiles[senderName]
    if not entry then
        -- Debug aid: list cached names so a mismatch is visible immediately.
        local known = {}
        for k in pairs(receivedProfiles) do table.insert(known, "[" .. k .. "]") end
        print("|cffff0000KastaCD:|r No profile data received from [" .. tostring(senderName) .. "]" ..
            (next(known) and (" - have data cached from: " .. table.concat(known, ", "))
                or " - nothing cached from anyone yet") ..
            ". They need to post it again while you're in the same group/guild.")
        return
    end

    local p, err = DeserializeProfile(entry.data)
    if not p then
        print("|cffff0000KastaCD:|r Import from " .. tostring(senderName) .. " failed — " .. tostring(err))
        return
    end

    local nm = senderName
    local n  = 1
    while KastaCDDB.profiles[nm] do n = n + 1; nm = senderName .. " " .. n end

    if type(PersistActiveProfile) == "function" then PersistActiveProfile() end
    KastaCDDB.profiles[nm] = p
    KastaCDDB.activeProfile = nm
    if type(ApplyActiveProfile) == "function" then ApplyActiveProfile() end
    if type(RebuildIcons) == "function" then RebuildIcons() end
    if type(RebuildInterruptBars) == "function" then RebuildInterruptBars() end
    if type(RebuildCCBars) == "function" then RebuildCCBars() end
    if LibStub then
        local reg = LibStub("AceConfigRegistry-3.0", true)
        if reg then reg:NotifyChange("KastaCD") end
    end
    print("|cff44ff44KastaCD:|r Imported " .. senderName .. "'s profile as '" .. nm .. "'.")
end

-- Intercepts clicks on our custom "kastacd:<name>" chat links.
-- Unrecognized links pass straight through to the original.
local origSetItemRef = SetItemRef
SetItemRef = function(link, text, button, chatFrame)
    -- Debug aid: shows the raw link data that made it through the click.
    if link:find("kastacd", 1, true) then
        print("|cff71d5ffKastaCD debug:|r clicked link = [" .. tostring(link) .. "]")
    end
    local senderName = link:match("^kastacd:(.+)$")
    if senderName then
        ImportProfileFromChatShare(senderName)
        return
    end
    origSetItemRef(link, text, button, chatFrame)
end

-- /kcdimport [name] - reliable alternative to clicking the chat link
-- (some servers strip |H...|h escape sequences). No argument = most recent.
SLASH_KASTACDIMPORT1 = "/kcdimport"
SlashCmdList["KASTACDIMPORT"] = function(msg)
    local name = msg and msg:match("^%s*(.-)%s*$")
    if not name or name == "" then
        name = lastReceivedSender
        if not name then
            print("|cffff0000KastaCD:|r No shared profile received yet - " ..
                "ask someone to post one first, or use /kcdimport <name>.")
            return
        end
    end
    ImportProfileFromChatShare(name)
end
