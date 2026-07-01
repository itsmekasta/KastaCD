-- =============================================================
-- KastaCD_DB.lua
-- SavedVariables initialisation, profile CRUD, data migration,
-- content-type detection, and spell-availability helpers.
-- Depends on: KastaCD_SpellDB.lua
-- =============================================================

local DEFAULT_PROFILE_NAME = "Default"

-- Forward declarations so DB.lua internal functions can reference each other
-- and so Tracking/Events can call them as globals after this file loads.
ApplyActiveProfile  = nil   -- set below
PersistActiveProfile = nil  -- set below

-- -------------------------------------------------------------
-- Profile skeleton
-- -------------------------------------------------------------
function NewProfileData()
    return {
        enabled      = {},
        offsetX      = 0,
        offsetY      = 0,
        iconSize     = 22,
        iconsPerRow  = 5,
        contentTypes = {
            ["Open World"]=true, ["Dungeon"]=true,
            ["Arena"]=true,      ["Battleground"]=true
        },
    }
end

-- -------------------------------------------------------------
-- DB initialisation (called once on ADDON_LOADED / PLAYER_ENTERING_WORLD)
-- -------------------------------------------------------------
local KastaCDDBInitialized = false

function KastaCDInitDB()
    if KastaCDDBInitialized then return end
    KastaCDDBInitialized = true

    if type(KastaCDDB) ~= "table" then KastaCDDB = {} end
    if type(KastaCDDB.profiles) ~= "table" then KastaCDDB.profiles = {} end
    if type(KastaCDDB.profiles[DEFAULT_PROFILE_NAME]) ~= "table" then
        KastaCDDB.profiles[DEFAULT_PROFILE_NAME] = NewProfileData()
    end
    if type(KastaCDDB.activeProfile) ~= "string"
    or not KastaCDDB.profiles[KastaCDDB.activeProfile] then
        KastaCDDB.activeProfile = DEFAULT_PROFILE_NAME
    end

    -- ── One-time migration from the old flat layout ──────────
    if KastaCDDB.enabled and not KastaCDDB._migrated then
        local d = KastaCDDB.profiles[DEFAULT_PROFILE_NAME]
        d.enabled      = KastaCDDB.enabled      or d.enabled
        d.offsetX      = KastaCDDB.offsetX      or d.offsetX
        d.offsetY      = KastaCDDB.offsetY      or d.offsetY
        d.iconSize     = KastaCDDB.iconSize      or d.iconSize
        d.iconsPerRow  = KastaCDDB.iconsPerRow   or d.iconsPerRow
        d.contentTypes = KastaCDDB.contentTypes  or d.contentTypes
        -- Scrub old keys so migration never re-runs
        KastaCDDB._migrated    = true
        KastaCDDB.enabled      = nil
        KastaCDDB.spellGroups  = nil
        KastaCDDB.positionIdx  = nil
        KastaCDDB.groupPositionIdx = nil
        KastaCDDB.offsetX      = nil
        KastaCDDB.offsetY      = nil
        KastaCDDB.iconSize     = nil
        KastaCDDB.iconsPerRow  = nil
        KastaCDDB.contentTypes = nil
    end

    -- ── Sanitise active profile fields ───────────────────────
    local p = KastaCDDB.profiles[KastaCDDB.activeProfile]
    if type(p.enabled)      ~= "table"  then p.enabled      = {} end
    if type(p.offsetX)      ~= "number" then p.offsetX      = 0  end
    if type(p.offsetY)      ~= "number" then p.offsetY      = 0  end
    if type(p.iconSize)     ~= "number" then p.iconSize     = 22 end
    if type(p.iconsPerRow)  ~= "number" then p.iconsPerRow  = 5  end
    if type(p.contentTypes) ~= "table"  then
        p.contentTypes = {
            ["Open World"]=true, ["Dungeon"]=true,
            ["Arena"]=true,      ["Battleground"]=true,
        }
    end

    -- Global (non-profile) anchor settings — shared across all profiles
    if type(KastaCDDB.anchorPos)   ~= "table" then KastaCDDB.anchorPos    = {} end
    if KastaCDDB.anchorsLocked      == nil     then KastaCDDB.anchorsLocked = true end
    if KastaCDDB.showIconBorders       == nil then KastaCDDB.showIconBorders       = false end
    if KastaCDDB.medallionOutsidePvP   == nil then KastaCDDB.medallionOutsidePvP   = false end

    -- Interrupt anchor settings
    if type(KastaCDDB.intAnchor) ~= "table" then KastaCDDB.intAnchor = {} end
    local ia = KastaCDDB.intAnchor
    if ia.barWidth  == nil then ia.barWidth  = 200                    end
    if ia.barHeight == nil then ia.barHeight = 20                     end
    if ia.enabled   == nil then ia.enabled   = true                   end
    if ia.locked    == nil then ia.locked    = true                   end
    if ia.fontPath  == nil then ia.fontPath  = "Fonts\\FRIZQT__.TTF" end
    if ia.fontSize  == nil then ia.fontSize  = 10                     end

    PersistActiveProfile()
    ApplyActiveProfile()
end

-- -------------------------------------------------------------
-- Profile switching helpers
-- -------------------------------------------------------------

-- Copy the active profile's data into the top-level KastaCDDB
-- convenience aliases so the rest of the code can read them directly.
ApplyActiveProfile = function()
    local p = KastaCDDB.profiles[KastaCDDB.activeProfile]
    KastaCDDB.enabled      = p.enabled
    KastaCDDB.offsetX      = p.offsetX
    KastaCDDB.offsetY      = p.offsetY
    KastaCDDB.iconSize     = p.iconSize
    KastaCDDB.iconsPerRow  = p.iconsPerRow
    KastaCDDB.contentTypes = p.contentTypes
end

-- Write the current top-level aliases back into the stored profile
-- so nothing is lost when switching profiles or on logout.
PersistActiveProfile = function()
    if type(KastaCDDB) ~= "table"
    or type(KastaCDDB.profiles) ~= "table"
    or type(KastaCDDB.activeProfile) ~= "string" then return end
    local p = KastaCDDB.profiles[KastaCDDB.activeProfile]
    if type(p) ~= "table" then return end
    p.enabled      = KastaCDDB.enabled      or p.enabled
    p.offsetX      = KastaCDDB.offsetX      or p.offsetX
    p.offsetY      = KastaCDDB.offsetY      or p.offsetY
    p.iconSize     = KastaCDDB.iconSize     or p.iconSize
    p.iconsPerRow  = KastaCDDB.iconsPerRow  or p.iconsPerRow
    p.contentTypes = KastaCDDB.contentTypes or p.contentTypes
end

-- -------------------------------------------------------------
-- Content-type detection
-- -------------------------------------------------------------
function GetCurrentContentType()
    local inInstance, instanceType = IsInInstance()
    if not inInstance then return "Open World" end
    if instanceType == "arena" then return "Arena" end
    if instanceType == "pvp"   then return "Battleground" end
    if instanceType == "party" or instanceType == "raid" then return "Dungeon" end
    return "Open World"
end

function IsContentEnabled()
    return KastaCDDB.contentTypes[GetCurrentContentType()] == true
end

-- -------------------------------------------------------------
-- Spell-availability check
-- -------------------------------------------------------------
-- KNOWN_UNIT_SPELLS is populated by the combat log (KastaCD_CombatLog.lua)
-- as party members cast. For isTalent=true spells (see Classes\*.lua),
-- this is the ONLY way they're ever shown - see IsSpellKnownForUnit.
KNOWN_UNIT_SPELLS = {}

-- -------------------------------------------------------------
-- Spec cache  –  [guid] = specId (number) or nil (unknown)
--
-- ARCHITECTURE NOTE: this intentionally does NOT validate the
-- resolved specId against the unit's class the way earlier versions
-- did. That validation approach (CLASS_SPEC_IDS) was an attempt to
-- guard against transient bad reads from GetSpecializationInfo() /
-- GetInspectSpecialization(), but it just moved the failure mode
-- around: a rejected bad read still left the spell hidden until
-- some other event happened to retrigger a rebuild, which produced
-- the "random missing abilities" symptom.
--
-- Adopted instead: simply not validating at all, and instead
-- refreshing the spec read on every party member every ~1 second
-- via SpecPollTicker in KastaCD_Events.lua. Under this model a
-- single bad/stale read is never trusted for long - it's silently
-- overwritten by the next poll a second later, which in practice is
-- indistinguishable from "always correct" without ever needing
-- complex validation logic.
-- -------------------------------------------------------------
UNIT_SPEC_CACHE = {}

-- Called every ~1s per tracked unit by SpecPollTicker (Events.lua).
-- Always re-reads and overwrites the cache - no caching-until-stale
-- logic, no validation. Cheap, frequent, self-correcting.
function PollUnitSpec(unit)
    if unit == "player" then
        if GetSpecialization then
            local idx = GetSpecialization()
            if idx then
                local specId = GetSpecializationInfo(idx)
                if specId and specId ~= 0 then
                    UNIT_SPEC_CACHE["player"] = specId
                end
            end
        end
        return
    end

    local guid = UnitGUID(unit)
    if not guid then return end

    if GetInspectSpecialization then
        local specId = GetInspectSpecialization(unit)
        if specId and specId ~= 0 then
            UNIT_SPEC_CACHE[guid] = specId
        end
    end
end

-- Fires an inspect request for a unit (does not read the result -
-- the result arrives via INSPECT_READY, which Events.lua uses to
-- trigger an immediate RebuildIcons rather than waiting for the
-- next poll tick).
function RequestUnitInspect(unit)
    if unit == "player" then return end
    if NotifyInspect and CanInspect and CanInspect(unit) then
        NotifyInspect(unit)
    end
end

-- Returns the last-known specId for a unit, or nil if never resolved.
function GetUnitSpec(unit)
    if unit == "player" then
        return UNIT_SPEC_CACHE["player"]
    end
    local guid = UnitGUID(unit)
    return guid and UNIT_SPEC_CACHE[guid] or nil
end

-- Call this whenever the group roster changes (from ClearIcons).
function ClearSpecCache()
    -- Wipe in-place to avoid global reassignment taint.
    for k in pairs(UNIT_SPEC_CACHE) do UNIT_SPEC_CACHE[k] = nil end
end

-- -------------------------------------------------------------
-- Spec filter helper
-- Returns true if the spell has no spec restriction, or if the
-- given specId matches one of the spell's allowed specs.
--
-- specId unknown -> hide spec-gated spells rather than show them all.
-- GetInspectSpecialization/NotifyInspect frequently never resolves on
-- private servers, which used to leave specId nil indefinitely and (with
-- the old "show all" fallback) displayed every spec's abilities at once
-- for any unresolved unit. Spec is instead confirmed quickly in practice
-- via combat-log cast inference (see KastaCD_CombatLog.lua) or the normal
-- inspect poll when it does work; until one of those resolves it, a
-- spec-restricted spell simply isn't shown - matching the isTalent
-- ground-truth-only philosophy used elsewhere in IsSpellKnownForUnit.
-- -------------------------------------------------------------
local function SpellMatchesSpec(data, specId)
    if not data.specs then return true end
    if not specId then return false end
    for _, s in ipairs(data.specs) do
        if s == specId then return true end
    end
    return false
end

-- -------------------------------------------------------------
-- IsSpellKnownForUnit
--
-- isTalent=true spells (see Classes\*.lua header comment) take an
-- entirely different path: they are NEVER shown based on spec/level
-- guessing, full stop. They only appear once KNOWN_UNIT_SPELLS has
-- recorded an actual combat-log sighting of that exact unit casting
-- that exact spell - ground truth, not inference. This is what
-- structurally eliminates "shows abilities a spec doesn't actually
-- have," since a talent row's real owner is never in doubt once
-- they've been seen using it, and nobody else's icon ever lights up
-- for it incorrectly in the meantime.
--
-- Baseline (non-talent) abilities use simple level + (if specs is
-- set) current-spec gating, same as before, just backed by the
-- simpler always-fresh spec polling above instead of validated/
-- cached reads.
-- -------------------------------------------------------------
function IsSpellKnownForUnit(unit, spellId)
    local data = SPELL_DB[spellId]
    if not data then return false end

    -- Class-agnostic spells (e.g. PvP Medallion, class="ALL") are considered
    -- known for every unit — the enabled toggle in Settings is the only gate.
    if data.class == "ALL" then return true end

    if unit == "player" then
        local checkId = spellId
        if FindSpellOverrideByID then
            local ov = FindSpellOverrideByID(spellId)
            if ov and ov ~= 0 then checkId = ov end
        end
        local known = (IsPlayerSpell and (IsPlayerSpell(checkId) or IsPlayerSpell(spellId)))
            or (IsSpellKnown and (IsSpellKnown(checkId) or IsSpellKnown(spellId)))
        if not known then return false end

        local specId = GetUnitSpec("player")
        return SpellMatchesSpec(data, specId)
    end

    -- ── Non-player units ──────────────────────────────────────
    local lvl = UnitLevel(unit)
    if not lvl or lvl < 0 then return false end
    if lvl == 0 then lvl = 1 end

    -- Combat-log sighting confirms the spell exists for this unit
    -- regardless of level/spec; checked as a fast positive path.
    local guid = UnitGUID(unit)
    if guid and KNOWN_UNIT_SPELLS[guid] and KNOWN_UNIT_SPELLS[guid][spellId] then
        return true
    end

    local levelOk = (not data.minLevel) or (lvl >= data.minLevel)
    if not levelOk then return false end

    local specId = GetUnitSpec(unit)
    return SpellMatchesSpec(data, specId)
end

-- -------------------------------------------------------------
-- Enabled-spell accessor (used by Tracking and UI)
-- -------------------------------------------------------------
function GetEnabledSpells()
    local out = {}
    for sid, data in pairs(SPELL_DB) do
        if KastaCDDB.enabled[sid] then out[sid] = data end
    end
    return out
end