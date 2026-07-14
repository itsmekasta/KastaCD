-- KastaCD_Sync.lua - fixes "ability doesn't show until cast" for
-- talent-gated/spec-gated spells when inspect never resolves, by having
-- party members broadcast their own confirmed spec+talent data via
-- addon message (like OmniCD's peer-to-peer sync). Reuses the
-- SendAddonMessage/CHAT_MSG_ADDON plumbing from KastaCD_ProfileShare.lua,
-- own prefix so the two features don't interfere.
-- Depends on: KastaCD_DB.lua, KastaCD_SpellDB.lua, KastaCD_CC.lua,
-- KastaCD_Tracking.lua/Interrupts.lua/CC.lua (Rebuild*).

local SYNC_PREFIX = "KASTACDCD"
local BROADCAST_INTERVAL = 8    -- periodic self-heal re-broadcast, seconds
local BROADCAST_DEBOUNCE = 2    -- min gap between event-triggered broadcasts
local TALENT_SETTLE_DELAY = 1.5 -- delay after talent/spec change before
                                 -- reading state (some clients fire the
                                 -- event before state finishes updating)

if RegisterAddonMessagePrefix then
    RegisterAddonMessagePrefix(SYNC_PREFIX)
end

-- Toggleable via /kcdsyncdebug - prints every send/receive so sync
-- behavior (or lack of it) can be watched live instead of guessed at.
local debugPrints = false

-- Sending

-- Direct IsPlayerSpell/IsSpellKnown check, independent of which table
-- (SPELL_DB/CC_SPELLS) a spell ID lives in - IsSpellKnownForUnit only
-- checks SPELL_DB internally, so a CC_SPELLS-only entry always failed.
local function PlayerKnowsSpellID(spellId)
    local checkId = spellId
    if FindSpellOverrideByID then
        local ov = FindSpellOverrideByID(spellId)
        if ov and ov ~= 0 then checkId = ov end
    end
    return (IsPlayerSpell and (IsPlayerSpell(checkId) or IsPlayerSpell(spellId)))
        or (IsSpellKnown and (IsSpellKnown(checkId) or IsSpellKnown(spellId)))
        or false
end

-- Builds "S:<specId>:<id1>,<id2>,..." from every SPELL_DB/CC_SPELLS entry
-- matching the player's class that PlayerKnowsSpellID confirms true.
-- specId is best-effort, sent as 0 when unresolved rather than blocking
-- the whole payload. Deduped via a set since a spell can appear in both
-- SPELL_DB and CC_SPELLS (e.g. Storm Bolt).
local function BuildSyncPayload()
    local _, classToken = UnitClass("player")
    if not classToken then return nil end

    -- Refresh KNOWN_UNIT_SPELLS[playerGUID] via GetTalentInfo before
    -- scanning - authoritative for isTalent entries. See ScanUnitTalents
    -- in KastaCD_DB.lua.
    local playerGUID = UnitGUID and UnitGUID("player")
    if type(ScanUnitTalents) == "function" then
        ScanUnitTalents("player")
    end
    local playerKnownTalents = playerGUID and KNOWN_UNIT_SPELLS and KNOWN_UNIT_SPELLS[playerGUID]

    -- inferredSpecIds: a known spell exclusively tied to one spec is a
    -- candidate spec inference, trusted over GetSpecialization() (which
    -- can report a stale spec on this server). Only trusted when every
    -- candidate agrees; a disagreement falls back to GetSpecialization().
    local idSet = {}
    local specCandidates = {}
    local function scan(tbl)
        if type(tbl) ~= "table" then return end
        for sid, data in pairs(tbl) do
            if data.class == classToken then
                -- isTalent entries trust the GetTalentInfo-backed cache
                -- refreshed above over IsPlayerSpell/IsSpellKnown.
                local known
                if data.isTalent then
                    known = playerKnownTalents and playerKnownTalents[sid] == true
                else
                    known = PlayerKnowsSpellID(sid)
                end
                if known then
                    idSet[sid] = true
                    if data.specs and #data.specs == 1 then
                        specCandidates[data.specs[1]] = true
                    end
                end
            end
        end
    end
    scan(SPELL_DB)
    scan(CC_SPELLS)

    local ids = {}
    for sid in pairs(idSet) do ids[#ids + 1] = sid end
    if #ids == 0 then
        if debugPrints then print("|cff71d5ffKastaCD Sync:|r BuildSyncPayload -> nil (0 known ids)") end
        return nil
    end

    local specId = nil
    for candidate in pairs(specCandidates) do
        if specId then specId = false; break end   -- more than one distinct candidate - ambiguous
        specId = candidate
    end
    if not specId then
        local specIndex = GetSpecialization and GetSpecialization()
        specId = (specIndex and GetSpecializationInfo(specIndex)) or 0
    end

    return "S:" .. specId .. ":" .. table.concat(ids, ",")
end

local function GetGroupChannel()
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    return nil
end

local lastBroadcast = 0
function BroadcastAbilitySync(force)
    if not SendAddonMessage then return end
    local channel = GetGroupChannel()
    if not channel then
        if debugPrints then print("|cff71d5ffKastaCD Sync:|r skip send - not in a group") end
        return
    end

    local now = GetTime()
    if not force and (now - lastBroadcast) < BROADCAST_DEBOUNCE then
        if debugPrints then print("|cff71d5ffKastaCD Sync:|r skip send - debounced") end
        return
    end

    local payload = BuildSyncPayload()
    if not payload then return end

    lastBroadcast = now
    SendAddonMessage(SYNC_PREFIX, payload, channel)
    if debugPrints then print("|cff71d5ffKastaCD Sync:|r sent to " .. channel .. ": " .. payload) end
end

-- Waits for the client's own talent/spec state to actually finish
-- updating before reading it - see TALENT_SETTLE_DELAY above.
local settleTimer
local function BroadcastAfterSettle()
    if settleTimer then settleTimer:Cancel() end
    settleTimer = C_Timer.NewTimer(TALENT_SETTLE_DELAY, function()
        settleTimer = nil
        BroadcastAbilitySync(true)
    end)
end

-- Receiving

-- Resolves a sender name to a unit token (player/party1-4).
local function ResolveSenderUnit(sender)
    local short = sender and sender:match("^([^-]+)") or sender
    if not short then return nil end
    if UnitName("player") == short then return "player" end
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) and UnitName(u) == short then return u end
    end
    return nil
end

local function HandleSyncMessage(prefix, message, _, sender)
    if prefix ~= SYNC_PREFIX then return end

    local specId, idList = message:match("^S:(%d+):(.*)$")
    if not specId then return end
    specId = tonumber(specId)

    if debugPrints then
        print("|cff71d5ffKastaCD Sync:|r received from " .. tostring(sender) ..
            ": spec=" .. tostring(specId) .. " ids=" .. tostring(idList))
    end

    local unit = ResolveSenderUnit(sender)
    if not unit or unit == "player" then
        if debugPrints then print("|cff71d5ffKastaCD Sync:|r  -> ignored (unresolved sender or self)") end
        return
    end
    local guid = UnitGUID(unit)
    if not guid then return end

    -- specId 0 means unresolved at broadcast time - don't overwrite a
    -- possibly-good cached value with it.
    if specId and specId > 0 then
        UNIT_SPEC_CACHE[guid] = specId
    end

    KNOWN_UNIT_SPELLS[guid] = KNOWN_UNIT_SPELLS[guid] or {}
    local known = KNOWN_UNIT_SPELLS[guid]

    -- Each payload is the sender's complete known-spell set - clear any
    -- previously-synced entry before applying, so a swapped-away talent
    -- doesn't stay marked "known" forever.
    for sid in pairs(known) do
        if (type(SPELL_DB) == "table" and SPELL_DB[sid]) or (type(CC_SPELLS) == "table" and CC_SPELLS[sid]) then
            known[sid] = nil
        end
    end
    for idStr in idList:gmatch("(%d+),?") do
        local id = tonumber(idStr)
        if id then known[id] = true end
    end

    -- Immediate rebuild, same as an INSPECT_READY resolution.
    if type(RebuildIcons) == "function" then RebuildIcons() end
    if type(RebuildInterruptBars) == "function" then RebuildInterruptBars() end
    if type(RebuildCCBars) == "function" then RebuildCCBars() end
end

local syncFrame = CreateFrame("Frame")
syncFrame:RegisterEvent("CHAT_MSG_ADDON")
syncFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
syncFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
syncFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
syncFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
syncFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
syncFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        HandleSyncMessage(...)
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_TALENT_UPDATE"
        or event == "CHARACTER_POINTS_CHANGED" then
        if debugPrints then print("|cff71d5ffKastaCD Sync:|r " .. event .. " fired, broadcasting after settle delay") end
        BroadcastAfterSettle()
    else
        BroadcastAbilitySync()
    end
end)

-- Periodic self-heal re-broadcast while grouped, covers anyone who
-- joined late or missed the last broadcast.
C_Timer.NewTicker(BROADCAST_INTERVAL, function()
    if HasGroup and HasGroup() then
        BroadcastAbilitySync()
    end
end)

-- /kcdsyncdebug - toggles print output and force-broadcasts once.
SLASH_KASTACDSYNCDEBUG1 = "/kcdsyncdebug"
SlashCmdList["KASTACDSYNCDEBUG"] = function()
    debugPrints = not debugPrints
    print("|cff71d5ffKastaCD Sync:|r debug prints " .. (debugPrints and "ON" or "OFF"))
    if debugPrints then
        BroadcastAbilitySync(true)
    end
end
