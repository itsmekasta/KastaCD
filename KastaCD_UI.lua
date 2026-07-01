-- =============================================================
-- KastaCD_UI.lua
-- Settings menu: frame construction, sidebar tab navigation,
-- per-class spell panels with subtabs, Settings panel (anchors,
-- sliders, content toggles), and Profiles panel (CRUD, export/import).
-- Depends on: KastaCD_SpellDB.lua, KastaCD_DB.lua, KastaCD_Tracking.lua
-- =============================================================

-- Exposed so KastaCD_Events.lua can call them from the slash handler
kcdMenu                = nil
refreshClassPanelsFns  = {}

-- =============================================================
-- Defensive DB normalization
-- ---------------------------------------------------------------
-- This file used to assume KastaCD_DB.lua had already fully populated
-- KastaCDDB (offsetX, iconSize, contentTypes, etc.)
-- by the time CreateKastaCDMenu() ran. That's true for an existing
-- install whose SavedVariables already have every field, but it's
-- NOT guaranteed for:
--   - a brand new install (no KastaCDDB on disk yet)
--   - someone upgrading from an older save shape missing newer fields
--     like new fields added in later versions
--   - any case where the other files' ADDON_LOADED-triggered init
--     didn't run before /kcd was typed
-- When any of those fields were nil, widgets like
-- Slider:SetValue(nil) threw immediately, aborting CreateKastaCDMenu
-- before kcdMenu ever got assigned - which is exactly why /kcd worked
-- for the author (whose DB already had every field) but silently
-- failed for other users. This function makes the menu self-healing
-- regardless of what the other files did or didn't set up.
-- =============================================================
local function EnsureMenuDBDefaults()
    if type(KastaCDDB) ~= "table" then KastaCDDB = {} end

    if type(KastaCDDB.profiles) ~= "table" then KastaCDDB.profiles = {} end
    if type(KastaCDDB.activeProfile) ~= "string"
    or not KastaCDDB.profiles[KastaCDDB.activeProfile] then
        KastaCDDB.activeProfile = "Default"
    end
    if type(KastaCDDB.profiles["Default"]) ~= "table" then
        KastaCDDB.profiles["Default"] = type(NewProfileData) == "function"
            and NewProfileData() or {}
    end

    if type(KastaCDDB.enabled) ~= "table" then KastaCDDB.enabled = {} end
    if type(KastaCDDB.offsetX) ~= "number" then KastaCDDB.offsetX = 0 end
    if type(KastaCDDB.offsetY) ~= "number" then KastaCDDB.offsetY = 0 end
    if type(KastaCDDB.iconSize) ~= "number" then KastaCDDB.iconSize = 22 end
    if type(KastaCDDB.iconsPerRow) ~= "number" then KastaCDDB.iconsPerRow = 5 end

    if type(KastaCDDB.contentTypes) ~= "table" then KastaCDDB.contentTypes = {} end
    if type(CONTENT_TYPES) == "table" then
        for _, ct in ipairs(CONTENT_TYPES) do
            if KastaCDDB.contentTypes[ct] == nil then
                KastaCDDB.contentTypes[ct] = true
            end
        end
    end

    -- Anchor frame positions (global, not profile-specific)
    if type(KastaCDDB.anchorPos)  ~= "table" then KastaCDDB.anchorPos     = {} end
    if KastaCDDB.anchorsLocked     == nil     then KastaCDDB.anchorsLocked  = true end
    if KastaCDDB.growLeft          == nil     then KastaCDDB.growLeft       = false end
    if KastaCDDB.showIconBorders   == nil     then KastaCDDB.showIconBorders = false end
end

-- =============================================================
-- Widget helpers
-- =============================================================

local sliderCount = 0
local function MakeSlider(parent, minV, maxV, curVal, w, onChange)
    sliderCount = sliderCount + 1
    local sName = "KastaCDSlider" .. sliderCount
    local s = CreateFrame("Slider", sName, parent, "OptionsSliderTemplate")
    s:SetWidth(w or 200)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(1)
    s:SetObeyStepOnDrag(true)
    s:SetValue(tonumber(curVal) or minV)
    _G[sName .. "Low"]:SetText(minV)
    _G[sName .. "High"]:SetText(maxV)
    _G[sName .. "Text"]:SetText("")

    -- Clickable value box: shows the current number; click to type a precise value.
    local valBox = CreateFrame("EditBox", nil, parent)
    valBox:SetSize(42, 18)
    valBox:SetPoint("LEFT", s, "RIGHT", 6, 0)
    valBox:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    valBox:SetTextColor(1, 0.82, 0)
    valBox:SetJustifyH("CENTER")
    valBox:SetAutoFocus(false)
    valBox:SetMaxLetters(6)
    valBox:SetText(tostring(math.floor(tonumber(curVal) or minV)))
    valBox:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true, tileSize=8, edgeSize=8,
        insets={left=2,right=2,top=2,bottom=2},
    })
    valBox:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
    valBox:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.7)

    local function ApplyVal()
        local num = tonumber(valBox:GetText())
        if not num then
            num = math.floor(s:GetValue())
        else
            num = math.max(minV, math.min(maxV, math.floor(num)))
        end
        valBox:SetText(tostring(num))
        s:SetValue(num)
        onChange(num)
    end

    valBox:SetScript("OnEnterPressed", function(self) ApplyVal(); self:ClearFocus() end)
    valBox:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(math.floor(s:GetValue())))
        self:ClearFocus()
    end)
    valBox:SetScript("OnEditFocusLost", ApplyVal)
    valBox:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1, 0.82, 0, 0.9)
    end)
    valBox:SetScript("OnLeave", function(self)
        if not self:HasFocus() then
            self:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.7)
        end
    end)

    s:SetScript("OnValueChanged", function(_, v)
        local fv = math.floor(v)
        -- Don't overwrite text while the user is typing
        if not valBox:HasFocus() then
            valBox:SetText(tostring(fv))
        end
        onChange(fv)
    end)

    return s, valBox
end

local function MakeLabel(parent, txt, point, relFrame, relPoint, x, y)
    local l = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l:SetPoint(point, relFrame, relPoint, x, y)
    l:SetText(txt)
    return l
end

local function MakeToggle(parent, txt, isOn, point, relFrame, relPoint, x, y, onChange)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(200, 22)
    btn:SetPoint(point, relFrame, relPoint, x, y)
    local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lbl:SetPoint("LEFT", btn, "LEFT", 0, 0)
    lbl:SetText(txt)
    local val = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    val:SetPoint("LEFT", btn, "LEFT", 120, 0)
    local state = isOn
    local function Refresh()
        val:SetText(state and "|cff44ff44ON|r" or "|cffff4444OFF|r")
    end
    btn:SetScript("OnClick", function()
        state = not state
        Refresh()
        onChange(state)
    end)
    Refresh()
    return btn
end

-- =============================================================
-- SharedMedia integration (optional - degrades to a small built-in
-- fallback list if LibStub/LibSharedMedia-3.0 isn't installed, e.g. via
-- the standalone "SharedMedia" addon).
-- =============================================================
local LSM = LibStub and LibStub:GetLibrary("LibSharedMedia-3.0", true)

local FALLBACK_FONTS = {
    { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF"  },
    { name = "Arial Narrow",  path = "Fonts\\ARIALN.TTF"    },
    { name = "Morpheus",      path = "Fonts\\MORPHEUS.TTF"  },
    { name = "Skurri",        path = "Fonts\\SKURRI.TTF"    },
}
local FALLBACK_TEXTURES = {
    { name = "Blizzard",   path = "Interface\\TargetingFrame\\UI-StatusBar" },
    { name = "Solid",      path = "Interface\\Buttons\\WHITE8x8"            },
}

-- Button + scrollable popup that lists either SharedMedia entries for
-- mediaType (LSM.MediaType.FONT / .STATUSBAR) or a small built-in
-- fallback list when SharedMedia isn't installed / has nothing registered
-- for that type. getCurrentPath()/applyFn(path) read and write the saved
-- selection - same pattern the original hand-rolled font picker used,
-- just shared between fonts and textures instead of duplicated per use.
-- kind: "font" previews each row rendered in its own font; "texture"
-- shows a small swatch of the actual statusbar art next to the name.
-- Anything else (or omitted) just shows the plain name, no preview.
local function MakeMediaPicker(panel, label, x, y, mediaType, fallbackList, getCurrentPath, applyFn, kind)
    local options = {}
    if LSM and mediaType then
        for _, name in ipairs(LSM:List(mediaType)) do
            table.insert(options, { name = name, path = LSM:Fetch(mediaType, name) })
        end
        table.sort(options, function(a, b) return a.name < b.name end)
    end
    if #options == 0 then
        options = fallbackList
    end

    MakeLabel(panel, label, "TOPLEFT", panel, "TOPLEFT", x, y)

    local function CurrentName()
        local cur = getCurrentPath()
        for _, o in ipairs(options) do
            if o.path == cur then return o.name end
        end
        return options[1] and options[1].name or "Default"
    end

    local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btn:SetSize(160, 22)
    btn:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y - 18)
    btn:SetText(CurrentName())

    local ROW_H    = 20
    local visible   = math.min(#options, 10)
    local popup = CreateFrame("Frame", nil, panel)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetSize(180, visible * ROW_H + 6)
    popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
    popup:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left=3, right=3, top=3, bottom=3 },
    })
    popup:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    popup:Hide()

    local scroll = CreateFrame("ScrollFrame", nil, popup, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", popup, "TOPLEFT", 3, -3)
    scroll:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -22, 3)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(150, math.max(1, #options * ROW_H))
    scroll:SetScrollChild(child)

    for i, o in ipairs(options) do
        local eBtn = CreateFrame("Button", nil, child)
        eBtn:SetSize(150, ROW_H)
        eBtn:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * ROW_H)
        eBtn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

        local eTxt = eBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        eTxt:SetJustifyH("LEFT")
        eTxt:SetText(o.name)

        if kind == "font" then
            -- Preview: render the entry's own name using its own font
            -- file, so the list doubles as a live sample of each option.
            -- Falls back to the default font if the file fails to load
            -- at this size (e.g. a broken/incompatible font file).
            eTxt:SetAllPoints()
            local ok = pcall(function() eTxt:SetFont(o.path, 12, "OUTLINE") end)
            if not ok then eTxt:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE") end
        elseif kind == "texture" then
            -- Preview: a small swatch of the actual statusbar art next to
            -- the name, so users can see the texture before picking it.
            local swatch = eBtn:CreateTexture(nil, "ARTWORK")
            swatch:SetSize(36, ROW_H - 6)
            swatch:SetPoint("LEFT", eBtn, "LEFT", 2, 0)
            swatch:SetTexture(o.path)
            eTxt:SetPoint("LEFT", swatch, "RIGHT", 4, 0)
            eTxt:SetPoint("RIGHT", eBtn, "RIGHT", 0, 0)
        else
            eTxt:SetAllPoints()
        end

        local oPath, oName = o.path, o.name
        eBtn:SetScript("OnClick", function()
            applyFn(oPath)
            btn:SetText(oName)
            popup:Hide()
        end)
    end

    btn:SetScript("OnClick", function()
        popup:SetShown(not popup:IsShown())
    end)

    return btn, popup
end

-- =============================================================
-- CreateKastaCDMenu  –  build the full UI (called once, lazily)
-- =============================================================
function CreateKastaCDMenu()
    if kcdMenu then return end

    -- Must run before anything below touches KastaCDDB.* - see the
    -- big comment on EnsureMenuDBDefaults above for why this is the
    -- actual fix for "menu works for me, not for other users."
    EnsureMenuDBDefaults()

    local FRAME_W   = 860
    local FRAME_H   = 620
    local SIDEBAR_W = 160

    -- ── Root frame ────────────────────────────────────────────
    local frame = CreateFrame("Frame", "KastaCDMenu", UIParent)
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetPoint("CENTER")
    frame:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=12,
        insets={left=4,right=4,top=4,bottom=4},
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
    frame:SetBackdropBorderColor(0, 0, 0, 1)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop",  frame.StopMovingOrSizing)
    frame:SetFrameStrata("HIGH")
    frame:Hide()
    tinsert(UISpecialFrames, "KastaCDMenu")

    -- ── Title bar ─────────────────────────────────────────────
    local titleBG = frame:CreateTexture(nil, "BACKGROUND")
    titleBG:SetPoint("TOPLEFT",  frame, "TOPLEFT",   4, -4)
    titleBG:SetPoint("TOPRIGHT", frame, "TOPRIGHT",  -4, -4)
    titleBG:SetHeight(32)
    titleBG:SetColorTexture(0.10, 0.10, 0.10, 1)

    local titleTxt = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleTxt:SetPoint("TOPLEFT", titleBG, "TOPLEFT", 12, -7)
    titleTxt:SetText("Kasta|cffff7f00CD|r – Party Cooldowns")

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    local verLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    verLbl:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 8)
    verLbl:SetText("Kasta|cffff7f00CD|r v" .. tostring(KASTACD_VERSION or "?"))
    verLbl:SetTextColor(0.5, 0.5, 0.5)

    -- ── Sidebar ───────────────────────────────────────────────
    local sidebarBG = frame:CreateTexture(nil, "BACKGROUND")
    sidebarBG:SetPoint("TOPLEFT",    titleBG, "BOTTOMLEFT",  0, -1)
    sidebarBG:SetPoint("BOTTOMLEFT", frame,   "BOTTOMLEFT",  4,  4)
    sidebarBG:SetWidth(SIDEBAR_W)
    sidebarBG:SetColorTexture(0.08, 0.08, 0.08, 1)

    local divider = frame:CreateTexture(nil, "BACKGROUND")
    divider:SetPoint("TOPLEFT",    sidebarBG, "TOPRIGHT",    0, 0)
    divider:SetPoint("BOTTOMLEFT", sidebarBG, "BOTTOMRIGHT", 0, 0)
    divider:SetWidth(1)
    divider:SetColorTexture(0.2, 0.2, 0.2, 1)

    -- ── Content area ──────────────────────────────────────────
    local contentArea = CreateFrame("Frame", nil, frame)
    contentArea:SetPoint("TOPLEFT",     divider, "TOPRIGHT",     0,   0)
    contentArea:SetPoint("BOTTOMRIGHT", frame,   "BOTTOMRIGHT", -4,  50)
    local contentBG = contentArea:CreateTexture(nil, "BACKGROUND")
    contentBG:SetAllPoints()
    contentBG:SetColorTexture(0.07, 0.07, 0.07, 1)

    -- ── Apply button ──────────────────────────────────────────
    local applyBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    applyBtn:SetSize(140, 26)
    applyBtn:SetPoint("CENTER", contentArea, "BOTTOM", 0, -25)
    applyBtn:SetText("Apply")
    applyBtn:SetScript("OnClick", function()
        if type(PersistActiveProfile) == "function" then PersistActiveProfile() end
        if type(RebuildIcons) == "function" then RebuildIcons() end
        print("KastaCD: Applied.")
    end)

    -- ── Panel registry ────────────────────────────────────────
    local panels = {}
    local function ShowPanel(name)
        for n, p in pairs(panels) do p:SetShown(n == name) end
    end

    -- =========================================================
    -- Settings panel
    -- =========================================================
    local panelPos = CreateFrame("Frame", nil, contentArea)
    panelPos:SetAllPoints()
    panels["Settings"] = panelPos

    -- Centre the two-column block: left col at CX, right col at RX.
    -- Block width: 200 (slider) + 46 (gap) + ~170 (right col) = ~416px.
    -- Centred in CONTENT_W=695: (695-416)/2 ≈ 138.
    -- offsetLabelY: block runs from y=0 down to the bottom of "Reset
    -- Positions" (offsetLabelY-434), and the content area is ~533px tall,
    -- so (533-434)/2 ≈ 50 centres it vertically - the old -14 packed
    -- everything near the top with a large empty gap at the bottom.
    local offsetLabelY = -50
    local CX = 138
    local RX = CX + 246   -- keeps the same 246px inter-column gap as before

    MakeLabel(panelPos, "Offset X:", "TOPLEFT", panelPos, "TOPLEFT", CX, offsetLabelY)
    local oxS = MakeSlider(panelPos, -200, 200, KastaCDDB.offsetX, 200,
        function(v) KastaCDDB.offsetX = v; if type(RebuildIcons) == "function" then RebuildIcons() end end)
    oxS:SetPoint("TOPLEFT", panelPos, "TOPLEFT", CX, offsetLabelY - 18)

    MakeLabel(panelPos, "Offset Y:", "TOPLEFT", panelPos, "TOPLEFT", CX, offsetLabelY - 48)
    local oyS = MakeSlider(panelPos, -200, 200, KastaCDDB.offsetY, 200,
        function(v) KastaCDDB.offsetY = v; if type(RebuildIcons) == "function" then RebuildIcons() end end)
    oyS:SetPoint("TOPLEFT", panelPos, "TOPLEFT", CX, offsetLabelY - 66)

    MakeLabel(panelPos, "Icon Size:", "TOPLEFT", panelPos, "TOPLEFT", CX, offsetLabelY - 96)
    local isS = MakeSlider(panelPos, 12, 48, KastaCDDB.iconSize, 200,
        function(v) KastaCDDB.iconSize = v; if type(RebuildIcons) == "function" then RebuildIcons() end end)
    isS:SetPoint("TOPLEFT", panelPos, "TOPLEFT", CX, offsetLabelY - 114)

    MakeLabel(panelPos, "Icons per Row:", "TOPLEFT", panelPos, "TOPLEFT", CX, offsetLabelY - 144)
    local iprS = MakeSlider(panelPos, 1, 10, KastaCDDB.iconsPerRow, 200,
        function(v) KastaCDDB.iconsPerRow = v; if type(RebuildIcons) == "function" then RebuildIcons() end end)
    iprS:SetPoint("TOPLEFT", panelPos, "TOPLEFT", CX, offsetLabelY - 162)

    MakeToggle(panelPos, "Grow Left", KastaCDDB.growLeft == true,
        "TOPLEFT", panelPos, "TOPLEFT", CX, offsetLabelY - 190,
        function(v)
            KastaCDDB.growLeft = v
            if type(RebuildIcons) == "function" then RebuildIcons() end
        end)

    local pvpHdr = panelPos:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pvpHdr:SetPoint("TOPLEFT", panelPos, "TOPLEFT", RX, offsetLabelY)
    pvpHdr:SetText("|cffff7f00Misc:|r")

    local pvpCB = CreateFrame("CheckButton", nil, panelPos, "UICheckButtonTemplate")
    pvpCB:SetSize(22, 22)
    pvpCB:SetPoint("TOPLEFT", panelPos, "TOPLEFT", RX, offsetLabelY - 22)
    pvpCB:SetChecked(KastaCDDB.enabled[208683] == true)
    local pvpLbl = panelPos:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    pvpLbl:SetPoint("LEFT", pvpCB, "RIGHT", 2, 0)
    pvpLbl:SetText("PvP Medallion")
    pvpCB:SetScript("OnClick", function(self)
        KastaCDDB.enabled[208683] = self:GetChecked() and true or nil
        if type(RebuildIcons) == "function" then RebuildIcons() end
    end)

    local medPvPCB = CreateFrame("CheckButton", nil, panelPos, "UICheckButtonTemplate")
    medPvPCB:SetSize(22, 22)
    medPvPCB:SetPoint("TOPLEFT", panelPos, "TOPLEFT", RX, offsetLabelY - 52)
    medPvPCB:SetChecked(KastaCDDB.medallionOutsidePvP == true)
    local medPvPLbl = panelPos:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    medPvPLbl:SetPoint("LEFT", medPvPCB, "RIGHT", 2, 0)
    medPvPLbl:SetText("Medallion outside PvP")

    local borderCB = CreateFrame("CheckButton", nil, panelPos, "UICheckButtonTemplate")
    borderCB:SetSize(22, 22)
    borderCB:SetPoint("TOPLEFT", panelPos, "TOPLEFT", RX, offsetLabelY - 82)
    borderCB:SetChecked(KastaCDDB.showIconBorders == true)
    local borderLbl = panelPos:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    borderLbl:SetPoint("LEFT", borderCB, "RIGHT", 2, 0)
    borderLbl:SetText("Icon Borders")
    medPvPCB:SetScript("OnClick", function(self)
        KastaCDDB.medallionOutsidePvP = self:GetChecked() and true or false
        if type(RebuildIcons) == "function" then RebuildIcons() end
    end)
    borderCB:SetScript("OnClick", function(self)
        KastaCDDB.showIconBorders = self:GetChecked() and true or false
        if type(ApplyIconBorders) == "function" then ApplyIconBorders() end
    end)

    -- Content-type toggles
    local ctHdr = panelPos:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ctHdr:SetPoint("TOPLEFT", panelPos, "TOPLEFT", CX, offsetLabelY - 218)
    ctHdr:SetText("|cffff7f00Active in:|r")

    local ctY = offsetLabelY - 238
    for _, ct in ipairs(CONTENT_TYPES or {}) do
        local ctName = ct
        MakeToggle(panelPos, ctName, KastaCDDB.contentTypes[ctName] == true,
            "TOPLEFT", panelPos, "TOPLEFT", CX, ctY,
            function(v)
                KastaCDDB.contentTypes[ctName] = v
                if type(RebuildIcons) == "function" then RebuildIcons() end
            end)
        ctY = ctY - 26
    end

    -- ── Anchor frames (draggable positioning) ────────────────
    local anchorHdr = panelPos:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    anchorHdr:SetPoint("TOPLEFT", panelPos, "TOPLEFT", CX, ctY - 10)
    anchorHdr:SetText("|cffff7f00Anchor Frames:|r")

    local anchorDesc = panelPos:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    anchorDesc:SetPoint("TOPLEFT", panelPos, "TOPLEFT", CX, ctY - 28)
    anchorDesc:SetText("Unlock to drag the orange anchor squares onto your party frames.")
    anchorDesc:SetTextColor(0.7, 0.7, 0.7)

    local anchorStatLbl = panelPos:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    anchorStatLbl:SetPoint("LEFT",  panelPos, "TOPLEFT", CX + 116, ctY - 52)

    local anchorUnlockBtn = CreateFrame("Button", nil, panelPos, "UIPanelButtonTemplate")
    anchorUnlockBtn:SetSize(110, 22)
    anchorUnlockBtn:SetPoint("TOPLEFT", panelPos, "TOPLEFT", CX, ctY - 44)

    local function RefreshAnchorBtn()
        if KastaCDDB.anchorsLocked then
            anchorUnlockBtn:SetText("Unlock")
            anchorStatLbl:SetText("|cffffd700Anchors: locked|r")
        else
            anchorUnlockBtn:SetText("Lock")
            anchorStatLbl:SetText("|cff44ff44Anchors: unlocked – drag to move|r")
        end
    end
    anchorUnlockBtn:SetScript("OnClick", function()
        KastaCDDB.anchorsLocked = not KastaCDDB.anchorsLocked
        if KastaCDDB.anchorsLocked then
            if type(HideKastaCDAnchors) == "function" then HideKastaCDAnchors() end
        else
            if type(ShowKastaCDAnchors) == "function" then ShowKastaCDAnchors() end
        end
        RefreshAnchorBtn()
    end)
    RefreshAnchorBtn()

    local resetAnchorsBtn = CreateFrame("Button", nil, panelPos, "UIPanelButtonTemplate")
    resetAnchorsBtn:SetSize(110, 22)
    resetAnchorsBtn:SetPoint("TOPLEFT", panelPos, "TOPLEFT", CX, ctY - 70)
    resetAnchorsBtn:SetText("Reset Positions")
    resetAnchorsBtn:SetScript("OnClick", function()
        KastaCDDB.anchorPos = {}
        if type(RebuildIcons) == "function" then RebuildIcons() end
        print("KastaCD: Anchor positions reset to defaults.")
    end)

    -- =========================================================
    -- Profiles panel
    -- =========================================================
    local panelProfiles = CreateFrame("Frame", nil, contentArea)
    panelProfiles:SetAllPoints()
    panels["Profiles"] = panelProfiles

    MakeLabel(panelProfiles, "Active Profile:", "TOPLEFT", panelProfiles, "TOPLEFT", 14, -14)
    local activeProfLbl = panelProfiles:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    activeProfLbl:SetPoint("TOPLEFT", panelProfiles, "TOPLEFT", 14, -34)
    activeProfLbl:SetTextColor(0.5, 0.8, 1)

    local profileListContainer = CreateFrame("Frame", nil, panelProfiles)
    profileListContainer:SetPoint("TOPLEFT", panelProfiles, "TOPLEFT", 14, -88)
    profileListContainer:SetSize(620, 160)

    local profileRows = {}

    -- ── RefreshClassPanels (forward ref, defined after class panels) ──
    local function RefreshClassPanels()
        for _, fn in ipairs(refreshClassPanelsFns) do fn() end
    end

    -- ── RefreshProfilesPanel ──────────────────────────────────
    local function RefreshProfilesPanel()
        activeProfLbl:SetText(KastaCDDB.activeProfile)
        for _, r in ipairs(profileRows) do r:Hide() end

        local names = {}
        for n in pairs(KastaCDDB.profiles) do table.insert(names, n) end
        table.sort(names)

        local y = 0
        for i, name in ipairs(names) do
            local row = profileRows[i]
            if not row then
                row = CreateFrame("Frame", nil, profileListContainer)
                row:SetSize(620, 26)
                local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                lbl:SetPoint("LEFT", row, "LEFT", 0, 0)
                row.lbl = lbl
                local useBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                useBtn:SetSize(70, 20)
                useBtn:SetPoint("LEFT", row, "LEFT", 420, 0)
                useBtn:SetText("Use")
                row.useBtn = useBtn
                local delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                delBtn:SetSize(70, 20)
                delBtn:SetPoint("LEFT", useBtn, "RIGHT", 8, 0)
                delBtn:SetText("Delete")
                row.delBtn = delBtn
                profileRows[i] = row
            end

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", profileListContainer, "TOPLEFT", 0, -y)
            row.lbl:SetText(name == KastaCDDB.activeProfile
                and ("|cff44ff44" .. name .. " (active)|r") or name)

            -- Capture loop variable
            local rowName = name
            row.useBtn:SetScript("OnClick", function()
                if type(PersistActiveProfile) == "function" then PersistActiveProfile() end
                KastaCDDB.activeProfile = rowName
                if type(ApplyActiveProfile) == "function" then ApplyActiveProfile() end
                if type(RebuildIcons) == "function" then RebuildIcons() end
                RefreshProfilesPanel()
                RefreshClassPanels()
                print("KastaCD: Switched to '" .. rowName .. "'.")
            end)
            row.delBtn:SetScript("OnClick", function()
                if rowName == "Default" then
                    print("KastaCD: Can't delete Default.")
                    return
                end
                if KastaCDDB.activeProfile == rowName then
                    if type(PersistActiveProfile) == "function" then PersistActiveProfile() end
                    KastaCDDB.activeProfile = "Default"
                    if type(ApplyActiveProfile) == "function" then ApplyActiveProfile() end
                    if type(RebuildIcons) == "function" then RebuildIcons() end
                end
                KastaCDDB.profiles[rowName] = nil
                RefreshProfilesPanel()
                RefreshClassPanels()
                print("KastaCD: Deleted '" .. rowName .. "'.")
            end)

            row:Show()
            y = y + 28
        end
    end

    -- ── Create / Copy ─────────────────────────────────────────
    local newNameBox = CreateFrame("EditBox", nil, panelProfiles, "InputBoxTemplate")
    newNameBox:SetSize(180, 20)
    newNameBox:SetPoint("TOPLEFT", panelProfiles, "TOPLEFT", 18, -260)
    newNameBox:SetAutoFocus(false)
    newNameBox:SetText("New profile name")

    local createBtn = CreateFrame("Button", nil, panelProfiles, "UIPanelButtonTemplate")
    createBtn:SetSize(100, 22)
    createBtn:SetPoint("LEFT", newNameBox, "RIGHT", 10, 0)
    createBtn:SetText("Create")
    createBtn:SetScript("OnClick", function()
        local nm = newNameBox:GetText()
        if not nm or nm == "" or nm == "New profile name" then
            print("KastaCD: Enter a name."); return
        end
        if KastaCDDB.profiles[nm] then
            print("KastaCD: Already exists."); return
        end
        if type(PersistActiveProfile) == "function" then PersistActiveProfile() end
        KastaCDDB.profiles[nm] = type(NewProfileData) == "function" and NewProfileData() or {}
        KastaCDDB.activeProfile = nm
        if type(ApplyActiveProfile) == "function" then ApplyActiveProfile() end
        if type(RebuildIcons) == "function" then RebuildIcons() end
        RefreshProfilesPanel()
        RefreshClassPanels()
        print("KastaCD: Created '" .. nm .. "'.")
    end)

    local copyBtn = CreateFrame("Button", nil, panelProfiles, "UIPanelButtonTemplate")
    copyBtn:SetSize(140, 22)
    copyBtn:SetPoint("TOPLEFT", newNameBox, "BOTTOMLEFT", 0, -10)
    copyBtn:SetText("Copy Current As New")
    copyBtn:SetScript("OnClick", function()
        local nm = newNameBox:GetText()
        if not nm or nm == "" or nm == "New profile name" then
            print("KastaCD: Enter a name."); return
        end
        if KastaCDDB.profiles[nm] then
            print("KastaCD: Already exists."); return
        end
        if type(PersistActiveProfile) == "function" then PersistActiveProfile() end
        local cur  = KastaCDDB.profiles[KastaCDDB.activeProfile]
        local copy = type(NewProfileData) == "function" and NewProfileData() or {}
        copy.enabled      = copy.enabled      or {}
        copy.contentTypes = copy.contentTypes or {}
        for sid, v in pairs(cur.enabled or {})       do copy.enabled[sid]     = v end
        copy.offsetX     = cur.offsetX     or 0
        copy.offsetY     = cur.offsetY     or 0
        copy.iconSize    = cur.iconSize    or 22
        copy.iconsPerRow = cur.iconsPerRow or 5
        for ct, v in pairs(cur.contentTypes or {}) do copy.contentTypes[ct] = v end
        KastaCDDB.profiles[nm] = copy
        KastaCDDB.activeProfile = nm
        if type(ApplyActiveProfile) == "function" then ApplyActiveProfile() end
        if type(RebuildIcons) == "function" then RebuildIcons() end
        RefreshProfilesPanel()
        RefreshClassPanels()
        print("KastaCD: Copied to '" .. nm .. "'.")
    end)

    -- ── Export / Import ───────────────────────────────────────
    local exportHdr = panelProfiles:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    exportHdr:SetPoint("TOPLEFT", copyBtn, "BOTTOMLEFT", 0, -16)
    exportHdr:SetText("|cffff7f00Export / Import:|r")

    local exportBox = CreateFrame("EditBox", nil, panelProfiles, "InputBoxTemplate")
    exportBox:SetSize(460, 20)
    exportBox:SetPoint("TOPLEFT", exportHdr, "BOTTOMLEFT", 4, -8)
    exportBox:SetAutoFocus(false)
    exportBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Serialise a profile to a compact string
    local function SerializeProfile(p)
        local parts = {}
        for sid, v in pairs(p.enabled or {}) do
            if v then table.insert(parts, "e" .. sid) end
        end
        for ct, v in pairs(p.contentTypes or {}) do
            if v then table.insert(parts, "c" .. ct:gsub(" ", "_")) end
        end
        table.sort(parts)
        return string.format("KCD3:%d:%d:%d:%d:%s",
            p.offsetX or 0, p.offsetY or 0, p.iconSize or 22, p.iconsPerRow or 5,
            table.concat(parts, ","))
    end

    -- Deserialise — KCD3 is current; KCD1/KCD2 are legacy (group data ignored)
    local function DeserializeProfile(str)
        local p = type(NewProfileData) == "function" and NewProfileData() or {}
        p.enabled = p.enabled or {}
        local ox, oy, isz, ipr, rest =
            str:match("^KCD3:(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(.*)$")
        if not ox then
            -- Legacy KCD2: 7 leading numbers (3 group positions + 4 params)
            local _, _, _, a, b, c, d, r =
                str:match("^KCD2:(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(.*)$")
            if a then ox, oy, isz, ipr, rest = a, b, c, d, r end
        end
        if not ox then
            -- Legacy KCD1: single position index then 4 params
            local _, a, b, c, d, r =
                str:match("^KCD%d+:(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(.*)$")
            if a then ox, oy, isz, ipr, rest = a, b, c, d, r end
        end
        if not ox then return nil, "Bad format." end
        p.offsetX     = tonumber(ox)  or 0
        p.offsetY     = tonumber(oy)  or 0
        p.iconSize    = tonumber(isz) or 22
        p.iconsPerRow = tonumber(ipr) or 5
        p.contentTypes = {}
        for tok in ((rest or "") .. ","):gmatch("([^,]*),") do
            if tok ~= "" then
                local k, v = tok:sub(1, 1), tok:sub(2)
                if k == "e" then
                    local sid = tonumber(v)
                    if sid then p.enabled[sid] = true end
                elseif k == "c" then
                    p.contentTypes[v:gsub("_", " ")] = true
                end
            end
        end
        return p
    end

    local exportBtn = CreateFrame("Button", nil, panelProfiles, "UIPanelButtonTemplate")
    exportBtn:SetSize(80, 20)
    exportBtn:SetPoint("LEFT", exportBox, "RIGHT", 8, 0)
    exportBtn:SetText("Export")
    exportBtn:SetScript("OnClick", function()
        if type(PersistActiveProfile) == "function" then PersistActiveProfile() end
        exportBox:SetText(SerializeProfile(KastaCDDB.profiles[KastaCDDB.activeProfile]))
        exportBox:HighlightText()
        exportBox:SetFocus()
    end)

    local importBtn = CreateFrame("Button", nil, panelProfiles, "UIPanelButtonTemplate")
    importBtn:SetSize(80, 20)
    importBtn:SetPoint("TOPLEFT", exportBtn, "BOTTOMLEFT", 0, -8)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function()
        local p, err = DeserializeProfile(exportBox:GetText())
        if not p then
            print("KastaCD: Import failed — " .. tostring(err)); return
        end
        local nm = "Imported"
        local n  = 1
        while KastaCDDB.profiles[nm] do n = n + 1; nm = "Imported " .. n end
        if type(PersistActiveProfile) == "function" then PersistActiveProfile() end
        KastaCDDB.profiles[nm] = p
        KastaCDDB.activeProfile = nm
        if type(ApplyActiveProfile) == "function" then ApplyActiveProfile() end
        if type(RebuildIcons) == "function" then RebuildIcons() end
        RefreshProfilesPanel()
        RefreshClassPanels()
        print("KastaCD: Imported as '" .. nm .. "'.")
    end)

    RefreshProfilesPanel()

    -- =========================================================
    -- Per-class spell panels  (category sub-tabs)
    -- =========================================================
    local CATEGORY_ORDER = { "OFFENSIVE", "INTERRUPT", "DEFENSIVE", "IMMUNITY", "UTILITY" }
    local CATEGORY_NAMES = {
        OFFENSIVE="Offensive", INTERRUPT="Interrupt",
        DEFENSIVE="Defensive", IMMUNITY="Immunity", UTILITY="Utility",
    }
    local CAT_TAB_H   = 22
    -- contentArea width: FRAME_W(860) - SIDEBAR_W(160) - divider(1) - right margin(4) = 695
    local CONTENT_W   = FRAME_W - SIDEBAR_W - 1 - 4

    for _, ci in ipairs(CLASS_INFO or {}) do
        local classFrame = CreateFrame("Frame", nil, contentArea)
        classFrame:SetAllPoints()
        panels[ci.key] = classFrame

        -- Class name header
        local hdr = classFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        hdr:SetPoint("TOPLEFT", classFrame, "TOPLEFT", 14, -10)
        hdr:SetText(string.format("|cff%02x%02x%02x%s|r",
            ci.r * 255, ci.g * 255, ci.b * 255, ci.label))

        -- Collect spells for this class, grouped by category
        local byCategory = {}
        for sid, data in pairs(SPELL_DB or {}) do
            if data.class == ci.key then
                local cat = data.category or "UTILITY"
                byCategory[cat] = byCategory[cat] or {}
                table.insert(byCategory[cat], { sid=sid, data=data })
            end
        end
        for _, spells in pairs(byCategory) do
            table.sort(spells, function(a, b) return a.data.name < b.data.name end)
        end

        -- Count non-empty categories to compute tab width
        local numActiveCats = 0
        for _, catKey in ipairs(CATEGORY_ORDER) do
            if byCategory[catKey] and #byCategory[catKey] > 0 then
                numActiveCats = numActiveCats + 1
            end
        end
        local CAT_TAB_W = numActiveCats > 0 and math.floor(CONTENT_W / numActiveCats) or 90

        -- Per-category tab buttons + scroll frames
        local catTabs    = {}   -- catKey → tab Button
        local catScrolls = {}   -- catKey → ScrollFrame

        local function SetActiveCatTab(activeKey)
            for k, sf  in pairs(catScrolls) do sf:SetShown(k == activeKey)   end
            for k, tab in pairs(catTabs)    do
                if k == activeKey then
                    tab.bg:SetColorTexture(1, 1, 1, 1)
                    tab.lbl:SetTextColor(0, 0, 0)
                else
                    tab.bg:SetColorTexture(0.12, 0.12, 0.12, 0.9)
                    tab.lbl:SetTextColor(0.7, 0.7, 0.7)
                end
            end
        end

        local tabX         = 0
        local TAB_TOP_Y    = -36   -- y offset below class header
        local SCROLL_TOP_Y = TAB_TOP_Y - CAT_TAB_H - 4
        local firstCatKey  = nil

        for _, catKey in ipairs(CATEGORY_ORDER) do
            local spells = byCategory[catKey]
            if spells and #spells > 0 then
                if not firstCatKey then firstCatKey = catKey end

                -- Tab button
                local tab = CreateFrame("Button", nil, classFrame)
                tab:SetSize(CAT_TAB_W, CAT_TAB_H)
                tab:SetPoint("TOPLEFT", classFrame, "TOPLEFT", tabX, TAB_TOP_Y)

                local tabBg = tab:CreateTexture(nil, "BACKGROUND")
                tabBg:SetAllPoints()
                tabBg:SetColorTexture(0.12, 0.12, 0.12, 0.9)
                tab.bg = tabBg

                local tabLbl = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                tabLbl:SetPoint("CENTER", tab, "CENTER", 0, 0)
                tabLbl:SetText(CATEGORY_NAMES[catKey] or catKey)
                tabLbl:SetTextColor(0.7, 0.7, 0.7)
                tab.lbl = tabLbl

                catTabs[catKey] = tab
                tabX = tabX + CAT_TAB_W

                -- Scroll frame for this category's spells
                local sf = CreateFrame("ScrollFrame", nil, classFrame, "UIPanelScrollFrameTemplate")
                sf:SetPoint("TOPLEFT",     classFrame, "TOPLEFT",     0, SCROLL_TOP_Y)
                sf:SetPoint("BOTTOMRIGHT", classFrame, "BOTTOMRIGHT", -20, 0)
                sf:Hide()
                catScrolls[catKey] = sf

                local childF = CreateFrame("Frame", nil, sf)
                childF:SetWidth(580)
                sf:SetScrollChild(childF)

                local cy = -4
                for _, entry in ipairs(spells) do
                    local sid, data = entry.sid, entry.data
                    local row = CreateFrame("Frame", nil, childF)
                    row:SetSize(580, 26)
                    row:SetPoint("TOPLEFT", childF, "TOPLEFT", 0, cy)

                    local ico = row:CreateTexture(nil, "ARTWORK")
                    ico:SetSize(20, 20)
                    ico:SetPoint("LEFT", row, "LEFT", 4, 0)
                    ico:SetTexture(GetSpellTexture and GetSpellTexture(sid) or data.icon)
                    ico:SetTexCoord(0, 1, 0, 1)

                    local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
                    cb:SetSize(22, 22)
                    cb:SetPoint("LEFT", ico, "RIGHT", 4, 0)
                    cb:SetChecked(KastaCDDB.enabled[sid] == true)
                    cb.spellId = sid
                    cb:SetScript("OnClick", function(self)
                        KastaCDDB.enabled[sid] = self:GetChecked() and true or nil
                        if type(RebuildIcons) == "function" then RebuildIcons() end
                    end)
                    row.checkbox = cb

                    local spellLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    spellLbl:SetPoint("LEFT",  cb,  "RIGHT", 4, 0)
                    spellLbl:SetPoint("RIGHT", row, "RIGHT", 0, 0)
                    spellLbl:SetJustifyH("LEFT")
                    spellLbl:SetText(data.name)

                    row:EnableMouse(true)
                    row:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                        local ok = pcall(function() GameTooltip:SetSpellByID(sid) end)
                        if not ok then GameTooltip:SetText(data.name, 1, 1, 1) end
                        GameTooltip:Show()
                    end)
                    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

                    cy = cy - 26
                end
                childF:SetHeight(math.abs(cy) + 10)

                tab:SetScript("OnClick", function() SetActiveCatTab(catKey) end)
            end
        end

        if firstCatKey then
            SetActiveCatTab(firstCatKey)
        else
            local empty = classFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            empty:SetPoint("TOPLEFT", classFrame, "TOPLEFT", 14, TAB_TOP_Y)
            empty:SetText("(no spells in database for this class)")
        end
    end

    -- =========================================================
    -- Interrupts panel
    -- =========================================================
    local panelInt = CreateFrame("Frame", nil, contentArea)
    panelInt:SetAllPoints()
    panels["Interrupts"] = panelInt

    -- ICX: left edge of the controls, centred in CONTENT_W. The widest row
    -- is a slider (200) + its value box (42) + the gap between them (6) =
    -- 248px - not the slider's bare width (200), which undercounted the
    -- value box and left everything visibly off-centre. Computed from the
    -- real CONTENT_W constant (not a hardcoded copy of it) so this can't
    -- silently drift out of sync if the frame/sidebar width ever changes.
    local ICX_ROW_W = 200 + 6 + 42
    local ICX = math.floor((CONTENT_W - ICX_ROW_W) / 2)
    -- intY: block runs from y=0 (header) to y=-422 (bottom of the Lock
    -- Anchor button, after Position X/Y and Texture rows), and the
    -- content area is ~533px tall, so (533-422)/2 ≈ 56 centres it
    -- vertically. Recompute this any time a row is added/removed from
    -- either tracker panel - it does NOT update itself automatically.
    local intY = -56
    MakeLabel(panelInt, "Interrupt Tracker", "TOPLEFT", panelInt, "TOPLEFT", ICX, intY)

    -- Enable toggle
    local intEnCB = CreateFrame("CheckButton", nil, panelInt, "UICheckButtonTemplate")
    intEnCB:SetSize(22, 22)
    intEnCB:SetPoint("TOPLEFT", panelInt, "TOPLEFT", ICX, intY - 22)
    intEnCB:SetChecked(KastaCDDB.intAnchor and KastaCDDB.intAnchor.enabled ~= false)
    local intEnLbl = panelInt:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    intEnLbl:SetPoint("LEFT", intEnCB, "RIGHT", 2, 0)
    intEnLbl:SetText("Enable")
    intEnCB:SetScript("OnClick", function(self)
        if type(KastaCDDB.intAnchor) ~= "table" then KastaCDDB.intAnchor = {} end
        KastaCDDB.intAnchor.enabled = self:GetChecked() and true or false
        if type(RebuildInterruptBars) == "function" then RebuildInterruptBars() end
    end)

    -- Test Mode toggle: previews the bar while solo (not in party/raid),
    -- where it's normally hidden entirely.
    local intTestCB = CreateFrame("CheckButton", nil, panelInt, "UICheckButtonTemplate")
    intTestCB:SetSize(22, 22)
    intTestCB:SetPoint("LEFT", intEnCB, "LEFT", 110, 0)
    intTestCB:SetChecked(KastaCDDB.intAnchor and KastaCDDB.intAnchor.testMode == true)
    local intTestLbl = panelInt:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    intTestLbl:SetPoint("LEFT", intTestCB, "RIGHT", 2, 0)
    intTestLbl:SetText("Test Mode")
    intTestCB:SetScript("OnClick", function(self)
        if type(KastaCDDB.intAnchor) ~= "table" then KastaCDDB.intAnchor = {} end
        KastaCDDB.intAnchor.testMode = self:GetChecked() and true or false
        if type(RebuildInterruptBars) == "function" then RebuildInterruptBars() end
    end)

    -- Bar Width slider
    MakeLabel(panelInt, "Bar Width:", "TOPLEFT", panelInt, "TOPLEFT", ICX, intY - 58)
    local intBWS = MakeSlider(panelInt, 100, 400,
        (KastaCDDB.intAnchor and KastaCDDB.intAnchor.barWidth) or 200, 200,
        function(v)
            if type(KastaCDDB.intAnchor) ~= "table" then KastaCDDB.intAnchor = {} end
            KastaCDDB.intAnchor.barWidth = v
            if type(RebuildInterruptBars) == "function" then RebuildInterruptBars() end
        end)
    intBWS:SetPoint("TOPLEFT", panelInt, "TOPLEFT", ICX, intY - 76)

    -- Bar Height slider
    MakeLabel(panelInt, "Bar Height:", "TOPLEFT", panelInt, "TOPLEFT", ICX, intY - 106)
    local intBHS = MakeSlider(panelInt, 14, 40,
        (KastaCDDB.intAnchor and KastaCDDB.intAnchor.barHeight) or 20, 200,
        function(v)
            if type(KastaCDDB.intAnchor) ~= "table" then KastaCDDB.intAnchor = {} end
            KastaCDDB.intAnchor.barHeight = v
            if type(RebuildInterruptBars) == "function" then RebuildInterruptBars() end
        end)
    intBHS:SetPoint("TOPLEFT", panelInt, "TOPLEFT", ICX, intY - 124)

    -- ── Position X/Y sliders: pixel-perfect placement without dragging ──
    MakeLabel(panelInt, "Position X:", "TOPLEFT", panelInt, "TOPLEFT", ICX, intY - 154)
    local intPXS = MakeSlider(panelInt, -2000, 2000,
        (KastaCDDB.intAnchor and KastaCDDB.intAnchor.savedX) or 0, 200,
        function(v)
            local ia = KastaCDDB.intAnchor or {}
            if type(SetIntAnchorPos) == "function" then
                SetIntAnchorPos(v, ia.savedY or 0)
            end
        end)
    intPXS:SetPoint("TOPLEFT", panelInt, "TOPLEFT", ICX, intY - 172)

    MakeLabel(panelInt, "Position Y:", "TOPLEFT", panelInt, "TOPLEFT", ICX, intY - 202)
    local intPYS = MakeSlider(panelInt, -2000, 2000,
        (KastaCDDB.intAnchor and KastaCDDB.intAnchor.savedY) or 0, 200,
        function(v)
            local ia = KastaCDDB.intAnchor or {}
            if type(SetIntAnchorPos) == "function" then
                SetIntAnchorPos(ia.savedX or 0, v)
            end
        end)
    intPYS:SetPoint("TOPLEFT", panelInt, "TOPLEFT", ICX, intY - 220)

    -- ── Font selector (SharedMedia-aware) ─────────────────────
    MakeMediaPicker(panelInt, "Font:", ICX, intY - 250, LSM and LSM.MediaType.FONT, FALLBACK_FONTS,
        function() return KastaCDDB.intAnchor and KastaCDDB.intAnchor.fontPath or "Fonts\\FRIZQT__.TTF" end,
        function(path)
            if type(KastaCDDB.intAnchor) ~= "table" then KastaCDDB.intAnchor = {} end
            KastaCDDB.intAnchor.fontPath = path
            if type(RebuildInterruptBars) == "function" then RebuildInterruptBars() end
        end, "font")

    -- ── Statusbar texture selector (SharedMedia-aware) ────────
    MakeMediaPicker(panelInt, "Texture:", ICX, intY - 298, LSM and LSM.MediaType.STATUSBAR, FALLBACK_TEXTURES,
        function() return KastaCDDB.intAnchor and KastaCDDB.intAnchor.texturePath or "Interface\\TargetingFrame\\UI-StatusBar" end,
        function(path)
            if type(KastaCDDB.intAnchor) ~= "table" then KastaCDDB.intAnchor = {} end
            KastaCDDB.intAnchor.texturePath = path
            if type(RebuildInterruptBars) == "function" then RebuildInterruptBars() end
        end, "texture")

    -- ── Font size slider ──────────────────────────────────────
    MakeLabel(panelInt, "Font Size:", "TOPLEFT", panelInt, "TOPLEFT", ICX, intY - 346)
    local intFSS = MakeSlider(panelInt, 8, 18,
        (KastaCDDB.intAnchor and KastaCDDB.intAnchor.fontSize) or 10, 200,
        function(v)
            if type(KastaCDDB.intAnchor) ~= "table" then KastaCDDB.intAnchor = {} end
            KastaCDDB.intAnchor.fontSize = v
            if type(RebuildInterruptBars) == "function" then RebuildInterruptBars() end
        end)
    intFSS:SetPoint("TOPLEFT", panelInt, "TOPLEFT", ICX, intY - 364)

    -- Anchor lock button
    local intLockBtn = CreateFrame("Button", nil, panelInt, "UIPanelButtonTemplate")
    intLockBtn:SetSize(130, 22)
    intLockBtn:SetPoint("TOPLEFT", panelInt, "TOPLEFT", ICX, intY - 400)
    local function RefreshIntLockBtn()
        local locked = not KastaCDDB.intAnchor or KastaCDDB.intAnchor.locked ~= false
        intLockBtn:SetText(locked and "Unlock Anchor" or "Lock Anchor")
    end
    RefreshIntLockBtn()
    intLockBtn:SetScript("OnClick", function()
        if type(KastaCDDB.intAnchor) ~= "table" then KastaCDDB.intAnchor = {} end
        local locked = KastaCDDB.intAnchor.locked ~= false
        if locked then
            if type(UnlockIntAnchor) == "function" then UnlockIntAnchor() end
        else
            if type(LockIntAnchor) == "function" then LockIntAnchor() end
        end
        KastaCDDB.intAnchor.locked = not locked
        RefreshIntLockBtn()
    end)

    -- =========================================================
    -- Crowd Control panel
    -- =========================================================
    local panelCC = CreateFrame("Frame", nil, contentArea)
    panelCC:SetAllPoints()
    panels["CrowdControl"] = panelCC

    MakeLabel(panelCC, "Crowd Control Tracker", "TOPLEFT", panelCC, "TOPLEFT", ICX, intY)

    -- Enable toggle
    local ccEnCB = CreateFrame("CheckButton", nil, panelCC, "UICheckButtonTemplate")
    ccEnCB:SetSize(22, 22)
    ccEnCB:SetPoint("TOPLEFT", panelCC, "TOPLEFT", ICX, intY - 22)
    ccEnCB:SetChecked(KastaCDDB.ccAnchor and KastaCDDB.ccAnchor.enabled ~= false)
    local ccEnLbl = panelCC:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ccEnLbl:SetPoint("LEFT", ccEnCB, "RIGHT", 2, 0)
    ccEnLbl:SetText("Enable")
    ccEnCB:SetScript("OnClick", function(self)
        if type(KastaCDDB.ccAnchor) ~= "table" then KastaCDDB.ccAnchor = {} end
        KastaCDDB.ccAnchor.enabled = self:GetChecked() and true or false
        if type(RebuildCCBars) == "function" then RebuildCCBars() end
    end)

    -- Test Mode toggle: previews the bar while solo (not in party/raid),
    -- where it's normally hidden entirely. Fabricates a sample CC spell
    -- for the player's class since there's no real cast to key off yet.
    local ccTestCB = CreateFrame("CheckButton", nil, panelCC, "UICheckButtonTemplate")
    ccTestCB:SetSize(22, 22)
    ccTestCB:SetPoint("LEFT", ccEnCB, "LEFT", 110, 0)
    ccTestCB:SetChecked(KastaCDDB.ccAnchor and KastaCDDB.ccAnchor.testMode == true)
    local ccTestLbl = panelCC:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ccTestLbl:SetPoint("LEFT", ccTestCB, "RIGHT", 2, 0)
    ccTestLbl:SetText("Test Mode")
    ccTestCB:SetScript("OnClick", function(self)
        if type(KastaCDDB.ccAnchor) ~= "table" then KastaCDDB.ccAnchor = {} end
        KastaCDDB.ccAnchor.testMode = self:GetChecked() and true or false
        if type(RebuildCCBars) == "function" then RebuildCCBars() end
    end)

    -- Bar Width slider
    MakeLabel(panelCC, "Bar Width:", "TOPLEFT", panelCC, "TOPLEFT", ICX, intY - 58)
    local ccBWS = MakeSlider(panelCC, 100, 400,
        (KastaCDDB.ccAnchor and KastaCDDB.ccAnchor.barWidth) or 200, 200,
        function(v)
            if type(KastaCDDB.ccAnchor) ~= "table" then KastaCDDB.ccAnchor = {} end
            KastaCDDB.ccAnchor.barWidth = v
            if type(RebuildCCBars) == "function" then RebuildCCBars() end
        end)
    ccBWS:SetPoint("TOPLEFT", panelCC, "TOPLEFT", ICX, intY - 76)

    -- Bar Height slider
    MakeLabel(panelCC, "Bar Height:", "TOPLEFT", panelCC, "TOPLEFT", ICX, intY - 106)
    local ccBHS = MakeSlider(panelCC, 14, 40,
        (KastaCDDB.ccAnchor and KastaCDDB.ccAnchor.barHeight) or 20, 200,
        function(v)
            if type(KastaCDDB.ccAnchor) ~= "table" then KastaCDDB.ccAnchor = {} end
            KastaCDDB.ccAnchor.barHeight = v
            if type(RebuildCCBars) == "function" then RebuildCCBars() end
        end)
    ccBHS:SetPoint("TOPLEFT", panelCC, "TOPLEFT", ICX, intY - 124)

    -- ── Position X/Y sliders: pixel-perfect placement without dragging ──
    MakeLabel(panelCC, "Position X:", "TOPLEFT", panelCC, "TOPLEFT", ICX, intY - 154)
    local ccPXS = MakeSlider(panelCC, -2000, 2000,
        (KastaCDDB.ccAnchor and KastaCDDB.ccAnchor.savedX) or 0, 200,
        function(v)
            local ca = KastaCDDB.ccAnchor or {}
            if type(SetCCAnchorPos) == "function" then
                SetCCAnchorPos(v, ca.savedY or 0)
            end
        end)
    ccPXS:SetPoint("TOPLEFT", panelCC, "TOPLEFT", ICX, intY - 172)

    MakeLabel(panelCC, "Position Y:", "TOPLEFT", panelCC, "TOPLEFT", ICX, intY - 202)
    local ccPYS = MakeSlider(panelCC, -2000, 2000,
        (KastaCDDB.ccAnchor and KastaCDDB.ccAnchor.savedY) or 0, 200,
        function(v)
            local ca = KastaCDDB.ccAnchor or {}
            if type(SetCCAnchorPos) == "function" then
                SetCCAnchorPos(ca.savedX or 0, v)
            end
        end)
    ccPYS:SetPoint("TOPLEFT", panelCC, "TOPLEFT", ICX, intY - 220)

    -- ── Font selector (SharedMedia-aware) ─────────────────────
    MakeMediaPicker(panelCC, "Font:", ICX, intY - 250, LSM and LSM.MediaType.FONT, FALLBACK_FONTS,
        function() return KastaCDDB.ccAnchor and KastaCDDB.ccAnchor.fontPath or "Fonts\\FRIZQT__.TTF" end,
        function(path)
            if type(KastaCDDB.ccAnchor) ~= "table" then KastaCDDB.ccAnchor = {} end
            KastaCDDB.ccAnchor.fontPath = path
            if type(RebuildCCBars) == "function" then RebuildCCBars() end
        end, "font")

    -- ── Statusbar texture selector (SharedMedia-aware) ────────
    MakeMediaPicker(panelCC, "Texture:", ICX, intY - 298, LSM and LSM.MediaType.STATUSBAR, FALLBACK_TEXTURES,
        function() return KastaCDDB.ccAnchor and KastaCDDB.ccAnchor.texturePath or "Interface\\TargetingFrame\\UI-StatusBar" end,
        function(path)
            if type(KastaCDDB.ccAnchor) ~= "table" then KastaCDDB.ccAnchor = {} end
            KastaCDDB.ccAnchor.texturePath = path
            if type(RebuildCCBars) == "function" then RebuildCCBars() end
        end, "texture")

    -- ── Font size slider ──────────────────────────────────────
    MakeLabel(panelCC, "Font Size:", "TOPLEFT", panelCC, "TOPLEFT", ICX, intY - 346)
    local ccFSS = MakeSlider(panelCC, 8, 18,
        (KastaCDDB.ccAnchor and KastaCDDB.ccAnchor.fontSize) or 10, 200,
        function(v)
            if type(KastaCDDB.ccAnchor) ~= "table" then KastaCDDB.ccAnchor = {} end
            KastaCDDB.ccAnchor.fontSize = v
            if type(RebuildCCBars) == "function" then RebuildCCBars() end
        end)
    ccFSS:SetPoint("TOPLEFT", panelCC, "TOPLEFT", ICX, intY - 364)

    -- Anchor lock button
    local ccLockBtn = CreateFrame("Button", nil, panelCC, "UIPanelButtonTemplate")
    ccLockBtn:SetSize(130, 22)
    ccLockBtn:SetPoint("TOPLEFT", panelCC, "TOPLEFT", ICX, intY - 400)
    local function RefreshCCLockBtn()
        local locked = not KastaCDDB.ccAnchor or KastaCDDB.ccAnchor.locked ~= false
        ccLockBtn:SetText(locked and "Unlock Anchor" or "Lock Anchor")
    end
    RefreshCCLockBtn()
    ccLockBtn:SetScript("OnClick", function()
        if type(KastaCDDB.ccAnchor) ~= "table" then KastaCDDB.ccAnchor = {} end
        local locked = KastaCDDB.ccAnchor.locked ~= false
        if locked then
            if type(UnlockCCAnchor) == "function" then UnlockCCAnchor() end
        else
            if type(LockCCAnchor) == "function" then LockCCAnchor() end
        end
        KastaCDDB.ccAnchor.locked = not locked
        RefreshCCLockBtn()
    end)

    -- =========================================================
    -- refreshClassPanelsFns  –  sync checkbox + group-button state
    -- after a profile switch
    -- =========================================================
    refreshClassPanelsFns = {}
    for _, ci in ipairs(CLASS_INFO or {}) do
        local classFrame = panels[ci.key]
        if classFrame then
            table.insert(refreshClassPanelsFns, function()
                local function walk(f)
                    for _, child in ipairs({ f:GetChildren() }) do
                        if child.checkbox and child.checkbox.spellId then
                            child.checkbox:SetChecked(
                                KastaCDDB.enabled[child.checkbox.spellId] == true)
                        end
                        walk(child)
                    end
                end
                walk(classFrame)
            end)
        end
    end

    -- =========================================================
    -- Sidebar tabs
    -- =========================================================
    local sidebarTabs = {}
    local activeTab   = nil

    local function SetTabVisual(t, isActive)
        local alpha = isActive and 1.0 or 0.15
        t.bg:SetColorTexture(t.r, t.g, t.b, alpha)
        if isActive and t.r >= 0.99 and t.g >= 0.99 and t.b >= 0.99 then
            t.label:SetTextColor(0.05, 0.05, 0.05)
        else
            t.label:SetTextColor(1, 1, 1)
        end
    end

    local function SetActiveTab(name)
        activeTab = name
        ShowPanel(name)
        for n, t in pairs(sidebarTabs) do SetTabVisual(t, n == name) end
    end

    local TAB_H = 32
    local tabDefs = {
        { name="Settings",   label="Settings",    r=0.55, g=0.55, b=0.55 },
        { name="Interrupts", label="Interrupt Tracker", r=0.55, g=0.55, b=0.55 },
        { name="CrowdControl", label="Crowd Control Tracker", r=0.55, g=0.55, b=0.55 },
    }
    for _, ci in ipairs(CLASS_INFO or {}) do
        table.insert(tabDefs, { name=ci.key, label=ci.label, r=ci.r, g=ci.g, b=ci.b })
    end
    table.insert(tabDefs, { name="Profiles", label="Profiles", r=0.55, g=0.55, b=0.55 })

    for i, tab in ipairs(tabDefs) do
        local t = CreateFrame("Button", nil, frame)
        t:SetSize(SIDEBAR_W, TAB_H)
        t:SetPoint("TOPLEFT", sidebarBG, "TOPLEFT", 0, -(i - 1) * (TAB_H + 1))

        local bg = t:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        t.bg = bg
        t.r  = tab.r; t.g = tab.g; t.b = tab.b

        local lbl = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT", t, "LEFT", 10, 0)
        lbl:SetText(tab.label)
        t.label = lbl

        local tname = tab.name
        t:SetScript("OnEnter", function(self)
            if activeTab ~= tname then
                self.bg:SetColorTexture(t.r, t.g, t.b, 0.30)
            end
        end)
        t:SetScript("OnLeave", function(self)
            if activeTab ~= tname then SetTabVisual(self, false) end
        end)
        t:SetScript("OnClick", function() SetActiveTab(tname) end)

        t.name = tname
        sidebarTabs[tname] = t
        SetTabVisual(t, false)
    end

    SetActiveTab("Settings")
    kcdMenu = frame
end