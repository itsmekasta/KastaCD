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

    for i = 1, 40 do
        local f = _G["CompactRaidFrame" .. i]
        if not f then break end
        local unit = f.unit or f.displayedUnit
        local _, cls = unit and UnitExists(unit) and UnitClass(unit) or nil, nil
        print(string.format("  RF[%d] unit=%s cls=%s shown=%s",
            i, tostring(unit), tostring(cls), tostring(f:IsShown())))
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
