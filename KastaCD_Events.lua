-- =============================================================
-- KastaCD_Events.lua
-- Event frame: registers all WoW events KastaCD cares about,
-- routes them to the correct handler, and registers the /kcd
-- slash command.
-- Depends on: everything else (loaded last).
-- =============================================================

local kcdEvent = CreateFrame("Frame")

kcdEvent:RegisterEvent("ADDON_LOADED")
kcdEvent:RegisterEvent("PLAYER_ENTERING_WORLD")
kcdEvent:RegisterEvent("PLAYER_LOGOUT")
kcdEvent:RegisterEvent("GROUP_ROSTER_UPDATE")
kcdEvent:RegisterEvent("ZONE_CHANGED_NEW_AREA")
kcdEvent:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
kcdEvent:RegisterEvent("SPELLS_CHANGED")
kcdEvent:RegisterEvent("CHARACTER_POINTS_CHANGED")
kcdEvent:RegisterEvent("PLAYER_TALENT_UPDATE")
kcdEvent:RegisterEvent("INSPECT_READY")

kcdEvent:SetScript("OnEvent", function(self, event, ...)
    -- ── ADDON_LOADED ───────────────────────────────────────────
    -- Initialise the DB as soon as our saved variables are available.
    if event == "ADDON_LOADED" then
        if select(1, ...) == "KastaCD" then
            KastaCDInitDB()
        end
        return
    end

    -- ── PLAYER_LOGOUT ──────────────────────────────────────────
    -- Flush in-memory changes back to the stored profile before the
    -- game writes SavedVariables to disk.
    if event == "PLAYER_LOGOUT" then
        PersistActiveProfile()
        return
    end

    -- ── PLAYER_ENTERING_WORLD ──────────────────────────────────
    -- Fires on login, reload, and every zone transition that involves
    -- a loading screen.  We delay the rebuild slightly so that
    -- CompactRaidFrames have time to populate their unit references.
    if event == "PLAYER_ENTERING_WORLD" then
        KastaCDInitDB()
        C_Timer.After(1.5, function()
            memberGUIDs = {}
            -- Always include the player themselves
            memberGUIDs["player"] = UnitGUID("player")
            -- Scan CompactRaidFrames (used in raid/party with default UI)
            for i = 1, 40 do
                local f = _G["CompactRaidFrame" .. i]
                if not f then break end
                local unit = f.unit or f.displayedUnit
                if unit and UnitExists(unit) then
                    memberGUIDs[unit] = UnitGUID(unit)
                end
            end
            -- Direct unit-token fallback: covers party1-4 even when
            -- CompactRaidFrames haven't populated yet (common on pservers)
            for i = 1, 4 do
                local unit = "party" .. i
                if UnitExists(unit) then
                    memberGUIDs[unit] = UnitGUID(unit)
                end
            end
            RebuildIcons()
        end)
        return
    end

    -- ── GROUP_ROSTER_UPDATE ────────────────────────────────────
    -- Players join / leave the group.  Delay so the raid frame
    -- widgets have updated their unit assignments first.
    if event == "GROUP_ROSTER_UPDATE" then
        if not HasGroup() then
            ClearIcons()
            return
        end
        C_Timer.After(0.8, function()
            if not HasGroup() then ClearIcons(); return end
            memberGUIDs = {}
            -- Always include the player themselves
            memberGUIDs["player"] = UnitGUID("player")
            -- CompactRaidFrames
            for i = 1, 40 do
                local f = _G["CompactRaidFrame" .. i]
                if not f then break end
                local unit = f.unit or f.displayedUnit
                if unit and UnitExists(unit) then
                    memberGUIDs[unit] = UnitGUID(unit)
                end
            end
            -- Direct unit-token fallback
            for i = 1, 4 do
                local unit = "party" .. i
                if UnitExists(unit) then
                    memberGUIDs[unit] = UnitGUID(unit)
                end
            end
            RebuildIcons()
        end)
        return
    end

    -- ── ZONE_CHANGED_NEW_AREA ──────────────────────────────────
    -- Content type may have changed (e.g. entering arena).
    -- Short delay so IsInInstance() returns the new value.
    if event == "ZONE_CHANGED_NEW_AREA" then
        C_Timer.After(1, RebuildIcons)
        return
    end

    -- ── Talent / spell changes ─────────────────────────────────
    -- The player's available spells may have changed; rebuild so
    -- newly learned spells appear and removed ones disappear.
    if event == "SPELLS_CHANGED"
    or event == "CHARACTER_POINTS_CHANGED"
    or event == "PLAYER_TALENT_UPDATE" then
        C_Timer.After(0.5, RebuildIcons)
        return
    end

    -- ── COMBAT_LOG_EVENT_UNFILTERED ───────────────────────────
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        HandleCombatLog(...)
        return
    end

    -- ── INSPECT_READY ─────────────────────────────────────────
    -- Fires when GetInspectSpecialization() data is ready for a unit.
    -- The arg is the GUID of the inspected unit. Only clear that one
    -- GUID's cache entry (not the whole cache) so we don't re-trigger
    -- NotifyInspect for everyone and cause an infinite rebuild loop.
    if event == "INSPECT_READY" then
        local guid = select(1, ...)
        if guid and UNIT_SPEC_CACHE and UNIT_SPEC_CACHE[guid] == false then
            -- Was pending; clear so GetUnitSpec() reads the fresh data next rebuild.
            UNIT_SPEC_CACHE[guid] = nil
            C_Timer.After(0.1, RebuildIcons)
        end
        return
    end
end)

-- =============================================================
-- Slash command  /kcd  –  open / close the settings menu
-- =============================================================
SLASH_KASTACD1 = "/kcd"
SlashCmdList["KASTACD"] = function()
    CreateKastaCDMenu()
    if kcdMenu:IsShown() then
        kcdMenu:Hide()
    else
        kcdMenu:Show()
    end
end