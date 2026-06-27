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
-- KastaCDDB (offsetX, iconSize, groupPositionIdx, contentTypes, etc.)
-- by the time CreateKastaCDMenu() ran. That's true for an existing
-- install whose SavedVariables already have every field, but it's
-- NOT guaranteed for:
--   - a brand new install (no KastaCDDB on disk yet)
--   - someone upgrading from an older save shape missing newer fields
--     like groupPositionIdx/spellGroups
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
    if type(KastaCDDB.spellGroups) ~= "table" then KastaCDDB.spellGroups = {} end

    if type(KastaCDDB.groupPositionIdx) ~= "table" then
        KastaCDDB.groupPositionIdx = {}
    end
    local groupCount = (type(SPELL_GROUP_COUNT) == "number" and SPELL_GROUP_COUNT) or 3
    for g = 1, groupCount do
        if type(KastaCDDB.groupPositionIdx[g]) ~= "number" then
            KastaCDDB.groupPositionIdx[g] = 8
        end
    end

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
    local val = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    val:SetPoint("LEFT", s, "RIGHT", 8, 0)
    val:SetText(tonumber(curVal) or minV)
    val:SetTextColor(1, 1, 1)
    s:SetScript("OnValueChanged", function(_, v)
        local fv = math.floor(v)
        val:SetText(fv)
        onChange(fv)
    end)
    return s, val
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
-- CreateKastaCDMenu  –  build the full UI (called once, lazily)
-- =============================================================
function CreateKastaCDMenu()
    if kcdMenu then return end

    -- Must run before anything below touches KastaCDDB.* - see the
    -- big comment on EnsureMenuDBDefaults above for why this is the
    -- actual fix for "menu works for me, not for other users."
    EnsureMenuDBDefaults()

    local FRAME_W   = 860
    local FRAME_H   = 540
    local SIDEBAR_W = 160

    -- ── Root frame ────────────────────────────────────────────
    local frame = CreateFrame("Frame", "KastaCDMenu", UIParent, "BackdropTemplate")
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
    verLbl:SetText("Kasta|cffff7f00CD|r v1.2")
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

    -- Group anchor pickers
    MakeLabel(panelPos, "Group Anchors:", "TOPLEFT", panelPos, "TOPLEFT", 14, -14)
    local groupAnchorY = -34
    local groupCount = (type(SPELL_GROUP_COUNT) == "number" and SPELL_GROUP_COUNT) or 3
    for g = 1, groupCount do
        local gLabel = panelPos:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        gLabel:SetPoint("TOPLEFT", panelPos, "TOPLEFT", 14, groupAnchorY)
        gLabel:SetText("Group " .. g .. ":")

        local posValLbl = panelPos:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        posValLbl:SetPoint("TOPLEFT", panelPos, "TOPLEFT", 72, groupAnchorY)
        posValLbl:SetTextColor(0.5, 0.8, 1)

        local gNum = g
        local function RefreshGroupPos()
            local idx = KastaCDDB.groupPositionIdx[gNum] or 8
            posValLbl:SetText((POSITION_OPTS and POSITION_OPTS[idx]) or "?")
        end

        local gPrevBtn = CreateFrame("Button", nil, panelPos, "UIPanelButtonTemplate")
        gPrevBtn:SetSize(24, 20)
        gPrevBtn:SetText("<")
        gPrevBtn:SetPoint("LEFT", posValLbl, "RIGHT", 6, 0)
        gPrevBtn:SetScript("OnClick", function()
            local idx = KastaCDDB.groupPositionIdx[gNum] or 8
            local total = (POSITION_OPTS and #POSITION_OPTS) or 9
            KastaCDDB.groupPositionIdx[gNum] = ((idx - 2) % total) + 1
            RefreshGroupPos()
            if type(RebuildIcons) == "function" then RebuildIcons() end
        end)

        local gNextBtn = CreateFrame("Button", nil, panelPos, "UIPanelButtonTemplate")
        gNextBtn:SetSize(24, 20)
        gNextBtn:SetText(">")
        gNextBtn:SetPoint("LEFT", gPrevBtn, "RIGHT", 2, 0)
        gNextBtn:SetScript("OnClick", function()
            local idx = KastaCDDB.groupPositionIdx[gNum] or 8
            local total = (POSITION_OPTS and #POSITION_OPTS) or 9
            KastaCDDB.groupPositionIdx[gNum] = (idx % total) + 1
            RefreshGroupPos()
            if type(RebuildIcons) == "function" then RebuildIcons() end
        end)

        RefreshGroupPos()
        groupAnchorY = groupAnchorY - 24
    end

    -- Offset / size / per-row sliders
    local offsetLabelY = groupAnchorY - 16

    MakeLabel(panelPos, "Offset X:", "TOPLEFT", panelPos, "TOPLEFT", 14, offsetLabelY)
    local oxS = MakeSlider(panelPos, -200, 200, KastaCDDB.offsetX, 200,
        function(v) KastaCDDB.offsetX = v; if type(RebuildIcons) == "function" then RebuildIcons() end end)
    oxS:SetPoint("TOPLEFT", panelPos, "TOPLEFT", 14, offsetLabelY - 18)

    MakeLabel(panelPos, "Offset Y:", "TOPLEFT", panelPos, "TOPLEFT", 14, offsetLabelY - 48)
    local oyS = MakeSlider(panelPos, -200, 200, KastaCDDB.offsetY, 200,
        function(v) KastaCDDB.offsetY = v; if type(RebuildIcons) == "function" then RebuildIcons() end end)
    oyS:SetPoint("TOPLEFT", panelPos, "TOPLEFT", 14, offsetLabelY - 66)

    MakeLabel(panelPos, "Icon Size:", "TOPLEFT", panelPos, "TOPLEFT", 14, offsetLabelY - 96)
    local isS = MakeSlider(panelPos, 12, 48, KastaCDDB.iconSize, 200,
        function(v) KastaCDDB.iconSize = v; if type(RebuildIcons) == "function" then RebuildIcons() end end)
    isS:SetPoint("TOPLEFT", panelPos, "TOPLEFT", 14, offsetLabelY - 114)

    MakeLabel(panelPos, "Icons per Row:", "TOPLEFT", panelPos, "TOPLEFT", 14, offsetLabelY - 144)
    local iprS = MakeSlider(panelPos, 1, 10, KastaCDDB.iconsPerRow, 200,
        function(v) KastaCDDB.iconsPerRow = v; if type(RebuildIcons) == "function" then RebuildIcons() end end)
    iprS:SetPoint("TOPLEFT", panelPos, "TOPLEFT", 14, offsetLabelY - 162)

    -- Content-type toggles
    local ctHdr = panelPos:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ctHdr:SetPoint("TOPLEFT", panelPos, "TOPLEFT", 14, offsetLabelY - 192)
    ctHdr:SetText("|cffff7f00Active in:|r")

    local ctY = offsetLabelY - 212
    for _, ct in ipairs(CONTENT_TYPES or {}) do
        local ctName = ct
        MakeToggle(panelPos, ctName, KastaCDDB.contentTypes[ctName] == true,
            "TOPLEFT", panelPos, "TOPLEFT", 14, ctY,
            function(v)
                KastaCDDB.contentTypes[ctName] = v
                if type(RebuildIcons) == "function" then RebuildIcons() end
            end)
        ctY = ctY - 26
    end

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
        copy.enabled = copy.enabled or {}
        copy.spellGroups = copy.spellGroups or {}
        copy.contentTypes = copy.contentTypes or {}
        for sid, v in pairs(cur.enabled or {})           do copy.enabled[sid]     = v end
        for sid, v in pairs(cur.spellGroups or {})        do copy.spellGroups[sid] = v end
        copy.groupPositionIdx = {
            (cur.groupPositionIdx and cur.groupPositionIdx[1]) or 8,
            (cur.groupPositionIdx and cur.groupPositionIdx[2]) or 8,
            (cur.groupPositionIdx and cur.groupPositionIdx[3]) or 8,
        }
        copy.offsetX     = cur.offsetX or 0
        copy.offsetY     = cur.offsetY or 0
        copy.iconSize    = cur.iconSize or 22
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
        for sid, group in pairs(p.spellGroups or {}) do
            group = tonumber(group) or 1
            if group > 1 then table.insert(parts, "g" .. sid .. "_" .. group) end
        end
        for ct, v in pairs(p.contentTypes or {}) do
            if v then table.insert(parts, "c" .. ct:gsub(" ", "_")) end
        end
        table.sort(parts)
        return string.format("KCD2:%d:%d:%d:%d:%d:%d:%d:%s",
            (p.groupPositionIdx and p.groupPositionIdx[1]) or 8,
            (p.groupPositionIdx and p.groupPositionIdx[2]) or 8,
            (p.groupPositionIdx and p.groupPositionIdx[3]) or 8,
            p.offsetX or 0, p.offsetY or 0, p.iconSize or 22, p.iconsPerRow or 5,
            table.concat(parts, ","))
    end

    -- Deserialise — supports both KCD2 (per-group anchors) and old KCD1 format
    local function DeserializeProfile(str)
        local p = type(NewProfileData) == "function" and NewProfileData() or {}
        p.enabled = p.enabled or {}
        local gp1, gp2, gp3, ox, oy, isz, ipr, rest =
            str:match("^KCD2:(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(.*)$")
        if not gp1 then
            -- Legacy KCD1 format (single position index)
            local pos
            pos, ox, oy, isz, ipr, rest =
                str:match("^KCD%d+:(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(.*)$")
            if not pos then return nil, "Bad format." end
            local pidx = tonumber(pos) or 8
            p.groupPositionIdx = { pidx, pidx, pidx }
        else
            p.groupPositionIdx = {
                tonumber(gp1) or 8,
                tonumber(gp2) or 8,
                tonumber(gp3) or 8,
            }
        end
        p.offsetX    = tonumber(ox)  or 0
        p.offsetY    = tonumber(oy)  or 0
        p.iconSize   = tonumber(isz) or 22
        p.iconsPerRow = tonumber(ipr) or 5
        p.contentTypes = {}
        local groupCountLocal = (type(SPELL_GROUP_COUNT) == "number" and SPELL_GROUP_COUNT) or 3
        for tok in ((rest or "") .. ","):gmatch("([^,]*),") do
            if tok ~= "" then
                local k, v = tok:sub(1, 1), tok:sub(2)
                if k == "e" then
                    local sid = tonumber(v)
                    if sid then p.enabled[sid] = true end
                elseif k == "g" then
                    local sid, grp = v:match("^(%d+)_(%d+)$")
                    sid, grp = tonumber(sid), tonumber(grp)
                    if sid and grp and grp >= 1 and grp <= groupCountLocal then
                        p.spellGroups[sid] = grp
                    end
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
    -- Per-class spell panels
    -- =========================================================
    for _, ci in ipairs(CLASS_INFO or {}) do
        local classFrame = CreateFrame("Frame", nil, contentArea)
        classFrame:SetAllPoints()
        panels[ci.key] = classFrame

        -- Class name header
        local hdr = classFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        hdr:SetPoint("TOPLEFT", classFrame, "TOPLEFT", 14, -10)
        hdr:SetText(string.format("|cff%02x%02x%02x%s|r",
            ci.r * 255, ci.g * 255, ci.b * 255, ci.label))

        -- Subtab bar (Offensives / Defensives / Interrupts / Immunity)
        local subTabBar = CreateFrame("Frame", nil, classFrame)
        subTabBar:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", -4, -10)
        subTabBar:SetSize(660, 24)

        local subPanels  = {}
        local subButtons = {}
        local activeSub  = nil

        local function ShowSub(key)
            activeSub = key
            for k, p in pairs(subPanels)  do p:SetShown(k == key) end
            for k, b in pairs(subButtons) do
                if k == key then
                    b.bg:SetColorTexture(1, 0.5, 0, 1)
                    b.lbl:SetTextColor(0, 0, 0)
                else
                    b.bg:SetColorTexture(0.15, 0.15, 0.15, 1)
                    b.lbl:SetTextColor(1, 1, 1)
                end
            end
        end

        -- Collect + sort spells for this class
        local classSpells = {}
        for sid, data in pairs(SPELL_DB or {}) do
            if data.class == ci.key then
                table.insert(classSpells, { sid=sid, data=data })
            end
        end
        table.sort(classSpells, function(a, b) return a.data.name < b.data.name end)

        -- Group-button highlight helper
        local function RefreshGroupButtons(row)
            local ag = type(GetSpellGroup) == "function" and GetSpellGroup(row.spellId) or 1
            for grp, btn in pairs(row.groupButtons or {}) do
                local fs = btn:GetFontString()
                if grp == ag then
                    btn:SetNormalFontObject("GameFontNormalSmall")
                    if fs then fs:SetTextColor(1, 0.82, 0) end
                else
                    btn:SetNormalFontObject("GameFontDisableSmall")
                    if fs then fs:SetTextColor(0.55, 0.55, 0.55) end
                end
            end
        end

        -- Build one scroll panel per subtab
        local tabX = 0
        for _, sd in ipairs(SUBTAB_DEFS or {}) do
            local sf = CreateFrame("ScrollFrame", nil, classFrame, "UIPanelScrollFrameTemplate")
            sf:SetPoint("TOPLEFT",     subTabBar, "BOTTOMLEFT",  4, -8)
            sf:SetPoint("BOTTOMRIGHT", classFrame, "BOTTOMRIGHT", -20, 0)
            subPanels[sd.key] = sf
            sf:Hide()

            local child = CreateFrame("Frame", nil, sf)
            child:SetWidth(640)
            sf:SetScrollChild(child)

            local cy    = -6
            local anyRow = false

            for _, entry in ipairs(classSpells) do
                local sid, data = entry.sid, entry.data
                if (CATEGORY_TO_SUBTAB and CATEGORY_TO_SUBTAB[data.category]) == sd.key then
                    anyRow = true
                    local row = CreateFrame("Frame", nil, child)
                    row:SetSize(640, 28)
                    row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, cy)

                    -- Spell icon thumbnail
                    local ico = row:CreateTexture(nil, "ARTWORK")
                    ico:SetSize(22, 22)
                    ico:SetPoint("LEFT", row, "LEFT", 0, 0)
                    ico:SetTexture(GetSpellTexture and GetSpellTexture(sid) or data.icon)
                    ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)

                    -- Enable checkbox
                    local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
                    cb:SetSize(22, 22)
                    cb:SetPoint("LEFT", ico, "RIGHT", 6, 0)
                    cb:SetChecked(KastaCDDB.enabled[sid] == true)
                    cb.spellId = sid
                    cb:SetScript("OnClick", function(self)
                        KastaCDDB.enabled[sid] = self:GetChecked() and true or nil
                        if type(RebuildIcons) == "function" then RebuildIcons() end
                    end)
                    row.checkbox = cb

                    -- Spell name
                    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    lbl:SetPoint("LEFT",  cb,  "RIGHT",  4, 0)
                    lbl:SetPoint("RIGHT", row, "RIGHT", -245, 0)
                    lbl:SetJustifyH("LEFT")
                    lbl:SetText(data.name)

                    row.spellId     = sid
                    row.groupButtons = {}

                    -- Group assignment buttons (1 / 2 / 3)
                    local groupCountLocal = (type(SPELL_GROUP_COUNT) == "number" and SPELL_GROUP_COUNT) or 3
                    for grp = 1, groupCountLocal do
                        local groupBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                        groupBtn:SetSize(24, 20)
                        groupBtn:SetPoint("RIGHT", row, "RIGHT", -210 + ((grp - 1) * 28), 0)
                        groupBtn:SetText(grp)
                        groupBtn:SetScript("OnClick", function()
                            if type(SetSpellGroup) == "function" then SetSpellGroup(sid, grp) end
                            RefreshGroupButtons(row)
                            if type(RebuildIcons) == "function" then RebuildIcons() end
                        end)
                        row.groupButtons[grp] = groupBtn
                    end
                    RefreshGroupButtons(row)

                    -- Cooldown / duration / level info
                    local info = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    info:SetPoint("RIGHT", row, "RIGHT", 0, 0)
                    info:SetTextColor(0.5, 0.5, 0.5)
                    local cdStr  = data.cooldown > 0 and (data.cooldown .. "s CD") or "no CD"
                    local durStr = data.duration > 0 and (" | " .. data.duration .. "s") or ""
                    info:SetText(cdStr .. durStr .. " | lvl " .. (data.minLevel or "?"))

                    cy = cy - 30
                end
            end

            if not anyRow then
                local empty = child:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                empty:SetPoint("TOPLEFT", child, "TOPLEFT", 0, cy)
                empty:SetText("(none)")
                cy = cy - 24
            end
            child:SetHeight(math.abs(cy) + 20)

            -- Subtab button
            local b = CreateFrame("Button", nil, subTabBar)
            b:SetSize(158, 24)
            b:SetPoint("TOPLEFT", subTabBar, "TOPLEFT", tabX, 0)
            local bg = b:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.15, 0.15, 0.15, 1)
            b.bg = bg
            local bl = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            bl:SetPoint("CENTER", b, "CENTER", 0, 0)
            bl:SetText(sd.label)
            b.lbl = bl
            local key = sd.key
            b:SetScript("OnClick", function() ShowSub(key) end)
            subButtons[key] = b
            tabX = tabX + 162
        end

        ShowSub((SUBTAB_DEFS and SUBTAB_DEFS[1] and SUBTAB_DEFS[1].key) or nil)
    end

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
                        if child.groupButtons and child.spellId then
                            local ag = type(GetSpellGroup) == "function" and GetSpellGroup(child.spellId) or 1
                            for grp, btn in pairs(child.groupButtons) do
                                local active = (grp == ag)
                                btn:SetNormalFontObject(active
                                    and "GameFontNormalSmall" or "GameFontDisableSmall")
                                local fs = btn:GetFontString()
                                if fs then
                                    fs:SetTextColor(
                                        active and 1    or 0.55,
                                        active and 0.82 or 0.55,
                                        active and 0    or 0.55)
                                end
                            end
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
        local brightness = t.r * 0.299 + t.g * 0.587 + t.b * 0.114
        if isActive and brightness > 0.5 then
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
    local tabDefs = { { name="Settings", label="Settings", r=0.55, g=0.55, b=0.55 } }
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