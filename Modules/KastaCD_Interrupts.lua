-- KastaCD_Interrupts.lua - independent interrupt cooldown tracker,
-- class-colored status bar per party member, mirrors KastaCD_CC.lua.

-- Default interrupt per class, shown before any cast is seen. Each class
-- maps to a list (some have a different interrupt per spec, e.g. Druid);
-- specs, if present, only matches a unit whose known spec is in the
-- list, first match wins.
local INT_DEFAULT = {
    WARRIOR     = { { spellId=6552,   cooldown=15 } },
    PALADIN     = { { spellId=96231,  cooldown=15, specs={70} } },        -- Ret only (Prot appears via Avenger's Shield cast)
    HUNTER      = { { spellId=147362, cooldown=24 } },                    -- Counter Shot (MM/BM); Survival appears via Muzzle cast
    ROGUE       = { { spellId=1766,   cooldown=15 } },
    DEATHKNIGHT = { { spellId=47528,  cooldown=15 } },
    SHAMAN      = { { spellId=57994,  cooldown=12 } },
    MAGE        = { { spellId=2139,   cooldown=24 } },
    MONK        = { { spellId=116705, cooldown=15 } },
    DRUID       = {
        { spellId=106839, cooldown=15, specs={103,104} },                -- Skull Bash (Feral/Guardian)
        { spellId=78675,  cooldown=60, specs={102} },                    -- Solar Beam (Balance)
    },
    DEMONHUNTER = { { spellId=183752, cooldown=15 } },
}

-- All interrupt spell IDs detected from the combat log
INT_SPELLS = {
    [6552]   = { class="WARRIOR",     cooldown=15 },
    [96231]  = { class="PALADIN",     cooldown=15 },
    [31935]  = { class="PALADIN",     cooldown=15 },  -- Avenger's Shield (Protection)
    [147362] = { class="HUNTER",      cooldown=24 },
    [187707] = { class="HUNTER",      cooldown=15 },  -- Muzzle (Survival)
    [1766]   = { class="ROGUE",       cooldown=15 },
    [15487]  = { class="PRIEST",      cooldown=45 },  -- Silence (Shadow only)
    [47476]  = { class="DEATHKNIGHT", cooldown=60 },  -- Strangulate (Blood)
    [47528]  = { class="DEATHKNIGHT", cooldown=15 },
    [57994]  = { class="SHAMAN",      cooldown=12 },
    [2139]   = { class="MAGE",        cooldown=24 },
    [116705] = { class="MONK",        cooldown=15 },
    [106839] = { class="DRUID",       cooldown=15 },
    [78675]  = { class="DRUID",       cooldown=60 },  -- Solar Beam (Balance)
    [183752] = { class="DEMONHUNTER", cooldown=15 },
    [119910] = { class="WARLOCK",     cooldown=24 },  -- Spell Lock (Felhunter)

    -- Arcane Torrent (Blood Elf racial). isRacial=true routes it to a
    -- separate "#racial" bar per unit instead of overwriting the class-
    -- interrupt bar. This server uses a different spell ID per resource
    -- type; each confirmed via /kcdcast, not guessed.
    [155145] = { class="ALL", cooldown=90,  isRacial=true },  -- Arcane Torrent (confirmed on this server)
    [25046]  = { class="ALL", cooldown=90,  isRacial=true },  -- Arcane Torrent (Energy - Rogue, confirmed)
    [50613]  = { class="ALL", cooldown=90,  isRacial=true },  -- Arcane Torrent (Runic Power - Death Knight, confirmed)
    [129597] = { class="ALL", cooldown=90,  isRacial=true },  -- Arcane Torrent (Chi - Monk, confirmed)
    [232633] = { class="ALL", cooldown=90,  isRacial=true },  -- Arcane Torrent (Priest, confirmed)
    [202719] = { class="ALL", cooldown=90,  isRacial=true },  -- Arcane Torrent (Demon Hunter, confirmed)
    -- Not yet confirmed - a wrong ID is harmless, correct via /kcdcast if wrong.
    [28730]  = { class="ALL", cooldown=90,  isRacial=true },  -- Arcane Torrent (Mana - unconfirmed)
    [69179]  = { class="ALL", cooldown=90,  isRacial=true },  -- Arcane Torrent (Rage - Warrior, unconfirmed)
    [80483]  = { class="ALL", cooldown=90,  isRacial=true },  -- Arcane Torrent (Focus - Hunter, unconfirmed)
}

-- Always-visible racial default per UnitRace() token - an additional bar, not a replacement.
local RACIAL_DEFAULT = {
    BloodElf = { spellId=155145, cooldown=90 },
}

local intBarState  = {}   -- [unit] = { spellId, cooldown, endTime, class }
local intBarFrames = {}   -- [unit] = { row, sb, ico, nameText, cdText }
local intAnchorFrame = nil
local intBarsParent  = nil

-- Five fake party members for Test Mode while solo.
local TEST_FAKE_UNITS = {
    { token="KCDTESTINT1", name="Test Warrior",     class="WARRIOR",     spellId=6552,   cooldown=15 },
    { token="KCDTESTINT2", name="Test Hunter",      class="HUNTER",      spellId=147362, cooldown=24 },
    { token="KCDTESTINT3", name="Test Shaman",      class="SHAMAN",      spellId=57994,  cooldown=12 },
    { token="KCDTESTINT4", name="Test Mage",        class="MAGE",        spellId=2139,   cooldown=24 },
    { token="KCDTESTINT5", name="Test DemonHunter", class="DEMONHUNTER", spellId=183752, cooldown=15 },
}
local TEST_FAKE_LOOKUP = {}
for _, u in ipairs(TEST_FAKE_UNITS) do TEST_FAKE_LOOKUP[u.token] = u end

-- Default statusbar texture when no SharedMedia texture is picked.
local DEFAULT_BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

local function GetIntDB()
    if type(KastaCDDB) ~= "table" then return {barWidth=200,barHeight=20,enabled=true,locked=true,testMode=false,texturePath=DEFAULT_BAR_TEXTURE,hideBorder=false} end
    if type(KastaCDDB.intAnchor) ~= "table" then KastaCDDB.intAnchor = {} end
    local db = KastaCDDB.intAnchor
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
    if db.contentTypes == nil then
        db.contentTypes = {
            ["Open World"]=true, ["Dungeon"]=true,
            ["Arena"]=true,      ["Battleground"]=true,
        }
    end
    -- One toggle controls every isRacial resource-type variant of Arcane Torrent.
    if db.showArcaneTorrent == nil then db.showArcaneTorrent = true end
    return db
end

-- Anchor frame (created once, reused). Header always visible; orange when unlocked.
local HEADER_H = 18
local BORDER_THICKNESS = 2  -- px, thickness of the bar outline strips

-- TOPLEFT for "grow down" (default), BOTTOMLEFT for "grow up".
local function IntAnchorPoint(db)
    return db.growUp and "BOTTOMLEFT" or "TOPLEFT"
end

-- Positions the header/bars container per the current grow direction.
local function ApplyIntGrowLayout()
    local a, bp = intAnchorFrame, intBarsParent
    if not a or not bp then return end
    local db = GetIntDB()

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

local function EnsureIntAnchor()
    if intAnchorFrame then return end

    local db  = GetIntDB()
    local BH  = db.barHeight
    local BW  = db.barWidth
    local ROW = BH + 2 + BW

    local a = CreateFrame("Frame", "KastaCDIntAnchor", UIParent)
    a:SetSize(ROW, HEADER_H)
    a:SetFrameStrata("MEDIUM")   -- above the settings window (which is HIGH)
    a:SetMovable(true)
    a:EnableMouse(true)
    a:RegisterForDrag("LeftButton")
    a:SetScript("OnDragStart", function(self)
        if not GetIntDB().locked then self:StartMoving() end
    end)
    a:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local db2  = GetIntDB()
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

    -- Header label: always "Interrupts"
    local hdrLbl = a:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdrLbl:SetHeight(HEADER_H)
    hdrLbl:SetJustifyH("CENTER")
    hdrLbl:SetJustifyV("MIDDLE")
    hdrLbl:SetText("Interrupts")
    hdrLbl:SetTextColor(0.85, 0.85, 0.85)
    a.hdrLbl = hdrLbl

    -- Restore saved position or default to centre-right
    if db.savedX and db.savedY then
        local esc = a:GetEffectiveScale()
        a:SetPoint(IntAnchorPoint(db), UIParent, "TOPLEFT", db.savedX / esc, db.savedY / esc)
    else
        a:SetPoint(IntAnchorPoint(db), UIParent, "CENTER", 250, 100)
    end

    -- Container for bars (exact position set by ApplyIntGrowLayout below)
    local bp = CreateFrame("Frame", nil, a)
    bp:SetSize(1, 1)

    -- Hidden by default; RebuildInterruptBars/UnlockIntAnchor own real visibility.
    a:Hide()

    intAnchorFrame = a
    intBarsParent  = bp
    ApplyIntGrowLayout()
end

-- Re-applies the saved position without recreating anything - called a
-- couple seconds after PLAYER_ENTERING_WORLD to fix occasional post-
-- reload pixel drift (UIParent scale not fully settled yet).
function ReapplyIntAnchorPos()
    if not intAnchorFrame then return end
    local db = GetIntDB()
    if not (db.savedX and db.savedY) then return end
    local esc = intAnchorFrame:GetEffectiveScale()
    intAnchorFrame:ClearAllPoints()
    intAnchorFrame:SetPoint(IntAnchorPoint(db), UIParent, "TOPLEFT", db.savedX / esc, db.savedY / esc)
end

-- Lets clicks pass through to whatever's underneath, only while locked.
function ApplyIntClickThrough()
    if not intAnchorFrame then return end
    local db = GetIntDB()
    local through = db.clickThrough and db.locked
    intAnchorFrame:EnableMouse(not through)
    if intBarsParent then
        for _, row in ipairs({ intBarsParent:GetChildren() }) do
            if row.EnableMouse then row:EnableMouse(not through) end
            for _, child in ipairs({ row:GetChildren() }) do
                if child.EnableMouse then child:EnableMouse(not through) end
            end
        end
    end
end

-- Show/hide the header strip based on lock state.
-- Size/position adjustments are handled inside RebuildInterruptBars.
local function ApplyIntAnchorLockState()
    if not intAnchorFrame then return end
    if GetIntDB().locked then
        intAnchorFrame.hdrBg:Hide()
        intAnchorFrame.hdrLbl:Hide()
    else
        intAnchorFrame.hdrBg:SetColorTexture(1, 0.55, 0, 0.9)
        intAnchorFrame.hdrBg:Show()
        intAnchorFrame.hdrLbl:SetTextColor(1, 1, 1)
        intAnchorFrame.hdrLbl:Show()
    end
    ApplyIntClickThrough()
end

-- ─────────────────────────────────────────────────────────────
-- Lock / unlock helpers (called from UI settings panel)
-- ─────────────────────────────────────────────────────────────
function LockIntAnchor()
    GetIntDB().locked = true
    ApplyIntAnchorLockState()
    -- Without this, locking while solo left the anchor/bars showing in
    -- whatever state they were in while unlocked - ApplyIntAnchorLockState
    -- only toggles the header strip, not the in-group/instance/content-type
    -- gating that decides whether the anchor should be visible at all.
    -- RebuildInterruptBars() re-applies all of that immediately, same as
    -- UnlockIntAnchor() already does on the way in.
    RebuildInterruptBars()
end

function UnlockIntAnchor()
    GetIntDB().locked = false
    EnsureIntAnchor()
    ApplyIntAnchorLockState()
    intAnchorFrame:Show()
    RebuildInterruptBars()
end

-- Sets the anchor's exact saved position (same units as OnDragStop below
-- writes) and repositions the live frame immediately - used by the
-- Position X/Y sliders in the settings panel for pixel-perfect placement
-- without needing to drag. EnsureIntAnchor() is a no-op if the frame
-- already exists, so this works whether or not it's been created yet.
function SetIntAnchorPos(x, y)
    EnsureIntAnchor()
    local db = GetIntDB()
    db.savedX = x
    db.savedY = y
    local esc = intAnchorFrame:GetEffectiveScale()
    intAnchorFrame:ClearAllPoints()
    intAnchorFrame:SetPoint(IntAnchorPoint(db), UIParent, "TOPLEFT", x / esc, y / esc)
end

-- Returns the anchor's current resolved x/y in the same units
-- SetIntAnchorPos expects. If nothing's been saved yet (anchor still
-- sitting at its CENTER-relative default), this reads the *actual* live
-- position off the frame instead of returning 0/0 - otherwise the
-- Position X/Y sliders in settings would snap the anchor to the corner
-- of the screen the moment either one is touched, since writing one axis
-- always writes both and the other would fall back to a wrong default.
function GetIntAnchorPos()
    EnsureIntAnchor()
    local db = GetIntDB()
    if db.savedX and db.savedY then
        return db.savedX, db.savedY
    end
    local esc = intAnchorFrame:GetEffectiveScale()
    local usc = UIParent:GetEffectiveScale()
    local x = intAnchorFrame:GetLeft() * esc
    local refY = db.growUp and intAnchorFrame:GetBottom() or intAnchorFrame:GetTop()
    local y = (refY * esc) - (UIParent:GetTop() * usc)
    return x, y
end

-- Clears a unit's stored state so the next rebuild re-guesses from
-- scratch - needed since a spec change can make witnessed "ground truth"
-- wrong. Called from KastaCD_Events.lua on spec change.
function ClearIntBarState(unit)
    intBarState[unit] = nil
end

function RebuildInterruptBars()
    local db = GetIntDB()

    if not db.enabled then
        if intAnchorFrame then intAnchorFrame:Hide() end
        return
    end

    -- Hidden unless in a group, unlocked, or test mode.
    if db.locked and not IsInGroup() and not db.testMode then
        if intAnchorFrame then intAnchorFrame:Hide() end
        for _, bf in pairs(intBarFrames) do bf.row:Hide() end
        return
    end

    local _, instanceType = IsInInstance()
    if db.locked and instanceType == "raid" then
        if intAnchorFrame then intAnchorFrame:Hide() end
        for _, bf in pairs(intBarFrames) do bf.row:Hide() end
        return
    end

    -- This tracker's own "Active in:" gating, independent of the others.
    if db.locked and not db.testMode and type(IsContentEnabledFor) == "function" and not IsContentEnabledFor(db.contentTypes) then
        if intAnchorFrame then intAnchorFrame:Hide() end
        for _, bf in pairs(intBarFrames) do bf.row:Hide() end
        return
    end

    EnsureIntAnchor()

    -- Test Mode always substitutes 5 fake units, solo or grouped.
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

        -- Sort by class so same-class units end up adjacent, before racial rows are appended.
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

        -- Appends a synthetic "<unit>#racial" entry (a second, additional
        -- bar) for anyone whose race has an always-on racial default, or
        -- who already has a witnessed racial cast (covers UnitRace()
        -- reporting an unexpected token on some servers). Gated by
        -- db.showArcaneTorrent, which suppresses every isRacial variant at once.
        if db.showArcaneTorrent then
            local racialUnits = {}
            for _, u in ipairs(units) do
                local _, raceToken = UnitRace(u)
                local hasDefault    = raceToken and RACIAL_DEFAULT[raceToken]
                local hasWitnessed  = intBarState[u .. "#racial"] ~= nil
                if hasDefault or hasWitnessed then
                    racialUnits[#racialUnits + 1] = u .. "#racial"
                end
            end
            for _, ru in ipairs(racialUnits) do units[#units + 1] = ru end
        end
    end

    local BH  = db.barHeight
    local BW  = db.barWidth
    local ICO = BH  -- icon is square, matches bar height
    local ROW = ICO + BW  -- total row width

    for _, bf in pairs(intBarFrames) do
        bf.row:Hide()
    end

    local yOff   = 0
    local anyBar = false

    for i, unit in ipairs(units) do
        local fakeInfo = TEST_FAKE_LOOKUP[unit]
        -- "#racial" rows resolve class/name from the real base unit token.
        local baseUnit    = unit:match("^(.*)#racial$")
        local isRacialRow = baseUnit ~= nil
        if not isRacialRow then baseUnit = unit end
        local class
        if fakeInfo then
            class = fakeInfo.class
        else
            local _, c = UnitClass(baseUnit)
            class = c
        end
        if class then
            local st     = intBarState[unit]
            local defInt
            if isRacialRow then
                local _, raceToken = UnitRace(baseUnit)
                defInt = raceToken and RACIAL_DEFAULT[raceToken]
            else
                -- Exact spec match wins; spec-less candidate only used as fallback.
                local candidates = INT_DEFAULT[class]
                if candidates then
                    local specId = (not fakeInfo) and type(GetUnitSpec) == "function" and GetUnitSpec(unit)
                    for _, cand in ipairs(candidates) do
                        if not cand.specs then
                            defInt = defInt or cand
                        elseif specId then
                            for _, s in ipairs(cand.specs) do
                                if s == specId then defInt = cand end
                            end
                        end
                    end
                end
            end

            -- Seed a staggered demo bar so the 5 preview bars show a mix of states.
            if fakeInfo and not st then
                local frac = (i - 1) / 5
                intBarState[unit] = {
                    spellId  = fakeInfo.spellId,
                    cooldown = fakeInfo.cooldown,
                    endTime  = GetTime() + fakeInfo.cooldown * (1 - frac),
                    class    = class,
                    isFake   = true,
                }
                st = intBarState[unit]
            end

            local spellId = (st and st.spellId)  or (defInt and defInt.spellId)
            local cd      = (st and st.cooldown) or (defInt and defInt.cooldown)

            if spellId and cd then
                -- Get or create bar frames
                local bf = intBarFrames[unit]
                if not bf then
                    local row = CreateFrame("Frame", nil, intBarsParent)

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

                    local iconF = CreateFrame("Frame", nil, row)
                    iconF:SetSize(ICO, ICO)
                    iconF:SetPoint("LEFT", row, "LEFT", 0, 0)
                    iconF:EnableMouse(true)

                    local ico = iconF:CreateTexture(nil, "ARTWORK")
                    ico:SetAllPoints()
                    ico:SetTexCoord(0, 1, 0, 1)

                    -- Always reads the unit's current tracked spell, not the row-creation-time one.
                    iconF:SetScript("OnEnter", function(self)
                        local liveSt = intBarState[unit]
                        local sid    = liveSt and liveSt.spellId
                        if not sid then return end
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        local ok = pcall(function() GameTooltip:SetSpellByID(sid) end)
                        if not ok then
                            local fake = TEST_FAKE_LOOKUP[unit]
                            GameTooltip:SetText((fake and fake.name) or UnitName(baseUnit) or unit, 1, 1, 1)
                        end
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddDoubleLine("Cooldown:",
                            (liveSt.cooldown or 0) .. "s", 0.7, 0.7, 0.7, 1, 1, 1)
                        GameTooltip:Show()
                    end)
                    iconF:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
                    intBarFrames[unit] = bf
                end

                -- Stacks down from top (grow down) or up from bottom (grow up).
                bf.row:SetSize(ROW, BH)
                bf.row:ClearAllPoints()
                if db.growUp then
                    bf.row:SetPoint("BOTTOMLEFT", intBarsParent, "BOTTOMLEFT", 0, yOff)
                else
                    bf.row:SetPoint("TOPLEFT", intBarsParent, "TOPLEFT", 0, -yOff)
                end

                bf.iconF:SetSize(ICO, ICO)
                bf.sb:SetHeight(BH)

                local barTex = db.texturePath or DEFAULT_BAR_TEXTURE
                bf.sb:SetStatusBarTexture(barTex)
                bf.sbBg:SetTexture(barTex)

                for _, b in ipairs(bf.border) do b:SetShown(not db.hideBorder) end

                local tex = GetSpellTexture and GetSpellTexture(spellId)
                if tex then bf.ico:SetTexture(tex) end

                -- Background track starts grey if on cooldown; the 0.1s ticker corrects it.
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

                -- Name (shortened to Max Name Characters if set - 0 = no limit)
                local displayName = (fakeInfo and fakeInfo.name) or UnitName(baseUnit) or baseUnit
                if db.maxNameChars and db.maxNameChars > 0 then
                    displayName = displayName:sub(1, db.maxNameChars)
                end
                bf.nameText:SetText(displayName)

                -- Initialise state if not yet tracked
                if not intBarState[unit] then
                    intBarState[unit] = { spellId=spellId, cooldown=cd, endTime=0, class=class }
                else
                    if not intBarState[unit].spellId  then intBarState[unit].spellId  = spellId end
                    if not intBarState[unit].cooldown then intBarState[unit].cooldown = cd end
                    intBarState[unit].class = class
                end

                bf.row:Show()
                yOff   = yOff + BH
                anyBar = true
            end
        end
    end

    intBarsParent:SetSize(math.max(1, ROW), math.max(1, yOff))
    intAnchorFrame:SetWidth(ROW)

    -- Header space is always reserved so bars don't shift when locking/unlocking.
    intAnchorFrame:SetHeight(HEADER_H + math.max(1, yOff))
    ApplyIntGrowLayout()
    ApplyIntAnchorLockState()
    intAnchorFrame:SetShown(anyBar or not db.locked)
end

-- Called from KastaCD_CombatLog when a known interrupt is cast.
function HandleInterruptCast(sourceGUID, spellId)
    local intInfo = INT_SPELLS[spellId]
    if not intInfo then return end

    local baseUnit = nil
    if UnitGUID("player") == sourceGUID then
        baseUnit = "player"
    else
        for i = 1, 4 do
            local u = "party" .. i
            if UnitGUID(u) == sourceGUID then
                baseUnit = u
                break
            end
        end
    end
    if not baseUnit then return end

    -- Racial abilities get their own separate "#racial" bar per unit.
    local unit = intInfo.isRacial and (baseUnit .. "#racial") or baseUnit

    local now = GetTime()
    local _, class = UnitClass(baseUnit)

    if not intBarState[unit] then
        intBarState[unit] = { spellId=spellId, cooldown=intInfo.cooldown, endTime=0, class=class or intInfo.class }
    end

    local st      = intBarState[unit]
    st.spellId    = spellId
    st.cooldown   = intInfo.cooldown
    st.endTime    = now + intInfo.cooldown
    st.class      = class or st.class

    local bf = intBarFrames[unit]
    if bf then
        local tex = GetSpellTexture and GetSpellTexture(spellId)
        if tex then bf.ico:SetTexture(tex) end
    end

    if not bf or not bf.row:IsShown() then
        RebuildInterruptBars()
    end
end

C_Timer.NewTicker(0.1, function()
    if type(KastaCDDB) ~= "table" then return end
    local db = GetIntDB()
    if not db.enabled then return end

    local now = GetTime()
    for unit, st in pairs(intBarState) do
        local bf = intBarFrames[unit]
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
    end
end)
