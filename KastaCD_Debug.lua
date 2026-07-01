-- =============================================================
-- KastaCD_Debug.lua
-- Developer slash commands for inspecting addon state.
-- Loaded last — depends on everything else.
--
--   /kcddebug   – dump icon containers, tracker state, profile info
--   /kcdlevel   – check level-gate visibility for all group members
--                 /kcdlevel 871  (filter to one spellID)
-- =============================================================

-- -------------------------------------------------------------
-- /kcddebug
-- -------------------------------------------------------------
SLASH_KASTACDDEBUG1 = "/kcddebug"
SlashCmdList["KASTACDDEBUG"] = function()
    local cc, tc, ec, dbc = 0, 0, 0, 0
    for _ in pairs(iconContainers)                        do cc  = cc  + 1 end
    for _ in pairs(trackerState)                          do tc  = tc  + 1 end
    for _ in pairs(KastaCDDB and KastaCDDB.enabled or {}) do ec  = ec  + 1 end
    for _ in pairs(SPELL_DB or {})                        do dbc = dbc + 1 end

    print("KastaCD debug:")
    print("  profile :", KastaCDDB and KastaCDDB.activeProfile)
    print("  SPELL_DB entries:", dbc, "  enabled:", ec,
          "  content:", GetCurrentContentType(),
          "  active:", tostring(IsContentEnabled()))
    print("  containers:", cc, "  tracker units:", tc)
    print("  anchorsLocked:", tostring(KastaCDDB and KastaCDDB.anchorsLocked))

    for u, g in pairs(memberGUIDs) do
        print("  ", u, "=", g)
    end

    for i = 1, 40 do
        local f = _G["CompactRaidFrame" .. i]
        if not f then break end
        local unit = f.unit or f.displayedUnit
        local _, cls = unit and UnitExists(unit) and UnitClass(unit) or nil, nil
        print(string.format("  RF[%d] unit=%s cls=%s shown=%s",
            i, tostring(unit), tostring(cls), tostring(f:IsShown())))
        local il = unit and iconContainers[unit]
        if il and il.icons and #il.icons > 0 then
            local p, _, _, x, y = il.container and il.container:GetPoint(1)
            print(string.format("    %d icons  container at %s %.0f %.0f",
                #il.icons, tostring(p), x or 0, y or 0))
        end
    end
end

-- -------------------------------------------------------------
-- /kcdelvui  –  deep ElvUI frame diagnostic
-- Run this in a party and paste the full output.
-- -------------------------------------------------------------
SLASH_KASTACDELVUI1 = "/kcdelvui"
SlashCmdList["KASTACDELVUI"] = function()
    print("=== KastaCD ElvUI Diagnostic ===")

    -- 1. Is ElvUI present?
    print("ElvUI global:", tostring(_G.ElvUI ~= nil))

    -- 2. Scan _G for any ElvUF_ frames
    local elvFrames = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and k:find("^ElvUF_") and type(v) == "table" and v.IsShown then
            local unit = v.unit or v.displayedUnit
            table.insert(elvFrames, string.format("  %s  shown=%s  unit=%s  exists=%s",
                k, tostring(v:IsShown()), tostring(unit), tostring(unit and UnitExists(unit) or false)))
        end
    end
    table.sort(elvFrames)
    print("ElvUF_ globals found:", #elvFrames)
    for _, s in ipairs(elvFrames) do print(s) end

    -- 3. Direct unit token scan
    print("Direct party unit scan:")
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) then
            print(string.format("  unit=%s  guid=%s", unit, tostring(UnitGUID(unit))))
        end
    end

    -- 4. memberGUIDs table
    print("memberGUIDs:")
    for u, g in pairs(memberGUIDs) do
        print("  ", u, "=", g)
    end

    -- 5. iconContainers
    print("iconContainers:", (function() local n=0; for _ in pairs(iconContainers) do n=n+1 end; return n end)())
    for k in pairs(iconContainers) do print("  ", k) end

    -- 6. Enabled spell count
    local ec = 0
    for _ in pairs(KastaCDDB and KastaCDDB.enabled or {}) do ec = ec + 1 end
    print("Enabled spells:", ec)

    -- 7. Content enabled?
    print("IsContentEnabled:", tostring(IsContentEnabled()))

    print("=== end ===")
end

-- -------------------------------------------------------------
-- /kcdlevel [spellID]
-- -------------------------------------------------------------
SLASH_KASTACDLEVEL1 = "/kcdlevel"
SlashCmdList["KASTACDLEVEL"] = function(msg)
    local filterSid = tonumber(msg)
    if filterSid and not SPELL_DB[filterSid] then
        print("KastaCD: spellID " .. filterSid .. " not in DB.")
        return
    end

    local units = { "player" }
    for i = 1, 40 do
        local u = "party" .. i
        if UnitExists(u) then table.insert(units, u) end
    end

    print("KastaCD level-gate check:")
    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            local name      = UnitName(unit) or unit
            local lvl       = UnitLevel(unit)
            local _, cls    = UnitClass(unit)
            print(string.format("  %s (%s lvl %s):", name, tostring(cls), tostring(lvl)))
            for sid, data in pairs(SPELL_DB) do
                if data.class == cls and (not filterSid or sid == filterSid) then
                    local known = IsSpellKnownForUnit(unit, sid)
                    print(string.format("    [%d] %s  minLvl=%s  -> %s",
                        sid, data.name, tostring(data.minLevel),
                        known and "|cff44ff44SHOWN|r" or "|cffff4444hidden|r"))
                end
            end
        end
    end
end
-- -------------------------------------------------------------
-- /kcdspec [spellID]
-- Diagnoses exactly why a spec-locked spell isn't showing for the
-- player, by printing each piece IsSpellKnownForUnit actually checks:
-- resolved specId, IsPlayerSpell/IsSpellKnown results, and whether
-- the spell's data.specs list contains that specId.
-- -------------------------------------------------------------
SLASH_KASTACDSPEC1 = "/kcdspec"
SlashCmdList["KASTACDSPEC"] = function(msg)
    local sid = tonumber(msg)
    if not sid or not SPELL_DB[sid] then
        print("KastaCD: usage /kcdspec <spellID> - must be a tracked spell.")
        return
    end

    local data = SPELL_DB[sid]
    print(string.format("KastaCD spec check for [%d] %s (class=%s)", sid, data.name, tostring(data.class)))

    local specIndex = GetSpecialization and GetSpecialization()
    print("  GetSpecialization() index:", tostring(specIndex))

    local resolvedSpecId
    if specIndex then
        resolvedSpecId = GetSpecializationInfo(specIndex)
    end
    print("  GetSpecializationInfo() specId:", tostring(resolvedSpecId))

    local cachedSpecId = type(GetUnitSpec) == "function" and GetUnitSpec("player")
    print("  GetUnitSpec(\"player\") result:", tostring(cachedSpecId))

    local checkId = sid
    if FindSpellOverrideByID then
        local ov = FindSpellOverrideByID(sid)
        if ov and ov ~= 0 then checkId = ov end
    end
    print("  FindSpellOverrideByID:", tostring(checkId ~= sid and checkId or "none"))

    local ips1 = IsPlayerSpell and IsPlayerSpell(checkId)
    local ips2 = IsPlayerSpell and IsPlayerSpell(sid)
    print(string.format("  IsPlayerSpell(checkId=%d): %s   IsPlayerSpell(spellId=%d): %s",
        checkId, tostring(ips1), sid, tostring(ips2)))

    local isk1 = IsSpellKnown and IsSpellKnown(checkId)
    local isk2 = IsSpellKnown and IsSpellKnown(sid)
    print(string.format("  IsSpellKnown(checkId=%d): %s   IsSpellKnown(spellId=%d): %s",
        checkId, tostring(isk1), sid, tostring(isk2)))

    print("  data.specs:", data.specs and table.concat(data.specs, ",") or "nil (shared/no restriction)")

    if data.specs and cachedSpecId then
        local matches = false
        for _, s in ipairs(data.specs) do
            if s == cachedSpecId then matches = true break end
        end
        print("  specId in data.specs list?:", tostring(matches))
    end

    print("  Final IsSpellKnownForUnit(\"player\", " .. sid .. "):", tostring(IsSpellKnownForUnit("player", sid)))
end
-- -------------------------------------------------------------
-- /kcdpoll
-- Dumps the live UNIT_SPEC_CACHE state for the player and all
-- present party members, as currently maintained by the 1s
-- SpecPollTicker in KastaCD_Events.lua. Useful for confirming the
-- PAB-style polling architecture is actually keeping spec data
-- fresh (run it a few times a couple seconds apart to watch it
-- self-correct after a spec change or a transient bad read).
-- -------------------------------------------------------------
SLASH_KASTACDPOLL1 = "/kcdpoll"
SlashCmdList["KASTACDPOLL"] = function()
    print("KastaCD live spec cache:")
    local playerSpec = UNIT_SPEC_CACHE and UNIT_SPEC_CACHE["player"]
    print(string.format("  player: spec=%s", tostring(playerSpec)))
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) then
            local guid = UnitGUID(unit)
            local spec = guid and UNIT_SPEC_CACHE and UNIT_SPEC_CACHE[guid]
            local name = UnitName(unit) or unit
            print(string.format("  %s (%s): spec=%s", unit, name, tostring(spec)))
        end
    end
end
