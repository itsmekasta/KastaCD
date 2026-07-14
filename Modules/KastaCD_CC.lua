-- KastaCD_CC.lua - independent crowd-control cooldown tracker, mirrors
-- KastaCD_Interrupts.lua's architecture, swapped to CC spells.
local CC_DEFAULT = {}

-- Only spells with a real fixed cooldown - GCD-only/combo-point finishers
-- are left out. `specs`: spec IDs that can use it (omitted = baseline for
-- every spec). `isTalent=true`: never guessed by PickGuessCC, only shown
-- once a cast or inspect scan confirms it (spec alone can't tell talent
-- picks apart). `alwaysGuess=true` on a talentGroup member shows one
-- placeholder guess immediately on join; ground truth overrides it once
-- it arrives (see PickGuessCC). `race` gates a racial to a UnitRace()
-- token; class="ALL" + race is for racials not tied to one class.
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
    -- WARRIOR - Shockwave/Storm Bolt are the same talent row (all 3 specs).
    [46968]  = { class="WARRIOR",     cooldown=40,  isTalent=true,  talentGroup="warr_stormrow", alwaysGuess=true },  -- Shockwave
    [107570] = { class="WARRIOR",     cooldown=30,  isTalent=true,  talentGroup="warr_stormrow", alwaysGuess=true },  -- Storm Bolt
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
    -- Kidney Shot has a real 20s CD on this server (not an uncapped finisher) - confirmed.
    [408]    = { class="ROGUE",       cooldown=20,  specs={259,261}, isTalent=true, alwaysGuess=true }, -- Kidney Shot (Assassination/Subtlety)
    [207777] = { class="ROGUE",       cooldown=60,  isTalent=true   },                    -- Dismantle (approx CD)
    [207736] = { class="ROGUE",       cooldown=60,  specs={261},    isTalent=true },       -- Shadowy Duel (Subtlety talent, approx CD)
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
    [88625]  = { class="PRIEST",      cooldown=60,  specs={257}     },                    -- Holy Word: Chastise (Holy, baseline)
    [205369] = { class="PRIEST",      cooldown=45,  isTalent=true   },                    -- Mind Bomb (PvP talent, approx CD)

    -- WARLOCK
    [30283]  = { class="WARLOCK",     cooldown=60, specs={267}                   },                    -- Shadowfury
    [6789]   = { class="WARLOCK",     cooldown=45,  isTalent=true   },                    -- Mortal Coil (talent, approx CD)
    [212459] = { class="WARLOCK",     cooldown=45,  specs={266},    isTalent=true },       -- Call Fel Lord (Demonology talent, approx CD)

    -- MONK - Leg Sweep/Ring of Peace/Charging Ox Wave are the same level-45 row.
    -- groupDefault marks Leg Sweep as the preferred placeholder guess.
    [119381] = { class="MONK",        cooldown=45,  isTalent=true,  talentGroup="monk_l45row", alwaysGuess=true, groupDefault=true },  -- Leg Sweep
    [116844] = { class="MONK",        cooldown=45,  isTalent=true,  talentGroup="monk_l45row", alwaysGuess=true },  -- Ring of Peace
    [119392] = { class="MONK",        cooldown=30,  isTalent=true,  talentGroup="monk_l45row", alwaysGuess=true },  -- Charging Ox Wave (approx CD, not yet confirmed against this server)
    [115078] = { class="MONK",        cooldown=45,  isTalent=true   },                    -- Paralysis (talent)
    [233759] = { class="MONK",        cooldown=60,  specs={268},    isTalent=true },       -- Grapple Weapon (Brewmaster PvP talent, approx CD)

    -- DRUID - "approx" cooldowns are unconfirmed against this server; check tooltip if off.
    [5211]   = { class="DRUID",       cooldown=60,                  isTalent=true },       -- Mighty Bash
    [102359] = { class="DRUID",       cooldown=30,  specs={103,104},isTalent=true },       -- Mass Entanglement (Feral/Guardian talent, approx CD)
    [132469] = { class="DRUID",       cooldown=30,  specs={103,104},isTalent=true },       -- Typhoon (Feral/Guardian talent, approx CD)
    [102793] = { class="DRUID",       cooldown=60,  specs={105},    isTalent=true },       -- Ursol's Vortex (Restoration talent, approx CD)
    -- Maim has a real 10s CD on this server (not an uncapped finisher) - confirmed.
    [22570]  = { class="DRUID",       cooldown=10,  specs={103},    isTalent=true, alwaysGuess=true }, -- Maim (Feral)

    -- DEMONHUNTER
    [179057] = { class="DEMONHUNTER", cooldown=45,  specs={577},    isTalent=true },       -- Chaos Nova (Havoc talent)
    [217832] = { class="DEMONHUNTER", cooldown=90                   },                    -- Imprison
    [205630] = { class="DEMONHUNTER", cooldown=30,  specs={581},    isTalent=true },       -- Illidan's Grasp (Vengeance talent, approx CD)
    [206649] = { class="DEMONHUNTER", cooldown=60,  specs={577},    isTalent=true },       -- Eye of Leotheras (Havoc talent, approx CD)

    -- Arcane Torrent (Blood Elf racial) moved to KastaCD_Interrupts.lua's INT_SPELLS.
}

-- [triggerSpellId] = { targetSpellId, reduction seconds }
local CC_COOLDOWN_REDUCERS = {}

local SMITE_SPELL_ID    = 585
local CHASTISE_SPELL_ID = 88625
local CHASTISE_REDUCTION_BASE        = 6
local CHASTISE_REDUCTION_NAARU_BONUS = 2
local CHASTISE_REDUCTION_APOTHEOSIS_BONUS = 12
local LIGHT_OF_THE_NAARU_SPELL_ID = 196985
local APOTHEOSIS_BUFF_NAME = "Apotheosis"

local hasApotheosis = false

local function RefreshApotheosisBuff()
    for i = 1, 40 do
        local name = UnitAura("player", i, "HELPFUL")
        if not name then break end
        if name == APOTHEOSIS_BUFF_NAME then
            hasApotheosis = true
            return
        end
    end
    hasApotheosis = false
end

local apotheosisWatcher = CreateFrame("Frame")
apotheosisWatcher:RegisterEvent("UNIT_AURA")
apotheosisWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
apotheosisWatcher:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" and unit ~= "player" then return end
    RefreshApotheosisBuff()
end)

-- Clears every other spellId sharing spellId's talentGroup from guid's
-- KNOWN_UNIT_SPELLS - confirming one pick proves the alternative isn't
-- selected. Called from every site that confirms a CC_SPELLS pick.
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

-- Nested by spellId so a unit with multiple CC options gets one bar per
-- spell - casting one doesn't erase another's in-progress cooldown.
local ccBarState  = {}   -- [unit][spellId] = { spellId, cooldown, endTime, class }
local ccBarFrames = {}   -- [unit][spellId] = { row, sb, ico, nameText, cdText }
local ccGridFrames = {}  -- [unit][spellId] = { cell, ico, nameText, cdText } - icon-mode display
local ccAnchorFrame = nil
local ccBarsParent  = nil

-- Corner/center anchor points for icon-mode name/timer text. "outside"
-- (name only) sits below the icon instead of on top of it.
local GRID_TEXT_ANCHORS = {
    topleft     = "TOPLEFT",
    topright    = "TOPRIGHT",
    center      = "CENTER",
    bottomleft  = "BOTTOMLEFT",
    bottomright = "BOTTOMRIGHT",
}

local function PositionGridText(fs, ico, position, ox, oy)
    fs:ClearAllPoints()
    if position == "outside" then
        fs:SetPoint("TOP", ico, "BOTTOM", ox, -1 + oy)
    else
        local point = GRID_TEXT_ANCHORS[position] or "CENTER"
        fs:SetPoint(point, ico, point, ox, oy)
    end
end

-- Five fake party members for Test Mode while solo.
local TEST_FAKE_UNITS = {
    { token="KCDTESTCC1", name="Test Warrior",     class="WARRIOR",     spellId=46968,  cooldown=40 },
    { token="KCDTESTCC2", name="Test Rogue",       class="ROGUE",       spellId=6770,   cooldown=20 },
    { token="KCDTESTCC3", name="Test Mage",        class="MAGE",        spellId=122,    cooldown=25 },
    { token="KCDTESTCC4", name="Test Priest",      class="PRIEST",      spellId=88625,  cooldown=60 },
    { token="KCDTESTCC5", name="Test DemonHunter", class="DEMONHUNTER", spellId=217832, cooldown=90 },
}
local TEST_FAKE_LOOKUP = {}
for _, u in ipairs(TEST_FAKE_UNITS) do TEST_FAKE_LOOKUP[u.token] = u end

-- Default statusbar texture when no SharedMedia texture is picked.
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
    -- growUp: false/nil = bars stack down from a fixed top edge, true = stack up from bottom.
    if db.growUp      == nil then db.growUp      = false end
    -- iconOnRight: false/nil = icon on the left (default), true = icon on the right.
    if db.iconOnRight == nil then db.iconOnRight = false end
    -- displayStyle: "bar" (default, one row per spell) or "icon" (wrapping grid of icons+names).
    if db.displayStyle    == nil then db.displayStyle    = "bar" end
    if db.iconGridSize    == nil then db.iconGridSize    = 36 end
    if db.iconGridPerRow  == nil then db.iconGridPerRow  = 4 end
    if db.iconGridBorder  == nil then db.iconGridBorder  = false end
    if db.iconGridGap     == nil then db.iconGridGap     = 4 end
    -- iconGridGrowLeft: false/nil = columns grow right (default), true = grow left.
    if db.iconGridGrowLeft == nil then db.iconGridGrowLeft = false end
    if db.iconGridNameFont == nil then db.iconGridNameFont = "Fonts\\FRIZQT__.TTF" end
    -- iconGridNamePosition: "outside" (default, below the icon) or a corner/center anchor on top of it.
    if db.iconGridNamePosition == nil then db.iconGridNamePosition = "outside" end
    if db.iconGridNameX    == nil then db.iconGridNameX    = 0 end
    if db.iconGridNameY    == nil then db.iconGridNameY    = 0 end
    if db.iconGridNameSize == nil then db.iconGridNameSize = 10 end
    -- iconGridTimerPosition: a corner/center anchor on top of the icon (no "outside").
    if db.iconGridTimerPosition == nil then db.iconGridTimerPosition = "center" end
    if db.iconGridTimerX    == nil then db.iconGridTimerX    = 0 end
    if db.iconGridTimerY    == nil then db.iconGridTimerY    = 0 end
    if db.iconGridTimerSize == nil then db.iconGridTimerSize = 10 end
    if db.contentTypes == nil then
        db.contentTypes = {
            ["Open World"]=true, ["Dungeon"]=true,
            ["Arena"]=true,      ["Battleground"]=true,
        }
    end
    -- Per-spell opt-out, set from the "Tracked Spells" sub-tab.
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

-- Returns the list of CC_SPELLS entries worth a preview bar for a unit,
-- before any real cast happens. A list, not one guess - a class can have
-- several independent CC options at once (baseline picks a single most-
-- specific match; isTalent entries only appear once KNOWN_UNIT_SPELLS
-- confirms them via cast or inspect scan). raceToken gates race-only
-- entries. "player" bypasses spec-cache/witnessed-cast entirely and
-- trusts IsPlayerSpell/IsSpellKnown directly, since ScanUnitTalents skips
-- "player" and GetSpecialization can be unreliable on some servers.
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
    -- "player"'s KNOWN_UNIT_SPELLS is kept fresh by ScanUnitTalents("player").
    local known = guid and KNOWN_UNIT_SPELLS[guid]

    local guesses = {}
    -- talentGroups with a ground-truth pick, so the alwaysGuess loop below
    -- never adds a second (possibly wrong) bar once the real one is known.
    local confirmedGroups = {}

    if known then
        for sid, info in pairs(CC_SPELLS) do
            if info.isTalent and known[sid] and IsCCSpellEnabled(sid) then
                local classOk = info.class == class or info.class == "ALL"
                local raceOk  = not info.race or info.race == raceToken
                if classOk and raceOk and SpecInList(info.specs, specId) then
                    table.insert(guesses, { spellId = sid, cooldown = info.cooldown })
                    if info.talentGroup then confirmedGroups[info.talentGroup] = true end
                end
            end
        end
    end

    -- alwaysGuess entries bypass the known/witnessed-cast gate so a bar
    -- shows immediately on join. No talentGroup = independent ability,
    -- every eligible one gets a bar. Shared talentGroup = mutually
    -- exclusive picks, only one placeholder guess per group (confirmed
    -- ground truth, if any, already took the group's slot above).
    local groupCandidates = {}
    for sid, info in pairs(CC_SPELLS) do
        if info.alwaysGuess and IsCCSpellEnabled(sid) then
            local classOk = info.class == class or info.class == "ALL"
            local raceOk  = not info.race or info.race == raceToken
            if classOk and raceOk and SpecInList(info.specs, specId) then
                if info.talentGroup then
                    if not confirmedGroups[info.talentGroup] then
                        local list = groupCandidates[info.talentGroup]
                        if not list then
                            list = {}
                            groupCandidates[info.talentGroup] = list
                        end
                        table.insert(list, sid)
                    end
                else
                    table.insert(guesses, { spellId = sid, cooldown = info.cooldown })
                end
            end
        end
    end
    for _, list in pairs(groupCandidates) do
        -- Prefer groupDefault=true; falls back to lowest spellId.
        local sid = nil
        for _, candidate in ipairs(list) do
            if CC_SPELLS[candidate].groupDefault then sid = candidate end
        end
        if not sid then
            table.sort(list)
            sid = list[1]
        end
        table.insert(guesses, { spellId = sid, cooldown = CC_SPELLS[sid].cooldown })
    end

    -- Every qualifying non-talent entry gets its own guess - a baseline,
    -- unrestricted ability (e.g. Frost Nova) and a spec-restricted one
    -- (e.g. Dragon's Breath) aren't mutually exclusive, both are usable
    -- at once. Only isTalent/talentGroup entries above are exclusive picks.
    for sid, info in pairs(CC_SPELLS) do
        local classOk = info.class == class or info.class == "ALL"
        local raceOk  = not info.race or info.race == raceToken
        if classOk and raceOk and not info.isTalent and IsCCSpellEnabled(sid) then
            local qualifies
            if not info.specs then
                qualifies = true
            elseif isPlayer then
                qualifies = PlayerHasSpellID(sid) or SpecInList(info.specs, specId)
            else
                qualifies = SpecInList(info.specs, specId)
            end
            if qualifies then
                table.insert(guesses, { spellId = sid, cooldown = info.cooldown })
            end
        end
    end

    return guesses
end

-- Anchor frame (created once, reused). Header always visible; orange when unlocked.
local HEADER_H = 18
local BORDER_THICKNESS = 2  -- px, thickness of the bar outline strips

-- TOPLEFT for "grow down" (default), BOTTOMLEFT for "grow up".
-- Icon mode's horizontal grow direction also flips which edge the whole
-- tracker (not just each cell) is anchored/grows from, so the saved
-- position stays visually fixed on the side you actually snapped it to.
local function CCIsHorizRight(db)
    return db.displayStyle == "icon" and db.iconGridGrowLeft
end

local function CCAnchorPoint(db)
    local v = db.growUp and "BOTTOM" or "TOP"
    local h = CCIsHorizRight(db) and "RIGHT" or "LEFT"
    return v .. h
end

-- Positions the header/bars container per the current grow direction.
local function ApplyCCGrowLayout()
    local a, bp = ccAnchorFrame, ccBarsParent
    if not a or not bp then return end
    local db = GetCCDB()
    local vPoint = db.growUp and "BOTTOM" or "TOP"
    local hPoint = CCIsHorizRight(db) and "RIGHT" or "LEFT"

    a.hdrBg:ClearAllPoints()
    a.hdrLbl:ClearAllPoints()
    bp:ClearAllPoints()
    a.hdrBg:SetPoint(vPoint .. "LEFT",  a, vPoint .. "LEFT",  0, 0)
    a.hdrBg:SetPoint(vPoint .. "RIGHT", a, vPoint .. "RIGHT", 0, 0)
    a.hdrLbl:SetPoint(vPoint .. "LEFT",  a, vPoint .. "LEFT",  0, 0)
    a.hdrLbl:SetPoint(vPoint .. "RIGHT", a, vPoint .. "RIGHT", 0, 0)
    bp:SetPoint(vPoint .. hPoint, a, vPoint .. hPoint, 0, db.growUp and HEADER_H or -HEADER_H)
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
        local refX = CCIsHorizRight(db2) and self:GetRight() or self:GetLeft()
        db2.savedX = refX * esc
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

    -- Hidden by default; RebuildCCBars/UnlockCCAnchor own real visibility.
    a:Hide()

    ccAnchorFrame = a
    ccBarsParent  = bp
    ApplyCCGrowLayout()
end

-- Lets clicks pass through to whatever's underneath, only while locked.
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

function LockCCAnchor()
    GetCCDB().locked = true
    ApplyCCAnchorLockState()
    RebuildCCBars()
end

function UnlockCCAnchor()
    GetCCDB().locked = false
    EnsureCCAnchor()
    ApplyCCAnchorLockState()
    ccAnchorFrame:Show()
    RebuildCCBars()
end

-- Sets the anchor's saved position and repositions the live frame immediately.
function SetCCAnchorPos(x, y)
    EnsureCCAnchor()
    local db = GetCCDB()
    db.savedX = x
    db.savedY = y
    local esc = ccAnchorFrame:GetEffectiveScale()
    ccAnchorFrame:ClearAllPoints()
    ccAnchorFrame:SetPoint(CCAnchorPoint(db), UIParent, "TOPLEFT", x / esc, y / esc)
end

-- Reads the anchor's live position if nothing's saved yet, so touching
-- one X/Y slider doesn't snap the other axis to a wrong default.
function GetCCAnchorPos()
    EnsureCCAnchor()
    local db = GetCCDB()
    if db.savedX and db.savedY then
        return db.savedX, db.savedY
    end
    local esc = ccAnchorFrame:GetEffectiveScale()
    local usc = UIParent:GetEffectiveScale()
    local refX = CCIsHorizRight(db) and ccAnchorFrame:GetRight() or ccAnchorFrame:GetLeft()
    local x = refX * esc
    local refY = db.growUp and ccAnchorFrame:GetBottom() or ccAnchorFrame:GetTop()
    local y = (refY * esc) - (UIParent:GetTop() * usc)
    return x, y
end

-- Clears a unit's stored state so the next rebuild re-guesses from
-- scratch - needed since a spec change can make witnessed "ground truth"
-- wrong (e.g. a respec away from a class that had it). Called from
-- KastaCD_Events.lua on spec change.
function ClearCCBarState(unit)
    ccBarState[unit] = nil
end

local function HideAllCCBarRows()
    for _, unitFrames in pairs(ccBarFrames) do
        for _, bf in pairs(unitFrames) do
            bf.row:Hide()
        end
    end
end

local function HideAllCCGridCells()
    for _, unitFrames in pairs(ccGridFrames) do
        for _, gf in pairs(unitFrames) do
            gf.cell:Hide()
        end
    end
end

function RebuildCCBars()
    local db = GetCCDB()

    if not db.enabled then
        if ccAnchorFrame then ccAnchorFrame:Hide() end
        return
    end

    -- Hidden unless in a group, unlocked, or test mode.
    if db.locked and not IsInGroup() and not db.testMode then
        if ccAnchorFrame then ccAnchorFrame:Hide() end
        HideAllCCBarRows()
        HideAllCCGridCells()
        return
    end

    local _, instanceType = IsInInstance()
    if db.locked and instanceType == "raid" then
        if ccAnchorFrame then ccAnchorFrame:Hide() end
        HideAllCCBarRows()
        HideAllCCGridCells()
        return
    end

    -- This tracker's own "Active in:" gating, independent of the others.
    if db.locked and not db.testMode and type(IsContentEnabledFor) == "function" and not IsContentEnabledFor(db.contentTypes) then
        if ccAnchorFrame then ccAnchorFrame:Hide() end
        HideAllCCBarRows()
        HideAllCCGridCells()
        return
    end

    EnsureCCAnchor()

    -- Test Mode always substitutes 5 fake units, solo or grouped.
    local units = {}
    local usingFakeUnits = db.testMode
    if usingFakeUnits then
        for _, u in ipairs(TEST_FAKE_UNITS) do units[#units + 1] = u.token end
    else
        units[1] = "player"
        for i = 1, 4 do
            local u = "party" .. i
            if UnitExists(u) and UnitIsConnected(u) then
                units[#units + 1] = u
            end
        end
    end

    -- Sort by class so same-class units end up adjacent; ties keep party-slot order.
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

    local iconMode = (db.displayStyle == "icon")
    local GICO   = db.iconGridSize
    local GCOLS  = math.max(1, db.iconGridPerRow)
    local NAME_H = math.max(10, math.floor(GICO * 0.35))
    local CELL_W = GICO
    local CELL_H = (db.iconGridNamePosition == "outside") and (GICO + NAME_H) or GICO
    local GAP    = db.iconGridGap or 4

    -- Hide all rows/cells; we re-show only the ones that are active
    HideAllCCBarRows()
    HideAllCCGridCells()

    local yOff   = 0
    local anyBar = false
    local gridIndex = 0

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

            -- Seed a staggered demo bar so the 5 preview bars show a mix of states.
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

            -- PickGuessCC returns a list - every entry gets its own bar.
            -- Only seeds an entry that's new or still just a preview, never
            -- overwrites a witnessed cast; re-evaluated every rebuild.
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

                -- Prune stale entries (guessed or witnessed) not in this
                -- rebuild's list anymore, unless mid-cooldown right now.
                local now = GetTime()
                for sid, st in pairs(unitState) do
                    if not currentGuesses[sid] and st.endTime <= now then
                        unitState[sid] = nil
                    end
                end
            end
        end
    end

    -- Flatten every unit's spells into one list, sorted so the same
    -- spell from different units sits together (e.g. every Frost Nova,
    -- then every Dragon's Breath) instead of grouped per-unit.
    local classOrder = {}
    for i, ci in ipairs(CLASS_INFO or {}) do classOrder[ci.key] = i end
    local origIndex = {}
    for i, u in ipairs(units) do origIndex[u] = i end

    local entries = {}
    for _, unit in ipairs(units) do
        local fakeInfo = TEST_FAKE_LOOKUP[unit]
        local class = fakeInfo and fakeInfo.class or select(2, UnitClass(unit))
        local unitState = ccBarState[unit]
        if class and unitState then
            for sid, st in pairs(unitState) do
                entries[#entries + 1] = { unit = unit, sid = sid, st = st, class = class, fakeInfo = fakeInfo }
            end
        end
    end
    table.sort(entries, function(a, b)
        if a.sid ~= b.sid then return a.sid < b.sid end
        local oa = classOrder[a.class] or math.huge
        local ob = classOrder[b.class] or math.huge
        if oa ~= ob then return oa < ob end
        return (origIndex[a.unit] or math.huge) < (origIndex[b.unit] or math.huge)
    end)

    for _, entry in ipairs(entries) do
        local unit, sid, st, class, fakeInfo = entry.unit, entry.sid, entry.st, entry.class, entry.fakeInfo
              if iconMode then
                -- Get or create grid cell
                ccGridFrames[unit] = ccGridFrames[unit] or {}
                local gf = ccGridFrames[unit][sid]
                if not gf then
                    local cell = CreateFrame("Frame", nil, ccBarsParent)
                    cell:EnableMouse(true)

                    local ico = cell:CreateTexture(nil, "ARTWORK")
                    ico:SetPoint("TOP", cell, "TOP", 0, 0)

                    local nameText = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    nameText:SetJustifyH("CENTER")
                    nameText:SetJustifyV("TOP")

                    local cdText = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    cdText:SetTextColor(1, 1, 0.7)

                    cell:SetScript("OnEnter", function(self)
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
                    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)

                    gf = { cell = cell, ico = ico, nameText = nameText, cdText = cdText }
                    ccGridFrames[unit][sid] = gf
                end

                gf.cell:SetSize(CELL_W, CELL_H)
                gf.ico:SetSize(GICO, GICO)
                if db.iconGridBorder then
                    gf.ico:SetTexCoord(0, 1, 0, 1)
                else
                    gf.ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end

                local tex = GetSpellTexture and GetSpellTexture(sid)
                if tex then gf.ico:SetTexture(tex) end

                local gfp = db.iconGridNameFont or "Fonts\\FRIZQT__.TTF"
                gf.nameText:SetFont(gfp, db.iconGridNameSize or 10, "OUTLINE")
                gf.cdText:SetFont(gfp, db.iconGridTimerSize or 10, "OUTLINE")

                PositionGridText(gf.nameText, gf.ico, db.iconGridNamePosition,
                    db.iconGridNameX or 0, db.iconGridNameY or 0)
                PositionGridText(gf.cdText, gf.ico, db.iconGridTimerPosition,
                    db.iconGridTimerX or 0, db.iconGridTimerY or 0)

                local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                local displayName = (fakeInfo and fakeInfo.name) or UnitName(unit) or unit
                if db.maxNameChars and db.maxNameChars > 0 then
                    displayName = displayName:sub(1, db.maxNameChars)
                end
                gf.nameText:SetText(displayName)
                if cc then gf.nameText:SetTextColor(cc.r, cc.g, cc.b) end

                local col    = gridIndex % GCOLS
                local rowIdx = math.floor(gridIndex / GCOLS)
                local gx     = col * (CELL_W + GAP)
                local vPoint = db.growUp and "BOTTOM" or "TOP"
                local hPoint = db.iconGridGrowLeft and "RIGHT" or "LEFT"
                local point  = vPoint .. hPoint
                local gxOff  = db.iconGridGrowLeft and -gx or gx
                local gyOff  = db.growUp and (rowIdx * (CELL_H + GAP)) or -(rowIdx * (CELL_H + GAP))
                gf.cell:ClearAllPoints()
                gf.cell:SetPoint(point, ccBarsParent, point, gxOff, gyOff)

                st.class = class
                gf.cell:Show()
                gridIndex = gridIndex + 1
                anyBar = true
              else
                -- Get or create bar frames
                ccBarFrames[unit] = ccBarFrames[unit] or {}
                local bf = ccBarFrames[unit][sid]
                if not bf then
                    local row = CreateFrame("Frame", nil, ccBarsParent)

                    -- Border: four edge strips, not one rectangle behind
                    -- everything (would tint through the bar's own bg).
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

                    -- Icon frame (anchored left or right per-rebuild, see db.iconOnRight)
                    local iconF = CreateFrame("Frame", nil, row)
                    iconF:SetSize(ICO, ICO)
                    iconF:EnableMouse(true)

                    local ico = iconF:CreateTexture(nil, "ARTWORK")
                    ico:SetAllPoints()
                    ico:SetTexCoord(0, 1, 0, 1)

                    -- Bound to this exact (unit, sid) pair - each spell has its own bar.
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

                    local sb = CreateFrame("StatusBar", nil, row)
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

                -- Stacks down from top (grow down) or up from bottom (grow up).
                bf.row:SetSize(ROW, BH)
                bf.row:ClearAllPoints()
                if db.growUp then
                    bf.row:SetPoint("BOTTOMLEFT", ccBarsParent, "BOTTOMLEFT", 0, yOff)
                else
                    bf.row:SetPoint("TOPLEFT", ccBarsParent, "TOPLEFT", 0, -yOff)
                end

                -- Icon always matches bar height
                bf.iconF:SetSize(ICO, ICO)
                bf.iconF:ClearAllPoints()
                bf.sb:ClearAllPoints()
                if db.iconOnRight then
                    bf.iconF:SetPoint("RIGHT", bf.row, "RIGHT", 0, 0)
                    bf.sb:SetPoint("LEFT",  bf.row,   "LEFT",  0, 0)
                    bf.sb:SetPoint("RIGHT", bf.iconF, "LEFT",  0, 0)
                else
                    bf.iconF:SetPoint("LEFT", bf.row, "LEFT", 0, 0)
                    bf.sb:SetPoint("LEFT",  bf.iconF, "RIGHT", 0, 0)
                    bf.sb:SetPoint("RIGHT", bf.row,   "RIGHT", 0, 0)
                end

                -- Resize status bar (in case barWidth changed)
                bf.sb:SetHeight(BH)

                local barTex = db.texturePath or DEFAULT_BAR_TEXTURE
                bf.sb:SetStatusBarTexture(barTex)
                bf.sbBg:SetTexture(barTex)

                for _, b in ipairs(bf.border) do b:SetShown(not db.hideBorder) end

                local tex = GetSpellTexture and GetSpellTexture(sid)
                if tex then bf.ico:SetTexture(tex) end

                -- Background track starts grey if on cooldown; the 0.1s ticker corrects it.
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

    -- Resize bars container
    if iconMode then
        local totalCols = math.min(gridIndex, GCOLS)
        local totalRows = gridIndex > 0 and math.ceil(gridIndex / GCOLS) or 0
        local gridWidth  = totalCols > 0 and (totalCols * CELL_W + (totalCols - 1) * GAP) or 1
        local gridHeight = totalRows > 0 and (totalRows * CELL_H + (totalRows - 1) * GAP) or 1
        ccBarsParent:SetSize(gridWidth, gridHeight)
        ccAnchorFrame:SetWidth(gridWidth)
    else
        ccBarsParent:SetSize(math.max(1, ROW), math.max(1, yOff))
        ccAnchorFrame:SetWidth(ROW)
    end

    -- Header space is always reserved (whether locked or not) so the bars never
    -- shift position when the header strip is shown/hidden by locking/unlocking.
    ccAnchorFrame:SetHeight(HEADER_H + math.max(1, yOff))
    ApplyCCGrowLayout()
    ApplyCCAnchorLockState()
    ccAnchorFrame:SetShown(anyBar or not db.locked)
end

-- Called from KastaCD_CombatLog when a known CC spell is cast.
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

    -- Keyed by (unit, spellId) so independent CC spells track separately.
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

    -- Update icon immediately if a bar or grid cell already exists
    local bf = ccBarFrames[unit] and ccBarFrames[unit][spellId]
    local gf = ccGridFrames[unit] and ccGridFrames[unit][spellId]
    local tex = GetSpellTexture and GetSpellTexture(spellId)
    if bf and tex then bf.ico:SetTexture(tex) end
    if gf and tex then gf.ico:SetTexture(tex) end

    -- First-seen (unit, spellId) → need a new row/cell
    local alreadyShown = (bf and bf.row:IsShown()) or (gf and gf.cell:IsShown())
    if not alreadyShown then
        RebuildCCBars()
    end
end

function HandleCCCooldownReducer(sourceGUID, spellId)
    local targetSpellId, reduction
    if spellId == SMITE_SPELL_ID then
        targetSpellId = CHASTISE_SPELL_ID
        reduction = CHASTISE_REDUCTION_BASE
        if IsPlayerSpell and IsPlayerSpell(LIGHT_OF_THE_NAARU_SPELL_ID) then
            reduction = reduction + CHASTISE_REDUCTION_NAARU_BONUS
        end
        if hasApotheosis then
            reduction = reduction + CHASTISE_REDUCTION_APOTHEOSIS_BONUS
        end
    else
        local reducer = CC_COOLDOWN_REDUCERS[spellId]
        if not reducer then return end
        targetSpellId, reduction = reducer.targetSpellId, reducer.reduction
    end

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

    local st = ccBarState[unit] and ccBarState[unit][targetSpellId]
    if not st or not st.endTime then return end

    local now = GetTime()
    if st.endTime <= now then return end

    st.endTime = math.max(now, st.endTime - reduction)
end

C_Timer.NewTicker(0.1, function()
    if type(KastaCDDB) ~= "table" then return end
    local db = GetCCDB()
    if not db.enabled then return end

    local now = GetTime()
    for unit, spells in pairs(ccBarState) do
        local unitFrames     = ccBarFrames[unit]
        local unitGridFrames = ccGridFrames[unit]
        if unitFrames or unitGridFrames then
            for sid, st in pairs(spells) do
                local bf = unitFrames and unitFrames[sid]
                if bf and bf.row:IsShown() then
                    local cd = st.cooldown or 1
                    local cc = RAID_CLASS_COLORS and st.class and RAID_CLASS_COLORS[st.class]
                    if st.endTime and st.endTime > now then
                        local remaining = st.endTime - now
                        -- Inverted: 0 = just used, fills toward 1 = ready
                        bf.sb:SetValue(math.max(0, math.min(1, 1 - remaining / cd)))
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

                        -- Fake demo units loop forever instead of sitting ready.
                        if st.isFake then
                            st.endTime = now + cd
                        end
                    end
                end

                local gf = unitGridFrames and unitGridFrames[sid]
                if gf and gf.cell:IsShown() then
                    if st.endTime and st.endTime > now then
                        local remaining = st.endTime - now
                        gf.ico:SetDesaturated(true)
                        local secs = math.ceil(remaining)
                        gf.cdText:SetText(secs >= 60
                            and (math.floor(secs / 60) .. "m" .. string.format("%02d", secs % 60))
                            or (secs .. "s"))
                    else
                        gf.ico:SetDesaturated(false)
                        gf.cdText:SetText("")
                        if st.isFake then st.endTime = now + (st.cooldown or 1) end
                    end
                end
            end
        end
    end
end)

-- Debug: /kcdccunit <unit> compares ground truth vs PickGuessCC vs persisted state.
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
