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
    -- WARRIOR
    [46968]  = { class="WARRIOR",     cooldown=40,  specs={73}      },                    -- Shockwave (Protection, baseline)
    [107570] = { class="WARRIOR",     cooldown=30,  isTalent=true   },                    -- Storm Bolt (talent)

    -- PALADIN
    [853]    = { class="PALADIN",     cooldown=60                   },                    -- Hammer of Justice
    [20066]  = { class="PALADIN",     cooldown=15,  specs={65,70},  isTalent=true },       -- Repentance (Holy/Ret talent)

    -- HUNTER
    [109248] = { class="HUNTER",      cooldown=45,  specs={253,254},isTalent=true },       -- Binding Shot (BM/MM talent)
    [24394]  = { class="HUNTER",      cooldown=60,  specs={253}     },                    -- Intimidation (BM pet, baseline)
    [19386]  = { class="HUNTER",      cooldown=45,  specs={254},    isTalent=true },       -- Wyvern Sting (MM talent)

    -- ROGUE
    [6770]   = { class="ROGUE",       cooldown=20                   },                    -- Sap
    [2094]   = { class="ROGUE",       cooldown=120                  },                    -- Blind
    [1776]   = { class="ROGUE",       cooldown=10,  specs={260},    isTalent=true },       -- Gouge (Outlaw, uncertain baseline/talent)
    -- Kidney Shot is a combo-point finisher with no real fixed cooldown
    -- (spammable off the GCD whenever combo points allow) - cooldown here
    -- is a short nominal "just used" flash, not a real timer. isTalent=true
    -- keeps it out of the default-guess pool (see PickGuessCC below) so it
    -- never shows as someone's *default* bar - only after an actual
    -- witnessed cast.
    [408]    = { class="ROGUE",       cooldown=2,   isTalent=true   },                    -- Kidney Shot

    -- DEATHKNIGHT
    [108194] = { class="DEATHKNIGHT", cooldown=45,  specs={252}     },                    -- Asphyxiate (Unholy, baseline)
    [221562] = { class="DEATHKNIGHT", cooldown=45,  specs={250}     },                    -- Asphyxiate (Blood, baseline)

    -- SHAMAN
    [51514]  = { class="SHAMAN",      cooldown=30                   },                    -- Hex
    [192058] = { class="SHAMAN",      cooldown=60,  specs={262}     },                    -- Capacitor Totem (Elemental, baseline)
    [51485]  = { class="SHAMAN",      cooldown=30,  specs={262,263},isTalent=true },       -- Earthgrab Totem (Ele/Enh, uncertain)

    -- MAGE
    [122]    = { class="MAGE",        cooldown=25                   },                    -- Frost Nova
    [113724] = { class="MAGE",        cooldown=45,  isTalent=true   },                    -- Ring of Frost (talent)
    [31661]  = { class="MAGE",        cooldown=20,  specs={63}      },                    -- Dragon's Breath (Fire only, baseline)
    [44572]  = { class="MAGE",        cooldown=25,  specs={64}      },                    -- Deep Freeze (Frost only, baseline)

    -- PRIEST
    [88625]  = { class="PRIEST",      cooldown=30,  specs={257}     },                    -- Holy Word: Chastise (Holy, baseline)

    -- WARLOCK
    [30283]  = { class="WARLOCK",     cooldown=60                   },                    -- Shadowfury

    -- MONK
    [119381] = { class="MONK",        cooldown=45                   },                    -- Leg Sweep
    [115078] = { class="MONK",        cooldown=45,  isTalent=true   },                    -- Paralysis (talent)

    -- DRUID
    [5211]   = { class="DRUID",       cooldown=50,  specs={103,104},isTalent=true },       -- Mighty Bash (Feral/Guardian talent)

    -- DEMONHUNTER
    [179057] = { class="DEMONHUNTER", cooldown=45,  specs={577},    isTalent=true },       -- Chaos Nova (Havoc talent)
    [217832] = { class="DEMONHUNTER", cooldown=90                   },                    -- Imprison

    -- Arcane Torrent (Blood Elf racial) moved to the Interrupt tracker's
    -- INT_SPELLS - see KastaCD_Interrupts.lua. `race`/class="ALL" support
    -- above is kept in place for any future racial CC additions.
}

-- Per-unit state and bar frames
local ccBarState  = {}   -- [unit] = { spellId, cooldown, endTime, class }
local ccBarFrames = {}   -- [unit] = { row, sb, ico, nameText, cdText }
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
    return db
end

-- Picks a CC_SPELLS entry matching the given class (and, when known, the
-- unit's actual current spec) to serve as their default bar - there's no
-- static CC_DEFAULT, see the comment above that table for why. Prefers a
-- spec-matching or spec-unrestricted (baseline) spell over one that's
-- simply the first entry found for the class, so an Arcane Mage doesn't
-- get shown a Fire-only spell like Dragon's Breath.
--
-- isTalent=true entries are always skipped here - spec alone can't tell
-- us which talent was picked (e.g. Shockwave and Storm Bolt are both
-- valid for Protection), so guessing one would just be wrong as often as
-- right. Those only ever appear once actually witnessed via combat log.
--
-- raceToken (from UnitRace(unit)'s second return) gates race-restricted
-- entries (class="ALL", e.g. Arcane Torrent) the same way specId gates
-- spec-restricted ones - an entry with a race requirement is skipped for
-- anyone who isn't that race, regardless of class/spec match.
local function PickGuessCC(class, specId, raceToken)
    local fallback = nil
    for sid, info in pairs(CC_SPELLS) do
        local classOk = info.class == class or info.class == "ALL"
        local raceOk  = not info.race or info.race == raceToken
        if classOk and raceOk and not info.isTalent then
            if not info.specs then
                -- Baseline for every spec - good enough unless something
                -- more specific (an exact spec match) turns up.
                fallback = fallback or { spellId = sid, cooldown = info.cooldown }
            elseif specId then
                for _, s in ipairs(info.specs) do
                    if s == specId then
                        return { spellId = sid, cooldown = info.cooldown }
                    end
                end
            end
        end
    end
    return fallback
end

-- ─────────────────────────────────────────────────────────────
-- Anchor frame (created once, reused)
-- Header is always visible when bars are shown; turns orange when unlocked.
-- ─────────────────────────────────────────────────────────────
local HEADER_H = 18
local BORDER_THICKNESS = 2  -- px, thickness of the bar outline strips

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
        db2.savedX = self:GetLeft()  * esc
        db2.savedY = (self:GetTop()  * esc) - (UIParent:GetTop() * usc)
    end)

    -- Header background strip (dark normally, orange when unlocked)
    local hdrBg = a:CreateTexture(nil, "BACKGROUND", nil, 1)
    hdrBg:SetPoint("TOPLEFT",  a, "TOPLEFT",  0, 0)
    hdrBg:SetPoint("TOPRIGHT", a, "TOPRIGHT", 0, 0)
    hdrBg:SetHeight(HEADER_H)
    hdrBg:SetColorTexture(0.12, 0.12, 0.12, 0.9)
    a.hdrBg = hdrBg

    -- Header label: always "Crowd Control"
    local hdrLbl = a:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdrLbl:SetPoint("TOPLEFT",  a, "TOPLEFT",  0, 0)
    hdrLbl:SetPoint("TOPRIGHT", a, "TOPRIGHT", 0, 0)
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
        a:SetPoint("TOPLEFT", UIParent, "TOPLEFT", db.savedX / esc, db.savedY / esc)
    else
        a:SetPoint("CENTER", UIParent, "CENTER", 250, -50)
    end

    -- Container for bars (position managed by RebuildCCBars)
    local bp = CreateFrame("Frame", nil, a)
    bp:SetPoint("TOPLEFT", a, "TOPLEFT", 0, 0)
    bp:SetSize(1, 1)

    ccAnchorFrame = a
    ccBarsParent  = bp
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
end

-- ─────────────────────────────────────────────────────────────
-- Lock / unlock helpers (called from UI settings panel)
-- ─────────────────────────────────────────────────────────────
function LockCCAnchor()
    GetCCDB().locked = true
    ApplyCCAnchorLockState()
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
    ccAnchorFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x / esc, y / esc)
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
    local y = (ccAnchorFrame:GetTop() * esc) - (UIParent:GetTop() * usc)
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

    -- Hide entirely when the current content type is disabled via the
    -- Settings panel's "Active in:" toggles, same unlocked/testMode
    -- exception as above - matches the main icon tracker's own gating
    -- (IsContentEnabled in KastaCD_DB.lua).
    if db.locked and not db.testMode and type(IsContentEnabled) == "function" and not IsContentEnabled() then
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

    local BH  = db.barHeight
    local BW  = db.barWidth
    local ICO = BH  -- icon is square, matches bar height
    local ROW = ICO + BW  -- total row width

    -- Hide all rows; we re-show only the ones that are active
    for _, bf in pairs(ccBarFrames) do
        bf.row:Hide()
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
            local st     = ccBarState[unit]
            local defCC  = CC_DEFAULT[class]
            local isPreviewPick = false

            -- Seed a fully "live" animated demo bar the first time a fake
            -- unit is seen: staggered cooldown position (spread across
            -- 0%-80% remaining) so the 5 preview bars show a mix of
            -- states - just used, mid-cooldown, nearly ready - instead of
            -- all sitting idle-ready. The ticker keeps looping it once it
            -- reaches ready, so the animation runs continuously.
            if fakeInfo and not st then
                local frac = (i - 1) / 5
                ccBarState[unit] = {
                    spellId  = fakeInfo.spellId,
                    cooldown = fakeInfo.cooldown,
                    endTime  = GetTime() + fakeInfo.cooldown * (1 - frac),
                    class    = class,
                    isFake   = true,
                }
                st = ccBarState[unit]
            end

            -- No static default for this class: guess a spec-appropriate
            -- spell so the bar shows something immediately, same as the
            -- interrupt tracker's INT_DEFAULT. Only substitutes for
            -- nothing or a *previous guess* (st.isPreview) - never a real
            -- witnessed cast, never a fake unit (already seeded above) -
            -- and re-evaluates every rebuild so a talent/spec swap (e.g.
            -- Storm Bolt -> Shockwave) updates it immediately instead of
            -- getting stuck on the first guess.
            if not fakeInfo and not defCC and (not st or st.isPreview) then
                local specId    = type(GetUnitSpec) == "function" and GetUnitSpec(unit)
                local raceToken = select(2, UnitRace(unit))
                defCC = PickGuessCC(class, specId, raceToken)
                isPreviewPick = true
            end

            local spellId = (not isPreviewPick and st and st.spellId)  or (defCC and defCC.spellId)
            local cd      = (not isPreviewPick and st and st.cooldown) or (defCC and defCC.cooldown)

            if spellId and cd then
                -- Get or create bar frames
                local bf = ccBarFrames[unit]
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

                    -- Tooltip: always reads the unit's *current* tracked spell
                    -- (not the one captured at row-creation time), since the
                    -- CC bound to a unit changes as they cast different spells.
                    iconF:SetScript("OnEnter", function(self)
                        local liveSt = ccBarState[unit]
                        local sid    = liveSt and liveSt.spellId
                        if not sid then return end
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
                    ccBarFrames[unit] = bf
                end

                -- Resize / reposition
                bf.row:SetSize(ROW, BH)
                bf.row:ClearAllPoints()
                bf.row:SetPoint("TOPLEFT", ccBarsParent, "TOPLEFT", 0, -yOff)

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
                local tex = GetSpellTexture and GetSpellTexture(spellId)
                if tex then bf.ico:SetTexture(tex) end

                -- Class colour: fill always class-colored, background
                -- track starts grey if already on cooldown so there's no
                -- flash of the wrong colour before the next 0.1s ticker
                -- tick corrects it - the ticker owns this for everything
                -- after the first draw.
                local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                if cc then
                    bf.sb:SetStatusBarColor(cc.r, cc.g, cc.b, 0.9)
                    local onCooldown = st and st.endTime and st.endTime > GetTime()
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

                -- Name
                bf.nameText:SetText((fakeInfo and fakeInfo.name) or UnitName(unit) or unit)

                -- Initialise/refresh state. A preview pick is fabricated,
                -- not ground truth, so it's always overwritten wholesale
                -- (letting a talent/spec swap replace it); real state only
                -- has missing fields filled in, never overwritten.
                if isPreviewPick then
                    ccBarState[unit] = { spellId=spellId, cooldown=cd, endTime=0, class=class, isPreview=true }
                elseif not ccBarState[unit] then
                    ccBarState[unit] = { spellId=spellId, cooldown=cd, endTime=0, class=class }
                else
                    if not ccBarState[unit].spellId  then ccBarState[unit].spellId  = spellId end
                    if not ccBarState[unit].cooldown then ccBarState[unit].cooldown = cd end
                    ccBarState[unit].class = class
                end

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
    ccBarsParent:ClearAllPoints()
    ccAnchorFrame:SetHeight(HEADER_H + math.max(1, yOff))
    ccBarsParent:SetPoint("TOPLEFT", ccAnchorFrame, "TOPLEFT", 0, -HEADER_H)
    ApplyCCAnchorLockState()
    ccAnchorFrame:SetShown(anyBar or not db.locked)
end

-- ─────────────────────────────────────────────────────────────
-- Called from KastaCD_CombatLog when a known CC spell is cast
-- ─────────────────────────────────────────────────────────────
function HandleCCCast(sourceGUID, spellId)
    local ccInfo = CC_SPELLS[spellId]
    if not ccInfo then return end

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

    if not ccBarState[unit] then
        ccBarState[unit] = { spellId=spellId, cooldown=ccInfo.cooldown, endTime=0, class=class or ccInfo.class }
    end

    local st      = ccBarState[unit]
    st.spellId    = spellId
    st.cooldown   = ccInfo.cooldown
    st.endTime    = now + ccInfo.cooldown
    st.class      = class or st.class
    st.isPreview  = nil  -- real cast is ground truth, overrides any prior spec-based guess

    -- Update icon immediately if bar already exists
    local bf = ccBarFrames[unit]
    if bf then
        local tex = GetSpellTexture and GetSpellTexture(spellId)
        if tex then bf.ico:SetTexture(tex) end
    end

    -- First-seen unit → need a new bar row
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
    for unit, st in pairs(ccBarState) do
        local bf = ccBarFrames[unit]
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
                bf.cdText:SetText("")

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
end)
