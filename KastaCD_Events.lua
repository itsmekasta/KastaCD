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
-- Rather than validating a single read and hoping it's correct,
-- re-read every tracked unit's spec once a second, forever, for as
-- long as the addon is loaded. A transient bad/stale read is never
-- trusted for more than ~1 second before being silently overwritten
-- by the next poll - which in practice behaves exactly like "always
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

    -- Same self-correcting philosophy as the spec poll above: rather than
    -- chasing the exact timing of whichever event *should* have shown the
    -- trackers, just re-run their rebuild on this same 1s cadence while
    -- grouped. Cheap (mostly reuses existing bar frames) and guarantees
    -- both trackers self-heal within ~1s of group/spec state settling,
    -- instead of staying stuck hidden until the user manually unlocks to
    -- force a rebuild.
    if type(RebuildInterruptBars) == "function" then RebuildInterruptBars() end
    if type(RebuildCCBars) == "function" then RebuildCCBars() end

    -- RebuildIcons() has its own signature-based short-circuit (near-free
    -- when nothing's actually changed), so it's cheap to include here too.
    -- This is what fixes the "player icons gone after login, back after a
    -- /reload" symptom with ElvUI's "show player in party frame" turned
    -- off: TrySnapAnchor's ElvUI-frame lookup depends on ElvUI having
    -- already applied that hide setting by the time we check, which is a
    -- timing race we don't control - a login has a loading screen giving
    -- ElvUI more time to settle before our one-shot delayed rebuild fires,
    -- while a same-session /reload can catch it mid-settle. Re-checking
    -- every second means whichever way that race goes, it self-corrects
    -- within ~1s instead of being stuck wrong until something else
    -- happens to trigger another rebuild.
    RebuildIcons()
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
            if type(RebuildInterruptBars) == "function" then RebuildInterruptBars() end
            if type(RebuildCCBars) == "function" then RebuildCCBars() end
        end)
        return
    end

    -- ── GROUP_ROSTER_UPDATE ────────────────────────────────────
    if event == "GROUP_ROSTER_UPDATE" then
        if not HasGroup() or (IsInRaid and IsInRaid()) then
            ClearIcons()
            if type(RebuildInterruptBars) == "function" then RebuildInterruptBars() end
            if type(RebuildCCBars) == "function" then RebuildCCBars() end
            return
        end
        C_Timer.After(0.8, function()
            if not HasGroup() or (IsInRaid and IsInRaid()) then ClearIcons(); return end
            RefreshMemberGUIDs()
            RebuildIcons()
            if type(RebuildInterruptBars) == "function" then RebuildInterruptBars() end
            if type(RebuildCCBars) == "function" then RebuildCCBars() end
        end)
        return
    end

    -- ── ZONE_CHANGED_NEW_AREA ──────────────────────────────────
    if event == "ZONE_CHANGED_NEW_AREA" then
        C_Timer.After(1, RebuildIcons)
        return
    end

    -- ── Talent / spell / spec changes ──────────────────────────
    -- Also clears the player's stored interrupt/CC bar state before
    -- rebuilding: once a real cast has been witnessed it's normally
    -- treated as permanently authoritative (never re-guessed), but a
    -- talent/spec swap can make that witnessed spell factually wrong
    -- (e.g. respeccing away from the class/spec that had it) - without
    -- clearing it, the bar would keep showing the old spell until the
    -- player actually casts whatever they swapped to.
    if event == "SPELLS_CHANGED"
    or event == "CHARACTER_POINTS_CHANGED"
    or event == "PLAYER_TALENT_UPDATE" then
        C_Timer.After(0.5, function()
            RebuildIcons()
            if type(ClearIntBarState) == "function" then ClearIntBarState("player") end
            if type(ClearCCBarState) == "function" then ClearCCBarState("player") end
            if type(RebuildInterruptBars) == "function" then RebuildInterruptBars() end
            if type(RebuildCCBars) == "function" then RebuildCCBars() end
        end)
        return
    end

    -- ── PLAYER_SPECIALIZATION_CHANGED ─────────────────────────
    -- The next SpecPollTicker tick (within 1s) will pick up the new
    -- spec on its own; this just rebuilds icons a beat after that so
    -- the UI reflects it without waiting for an unrelated event. Clears
    -- stored bar state first - see the comment above for why.
    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        local unit = ...
        if unit == "player" then
            C_Timer.After(1.2, function()
                RebuildIcons()
                if type(ClearIntBarState) == "function" then ClearIntBarState("player") end
                if type(ClearCCBarState) == "function" then ClearCCBarState("player") end
                if type(RebuildInterruptBars) == "function" then RebuildInterruptBars() end
                if type(RebuildCCBars) == "function" then RebuildCCBars() end
            end)
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
    --
    -- Deliberately does NOT call ClearIntBarState/ClearCCBarState here.
    -- GetInspectSpecialization() is the exact unreliable-on-private-
    -- servers read this file's own architecture notes warn about (see
    -- KastaCD_DB.lua) - trusting a single "spec changed" detection from
    -- it to wipe out real witnessed-cast bar state meant a transient bad
    -- read would intermittently clear valid data, and the bar wouldn't
    -- reliably come back until the next witnessed cast or lucky guess.
    -- The player's own spec (PLAYER_SPECIALIZATION_CHANGED below) is
    -- safe to clear on since GetSpecialization() is synchronous/reliable
    -- - only that path gets the clear.
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
                        if type(RebuildInterruptBars) == "function" then RebuildInterruptBars() end
                        if type(RebuildCCBars) == "function" then RebuildCCBars() end
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