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
        -- Separate offset/size/per-row settings used only for raid1-40
        -- units when Settings > "Show in Raid Groups" is on (see
        -- KastaCD_DB.lua's global showInRaidGroups + IsRaidUnit in
        -- KastaCD_Tracking.lua) - a 40-member raid usually wants smaller,
        -- differently-placed icons than a 5-person party, so this is
        -- deliberately its own set of values rather than reusing the
        -- party ones above. Defaults match the party values exactly so
        -- behavior is identical until a user actually tweaks them.
        raidOffsetX     = 0,
        raidOffsetY     = 0,
        raidIconSize    = 22,
        raidIconsPerRow = 5,
        contentTypes = {
            ["Open World"]=true, ["Dungeon"]=true,
            ["Arena"]=true,      ["Battleground"]=true
        },
        -- Interrupt/CC tracker bar settings (position, size, font, per-spell
        -- toggles, etc.) - GetIntDB()/GetCCDB() in their respective modules
        -- lazily fill in every field the first time each is touched, so an
        -- empty table here is a complete, valid starting point.
        intAnchor = {},
        ccAnchor  = {},
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

    -- ── One-time cleanup: revert a leftover raid-style-party-frames CVar
    -- flip left behind by an early, since-fully-removed Test Mode feature
    -- that toggled it on to preview against. CVars live in the client's
    -- own WTF settings, not in this addon's SavedVariables, so removing
    -- that feature's code didn't undo the flip on anyone who'd tried it -
    -- their client keeps showing Blizzard's raid-style party frame
    -- background even with the addon's code long gone. Runs once ever per
    -- account (never re-touches it again after this, so a user's own
    -- later, unrelated choice to enable raid-style frames is respected).
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
    -- Off by default: Party Cooldown icons are hidden entirely in raid-sized
    -- groups (see IsInPartyOnly in KastaCD_Tracking.lua) since there'd
    -- normally be too many members to anchor icons to usefully. A global
    -- (non-profile) toggle, same as the other simple on/off flags above -
    -- deliberately NOT threaded through NewProfileData/ApplyActiveProfile/
    -- PersistActiveProfile like contentTypes is, because that copy pipeline
    -- uses `KastaCDDB.x or p.x` and `or` silently discards an explicit
    -- `false` (0 is truthy in Lua, but false isn't) - fine for the numeric/
    -- table fields it already handles, but it would quietly undo this
    -- setting the moment it's turned off.
    if KastaCDDB.showInRaidGroups      == nil then KastaCDDB.showInRaidGroups      = false end
    -- Glow color shared by every glow in the addon (see ShowProcGlow/
    -- HideProcGlow in KastaCD_Tracking.lua) - nil means "use stock
    -- Blizzard gold", not stored as a default table so a fresh install
    -- and an explicit "reset" both mean the exact same thing.
    -- ── One-time migration: Interrupt/CC tracker bar settings used to
    -- live directly on KastaCDDB.intAnchor/.ccAnchor, shared globally
    -- across every profile - switching or importing a profile never
    -- touched them, only Party Cooldowns' own fields did. Move whatever's
    -- there into the currently-active profile (the one it was actually
    -- being used for) so each profile can carry its own tracker setup
    -- from here on. Runs once ever per account; a profile created after
    -- this point starts from GetIntDB()/GetCCDB()'s own lazy defaults.
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
    KastaCDDB.raidOffsetX     = p.raidOffsetX
    KastaCDDB.raidOffsetY     = p.raidOffsetY
    KastaCDDB.raidIconSize    = p.raidIconSize
    KastaCDDB.raidIconsPerRow = p.raidIconsPerRow
    KastaCDDB.contentTypes = p.contentTypes
    if type(p.intAnchor) ~= "table" then p.intAnchor = {} end
    if type(p.ccAnchor)  ~= "table" then p.ccAnchor  = {} end
    KastaCDDB.intAnchor = p.intAnchor
    KastaCDDB.ccAnchor  = p.ccAnchor

    -- Force the already-created anchor frames to jump to this profile's
    -- own saved position right away. EnsureIntAnchor/EnsureCCAnchor only
    -- ever apply savedX/savedY once, at first-ever creation - without
    -- this, switching to a profile with a different saved position
    -- wouldn't visibly move a tracker bar that's already on screen until
    -- the next /reload. Skipped when the profile's anchor was never
    -- manually positioned (still nil, sitting at its default).
    if p.intAnchor.savedX and p.intAnchor.savedY and type(SetIntAnchorPos) == "function" then
        SetIntAnchorPos(p.intAnchor.savedX, p.intAnchor.savedY)
    end
    if p.ccAnchor.savedX and p.ccAnchor.savedY and type(SetCCAnchorPos) == "function" then
        SetCCAnchorPos(p.ccAnchor.savedX, p.ccAnchor.savedY)
    end
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
    p.raidOffsetX     = KastaCDDB.raidOffsetX     or p.raidOffsetX
    p.raidOffsetY     = KastaCDDB.raidOffsetY     or p.raidOffsetY
    p.raidIconSize    = KastaCDDB.raidIconSize    or p.raidIconSize
    p.raidIconsPerRow = KastaCDDB.raidIconsPerRow or p.raidIconsPerRow
    p.contentTypes = KastaCDDB.contentTypes or p.contentTypes
    p.intAnchor    = KastaCDDB.intAnchor    or p.intAnchor
    p.ccAnchor     = KastaCDDB.ccAnchor     or p.ccAnchor
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

-- Generalised form: takes an explicit contentTypes table instead of always
-- reading the main icon tracker's KastaCDDB.contentTypes, so the Interrupt
-- and Crowd Control trackers can each have their own independent "Active
-- in:" choice (KastaCDDB.intAnchor.contentTypes / .ccAnchor.contentTypes)
-- instead of all three being bound to the same shared setting.
function IsContentEnabledFor(contentTypes)
    if type(contentTypes) ~= "table" then return true end
    return contentTypes[GetCurrentContentType()] == true
end

function IsContentEnabled()
    return IsContentEnabledFor(KastaCDDB.contentTypes)
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

-- -------------------------------------------------------------
-- ScanUnitTalents  –  confirms a unit's actual talent picks via the
-- inspect API, writing results into KNOWN_UNIT_SPELLS - the exact same
-- ground-truth cache a real witnessed combat-log cast writes to. This
-- lets a talent-gated spell (isTalent=true in SPELL_DB/CC_SPELLS, e.g.
-- Storm Bolt, Mighty Bash) show up the moment inspect confirms it's
-- talented, instead of only after the first time it's actually cast.
--
-- Called from Events.lua's INSPECT_READY handler, right alongside
-- PollUnitSpec - same trigger, same "only useful once an inspect
-- request has actually resolved" caveat. GetTalentInfo(tier, column, 1,
-- true, unit) is scanned across all 7 tiers x 3 columns rather than
-- using a hardcoded tier/column-per-spell table, so this doesn't depend
-- on manually sourced (and easy to get wrong) Legion talent-tree layout
-- data - it just reads back whatever spellId the game itself reports
-- for each selected talent.
--
-- Also callable with unit == "player" (isInspect=false, reads your own
-- talent frame directly) - originally skipped on the assumption that
-- IsPlayerSpell/IsSpellKnown already covered the player's own talents
-- reliably (see IsSpellKnownForUnit), but live testing showed those can
-- ALSO lag behind a real respec on this server for a currently-selected
-- talent row, not just the spec-index API. GetTalentInfo reads the
-- talent frame's actual current selection directly, and structurally
-- can't report two selections in the same row, so it's the more
-- authoritative source for talent-gated CC_SPELLS entries specifically -
-- see KastaCD_Sync.lua's BuildSyncPayload, which now calls this before
-- building the outgoing payload instead of trusting IsPlayerSpell alone
-- for isTalent entries.
--
-- Clears any previously-confirmed talent pick that ISN'T reconfirmed by
-- THIS scan before adding the current one - mirrors OmniCD's own
-- InspectUnit/InspectUser (wipe(info.talentData) before repopulating)
-- and the same fix already applied to KastaCD_Sync.lua's
-- HandleSyncMessage. Without this, swapping to a competing talent in the
-- same row (e.g. Bladestorm -> a different Arms option, or respeccing
-- away from Arms entirely) left the OLD pick stuck in KNOWN_UNIT_SPELLS
-- forever, since this only ever ADDED before - and because this function
-- runs independently on its own inspect cadence (Events.lua), it kept
-- re-polluting KNOWN_UNIT_SPELLS with the stale pick right after
-- anything else (like Sync) correctly cleared it, a tug-of-war between
-- the two mechanisms. Only clears entries that are THEMSELVES
-- talent-gated (isTalent=true) in SPELL_DB/CC_SPELLS - never touches a
-- real witnessed cast of a baseline ability, unrelated to this scan.
--
-- ALSO calls ClearCompetingCCTalents (KastaCD_CC.lua) for each newly
-- (re)confirmed pick - defense in depth for mutually-exclusive CC_SPELLS
-- rows (e.g. Shockwave vs Storm Bolt): GetTalentInfo already structurally
-- can't return two selections for the same row, so this should be a
-- no-op in practice, but keeps every write site consistent regardless.
-- -------------------------------------------------------------
function ScanUnitTalents(unit)
    if not GetTalentInfo then return false end

    local guid = (unit == "player") and UnitGUID("player") or UnitGUID(unit)
    if not guid then return false end

    local isInspect = (unit ~= "player")

    local confirmed = {}
    for tier = 1, 7 do
        for column = 1, 3 do
            -- GetTalentInfo returns 7 values: name, icon, tier, column,
            -- selected, available, spellID. This used to only capture 6
            -- variables (missing a placeholder for "column"), which silently
            -- shifted every value after it by one - "selected" below was
            -- actually reading the real "column" number (always truthy, so
            -- every talent looked "selected"), and "spellId" was reading the
            -- real "available" boolean instead of the real spellID, so
            -- confirmed[spellId] never matched a real spell ID. This made
            -- isTalent-gated spells (Ravager, Storm Bolt, Mighty Bash, etc.)
            -- never show as a known/idle icon via inspect - only a real
            -- witnessed cast (a completely separate code path) ever lit
            -- them up.
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
        -- isTalent entries: trust the GetTalentInfo-backed KNOWN_UNIT_SPELLS
        -- cache (kept fresh by ScanUnitTalents("player"), called from
        -- KastaCD_Sync.lua's BuildSyncPayload) over raw IsPlayerSpell/
        -- IsSpellKnown - live testing showed those two can BOTH report
        -- "known" simultaneously for two mutually-exclusive picks in the
        -- same talent row for a stretch after respeccing (e.g. Shockwave
        -- and Storm Bolt both true at once), which showed both on the
        -- player's own screen instead of just the current pick.
        -- GetTalentInfo reads the talent frame directly and structurally
        -- can't report two selections for one row.
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
        -- Deliberately NOT cross-checked against GetUnitSpec("player")/
        -- SpellMatchesSpec below: IsPlayerSpell/IsSpellKnown already
        -- reflects your ACTUAL current spec (Blizzard adds/removes
        -- spec-exclusive spells from your spellbook the moment you swap),
        -- so a "known" result is already spec-correct on its own. Adding
        -- a second check against UNIT_SPEC_CACHE["player"] only ever made
        -- this WORSE - GetSpecialization()/GetSpecializationInfo() can
        -- fail to resolve on some servers (see the spec-inference comment
        -- in KastaCD_CombatLog.lua), which used to hide an already-
        -- confirmed-known, spec-restricted spell until something else
        -- happened to populate the spec cache.
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