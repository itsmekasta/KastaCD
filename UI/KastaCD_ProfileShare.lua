-- =============================================================
-- KastaCD_ProfileShare.lua
-- "Post to Chat" profile sharing: posts a short chat message ("type
-- /kcdimport <name> to get it", plus a best-effort clickable link)
-- instead of the full export string, which is far too long to fit in a
-- single chat message (WoW caps chat messages at 255 characters). The
-- instant it's posted, the full profile is broadcast as a series of
-- hidden addon messages to that same channel - every KastaCD client
-- listening on it silently caches the data, keyed by the sender's name,
-- so /kcdimport (even after the sender has logged off) imports instantly
-- from that local cache rather than needing to ask the sender live.
--
-- /kcdimport, not the chat hyperlink, is the primary/guaranteed path:
-- some servers strip or mangle |H...|h escape sequences out of chat text
-- before relaying it (anti-exploit sanitization), which silently turns
-- the clickable link into inert plain text with no way for the addon to
-- detect that happened. Plain text always survives, so the link is only
-- ever a nicer bonus for servers where it isn't stripped.
--
-- No channel picker - it posts to whatever chat type the player actually
-- last used (Say, Party, Whisper, etc.), tracked via a SendChatMessage
-- wrap, since there's no reliable way to read "the active channel" at
-- the moment a Settings-panel button is clicked (the chat edit box isn't
-- open/focused then). Say/Yell/Emote can carry the visible message but
-- have no addon-message equivalent, so the profile data itself can't
-- ride along on those specifically - see ResolveAddonChannel below.
--
-- This is purely an ADDITIONAL transport on top of the existing plain
-- Export/Import text boxes in KastaCD_Options.lua (SerializeProfile /
-- DeserializeProfile) - the copy-paste string used outside WoW (Discord,
-- Pastebin, etc.) is completely unchanged.
-- Depends on: KastaCD_DB.lua, KastaCD_Options.lua (SerializeProfile /
--             DeserializeProfile must be global)
-- =============================================================

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

-- -------------------------------------------------------------
-- Sending
-- -------------------------------------------------------------
-- Tracks whichever chat type/target the player actually last sent a real
-- message to (SAY, PARTY, WHISPER + target, etc.) by observing
-- SendChatMessage - this is the only reliable way to know "whatever they
-- have active", since the chat edit box itself isn't open/focused at the
-- moment a Settings-panel button is clicked. Defaults to SAY, matching
-- the game's own default chat type before anything's ever been sent.
--
-- Deliberately hooksecurefunc, not a reassignment of the global -
-- overwriting SendChatMessage outright would replace it for every future
-- caller, including chat commands issued from secure macros.
local lastChatType, lastChatTarget = "SAY", nil
hooksecurefunc("SendChatMessage", function(msg, chatType, language, target)
    lastChatType   = chatType or "SAY"
    lastChatTarget = target
end)

-- Not every chat type has an addon-message equivalent: SAY/YELL/EMOTE are
-- position-based broadcasts to whoever's nearby, which has no defined
-- "recipient set" SendAddonMessage could target. PARTY/RAID/INSTANCE_CHAT/
-- GUILD/OFFICER/WHISPER/CHANNEL all map straight across.
--
-- For anything unmapped (Say/Yell/Emote), fall back to whatever group
-- channel is actually available instead of just giving up - the visible
-- link still goes out over the original channel, but the data itself
-- rides along on Raid/Party/Guild so people there can still import it.
-- Returns a third value (isFallback=true) when this happened, so the
-- caller can word its confirmation message accordingly.
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

-- Broadcasts the given profile's serialized data as chunked addon
-- messages to whatever channel the player last actually chatted in, then
-- posts the short clickable link to that same channel/target. Returns
-- true on success (with a warning string if the channel can't carry the
-- actual data, e.g. Say/Yell), or false + an error string on failure.
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
        -- transferId: cheap per-send uniqueness so two posts in quick
        -- succession from the same player don't get their chunks mixed up.
        local transferId = tostring(math.random(100000, 999999))
        SendAddonMessage(ADDON_PREFIX, "H:" .. transferId .. ":" .. total, addonChannel, addonTarget)
        for i = 1, total do
            local chunk = data:sub((i - 1) * CHUNK_SIZE + 1, i * CHUNK_SIZE)
            SendAddonMessage(ADDON_PREFIX, "D:" .. transferId .. ":" .. i .. ":" .. chunk, addonChannel, addonTarget)
        end
    end

    -- The clickable hyperlink is included as a best-effort bonus, but the
    -- /kcdimport slash command is the message's real, guaranteed-to-work
    -- payload - some servers strip/mangle |H...|h escape sequences out of
    -- chat text before relaying it (anti-exploit sanitization), which
    -- silently turns the link into inert plain text with no way to know
    -- from the addon side whether that happened. Plain text always
    -- survives, so it's the primary instruction, not a fallback footnote.
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
    -- isFallback (e.g. Say/Yell with a group/guild to fall back to) used
    -- to also print "Posted to X - X can't carry the profile data itself,
    -- so it was also sent via Y..." here - dropped per request, since the
    -- addon data silently rides along on the fallback channel regardless
    -- and didn't need its own extra confirmation line.
    return true
end

-- -------------------------------------------------------------
-- Receiving
-- -------------------------------------------------------------
local function HandleAddonMessage(prefix, message, _, sender)
    if prefix ~= ADDON_PREFIX then return end
    -- Strip realm suffix ("Kasta-RealmName") to match UnitName("player")'s
    -- unqualified form, so a link clicked by someone on the same realm
    -- resolves against the cache key we actually stored it under.
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
            -- Addon messages never show up in the chat window (that's the
            -- entire point - only the short link is meant to be visible),
            -- so without this print there's otherwise no confirmation a
            -- transfer actually completed. Note this only ever fires on
            -- OTHER players' clients, never your own - you don't receive
            -- an echo of your own SendAddonMessage broadcast, so testing
            -- solo on one character will never show this.
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

-- -------------------------------------------------------------
-- Click handling
-- -------------------------------------------------------------
-- Imports whatever profile data was broadcast by senderName, naming the
-- new profile after them (deduped with a numeric suffix, same pattern
-- the plain-paste import box already uses for "Imported"/"Imported 2").
function ImportProfileFromChatShare(senderName)
    local entry = receivedProfiles[senderName]
    if not entry then
        -- Debug aid: list whatever names ARE cached, so a mismatch (case,
        -- stray whitespace, realm suffix, etc.) is visible immediately
        -- instead of just "nothing happened".
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

-- Intercepts clicks on our custom "kastacd:<name>" chat links. This is
-- the standard pattern for handling non-Blizzard link types - SetItemRef
-- isn't a protected function, so wrapping it is safe. Any link we don't
-- recognize is passed straight through to the original.
local origSetItemRef = SetItemRef
SetItemRef = function(link, text, button, chatFrame)
    -- Debug aid: shows exactly what raw link data made it through the
    -- click, in case chat filtering/sanitization on this server ever
    -- mangles the |H...|h payload in transit - if this print never
    -- appears at all when clicking a KastaCD link, the click isn't
    -- reaching this hook in the first place.
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

-- -------------------------------------------------------------
-- /kcdimport [name] - guaranteed-to-work alternative to clicking the
-- chat link, since some servers strip |H...|h hyperlink escape
-- sequences out of chat text before relaying it, silently turning the
-- link into plain inert text with no way for the addon to detect that
-- happened. Plain text always survives, so this is the reliable path;
-- the chat link is just a nicer bonus for servers where it works.
-- No argument = import whoever's data arrived most recently.
-- -------------------------------------------------------------
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
