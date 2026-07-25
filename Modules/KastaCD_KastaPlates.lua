-- KastaCD_KastaPlates.lua - recolors a nameplate's health bar for
-- flagged priority enemies in Mythic+ dungeons, and optionally assigns a
-- raid target icon. Entries are organized per-dungeon (instanceID).
-- The NPC roster (KASTAPLATES_DUNGEONS/KASTAPLATES_DUNGEON_NPCS) comes
-- from Method Dungeon Tools' route data, see KastaCD_KastaPlatesData.lua.

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

-- Raid target marker names, index 1-8 matches SetRaidTarget's numbering.
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

-- Lazily creates the customization entry for an NPC, only once its
-- color or mark is changed away from the default.
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

-- Turns every preset color into a saved customization, tracked per-npcID
-- so adding more presets later only seeds the new ones.
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

-- Health bar color enforcement
local activeUnits = {}   -- [unitToken] = { npcID, baseColor={r,g,b} or nil, castColor={r,g,b} or nil }

-- TidyPlates' health bar is a hand-rolled pseudo-StatusBar at
-- plate.extended.visual.healthbar, not a real Blizzard StatusBar. ElvUI
-- builds its own parallel frame at plate.unitFrame with a real .HealthBar.
-- Kui Nameplates attaches its replacement frame at plate.kui (see
-- Kui_Nameplates/addon.lua's NAME_PLATE_UNIT_ADDED), also a real
-- StatusBar at .HealthBar (Kui_Nameplates_Core/create.lua) - no special
-- hook needed, it goes through the same generic path as Blizzard/ElvUI.
local function GetPlateHealthBar(unitToken)
    local plate = C_NamePlate.GetNamePlateForUnit(unitToken)
    if not plate then return nil end

    local tpBar = plate.extended and plate.extended.visual and plate.extended.visual.healthbar
    if tpBar then return tpBar, "tidyplates" end

    local elvBar = plate.unitFrame and plate.unitFrame.HealthBar
    if elvBar then return elvBar, "elvui" end

    local kuiBar = plate.kui and plate.kui.HealthBar
    if kuiBar then return kuiBar, "kui" end

    local uf = plate.UnitFrame
    return uf and uf.healthBar, "blizzard"
end

-- baseColor always wins over the Cast Highlight tint (castColor), so a
-- colored mob doesn't lose its color the moment it casts.
local function EffectiveColor(state)
    if not state then return nil end
    return state.baseColor or state.castColor
end

-- Hooks TidyPlates' per-instance :SetStatusBarColor method (tracked via
-- kcdTPHooked since bar objects get reused across units).
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

-- Re-asserts a health bar's forced color right after Blizzard's own
-- color logic runs, so it isn't silently overwritten.
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

-- Plater re-asserts color through its own choke point,
-- Plater.ForceChangeHealthBarColor, bypassing SetStatusBarColor entirely -
-- hooking CompactUnitFrame_UpdateHealthColor alone doesn't catch it.
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

-- ElvUI re-asserts color through NamePlates:UpdateElement_HealthColor,
-- same choke-point shape as Plater's hook above.
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

-- Per-plate evaluation
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

    -- Re-applies only when the wanted mark changes, so a raid leader
    -- manually clearing the marker in-game isn't fought.
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

-- Cast-based highlight - reads whether the unit is casting, no spellID DB needed.
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

-- Events
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
        -- Force one rebuild after the world loads, since the options menu
        -- can build once too early, before KastaCDDB is restored.
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

-- Blizzard's threat/mouseover highlight logic recolors the health bar
-- through a path the hooks above can't catch; re-asserting every frame
-- is the only reliable fix.
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

-- /kcdplatesdebug - dumps raw saved state plus what's applied to visible plates.
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
