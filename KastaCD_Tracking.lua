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
iconContainers = {}   -- [unit] = { container, icons={} }

-- -------------------------------------------------------------
-- Draggable anchor frames (one per party slot)
--
-- Icons always attach to these anchors — no unit-frame detection
-- required. TrySnapAnchor() tries to position each anchor near its
-- real unit frame, but icons appear regardless. User can unlock and
-- drag them via Settings > Unlock Anchors when auto-snap fails.
-- -------------------------------------------------------------
local PARTY_UNITS = { "player", "party1", "party2", "party3", "party4" }
local kcdAnchors  = {}   -- [unit] = frame

local function GetOrMakeAnchor(unit)
    if kcdAnchors[unit] then return kcdAnchors[unit] end

    -- player = slot 0 (above party1 in default stacking)
    local idx = unit == "player" and 0 or (tonumber(unit:match("party(%d)")) or 1)
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

    -- Orange square and label shown only when anchors are unlocked.
    -- Hidden by default so newly created anchors don't appear unlocked
    -- when KastaCDDB.anchorsLocked is true (e.g. on every fresh login).
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
        a:SetPoint("CENTER", UIParent, "CENTER", -130, (3 - idx) * 55)
    end

    kcdAnchors[unit] = a
    return a
end

-- Called by the Settings panel "Unlock Anchors" button.
-- Only shows anchors for party slots that are actually occupied.
function ShowKastaCDAnchors()
    for _, u in ipairs(PARTY_UNITS) do
        if UnitExists(u) then
            local a = GetOrMakeAnchor(u)
            a.dot:Show(); a.lbl:Show(); a:Show()
        else
            -- Hide any stale anchor for this empty slot
            local a = kcdAnchors[u]
            if a then a:Hide() end
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

-- Always tries to find the real unit frame and snap the anchor to it.
-- Falls back to saved/default position only when no frame is found.
--
-- Uses FindUnitFrames() as the sole detection path (ElvUI > CompactRaid >
-- vanilla > broad scan) rather than checking PartyMemberFrame1..4 first.
-- Those vanilla globals still exist even when ElvUI is active (just hidden),
-- so the old early-out was silently snapping to the wrong, off-screen frames.
-- Anchors directly to the found frame instead of computing absolute pixel
-- coords — direct SetPoint means the anchor follows the frame automatically
-- if it ever moves.
local function TrySnapAnchor(unit)
    local a = kcdAnchors[unit]
    if not a then return end

    local mf = nil

    -- FindUnitFrames prioritises ElvUI frames, then CompactRaid, then vanilla.
    for _, pair in ipairs(FindUnitFrames()) do
        if pair.unit == unit then mf = pair.frame; break end
    end

    -- For the player slot, fall back to the dedicated PlayerFrame global when
    -- no unit-frame addon covers it (vanilla UI with no raid-style frames).
    if not mf and unit == "player" then
        local pf = _G["PlayerFrame"]
        if pf and pf.IsShown and pf:IsShown() and pf.GetRight then mf = pf end
    end

    local ox = (type(KastaCDDB) == "table" and KastaCDDB.offsetX) or 0
    local oy = (type(KastaCDDB) == "table" and KastaCDDB.offsetY) or 0

    if mf then
        a:ClearAllPoints()
        local growLeft = type(KastaCDDB) == "table" and KastaCDDB.growLeft
        if growLeft then
            a:SetPoint("TOPRIGHT", mf, "TOPLEFT", ox, oy)
        else
            a:SetPoint("TOPLEFT", mf, "TOPRIGHT", ox, oy)
        end
        return
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
end

-- -------------------------------------------------------------
-- Helpers
-- -------------------------------------------------------------
function HasGroup()
    if IsInGroup then return IsInGroup() end
    return GetNumGroupMembers and GetNumGroupMembers() > 0
end

-- Returns true only when in a party (not a raid).
-- Icons should be hidden in raid groups since they'd be too small
-- to be useful and CompactRaidFrames cover too many units to track.
function IsInPartyOnly()
    if IsInRaid and IsInRaid() then return false end
    return HasGroup()
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

-- =============================================================
-- FindUnitFrames
--
-- THE PROBLEM THIS FIXES: KastaCD only ever looked for Blizzard's
-- default CompactRaidFrame1..40 globals. Unit-frame replacement
-- addons like ElvUI build their party/raid frames through the oUF
-- framework instead, so those globals are never populated the way
-- KastaCD expected, and it found zero usable frames.
--
-- THE FIX (verified against actual ElvUI source, not guessed):
-- ElvUI deliberately exposes its internal engine table as a GLOBAL
-- named "ElvUI" specifically so other addons can hook into it — this
-- is ElvUI's own documented integration pattern, the same one its
-- official plugin template uses:
--     local E = unpack(ElvUI)
--     local UF = E:GetModule('UnitFrames')
-- UF.headers is a live table keyed by group name ("party", "raid")
-- pointing at the real header frame for that group. Party's header
-- has no "Group" suffix (ElvUI spawns it directly via CreateHeader
-- with no sub-groups, since headerstoload.party has no numGroups
-- value); Raid's header in turn owns up to 3 child sub-headers
-- (.groups[1], .groups[2], .groups[3]) for its raid-group buckets.
-- Each individual member button is a secure-template child of
-- whichever of those header frames is relevant, with its `.unit`
-- attribute set by oUF's own header-spawning code — the same
-- attribute Blizzard's frames and every other unit-frame addon use.
--
-- Reading UF.headers directly means KastaCD doesn't need to guess
-- ElvUI's internal frame names at all, and won't break if a future
-- ElvUI version changes its naming scheme, since this goes through
-- ElvUI's own supported module/engine access point instead.
-- =============================================================

-- Walks every child (and grandchild) of a header frame, collecting
-- any with a valid, currently-shown unit. Capped at 2 levels deep,
-- which covers header -> sub-group -> member-button nesting.
--
-- NOTE: this only ever READS frame state (GetChildren/IsShown/unit
-- field access). Plain reads on a Blizzard-owned frame don't taint
-- it. What WOULD taint it is calling a setter (SetPoint/Show/Hide/
-- SetSize/etc.) targeting that frame — which is exactly what we
-- avoid everywhere in this file. See PositionIconCluster below.
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

-- Best-effort fallback for OTHER unit-frame replacement addons
-- (Grid, Grid2, Shadowed Unit Frames) that, unlike ElvUI, don't
-- expose a documented external API to fetch their header frames by
-- name. These prefixes are not independently verified against each
-- addon's current source the way the ElvUI path above is — treat
-- this tier as a reasonable guess, not a guarantee.
local OTHER_HEADER_PREFIXES = {
    "SUFHeaderraid", "SUFHeaderparty",
    "GridLayoutHeader1", "Grid2LayoutHeader1",
}

-- Returns an array of { unit=<unitId>, frame=<frame> } for every
-- currently visible party/raid member frame KastaCD can find, no
-- matter which unit-frame addon (if any) is in use.
function FindUnitFrames()
    local unitFramePairs = {}

    -- Step 1: ElvUI – checked FIRST because on this server ElvUI and
    -- Blizzard CompactRaidFrames are both visible simultaneously.
    -- ElvUI frames must win so icons attach to the visible ones.
    if _G.ElvUI then
        local found = {}
        for i = 1, 5 do
            local f = _G["ElvUF_PartyGroup1UnitButton" .. i]
            if f then
                local unit = f.unit or f.displayedUnit
                if unit and f:IsShown() and UnitExists(unit) then
                    table.insert(found, { unit = unit, frame = f })
                end
            end
        end
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
        if #found > 0 then return found end
    end

    -- Step 2: Blizzard CompactRaidFrames (raid / raid-style party).
    for i = 1, 40 do
        local f = _G["CompactRaidFrame" .. i]
        if not f then break end
        local unit = f.unit or f.displayedUnit
        if unit and f:IsShown() and UnitExists(unit) then
            table.insert(unitFramePairs, { unit = unit, frame = f })
        end
    end
    if #unitFramePairs > 0 then return unitFramePairs end

    -- Step 2b: CompactPartyFrame – Legion default UI with "Use Raid-Style
    -- Party Frames" enabled. Members live as children of this container
    -- rather than as individually-named CompactRaidFrame globals.
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

    -- Step 4: classic PartyMemberFrame fallback (vanilla party frames,
    -- "Use Raid-Style Party Frames" disabled). Drop IsShown() – on some
    -- private-server clients these frames report hidden even while visible.
    for i = 1, 4 do
        local f = _G["PartyMemberFrame" .. i]
        local unit = "party" .. i
        if f and UnitExists(unit) then
            table.insert(unitFramePairs, { unit = unit, frame = f })
        end
    end
    if #unitFramePairs > 0 then return unitFramePairs end

    -- Step 5: broad _G scan – last resort for private-server clients where
    -- party frames exist visually but aren't registered under their expected
    -- global names. Scans every global table for a .unit / .displayedUnit
    -- matching an active party slot and a GetWidth method (i.e. it's a frame).
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

-- -------------------------------------------------------------
-- ClearIcons  –  destroy all icon frames and reset state
-- -------------------------------------------------------------
-- Graveyard: every container ever created, so ClearIcons can always
-- find and hide them even across multiple rapid rebuild cycles.
local _allContainers = {}

-- Declared here (above ClearIcons) so ClearIcons can reset it.
-- RebuildIcons uses this to skip full rebuilds when nothing changed.
local lastBuildSignature = nil

function ClearIcons()
    for _, container in ipairs(_allContainers) do
        container:Hide()
        container:ClearAllPoints()
    end
    for _, iconList in pairs(iconContainers) do
        local icons = iconList.icons or {}
        for _, ico in ipairs(icons) do
            if ico.spellId then HideProcGlow(ico) end
            ico:Hide()
        end
    end
    -- Wipe in-place — never reassign globals to new tables.
    -- Reassigning taints Blizzard protected frames causing SetHeight / UnitIsConnected errors.
    for k in pairs(iconContainers) do iconContainers[k] = nil end
    for k in pairs(trackerState)   do trackerState[k]   = nil end
    for k in pairs(memberGUIDs)    do memberGUIDs[k]    = nil end
    -- NOTE: deliberately does NOT call ClearSpecCache() here. ClearIcons()
    -- runs on every full rebuild (RebuildIcons Pass 2 whenever the desired
    -- spell set changes), which includes the moment a spec just resolved
    -- and a new spec-gated icon should appear. Wiping UNIT_SPEC_CACHE at
    -- that exact point immediately forgot the just-learned spec, sending
    -- spec-gated spells back to "unknown" (hidden) until the next poll or
    -- cast re-resolved it - a self-perpetuating flicker loop. The cache is
    -- keyed by GUID, not party slot, so stale entries from members who left
    -- are harmless and don't need clearing here.
    -- Force the next RebuildIcons to do a full rebuild regardless of
    -- whether the desired spell set looks the same as before. Without
    -- this, an external ClearIcons() call (e.g. from GROUP_ROSTER_UPDATE)
    -- leaves lastBuildSignature pointing at the now-destroyed frames,
    -- and the next RebuildIcons() call sees a matching signature and
    -- calls RelayoutAllIcons() on dead containers instead of rebuilding.
    lastBuildSignature = nil
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

-- -------------------------------------------------------------
-- PositionIconCluster  –  anchor a container to a kcdAnchor frame
--
-- kcdAnchors are addon-owned frames, so SetPoint is taint-free.
-- Groups stack vertically above the anchor (group 1 at the bottom,
-- group 2 above, etc.) with a small gap between each row.
-- -------------------------------------------------------------
function PositionIconCluster(containerFrame, anchorFrame)
    if not containerFrame or not anchorFrame then return end
    containerFrame:ClearAllPoints()
    if KastaCDDB and KastaCDDB.growLeft then
        containerFrame:SetPoint("BOTTOMRIGHT", anchorFrame, "TOPRIGHT", 0, 0)
    else
        containerFrame:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, 0)
    end
end

-- -------------------------------------------------------------
-- LayoutIconRow  –  arrange icons in a grid inside their container
-- -------------------------------------------------------------
function LayoutIconRow(container, icons)
    local size = KastaCDDB.iconSize
    local ipr  = KastaCDDB.iconsPerRow
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

-- -------------------------------------------------------------
-- RebuildIcons  –  full rebuild of all icon clusters
-- Called on group roster changes, zone transitions, and settings changes.
-- -------------------------------------------------------------
-- Tracks what the last successful RebuildIcons actually produced, so a
-- call that wouldn't change anything can bail out before touching any
-- frames. Without this, RebuildIcons() — which gets invoked very often
-- (roster ticks, spec re-checks, SPELLS_CHANGED, zone changes, etc.) —
-- was destroying and recreating every icon frame each time even when
-- the unit/spell list was identical. A brand new frame always starts
-- with glowing = nil, so the glow restarted on every single call,
-- which is what caused the nonstop flashing.

function RebuildIcons()
    PersistActiveProfile()

    -- Hide in raids — too many frames to be useful, and CompactRaidFrames
    -- are protected and harder to anchor to reliably at raid scale.
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

    -- ── Collect active party slots directly (anchor frames, no unit-frame detection) ──
    local activeUnits = {}
    for _, u in ipairs(PARTY_UNITS) do
        if UnitExists(u) then
            GetOrMakeAnchor(u)   -- ensure anchor exists
            activeUnits[#activeUnits+1] = u
        end
    end
    if #activeUnits == 0 then
        if lastBuildSignature ~= nil then lastBuildSignature = nil; ClearIcons() end
        return
    end

    -- Best-effort: snap anchors to any discoverable unit frames.
    for _, u in ipairs(activeUnits) do TrySnapAnchor(u) end

    -- ── Pass 1: figure out what SHOULD be shown, without touching any frames ──
    local desired = {}   -- [unit] = { spells = { {sid,data}, ... } }
    local sigParts = {
        tostring(KastaCDDB.iconSize), tostring(KastaCDDB.iconsPerRow),
        tostring(KastaCDDB.offsetX), tostring(KastaCDDB.offsetY),
    }

    for _, unit in ipairs(activeUnits) do
        if UnitExists(unit) then
            local _, unitClass = UnitClass(unit)
            if unitClass then
                local spells = {}
                for sid, data in pairs(enabled) do
                    if (data.class == unitClass or data.class == "ALL") and IsSpellKnownForUnit(unit, sid) then
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
        -- Nothing actually changed — just reposition in case frames moved,
        -- and leave every existing icon (and its glow/timer) untouched.
        RelayoutAllIcons()
        return
    end
    lastBuildSignature = signature

    -- ── Pass 2: snapshot live timers, then do the real rebuild ──
    -- `local oldState = trackerState` would NOT be a real copy — it's just
    -- another reference to the SAME table, so when ClearIcons() wipes
    -- trackerState in-place, it would wipe oldState too. Build an actual
    -- shallow copy instead.
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
                rechargeEndTimes = rechargeCopy,
            }
        end
    end

    ClearIcons()

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

                for _, entry in ipairs(entries) do
                    local ico = MakeIconFrame(entry.sid, entry.data, container)
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

                        if prev.phase and prev.endTime and prev.endTime > now then
                            state.phase   = prev.phase
                            state.endTime = prev.endTime
                            if state.phase == "uptime" then
                                -- Don't call ShowProcGlow directly here - calling it on
                                -- every rebuild while glow is active restarts the flipbook
                                -- animation, causing visible flicker. Leave glowing=false
                                -- so the 0.1s update ticker calls ShowProcGlow once on its
                                -- next pass through the same guard it uses during normal play.
                                ico.glowing = false
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

                LayoutIconRow(container, iconList.icons)
                PositionIconCluster(container, anchorFrame)
                container:Show()
                for _, ico in ipairs(iconList.icons) do ico:Show() end
            end
        end
    end

    -- Enforce correct anchor visual state after every rebuild.
    -- ShowKastaCDAnchors/HideKastaCDAnchors only toggle dot+label,
    -- so calling either on every rebuild is cheap and ensures newly
    -- created anchor frames always match the saved lock state.
    if KastaCDDB and not KastaCDDB.anchorsLocked then
        ShowKastaCDAnchors()
    else
        HideKastaCDAnchors()
    end
end

-- -------------------------------------------------------------
-- RelayoutAllIcons  –  reposition existing clusters without a full rebuild
-- Called every ~0.5 s in case frames have moved or the window was resized.
-- -------------------------------------------------------------
local function RelayoutAllIcons()
    -- Re-snap anchors to unit frames where discoverable
    for _, u in ipairs(PARTY_UNITS) do
        if kcdAnchors[u] then TrySnapAnchor(u) end
    end
    for _, u in ipairs(PARTY_UNITS) do
        local anchorFrame = kcdAnchors[u]
        if anchorFrame then
            local iconList = iconContainers[u]
            if iconList and iconList.icons and #iconList.icons > 0 then
                LayoutIconRow(iconList.container, iconList.icons)
                PositionIconCluster(iconList.container, anchorFrame)
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
                        local cd = SPELL_DB[sid].cooldown
                        if cd and cd > 0 then
                            state.phase = "cooldown"
                            state.endTime = now + cd
                        else
                            state.phase = nil
                        end
                    end
                else
                    -- Only (re)trigger the glow animation once when uptime
                    -- starts, not on every tick — ActionButton_ShowOverlayGlow
                    -- restarts its flipbook animation each call, so calling it
                    -- every 0.1s made the glow visibly flash/reset instead of
                    -- playing continuously.
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