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
kcdEvent:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
kcdEvent:RegisterEvent("INSPECT_READY")

-- Shared helper: populate memberGUIDs from CompactRaidFrames + direct unit tokens.
local function RefreshMemberGUIDs()
    memberGUIDs = {}
    -- Always include the player themselves
    memberGUIDs["player"] = UnitGUID("player")
    -- CompactRaidFrames (default Blizzard UI)
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
end

-- All unit tokens currently worth polling for spec data: the player
-- plus every party member we know about. Rebuilt fresh each call so
-- it always reflects the current roster.
local function GetTrackedUnits()
    local units = { "player" }
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) then units[#units + 1] = u end
    end
    return units
end

-- ---------------------------------------------------------------
-- SpecPollTicker  –  the actual fix for spec-detection reliability.
--
-- Adopted directly from PartyAbilityBars' architecture: rather than
-- validating a single read and hoping it's correct, just re-read
-- every tracked unit's spec once a second, forever, for as long as
-- the addon is loaded. A transient bad/stale read is never trusted
-- for more than ~1 second before being silently overwritten by the
-- next poll - which in practice behaves exactly like "always
-- correct" without any of the validation complexity that kept
-- producing edge-case false negatives in earlier versions.
-- ---------------------------------------------------------------
local lastInspectRequest = 0
C_Timer.NewTicker(1.0, function()
    if not HasGroup() then return end

    for _, unit in ipairs(GetTrackedUnits()) do
        PollUnitSpec(unit)
    end

    -- Fire inspect requests at a slower cadence (every 3rd tick) so
    -- we don't spam NotifyInspect; GetInspectSpecialization only
    -- returns real data after an inspect request has been answered.
    local now = GetTime()
    if now - lastInspectRequest > 3 then
        lastInspectRequest = now
        for _, unit in ipairs(GetTrackedUnits()) do
            RequestUnitInspect(unit)
        end
    end
end)

kcdEvent:SetScript("OnEvent", function(self, event, ...)
    -- ── ADDON_LOADED ───────────────────────────────────────────
    if event == "ADDON_LOADED" then
        if select(1, ...) == "KastaCD" then
            KastaCDInitDB()
        end
        return
    end

    -- ── PLAYER_LOGOUT ──────────────────────────────────────────
    if event == "PLAYER_LOGOUT" then
        PersistActiveProfile()
        return
    end

    -- ── PLAYER_ENTERING_WORLD ──────────────────────────────────
    if event == "PLAYER_ENTERING_WORLD" then
        KastaCDInitDB()
        C_Timer.After(1.5, function()
            RefreshMemberGUIDs()
            RebuildIcons()
        end)
        return
    end

    -- ── GROUP_ROSTER_UPDATE ────────────────────────────────────
    if event == "GROUP_ROSTER_UPDATE" then
        if not HasGroup() or (IsInRaid and IsInRaid()) then
            ClearIcons()
            return
        end
        C_Timer.After(0.8, function()
            if not HasGroup() or (IsInRaid and IsInRaid()) then ClearIcons(); return end
            RefreshMemberGUIDs()
            RebuildIcons()
        end)
        return
    end

    -- ── ZONE_CHANGED_NEW_AREA ──────────────────────────────────
    if event == "ZONE_CHANGED_NEW_AREA" then
        C_Timer.After(1, RebuildIcons)
        return
    end

    -- ── Talent / spell / spec changes ──────────────────────────
    if event == "SPELLS_CHANGED"
    or event == "CHARACTER_POINTS_CHANGED"
    or event == "PLAYER_TALENT_UPDATE" then
        C_Timer.After(0.5, RebuildIcons)
        return
    end

    -- ── PLAYER_SPECIALIZATION_CHANGED ─────────────────────────
    -- The next SpecPollTicker tick (within 1s) will pick up the new
    -- spec on its own; this just rebuilds icons a beat after that so
    -- the UI reflects it without waiting for an unrelated event.
    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        local unit = ...
        if unit == "player" then
            C_Timer.After(1.2, RebuildIcons)
        end
        return
    end

    -- ── COMBAT_LOG_EVENT_UNFILTERED ───────────────────────────
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        HandleCombatLog(...)
        return
    end

    -- ── INSPECT_READY ─────────────────────────────────────────
    -- Inspect data just arrived. Only rebuild when the spec actually
    -- changed - unconditional RebuildIcons() here would restart active
    -- glow animations unnecessarily on every 3-second inspect cycle
    -- (INSPECT_READY fires for every NotifyInspect, even if the spec
    -- value is identical to what was already cached).
    if event == "INSPECT_READY" then
        local guid = select(1, ...)
        if guid then
            for i = 1, 4 do
                local unit = "party" .. i
                if UnitGUID(unit) == guid then
                    local oldSpec = GetUnitSpec(unit)
                    PollUnitSpec(unit)
                    if GetUnitSpec(unit) ~= oldSpec then
                        RebuildIcons()
                    end
                    break
                end
            end
        end
        return
    end
end)

-- =============================================================
-- Slash command  /kcd  –  open / close the settings menu
-- =============================================================
SLASH_KASTACD1 = "/kcd"
SlashCmdList["KASTACD"] = function()
    -- Wrap in pcall so any error during menu construction is shown
    -- rather than silently leaving kcdMenu nil and erroring on IsShown.
    local ok, err = pcall(CreateKastaCDMenu)
    if not ok then
        print("|cffff0000KastaCD: failed to open menu — " .. tostring(err) .. "|r")
        return
    end
    if not kcdMenu then
        print("|cffff0000KastaCD: menu could not be created.|r")
        return
    end
    if kcdMenu:IsShown() then
        kcdMenu:Hide()
    else
        kcdMenu:Show()
    end
end