-- KastaCD_BuffDisplay.lua - user-defined buff/debuff watch list.
-- Tracks real aura presence via UnitAura, not casts. Each watched spell
-- shows its own icon anchored to the owning unit's real frame.
-- Depends on: KastaCD_DB.lua, KastaCD_Tracking.lua

local PARTY_UNITS = { "player", "party1", "party2", "party3", "party4" }

-- Party by default; raid1-N while in a raid and this feature's own
-- "Show in Raid Groups" toggle is on (separate from the main tracker's).
local function GetBuffDisplayUnits()
    local db = GetBuffDisplayDB()
    if IsInRaid and IsInRaid() and db.showInRaidGroups then
        local units = {}
        local n = GetNumGroupMembers and GetNumGroupMembers() or 0
        for i = 1, n do units[#units + 1] = "raid" .. i end
        return units
    end
    return PARTY_UNITS
end

-- Best-effort class lookup for a spellId, for the options UI's class tabs.
-- Falls back to "OTHER" when unresolved.

-- Curated fallback for well-known external buffs not in SPELL_DB/CC_SPELLS.
local COMMON_BUFF_CLASS = {
    [102342] = "DRUID",       -- Ironbark
    [29166]  = "DRUID",       -- Innervate
    [33763]  = "DRUID",       -- Lifebloom
    [33206]  = "PRIEST",      -- Pain Suppression
    [47788]  = "PRIEST",      -- Guardian Spirit
    [62618]  = "PRIEST",      -- Power Word: Barrier
    [64843]  = "PRIEST",      -- Divine Hymn
    [1022]   = "PALADIN",     -- Blessing of Protection
    [6940]   = "PALADIN",     -- Blessing of Sacrifice
    [31821]  = "PALADIN",     -- Aura Mastery
    [465]    = "PALADIN",     -- Devotion Aura
    [223306] = "PALADIN",     -- Bestow Faith
    [200025] = "PALADIN",     -- Beacon of Virtue
    [53563]  = "PALADIN",     -- Beacon of Light
    [116849] = "MONK",        -- Life Cocoon
    [108271] = "SHAMAN",      -- Astral Shift
    [98008]  = "SHAMAN",      -- Spirit Link Totem
    [61295]  = "SHAMAN",      -- Riptide
    [196718] = "DEMONHUNTER", -- Darkness
}

local function GuessSpellClass(spellId)
    if type(SPELL_DB) == "table" and SPELL_DB[spellId] and SPELL_DB[spellId].class then
        return SPELL_DB[spellId].class
    end
    if type(CC_SPELLS) == "table" and CC_SPELLS[spellId] and CC_SPELLS[spellId].class then
        return CC_SPELLS[spellId].class
    end
    if COMMON_BUFF_CLASS[spellId] then return COMMON_BUFF_CLASS[spellId] end
    return "OTHER"
end

function GetBuffDisplayDB()
    KastaCDDB = KastaCDDB or {}
    local db = KastaCDDB.buffDisplay
    if not db then
        db = {}
        KastaCDDB.buffDisplay = db
    end
    if db.enabled == nil then db.enabled = true end
    if type(db.list) ~= "table" then db.list = {} end
    -- Test Mode: force every enabled watched spell to show with a fake timer.
    if db.testMode == nil then db.testMode = false end
    -- Shared Offset X/Y for every watched spell's icon (not per-spell).
    if db.offsetX == nil then db.offsetX = 0 end
    if db.offsetY == nil then db.offsetY = 0 end
    if db.raidOffsetX == nil then db.raidOffsetX = 0 end
    if db.raidOffsetY == nil then db.raidOffsetY = 0 end
    if db.showInRaidGroups == nil then db.showInRaidGroups = false end
    -- Row/column growth direction when 2+ watched spells are active at once.
    if db.growDirection == nil then db.growDirection = "CENTER" end
    if db.showIconBorders == nil then db.showIconBorders = false end
    -- Backfill name/class for entries added before those fields existed.
    for spellId, entry in pairs(db.list) do
        if not entry.name and GetSpellInfo then
            entry.name = GetSpellInfo(spellId)
        end
        entry.class = GuessSpellClass(spellId)
    end
    return db
end

-- Resolves a user-typed spell ID/name and adds it to the watch list.
-- Returns true, name on success or false, errorMessage on failure.
function AddBuffDisplaySpell(input)
    input = strtrim and strtrim(tostring(input or "")) or tostring(input or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if input == "" then return false, "Enter a spell ID or name." end

    if not GetSpellInfo then return false, "Spell lookup unavailable." end
    -- Not "GetSpellInfo and GetSpellInfo(input)" - `and` would collapse
    -- the multi-return call down to just its first value.
    local name, _, _, _, _, _, spellId = GetSpellInfo(input)
    if not name or not spellId then
        return false, "No spell found for \"" .. input .. "\" - try the exact spell ID instead."
    end

    local db = GetBuffDisplayDB()
    if db.list[spellId] then
        return false, name .. " is already in the list."
    end

    db.list[spellId] = {
        enabled    = true,
        glow       = true,
        showTimer  = true,
        iconSize   = 30,
        class      = GuessSpellClass(spellId),
        -- Kept for name-based aura matching (see ScanUnitAura) - this
        -- server can report a different spellId on the live UnitAura.
        name       = name,
    }
    return true, name
end

function RemoveBuffDisplaySpell(spellId)
    local db = GetBuffDisplayDB()
    db.list[spellId] = nil
    if bdIcons then
        for _, unit in ipairs(GetBuffDisplayUnits()) do
            HideBuffDisplayIcon(unit, spellId)
            if bdIcons[unit] then bdIcons[unit][spellId] = nil end
        end
    end
end

-- Icon frames: one per (unit, spellId) pair, created lazily and reused.
bdIcons  = {}   -- [unit][spellId] = frame
local bdActive = {}   -- [unit][spellId] = { expirationTime, duration } - only while shown

local function MakeBuffDisplayIcon(spellId, entry, parent)
    local size = entry.iconSize or 30
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(60)

    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture((GetSpellTexture and GetSpellTexture(spellId)) or 134400)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.tex = tex

    local timerText = f:CreateFontString(nil, "OVERLAY")
    timerText:SetFont("Fonts\\FRIZQT__.TTF", math.max(8, size * 0.4), "OUTLINE")
    timerText:SetPoint("CENTER", f, "CENTER", 0, 1)
    timerText:SetText("")
    f.timerText = timerText

    f.spellId = spellId
    f:Hide()
    return f
end

local function GetOrMakeBuffDisplayIcon(unit, spellId, entry)
    bdIcons[unit] = bdIcons[unit] or {}
    local f = bdIcons[unit][spellId]
    if not f then
        f = MakeBuffDisplayIcon(spellId, entry, UIParent)
        bdIcons[unit][spellId] = f
    end
    return f
end

function HideBuffDisplayIcon(unit, spellId)
    local f = bdIcons[unit] and bdIcons[unit][spellId]
    if f then
        if f.glowing then HideProcGlow(f); f.glowing = false end
        f:Hide()
    end
    if bdActive[unit] then bdActive[unit][spellId] = nil end
end

function HideAllBuffDisplayIcons()
    for unit, spells in pairs(bdIcons) do
        for spellId in pairs(spells) do
            HideBuffDisplayIcon(unit, spellId)
        end
    end
end

-- Scans one unit's HELPFUL and HARMFUL auras for the given spell.
-- Matches by name first when available (this server can report a
-- different spellId on live UnitAura than GetSpellInfo resolved).
-- This client's UnitAura uses the older signature with an extra "rank"
-- return, shifting later values by one - confirmed via /kcdbuffdebug.
-- Returns expirationTime, duration, found.
local function ScanUnitAura(unit, spellId, watchName)
    for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
        for i = 1, 40 do
            local auraName, _, _, _, _, duration, expirationTime, _, _, _, sid = UnitAura(unit, i, filter)
            if not auraName then break end
            if (watchName and auraName == watchName) or (not watchName and sid == spellId) then
                return expirationTime, duration, true
            end
        end
    end
    return nil, nil, false
end

-- Arranges every active icon for one unit in a row/column on that unit's
-- frame instead of stacking dead-center. Sorted by spellId for a stable
-- order. offsetX/offsetY is one shared position applied to the whole group.
-- growDirection: CENTER (default, horizontal both ways), LEFT/RIGHT
-- (horizontal one way), UP/DOWN (vertical).
local ICON_GAP = 2
local function LayoutUnitBuffIcons(mf, shown, offsetX, offsetY, growDirection)
    if #shown == 0 then return end
    table.sort(shown, function(a, b) return a.spellId < b.spellId end)
    growDirection = growDirection or "CENTER"

    if growDirection == "UP" or growDirection == "DOWN" then
        local cursor = 0
        for _, item in ipairs(shown) do
            local size = item.entry.iconSize or 30
            local centerY = cursor + size / 2
            if growDirection == "DOWN" then centerY = -centerY end
            item.f:ClearAllPoints()
            item.f:SetPoint("CENTER", mf, "CENTER", (offsetX or 0), centerY + (offsetY or 0))
            cursor = cursor + size + ICON_GAP
        end
        return
    end

    local totalWidth = -ICON_GAP
    for _, item in ipairs(shown) do
        totalWidth = totalWidth + (item.entry.iconSize or 30) + ICON_GAP
    end

    -- CENTER straddles the anchor evenly; LEFT extends left from the
    -- anchor; RIGHT extends right from the anchor.
    local x
    if growDirection == "LEFT" then
        x = -totalWidth
    elseif growDirection == "RIGHT" then
        x = 0
    else
        x = -totalWidth / 2
    end
    for _, item in ipairs(shown) do
        local size = item.entry.iconSize or 30
        item.f:ClearAllPoints()
        item.f:SetPoint("CENTER", mf, "CENTER", x + size / 2 + (offsetX or 0), (offsetY or 0))
        x = x + size + ICON_GAP
    end
end

-- Full re-scan of every watched spell against every tracked unit. Cheap
-- enough to call from the self-heal ticker and straight off UNIT_AURA.
function RefreshBuffDisplay()
    local db = GetBuffDisplayDB()
    if not db.enabled or not next(db.list) or not HasGroup() then
        HideAllBuffDisplayIcons()
        return
    end

    -- Test Mode forces every enabled entry to show with a fake 30s timer.
    local forceShow = db.testMode
    local now = GetTime()

    local unitFrames = {}
    for _, pair in ipairs(FindUnitFrames()) do
        unitFrames[pair.unit] = pair.frame
    end

    for _, unit in ipairs(GetBuffDisplayUnits()) do
        local mf = unitFrames[unit]
        bdActive[unit] = bdActive[unit] or {}
        if UnitExists(unit) and mf then
            local shown = {}
            for spellId, entry in pairs(db.list) do
                if entry.enabled ~= false then
                    local found, expirationTime, duration
                    if forceShow then
                        found, expirationTime, duration = true, now + 30, 30
                    else
                        expirationTime, duration, found = ScanUnitAura(unit, spellId, entry.name)
                    end
                    if found then
                        local f = GetOrMakeBuffDisplayIcon(unit, spellId, entry)
                        local size = entry.iconSize or 30
                        f:SetSize(size, size)
                        f.timerText:SetFont("Fonts\\FRIZQT__.TTF", math.max(8, size * 0.4), "OUTLINE")
                        if db.showIconBorders then
                            f.tex:SetTexCoord(0, 1, 0, 1)
                        else
                            f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                        end
                        f:Show()
                        if entry.glow ~= false then
                            if not f.glowing then ShowProcGlow(f); f.glowing = true end
                        elseif f.glowing then
                            HideProcGlow(f); f.glowing = false
                        end
                        bdActive[unit][spellId] = { expirationTime = expirationTime, duration = duration }
                        table.insert(shown, { spellId = spellId, entry = entry, f = f })
                    else
                        HideBuffDisplayIcon(unit, spellId)
                    end
                else
                    HideBuffDisplayIcon(unit, spellId)
                end
            end
            local isRaid = type(IsRaidUnit) == "function" and IsRaidUnit(unit)
            local offsetX = isRaid and db.raidOffsetX or db.offsetX
            local offsetY = isRaid and db.raidOffsetY or db.offsetY
            LayoutUnitBuffIcons(mf, shown, offsetX, offsetY, db.growDirection)
        else
            for spellId in pairs(db.list) do
                HideBuffDisplayIcon(unit, spellId)
            end
        end
    end
end

-- Timer text ticker (0.2s) - cosmetic countdown text only.
C_Timer.NewTicker(0.2, function()
    local db = GetBuffDisplayDB()
    if not db.enabled then return end
    local now = GetTime()
    for unit, spells in pairs(bdActive) do
        for spellId, info in pairs(spells) do
            local entry = db.list[spellId]
            local f = bdIcons[unit] and bdIcons[unit][spellId]
            if f and entry and f:IsShown() then
                if entry.showTimer ~= false and info.expirationTime and info.expirationTime > 0 then
                    local rem = info.expirationTime - now
                    if rem > 0 then
                        f.timerText:SetText(rem >= 60
                            and string.format("%dm", math.ceil(rem / 60))
                            or  string.format("%d",  math.ceil(rem)))
                    else
                        f.timerText:SetText("")
                    end
                else
                    f.timerText:SetText("")
                end
            end
        end
    end
end)

-- Self-heal ticker (1s) - catches roster changes and new watch entries.
C_Timer.NewTicker(1.0, function()
    if type(RefreshBuffDisplay) == "function" then RefreshBuffDisplay() end
end)

-- Immediate refresh on aura change instead of waiting for the ticker.
local bdWatcher = CreateFrame("Frame")
bdWatcher:RegisterEvent("UNIT_AURA")
bdWatcher:RegisterEvent("GROUP_ROSTER_UPDATE")
bdWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
bdWatcher:SetScript("OnEvent", function(_, event, arg1)
    if event == "UNIT_AURA" then
        local isWatched = false
        for _, u in ipairs(GetBuffDisplayUnits()) do
            if u == arg1 then isWatched = true; break end
        end
        if not isWatched then return end
    end
    if type(RefreshBuffDisplay) == "function" then RefreshBuffDisplay() end
end)

-- /kcdbuffdebug - dumps live state for diagnosing a "not showing" report.
SLASH_KASTACDBUFFDEBUG1 = "/kcdbuffdebug"
SlashCmdList["KASTACDBUFFDEBUG"] = function()
    local db = GetBuffDisplayDB()
    print("|cff00ff00KastaCD Buff Display Debug|r -- enabled=" .. tostring(db.enabled)
        .. " testMode=" .. tostring(db.testMode) .. " showInRaidGroups=" .. tostring(db.showInRaidGroups)
        .. " HasGroup=" .. tostring(HasGroup and HasGroup()))

    local n = 0
    for spellId, entry in pairs(db.list) do
        n = n + 1
        local name = (GetSpellInfo and GetSpellInfo(spellId)) or "?"
        print(("  [%d] %s enabled=%s class=%s"):format(spellId, name, tostring(entry.enabled), tostring(entry.class)))
    end
    if n == 0 then print("  (no spells in the watch list)") end

    print("|cff00ff00KastaCD Buff Display Debug|r -- FindUnitFrames() results:")
    local frames = FindUnitFrames and FindUnitFrames() or {}
    if #frames == 0 then
        print("  (none found - no unit-frame addon/Blizzard frame detected)")
    else
        for _, pair in ipairs(frames) do
            print(("  %s -> %s"):format(pair.unit, pair.frame and pair.frame:GetName() or "(unnamed frame)"))
        end
    end

    if n > 0 then
        print("|cff00ff00KastaCD Buff Display Debug|r -- live aura scan (matched by name):")
        for _, unit in ipairs(GetBuffDisplayUnits()) do
            if UnitExists(unit) then
                for spellId, entry in pairs(db.list) do
                    local expirationTime, duration, found = ScanUnitAura(unit, spellId, entry.name)
                    print(("  %s: %s (watching name=\"%s\") -> %s (duration=%s, expirationTime=%s)"):format(
                        unit, tostring(entry.name or spellId), tostring(entry.name),
                        found and "ACTIVE" or "not present", tostring(duration), tostring(expirationTime)))
                end

                print(("  %s's full aura list (compare names above against this):"):format(unit))
                for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
                    for i = 1, 40 do
                        local auraName, _, _, _, _, duration, expirationTime, _, _, _, sid = UnitAura(unit, i, filter)
                        if not auraName then break end
                        print(("    [%s] %s (spellId=%s, duration=%s, expirationTime=%s)"):format(
                            filter, auraName, tostring(sid), tostring(duration), tostring(expirationTime)))
                    end
                end
            end
        end
    end
end
