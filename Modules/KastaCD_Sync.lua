-- =============================================================
-- KastaCD_Sync.lua
--
-- Fixes the "ability doesn't show until they actually use it" problem
-- for talent-gated spells (isTalent=true in SPELL_DB/CC_SPELLS) and for
-- spec-gated baseline spells when spec never resolves. Both are
-- documented in KastaCD_DB.lua as depending on Blizzard's inspect API
-- (NotifyInspect/GetInspectSpecialization/GetTalentInfo), which
-- routinely never resolves on private servers - when it doesn't, a
-- talent-gated spell is only ever shown once witnessed via a real
-- combat-log cast (by design, to avoid guessing wrong).
--
-- Researched OmniCD and ExRT for how they solve this. ExRT uses the same
-- inspect-queue approach KastaCD already has - nothing more robust to
-- adopt there. OmniCD's actual fix (its retail talent/covenant/soulbind
-- scraping itself doesn't apply to Legion) is peer-to-peer sync: every
-- OmniCD user broadcasts their own confirmed spec+talent data to the
-- party via addon message, so any two OmniCD users get instant, 100%
-- reliable data from each other without ever touching inspect. This file
-- adapts that same concept, reusing the chunked SendAddonMessage/
-- CHAT_MSG_ADDON plumbing pattern already established in
-- KastaCD_ProfileShare.lua (own prefix here, kept separate from profile
-- sharing's "KASTACD" prefix so the two features can't interfere).
--
-- Payload is small (a spec ID + a handful of spell IDs per class) so it
-- always fits in one addon message - no chunking needed, unlike profile
-- sharing's much larger export strings.
--
-- Depends on: KastaCD_DB.lua (IsSpellKnownForUnit, UNIT_SPEC_CACHE,
-- KNOWN_UNIT_SPELLS), KastaCD_SpellDB.lua (SPELL_DB), KastaCD_CC.lua
-- (CC_SPELLS), KastaCD_Tracking.lua/Interrupts.lua/CC.lua (Rebuild*).
-- =============================================================

local SYNC_PREFIX = "KASTACDCD"
local BROADCAST_INTERVAL = 8    -- periodic self-heal re-broadcast, seconds
local BROADCAST_DEBOUNCE = 2    -- min gap between event-triggered broadcasts
local TALENT_SETTLE_DELAY = 1.5 -- wait this long after a talent/spec-change
                                 -- event before reading state - some clients
                                 -- fire these events slightly before their
                                 -- own internal spellbook/spec state has
                                 -- actually finished updating, which was
                                 -- silently broadcasting the OLD build.

if RegisterAddonMessagePrefix then
    RegisterAddonMessagePrefix(SYNC_PREFIX)
end

-- Toggleable via /kcdsyncdebug - prints every send/receive so sync
-- behavior (or lack of it) can be watched live instead of guessed at.
local debugPrints = false

-- -------------------------------------------------------------
-- Sending
-- -------------------------------------------------------------
-- Direct IsPlayerSpell/IsSpellKnown check, independent of which table a
-- spell ID lives in - IsSpellKnownForUnit("player", sid) looks ONLY at
-- SPELL_DB internally (`local data = SPELL_DB[spellId]`), so calling it
-- for a CC_SPELLS-only entry (e.g. Shockwave, which never appears in
-- SPELL_DB) always returned false regardless of whether the player
-- actually has it - only spells dual-listed in both tables (like Storm
-- Bolt) ever synced correctly. This mirrors the exact check
-- IsSpellKnownForUnit's own player branch does internally, just without
-- requiring a SPELL_DB lookup to succeed first.
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
-- matching the player's own class that PlayerKnowsSpellID confirms true -
-- 100% reliable for your own character, no inspect or GetSpecialization()
-- dependency involved.
--
-- specId itself is best-effort only, sent as 0 when unresolved rather
-- than blocking the whole payload - confirmed spell IDs are useful on
-- their own via KNOWN_UNIT_SPELLS ground truth regardless of whether
-- specId ever resolves (see IsSpellKnownForUnit's non-player branch,
-- which checks KNOWN_UNIT_SPELLS before ever looking at spec). The old
-- version required specId to resolve before sending ANYTHING, which on
-- a server where GetSpecialization() doesn't reliably resolve even for
-- your own character meant this player could never broadcast at all.
--
-- Deduped via a set (ids[sid]=true) rather than a plain array, since a
-- spell can appear in BOTH SPELL_DB and CC_SPELLS (e.g. Storm Bolt) -
-- appending from both loops into a plain array sent it twice.
local function BuildSyncPayload()
    local _, classToken = UnitClass("player")
    if not classToken then return nil end

    -- Refresh KNOWN_UNIT_SPELLS[playerGUID] via GetTalentInfo (own read,
    -- isInspect=false) before scanning - authoritative for isTalent
    -- entries specifically, since GetTalentInfo reads the talent frame's
    -- actual current selection and structurally can't report two picks
    -- for the same row, unlike IsPlayerSpell/IsSpellKnown which live
    -- testing showed can still report an old competing pick (e.g.
    -- Shockwave AND Storm Bolt both "known") for a stretch after
    -- respeccing. See ScanUnitTalents in KastaCD_DB.lua.
    local playerGUID = UnitGUID and UnitGUID("player")
    if type(ScanUnitTalents) == "function" then
        ScanUnitTalents("player")
    end
    local playerKnownTalents = playerGUID and KNOWN_UNIT_SPELLS and KNOWN_UNIT_SPELLS[playerGUID]

    -- inferredSpecIds: whenever a currently-known spell is exclusively
    -- tied to exactly one spec (data.specs has one entry), that's a
    -- candidate spec inference - trusted over GetSpecialization()/
    -- GetSpecializationInfo() (confirmed via live testing that those can
    -- report a STALE spec, not just nil/0, on this server). Collects
    -- EVERY distinct candidate rather than trusting whichever is found
    -- first (pairs() iteration order is unspecified) - if a stale,
    -- not-yet-cleared entry from a different spec is also present (e.g.
    -- ScanUnitTalents hadn't caught up removing an old talent pick yet),
    -- blindly picking "the first one" could just as easily lock onto the
    -- WRONG spec as the right one. Only trusted when every candidate
    -- agrees; a disagreement means something here is stale and it's
    -- safer to fall back to GetSpecialization() than confidently guess
    -- wrong.
    local idSet = {}
    local specCandidates = {}
    local function scan(tbl)
        if type(tbl) ~= "table" then return end
        for sid, data in pairs(tbl) do
            if data.class == classToken then
                -- isTalent entries: trust the GetTalentInfo-backed cache
                -- just refreshed above over IsPlayerSpell/IsSpellKnown -
                -- see the comment at the top of this function.
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

-- -------------------------------------------------------------
-- Receiving
-- -------------------------------------------------------------
-- Resolves an addon-message sender name to a currently-valid unit token
-- (player/party1-4), the same realm-suffix-stripping approach used in
-- KastaCD_ProfileShare.lua's HandleAddonMessage.
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

    -- specId 0 means the sender's own GetSpecialization() hadn't resolved
    -- at broadcast time (see BuildSyncPayload) - leave UNIT_SPEC_CACHE
    -- alone rather than overwriting a possibly-good cached value with a
    -- bogus 0 (which is truthy in Lua and would otherwise start failing
    -- SpellMatchesSpec checks that were working fine before).
    if specId and specId > 0 then
        UNIT_SPEC_CACHE[guid] = specId
    end

    KNOWN_UNIT_SPELLS[guid] = KNOWN_UNIT_SPELLS[guid] or {}
    local known = KNOWN_UNIT_SPELLS[guid]

    -- Each payload is the sender's complete, current SPELL_DB/CC_SPELLS
    -- known-spell set (see BuildSyncPayload) - clear any previously-synced
    -- entry from those two tables before applying the new one, otherwise
    -- a talent they've since swapped away from stays marked "known"
    -- forever (only ever added to, never removed). Leaves any other
    -- GUID-keyed entry untouched (e.g. from a witnessed cast of something
    -- outside these two tables, though nothing currently writes those).
    for sid in pairs(known) do
        if (type(SPELL_DB) == "table" and SPELL_DB[sid]) or (type(CC_SPELLS) == "table" and CC_SPELLS[sid]) then
            known[sid] = nil
        end
    end
    for idStr in idList:gmatch("(%d+),?") do
        local id = tonumber(idStr)
        if id then known[id] = true end
    end

    -- Same immediate-rebuild treatment as an INSPECT_READY resolution
    -- (see KastaCD_Events.lua) - no reason to wait for the next poll tick
    -- once we have ground-truth data in hand.
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

-- Periodic self-heal re-broadcast while grouped - covers anyone who
-- joined after your last broadcast, or whose own client wasn't
-- listening yet when you sent it, or an event-triggered broadcast that
-- silently failed to fire for whatever reason. Same "cheap and frequent
-- beats validated-once" philosophy as SpecPollTicker in KastaCD_Events.lua.
C_Timer.NewTicker(BROADCAST_INTERVAL, function()
    if HasGroup and HasGroup() then
        BroadcastAbilitySync()
    end
end)

-- -------------------------------------------------------------
-- /kcdsyncdebug - toggles the print output above so send/receive activity
-- can be watched live in chat. Also immediately force-broadcasts once so
-- you can confirm sending works without waiting for the next trigger.
-- -------------------------------------------------------------
SLASH_KASTACDSYNCDEBUG1 = "/kcdsyncdebug"
SlashCmdList["KASTACDSYNCDEBUG"] = function()
    debugPrints = not debugPrints
    print("|cff71d5ffKastaCD Sync:|r debug prints " .. (debugPrints and "ON" or "OFF"))
    if debugPrints then
        BroadcastAbilitySync(true)
    end
end
