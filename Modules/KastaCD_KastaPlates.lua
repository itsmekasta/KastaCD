-- =============================================================
-- KastaCD_KastaPlates.lua
-- Recolors a nameplate's health bar for specific enemies you've flagged
-- as important (interrupt/CC/priority targets) in Mythic+ dungeons, and
-- optionally assigns a raid target icon to them when they spawn. Entries
-- are organized per-dungeon (by instanceID) since the same NPC name/color
-- choice usually only makes sense within one specific dungeon.
--
-- The per-dungeon NPC roster (KASTAPLATES_DUNGEONS/KASTAPLATES_DUNGEON_NPCS)
-- comes from Method Dungeon Tools' route-planning data - see
-- KastaCD_KastaPlatesData.lua. Users pick a dungeon + NPC from that
-- pre-built list in the options UI and customize its color/mark directly;
-- there's no separate "add" step since every NPC is already known.
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

local function CurrentInstance()
    local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    return instanceID, name
end

-- Plain red unless this npcID has a curated preset (KASTAPLATES_PRESET_
-- COLORS, KastaCD_KastaPlatesData.lua).
function DefaultKastaPlatesColor(npcID)
    local preset = KASTAPLATES_PRESET_COLORS and npcID and KASTAPLATES_PRESET_COLORS[npcID]
    return preset or { 1, 0, 0 }
end

-- Lazily returns (creating if needed) the customization entry for an NPC.
-- An entry is only actually created the moment its color or mark is
-- changed away from the default (see BuildKastaPlatesGroup's color/mark
-- get/set), not merely by looking at it.
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

-- Turns every KASTAPLATES_PRESET_COLORS entry into an actual saved
-- customization, tracked per-npcID (db.seededPresetNPCs) so adding more
-- presets later only seeds the new ones without touching anything the
-- user has already customized or removed.
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
local activeUnits = {}   -- [unitToken] = { npcID, baseColor={r,g,b} or nil, castColor={r,g,b} or nil }

-- TidyPlates (and its skin packages) replaces Blizzard's nameplate
-- visuals but keeps using the same frame C_NamePlate.GetNamePlateForUnit
-- returns. Its health bar is a hand-rolled pseudo-StatusBar at
-- plate.extended.visual.healthbar, not a real Blizzard StatusBar - only a
-- .Bar texture and a :SetStatusBarColor(r,g,b) method it defines itself.
--
-- ElvUI hides Blizzard's real plate.UnitFrame and builds its own parallel
-- frame at plate.unitFrame (lowercase u) with its own .HealthBar, which
-- IS a genuine Blizzard StatusBar.
local function GetPlateHealthBar(unitToken)
    local plate = C_NamePlate.GetNamePlateForUnit(unitToken)
    if not plate then return nil end

    local tpBar = plate.extended and plate.extended.visual and plate.extended.visual.healthbar
    if tpBar then return tpBar, "tidyplates" end

    local elvBar = plate.unitFrame and plate.unitFrame.HealthBar
    if elvBar then return elvBar, "elvui" end

    local uf = plate.UnitFrame
    return uf and uf.healthBar, "blizzard"
end

-- A priority-NPC color (baseColor) always wins over the generic Cast
-- Highlight tint (castColor), so a colored mob doesn't lose its color the
-- moment it casts/attacks.
local function EffectiveColor(state)
    if not state then return nil end
    return state.baseColor or state.castColor
end

-- TidyPlates recolors via its own per-instance :SetStatusBarColor method,
-- not a shared global function, so this hooks that one health bar
-- object's method (tracked via kcdTPHooked, since nameplate bar objects
-- get reused across different units over time).
local function EnsureTidyPlatesHook(healthBar)
    if healthBar.kcdTPHooked then return end
    healthBar.kcdTPHooked = true
    hooksecurefunc(healthBar, "SetStatusBarColor", function(self, r, g, b)
        local c = self.kcdForcedColor
        if c and (r ~= c[1] or g ~= c[2] or b ~= c[3]) then
            self:SetStatusBarColor(c[1], c[2], c[3])
        end
    end)
end

local function EnsureHealthBarColorHook(healthBar)
    if healthBar.kcdColorHooked then return end
    healthBar.kcdColorHooked = true
    hooksecurefunc(healthBar, "SetStatusBarColor", function(self, r, g, b)
        local c = self.kcdForcedColor
        if c and (r ~= c[1] or g ~= c[2] or b ~= c[3]) then
            self:SetStatusBarColor(c[1], c[2], c[3])
        end
    end)
    local tex = healthBar.GetStatusBarTexture and healthBar:GetStatusBarTexture()
    if tex and not tex.kcdColorHooked then
        tex.kcdColorHooked = true
        hooksecurefunc(tex, "SetVertexColor", function(self, r, g, b)
            local c = healthBar.kcdForcedColor
            if c and (r ~= c[1] or g ~= c[2] or b ~= c[3]) then
                self:SetVertexColor(c[1], c[2], c[3])
            end
        end)
    end
end

local function ApplyEffectiveColor(unitToken)
    local state = activeUnits[unitToken]
    local healthBar, kind = GetPlateHealthBar(unitToken)
    if not healthBar then return end

    if kind == "tidyplates" then
        EnsureTidyPlatesHook(healthBar)
    else
        EnsureHealthBarColorHook(healthBar)
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
    end
end

-- Re-asserts a health bar's forced color immediately after Blizzard's own
-- color logic runs on it, so the forced color sticks instead of being
-- silently overwritten on the next health/threat update.
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

-- Plater keeps using Blizzard's own plate.UnitFrame.healthBar object, but
-- re-asserts its own color through a single choke point,
-- Plater.ForceChangeHealthBarColor, which sets healthBar.R/G/B and calls
-- healthBar.barTexture:SetVertexColor directly, bypassing
-- SetStatusBarColor entirely - hooking CompactUnitFrame_UpdateHealthColor
-- alone doesn't catch that. Safe to call
-- Plater.ForceChangeHealthBarColor again from inside its own hook without
-- infinite recursion since that function is itself idempotent.
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

-- ElvUI's HealthBar is a genuine Blizzard StatusBar, but ElvUI re-asserts
-- its own computed color through one shared module method,
-- NamePlates:UpdateElement_HealthColor(frame), called from every relevant
-- event path - the same single-choke-point shape as Plater's
-- ForceChangeHealthBarColor. ElvUI's engine is exposed as the global
-- _G.ElvUI, an AceAddon table whose [1] slot is the actual addon object.
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

    -- Re-applies only when the WANTED mark actually changes, not every
    -- refresh, so a raid leader/assist manually clearing the marker
    -- in-game isn't fought.
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
-- Cast-based highlight - reads whether the nameplate unit is currently
-- casting anything at all, no spellID database needed.
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
        RefreshKastaPlates()
        SeedKastaPlatesPresets()
        -- The options menu can build once, very early, before KastaCDDB
        -- has been restored from SavedVariables - force one rebuild here,
        -- after the world has finished loading, so the per-dungeon/per-NPC
        -- list reflects whatever's actually saved regardless of timing.
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

-- Blizzard's own threat/aggro and mouseover/OnEnter highlight logic both
-- recolor the health bar through a path that never calls
-- healthBar:SetStatusBarColor or its texture's :SetVertexColor on the
-- hooked objects, so the hooks above alone can't catch it - a slower
-- ticker (0.2s) still loses the race. Re-asserting every frame is the
-- only reliable fix; every write here only ever touches this addon's own
-- tracked units, same as the rest of this file's writes.
local reassertFrame = CreateFrame("Frame")
reassertFrame:SetScript("OnUpdate", function()
    for unitToken, state in pairs(activeUnits) do
        local color = EffectiveColor(state)
        if color then
            local healthBar = GetPlateHealthBar(unitToken)
            if healthBar then
                healthBar.kcdForcedColor = color
                healthBar:SetStatusBarColor(color[1], color[2], color[3])
                local tex = healthBar.GetStatusBarTexture and healthBar:GetStatusBarTexture()
                if tex then
                    tex:SetVertexColor(color[1], color[2], color[3])
                end
                if healthBar.Bar then
                    healthBar.Bar:SetVertexColor(color[1], color[2], color[3])
                end
            end
        end
    end
end)

-- -------------------------------------------------------------
-- /kcdplatesdebug - dumps the raw saved state plus what's currently
-- applied to visible plates.
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
