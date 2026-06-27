-- =============================================================
-- KastaCD_Tracking.lua
-- Icon frame creation, grid layout, position anchoring,
-- icon-cluster rebuild, and the 0.1 s update ticker.
-- Depends on: KastaCD_SpellDB.lua, KastaCD_DB.lua
-- =============================================================

-- -------------------------------------------------------------
-- Module-level state
-- -------------------------------------------------------------
trackerState   = {}   -- [unit][spellId] = { frame, phase, endTime }
memberGUIDs    = {}   -- [unit] = GUID
iconContainers = {}   -- [unit.."_g"..group] = { container, icons={} }

-- -------------------------------------------------------------
-- Helpers
-- -------------------------------------------------------------
function HasGroup()
    if IsInGroup then return IsInGroup() end
    return GetNumGroupMembers and GetNumGroupMembers() > 0
end

function GetSpellGroup(spellId)
    local g = KastaCDDB and KastaCDDB.spellGroups and tonumber(KastaCDDB.spellGroups[spellId])
    if not g or g < 1 or g > SPELL_GROUP_COUNT then return 1 end
    return g
end

function SetSpellGroup(spellId, group)
    group = tonumber(group) or 1
    if group < 1 or group > SPELL_GROUP_COUNT then group = 1 end
    KastaCDDB.spellGroups[spellId] = group
end

-- Glow helpers (ActionButton overlay API)
function ShowProcGlow(f)
    if ActionButton_ShowOverlayGlow then ActionButton_ShowOverlayGlow(f) end
end
function HideProcGlow(f)
    if ActionButton_HideOverlayGlow then ActionButton_HideOverlayGlow(f) end
end

local FALLBACK_ICON = 134400
local function GetIconForSpell(spellId, fallbackIcon)
    local tex = GetSpellTexture and GetSpellTexture(spellId)
    if tex and tex ~= 0 then return tex end
    return fallbackIcon or FALLBACK_ICON
end

-- -------------------------------------------------------------
-- ClearIcons  –  destroy all icon frames and reset state
-- -------------------------------------------------------------
function ClearIcons()
    for _, iconList in pairs(iconContainers) do
        local icons = iconList.icons or iconList
        for _, ico in ipairs(icons) do
            if ico.spellId then HideProcGlow(ico) end
            ico:Hide()
        end
        if iconList.container then iconList.container:Hide() end
    end
    iconContainers = {}
    trackerState   = {}
    memberGUIDs    = {}
    -- Invalidate cached spec IDs so the next RebuildIcons re-inspects.
    if ClearSpecCache then ClearSpecCache() end
end

-- -------------------------------------------------------------
-- MakeIconFrame  –  create a single spell icon widget
-- -------------------------------------------------------------
local function MakeIconFrame(spellId, spellData, parent)
    local size = KastaCDDB.iconSize
    local f = CreateFrame("Frame", nil, parent or UIParent)
    f:SetSize(size, size)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(50)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)

    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture(GetIconForSpell(spellId, spellData.icon))
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.tex = tex

    -- Grey overlay shown while the spell is on cooldown
    local desat = f:CreateTexture(nil, "OVERLAY")
    desat:SetAllPoints()
    desat:SetColorTexture(0, 0, 0, 0.55)
    desat:Hide()
    f.desat = desat

    -- Cooldown / uptime text
    local cdText = f:CreateFontString(nil, "OVERLAY")
    cdText:SetFont("Fonts\\FRIZQT__.TTF", math.max(8, size * 0.38), "OUTLINE")
    cdText:SetPoint("CENTER", f, "CENTER", 0, 0)
    cdText:SetText("")
    f.cdText = cdText

    -- Bottom bar showing remaining uptime as a proportion of total duration
    local bar = f:CreateTexture(nil, "OVERLAY")
    bar:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  0, 0)
    bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    bar:SetHeight(2)
    bar:SetColorTexture(0.2, 1, 0.2, 1)
    bar:Hide()
    f.bar = bar

    f.spellId   = spellId
    f.spellData = spellData
    f.phase     = nil
    f.endTime   = 0
    f.startTime = 0

    -- Tooltip
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local ok = pcall(function() GameTooltip:SetSpellByID(spellId) end)
        if not ok then GameTooltip:SetText(spellData.name, 1, 1, 1) end
        local d = spellData
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Cooldown:",
            d.cooldown > 0 and (d.cooldown .. "s") or "None",
            0.7, 0.7, 0.7, 1, 1, 1)
        if d.duration > 0 then
            GameTooltip:AddDoubleLine("Duration:", d.duration .. "s", 0.7, 0.7, 0.7, 1, 1, 1)
        end
        if d.minLevel and d.minLevel > 1 then
            GameTooltip:AddDoubleLine("Min level:", tostring(d.minLevel), 0.7, 0.7, 0.7, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return f
end

-- -------------------------------------------------------------
-- PositionIconCluster  –  anchor a container to a raid frame
-- -------------------------------------------------------------
function PositionIconCluster(containerFrame, memberFrame, group)
    if not containerFrame or not memberFrame then return end
    local gIdx = (KastaCDDB.groupPositionIdx and KastaCDDB.groupPositionIdx[group or 1]) or 8
    local cfg  = POSITION_CFG[gIdx] or POSITION_CFG[8]
    local ox   = KastaCDDB.offsetX or 0
    local oy   = KastaCDDB.offsetY or 0
    -- Anchor directly to the member frame — no screen-coord snapshotting,
    -- so icons follow the frame correctly across UI scale and layout changes.
    containerFrame:ClearAllPoints()
    containerFrame:SetPoint(cfg.anchor, memberFrame, cfg.relAnchor, ox, oy)
end

-- -------------------------------------------------------------
-- LayoutIconRow  –  arrange icons in a grid inside their container
-- -------------------------------------------------------------
function LayoutIconRow(container, icons)
    local size = KastaCDDB.iconSize
    local ipr  = KastaCDDB.iconsPerRow
    local pad  = 2
    local cols = math.min(#icons, ipr)
    local rows = math.ceil(#icons / ipr)
    container:SetSize(
        cols * (size + pad) - pad,
        rows * (size + pad) - pad)
    for i, ico in ipairs(icons) do
        local col = (i - 1) % ipr
        local row = math.floor((i - 1) / ipr)
        ico:ClearAllPoints()
        ico:SetPoint("TOPLEFT", container, "TOPLEFT",
             col * (size + pad),
            -row * (size + pad))
        ico:SetSize(size, size)
    end
end

-- -------------------------------------------------------------
-- RebuildIcons  –  full rebuild of all icon clusters
-- Called on group roster changes, zone transitions, and settings changes.
-- -------------------------------------------------------------
function RebuildIcons()
    PersistActiveProfile()
    local oldState = trackerState
    ClearIcons()
    -- Do not gate on HasGroup() — the menu must open even when solo.
    -- Icons simply won't appear if there are no party members.
    if not IsContentEnabled() then return end
    local enabled = GetEnabledSpells()
    if not next(enabled) then return end

    -- Collect all visible raid frames (CompactRaidFrame, then classic fallback)
    local unitFramePairs = {}
    for i = 1, 40 do
        local f = _G["CompactRaidFrame" .. i]
        if not f then break end
        local unit = f.unit or f.displayedUnit
        if unit and UnitExists(unit) then
            table.insert(unitFramePairs, { unit=unit, frame=f })
        end
    end
    -- Classic PartyMemberFrame fallback for servers that don't use CompactRaidFrames
    if #unitFramePairs == 0 then
        for i = 1, 4 do
            local f = _G["PartyMemberFrame" .. i]
            local unit = "party" .. i
            if f and f:IsShown() and UnitExists(unit) then
                table.insert(unitFramePairs, { unit=unit, frame=f })
            end
        end
    end
    if #unitFramePairs == 0 then return end

    local now = GetTime()

    for _, pair in ipairs(unitFramePairs) do
        local unit = pair.unit
        local mf   = pair.frame
        if unit and UnitExists(unit) then
            memberGUIDs[unit] = UnitGUID(unit)
            local _, unitClass = UnitClass(unit)
            if unitClass then
                -- Bucket enabled spells for this unit into groups
                local spellGroups = {}
                for sid, data in pairs(enabled) do
                    if data.class == unitClass and IsSpellKnownForUnit(unit, sid) then
                        local g = GetSpellGroup(sid)
                        spellGroups[g] = spellGroups[g] or {}
                        table.insert(spellGroups[g], { sid=sid, data=data })
                    end
                end

                local hasSpells = false
                for i = 1, SPELL_GROUP_COUNT do
                    if spellGroups[i] and #spellGroups[i] > 0 then hasSpells = true end
                end

                if hasSpells then
                    for group = 1, SPELL_GROUP_COUNT do
                        local entries = spellGroups[group]
                        if entries and #entries > 0 then
                            table.sort(entries, function(a, b) return a.data.name < b.data.name end)

                            local containerKey = unit .. "_g" .. group
                            local container = CreateFrame("Frame", nil, UIParent)
                            container:SetFrameStrata("MEDIUM")
                            container:SetFrameLevel(48)
                            container:SetSize(1, 1)

                            local iconList = { container=container, icons={} }
                            iconContainers[containerKey] = iconList

                            trackerState[unit] = trackerState[unit] or {}

                            for _, entry in ipairs(entries) do
                                local ico = MakeIconFrame(entry.sid, entry.data, container)
                                local state = { frame=ico, phase=nil, endTime=0 }

                                -- Restore live cooldown / uptime from the previous build
                                local prev = oldState[unit] and oldState[unit][entry.sid]
                                if prev and prev.phase and prev.endTime and prev.endTime > now then
                                    state.phase   = prev.phase
                                    state.endTime = prev.endTime
                                    if state.phase == "uptime" then
                                        ShowProcGlow(ico)
                                        ico.bar:Show()
                                    elseif state.phase == "cooldown" then
                                        ico.desat:Show()
                                        local rem = prev.endTime - now
                                        ico.cdText:SetText(rem >= 60
                                            and string.format("%dm", math.ceil(rem / 60))
                                            or  string.format("%d",  math.ceil(rem)))
                                    end
                                end

                                trackerState[unit][entry.sid] = state
                                table.insert(iconList.icons, ico)
                            end

                            LayoutIconRow(container, iconList.icons)
                            PositionIconCluster(container, mf, group)
                            container:Show()
                            for _, ico in ipairs(iconList.icons) do ico:Show() end
                        end
                    end
                end
            end
        end
    end
end

-- -------------------------------------------------------------
-- RelayoutAllIcons  –  reposition existing clusters without a full rebuild
-- Called every ~0.5 s in case raid frames have moved.
-- -------------------------------------------------------------
local function RelayoutAllIcons()
    for i = 1, 40 do
        local f = _G["CompactRaidFrame" .. i]
        if not f then break end
        local unit = f.unit or f.displayedUnit
        if unit then
            for group = 1, SPELL_GROUP_COUNT do
                local iconList = iconContainers[unit .. "_g" .. group]
                if iconList and iconList.icons and #iconList.icons > 0 then
                    LayoutIconRow(iconList.container, iconList.icons)
                    PositionIconCluster(iconList.container, f, group)
                end
            end
        end
    end
end

-- -------------------------------------------------------------
-- Update ticker  –  runs every 0.1 s
-- Drives uptime bars, cooldown countdown text, and periodic relayout.
-- -------------------------------------------------------------
local relayoutElapsed = 0

C_Timer.NewTicker(0.1, function()
    local now = GetTime()

    relayoutElapsed = relayoutElapsed + 0.1
    if relayoutElapsed >= 0.5 then
        relayoutElapsed = 0
        RelayoutAllIcons()
    end

    for unit, spells in pairs(trackerState) do
        for sid, state in pairs(spells) do
            local f = state.frame
            if not f then
                -- Skip this spell; don't abort the entire unit loop.
            elseif state.phase == "uptime" then
                local rem = state.endTime - now
                if rem <= 0 then
                    -- Uptime expired → enter cooldown
                    local cd = SPELL_DB[sid].cooldown
                    if cd and cd > 0 then
                        state.phase = "cooldown"
                        state.endTime = now + cd
                    else
                        state.phase = nil
                    end
                    HideProcGlow(f)
                    f.bar:Hide()
                    f.cdText:SetText("")
                else
                    ShowProcGlow(f)
                    local dur = SPELL_DB[sid].duration
                    local pct = dur > 0 and (rem / dur) or 1
                    f.bar:Show()
                    f.bar:SetWidth(math.max(1, f:GetWidth() * pct))
                    f.cdText:SetText(rem >= 60
                        and string.format("%dm", math.ceil(rem / 60))
                        or  string.format("%d",  math.ceil(rem)))
                end

            elseif state.phase == "cooldown" then
                local rem = state.endTime - now
                if rem <= 0 then
                    state.phase = nil
                    f.desat:Hide()
                    f.cdText:SetText("")
                else
                    f.desat:Show()
                    f.cdText:SetText(rem >= 60
                        and string.format("%dm", math.ceil(rem / 60))
                        or  string.format("%d",  math.ceil(rem)))
                end

            else
                -- Idle state
                HideProcGlow(f)
                f.desat:Hide()
                f.bar:Hide()
                f.cdText:SetText("")
            end
        end
    end
end)