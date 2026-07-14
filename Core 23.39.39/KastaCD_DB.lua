-- KastaCD_DB.lua - SavedVariables init, profile CRUD, data migration,
-- content-type detection, spell-availability helpers.
-- Depends on: KastaCD_SpellDB.lua

local DEFAULT_PROFILE_NAME = "Default"

-- Forward declarations so Tracking/Events can call these as globals.
ApplyActiveProfile  = nil
PersistActiveProfile = nil

function NewProfileData()
    return {
        enabled      = {},
        offsetX      = 0,
        offsetY      = 0,
        iconSize     = 22,
        iconsPerRow  = 5,
        -- Separate raid1-40 offset/size, used when "Show in Raid Groups" is on.
        raidOffsetX     = 0,
        raidOffsetY     = 0,
        raidIconSize    = 22,
        raidIconsPerRow = 5,
        contentTypes = {
            ["Open World"]=true, ["Dungeon"]=true,
            ["Arena"]=true,      ["Battleground"]=true
        },
        -- GetIntDB()/GetCCDB() lazily fill these in on first touch.
        intAnchor = {},
        ccAnchor  = {},
    }
end

-- Called once on ADDON_LOADED/PLAYER_ENTERING_WORLD.
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

    -- One-time cleanup: revert a leftover raid-style-party-frames CVar
    -- flip left by an early, since-removed Test Mode feature. Runs once ever.
    if not KastaCDDB._partyTestModeCVarCleanupDone then
        KastaCDDB._partyTestModeCVarCleanupDone = true
        if GetCVar and SetCVar and GetCVar("useCompactPartyFrames") == "1" then
            SetCVar("useCompactPartyFrames", "0")
        end
    end

    -- ── Sanitise active profile fields ───────────────────────
    local p = KastaCDDB.profiles[KastaCDDB.activeProfile]
    if type(p.enabled)      ~= "table"  then p.enabled      = {} end
    if type(p.offsetX)      ~= "number" then p.offsetX      = 0  end
    if type(p.offsetY)      ~= "number" then p.offsetY      = 0  end
    if type(p.iconSize)     ~= "number" then p.iconSize     = 22 end
    if type(p.iconsPerRow)  ~= "number" then p.iconsPerRow  = 5  end
    if type(p.raidOffsetX)     ~= "number" then p.raidOffsetX     = 0  end
    if type(p.raidOffsetY)     ~= "number" then p.raidOffsetY     = 0  end
    if type(p.raidIconSize)    ~= "number" then p.raidIconSize    = 22 end
    if type(p.raidIconsPerRow) ~= "number" then p.raidIconsPerRow = 5  end
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
    -- Global (non-profile) toggle, deliberately not routed through the
    -- profile copy pipeline (which uses `or` and would silently discard an explicit false).
    if KastaCDDB.showInRaidGroups      == nil then KastaCDDB.showInRaidGroups      = false end
    -- Migrate Interrupt/CC tracker settings (used to be global) into the
    -- active profile so each profile can carry its own setup. Runs once ever.
    if not KastaCDDB._trackerAnchorsMigrated then
        KastaCDDB._trackerAnchorsMigrated = true
        if type(KastaCDDB.intAnchor) == "table" and type(p.intAnchor) ~= "table" then
            p.intAnchor = KastaCDDB.intAnchor
        end
        if type(KastaCDDB.ccAnchor) == "table" and type(p.ccAnchor) ~= "table" then
            p.ccAnchor = KastaCDDB.ccAnchor
        end
    end

    -- Interrupt anchor settings (per-profile - see migration above)
    if type(p.intAnchor) ~= "table" then p.intAnchor = {} end
    local ia = p.intAnchor
    if ia.barWidth  == nil then ia.barWidth  = 200                    end
    if ia.barHeight == nil then ia.barHeight = 20                     end
    if ia.enabled   == nil then ia.enabled   = true                   end
    if ia.locked    == nil then ia.locked    = true                   end
    if ia.fontPath  == nil then ia.fontPath  = "Fonts\\FRIZQT__.TTF" end
    if ia.fontSize  == nil then ia.fontSize  = 10                     end
    if ia.testMode  == nil then ia.testMode  = false                  end
    if ia.texturePath == nil then ia.texturePath = "Interface\\TargetingFrame\\UI-StatusBar" end
    if ia.hideBorder == nil then ia.hideBorder = false                end
    if ia.clickThrough == nil then ia.clickThrough = false            end
    if type(ia.contentTypes) ~= "table" then
        ia.contentTypes = {
            ["Open World"]=true, ["Dungeon"]=true,
            ["Arena"]=true,      ["Battleground"]=true,
        }
    end

    -- Crowd-control anchor settings (per-profile - see migration above)
    if type(p.ccAnchor) ~= "table" then p.ccAnchor = {} end
    local ca = p.ccAnchor
    if ca.barWidth  == nil then ca.barWidth  = 200                    end
    if ca.barHeight == nil then ca.barHeight = 20                     end
    if ca.enabled   == nil then ca.enabled   = true                   end
    if ca.locked    == nil then ca.locked    = true                   end
    if ca.testMode  == nil then ca.testMode  = false                  end
    if ca.fontPath  == nil then ca.fontPath  = "Fonts\\FRIZQT__.TTF" end
    if ca.fontSize  == nil then ca.fontSize  = 10                     end
    if ca.texturePath == nil then ca.texturePath = "Interface\\TargetingFrame\\UI-StatusBar" end
    if ca.hideBorder == nil then ca.hideBorder = false                end
    if ca.clickThrough == nil then ca.clickThrough = false            end
    if type(ca.contentTypes) ~= "table" then
        ca.contentTypes = {
            ["Open World"]=true, ["Dungeon"]=true,
            ["Arena"]=true,      ["Battleground"]=true,
        }
    end

    PersistActiveProfile()
    ApplyActiveProfile()
end

-- Profile switching helpers

-- Copies the active profile's data into the top-level KastaCDDB aliases.
ApplyActiveProfile = function()
    local p = KastaCDDB.profiles[KastaCDDB.activeProfile]
    KastaCDDB.enabled      = p.enabled
    KastaCDDB.offsetX      = p.offsetX
    KastaCDDB.offsetY      = p.offsetY
    KastaCDDB.iconSize     = p.iconSize
    KastaCDDB.iconsPerRow  = p.iconsPerRow
    KastaCDDB.raidOffsetX     = p.raidOffsetX
    KastaCDDB.raidOffsetY     = p.raidOffsetY
    KastaCDDB.raidIconSize    = p.raidIconSize
    KastaCDDB.raidIconsPerRow = p.raidIconsPerRow
    KastaCDDB.contentTypes = p.contentTypes
    if type(p.intAnchor) ~= "table" then p.intAnchor = {} end
    if type(p.ccAnchor)  ~= "table" then p.ccAnchor  = {} end
    KastaCDDB.intAnchor = p.intAnchor
    KastaCDDB.ccAnchor  = p.ccAnchor

    -- Jump already-created anchor frames to this profile's saved position now
    -- (EnsureIntAnchor/EnsureCCAnchor only apply savedX/Y once, at creation).
    if p.intAnchor.savedX and p.intAnchor.savedY and type(SetIntAnchorPos) == "function" then
        SetIntAnchorPos(p.intAnchor.savedX, p.intAnchor.savedY)
    end
    if p.ccAnchor.savedX and p.ccAnchor.savedY and type(SetCCAnchorPos) == "function" then
        SetCCAnchorPos(p.ccAnchor.savedX, p.ccAnchor.savedY)
    end
end

-- Writes the current top-level aliases back into the stored profile.
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
    p.raidOffsetX     = KastaCDDB.raidOffsetX     or p.raidOffsetX
    p.raidOffsetY     = KastaCDDB.raidOffsetY     or p.raidOffsetY
    p.raidIconSize    = KastaCDDB.raidIconSize    or p.raidIconSize
    p.raidIconsPerRow = KastaCDDB.raidIconsPerRow or p.raidIconsPerRow
    p.contentTypes = KastaCDDB.contentTypes or p.contentTypes
    p.intAnchor    = KastaCDDB.intAnchor    or p.intAnchor
    p.ccAnchor     = KastaCDDB.ccAnchor     or p.ccAnchor
end

-- Content-type detection
function GetCurrentContentType()
    local inInstance, instanceType = IsInInstance()
    if not inInstance then return "Open World" end
    if instanceType == "arena" then return "Arena" end
    if instanceType == "pvp"   then return "Battleground" end
    if instanceType == "party" or instanceType == "raid" then return "Dungeon" end
    return "Open World"
end

-- Takes an explicit contentTypes table so Interrupt/CC trackers can each
-- have their own independent "Active in:" choice.
function IsContentEnabledFor(contentTypes)
    if type(contentTypes) ~= "table" then return true end
    return contentTypes[GetCurrentContentType()] == true
end

function IsContentEnabled()
    return IsContentEnabledFor(KastaCDDB.contentTypes)
end

-- Spell-availability check
-- KNOWN_UNIT_SPELLS is populated by the combat log (KastaCD_CombatLog.lua).
-- For isTalent=true spells this is the only way they're ever shown.
KNOWN_UNIT_SPELLS = {}

-- Spec cache: [guid] = specId or nil. No validation against class - an
-- earlier validation approach just delayed bad reads instead of fixing
-- them. Instead, PollUnitSpec re-reads every ~1s, so a bad read is
-- overwritten a second later.
UNIT_SPEC_CACHE = {}

-- Called every ~1s per tracked unit by SpecPollTicker (Events.lua).
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

-- Fires an inspect request; result arrives via INSPECT_READY (Events.lua).
function RequestUnitInspect(unit)
    if unit == "player" then return end
    if NotifyInspect and CanInspect and CanInspect(unit) then
        NotifyInspect(unit)
    end
end

-- Confirms a unit's actual talent picks via the inspect API into
-- KNOWN_UNIT_SPELLS, the same ground-truth cache a witnessed cast
-- writes to - lets an isTalent spell show up the moment inspect
-- confirms it, not just after it's cast. Scans all 7 tiers x 3 columns
-- rather than a hardcoded tier/column table. Also callable with
-- unit=="player" (reads your own talent frame directly - more
-- authoritative than IsPlayerSpell/IsSpellKnown, which can lag behind a
-- real respec on this server). Clears any previously-confirmed pick not
-- reconfirmed by this scan before adding the current one, so a respec
-- doesn't leave a stale pick stuck forever. Also calls
-- ClearCompetingCCTalents for each newly confirmed pick (defense in depth).
function ScanUnitTalents(unit)
    if not GetTalentInfo then return false end

    local guid = (unit == "player") and UnitGUID("player") or UnitGUID(unit)
    if not guid then return false end

    local isInspect = (unit ~= "player")

    local confirmed = {}
    for tier = 1, 7 do
        for column = 1, 3 do
            -- GetTalentInfo returns 7 values; missing the "column"
            -- placeholder here used to shift selected/spellId by one slot.
            local _, _, _, _, selected, _, spellId
            if isInspect then
                _, _, _, _, selected, _, spellId = GetTalentInfo(tier, column, 1, true, unit)
            else
                _, _, _, _, selected, _, spellId = GetTalentInfo(tier, column, 1, false, "player")
            end
            if selected and spellId and spellId ~= 0 then
                confirmed[spellId] = true
            end
        end
    end

    KNOWN_UNIT_SPELLS[guid] = KNOWN_UNIT_SPELLS[guid] or {}
    local known   = KNOWN_UNIT_SPELLS[guid]
    local changed = false

    for sid in pairs(known) do
        local data = (type(SPELL_DB) == "table" and SPELL_DB[sid]) or (type(CC_SPELLS) == "table" and CC_SPELLS[sid])
        if data and data.isTalent and not confirmed[sid] then
            known[sid] = nil
            changed = true
        end
    end

    for spellId in pairs(confirmed) do
        if not known[spellId] then
            known[spellId] = true
            changed = true
        end
        if type(ClearCompetingCCTalents) == "function" then
            ClearCompetingCCTalents(guid, spellId)
        end
    end

    return changed
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

-- Spec filter: true if spell has no spec restriction or specId matches.
-- Unknown specId hides spec-gated spells rather than showing them all.
local function SpellMatchesSpec(data, specId)
    if not data.specs then return true end
    if not specId then return false end
    for _, s in ipairs(data.specs) do
        if s == specId then return true end
    end
    return false
end

-- isTalent=true spells only show once KNOWN_UNIT_SPELLS has recorded an
-- actual combat-log sighting - ground truth, not spec/level guessing.
-- Baseline abilities use simple level + spec gating instead.
function IsSpellKnownForUnit(unit, spellId)
    local data = SPELL_DB[spellId]
    if not data then return false end

    -- Class-agnostic spells (e.g. PvP Medallion, class="ALL") are considered
    -- known for every unit — the enabled toggle in Settings is the only gate.
    if data.class == "ALL" then return true end

    if unit == "player" then
        -- isTalent entries trust the GetTalentInfo-backed KNOWN_UNIT_SPELLS
        -- cache over raw IsPlayerSpell/IsSpellKnown - those two can both
        -- report "known" for two mutually-exclusive picks after a respec.
        if data.isTalent then
            local guid = UnitGUID("player")
            local known = guid and KNOWN_UNIT_SPELLS[guid]
            return known and known[spellId] == true
        end

        local checkId = spellId
        if FindSpellOverrideByID then
            local ov = FindSpellOverrideByID(spellId)
            if ov and ov ~= 0 then checkId = ov end
        end
        local known = (IsPlayerSpell and (IsPlayerSpell(checkId) or IsPlayerSpell(spellId)))
            or (IsSpellKnown and (IsSpellKnown(checkId) or IsSpellKnown(spellId)))
        -- Not cross-checked against GetUnitSpec: IsPlayerSpell/IsSpellKnown
        -- already reflects the actual current spec on its own.
        return known
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

-- Enabled-spell accessor (used by Tracking and UI)
function GetEnabledSpells()
    local out = {}
    for sid, data in pairs(SPELL_DB) do
        if KastaCDDB.enabled[sid] then out[sid] = data end
    end
    return out
end