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

-- Fire inspect requests for every current group member so GetUnitSpec()
-- can populate UNIT_SPEC_CACHE and filter spec-locked spells correctly.
-- Called before RebuildIcons so requests are in-flight as early as possible.
local function RequestGroupInspects()
    local units = {}
    for i = 1, 40 do
        local f = _G["CompactRaidFrame" .. i]
        if not f then break end
        local unit = f.unit or f.displayedUnit
        if unit and UnitExists(unit) and unit ~= "player" then
            units[unit] = true
        end
    end
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) then units[unit] = true end
    end
    for unit in pairs(units) do
        if NotifyInspect and CanInspect and CanInspect(unit) then
            NotifyInspect(unit)
        end
    end
end

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
            RequestGroupInspects()
            RebuildIcons()
            -- Second pass after inspect data has had time to arrive,
            -- correcting any icons shown optimistically due to unknown spec.
            C_Timer.After(3.0, RebuildIcons)
        end)
        return
    end

    -- ── GROUP_ROSTER_UPDATE ────────────────────────────────────
    if event == "GROUP_ROSTER_UPDATE" then
        -- Fire an immediate clear so icons never linger when leaving a group.
        -- The delayed path below will rebuild if we're still in a valid party
        -- after the roster settles.
        if not HasGroup() or (IsInRaid and IsInRaid()) then
            ClearIcons()
            return
        end
        C_Timer.After(0.8, function()
            if not HasGroup() or (IsInRaid and IsInRaid()) then ClearIcons(); return end
            RefreshMemberGUIDs()
            RequestGroupInspects()
            RebuildIcons()
            C_Timer.After(3.0, RebuildIcons)
        end)
        return
    end

    -- ── ZONE_CHANGED_NEW_AREA ──────────────────────────────────
    if event == "ZONE_CHANGED_NEW_AREA" then
        C_Timer.After(1, RebuildIcons)
        return
    end

    -- ── Talent / spell changes ─────────────────────────────────
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
    if event == "INSPECT_READY" then
        local guid = select(1, ...)
        if guid and UNIT_SPEC_CACHE and UNIT_SPEC_CACHE[guid] == false then
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