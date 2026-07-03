-- =============================================================
-- KastaCD_MobCount.lua
--
-- Shows each Mythic+ trash mob's "enemy forces" completion percentage
-- next to its nameplate. GottaGoFast (Scanned/AddOns/GottaGoFast) shows
-- this same number in the mouseover tooltip during a Challenge Mode run
-- (Core.lua's UPDATE_MOUSEOVER_UNIT handler) - this ports that same
-- lookup to nameplates instead of the tooltip.
--
-- The actual per-dungeon mob weight data comes from
-- LibObjectiveProgress-1.0 (libs/LibObjectiveProgress-1.0), a standalone
-- LibStub library by MMOSimca that GottaGoFast itself depends on for
-- this exact feature - vendored here rather than reimplementing
-- GottaGoFast's own bespoke data. Its data file states plainly: "You may
-- use this data in any form for any purpose without my permission."
--
-- Depends on: libs/LibObjectiveProgress-1.0 (loaded via KastaCD_libs.xml).
-- =============================================================

local LOP = LibStub and LibStub("LibObjectiveProgress-1.0", true)

function GetMobCountDB()
    KastaCDDB = KastaCDDB or {}
    local db = KastaCDDB.mobCount
    if not db then
        db = {}
        KastaCDDB.mobCount = db
    end
    if db.enabled == nil then db.enabled = true end
    return db
end

local function IsMobCountEnabled()
    return LOP ~= nil and GetMobCountDB().enabled == true
end

-- -------------------------------------------------------------
-- Current Mythic+ run state - refreshed on zone/challenge events. Same
-- fields GottaGoFast's own WhereAmI()/HasTeeming() derive:
--   instanceID   - GetInstanceInfo()'s 8th return, what LOP:GetNPCWeightByMap
--                  actually keys weight data by (NOT C_ChallengeMode's
--                  own mapID, a different number space).
--   isUpperKarazhan - Return to Karazhan's "Upper" wing shares an
--                  instanceID with "Lower", so the library needs an
--                  explicit flag to pick the right weight table -
--                  cmID 234 is that special case (see the library's own
--                  comment in LibObjectiveProgress-1.0.lua).
-- -------------------------------------------------------------
local TEEMING_AFFIX_ID     = 5
local UPPER_KARAZHAN_CM_ID = 234

local runState = { inCM = false, instanceID = nil, isTeeming = false, isUpperKarazhan = false }

local function RefreshRunState()
    local _, _, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
    local cmMapID = C_ChallengeMode.GetActiveChallengeMapID()

    runState.inCM           = (difficultyID == 8) and (cmMapID ~= nil)
    runState.instanceID     = instanceID
    runState.isUpperKarazhan = (cmMapID == UPPER_KARAZHAN_CM_ID)

    runState.isTeeming = false
    if cmMapID then
        local _, affixIDs = C_ChallengeMode.GetActiveKeystoneInfo()
        if affixIDs then
            for _, id in ipairs(affixIDs) do
                if id == TEEMING_AFFIX_ID then
                    runState.isTeeming = true
                    break
                end
            end
        end
    end
end

-- -------------------------------------------------------------
-- Per-plate percentage text - one reusable FontString per active
-- nameplate unit token, anchored to the LEFT edge of the plate. Kept as
-- an independent UIParent-owned overlay (never parented to the plate
-- itself) so nothing here ever calls a setter on a nameplate frame -
-- SetPoint targeting the plate is a read of its position, not a
-- modification of it, so this stays taint-free regardless of whatever
-- nameplate addon (TidyPlates, etc.) owns the actual plate skin.
-- -------------------------------------------------------------
local plateTexts = {}   -- [unitToken] = fontstring

local function GetOrCreatePlateText(unitToken)
    local fs = plateTexts[unitToken]
    if fs then return fs end

    fs = UIParent:CreateFontString(nil, "OVERLAY")
    fs:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    fs:SetTextColor(1, 0.82, 0, 1)
    plateTexts[unitToken] = fs
    return fs
end

local function HidePlate(unitToken)
    local fs = plateTexts[unitToken]
    if fs then fs:Hide() end
end

local function UpdatePlate(unitToken)
    if not unitToken then return end

    if not IsMobCountEnabled() or not runState.inCM
        or not UnitExists(unitToken) or not UnitCanAttack("player", unitToken) or UnitIsDead(unitToken)
    then
        HidePlate(unitToken)
        return
    end

    local guid = UnitGUID(unitToken)
    local npcID = guid and tonumber(guid:match("^Creature%-0%-%d+%-%d+%-%d+%-(%d+)%-"))
    if not npcID then
        HidePlate(unitToken)
        return
    end

    local weight = LOP:GetNPCWeightByMap(runState.instanceID, npcID, runState.isTeeming, runState.isUpperKarazhan)
    if not weight then
        HidePlate(unitToken)
        return
    end

    local plate = C_NamePlate.GetNamePlateForUnit(unitToken)
    if not plate then
        HidePlate(unitToken)
        return
    end

    local fs = GetOrCreatePlateText(unitToken)
    fs:SetText(string.format("%.2f%%", weight))
    fs:ClearAllPoints()
    fs:SetPoint("RIGHT", plate, "RIGHT", 15, 8)
    fs:Show()
end

-- -------------------------------------------------------------
-- Events
-- -------------------------------------------------------------
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("ZONE_CHANGED_NEW_AREA")
watcher:RegisterEvent("CHALLENGE_MODE_START")
watcher:RegisterEvent("CHALLENGE_MODE_COMPLETED")
watcher:RegisterEvent("CHALLENGE_MODE_RESET")
watcher:RegisterEvent("NAME_PLATE_UNIT_ADDED")
watcher:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
watcher:SetScript("OnEvent", function(_, event, unitToken)
    if event == "NAME_PLATE_UNIT_ADDED" then
        UpdatePlate(unitToken)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        HidePlate(unitToken)
    else
        RefreshRunState()
        -- Re-evaluate every currently visible plate against the fresh
        -- run state (e.g. the run just started/ended, or affixes only
        -- just resolved).
        for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
            if plate.namePlateUnitToken then
                UpdatePlate(plate.namePlateUnitToken)
            end
        end
    end
end)

RefreshRunState()

-- Rebuilds every visible plate immediately after a settings change
-- (Enable toggle) instead of waiting for the next nameplate event.
function RefreshMobCountPlates()
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        if plate.namePlateUnitToken then
            UpdatePlate(plate.namePlateUnitToken)
        end
    end
end
