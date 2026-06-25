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
    local cc, tc, ec = 0, 0, 0
    for _ in pairs(iconContainers)                        do cc = cc + 1 end
    for _ in pairs(trackerState)                          do tc = tc + 1 end
    for _ in pairs(KastaCDDB and KastaCDDB.enabled or {}) do ec = ec + 1 end

    print("KastaCD debug:")
    print("  profile :", KastaCDDB and KastaCDDB.activeProfile)
    print("  enabled :", ec,
          "  content:", GetCurrentContentType(),
          "  active:", tostring(IsContentEnabled()))
    print("  containers:", cc, "  tracker units:", tc)

    local gpi = KastaCDDB and KastaCDDB.groupPositionIdx
    print("  groupPos:",
        tostring(gpi and gpi[1]),
        tostring(gpi and gpi[2]),
        tostring(gpi and gpi[3]))

    for u, g in pairs(memberGUIDs) do
        print("  ", u, "=", g)
    end

    local foundFrames = FindUnitFrames()
    print("  detected frames:", #foundFrames)
    for _, pair in ipairs(foundFrames) do
        local unit = pair.unit
        local _, cls = UnitClass(unit)
        local frameName = pair.frame.GetName and pair.frame:GetName() or "(unnamed)"
        print(string.format("  RF unit=%s cls=%s shown=%s frame=%s",
            tostring(unit), tostring(cls), tostring(pair.frame:IsShown()), tostring(frameName)))
        for g = 1, SPELL_GROUP_COUNT do
            local ck = unit and (unit .. "_g" .. g)
            local il = ck and iconContainers[ck]
            if il and il.icons and #il.icons > 0 then
                local p, _, _, x, y = il.container and il.container:GetPoint(1)
                print(string.format("    g%d: %d icons  container at %s %.0f %.0f",
                    g, #il.icons, tostring(p), x or 0, y or 0))
            end
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

    -- 3. What does FindUnitFrames() return?
    local pairs_found = FindUnitFrames()
    print("FindUnitFrames() returned:", #pairs_found)
    for _, p in ipairs(pairs_found) do
        print(string.format("  unit=%s  frame=%s  guid=%s",
            tostring(p.unit),
            tostring(p.frame.GetName and p.frame:GetName() or "(unnamed)"),
            tostring(UnitGUID(p.unit))))
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