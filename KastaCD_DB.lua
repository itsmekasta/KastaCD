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
        enabled          = {},
        spellGroups      = {},
        groupPositionIdx = { 8, 8, 8 },
        offsetX          = 0,
        offsetY          = 0,
        iconSize         = 22,
        iconsPerRow      = 5,
        contentTypes     = {
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
        d.spellGroups  = KastaCDDB.spellGroups  or d.spellGroups
        if KastaCDDB.positionIdx then
            d.groupPositionIdx = {
                KastaCDDB.positionIdx,
                KastaCDDB.positionIdx,
                KastaCDDB.positionIdx,
            }
        end
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
        KastaCDDB.offsetX      = nil
        KastaCDDB.offsetY      = nil
        KastaCDDB.iconSize     = nil
        KastaCDDB.iconsPerRow  = nil
        KastaCDDB.contentTypes = nil
    end

    -- ── Sanitise active profile fields ───────────────────────
    local p = KastaCDDB.profiles[KastaCDDB.activeProfile]
    if type(p.enabled)          ~= "table"  then p.enabled          = {} end
    if type(p.spellGroups)      ~= "table"  then p.spellGroups      = {} end
    if type(p.groupPositionIdx) ~= "table"  then
        local old = type(p.positionIdx) == "number" and p.positionIdx or 8
        p.groupPositionIdx = { old, old, old }
        p.positionIdx = nil
    end
    for g = 1, SPELL_GROUP_COUNT do
        if type(p.groupPositionIdx[g]) ~= "number" then p.groupPositionIdx[g] = 8 end
        -- Index 1 was removed; remap old saves that used it
        if p.groupPositionIdx[g] == 1 then p.groupPositionIdx[g] = 8 end
    end
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
    KastaCDDB.enabled          = p.enabled
    KastaCDDB.spellGroups      = p.spellGroups
    KastaCDDB.groupPositionIdx = p.groupPositionIdx
    KastaCDDB.offsetX          = p.offsetX
    KastaCDDB.offsetY          = p.offsetY
    KastaCDDB.iconSize         = p.iconSize
    KastaCDDB.iconsPerRow      = p.iconsPerRow
    KastaCDDB.contentTypes     = p.contentTypes
end

-- Write the current top-level aliases back into the stored profile
-- so nothing is lost when switching profiles or on logout.
PersistActiveProfile = function()
    if type(KastaCDDB) ~= "table"
    or type(KastaCDDB.profiles) ~= "table"
    or type(KastaCDDB.activeProfile) ~= "string" then return end
    local p = KastaCDDB.profiles[KastaCDDB.activeProfile]
    if type(p) ~= "table" then return end
    p.enabled          = KastaCDDB.enabled          or p.enabled
    p.spellGroups      = KastaCDDB.spellGroups      or p.spellGroups
    p.groupPositionIdx = KastaCDDB.groupPositionIdx or p.groupPositionIdx
    p.offsetX          = KastaCDDB.offsetX          or p.offsetX
    p.offsetY          = KastaCDDB.offsetY          or p.offsetY
    p.iconSize         = KastaCDDB.iconSize         or p.iconSize
    p.iconsPerRow      = KastaCDDB.iconsPerRow      or p.iconsPerRow
    p.contentTypes     = KastaCDDB.contentTypes     or p.contentTypes
end

-- -------------------------------------------------------------
-- Content-type detection
-- -------------------------------------------------------------
local function GetCurrentContentType()
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
-- as party members cast. Used as an additive signal only; icons are shown
-- upfront from minLevel gating without needing a prior cast.
KNOWN_UNIT_SPELLS = {}

-- -------------------------------------------------------------
-- Spec cache  –  [guid] = specId (number) or false (unknown)
-- Populated lazily on first call per unit; cleared by ClearSpecCache()
-- which is called from ClearIcons() in Tracking.lua whenever the
-- group roster changes.
-- -------------------------------------------------------------
UNIT_SPEC_CACHE = {}

-- Request inspect data for a unit so the game populates
-- GetInspectSpecialization(). Safe to call repeatedly; the game
-- throttles the underlying query itself.
local function RequestInspect(unit)
    if NotifyInspect and CanInspect and CanInspect(unit) then
        NotifyInspect(unit)
    end
end

-- Return the cached spec ID for a unit, or nil if not yet known.
-- Also fires an inspect request so the cache fills in on the next
-- GROUP_ROSTER_UPDATE / RebuildIcons cycle.
function GetUnitSpec(unit)
    if unit == "player" then
        -- Local player: use the direct API, no inspect needed.
        if GetSpecialization then
            local idx = GetSpecialization()
            if idx then
                local specId = GetSpecializationInfo(idx)
                return specId
            end
        end
        return nil
    end

    local guid = UnitGUID(unit)
    if not guid then return nil end

    -- Return cached value if we already have it.
    if UNIT_SPEC_CACHE[guid] ~= nil then
        return UNIT_SPEC_CACHE[guid] or nil  -- false → nil (unknown)
    end

    -- Not cached yet — try to read it now.
    local specId = nil
    if GetInspectSpecialization then
        specId = GetInspectSpecialization(unit)
        if specId and specId == 0 then specId = nil end  -- 0 = not ready
    end

    if specId then
        UNIT_SPEC_CACHE[guid] = specId
    else
        -- Mark as "requested but not yet available" so we don't spam.
        UNIT_SPEC_CACHE[guid] = false
        RequestInspect(unit)
    end

    return specId
end

-- Call this whenever the group roster changes (from ClearIcons).
function ClearSpecCache()
    UNIT_SPEC_CACHE = {}
end

-- -------------------------------------------------------------
-- Spec filter helper
-- Returns true if the spell has no spec restriction, or if the
-- given specId matches one of the spell's allowed specs.
-- -------------------------------------------------------------
local function SpellMatchesSpec(data, specId)
    -- No specs field = shared by all specs of that class.
    if not data.specs then return true end
    -- Spec unknown yet — show the spell optimistically so the icon
    -- appears immediately; it will be hidden on the next RebuildIcons
    -- once the inspect data arrives and the spec is confirmed wrong.
    if not specId then return true end
    for _, s in ipairs(data.specs) do
        if s == specId then return true end
    end
    return false
end

function IsSpellKnownForUnit(unit, spellId)
    local data = SPELL_DB[spellId]
    if not data then return false end

    if unit == "player" then
        -- For the local player we can query the spellbook exactly.
        local checkId = spellId
        if FindSpellOverrideByID then
            local ov = FindSpellOverrideByID(spellId)
            if ov and ov ~= 0 then checkId = ov end
        end
        if IsPlayerSpell and (IsPlayerSpell(checkId) or IsPlayerSpell(spellId)) then
            -- Still filter by spec even for the player.
            local specId = GetUnitSpec("player")
            return SpellMatchesSpec(data, specId)
        end
        if IsSpellKnown and (IsSpellKnown(checkId) or IsSpellKnown(spellId)) then
            local specId = GetUnitSpec("player")
            return SpellMatchesSpec(data, specId)
        end
        return false
    end

    -- ── Non-player units ──────────────────────────────────────
    local lvl = UnitLevel(unit)
    if not lvl or lvl < 0 then return false end
    if lvl == 0 then lvl = 110 end  -- pserver quirk: 0 means max level

    -- Spec check: hide icons for wrong-spec spells.
    -- If the spec isn't known yet we show the spell optimistically
    -- (SpellMatchesSpec returns true when specId is nil) and correct
    -- on the next rebuild once inspect data comes in.
    local specId = GetUnitSpec(unit)
    if not SpellMatchesSpec(data, specId) then return false end

    -- Combat-log sighting confirms the spell exists for this unit
    -- regardless of level — catches talent spells with no minLevel.
    local guid = UnitGUID(unit)
    if guid and KNOWN_UNIT_SPELLS[guid] and KNOWN_UNIT_SPELLS[guid][spellId] then
        return true
    end

    -- No minLevel defined — assume available at the unit's current level.
    if not data.minLevel then return true end
    return lvl >= data.minLevel
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