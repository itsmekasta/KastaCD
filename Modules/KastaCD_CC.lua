-- =============================================================
-- KastaCD_CC.lua
-- Independent crowd-control cooldown tracker.
-- Shows a class-colored status bar for each party member with a
-- tracked stun/root/incapacitate, tracking cooldown remaining after
-- each use. Completely independent of the main cooldown anchor/icon
-- system and of the interrupt tracker (KastaCD_Interrupts.lua) - this
-- file mirrors that one's architecture exactly, swapped to CC spells.
-- =============================================================

-- Unlike interrupts (one interrupt per class/spec), most classes have
-- several unrelated CC spells with no single hardcoded "primary" one -
-- so instead of a static INT_DEFAULT-style table, a unit's default is
-- guessed live from their current spec (see PickGuessCC below) the same
-- way the interrupt tracker's per-class default works, just resolved
-- per-spec instead of hardcoded. The guess is always replaced the moment
-- a real cast is witnessed, since that's ground truth.
local CC_DEFAULT = {}

-- All crowd-control spell IDs detected from the combat log.
-- Only spells with a real, fixed cooldown are listed - GCD-only /
-- combo-point finishers (Polymorph, Kidney Shot, Cheap Shot, Entangling
-- Roots, ...) have nothing meaningful to show on a cooldown bar, so
-- they're intentionally left out.
--
-- `specs` mirrors SpellMatchesSpec's convention in KastaCD_DB.lua: a list
-- of spec IDs that can actually use the spell, omitted when it's baseline
-- for every spec of that class.
--
-- `isTalent=true` mirrors the same field in KastaCD_SpellDB.lua: spec
-- alone can't tell us which *talent* a player picked (multiple CC spells
-- can share a spec, e.g. Shockwave is baseline Protection while Storm
-- Bolt is a Protection-selectable talent) - so PickGuessCC below never
-- guesses a talent-gated entry, it only ever appears once the combat log
-- actually witnesses that exact spell being cast. Non-talent entries are
-- always safe to guess since they're guaranteed available the moment the
-- spec/class matches. A real combat-log cast is ground truth regardless
-- of either flag, since you can't cast what you don't have.
--
-- `race` gates a racial ability to a specific UnitRace() token (e.g.
-- "BloodElf") - only relevant to the guess path, same reasoning as
-- isTalent. `class="ALL"` marks an entry as available to any class
-- (mirrors SPELL_DB[208683]'s PvP Medallion convention), used together
-- with `race` for racials that aren't tied to a single class at all.
--   WARRIOR:     71=Arms, 72=Fury, 73=Protection
--   PALADIN:     65=Holy, 66=Protection, 70=Retribution
--   HUNTER:     253=Beast Mastery, 254=Marksmanship, 255=Survival
--   ROGUE:      259=Assassination, 260=Outlaw, 261=Subtlety
--   PRIEST:     256=Discipline, 257=Holy, 258=Shadow
--   DEATHKNIGHT:250=Blood, 251=Frost, 252=Unholy
--   SHAMAN:     262=Elemental, 263=Enhancement, 264=Restoration
--   MAGE:       62=Arcane, 63=Fire, 64=Frost
--   WARLOCK:    265=Affliction, 266=Demonology, 267=Destruction
--   MONK:       268=Brewmaster, 269=Windwalker, 270=Mistweaver
--   DRUID:      102=Balance, 103=Feral, 104=Guardian, 105=Restoration
--   DEMONHUNTER:577=Havoc, 581=Vengeance
CC_SPELLS = {
    -- WARRIOR - Shockwave and Storm Bolt are the same talent row, pick
    -- one or the other, available to all 3 specs (not Protection-only -
    -- corrected per live confirmation, the old specs={73} restriction was
    -- wrong). talentGroup marks them as mutually exclusive - see
    -- ClearCompetingCCTalents below.
    [46968]  = { class="WARRIOR",     cooldown=40,  isTalent=true,  talentGroup="warr_stormrow" },  -- Shockwave
    [107570] = { class="WARRIOR",     cooldown=30,  isTalent=true,  talentGroup="warr_stormrow" },  -- Storm Bolt
    [5246]   = { class="WARRIOR",     cooldown=90                   },                    -- Intimidating Shout (baseline, approx CD)
    [236077] = { class="WARRIOR",     cooldown=60                   },                    -- Disarm (baseline, approx CD)

    -- PALADIN
    [853]    = { class="PALADIN",     cooldown=60                   },                    -- Hammer of Justice
    [20066]  = { class="PALADIN",     cooldown=15,  specs={65,70},  isTalent=true },       -- Repentance (Holy/Ret talent)
    [115750] = { class="PALADIN",     cooldown=90                   },                    -- Blinding Light (baseline, approx CD)

    -- HUNTER
    [109248] = { class="HUNTER",      cooldown=45,  specs={253,254},isTalent=true },       -- Binding Shot (BM/MM talent)
    [24394]  = { class="HUNTER",      cooldown=60,  specs={253}     },                    -- Intimidation (BM pet, baseline)
    [19386]  = { class="HUNTER",      cooldown=45,  specs={254},    isTalent=true },       -- Wyvern Sting (MM talent)
    [202914] = { class="HUNTER",      cooldown=30,  specs={255},    isTalent=true },       -- Spider Sting (Survival talent, approx CD)

    -- ROGUE
    [2094]   = { class="ROGUE",       cooldown=120                  },                    -- Blind
    [1776]   = { class="ROGUE",       cooldown=10,  specs={260},    isTalent=true },       -- Gouge (Outlaw, uncertain baseline/talent)
    -- Kidney Shot has a real 20s cooldown on this server (unlike retail,
    -- where it's an uncapped combo-point finisher) - confirmed by the
    -- user. Assassination/Subtlety only - Outlaw uses Between the Eyes
    -- instead (see below). isTalent=true keeps it out of the single-slot
    -- default-guess pool (see PickGuessCC below), but alwaysGuess=true
    -- makes it show as its own bar the moment a matching-spec Rogue is
    -- seen in the group, rather than waiting on an actual witnessed cast.
    [408]    = { class="ROGUE",       cooldown=20,  specs={259,261}, isTalent=true, alwaysGuess=true }, -- Kidney Shot (Assassination/Subtlety)
    [207777] = { class="ROGUE",       cooldown=60,  isTalent=true   },                    -- Dismantle (approx CD)
    [207736] = { class="ROGUE",       cooldown=60,  specs={261},    isTalent=true },       -- Shadowy Duel (Subtlety talent, approx CD)
    -- Between the Eyes is Outlaw's baseline finisher stun/debuff - cooldown
    -- is the author's best-known Legion value (approx, not yet confirmed
    -- against this server). Same alwaysGuess treatment as Kidney Shot: show
    -- it as soon as an Outlaw Rogue is in the group.
    [199804] = { class="ROGUE",       cooldown=45,  specs={260},    isTalent=true, alwaysGuess=true }, -- Between the Eyes (Outlaw, approx CD)

    -- DEATHKNIGHT
    [108194] = { class="DEATHKNIGHT", cooldown=45,  specs={252}     },                    -- Asphyxiate (Unholy, baseline)
    [221562] = { class="DEATHKNIGHT", cooldown=45,  specs={250}     },                    -- Asphyxiate (Blood, baseline)
    [207167] = { class="DEATHKNIGHT", cooldown=60,  specs={251},    isTalent=true },       -- Blinding Sleet (Frost talent, approx CD)

    -- SHAMAN
    [51514]  = { class="SHAMAN",      cooldown=30                   },                    -- Hex
    [192058] = { class="SHAMAN",      cooldown=60,  specs={262}     },                    -- Capacitor Totem (Elemental, baseline)
    [51485]  = { class="SHAMAN",      cooldown=30,  specs={262,263},isTalent=true },       -- Earthgrab Totem (Ele/Enh, uncertain)

    -- MAGE
    [122]    = { class="MAGE",        cooldown=30                   },                    -- Frost Nova
    [113724] = { class="MAGE",        cooldown=45,  isTalent=true   },                    -- Ring of Frost (talent)
    [31661]  = { class="MAGE",        cooldown=20,  specs={63}      },                    -- Dragon's Breath (Fire only, baseline)

    -- PRIEST
    [88625]  = { class="PRIEST",      cooldown=30,  specs={257}     },                    -- Holy Word: Chastise (Holy, baseline)
    [205369] = { class="PRIEST",      cooldown=45,  isTalent=true   },                    -- Mind Bomb (PvP talent, approx CD)

    -- WARLOCK
    [30283]  = { class="WARLOCK",     cooldown=60, specs={267}                   },                    -- Shadowfury
    [6789]   = { class="WARLOCK",     cooldown=45,  isTalent=true   },                    -- Mortal Coil (talent, approx CD)
    [212459] = { class="WARLOCK",     cooldown=45,  specs={266},    isTalent=true },       -- Call Fel Lord (Demonology talent, approx CD)

    -- MONK
    [119381] = { class="MONK",        cooldown=45                   },                    -- Leg Sweep
    [115078] = { class="MONK",        cooldown=45,  isTalent=true   },                    -- Paralysis (talent)
    [116844] = { class="MONK",        cooldown=45                   },                    -- Ring of Peace (baseline, approx CD)
    [233759] = { class="MONK",        cooldown=60,  specs={268},    isTalent=true },       -- Grapple Weapon (Brewmaster PvP talent, approx CD)

    -- DRUID
    -- Cooldowns below marked "approx" are the author's best-known Legion
    -- value, not yet confirmed against this specific server - correct via
    -- the in-game tooltip if a bar's countdown looks off.
    [5211]   = { class="DRUID",       cooldown=60,                  isTalent=true },       -- Mighty Bash
    [102359] = { class="DRUID",       cooldown=30,  specs={103,104},isTalent=true },       -- Mass Entanglement (Feral/Guardian talent, approx CD)
    [132469] = { class="DRUID",       cooldown=30,  specs={103,104},isTalent=true },       -- Typhoon (Feral/Guardian talent, approx CD)
    [102793] = { class="DRUID",       cooldown=60,  specs={105},    isTalent=true },       -- Ursol's Vortex (Restoration talent, approx CD)
    -- Maim has a real 10s cooldown on this server (unlike retail, where
    -- it's an uncapped combo-point finisher) - confirmed by the user,
    -- same treatment as Rogue's Kidney Shot above. isTalent=true keeps
    -- it out of the single-slot default-guess pool (see PickGuessCC
    -- below), but alwaysGuess=true makes it show as its own bar the
    -- moment a Feral Druid is seen in the group, rather than waiting on
    -- an actual witnessed cast.
    [22570]  = { class="DRUID",       cooldown=10,  specs={103},    isTalent=true, alwaysGuess=true }, -- Maim (Feral)

    -- DEMONHUNTER
    [179057] = { class="DEMONHUNTER", cooldown=45,  specs={577},    isTalent=true },       -- Chaos Nova (Havoc talent)
    [217832] = { class="DEMONHUNTER", cooldown=90                   },                    -- Imprison
    [205630] = { class="DEMONHUNTER", cooldown=30,  specs={581},    isTalent=true },       -- Illidan's Grasp (Vengeance talent, approx CD)
    [206649] = { class="DEMONHUNTER", cooldown=60,  specs={577},    isTalent=true },       -- Eye of Leotheras (Havoc talent, approx CD)

    -- Arcane Torrent (Blood Elf racial) moved to the Interrupt tracker's
    -- INT_SPELLS - see KastaCD_Interrupts.lua. `race`/class="ALL" support
    -- above is kept in place for any future racial CC additions.
}

-- Clears every OTHER spellId sharing spellId's talentGroup from guid's
-- KNOWN_UNIT_SPELLS. Confirming one pick in a mutually-exclusive talent
-- row (e.g. Shockwave vs Storm Bolt) is definitive proof the alternative
-- is NOT currently selected - Legion's talent system only allows one
-- choice per row. Without this, ground truth from an earlier pick (a
-- witnessed cast, a sync update, or an inspect scan) could keep both
-- marked "known" simultaneously, showing two bars for what's actually
-- one talent choice, or leaving the display stuck on a stale pick once
-- the current one's own entry got cleared by something else. Called from
-- every site that writes a confirmed CC_SPELLS pick into KNOWN_UNIT_SPELLS
-- (KastaCD_CombatLog.lua's cast hook, KastaCD_DB.lua's ScanUnitTalents,
-- KastaCD_Sync.lua's HandleSyncMessage).
function ClearCompetingCCTalents(guid, spellId)
    if not guid then return end
    local info = CC_SPELLS[spellId]
    local group = info and info.talentGroup
    if not group then return end

    local known = KNOWN_UNIT_SPELLS[guid]
    if not known then return end

    for sid, otherInfo in pairs(CC_SPELLS) do
        if sid ~= spellId and otherInfo.talentGroup == group then
            known[sid] = nil
        end
    end
end

-- Per-unit, per-spell state and bar frames. Nested by spellId (not a
-- single entry per unit) so a unit with multiple independent CC options
-- (e.g. a Rogue's Blind AND Kidney Shot) gets one bar per spell that
-- never overwrites the other - casting one doesn't erase the other's
-- in-progress cooldown.
local ccBarState  = {}   -- [unit][spellId] = { spellId, cooldown, endTime, class }
local ccBarFrames = {}   -- [unit][spellId] = { row, sb, ico, nameText, cdText }
local ccAnchorFrame = nil
local ccBarsParent  = nil

-- Five synthetic "party members" used only for Test Mode while solo (no
-- real party exists to preview against). Picked for class-color variety
-- and a spread of cooldown lengths (20s-90s) so the staggered start below
-- shows several different animation states at once. Each token is fake
-- and never resolves via the real UnitClass/UnitName/UnitGUID APIs - see
-- the class/name-resolution branches in RebuildCCBars for how that's
-- handled, and the ticker for how their cooldowns loop forever instead of
-- sitting "ready" after the first cycle.
local TEST_FAKE_UNITS = {
    { token="KCDTESTCC1", name="Test Warrior",     class="WARRIOR",     spellId=46968,  cooldown=40 },
    { token="KCDTESTCC2", name="Test Rogue",       class="ROGUE",       spellId=6770,   cooldown=20 },
    { token="KCDTESTCC3", name="Test Mage",        class="MAGE",        spellId=122,    cooldown=25 },
    { token="KCDTESTCC4", name="Test Priest",      class="PRIEST",      spellId=88625,  cooldown=30 },
    { token="KCDTESTCC5", name="Test DemonHunter", class="DEMONHUNTER", spellId=217832, cooldown=90 },
}
local TEST_FAKE_LOOKUP = {}
for _, u in ipairs(TEST_FAKE_UNITS) do TEST_FAKE_LOOKUP[u.token] = u end

-- ─────────────────────────────────────────────────────────────
-- DB accessor with lazy defaults
-- ─────────────────────────────────────────────────────────────
-- Default statusbar texture, used whenever no SharedMedia texture has
-- been picked (or SharedMedia/LibStub isn't installed at all).
local DEFAULT_BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

local function GetCCDB()
    if type(KastaCDDB) ~= "table" then return {barWidth=200,barHeight=20,enabled=true,locked=true,testMode=false,texturePath=DEFAULT_BAR_TEXTURE,hideBorder=false} end
    if type(KastaCDDB.ccAnchor) ~= "table" then KastaCDDB.ccAnchor = {} end
    local db = KastaCDDB.ccAnchor
    if db.barWidth    == nil then db.barWidth    = 200 end
    if db.barHeight   == nil then db.barHeight   = 20  end
    if db.enabled     == nil then db.enabled     = true end
    if db.locked      == nil then db.locked      = true end
    if db.testMode    == nil then db.testMode    = false end
    if db.texturePath == nil then db.texturePath = DEFAULT_BAR_TEXTURE end
    if db.hideBorder  == nil then db.hideBorder  = false end
    if db.showReady   == nil then db.showReady   = true  end
    if db.clickThrough == nil then db.clickThrough = false end
    if db.maxNameChars == nil then db.maxNameChars = 0 end
    -- Grow direction: false/nil = grow down (bars stack below a fixed top
    -- edge, the original behavior), true = grow up (bars stack above a
    -- fixed bottom edge).
    if db.growUp      == nil then db.growUp      = false end
    -- Independent "Active in:" choice for this tracker - no longer bound
    -- to the main icon tracker's shared KastaCDDB.contentTypes.
    if db.contentTypes == nil then
        db.contentTypes = {
            ["Open World"]=true, ["Dungeon"]=true,
            ["Arena"]=true,      ["Battleground"]=true,
        }
    end
    -- Per-spell opt-out: every CC_SPELLS entry is shown by default (the
    -- pre-existing behavior, preserved for anyone who never touches this
    -- setting) - [sid]=true here explicitly EXCLUDES a spell from the
    -- tracker regardless of what PickGuessCC/a real cast would otherwise
    -- show. Set from the "Tracked Spells" sub-tab (KastaCD_Options.lua).
    if type(db.disabledSpells) ~= "table" then db.disabledSpells = {} end
    return db
end

local function IsCCSpellEnabled(sid)
    return not GetCCDB().disabledSpells[sid]
end

-- True if specs is unset (unrestricted) or specId is in the list.
local function SpecInList(specs, specId)
    if not specs then return true end
    if not specId then return false end
    for _, s in ipairs(specs) do
        if s == specId then return true end
    end
    return false
end

-- Picks the CC_SPELLS entries matching the given class (and, when known,
-- the unit's actual current spec) worth showing a preview bar for before
-- any real cast happens - there's no static CC_DEFAULT, see the comment
-- above that table for why. Returns a LIST, not a single best guess: a
-- class can have more than one independent CC option worth previewing at
-- once (e.g. a Rogue always has Blind available, and separately may have
-- a confirmed talent like Kidney Shot) - these must never replace each
-- other's bar, so every eligible entry is returned and the caller seeds
-- a preview for each spellId that doesn't already have one.
--
-- For the baseline (non-talent) half, only the single most specific match
-- is included (an exact spec match over a spec-unrestricted fallback) -
-- unlike talents, baseline CC options for the same class are typically
-- mutually exclusive across specs (only one applies to a given spec at a
-- time), so including every class-wide baseline entry would show
-- irrelevant other-spec abilities.
--
-- isTalent=true entries are only included once KNOWN_UNIT_SPELLS actually
-- confirms the pick - either a real witnessed cast, or a resolved inspect
-- talent scan (ScanUnitTalents in KastaCD_DB.lua) - never guessed from
-- spec alone, since multiple CC spells can share a spec (e.g. Shockwave
-- and Storm Bolt are both valid for Protection).
--
-- raceToken (from UnitRace(unit)'s second return) gates race-restricted
-- entries (class="ALL", e.g. Arcane Torrent) the same way specId gates
-- spec-restricted ones - an entry with a race requirement is skipped for
-- anyone who isn't that race, regardless of class/spec match.
--
-- PLAYER-ONLY EXCEPTION: ScanUnitTalents (KastaCD_DB.lua) explicitly
-- skips "player" on the assumption IsPlayerSpell/IsSpellKnown already
-- covers them reliably - true for SPELL_DB's IsSpellKnownForUnit path,
-- but this function has its own separate KNOWN_UNIT_SPELLS-only gate with
-- no equivalent player self-check, so a talent-gated CC spell (e.g. Storm
-- Bolt) stayed hidden for your OWN bar until you happened to cast it once.
-- Same problem for baseline spec-gated entries (e.g. Shockwave) whenever
-- GetSpecialization()/GetSpecializationInfo() themselves don't resolve
-- reliably on a given server - KastaCD_CombatLog.lua already documents
-- this exact failure mode for the player's own spec cache. Both are fixed
-- below by trusting IsPlayerSpell/IsSpellKnown directly for "player",
-- bypassing spec-cache/witnessed-cast entirely - "do I have this spell"
-- is always 100% reliable for your own character.
local function PlayerHasSpellID(spellId)
    local checkId = spellId
    if FindSpellOverrideByID then
        local ov = FindSpellOverrideByID(spellId)
        if ov and ov ~= 0 then checkId = ov end
    end
    return (IsPlayerSpell and (IsPlayerSpell(checkId) or IsPlayerSpell(spellId)))
        or (IsSpellKnown and (IsSpellKnown(checkId) or IsSpellKnown(spellId)))
        or false
end

local function PickGuessCC(unit, class, specId, raceToken)
    local isPlayer = (unit == "player")
    local guid  = unit and UnitGUID(unit)
    -- For "player", KNOWN_UNIT_SPELLS[guid] is kept fresh by
    -- ScanUnitTalents("player") (KastaCD_DB.lua, called from
    -- KastaCD_Sync.lua's BuildSyncPayload) - this loop already handles
    -- the player correctly via that shared cache, no separate
    -- IsPlayerSpell-based branch needed (that used to exist here and was
    -- removed: it was redundant with this loop once ScanUnitTalents
    -- started covering "player" too, and worse, actively risky - raw
    -- IsPlayerSpell can report a stale competing pick true for a stretch
    -- after respeccing, which could re-add an already-invalidated talent
    -- guess right back in).
    local known = guid and KNOWN_UNIT_SPELLS[guid]

    local guesses = {}

    if known then
        for sid, info in pairs(CC_SPELLS) do
            if info.isTalent and not info.alwaysGuess and known[sid] and IsCCSpellEnabled(sid) then
                local classOk = info.class == class or info.class == "ALL"
                local raceOk  = not info.race or info.race == raceToken
                if classOk and raceOk and SpecInList(info.specs, specId) then
                    table.insert(guesses, { spellId = sid, cooldown = info.cooldown })
                end
            end
        end
    end

    -- alwaysGuess entries (Kidney Shot, Maim, Between the Eyes) bypass the
    -- "known"/witnessed-cast gate entirely - they're real baseline finishers
    -- with a fixed cooldown on this server, so as soon as a unit's class/spec
    -- matches they get their own guessed bar, independent of the single-slot
    -- exactMatch/fallback competition below.
    for sid, info in pairs(CC_SPELLS) do
        if info.alwaysGuess and IsCCSpellEnabled(sid) then
            local classOk = info.class == class or info.class == "ALL"
            local raceOk  = not info.race or info.race == raceToken
            if classOk and raceOk and SpecInList(info.specs, specId) then
                table.insert(guesses, { spellId = sid, cooldown = info.cooldown })
            end
        end
    end

    local fallback, exactMatch = nil, nil
    for sid, info in pairs(CC_SPELLS) do
        local classOk = info.class == class or info.class == "ALL"
        local raceOk  = not info.race or info.race == raceToken
        if classOk and raceOk and not info.isTalent and IsCCSpellEnabled(sid) then
            if not info.specs then
                -- Baseline for every spec - good enough unless something
                -- more specific (an exact spec match) turns up.
                fallback = fallback or { spellId = sid, cooldown = info.cooldown }
            elseif isPlayer and PlayerHasSpellID(sid) then
                exactMatch = exactMatch or { spellId = sid, cooldown = info.cooldown }
            elseif SpecInList(info.specs, specId) then
                exactMatch = exactMatch or { spellId = sid, cooldown = info.cooldown }
            end
        end
    end
    if exactMatch or fallback then
        table.insert(guesses, exactMatch or fallback)
    end

    return guesses
end

-- ─────────────────────────────────────────────────────────────
-- Anchor frame (created once, reused)
-- Header is always visible when bars are shown; turns orange when unlocked.
-- ─────────────────────────────────────────────────────────────
local HEADER_H = 18
local BORDER_THICKNESS = 2  -- px, thickness of the bar outline strips

-- KastaCD-local: which corner of the anchor frame is the fixed/dragged
-- point - TOPLEFT for "grow down" (bars stack below a fixed top edge,
-- the original/default behavior), BOTTOMLEFT for "grow up" (bars stack
-- above a fixed bottom edge). Used everywhere the frame's position is
-- read or written so all of them agree on which edge "savedX/savedY"
-- actually refers to.
local function CCAnchorPoint(db)
    return db.growUp and "BOTTOMLEFT" or "TOPLEFT"
end

-- Positions the header strip/label and the bars container relative to
-- the anchor frame according to the current grow direction - called both
-- once at creation and on every RebuildCCBars pass (so toggling Grow Up/
-- Down in settings takes effect immediately, not just for newly-created
-- frames). For "grow down" the header sits at the top and bars extend
-- below it (original layout); for "grow up" the header sits at the
-- bottom and bars extend above it, so the header stays next to whichever
-- edge the user actually dragged/anchored.
local function ApplyCCGrowLayout()
    local a, bp = ccAnchorFrame, ccBarsParent
    if not a or not bp then return end
    local db = GetCCDB()

    a.hdrBg:ClearAllPoints()
    a.hdrLbl:ClearAllPoints()
    bp:ClearAllPoints()
    if db.growUp then
        a.hdrBg:SetPoint("BOTTOMLEFT",  a, "BOTTOMLEFT",  0, 0)
        a.hdrBg:SetPoint("BOTTOMRIGHT", a, "BOTTOMRIGHT", 0, 0)
        a.hdrLbl:SetPoint("BOTTOMLEFT",  a, "BOTTOMLEFT",  0, 0)
        a.hdrLbl:SetPoint("BOTTOMRIGHT", a, "BOTTOMRIGHT", 0, 0)
        bp:SetPoint("BOTTOMLEFT", a, "BOTTOMLEFT", 0, HEADER_H)
    else
        a.hdrBg:SetPoint("TOPLEFT",  a, "TOPLEFT",  0, 0)
        a.hdrBg:SetPoint("TOPRIGHT", a, "TOPRIGHT", 0, 0)
        a.hdrLbl:SetPoint("TOPLEFT",  a, "TOPLEFT",  0, 0)
        a.hdrLbl:SetPoint("TOPRIGHT", a, "TOPRIGHT", 0, 0)
        bp:SetPoint("TOPLEFT", a, "TOPLEFT", 0, -HEADER_H)
    end
end

local function EnsureCCAnchor()
    if ccAnchorFrame then return end

    local db  = GetCCDB()
    local BH  = db.barHeight
    local BW  = db.barWidth
    local ROW = BH + 2 + BW

    local a = CreateFrame("Frame", "KastaCDCCAnchor", UIParent)
    a:SetSize(ROW, HEADER_H)
    a:SetFrameStrata("MEDIUM")   -- above the settings window (which is HIGH)
    a:SetMovable(true)
    a:EnableMouse(true)
    a:RegisterForDrag("LeftButton")
    a:SetScript("OnDragStart", function(self)
        if not GetCCDB().locked then self:StartMoving() end
    end)
    a:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local db2  = GetCCDB()
        local esc  = self:GetEffectiveScale()
        local usc  = UIParent:GetEffectiveScale()
        db2.savedX = self:GetLeft() * esc
        local refY = db2.growUp and self:GetBottom() or self:GetTop()
        db2.savedY = (refY * esc) - (UIParent:GetTop() * usc)
    end)

    -- Header background strip (dark normally, orange when unlocked)
    local hdrBg = a:CreateTexture(nil, "BACKGROUND", nil, 1)
    hdrBg:SetHeight(HEADER_H)
    hdrBg:SetColorTexture(0.12, 0.12, 0.12, 0.9)
    a.hdrBg = hdrBg

    -- Header label: always "Crowd Control"
    local hdrLbl = a:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdrLbl:SetHeight(HEADER_H)
    hdrLbl:SetJustifyH("CENTER")
    hdrLbl:SetJustifyV("MIDDLE")
    hdrLbl:SetText("Crowd Control")
    hdrLbl:SetTextColor(0.85, 0.85, 0.85)
    a.hdrLbl = hdrLbl

    -- Restore saved position or default to centre-right (offset from the
    -- interrupt tracker's default spot so they don't stack on first use)
    if db.savedX and db.savedY then
        local esc = a:GetEffectiveScale()
        a:SetPoint(CCAnchorPoint(db), UIParent, "TOPLEFT", db.savedX / esc, db.savedY / esc)
    else
        a:SetPoint(CCAnchorPoint(db), UIParent, "CENTER", 250, -50)
    end

    -- Container for bars (exact position set by ApplyCCGrowLayout below)
    local bp = CreateFrame("Frame", nil, a)
    bp:SetSize(1, 1)

    -- Hidden by default - WoW frames are shown unless told otherwise, and
    -- this function can be triggered just by reading the anchor's position
    -- (GetCCAnchorPos, e.g. the settings menu's Position X/Y fields opening
    -- for the first time) without a real RebuildCCBars pass ever following
    -- it. Real visibility is entirely owned by that function's own
    -- `ccAnchorFrame:SetShown(anyBar or not db.locked)` call at the end,
    -- and by UnlockCCAnchor()'s explicit :Show() - never by mere frame
    -- creation.
    a:Hide()

    ccAnchorFrame = a
    ccBarsParent  = bp
    ApplyCCGrowLayout()
end

-- Click-through: lets clicks pass to whatever is underneath the bar
-- (nameplates, action bars, the game world) instead of the bar itself
-- eating them. Only takes effect while locked - unlocked always keeps
-- mouse enabled, otherwise the anchor couldn't be dragged at all.
-- EnableMouse only affects the exact frame it's called on (not
-- children), so every icon frame under ccBarsParent needs the same
-- call, not just the anchor itself - walked generically via
-- GetChildren() rather than tracking a separate icon-frame list, so
-- this stays correct regardless of how RebuildCCBars builds rows.
function ApplyCCClickThrough()
    if not ccAnchorFrame then return end
    local db = GetCCDB()
    local through = db.clickThrough and db.locked
    ccAnchorFrame:EnableMouse(not through)
    if ccBarsParent then
        for _, row in ipairs({ ccBarsParent:GetChildren() }) do
            if row.EnableMouse then row:EnableMouse(not through) end
            for _, child in ipairs({ row:GetChildren() }) do
                if child.EnableMouse then child:EnableMouse(not through) end
            end
        end
    end
end

-- Show/hide the header strip based on lock state.
-- Size/position adjustments are handled inside RebuildCCBars.
local function ApplyCCAnchorLockState()
    if not ccAnchorFrame then return end
    if GetCCDB().locked then
        ccAnchorFrame.hdrBg:Hide()
        ccAnchorFrame.hdrLbl:Hide()
    else
        ccAnchorFrame.hdrBg:SetColorTexture(1, 0.55, 0, 0.9)
        ccAnchorFrame.hdrBg:Show()
        ccAnchorFrame.hdrLbl:SetTextColor(1, 1, 1)
        ccAnchorFrame.hdrLbl:Show()
    end
    ApplyCCClickThrough()
end

-- ─────────────────────────────────────────────────────────────
-- Lock / unlock helpers (called from UI settings panel)
-- ─────────────────────────────────────────────────────────────
function LockCCAnchor()
    GetCCDB().locked = true
    ApplyCCAnchorLockState()
    -- Without this, locking while solo left the anchor/bars showing in
    -- whatever state they were in while unlocked - ApplyCCAnchorLockState
    -- only toggles the header strip, not the in-group/instance/content-type
    -- gating that decides whether the anchor should be visible at all.
    -- RebuildCCBars() re-applies all of that immediately, same as
    -- UnlockCCAnchor() already does on the way in.
    RebuildCCBars()
end

function UnlockCCAnchor()
    GetCCDB().locked = false
    EnsureCCAnchor()
    ApplyCCAnchorLockState()
    ccAnchorFrame:Show()
    RebuildCCBars()
end

-- Sets the anchor's exact saved position (same units as OnDragStop above
-- writes) and repositions the live frame immediately - used by the
-- Position X/Y sliders in the settings panel for pixel-perfect placement
-- without needing to drag. EnsureCCAnchor() is a no-op if the frame
-- already exists, so this works whether or not it's been created yet.
function SetCCAnchorPos(x, y)
    EnsureCCAnchor()
    local db = GetCCDB()
    db.savedX = x
    db.savedY = y
    local esc = ccAnchorFrame:GetEffectiveScale()
    ccAnchorFrame:ClearAllPoints()
    ccAnchorFrame:SetPoint(CCAnchorPoint(db), UIParent, "TOPLEFT", x / esc, y / esc)
end

-- Returns the anchor's current resolved x/y in the same units
-- SetCCAnchorPos expects. If nothing's been saved yet (anchor still
-- sitting at its CENTER-relative default), this reads the *actual* live
-- position off the frame instead of returning 0/0 - otherwise the
-- Position X/Y sliders in settings would snap the anchor to the corner
-- of the screen the moment either one is touched, since writing one axis
-- always writes both and the other would fall back to a wrong default.
function GetCCAnchorPos()
    EnsureCCAnchor()
    local db = GetCCDB()
    if db.savedX and db.savedY then
        return db.savedX, db.savedY
    end
    local esc = ccAnchorFrame:GetEffectiveScale()
    local usc = UIParent:GetEffectiveScale()
    local x = ccAnchorFrame:GetLeft() * esc
    local refY = db.growUp and ccAnchorFrame:GetBottom() or ccAnchorFrame:GetTop()
    local y = (refY * esc) - (UIParent:GetTop() * usc)
    return x, y
end

-- Clears a unit's stored state (real witnessed cast or guess alike), so
-- the next rebuild re-evaluates their default guess from scratch. Needed
-- because a spec change can make previously-witnessed "ground truth"
-- state factually wrong (e.g. a Blood DK's witnessed Asphyxiate cast
-- keeps showing after respeccing to Frost, which can't use it at all) -
-- without this, stale ground-truth data persists forever since it's
-- normally treated as permanently authoritative. Called from
-- KastaCD_Events.lua whenever a spec change is detected.
function ClearCCBarState(unit)
    ccBarState[unit] = nil
end

-- ─────────────────────────────────────────────────────────────
-- Rebuild all crowd-control bars
-- ─────────────────────────────────────────────────────────────
function RebuildCCBars()
    local db = GetCCDB()

    if not db.enabled then
        if ccAnchorFrame then ccAnchorFrame:Hide() end
        return
    end

    -- Hide entirely when not in a party or raid group, unless test mode is
    -- on or the anchor is unlocked - unlocking always has to make the
    -- anchor visible, otherwise there'd be nothing to drag while solo.
    if db.locked and not IsInGroup() and not db.testMode then
        if ccAnchorFrame then ccAnchorFrame:Hide() end
        for _, bf in pairs(ccBarFrames) do bf.row:Hide() end
        return
    end

    -- Hide entirely inside raid instances (10-man and above), same
    -- unlocked exception as above.
    local _, instanceType = IsInInstance()
    if db.locked and instanceType == "raid" then
        if ccAnchorFrame then ccAnchorFrame:Hide() end
        for _, bf in pairs(ccBarFrames) do bf.row:Hide() end
        return
    end

    -- Hide entirely when the current content type is disabled via this
    -- tracker's OWN "Active in:" toggles (Crowd Control panel >
    -- Visibility) - independent of the main icon tracker's and the
    -- Interrupt tracker's own choices, same unlocked/testMode exception
    -- as above.
    if db.locked and not db.testMode and type(IsContentEnabledFor) == "function" and not IsContentEnabledFor(db.contentTypes) then
        if ccAnchorFrame then ccAnchorFrame:Hide() end
        for _, bf in pairs(ccBarFrames) do bf.row:Hide() end
        return
    end

    EnsureCCAnchor()

    -- Collect current party units. Test Mode always substitutes 5 fake
    -- units, whether solo or grouped, so it's a straightforward "show me
    -- the demo" toggle usable anytime - not just when there's no real
    -- party to preview against.
    local units = {}
    local usingFakeUnits = db.testMode
    if usingFakeUnits then
        for _, u in ipairs(TEST_FAKE_UNITS) do units[#units + 1] = u.token end
    else
        units[1] = "player"
        for i = 1, 4 do
            if UnitExists("party" .. i) then
                units[#units + 1] = "party" .. i
            end
        end
    end

    -- Sort by class instead of raid/party slot order, so bars group
    -- same-class units together (e.g. two Monks always end up adjacent)
    -- rather than scattering them whenever a different class happens to
    -- land in a party slot between them. CLASS_INFO's order matches the
    -- rest of the addon (per-class settings panels, etc.); unrecognized
    -- classes sort last and ties keep their original party-slot order.
    do
        local classOrder = {}
        for i, ci in ipairs(CLASS_INFO or {}) do classOrder[ci.key] = i end
        local function UnitClassToken(u)
            local fakeInfo = TEST_FAKE_LOOKUP[u]
            if fakeInfo then return fakeInfo.class end
            local _, c = UnitClass(u)
            return c
        end
        local origIndex = {}
        for i, u in ipairs(units) do origIndex[u] = i end
        table.sort(units, function(a, b)
            local oa = classOrder[UnitClassToken(a)] or math.huge
            local ob = classOrder[UnitClassToken(b)] or math.huge
            if oa ~= ob then return oa < ob end
            return origIndex[a] < origIndex[b]
        end)
    end

    local BH  = db.barHeight
    local BW  = db.barWidth
    local ICO = BH  -- icon is square, matches bar height
    local ROW = ICO + BW  -- total row width

    -- Hide all rows; we re-show only the ones that are active
    for _, unitFrames in pairs(ccBarFrames) do
        for _, bf in pairs(unitFrames) do
            bf.row:Hide()
        end
    end

    local yOff   = 0
    local anyBar = false

    for i, unit in ipairs(units) do
        local fakeInfo = TEST_FAKE_LOOKUP[unit]
        local class
        if fakeInfo then
            class = fakeInfo.class
        else
            local _, c = UnitClass(unit)
            class = c
        end
        if class then
            ccBarState[unit] = ccBarState[unit] or {}
            local unitState = ccBarState[unit]

            -- Seed a fully "live" animated demo bar the first time a fake
            -- unit is seen: staggered cooldown position (spread across
            -- 0%-80% remaining) so the 5 preview bars show a mix of
            -- states - just used, mid-cooldown, nearly ready - instead of
            -- all sitting idle-ready. The ticker keeps looping it once it
            -- reaches ready, so the animation runs continuously.
            if fakeInfo and not next(unitState) then
                local frac = (i - 1) / 5
                unitState[fakeInfo.spellId] = {
                    spellId  = fakeInfo.spellId,
                    cooldown = fakeInfo.cooldown,
                    endTime  = GetTime() + fakeInfo.cooldown * (1 - frac),
                    class    = class,
                    isFake   = true,
                }
            end

            -- No static default for this class: guess every
            -- spec-appropriate CC option so a bar shows something
            -- immediately, same as the interrupt tracker's INT_DEFAULT -
            -- but a class can have more than one independent CC option at
            -- once (e.g. a Rogue's Blind is always available, and
            -- separately Kidney Shot once confirmed), so PickGuessCC
            -- returns a list and every entry gets its own bar - one never
            -- replaces another. Only seeds an entry that doesn't exist yet
            -- or is itself still just a preview (isPreview) - never
            -- overwrites a real witnessed cast - and re-evaluates every
            -- rebuild so a talent/spec swap updates that specific preview
            -- immediately instead of getting stuck on the first guess.
            if not fakeInfo then
                local specId    = type(GetUnitSpec) == "function" and GetUnitSpec(unit)
                local raceToken = select(2, UnitRace(unit))
                local currentGuesses = {}
                for _, guess in ipairs(PickGuessCC(unit, class, specId, raceToken)) do
                    currentGuesses[guess.spellId] = true
                    local existing = unitState[guess.spellId]
                    if not existing or existing.isPreview then
                        unitState[guess.spellId] = {
                            spellId = guess.spellId, cooldown = guess.cooldown,
                            endTime = 0, class = class, isPreview = true,
                        }
                    end
                end

                -- Prune stale entries: the seeding loop above only ever
                -- ADDED entries, never removed one - so a spell that WAS
                -- guessed/confirmed before (an old talent pick, or a
                -- since-corrected sync snapshot - see KastaCD_Sync.lua)
                -- but ISN'T in this rebuild's guess list anymore just sat
                -- there forever. This covers BOTH guessed previews AND
                -- real witnessed-cast entries (HandleCCCast clears
                -- isPreview on those, so an earlier fix here that only
                -- pruned isPreview==true entries left any spell that had
                -- ever actually been cast once permanently stuck,
                -- immune to ever being corrected by a later respec/sync
                -- update) - PickGuessCC's own isTalent branch already
                -- re-checks KNOWN_UNIT_SPELLS fresh every call, so
                -- currentGuesses is always this rebuild's true ground
                -- truth regardless of how the entry originally got here.
                -- Never yanks a bar that's actively mid-cooldown right
                -- now (endTime in the future) - only prunes once it's
                -- back to idle, so a live countdown never visibly cuts
                -- off mid-animation.
                local now = GetTime()
                for sid, st in pairs(unitState) do
                    if not currentGuesses[sid] and st.endTime <= now then
                        unitState[sid] = nil
                    end
                end
            end

            for sid, st in pairs(unitState) do
                -- Get or create bar frames
                ccBarFrames[unit] = ccBarFrames[unit] or {}
                local bf = ccBarFrames[unit][sid]
                if not bf then
                    local row = CreateFrame("Frame", nil, ccBarsParent)

                    -- Border: four strips forming an outline flush against
                    -- the row's own edges and extending outward by
                    -- BORDER_THICKNESS - not a single oversized rectangle
                    -- behind everything, which would sit under the
                    -- statusbar's semi-transparent background and show
                    -- through as a dark tint across the whole unfilled
                    -- portion of the bar instead of a crisp edge. Top/
                    -- bottom strips overhang left/right by the same
                    -- thickness so the four corners meet cleanly.
                    local T = BORDER_THICKNESS
                    local border = {}
                    local bTop = row:CreateTexture(nil, "BACKGROUND", nil, -1)
                    bTop:SetPoint("BOTTOMLEFT",  row, "TOPLEFT",  -T, 0)
                    bTop:SetPoint("BOTTOMRIGHT", row, "TOPRIGHT",  T, 0)
                    bTop:SetHeight(T)
                    bTop:SetColorTexture(0, 0, 0, 1)
                    border[#border + 1] = bTop

                    local bBottom = row:CreateTexture(nil, "BACKGROUND", nil, -1)
                    bBottom:SetPoint("TOPLEFT",  row, "BOTTOMLEFT",  -T, 0)
                    bBottom:SetPoint("TOPRIGHT", row, "BOTTOMRIGHT",  T, 0)
                    bBottom:SetHeight(T)
                    bBottom:SetColorTexture(0, 0, 0, 1)
                    border[#border + 1] = bBottom

                    local bLeft = row:CreateTexture(nil, "BACKGROUND", nil, -1)
                    bLeft:SetPoint("TOPRIGHT",    row, "TOPLEFT",    0, 0)
                    bLeft:SetPoint("BOTTOMRIGHT", row, "BOTTOMLEFT", 0, 0)
                    bLeft:SetWidth(T)
                    bLeft:SetColorTexture(0, 0, 0, 1)
                    border[#border + 1] = bLeft

                    local bRight = row:CreateTexture(nil, "BACKGROUND", nil, -1)
                    bRight:SetPoint("TOPLEFT",    row, "TOPRIGHT",    0, 0)
                    bRight:SetPoint("BOTTOMLEFT", row, "BOTTOMRIGHT", 0, 0)
                    bRight:SetWidth(T)
                    bRight:SetColorTexture(0, 0, 0, 1)
                    border[#border + 1] = bRight

                    -- Icon frame
                    local iconF = CreateFrame("Frame", nil, row)
                    iconF:SetSize(ICO, ICO)
                    iconF:SetPoint("LEFT", row, "LEFT", 0, 0)
                    iconF:EnableMouse(true)

                    local ico = iconF:CreateTexture(nil, "ARTWORK")
                    ico:SetAllPoints()
                    ico:SetTexCoord(0, 1, 0, 1)

                    -- Tooltip: this bar is permanently bound to this one
                    -- (unit, sid) pair, so it just reads the live state for
                    -- that exact spell rather than "whatever the unit's
                    -- current spell happens to be" - each spell now has
                    -- its own bar instead of sharing one per unit.
                    iconF:SetScript("OnEnter", function(self)
                        local liveSt = ccBarState[unit] and ccBarState[unit][sid]
                        if not liveSt then return end
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        local ok = pcall(function() GameTooltip:SetSpellByID(sid) end)
                        if not ok then
                            local fake = TEST_FAKE_LOOKUP[unit]
                            GameTooltip:SetText((fake and fake.name) or UnitName(unit) or unit, 1, 1, 1)
                        end
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddDoubleLine("Cooldown:",
                            (liveSt.cooldown or 0) .. "s", 0.7, 0.7, 0.7, 1, 1, 1)
                        GameTooltip:Show()
                    end)
                    iconF:SetScript("OnLeave", function() GameTooltip:Hide() end)

                    -- StatusBar (background + fill). Texture is applied
                    -- every rebuild below (not here) so changing it in
                    -- settings updates already-existing bars immediately.
                    local sb = CreateFrame("StatusBar", nil, row)
                    sb:SetPoint("LEFT",  iconF, "RIGHT",  0, 0)
                    sb:SetPoint("RIGHT", row,   "RIGHT",  0, 0)
                    sb:SetHeight(BH)
                    sb:SetMinMaxValues(0, 1)
                    sb:SetValue(1)

                    local sbBg = sb:CreateTexture(nil, "BACKGROUND")
                    sbBg:SetAllPoints()
                    sbBg:SetAlpha(0.25)

                    local nameText = sb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    nameText:SetPoint("LEFT",   sb, "LEFT",   4, 0)
                    nameText:SetPoint("RIGHT",  sb, "RIGHT", -40, 0)
                    nameText:SetJustifyH("LEFT")
                    nameText:SetJustifyV("MIDDLE")
                    nameText:SetTextColor(1, 1, 1)

                    local cdText = sb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    cdText:SetPoint("RIGHT", sb, "RIGHT", -4, 0)
                    cdText:SetJustifyH("RIGHT")
                    cdText:SetJustifyV("MIDDLE")
                    cdText:SetTextColor(1, 1, 0.7)

                    bf = { row=row, sb=sb, sbBg=sbBg, ico=ico, iconF=iconF, nameText=nameText, cdText=cdText, border=border }
                    ccBarFrames[unit][sid] = bf
                end

                -- Resize / reposition - stacks downward from the top (grow
                -- down) or upward from the bottom (grow up), see
                -- ApplyCCGrowLayout for how ccBarsParent itself is anchored.
                bf.row:SetSize(ROW, BH)
                bf.row:ClearAllPoints()
                if db.growUp then
                    bf.row:SetPoint("BOTTOMLEFT", ccBarsParent, "BOTTOMLEFT", 0, yOff)
                else
                    bf.row:SetPoint("TOPLEFT", ccBarsParent, "TOPLEFT", 0, -yOff)
                end

                -- Icon always matches bar height
                bf.iconF:SetSize(ICO, ICO)

                -- Resize status bar (in case barWidth changed)
                bf.sb:SetHeight(BH)

                -- Statusbar texture (applied every rebuild so a SharedMedia
                -- selection change in settings takes effect immediately).
                local barTex = db.texturePath or DEFAULT_BAR_TEXTURE
                bf.sb:SetStatusBarTexture(barTex)
                bf.sbBg:SetTexture(barTex)

                -- Border visibility (applied every rebuild so toggling it
                -- in settings takes effect immediately). bf.border is a
                -- list of the 4 edge-strip textures.
                for _, b in ipairs(bf.border) do b:SetShown(not db.hideBorder) end

                -- Icon texture
                local tex = GetSpellTexture and GetSpellTexture(sid)
                if tex then bf.ico:SetTexture(tex) end

                -- Class colour: fill always class-colored, background
                -- track starts grey if already on cooldown so there's no
                -- flash of the wrong colour before the next 0.1s ticker
                -- tick corrects it - the ticker owns this for everything
                -- after the first draw.
                local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                if cc then
                    bf.sb:SetStatusBarColor(cc.r, cc.g, cc.b, 0.9)
                    local onCooldown = st.endTime and st.endTime > GetTime()
                    if onCooldown then
                        bf.sbBg:SetVertexColor(0.5, 0.5, 0.5)
                    else
                        bf.sbBg:SetVertexColor(cc.r, cc.g, cc.b)
                    end
                end

                -- Font (applied every rebuild so slider/dropdown changes take effect).
                -- Height is pinned to BH so changing font size never shifts the bar's Y.
                local fp = db.fontPath or "Fonts\\FRIZQT__.TTF"
                local fs = db.fontSize or 10
                bf.nameText:SetFont(fp, fs, "OUTLINE")
                bf.nameText:SetHeight(BH)
                bf.cdText:SetFont(fp, fs, "OUTLINE")
                bf.cdText:SetHeight(BH)

                -- Name (shortened to Max Name Characters if set - 0 = no limit)
                local displayName = (fakeInfo and fakeInfo.name) or UnitName(unit) or unit
                if db.maxNameChars and db.maxNameChars > 0 then
                    displayName = displayName:sub(1, db.maxNameChars)
                end
                bf.nameText:SetText(displayName)

                st.class = class

                bf.row:Show()
                yOff   = yOff + BH
                anyBar = true
            end
        end
    end

    -- Resize bars container
    ccBarsParent:SetSize(math.max(1, ROW), math.max(1, yOff))
    ccAnchorFrame:SetWidth(ROW)

    -- Header space is always reserved (whether locked or not) so the bars never
    -- shift position when the header strip is shown/hidden by locking/unlocking.
    ccAnchorFrame:SetHeight(HEADER_H + math.max(1, yOff))
    ApplyCCGrowLayout()
    ApplyCCAnchorLockState()
    ccAnchorFrame:SetShown(anyBar or not db.locked)
end

-- ─────────────────────────────────────────────────────────────
-- Called from KastaCD_CombatLog when a known CC spell is cast
-- ─────────────────────────────────────────────────────────────
function HandleCCCast(sourceGUID, spellId)
    local ccInfo = CC_SPELLS[spellId]
    if not ccInfo then return end
    if not IsCCSpellEnabled(spellId) then return end

    -- Resolve GUID → unit token
    local unit = nil
    if UnitGUID("player") == sourceGUID then
        unit = "player"
    else
        for i = 1, 4 do
            local u = "party" .. i
            if UnitGUID(u) == sourceGUID then
                unit = u
                break
            end
        end
    end
    if not unit then return end

    local now = GetTime()
    local _, class = UnitClass(unit)

    -- Keyed by (unit, spellId), not just unit - casting a different CC
    -- spell must never overwrite/replace another CC spell's own
    -- in-progress bar for the same unit (e.g. a Rogue's Blind and Kidney
    -- Shot track independently).
    ccBarState[unit] = ccBarState[unit] or {}
    if not ccBarState[unit][spellId] then
        ccBarState[unit][spellId] = { spellId=spellId, cooldown=ccInfo.cooldown, endTime=0, class=class or ccInfo.class }
    end

    local st      = ccBarState[unit][spellId]
    st.spellId    = spellId
    st.cooldown   = ccInfo.cooldown
    st.endTime    = now + ccInfo.cooldown
    st.class      = class or st.class
    st.isPreview  = nil  -- real cast is ground truth, overrides any prior spec-based guess

    -- Update icon immediately if bar already exists
    local bf = ccBarFrames[unit] and ccBarFrames[unit][spellId]
    if bf then
        local tex = GetSpellTexture and GetSpellTexture(spellId)
        if tex then bf.ico:SetTexture(tex) end
    end

    -- First-seen (unit, spellId) → need a new bar row
    if not bf or not bf.row:IsShown() then
        RebuildCCBars()
    end
end

-- ─────────────────────────────────────────────────────────────
-- 0.1-second update ticker
-- ─────────────────────────────────────────────────────────────
C_Timer.NewTicker(0.1, function()
    if type(KastaCDDB) ~= "table" then return end
    local db = GetCCDB()
    if not db.enabled then return end

    local now = GetTime()
    for unit, spells in pairs(ccBarState) do
        local unitFrames = ccBarFrames[unit]
        if unitFrames then
            for sid, st in pairs(spells) do
                local bf = unitFrames[sid]
                if bf and bf.row:IsShown() then
                    local cd = st.cooldown or 1
                    local cc = RAID_CLASS_COLORS and st.class and RAID_CLASS_COLORS[st.class]
                    if st.endTime and st.endTime > now then
                        local remaining = st.endTime - now
                        -- Inverted: 0 = just used, fills toward 1 = ready
                        bf.sb:SetValue(math.max(0, math.min(1, 1 - remaining / cd)))
                        -- Fill stays class-colored; grey the background track
                        -- instead while on cooldown - makes "still down" instantly
                        -- readable without checking the text, without losing the
                        -- class-color identity on the active bar itself.
                        if cc then bf.sb:SetStatusBarColor(cc.r, cc.g, cc.b, 0.9) end
                        bf.sbBg:SetVertexColor(0.5, 0.5, 0.5)
                        bf.cdText:SetTextColor(1, 1, 0.7)
                        local secs = math.ceil(remaining)
                        if secs >= 60 then
                            bf.cdText:SetText(math.floor(secs / 60) .. "m" .. string.format("%02d", secs % 60))
                        else
                            bf.cdText:SetText(secs .. "s")
                        end
                    else
                        bf.sb:SetValue(1)
                        if cc then
                            bf.sb:SetStatusBarColor(cc.r, cc.g, cc.b, 0.9)
                            bf.sbBg:SetVertexColor(cc.r, cc.g, cc.b)
                        end
                        if db.showReady then
                            bf.cdText:SetTextColor(0, 1, 0)
                            bf.cdText:SetText("READY")
                        else
                            bf.cdText:SetText("")
                        end

                        -- Fake demo units (solo Test Mode preview) loop forever
                        -- instead of sitting ready after the first cycle, so the
                        -- animation keeps demonstrating what an active cooldown
                        -- looks like without requiring a real cast.
                        if st.isFake then
                            st.endTime = now + cd
                        end
                    end
                end
            end
        end
    end
end)

-- =============================================================
-- Debug helper: /kcdccunit <party1|party2|party3|party4|player> - compares
-- ground truth (KNOWN_UNIT_SPELLS/UNIT_SPEC_CACHE) against what
-- PickGuessCC currently computes against what's actually persisted in
-- ccBarState right now, for one specific unit. Pinpoints exactly which
-- stage a "why doesn't this unit's CC bar update" bug is stuck at.
-- =============================================================
SLASH_KASTACDCCUNIT1 = "/kcdccunit"
SlashCmdList["KASTACDCCUNIT"] = function(msg)
    local unit = (msg and msg:match("^%s*(.-)%s*$")) or ""
    if unit == "" or not UnitExists(unit) then
        print("KastaCD CC unit debug: usage /kcdccunit <party1|party2|party3|party4|player> - unit must exist right now.")
        return
    end

    local guid = UnitGUID(unit)
    local _, class = UnitClass(unit)
    print(string.format("KastaCD CC unit debug: unit=%s class=%s guid=%s", unit, tostring(class), tostring(guid)))

    local specId = type(GetUnitSpec) == "function" and GetUnitSpec(unit)
    print("  UNIT_SPEC_CACHE:", tostring(specId))

    local known = guid and KNOWN_UNIT_SPELLS[guid]
    if known then
        local parts = {}
        for sid in pairs(known) do parts[#parts + 1] = tostring(sid) end
        print("  KNOWN_UNIT_SPELLS[guid]:", #parts > 0 and table.concat(parts, ",") or "(empty)")
    else
        print("  KNOWN_UNIT_SPELLS[guid]: nil (no entry at all)")
    end

    local raceToken = select(2, UnitRace(unit))
    local guesses = PickGuessCC(unit, class, specId, raceToken)
    local gparts = {}
    for _, g in ipairs(guesses) do gparts[#gparts + 1] = tostring(g.spellId) end
    print("  PickGuessCC() returns:", #gparts > 0 and table.concat(gparts, ",") or "(empty)")

    local state = ccBarState[unit]
    if state then
        local sparts = {}
        for sid, st in pairs(state) do
            sparts[#sparts + 1] = string.format("%d(isPreview=%s,isFake=%s)", sid, tostring(st.isPreview), tostring(st.isFake))
        end
        print("  ccBarState[unit] (actually persisted):", #sparts > 0 and table.concat(sparts, " ") or "(empty)")
    else
        print("  ccBarState[unit]: nil (no entry at all)")
    end

    local frames = ccBarFrames[unit]
    if frames then
        local fparts = {}
        for sid, bf in pairs(frames) do
            fparts[#fparts + 1] = string.format("%d(shown=%s)", sid, tostring(bf.row:IsShown()))
        end
        print("  ccBarFrames[unit] (actual bar frames):", #fparts > 0 and table.concat(fparts, " ") or "(empty)")
    else
        print("  ccBarFrames[unit]: nil (no entry at all)")
    end
end
