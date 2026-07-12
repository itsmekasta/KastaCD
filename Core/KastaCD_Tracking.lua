-- KastaCD_Tracking.lua - icon frame creation, grid layout, position
-- anchoring, icon-cluster rebuild, and the 0.1s update ticker.
-- Depends on: KastaCD_SpellDB.lua, KastaCD_DB.lua

trackerState   = {}   -- [unit][spellId] = { frame, phase, endTime }
memberGUIDs    = {}   -- [unit] = GUID
iconContainers = {}   -- [unit] = { container, icons={} }

-- Draggable anchors (one per party slot). Icons always attach to these -
-- TrySnapAnchor tries to snap near the real unit frame, but icons show
-- regardless. Unlock/drag via Settings > Unlock Anchors.
local PARTY_UNITS = { "player", "party1", "party2", "party3", "party4" }
local kcdAnchors  = {}   -- [unit] = frame

function IsRaidUnit(unit)
    return unit ~= nil and unit:match("^raid%d+$") ~= nil
end

-- player/party1-4 normally, or raid1-N while in a raid with "Show in Raid Groups" on.
function GetGroupUnits()
    if IsInRaid and IsInRaid() and KastaCDDB and KastaCDDB.showInRaidGroups then
        local units = {}
        local n = GetNumGroupMembers and GetNumGroupMembers() or 0
        for i = 1, n do
            units[#units + 1] = "raid" .. i
        end
        return units
    end
    return PARTY_UNITS
end

-- Raid members use their own separate raidOffsetX/raidIconSize/etc.
function GetIconSettingsFor(unit)
    if IsRaidUnit(unit) then
        return KastaCDDB.raidIconSize, KastaCDDB.raidIconsPerRow,
               KastaCDDB.raidOffsetX,  KastaCDDB.raidOffsetY
    end
    return KastaCDDB.iconSize, KastaCDDB.iconsPerRow,
           KastaCDDB.offsetX,  KastaCDDB.offsetY
end

local function GetOrMakeAnchor(unit)
    if kcdAnchors[unit] then return kcdAnchors[unit] end

    local idx = unit == "player" and 0
        or (tonumber(unit:match("party(%d)")) or tonumber(unit:match("raid(%d+)")) or 1)
    local a   = CreateFrame("Frame", nil, UIParent)
    a:SetSize(10, 10)
    a:SetMovable(true)
    a:EnableMouse(true)
    a:RegisterForDrag("LeftButton")
    a:SetScript("OnDragStart", function(self)
        if not (KastaCDDB and KastaCDDB.anchorsLocked) then self:StartMoving() end
    end)
    a:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if type(KastaCDDB) == "table" then
            if type(KastaCDDB.anchorPos) ~= "table" then KastaCDDB.anchorPos = {} end
            local esc = self:GetEffectiveScale()
            local usc = UIParent:GetEffectiveScale()
            KastaCDDB.anchorPos[unit] = {
                x = self:GetLeft() * esc,
                y = (self:GetTop() * esc) - (UIParent:GetTop() * usc),
            }
        end
    end)

    -- Orange square/label shown only when anchors are unlocked.
    local dot = a:CreateTexture(nil, "BACKGROUND")
    dot:SetAllPoints()
    dot:SetColorTexture(1, 0.5, 0, 0.9)
    dot:Hide()
    a.dot = dot

    local lbl = a:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("LEFT", a, "RIGHT", 3, 0)
    lbl:SetText(unit)
    lbl:Hide()
    a.lbl = lbl

    -- Load saved position, else spread down the centre of the screen
    local saved = type(KastaCDDB) == "table"
               and type(KastaCDDB.anchorPos) == "table"
               and KastaCDDB.anchorPos[unit]
    if saved then
        local esc = a:GetEffectiveScale()
        a:ClearAllPoints()
        a:SetPoint("TOPLEFT", UIParent, "TOPLEFT", saved.x / esc, saved.y / esc)
    else
        -- Fallback spread until a real frame is found or the user drags it.
        local col = math.floor(idx / 8)
        local row = idx % 8
        a:SetPoint("CENTER", UIParent, "CENTER", -130 + col * 160, (3 - row) * 55)
    end

    kcdAnchors[unit] = a
    return a
end

-- Called by the Settings panel "Unlock Anchors" button.
-- Only shows anchors for party/raid slots that are actually occupied.
function ShowKastaCDAnchors()
    local wanted = {}
    for _, u in ipairs(GetGroupUnits()) do
        wanted[u] = true
        if UnitExists(u) then
            local a = GetOrMakeAnchor(u)
            a.dot:Show(); a.lbl:Show(); a:Show()
        else
            local a = kcdAnchors[u]
            if a then a:Hide() end
        end
    end
    -- Hide dot/label left over from a different group shape.
    for u, a in pairs(kcdAnchors) do
        if not wanted[u] then
            a.dot:Hide(); a.lbl:Hide()
        end
    end
end

function HideKastaCDAnchors()
    for _, a in pairs(kcdAnchors) do
        a.dot:Hide(); a.lbl:Hide()
        -- Keep the frame itself alive (it's a positioning reference for icons)
    end
end

-- Apply / remove icon borders on all live icon frames without a full rebuild.
-- Borders = full texcoord (0,1,0,1); no borders = cropped coords that hide
-- the in-game border art (0.08,0.92,0.08,0.92).
function ApplyIconBorders()
    local on = KastaCDDB and KastaCDDB.showIconBorders
    for _, iconList in pairs(iconContainers) do
        for _, ico in ipairs(iconList.icons or {}) do
            if ico.tex then
                if on then
                    ico.tex:SetTexCoord(0, 1, 0, 1)
                else
                    ico.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end
            end
        end
    end
end

-- Snaps the anchor to the real unit frame (FindUnitFrames: ElvUI >
-- CompactRaid > vanilla), falling back to saved/default position if none
-- found. Returns true if it snapped - RebuildIcons uses this to hide the
-- player's own icons when their frame can't be found.
local function TrySnapAnchor(unit)
    local a = kcdAnchors[unit]
    if not a then return false end

    local mf = nil

    -- FindUnitFrames prioritises ElvUI frames, then CompactRaid, then vanilla.
    for _, pair in ipairs(FindUnitFrames()) do
        if pair.unit == unit then mf = pair.frame; break end
    end

    -- Fall back to PlayerFrame for the player slot, but never when ElvUI
    -- is active - its own detection above is the only source of truth then.
    if not mf and unit == "player" and not _G.ElvUI then
        local pf = _G["PlayerFrame"]
        if pf and pf.IsShown and pf:IsShown() and pf.GetRight then mf = pf end
    end

    local ox, oy = 0, 0
    if type(KastaCDDB) == "table" then
        local _, _, sox, soy = GetIconSettingsFor(unit)
        ox, oy = sox or 0, soy or 0
    end

    if mf then
        a:ClearAllPoints()
        local growLeft = type(KastaCDDB) == "table" and KastaCDDB.growLeft
        if growLeft then
            a:SetPoint("TOPRIGHT", mf, "TOPLEFT", ox, oy)
        else
            a:SetPoint("TOPLEFT", mf, "TOPRIGHT", ox, oy)
        end
        return true
    end

    -- No frame found — restore saved position or keep default
    local saved = type(KastaCDDB) == "table"
               and type(KastaCDDB.anchorPos) == "table"
               and KastaCDDB.anchorPos[unit]
    if saved then
        local esc = a:GetEffectiveScale()
        a:ClearAllPoints()
        a:SetPoint("TOPLEFT", UIParent, "TOPLEFT", saved.x / esc, saved.y / esc)
    end
    return false
end

function HasGroup()
    if IsInGroup then return IsInGroup() end
    return GetNumGroupMembers and GetNumGroupMembers() > 0
end

-- Icons are hidden in raid groups by default unless "Show in Raid Groups" is on.
function IsInPartyOnly()
    if IsInRaid and IsInRaid() then
        return KastaCDDB and KastaCDDB.showInRaidGroups == true
    end
    return HasGroup()
end

-- Glow helpers shared by every glow in the addon, controlled by one
-- Settings > Glow Color choice. Uses LibCustomGlow's "Action Button
-- Glow" (not the animated "Proc Glow" style - its flipbook loop visibly
-- restarted on a fixed cycle, tried and reverted).
function ShowProcGlow(f)
    if not f then return end
    local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
    if LCG then
        if f._ButtonGlow then return end -- already glowing, no need to restart it
        local c = KastaCDDB and KastaCDDB.glowColor
        LCG.ButtonGlow_Start(f, c and { c[1], c[2], c[3], c[4] or 1 } or nil)
        return
    end
    if ActionButton_ShowOverlayGlow then ActionButton_ShowOverlayGlow(f) end
end
function HideProcGlow(f)
    if not f then return end
    local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
    if LCG then LCG.ButtonGlow_Stop(f) end
    if ActionButton_HideOverlayGlow then ActionButton_HideOverlayGlow(f) end
end

local FALLBACK_ICON = 134400
local function GetIconForSpell(spellId, fallbackIcon)
    local tex = GetSpellTexture and GetSpellTexture(spellId)
    if tex and tex ~= 0 then return tex end
    return fallbackIcon or FALLBACK_ICON
end

-- FindUnitFrames locates party/raid member frames across unit-frame
-- addons. ElvUI's globals aren't populated the way stock CompactRaidFrame
-- ones are, so this reads its exposed engine table (E:GetModule
-- ('UnitFrames').headers) instead of guessing frame names.

-- Walks children/grandchildren of a header frame collecting shown units
-- (capped 2 levels deep). Only ever READS frame state - plain reads
-- don't taint a Blizzard-owned frame, only setters would (never used here).
local function CollectUnitChildren(frame, out, depth)
    if not frame or not frame.GetChildren then return end
    depth = depth or 0
    if depth > 2 then return end
    local children = { frame:GetChildren() }
    for _, child in ipairs(children) do
        local unit = child.unit or child.displayedUnit
        if unit and child:IsShown() and UnitExists(unit) then
            table.insert(out, { unit = unit, frame = child })
        else
            CollectUnitChildren(child, out, depth + 1)
        end
    end
end

-- Best-effort fallback for other unit-frame addons (Grid, Grid2, SUF)
-- that don't expose a documented API - unverified guesses, not a guarantee.
local OTHER_HEADER_PREFIXES = {
    "SUFHeaderraid", "SUFHeaderparty",
    "GridLayoutHeader1", "Grid2LayoutHeader1",
}

-- Returns { unit=<unitId>, frame=<frame> } for every visible party/raid
-- member frame, whatever unit-frame addon is in use.
function FindUnitFrames()
    local unitFramePairs = {}

    -- ElvUI checked first (visible alongside Blizzard CompactRaidFrames
    -- on this server). Only checks whichever group type is actually
    -- active - the raid-style header can spuriously read shown in a
    -- 5-man party after a /reload.
    if _G.ElvUI then
        local found = {}
        if IsInRaid and IsInRaid() then
            for g = 1, 8 do
                for i = 1, 5 do
                    local f = _G["ElvUF_RaidGroup" .. g .. "UnitButton" .. i]
                    if f then
                        local unit = f.unit or f.displayedUnit
                        if unit and f:IsShown() and UnitExists(unit) then
                            table.insert(found, { unit = unit, frame = f })
                        end
                    end
                end
            end
        else
            for i = 1, 5 do
                local f = _G["ElvUF_PartyGroup1UnitButton" .. i]
                if f then
                    local unit = f.unit or f.displayedUnit
                    if unit and f:IsShown() and UnitExists(unit) then
                        table.insert(found, { unit = unit, frame = f })
                    end
                end
            end
        end
        if #found > 0 then return found end
    end

    -- VuhDo exposes its own VUHDO_UNIT_BUTTONS[unit] table directly - no
    -- frame-name guessing needed, confirmed against its source.
    if _G.VUHDO_UNIT_BUTTONS then
        local found = {}
        for _, unit in ipairs(GetGroupUnits()) do
            local buttons = _G.VUHDO_UNIT_BUTTONS[unit]
            if buttons then
                for _, btn in ipairs(buttons) do
                    if btn:IsShown() then
                        table.insert(found, { unit = unit, frame = btn })
                        break
                    end
                end
            end
        end
        if #found > 0 then return found end
    end

    -- Blizzard CompactRaidFrames. Range extended to 90 (matches OmniCD's own list).
    for i = 1, 90 do
        local f = _G["CompactRaidFrame" .. i]
        if not f then break end
        local unit = f.unit or f.displayedUnit
        if unit and f:IsShown() and UnitExists(unit) then
            table.insert(unitFramePairs, { unit = unit, frame = f })
        end
    end
    if #unitFramePairs > 0 then return unitFramePairs end

    -- CompactRaidGroup<N>Member<M> - the "Keep Groups Together" raid layout naming.
    for g = 1, 8 do
        for m = 1, 5 do
            local f = _G["CompactRaidGroup" .. g .. "Member" .. m]
            if f then
                local unit = f.unit or f.displayedUnit
                if unit and f:IsShown() and UnitExists(unit) then
                    table.insert(unitFramePairs, { unit = unit, frame = f })
                end
            end
        end
    end
    if #unitFramePairs > 0 then return unitFramePairs end

    -- CompactPartyFrame - "Use Raid-Style Party Frames" enabled.
    local cpf = _G["CompactPartyFrame"]
    if cpf then
        CollectUnitChildren(cpf, unitFramePairs)
        if #unitFramePairs > 0 then return unitFramePairs end
    end

    -- Step 3: other header-based unit frame addons (best effort).
    for _, prefix in ipairs(OTHER_HEADER_PREFIXES) do
        for i = 1, 3 do
            local headerName = (i == 1) and prefix or (prefix .. i)
            local header = _G[headerName]
            if header then
                CollectUnitChildren(header, unitFramePairs)
            end
        end
    end
    if #unitFramePairs > 0 then return unitFramePairs end

    -- Classic PartyMemberFrame fallback. Skips IsShown() - some private
    -- server clients report these hidden even while visible.
    for i = 1, 4 do
        local f = _G["PartyMemberFrame" .. i]
        local unit = "party" .. i
        if f and UnitExists(unit) then
            table.insert(unitFramePairs, { unit = unit, frame = f })
        end
    end
    if #unitFramePairs > 0 then return unitFramePairs end

    -- Broad _G scan, last resort - matches any .unit/.displayedUnit frame.
    local needed = {}
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) then needed[u] = true end
    end
    if next(needed) then
        for _, v in pairs(_G) do
            if type(v) == "table" then
                local unit = (type(v.unit) == "string" and v.unit)
                          or (type(v.displayedUnit) == "string" and v.displayedUnit)
                if unit and needed[unit] and type(v.GetWidth) == "function" then
                    table.insert(unitFramePairs, { unit = unit, frame = v })
                    needed[unit] = nil
                    if not next(needed) then break end
                end
            end
        end
    end

    return unitFramePairs
end

-- NOTE: "Hide Blizzard Buffs/Debuffs on Party Frames" used to live here -
-- removed after a live taint report; needs a taint-free overlay approach
-- (never a setter on a Blizzard-owned frame) before it can come back.

-- Graveyard of every container ever created, so ClearIcons always finds them.
local _allContainers = {}
local lastBuildSignature = nil

-- keepFrames (optional): [unit][spellId] = true for icons being reused
-- this rebuild - left untouched instead of torn down, so a mid-uptime
-- glow doesn't visibly flicker/restart.
function ClearIcons(keepFrames)
    for _, container in ipairs(_allContainers) do
        container:Hide()
        container:ClearAllPoints()
    end
    for unit, iconList in pairs(iconContainers) do
        local icons = iconList.icons or {}
        local keep = keepFrames and keepFrames[unit]
        for _, ico in ipairs(icons) do
            if not (keep and ico.spellId and keep[ico.spellId]) then
                if ico.spellId then HideProcGlow(ico) end
                ico:Hide()
            end
        end
    end
    -- Wipe in-place - reassigning taints Blizzard protected frames.
    for k in pairs(iconContainers) do iconContainers[k] = nil end
    for k in pairs(trackerState)   do trackerState[k]   = nil end
    for k in pairs(memberGUIDs)    do memberGUIDs[k]    = nil end
    -- Deliberately doesn't clear UNIT_SPEC_CACHE (keyed by GUID, stale
    -- entries are harmless) - clearing here would forget a just-learned
    -- spec and cause a flicker loop.
    -- Forces the next RebuildIcons to do a full rebuild, not a relayout.
    lastBuildSignature = nil
end

local function MakeIconFrame(spellId, spellData, parent, size)
    size = size or KastaCDDB.iconSize
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
    if KastaCDDB and KastaCDDB.showIconBorders then
        tex:SetTexCoord(0, 1, 0, 1)
    else
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
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

    -- Bottom-right badge: remaining charge count for spells with maxCharges > 1.
    -- Stays empty for single-charge spells (no text set on them).
    local chargesText = f:CreateFontString(nil, "OVERLAY")
    chargesText:SetFont("Fonts\\FRIZQT__.TTF", math.max(8, size * 0.45), "OUTLINE")
    chargesText:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    chargesText:SetText("")
    f.chargesText = chargesText

    f.spellId   = spellId
    f.spellData = spellData
    f.phase     = nil
    f.endTime   = 0
    f.startTime = 0

    -- Tooltip
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
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

-- kcdAnchors are addon-owned frames, so SetPoint here is taint-free.
function PositionIconCluster(containerFrame, anchorFrame)
    if not containerFrame or not anchorFrame then return end
    containerFrame:ClearAllPoints()
    if KastaCDDB and KastaCDDB.growLeft then
        containerFrame:SetPoint("BOTTOMRIGHT", anchorFrame, "TOPRIGHT", 0, 0)
    else
        containerFrame:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, 0)
    end
end

function LayoutIconRow(container, icons, size, ipr)
    size = size or KastaCDDB.iconSize
    ipr  = ipr  or KastaCDDB.iconsPerRow
    local cols = math.min(#icons, ipr)
    local rows = math.ceil(#icons / ipr)
    container:SetSize(cols * size, rows * size)
    for i, ico in ipairs(icons) do
        local col = (i - 1) % ipr
        local row = math.floor((i - 1) / ipr)
        ico:ClearAllPoints()
        ico:SetPoint("TOPLEFT", container, "TOPLEFT", col * size, -row * size)
        ico:SetSize(size, size)
    end
end

-- Full rebuild of all icon clusters, called on roster changes, zone
-- transitions, and settings changes. Tracks the last build's signature
-- (see below) so a no-op call bails before touching any frames - a
-- brand new frame always starts with glowing=nil, so rebuilding
-- unconditionally caused nonstop glow flashing.
function RebuildIcons()
    PersistActiveProfile()

    -- Master switch - unconditionally re-asserts hidden state every call
    -- while disabled, since "still visible after disabling" can't happen.
    if KastaCDDB.iconsEnabled == false then
        lastBuildSignature = nil
        ClearIcons()
        return
    end

    -- Hide in raids - too many frames, CompactRaidFrames are harder to anchor to.
    if not IsInPartyOnly() then
        if lastBuildSignature ~= nil then lastBuildSignature = nil; ClearIcons() end
        return
    end
    if not IsContentEnabled() then
        if lastBuildSignature ~= nil then lastBuildSignature = nil; ClearIcons() end
        return
    end
    local enabled = GetEnabledSpells()
    if not next(enabled) then
        if lastBuildSignature ~= nil then lastBuildSignature = nil; ClearIcons() end
        return
    end

    -- UnitIsConnected (not just UnitExists) is what hides an offline member's icons.
    local activeUnits = {}
    for _, u in ipairs(GetGroupUnits()) do
        if UnitExists(u) and UnitIsConnected(u) then
            GetOrMakeAnchor(u)   -- ensure anchor exists
            activeUnits[#activeUnits+1] = u
        end
    end
    if #activeUnits == 0 then
        if lastBuildSignature ~= nil then lastBuildSignature = nil; ClearIcons() end
        return
    end

    -- Snap anchors to any discoverable unit frame; tracked per-unit so
    -- Pass 1 can hide the player's own icons entirely if no frame is
    -- found (no useful fallback position for just the player).
    local snapped = {}
    for _, u in ipairs(activeUnits) do snapped[u] = TrySnapAnchor(u) end

    -- Pass 1: figure out what SHOULD be shown, without touching any frames.
    local desired = {}   -- [unit] = { spells = { {sid,data}, ... } }
    -- Includes both party and raid settings so a change to the inactive
    -- shape still forces a rebuild once the group shape switches to it.
    local sigParts = {
        tostring(KastaCDDB.iconSize), tostring(KastaCDDB.iconsPerRow),
        tostring(KastaCDDB.offsetX), tostring(KastaCDDB.offsetY),
        tostring(KastaCDDB.raidIconSize), tostring(KastaCDDB.raidIconsPerRow),
        tostring(KastaCDDB.raidOffsetX), tostring(KastaCDDB.raidOffsetY),
    }

    for _, unit in ipairs(activeUnits) do
        -- Player-only: skip if no real frame was found to snap to.
        if UnitExists(unit) and not (unit == "player" and not snapped[unit]) then
            local _, unitClass = UnitClass(unit)
            if unitClass then
                local spells = {}
                for sid, data in pairs(enabled) do
                    -- A spell actually mid-uptime/cooldown counts as "known"
                    -- even if IsSpellKnownForUnit's talent-scan is transiently
                    -- false this poll - a real witnessed cast is stronger
                    -- evidence than a polling hiccup (matters for short-uptime
                    -- talents like Ravager, where one stale read could tear
                    -- the live timer down mid-flight).
                    local activeState = trackerState[unit] and trackerState[unit][sid]
                    local isActive = activeState and activeState.phase ~= nil
                    if (data.class == unitClass or data.class == "ALL") and (IsSpellKnownForUnit(unit, sid) or isActive) then
                        -- Medallion: skip outside Arena/BG unless the "outside PvP" toggle is on
                        if sid == 208683 and not KastaCDDB.medallionOutsidePvP then
                            local ct = GetCurrentContentType()
                            if ct ~= "Arena" and ct ~= "Battleground" then
                                -- skip
                            else
                                table.insert(spells, { sid=sid, data=data })
                            end
                        else
                            table.insert(spells, { sid=sid, data=data })
                        end
                    end
                end
                if #spells > 0 then
                    table.sort(spells, function(a, b) return a.data.name < b.data.name end)
                    -- PvP Medallion always last regardless of alphabetical order
                    for i, e in ipairs(spells) do
                        if e.sid == 208683 and i < #spells then
                            table.remove(spells, i)
                            table.insert(spells, e)
                            break
                        end
                    end
                    desired[unit] = { spells = spells }
                    sigParts[#sigParts+1] = unit
                    for _, e in ipairs(spells) do
                        sigParts[#sigParts+1] = e.sid
                    end
                end
            end
        end
    end

    local signature = table.concat(sigParts, "|")
    if signature == lastBuildSignature then
        -- Nothing changed - just reposition, leave every icon untouched.
        RelayoutAllIcons()
        return
    end
    lastBuildSignature = signature

    -- Pass 2: snapshot live timers (a real shallow copy - trackerState
    -- itself gets wiped in-place by ClearIcons below), then rebuild.
    local oldState = {}
    for unit, spells in pairs(trackerState) do
        oldState[unit] = {}
        for sid, state in pairs(spells) do
            local rechargeCopy
            if state.rechargeEndTimes then
                rechargeCopy = {}
                for i, v in ipairs(state.rechargeEndTimes) do rechargeCopy[i] = v end
            end
            oldState[unit][sid] = {
                phase = state.phase, endTime = state.endTime,
                charges = state.charges, maxCharges = state.maxCharges,
                rechargeEndTimes = rechargeCopy, cdEndTime = state.cdEndTime,
            }
        end
    end

    -- Which existing (unit, spellId) frames carry over to the new build -
    -- reusing the same frame object keeps f.glowing intact so a mid-uptime
    -- glow doesn't flicker off/on when anything else changes the signature.
    local keepFrames, reusedFrame = {}, {}
    for unit, iconList in pairs(iconContainers) do
        for _, ico in ipairs(iconList.icons or {}) do
            if ico.spellId and desired[unit] then
                for _, entry in ipairs(desired[unit].spells) do
                    if entry.sid == ico.spellId then
                        keepFrames[unit] = keepFrames[unit] or {}
                        keepFrames[unit][ico.spellId] = true
                        reusedFrame[unit] = reusedFrame[unit] or {}
                        reusedFrame[unit][ico.spellId] = ico
                        break
                    end
                end
            end
        end
    end

    ClearIcons(keepFrames)

    local now = GetTime()

    for unit, info in pairs(desired) do
        local anchorFrame = kcdAnchors[unit]
        if anchorFrame then
            memberGUIDs[unit] = UnitGUID(unit)
            trackerState[unit] = trackerState[unit] or {}

            local entries = info.spells
            if entries and #entries > 0 then
                local container = CreateFrame("Frame", nil, UIParent)
                container:SetFrameStrata("MEDIUM")
                container:SetFrameLevel(48)
                container:SetSize(1, 1)
                table.insert(_allContainers, container)

                local iconList = { container=container, icons={} }
                iconContainers[unit] = iconList

                local unitSize, unitIpr = GetIconSettingsFor(unit)

                for _, entry in ipairs(entries) do
                    local reused = reusedFrame[unit] and reusedFrame[unit][entry.sid]
                    local ico
                    if reused then
                        -- Preserves f.glowing; re-applies size/border in case settings changed.
                        ico = reused
                        ico:SetParent(container)
                        ico:SetSize(unitSize, unitSize)
                        if KastaCDDB and KastaCDDB.showIconBorders then
                            ico.tex:SetTexCoord(0, 1, 0, 1)
                        else
                            ico.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                        end
                        ico:Show()
                    else
                        ico = MakeIconFrame(entry.sid, entry.data, container, unitSize)
                    end
                    local state = { frame=ico, phase=nil, endTime=0 }

                    -- Initialise charge tracking for multi-charge spells
                    if entry.data.maxCharges and entry.data.maxCharges > 1 then
                        state.maxCharges       = entry.data.maxCharges
                        state.charges          = entry.data.maxCharges
                        state.rechargeEndTimes = {}
                    end

                    -- Restore live cooldown / uptime from the previous build
                    local prev = oldState[unit] and oldState[unit][entry.sid]
                    if prev then
                        -- Restore charge state first (needed by phase restoration below)
                        if prev.maxCharges then
                            state.maxCharges       = prev.maxCharges
                            state.charges          = prev.charges or prev.maxCharges
                            state.rechargeEndTimes = prev.rechargeEndTimes or {}
                        end
                        if state.maxCharges then
                            ico.chargesText:SetText(tostring(state.charges))
                        end

                        state.cdEndTime = prev.cdEndTime

                        if prev.phase and prev.endTime and prev.endTime > now then
                            state.phase   = prev.phase
                            state.endTime = prev.endTime
                            if state.phase == "uptime" then
                                if not reused then
                                    -- Don't call ShowProcGlow here - it'd restart the flipbook
                                    -- animation. Leave glowing=false; the 0.1s ticker starts it.
                                    ico.glowing = false
                                end
                                -- Reused frames keep their existing f.glowing untouched.
                                ico.bar:Show()
                            elseif state.phase == "cooldown" then
                                ico.desat:Show()
                                local rem = prev.endTime - now
                                ico.cdText:SetText(rem >= 60
                                    and string.format("%dm", math.ceil(rem / 60))
                                    or  string.format("%d",  math.ceil(rem)))
                            end
                        end
                    elseif state.maxCharges then
                        -- Fresh frame with no prior state: display full charge count
                        ico.chargesText:SetText(tostring(state.charges))
                    end

                    trackerState[unit][entry.sid] = state
                    table.insert(iconList.icons, ico)
                end

                LayoutIconRow(container, iconList.icons, unitSize, unitIpr)
                PositionIconCluster(container, anchorFrame)
                container:Show()
                for _, ico in ipairs(iconList.icons) do ico:Show() end
            end
        end
    end

    -- Enforce correct anchor visual state - cheap, just toggles dot+label.
    if KastaCDDB and not KastaCDDB.anchorsLocked then
        ShowKastaCDAnchors()
    else
        HideKastaCDAnchors()
    end
end

-- Repositions existing clusters without a full rebuild; called every ~0.5s.
local function RelayoutAllIcons()
    local groupUnits = GetGroupUnits()
    for _, u in ipairs(groupUnits) do
        if kcdAnchors[u] then TrySnapAnchor(u) end
    end
    for _, u in ipairs(groupUnits) do
        local anchorFrame = kcdAnchors[u]
        if anchorFrame then
            local iconList = iconContainers[u]
            if iconList and iconList.icons and #iconList.icons > 0 then
                local unitSize, unitIpr = GetIconSettingsFor(u)
                LayoutIconRow(iconList.container, iconList.icons, unitSize, unitIpr)
                PositionIconCluster(iconList.container, anchorFrame)
            end
        end
    end
end

-- Runs every 0.1s: uptime bars, cooldown countdown text, periodic relayout.
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
                    HideProcGlow(f)
                    f.glowing = false
                    f.bar:Hide()
                    f.cdText:SetText("")
                    if state.maxCharges then
                        -- Multi-charge spell: only enter cooldown when all charges are gone
                        if state.charges == 0 and state.rechargeEndTimes[1] then
                            state.phase   = "cooldown"
                            state.endTime = state.rechargeEndTimes[1]
                        else
                            state.phase = nil   -- still has charges, icon stays ready
                        end
                    else
                        -- Use the cooldown end time from the original cast
                        -- (state.cdEndTime), not a fresh timer from "now".
                        local cd = SPELL_DB[sid].cooldown
                        if state.cdEndTime and state.cdEndTime > now then
                            state.phase   = "cooldown"
                            state.endTime = state.cdEndTime
                        elseif cd and cd > 0 and not state.cdEndTime then
                            -- Safe fallback if no precomputed cooldown end exists.
                            state.phase = "cooldown"
                            state.endTime = now + cd
                        else
                            state.phase = nil
                        end
                    end
                else
                    -- Trigger glow once on uptime start, not every tick (restarts the flipbook).
                    if not f.glowing then
                        ShowProcGlow(f)
                        f.glowing = true
                    end
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
                    f.desat:Hide()
                    f.cdText:SetText("")
                    if state.maxCharges then
                        -- A charge recharged: pop the completed entry and increment
                        table.remove(state.rechargeEndTimes, 1)
                        state.charges = math.min(state.maxCharges, state.charges + 1)
                        f.chargesText:SetText(tostring(state.charges))
                        if state.charges < state.maxCharges and state.rechargeEndTimes[1] then
                            -- Still recharging remaining charges
                            state.endTime = state.rechargeEndTimes[1]
                        else
                            state.phase = nil
                        end
                    else
                        state.phase = nil
                    end
                else
                    f.desat:Show()
                    f.cdText:SetText(rem >= 60
                        and string.format("%dm", math.ceil(rem / 60))
                        or  string.format("%d",  math.ceil(rem)))
                end

            else
                -- Idle state
                if f.glowing then
                    HideProcGlow(f)
                    f.glowing = false
                end
                f.desat:Hide()
                f.bar:Hide()
                f.cdText:SetText("")
            end
        end
    end
end)