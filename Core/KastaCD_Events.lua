-- KastaCD_Events.lua - registers all WoW events KastaCD cares about,
-- routes them to the correct handler, and registers the /kcd slash command.
-- Depends on: everything else (loaded last).

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
kcdEvent:RegisterEvent("UNIT_SPELLCAST_START")
kcdEvent:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")

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

-- Player plus every known party member. Rebuilt fresh each call.
local function GetTrackedUnits()
    local units = { "player" }
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) then units[#units + 1] = u end
    end
    return units
end

-- SpecPollTicker: re-reads every tracked unit's spec every second rather
-- than validating a single read - a bad/stale read is overwritten within
-- ~1s instead of needing complex validation logic.
local lastInspectRequest = 0
C_Timer.NewTicker(1.0, function()
    if not HasGroup() then return end

    for _, unit in ipairs(GetTrackedUnits()) do
        PollUnitSpec(unit)
    end

    -- Fire inspect requests at a slower cadence so we don't spam NotifyInspect.
    local now = GetTime()
    if now - lastInspectRequest > 3 then
        lastInspectRequest = now
        for _, unit in ipairs(GetTrackedUnits()) do
            RequestUnitInspect(unit)
        end
    end

    -- Same self-correcting philosophy: re-run rebuilds on this 1s cadence
    -- while grouped instead of chasing exact event timing.
    if type(RebuildInterruptBars) == "function" then RebuildInterruptBars() end
    if type(RebuildCCBars) == "function" then RebuildCCBars() end

    -- RebuildIcons has its own signature-based short-circuit, so it's
    -- cheap to include here too - fixes ElvUI hide-setting timing races.
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

    if event == "PLAYER_ENTERING_WORLD" then
        KastaCDInitDB()
        -- Test Mode never persists across a reload/relog.
        if type(KastaCDDB.intAnchor) == "table" then KastaCDDB.intAnchor.testMode = false end
        if type(KastaCDDB.ccAnchor)  == "table" then KastaCDDB.ccAnchor.testMode  = false end
        if type(GetBuffDisplayDB)    == "function" then GetBuffDisplayDB().testMode   = false end
        if type(GetDebuffDisplayDB)  == "function" then GetDebuffDisplayDB().testMode = false end
        C_Timer.After(1.5, function()
            RefreshMemberGUIDs()
            RebuildIcons()
            if type(RebuildInterruptBars) == "function" then RebuildInterruptBars() end
            if type(RebuildCCBars) == "function" then RebuildCCBars() end
        end)
        -- Re-asserts the Interrupt Tracker's saved position once more,
        -- later, since UIParent's scale isn't always settled by the first try.
        C_Timer.After(3, function()
            if type(ReapplyIntAnchorPos) == "function" then ReapplyIntAnchorPos() end
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
        C_Timer.After(1, function()
            RebuildIcons()
            if type(RebuildInterruptBars) == "function" then RebuildInterruptBars() end
            if type(RebuildCCBars) == "function" then RebuildCCBars() end
        end)
        return
    end

    -- Talent/spell/spec changes: also clears stored interrupt/CC bar
    -- state, since a witnessed cast can become factually wrong after a respec.
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

    -- SpecPollTicker picks up the new spec within 1s; this rebuilds icons
    -- a beat after and clears stored bar state (same reason as above).
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

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        HandleCombatLog(...)
        return
    end

    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        if type(TrackCastInterruptible) == "function" then TrackCastInterruptible(...) end
        return
    end

    -- Only rebuild when spec actually changed, to avoid restarting glow
    -- animations on every inspect cycle. Doesn't clear bar state here -
    -- GetInspectSpecialization is unreliable enough that a bad read would
    -- intermittently wipe valid data; only the player's own
    -- (synchronous) spec change gets the clear.
    if event == "INSPECT_READY" then
        local guid = select(1, ...)
        if guid then
            for i = 1, 4 do
                local unit = "party" .. i
                if UnitGUID(unit) == guid then
                    local oldSpec = GetUnitSpec(unit)
                    PollUnitSpec(unit)
                    local specChanged = GetUnitSpec(unit) ~= oldSpec
                    -- Also confirm talent picks via the same inspect data.
                    local talentsLearned = type(ScanUnitTalents) == "function" and ScanUnitTalents(unit)
                    if specChanged or talentsLearned then
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

-- /rl - shorthand for /reload.
SLASH_KASTACDRELOAD1 = "/rl"
SlashCmdList["KASTACDRELOAD"] = function()
    ReloadUI()
end

-- /kcd, /kastacd, /kasta - open/close the settings menu.
SLASH_KASTACD1 = "/kcd"
SLASH_KASTACD2 = "/kastacd"
SLASH_KASTACD3 = "/kasta"
SlashCmdList["KASTACD"] = function()
    -- pcall so a construction error is shown, not left silently nil.
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