-- =============================================================
-- KastaCD_KastaPlates.lua
-- Recolors a nameplate's health bar for specific enemies you've flagged
-- as important (interrupt/CC/priority targets) in Mythic+ dungeons, and
-- optionally assigns a raid target icon to them when they spawn. Entries
-- are organized per-dungeon (by instanceID) since the same NPC name/color
-- choice usually only makes sense within one specific dungeon.
--
-- Reference: Plater (Addons/Plater/Plater.lua) was studied for HOW to
-- recolor a nameplate health bar without tainting - it doesn't ship any
-- reusable "important NPC" database itself (its only NPC-ID table is for
-- world-map service-NPC classification, unrelated). The actual per-dungeon
-- NPC roster (KASTAPLATES_DUNGEONS/KASTAPLATES_DUNGEON_NPCS) instead comes
-- from Method Dungeon Tools' route-planning data - see
-- KastaCD_KastaPlatesData.lua. Users pick a dungeon + NPC from that
-- pre-built list in the options UI and customize its color/mark directly;
-- there's no separate "add" step since every NPC is already known.
--
-- Taint safety: Blizzard's nameplates are CompactUnitFrames, and Blizzard
-- itself resets a frame's health bar color on many of its own events
-- (CompactUnitFrame_UpdateHealthColor). Directly calling
-- healthBar:SetStatusBarColor(...) once would just get overwritten the
-- next time Blizzard's own code runs. Plater's fix (confirmed by reading
-- its source) is to hooksecurefunc CompactUnitFrame_UpdateHealthColor and
-- re-apply the forced color AFTER Blizzard's own logic runs each time -
-- hooksecurefunc chains onto a function rather than replacing it, so it
-- never touches a protected function's execution path and can't taint.
-- =============================================================

function GetKastaPlatesDB()
    KastaCDDB = KastaCDDB or {}
    local db = KastaCDDB.kastaPlates
    if not db then
        db = {}
        KastaCDDB.kastaPlates = db
    end
    if db.enabled == nil then db.enabled = true end
    if type(db.dungeons) ~= "table" then db.dungeons = {} end
    if type(db.castHighlight) ~= "table" then db.castHighlight = {} end
    local ch = db.castHighlight
    if ch.enabled == nil then ch.enabled = true end
    -- Two separate colors instead of one flat color + an "only
    -- non-interruptible" on/off toggle - the color itself now signals
    -- which kind of cast it is (kickable vs not) instead of hiding one
    -- category outright.
    if type(ch.interruptibleColor) ~= "table" then ch.interruptibleColor = { 1, 0.82, 0 } end
    if type(ch.nonInterruptibleColor) ~= "table" then ch.nonInterruptibleColor = { 1, 0, 0 } end
    return db
end

-- Raid target marker names/order, index 1-8 (matches SetRaidTarget's own
-- numbering) - 0 always means "no marker" and isn't listed here.
KASTAPLATES_MARKS = {
    [0] = "None",
    [1] = "Star", [2] = "Circle", [3] = "Diamond", [4] = "Triangle",
    [5] = "Moon", [6] = "Square", [7] = "Cross", [8] = "Skull",
}

local function GUIDToNpcID(guid)
    if not guid then return nil end
    return tonumber(guid:match("^Creature%-0%-%d+%-%d+%-%d+%-(%d+)%-"))
end

-- Returns (instanceID, instanceName) for whatever zone/instance the
-- player is currently in - used both as the dungeon "bucket" key for new
-- entries and to decide which bucket's entries apply to currently-visible
-- plates.
local function CurrentInstance()
    local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    return instanceID, name
end


-- Lazily returns (creating if needed) the customization entry for an NPC
-- picked from the dungeon/NPC dropdowns (KASTAPLATES_DUNGEONS/
-- KASTAPLATES_DUNGEON_NPCS - see KastaCD_KastaPlatesData.lua). The full
-- roster is already known from that static database, so merely picking
-- an NPC to look at doesn't need an explicit "Add" step or clutter the
-- saved list - an entry is only actually created the moment its color or
-- mark is changed away from the default (see BuildKastaPlatesGroup's
-- color/mark get/set).
-- Plain red unless this npcID has a curated preset (KASTAPLATES_PRESET_
-- COLORS, KastaCD_KastaPlatesData.lua) - shared by the entry-creation
-- default below AND the options UI's color-picker get()s, so a preset
-- shows up immediately even before anyone's actually saved a
-- customization for that NPC.
function DefaultKastaPlatesColor(npcID)
    local preset = KASTAPLATES_PRESET_COLORS and npcID and KASTAPLATES_PRESET_COLORS[npcID]
    return preset or { 1, 0, 0 }
end

function GetOrCreateKastaPlatesEntry(instanceID, npcID)
    if not instanceID or not npcID then return nil end
    local roster = KASTAPLATES_DUNGEON_NPCS and KASTAPLATES_DUNGEON_NPCS[instanceID]
    local name = roster and roster[npcID]
    if not name then return nil end

    local db = GetKastaPlatesDB()
    local bucket = db.dungeons[instanceID]
    if not bucket then
        bucket = { name = KASTAPLATES_DUNGEONS[instanceID] or ("Instance " .. instanceID), npcs = {} }
        db.dungeons[instanceID] = bucket
    end

    local entry = bucket.npcs[npcID]
    if not entry then
        entry = { name = name, color = DefaultKastaPlatesColor(npcID), mark = 0 }
        bucket.npcs[npcID] = entry
    end
    return entry
end

-- Turns every KASTAPLATES_PRESET_COLORS entry into an actual saved,
-- persistent customization (not just a fallback default color for the
-- picker to display) - so preset-colored NPCs show up immediately in the
-- per-dungeon tabs below, the same as anything manually customized,
-- instead of only materializing once someone happens to open the picker
-- and touch that exact NPC.
--
-- Tracked per-npcID (db.seededPresetNPCs), not one blanket flag, so
-- adding MORE presets in a future update still seeds those new ones on
-- next login without re-touching (or fighting) anything already seeded
-- before - including a color you've since changed away from the preset,
-- or an entry you've since removed entirely.
function SeedKastaPlatesPresets()
    if not KASTAPLATES_PRESET_COLORS then return end
    local db = GetKastaPlatesDB()
    if type(db.seededPresetNPCs) ~= "table" then db.seededPresetNPCs = {} end

    for instanceID, roster in pairs(KASTAPLATES_DUNGEON_NPCS or {}) do
        for npcID in pairs(roster) do
            local preset = KASTAPLATES_PRESET_COLORS[npcID]
            if preset and not db.seededPresetNPCs[npcID] then
                db.seededPresetNPCs[npcID] = true
                local entry = GetOrCreateKastaPlatesEntry(instanceID, npcID)
                if entry then entry.color = preset end
            end
        end
    end
end

function RemoveKastaPlatesNPC(instanceID, npcID)
    local db = GetKastaPlatesDB()
    local bucket = db.dungeons[instanceID]
    if not bucket then return end
    bucket.npcs[npcID] = nil
    if not next(bucket.npcs) then
        db.dungeons[instanceID] = nil
    end
end

-- -------------------------------------------------------------
-- Health bar color enforcement
-- -------------------------------------------------------------
-- hookedFrames avoids double-hooking the same CompactUnitFrame's health
-- bar reference (nameplates get reused across units, but hooksecurefunc
-- itself is global to the function name, not per-frame, so this is
-- really just bookkeeping for readability - the actual hook is installed
-- exactly once below, ever).
local activeUnits = {}   -- [unitToken] = { npcID, baseColor={r,g,b} or nil, castColor={r,g,b} or nil }

-- TidyPlates (and its skin packages Graphite/Grey/Neon/Quatre) replaces
-- Blizzard's nameplate visuals but keeps using the SAME frame
-- C_NamePlate.GetNamePlateForUnit returns - it just bolts extra fields
-- onto it. Its actual health bar is a hand-rolled pseudo-StatusBar at
-- plate.extended.visual.healthbar (confirmed by reading TidyPlatesCore.lua/
-- TidyPlatesStatusbar.lua), not a real Blizzard StatusBar, so it has no
-- GetStatusBarTexture()/GetParent() the way plate.UnitFrame.healthBar
-- does - only a plain .Bar texture and a :SetStatusBarColor(r,g,b) method
-- TidyPlates itself defines. Checking for that field first means both
-- nameplate systems fall through the exact same coloring code below.
local function GetPlateHealthBar(unitToken)
    local plate = C_NamePlate.GetNamePlateForUnit(unitToken)
    if not plate then return nil end

    local tpBar = plate.extended and plate.extended.visual and plate.extended.visual.healthbar
    if tpBar then return tpBar, "tidyplates" end

    -- ElvUI hides Blizzard's real plate.UnitFrame entirely (hooks its
    -- OnShow straight to :Hide()) and builds its own parallel frame at
    -- plate.unitFrame (lowercase u - a different field, not a typo) with
    -- its own .HealthBar - confirmed by reading ElvUI's nameplates.lua/
    -- healthBar.lua. That HealthBar IS a real Blizzard StatusBar widget
    -- (CreateFrame("StatusBar", ...)), unlike TidyPlates' hand-rolled
    -- object, so it needs no special-cased coloring path below - just
    -- has to be found before falling through to the (invisible, ElvUI-
    -- suppressed) plate.UnitFrame.healthBar.
    local elvBar = plate.unitFrame and plate.unitFrame.HealthBar
    if elvBar then return elvBar, "elvui" end

    local uf = plate.UnitFrame
    return uf and uf.healthBar, "blizzard"
end

-- A priority-NPC color (baseColor) always wins over the generic Cast
-- Highlight tint (castColor) - previously the other way around, which
-- meant any mob you'd colored got silently overridden by the (default
-- yellow) cast highlight the moment it cast/attacked, defeating the
-- whole point of giving it a stable, recognizable color. Cast Highlight
-- now only ever shows on nameplates that DON'T have a priority color
-- assigned at all.
local function EffectiveColor(state)
    if not state then return nil end
    return state.baseColor or state.castColor
end

-- TidyPlates recolors its custom health bar via its own per-instance
-- :SetStatusBarColor method (TidyPlatesStatusbar.lua), not any single
-- shared function the way Blizzard's CompactUnitFrame_UpdateHealthColor
-- is - so there's no one global function to hooksecurefunc once. Instead
-- this hooks that ONE health bar OBJECT's method, exactly once per
-- object (tracked via kcdTPHooked on the bar itself, since nameplates -
-- and their bar objects - get reused across different units over time).
local function EnsureTidyPlatesHook(healthBar)
    if healthBar.kcdTPHooked then return end
    healthBar.kcdTPHooked = true
    hooksecurefunc(healthBar, "SetStatusBarColor", function(self, r, g, b)
        local c = self.kcdForcedColor
        -- Guard against re-triggering our own call to SetStatusBarColor
        -- just below - hooksecurefunc still fires for calls WE make, not
        -- just TidyPlates' own.
        if c and (r ~= c[1] or g ~= c[2] or b ~= c[3]) then
            self:SetStatusBarColor(c[1], c[2], c[3])
        end
    end)
end

local function ApplyEffectiveColor(unitToken)
    local state = activeUnits[unitToken]
    local healthBar, kind = GetPlateHealthBar(unitToken)
    if not healthBar then return end

    if kind == "tidyplates" then
        EnsureTidyPlatesHook(healthBar)
    end

    local color = EffectiveColor(state)
    if color then
        healthBar.kcdForcedColor = color
        healthBar:SetStatusBarColor(color[1], color[2], color[3])
        if healthBar.Bar then
            healthBar.Bar:SetVertexColor(color[1], color[2], color[3])
        end
    elseif healthBar.kcdForcedColor then
        healthBar.kcdForcedColor = nil
        if kind == "blizzard" and CompactUnitFrame_UpdateHealthColor and healthBar:GetParent() then
            -- Let Blizzard recompute its own normal color immediately
            -- instead of waiting for its next unrelated health-color
            -- update.
            CompactUnitFrame_UpdateHealthColor(healthBar:GetParent())
        end
        -- TidyPlates has no equivalent "recompute now" call to make here -
        -- it repaints this bar on its own next update cycle regardless.
    end
end

-- Installed exactly once - re-asserts whatever forced color a health bar
-- is currently marked with, immediately after Blizzard's own color logic
-- runs on it. This is what makes the forced color actually stick instead
-- of being silently overwritten on the next health/threat update.
local hookInstalled = false
local function EnsureHealthColorHook()
    if hookInstalled then return end
    hookInstalled = true
    if type(CompactUnitFrame_UpdateHealthColor) ~= "function" then return end
    hooksecurefunc("CompactUnitFrame_UpdateHealthColor", function(frame)
        local healthBar = frame and frame.healthBar
        local c = healthBar and healthBar.kcdForcedColor
        if c then
            healthBar:SetStatusBarColor(c[1], c[2], c[3])
        end
    end)
end

-- Plater (unlike TidyPlates) keeps using Blizzard's own real
-- plate.UnitFrame.healthBar object - GetPlateHealthBar already finds it
-- correctly with no changes needed. The problem is Plater aggressively
-- re-asserts ITS OWN color on that same object through a single choke
-- point, Plater.ForceChangeHealthBarColor (confirmed by reading its
-- source - every one of its own threat/quest/class/faction/periodic
-- recolor paths funnels through this one function, which sets
-- healthBar.R/G/B and calls healthBar.barTexture:SetVertexColor
-- directly, bypassing SetStatusBarColor entirely). Hooking
-- CompactUnitFrame_UpdateHealthColor alone doesn't catch that, since
-- Plater's own recoloring never calls it.
--
-- Safe to call Plater.ForceChangeHealthBarColor again from inside its own
-- hook without infinite recursion: that function is itself idempotent
-- (`if r~=healthBar.R or ... then ... end` - a no-op if the color passed
-- in already matches what's already set), so forcing our color back on
-- triggers the hook once more, sees our color already matches, and does
-- nothing further the second time.
local platerHookInstalled = false
local function EnsurePlaterHook()
    if platerHookInstalled then return end
    platerHookInstalled = true
    if not (_G.Plater and type(Plater.ForceChangeHealthBarColor) == "function") then return end
    hooksecurefunc(Plater, "ForceChangeHealthBarColor", function(healthBar, r, g, b)
        local c = healthBar and healthBar.kcdForcedColor
        if c and (r ~= c[1] or g ~= c[2] or b ~= c[3]) then
            Plater.ForceChangeHealthBarColor(healthBar, c[1], c[2], c[3])
        end
    end)
end

-- ElvUI hides Blizzard's real nameplate frame and builds its own parallel
-- one (plate.unitFrame.HealthBar - see GetPlateHealthBar above), but that
-- HealthBar IS a genuine Blizzard StatusBar, so no special coloring path
-- is needed once it's found. What IS needed is a hook, since ElvUI
-- re-asserts its own computed color through one shared module method,
-- NamePlates:UpdateElement_HealthColor(frame) - called from every
-- relevant event path (target change, aura, threat, name update, etc. -
-- confirmed by reading ElvUI's nameplates.lua/healthBar.lua), the same
-- single-choke-point shape as Plater's ForceChangeHealthBarColor.
--
-- ElvUI's engine is exposed as the global _G.ElvUI, an AceAddon table
-- whose [1] slot is the actual addon object (E) - E:GetModule(name, true)
-- with the silent flag so this doesn't hard-error if the user has ElvUI
-- installed but its NamePlates module disabled. The method is called with
-- a colon (mod:UpdateElement_HealthColor(frame)), so the hook handler
-- receives (self, frame) - `frame` here is ElvUI's own unitFrame object
-- (has .HealthBar/.unit/.displayedUnit directly on it, not the Blizzard
-- plate).
local elvuiHookInstalled = false
local function EnsureElvUIHook()
    if elvuiHookInstalled then return end
    elvuiHookInstalled = true
    local E = _G.ElvUI and _G.ElvUI[1]
    local NP = E and E.GetModule and E:GetModule("NamePlates", true)
    if not (NP and type(NP.UpdateElement_HealthColor) == "function") then return end
    hooksecurefunc(NP, "UpdateElement_HealthColor", function(_, frame)
        local healthBar = frame and frame.HealthBar
        local c = healthBar and healthBar.kcdForcedColor
        if c and healthBar:IsShown() then
            healthBar:SetStatusBarColor(c[1], c[2], c[3])
        end
    end)
end

-- Backup for color resets that DON'T go through CompactUnitFrame_
-- UpdateHealthColor at all - threat/aggro state apparently recolors the
-- health bar via a per-frame path of its own (a 0.2s C_Timer ticker tried
-- first still lost the race), so this re-asserts on a real OnUpdate
-- instead - every single frame, the same as Plater's own source, which
-- explicitly re-applies its forced color every OnUpdate tick rather than
-- on a slower timer (confirmed while researching how it recolors
-- nameplates). Also sets the underlying texture's vertex color directly
-- (not just the StatusBar-level SetStatusBarColor call) since Plater's
-- own fix does the same - matches whatever Blizzard's aggro-highlight
-- code is touching more closely than the StatusBar API alone. Only
-- touches nameplates KastaPlates is actually tracking, so this is cheap
-- even running every frame.
local reassertFrame
local function EnsureColorReassertTicker()
    if reassertFrame then return end
    reassertFrame = CreateFrame("Frame")
    reassertFrame:SetScript("OnUpdate", function()
        for unitToken, state in pairs(activeUnits) do
            local color = EffectiveColor(state)
            if color then
                local healthBar = GetPlateHealthBar(unitToken)
                if healthBar then
                    healthBar:SetStatusBarColor(color[1], color[2], color[3])
                    local tex = healthBar.GetStatusBarTexture and healthBar:GetStatusBarTexture()
                    if tex then
                        tex:SetVertexColor(color[1], color[2], color[3])
                    end
                    -- TidyPlates' custom health bar object (no real
                    -- GetStatusBarTexture) exposes its texture directly.
                    if healthBar.Bar then
                        healthBar.Bar:SetVertexColor(color[1], color[2], color[3])
                    end
                end
            end
        end
    end)
end

-- -------------------------------------------------------------
-- Per-plate evaluation
-- -------------------------------------------------------------
local function EvaluatePlate(unitToken)
    if not UnitExists(unitToken) then
        activeUnits[unitToken] = nil
        return
    end

    local db = GetKastaPlatesDB()
    if not db.enabled then
        if activeUnits[unitToken] then
            activeUnits[unitToken] = nil
            ApplyEffectiveColor(unitToken)
        end
        return
    end

    local npcID = GUIDToNpcID(UnitGUID(unitToken))
    local instanceID = CurrentInstance()
    local bucket = instanceID and db.dungeons[instanceID]
    local entry = bucket and npcID and bucket.npcs[npcID]

    local state = activeUnits[unitToken]
    if not state then
        state = { npcID = npcID }
        activeUnits[unitToken] = state
    end
    state.baseColor = entry and entry.color or nil

    ApplyEffectiveColor(unitToken)

    -- Re-applies only when the WANTED mark actually changes (either the
    -- user picked a different one in settings, or this is the first time
    -- this plate's been evaluated) - not every refresh, so a raid
    -- leader/assist manually clearing the marker in-game isn't fought.
    -- Previously this only ever applied once per plate ever (guarded by
    -- a plain `not state.marked` flag), so changing the mark after the
    -- NPC had already spawned silently never took effect.
    local wantMark = (entry and entry.mark) or 0
    if state.appliedMark ~= wantMark then
        state.appliedMark = wantMark
        pcall(SetRaidTarget, unitToken, wantMark)
    end
end

function RefreshKastaPlates()
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        if plate.namePlateUnitToken then
            EvaluatePlate(plate.namePlateUnitToken)
        end
    end
end

-- -------------------------------------------------------------
-- Cast-based highlight - cheap, no spellID database needed: just reads
-- whether the nameplate unit is currently casting anything at all, same
-- building block Plater's own cast bar uses (UnitCastingInfo/
-- UnitChannelInfo's notInterruptible return value).
-- -------------------------------------------------------------
local function UpdateCastHighlight(unitToken)
    local state = activeUnits[unitToken]
    if not state then return end

    local db = GetKastaPlatesDB()
    local ch = db.castHighlight
    if not db.enabled or not ch.enabled then
        state.castColor = nil
        ApplyEffectiveColor(unitToken)
        return
    end

    local name, _, _, _, _, _, notInterruptible = UnitCastingInfo(unitToken)
    if not name then
        name, _, _, _, _, _, _, notInterruptible = UnitChannelInfo(unitToken)
    end

    if not name then
        state.castColor = nil
    elseif notInterruptible then
        state.castColor = ch.nonInterruptibleColor
    else
        state.castColor = ch.interruptibleColor
    end
    ApplyEffectiveColor(unitToken)
end

-- -------------------------------------------------------------
-- Events
-- -------------------------------------------------------------
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("NAME_PLATE_UNIT_ADDED")
watcher:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
watcher:RegisterEvent("UNIT_SPELLCAST_START")
watcher:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
watcher:RegisterEvent("UNIT_SPELLCAST_STOP")
watcher:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
watcher:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
watcher:RegisterEvent("UNIT_SPELLCAST_FAILED")
local optionsRebuiltOnce = false
watcher:SetScript("OnEvent", function(_, event, unitToken)
    if event == "PLAYER_ENTERING_WORLD" then
        EnsureHealthColorHook()
        EnsurePlaterHook()
        EnsureElvUIHook()
        EnsureColorReassertTicker()
        SeedKastaPlatesPresets()
        RefreshKastaPlates()
        -- KastaCD_UI.lua's EnsureOptionsRegistered() builds the whole
        -- options menu once, very early during addon load - possibly
        -- before KastaCDDB has actually been restored from this
        -- session's SavedVariables file yet. Every other dynamic list in
        -- the menu either reads a hardcoded table (CC_SPELLS/CLASS_INFO,
        -- unaffected either way) or re-evaluates live on open (Profiles'
        -- dropdown), so this per-dungeon/per-NPC list is the first thing
        -- that actually needed real saved data baked in at build time -
        -- and the first to notice if that data wasn't there yet. Forcing
        -- one rebuild here, once, after the world has definitely
        -- finished loading, means the menu reflects whatever's actually
        -- in KastaCDDB regardless of exactly when the earlier build ran.
        if not optionsRebuiltOnce and type(RefreshKastaCDOptionsTable) == "function" then
            optionsRebuiltOnce = true
            RefreshKastaCDOptionsTable()
        end
        return
    end
    if event == "NAME_PLATE_UNIT_ADDED" then
        EvaluatePlate(unitToken)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        activeUnits[unitToken] = nil
    elseif unitToken and unitToken:match("^nameplate") then
        UpdateCastHighlight(unitToken)
    end
end)

EnsureHealthColorHook()
EnsurePlaterHook()
EnsureElvUIHook()
EnsureColorReassertTicker()

-- -------------------------------------------------------------
-- /kcdplatesdebug - dumps the raw saved state plus what's currently
-- applied to visible plates, to track down "color doesn't change" /
-- "entry disappears on reload" reports without guessing further.
-- -------------------------------------------------------------
SLASH_KASTACDPLATESDEBUG1 = "/kcdplatesdebug"
SlashCmdList["KASTACDPLATESDEBUG"] = function()
    local db = GetKastaPlatesDB()
    local instanceID, instanceName = CurrentInstance()
    print("|cff71d5ffKastaCD KastaPlates debug:|r")
    print("  enabled=" .. tostring(db.enabled) .. "  currentInstance=" .. tostring(instanceID) .. " (" .. tostring(instanceName) .. ")")

    local dungeonCount, npcCount = 0, 0
    for id, bucket in pairs(db.dungeons) do
        dungeonCount = dungeonCount + 1
        print(("  dungeon[%s] name=%s"):format(tostring(id), tostring(bucket.name)))
        for npcID, entry in pairs(bucket.npcs) do
            npcCount = npcCount + 1
            local c = entry.color or {}
            print(("    npc[%s] name=%s color=%.2f,%.2f,%.2f mark=%s"):format(
                tostring(npcID), tostring(entry.name), c[1] or -1, c[2] or -1, c[3] or -1, tostring(entry.mark)))
        end
    end
    print(("  total dungeons=%d, total npcs=%d"):format(dungeonCount, npcCount))

    print("  active plates:")
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        local unitToken = plate.namePlateUnitToken
        if unitToken then
            local state = activeUnits[unitToken]
            local healthBar, kind = GetPlateHealthBar(unitToken)
            local npcID = GUIDToNpcID(UnitGUID(unitToken))
            local forced = healthBar and healthBar.kcdForcedColor
            -- TidyPlates' custom health bar object only defines
            -- SetStatusBarColor, not the getter - guard rather than error.
            local realColor = "no healthbar"
            if healthBar and healthBar.GetStatusBarColor then
                realColor = string.format("%.2f,%.2f,%.2f", healthBar:GetStatusBarColor())
            elseif healthBar then
                realColor = "n/a (no getter)"
            end
            print(("    %s npcID=%s tracked=%s kind=%s forcedColor=%s realColor=%s"):format(
                tostring(unitToken), tostring(npcID), tostring(state ~= nil), tostring(kind),
                forced and string.format("%.2f,%.2f,%.2f", forced[1], forced[2], forced[3]) or "nil",
                realColor))
        end
    end
end
