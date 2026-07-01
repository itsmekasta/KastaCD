-- =============================================================
-- KastaCD_Interrupts.lua
-- Independent interrupt cooldown tracker.
-- Shows a class-colored status bar for each party member with
-- an interrupt, tracking cooldown remaining after each use.
-- Completely independent of the main cooldown anchor/icon system.
-- =============================================================

-- Default interrupt per class (shown before any cast is seen).
-- specs: if present, only show when the unit's known spec matches one of these.
-- Units whose spec isn't yet known won't show a default bar until their first cast.
local INT_DEFAULT = {
    WARRIOR     = { spellId=6552,   cooldown=15 },
    PALADIN     = { spellId=96231,  cooldown=15, specs={70} },           -- Ret only (Prot appears via Avenger's Shield cast)
    HUNTER      = { spellId=147362, cooldown=24 },                       -- Counter Shot (MM/BM); Survival appears via Muzzle cast
    ROGUE       = { spellId=1766,   cooldown=15 },
    DEATHKNIGHT = { spellId=47528,  cooldown=15 },
    SHAMAN      = { spellId=57994,  cooldown=12 },
    MAGE        = { spellId=2139,   cooldown=24 },
    MONK        = { spellId=116705, cooldown=15 },
    DRUID       = { spellId=106839, cooldown=15, specs={103,104} },      -- Feral, Guardian only
    DEMONHUNTER = { spellId=183752, cooldown=15 },
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
    [183752] = { class="DEMONHUNTER", cooldown=15 },
    [119910] = { class="WARLOCK",     cooldown=24 },  -- Spell Lock (Felhunter)
}

-- Per-unit state and bar frames
local intBarState  = {}   -- [unit] = { spellId, cooldown, endTime, class }
local intBarFrames = {}   -- [unit] = { row, sb, ico, nameText, cdText }
local intAnchorFrame = nil
local intBarsParent  = nil

-- Five synthetic "party members" used only for Test Mode while solo (no
-- real party exists to preview against). Picked for class-color variety.
-- Each token is fake and never resolves via the real
-- UnitClass/UnitName/UnitGUID APIs - see the class/name-resolution
-- branches in RebuildInterruptBars for how that's handled, and the
-- ticker for how their cooldowns loop forever instead of sitting "ready"
-- after the first cycle.
local TEST_FAKE_UNITS = {
    { token="KCDTESTINT1", name="Test Warrior",     class="WARRIOR",     spellId=6552,   cooldown=15 },
    { token="KCDTESTINT2", name="Test Hunter",      class="HUNTER",      spellId=147362, cooldown=24 },
    { token="KCDTESTINT3", name="Test Shaman",      class="SHAMAN",      spellId=57994,  cooldown=12 },
    { token="KCDTESTINT4", name="Test Mage",        class="MAGE",        spellId=2139,   cooldown=24 },
    { token="KCDTESTINT5", name="Test DemonHunter", class="DEMONHUNTER", spellId=183752, cooldown=15 },
}
local TEST_FAKE_LOOKUP = {}
for _, u in ipairs(TEST_FAKE_UNITS) do TEST_FAKE_LOOKUP[u.token] = u end

-- ─────────────────────────────────────────────────────────────
-- DB accessor with lazy defaults
-- ─────────────────────────────────────────────────────────────
-- Default statusbar texture, used whenever no SharedMedia texture has
-- been picked (or SharedMedia/LibStub isn't installed at all).
local DEFAULT_BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

local function GetIntDB()
    if type(KastaCDDB) ~= "table" then return {barWidth=200,barHeight=20,enabled=true,locked=true,testMode=false,texturePath=DEFAULT_BAR_TEXTURE} end
    if type(KastaCDDB.intAnchor) ~= "table" then KastaCDDB.intAnchor = {} end
    local db = KastaCDDB.intAnchor
    if db.barWidth    == nil then db.barWidth    = 200 end
    if db.barHeight   == nil then db.barHeight   = 20  end
    if db.enabled     == nil then db.enabled     = true end
    if db.locked      == nil then db.locked      = true end
    if db.testMode    == nil then db.testMode    = false end
    if db.texturePath == nil then db.texturePath = DEFAULT_BAR_TEXTURE end
    return db
end

-- ─────────────────────────────────────────────────────────────
-- Anchor frame (created once, reused)
-- Header is always visible when bars are shown; turns orange when unlocked.
-- ─────────────────────────────────────────────────────────────
local HEADER_H = 18

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

    -- Header label: always "Interrupts"
    local hdrLbl = a:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdrLbl:SetPoint("TOPLEFT",  a, "TOPLEFT",  0, 0)
    hdrLbl:SetPoint("TOPRIGHT", a, "TOPRIGHT", 0, 0)
    hdrLbl:SetHeight(HEADER_H)
    hdrLbl:SetJustifyH("CENTER")
    hdrLbl:SetJustifyV("MIDDLE")
    hdrLbl:SetText("Interrupts")
    hdrLbl:SetTextColor(0.85, 0.85, 0.85)
    a.hdrLbl = hdrLbl

    -- Restore saved position or default to centre-right
    if db.savedX and db.savedY then
        local esc = a:GetEffectiveScale()
        a:SetPoint("TOPLEFT", UIParent, "TOPLEFT", db.savedX / esc, db.savedY / esc)
    else
        a:SetPoint("CENTER", UIParent, "CENTER", 250, 100)
    end

    -- Container for bars (position managed by RebuildInterruptBars)
    local bp = CreateFrame("Frame", nil, a)
    bp:SetPoint("TOPLEFT", a, "TOPLEFT", 0, 0)
    bp:SetSize(1, 1)

    intAnchorFrame = a
    intBarsParent  = bp
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
end

-- ─────────────────────────────────────────────────────────────
-- Lock / unlock helpers (called from UI settings panel)
-- ─────────────────────────────────────────────────────────────
function LockIntAnchor()
    GetIntDB().locked = true
    ApplyIntAnchorLockState()
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
    intAnchorFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x / esc, y / esc)
end

-- ─────────────────────────────────────────────────────────────
-- Rebuild all interrupt bars
-- ─────────────────────────────────────────────────────────────
function RebuildInterruptBars()
    local db = GetIntDB()

    if not db.enabled then
        if intAnchorFrame then intAnchorFrame:Hide() end
        return
    end

    -- Hide entirely when not in a party or raid group, unless test mode is
    -- on or the anchor is unlocked - unlocking always has to make the
    -- anchor visible, otherwise there'd be nothing to drag while solo.
    if db.locked and not IsInGroup() and not db.testMode then
        if intAnchorFrame then intAnchorFrame:Hide() end
        for _, bf in pairs(intBarFrames) do bf.row:Hide() end
        return
    end

    -- Hide entirely inside raid instances (10-man and above), same
    -- unlocked exception as above.
    local _, instanceType = IsInInstance()
    if db.locked and instanceType == "raid" then
        if intAnchorFrame then intAnchorFrame:Hide() end
        for _, bf in pairs(intBarFrames) do bf.row:Hide() end
        return
    end

    EnsureIntAnchor()

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
    for _, bf in pairs(intBarFrames) do
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
            local st     = intBarState[unit]
            local defInt = INT_DEFAULT[class]

            -- Seed a fully "live" animated demo bar the first time a fake
            -- unit is seen: staggered cooldown position (spread across
            -- 0%-80% remaining) so the 5 preview bars show a mix of
            -- states - just used, mid-cooldown, nearly ready - instead of
            -- all sitting idle-ready. The ticker keeps looping it once it
            -- reaches ready, so the animation runs continuously.
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

            -- Spec gate: if the default interrupt is spec-restricted, check before using it.
            -- Falls back to nil (no bar) until a cast is observed via combat log.
            -- Fake units skip this entirely - they're already fully seeded above.
            if not fakeInfo and defInt and defInt.specs then
                local specId = type(GetUnitSpec) == "function" and GetUnitSpec(unit)
                local specOk = false
                if specId then
                    for _, s in ipairs(defInt.specs) do
                        if s == specId then specOk = true; break end
                    end
                end
                if not specOk then defInt = nil end
            end

            local spellId = (st and st.spellId)  or (defInt and defInt.spellId)
            local cd      = (st and st.cooldown) or (defInt and defInt.cooldown)

            if spellId and cd then
                -- Get or create bar frames
                local bf = intBarFrames[unit]
                if not bf then
                    local row = CreateFrame("Frame", nil, intBarsParent)

                    -- Border: a slightly larger solid-black layer behind
                    -- the icon+bar combo, giving a clean 1px outline -
                    -- same flat/minimal border technique used elsewhere.
                    local border = row:CreateTexture(nil, "BACKGROUND", nil, -1)
                    border:SetPoint("TOPLEFT",     row, "TOPLEFT",     -1,  1)
                    border:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT",  1, -1)
                    border:SetColorTexture(0, 0, 0, 1)

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
                    -- interrupt bound to a unit can change after a first-seen cast.
                    iconF:SetScript("OnEnter", function(self)
                        local liveSt = intBarState[unit]
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

                    bf = { row=row, sb=sb, sbBg=sbBg, ico=ico, iconF=iconF, nameText=nameText, cdText=cdText }
                    intBarFrames[unit] = bf
                end

                -- Resize / reposition
                bf.row:SetSize(ROW, BH)
                bf.row:ClearAllPoints()
                bf.row:SetPoint("TOPLEFT", intBarsParent, "TOPLEFT", 0, -yOff)

                -- Icon always matches bar height
                bf.iconF:SetSize(ICO, ICO)

                -- Resize status bar (in case barWidth changed)
                bf.sb:SetHeight(BH)

                -- Statusbar texture (applied every rebuild so a SharedMedia
                -- selection change in settings takes effect immediately).
                local barTex = db.texturePath or DEFAULT_BAR_TEXTURE
                bf.sb:SetStatusBarTexture(barTex)
                bf.sbBg:SetTexture(barTex)

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

    -- Resize bars container
    intBarsParent:SetSize(math.max(1, ROW), math.max(1, yOff))
    intAnchorFrame:SetWidth(ROW)

    -- Header space is always reserved (whether locked or not) so the bars never
    -- shift position when the header strip is shown/hidden by locking/unlocking.
    intBarsParent:ClearAllPoints()
    intAnchorFrame:SetHeight(HEADER_H + math.max(1, yOff))
    intBarsParent:SetPoint("TOPLEFT", intAnchorFrame, "TOPLEFT", 0, -HEADER_H)
    ApplyIntAnchorLockState()
    intAnchorFrame:SetShown(anyBar or not db.locked)
end

-- ─────────────────────────────────────────────────────────────
-- Called from KastaCD_CombatLog when a known interrupt is cast
-- ─────────────────────────────────────────────────────────────
function HandleInterruptCast(sourceGUID, spellId)
    local intInfo = INT_SPELLS[spellId]
    if not intInfo then return end

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

    if not intBarState[unit] then
        intBarState[unit] = { spellId=spellId, cooldown=intInfo.cooldown, endTime=0, class=class or intInfo.class }
    end

    local st      = intBarState[unit]
    st.spellId    = spellId
    st.cooldown   = intInfo.cooldown
    st.endTime    = now + intInfo.cooldown
    st.class      = class or st.class

    -- Update icon immediately if bar already exists
    local bf = intBarFrames[unit]
    if bf then
        local tex = GetSpellTexture and GetSpellTexture(spellId)
        if tex then bf.ico:SetTexture(tex) end
    end

    -- First-seen unit (Priest/Warlock) → need a new bar row
    if not bf or not bf.row:IsShown() then
        RebuildInterruptBars()
    end
end

-- ─────────────────────────────────────────────────────────────
-- 0.1-second update ticker
-- ─────────────────────────────────────────────────────────────
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
