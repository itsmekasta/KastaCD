-- KastaCD_DebuffDisplay.lua - user-defined HARMFUL-aura watch list, same
-- UnitAura-presence mechanism as KastaCD_BuffDisplay.lua. Debuffs don't
-- map cleanly to a caster's class, so this uses user-created renamable
-- categories instead of auto-sorted class tabs.
-- Depends on: KastaCD_DB.lua, KastaCD_Tracking.lua

local PARTY_UNITS = { "player", "party1", "party2", "party3", "party4" }

-- Party by default; raid1-N while in a raid and this feature's own
-- "Show in Raid Groups" toggle is on (independent of the other trackers').
local function GetDebuffDisplayUnits()
    local db = GetDebuffDisplayDB()
    if IsInRaid and IsInRaid() and db.showInRaidGroups then
        local units = {}
        local n = GetNumGroupMembers and GetNumGroupMembers() or 0
        for i = 1, n do units[#units + 1] = "raid" .. i end
        return units
    end
    return PARTY_UNITS
end

function GetDebuffDisplayDB()
    KastaCDDB = KastaCDDB or {}
    local db = KastaCDDB.debuffDisplay
    if not db then
        db = {}
        KastaCDDB.debuffDisplay = db
    end
    if db.enabled == nil then db.enabled = true end
    if type(db.list) ~= "table" then db.list = {} end
    if db.testMode == nil then db.testMode = false end
    if db.offsetX == nil then db.offsetX = 0 end
    if db.offsetY == nil then db.offsetY = 0 end
    if db.raidOffsetX == nil then db.raidOffsetX = 0 end
    if db.raidOffsetY == nil then db.raidOffsetY = 0 end
    if db.showInRaidGroups == nil then db.showInRaidGroups = false end
    if db.growDirection == nil then db.growDirection = "CENTER" end
    if db.showIconBorders == nil then db.showIconBorders = false end
    -- User-managed categories, id-keyed. id=0 is reserved ("Uncategorized").
    if type(db.categories) ~= "table" then db.categories = {} end
    if db.nextCategoryId == nil then db.nextCategoryId = 1 end
    -- Backfill entries added before name-based aura matching (ScanUnitAura).
    for spellId, entry in pairs(db.list) do
        if not entry.name and GetSpellInfo then
            entry.name = GetSpellInfo(spellId)
        end
        if entry.categoryId == nil then entry.categoryId = 0 end
    end
    return db
end

-- Creates a new renamable category. Returns the new category's id.
function AddDebuffDisplayCategory(name)
    name = (strtrim and strtrim(tostring(name or ""))) or tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then name = "Category" end
    local db = GetDebuffDisplayDB()
    local id = db.nextCategoryId
    db.nextCategoryId = id + 1
    db.categories[id] = name
    return id
end

function RenameDebuffDisplayCategory(id, newName)
    newName = (strtrim and strtrim(tostring(newName or ""))) or tostring(newName or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if newName == "" then return end
    local db = GetDebuffDisplayDB()
    if db.categories[id] then db.categories[id] = newName end
end

-- Only removes an empty category. Returns true on success, false + reason.
function RemoveDebuffDisplayCategory(id)
    local db = GetDebuffDisplayDB()
    if not db.categories[id] then return false, "Category doesn't exist." end
    for _, entry in pairs(db.list) do
        if entry.categoryId == id then
            return false, "Move its spells to another category first."
        end
    end
    db.categories[id] = nil
    return true
end

function SetDebuffDisplaySpellCategory(spellId, categoryId)
    local db = GetDebuffDisplayDB()
    local entry = db.list[spellId]
    if not entry then return end
    if categoryId ~= 0 and not db.categories[categoryId] then categoryId = 0 end
    entry.categoryId = categoryId
end

-- Rename-a-category-tab-by-clicking-it. KASTACD_TabRenameClick is called
-- by the KastaCD-local AceGUIContainer-TabGroup.lua patch whenever an
-- already-selected tab is clicked again; only reacts to a real,
-- renamable category (not id 0/Uncategorized or another section's tab).
-- Popup registration is deferred to first use, not file load - writing
-- into StaticPopupDialogs at load time caused a persistent taint report.
local kastaRenamePopupRegistered = false
local function EnsureRenamePopupRegistered()
    if kastaRenamePopupRegistered then return end
    kastaRenamePopupRegistered = true
    StaticPopupDialogs = StaticPopupDialogs or {}
    StaticPopupDialogs["KASTACD_RENAME_DEBUFF_CATEGORY"] = {
        text = "Rename category:",
        button1 = "Rename",
        button2 = "Cancel",
        hasEditBox = true,
        maxLetters = 40,
        OnShow = function(self)
            self.editBox:SetText(self.data.currentName or "")
            self.editBox:HighlightText()
        end,
        OnAccept = function(self)
            RenameDebuffDisplayCategory(self.data.categoryId, self.editBox:GetText())
            if type(RefreshKastaCDOptionsTable) == "function" then RefreshKastaCDOptionsTable() end
        end,
        EditBoxOnEnterPressed = function(self)
            RenameDebuffDisplayCategory(self:GetParent().data.categoryId, self:GetText())
            if type(RefreshKastaCDOptionsTable) == "function" then RefreshKastaCDOptionsTable() end
            self:GetParent():Hide()
        end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
end

function KASTACD_TabRenameClick(tabValue)
    local idStr = type(tabValue) == "string" and tabValue:match("^category_(%d+)$")
    local id = idStr and tonumber(idStr)
    if not id or id == 0 then return end
    local db = GetDebuffDisplayDB()
    local currentName = db.categories[id]
    if not currentName then return end
    EnsureRenamePopupRegistered()
    StaticPopup_Show("KASTACD_RENAME_DEBUFF_CATEGORY", nil, nil, { categoryId = id, currentName = currentName })
end

-- GetSpellInfo(name) only resolves names the client has already cached
-- locally, which fails for pure side-effect debuffs nobody ever casts
-- (Forbearance, Weakened Soul, etc.). Curated fallback for common ones.
local COMMON_DEBUFF_IDS = {
    ["forbearance"]      = 25771,
    ["weakened soul"]    = 6788,
    ["sated"]            = 57724,
    ["exhaustion"]       = 57723,
    ["temporal displacement"] = 80354,
    ["weakened blows"]   = 115798,
}

-- Resolves a user-typed spell ID/name and adds it to the watch list.
-- Returns true, name on success or false, errorMessage on failure.
function AddDebuffDisplaySpell(input)
    input = strtrim and strtrim(tostring(input or "")) or tostring(input or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if input == "" then return false, "Enter a spell ID or name." end

    if not GetSpellInfo then return false, "Spell lookup unavailable." end
    -- Not "GetSpellInfo and GetSpellInfo(input)" - `and` would collapse
    -- the multi-return call down to just its first value.
    local name, _, _, _, _, _, spellId = GetSpellInfo(input)
    if not name or not spellId then
        local fallbackId = COMMON_DEBUFF_IDS[input:lower()]
        if fallbackId then
            name, _, _, _, _, _, spellId = GetSpellInfo(fallbackId)
        end
    end
    if not name or not spellId then
        return false, "No spell found for \"" .. input .. "\" - try the exact spell ID instead."
    end

    local db = GetDebuffDisplayDB()
    if db.list[spellId] then
        return false, name .. " is already in the list."
    end

    db.list[spellId] = {
        enabled    = true,
        glow       = true,
        showTimer  = true,
        iconSize   = 30,
        categoryId = 0,
        name       = name,
    }
    return true, name
end

function RemoveDebuffDisplaySpell(spellId)
    local db = GetDebuffDisplayDB()
    db.list[spellId] = nil
    if ddIcons then
        for _, unit in ipairs(GetDebuffDisplayUnits()) do
            HideDebuffDisplayIcon(unit, spellId)
            if ddIcons[unit] then ddIcons[unit][spellId] = nil end
        end
    end
end

-- Icon frames: one per (unit, spellId) pair, created lazily and reused.
ddIcons  = {}   -- [unit][spellId] = frame
local ddActive = {}   -- [unit][spellId] = { expirationTime, duration } - only while shown

local function MakeDebuffDisplayIcon(spellId, entry, parent)
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

local function GetOrMakeDebuffDisplayIcon(unit, spellId, entry)
    ddIcons[unit] = ddIcons[unit] or {}
    local f = ddIcons[unit][spellId]
    if not f then
        f = MakeDebuffDisplayIcon(spellId, entry, UIParent)
        ddIcons[unit][spellId] = f
    end
    return f
end

function HideDebuffDisplayIcon(unit, spellId)
    local f = ddIcons[unit] and ddIcons[unit][spellId]
    if f then
        if f.glowing then HideProcGlow(f); f.glowing = false end
        f:Hide()
    end
    if ddActive[unit] then ddActive[unit][spellId] = nil end
end

function HideAllDebuffDisplayIcons()
    for unit, spells in pairs(ddIcons) do
        for spellId in pairs(spells) do
            HideDebuffDisplayIcon(unit, spellId)
        end
    end
end

-- Scans one unit's HARMFUL auras only for the given spell. Matches by
-- name first when available. This client's UnitAura uses the older
-- signature with an extra "rank" return, shifting later values by one.
-- Returns expirationTime, duration, found.
local function ScanUnitDebuff(unit, spellId, watchName)
    for i = 1, 40 do
        local auraName, _, _, _, _, duration, expirationTime, _, _, _, sid = UnitAura(unit, i, "HARMFUL")
        if not auraName then break end
        if (watchName and auraName == watchName) or (not watchName and sid == spellId) then
            return expirationTime, duration, true
        end
    end
    return nil, nil, false
end

-- Arranges every currently-active icon for one unit in a row or column
-- anchored on that unit's frame - see KastaCD_BuffDisplay.lua's
-- LayoutUnitBuffIcons for the full rationale, identical logic here.
local ICON_GAP = 2
local function LayoutUnitDebuffIcons(mf, shown, offsetX, offsetY, growDirection)
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

-- Full re-scan of every watched spell against every tracked unit.
function RefreshDebuffDisplay()
    local db = GetDebuffDisplayDB()
    if not db.enabled or not next(db.list) or not HasGroup() then
        HideAllDebuffDisplayIcons()
        return
    end

    local forceShow = db.testMode
    local now = GetTime()

    local unitFrames = {}
    for _, pair in ipairs(FindUnitFrames()) do
        unitFrames[pair.unit] = pair.frame
    end

    for _, unit in ipairs(GetDebuffDisplayUnits()) do
        local mf = unitFrames[unit]
        ddActive[unit] = ddActive[unit] or {}
        if UnitExists(unit) and mf then
            local shown = {}
            for spellId, entry in pairs(db.list) do
                if entry.enabled ~= false then
                    local found, expirationTime, duration
                    if forceShow then
                        found, expirationTime, duration = true, now + 30, 30
                    else
                        expirationTime, duration, found = ScanUnitDebuff(unit, spellId, entry.name)
                    end
                    if found then
                        local f = GetOrMakeDebuffDisplayIcon(unit, spellId, entry)
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
                        ddActive[unit][spellId] = { expirationTime = expirationTime, duration = duration }
                        table.insert(shown, { spellId = spellId, entry = entry, f = f })
                    else
                        HideDebuffDisplayIcon(unit, spellId)
                    end
                else
                    HideDebuffDisplayIcon(unit, spellId)
                end
            end
            local isRaid = type(IsRaidUnit) == "function" and IsRaidUnit(unit)
            local offsetX = isRaid and db.raidOffsetX or db.offsetX
            local offsetY = isRaid and db.raidOffsetY or db.offsetY
            LayoutUnitDebuffIcons(mf, shown, offsetX, offsetY, db.growDirection)
        else
            for spellId in pairs(db.list) do
                HideDebuffDisplayIcon(unit, spellId)
            end
        end
    end
end

-- Timer text ticker (0.2s) - cosmetic, mirrors Buff Display's own.
C_Timer.NewTicker(0.2, function()
    local db = GetDebuffDisplayDB()
    if not db.enabled then return end
    local now = GetTime()
    for unit, spells in pairs(ddActive) do
        for spellId, info in pairs(spells) do
            local entry = db.list[spellId]
            local f = ddIcons[unit] and ddIcons[unit][spellId]
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

-- Self-heal ticker (1s) + UNIT_AURA, mirrors Buff Display's own.
C_Timer.NewTicker(1.0, function()
    if type(RefreshDebuffDisplay) == "function" then RefreshDebuffDisplay() end
end)

local ddWatcher = CreateFrame("Frame")
ddWatcher:RegisterEvent("UNIT_AURA")
ddWatcher:RegisterEvent("GROUP_ROSTER_UPDATE")
ddWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
ddWatcher:SetScript("OnEvent", function(_, event, arg1)
    if event == "UNIT_AURA" then
        local isWatched = false
        for _, u in ipairs(GetDebuffDisplayUnits()) do
            if u == arg1 then isWatched = true; break end
        end
        if not isWatched then return end
    end
    if type(RefreshDebuffDisplay) == "function" then RefreshDebuffDisplay() end
end)

-- /kcddebuffdebug - mirrors KastaCD_BuffDisplay.lua's /kcdbuffdebug.
SLASH_KASTACDDEBUFFDEBUG1 = "/kcddebuffdebug"
SlashCmdList["KASTACDDEBUFFDEBUG"] = function()
    local db = GetDebuffDisplayDB()
    print("|cff00ff00KastaCD Debuff Display Debug|r -- enabled=" .. tostring(db.enabled)
        .. " testMode=" .. tostring(db.testMode) .. " showInRaidGroups=" .. tostring(db.showInRaidGroups)
        .. " HasGroup=" .. tostring(HasGroup and HasGroup()))

    local n = 0
    for spellId, entry in pairs(db.list) do
        n = n + 1
        local name = (GetSpellInfo and GetSpellInfo(spellId)) or "?"
        local catName = (entry.categoryId ~= 0 and db.categories[entry.categoryId]) or "Uncategorized"
        print(("  [%d] %s enabled=%s category=%s"):format(spellId, name, tostring(entry.enabled), catName))
    end
    if n == 0 then print("  (no spells in the watch list)") end

    print("|cff00ff00KastaCD Debuff Display Debug|r -- FindUnitFrames() results:")
    local frames = FindUnitFrames and FindUnitFrames() or {}
    if #frames == 0 then
        print("  (none found - no unit-frame addon/Blizzard frame detected)")
    else
        for _, pair in ipairs(frames) do
            print(("  %s -> %s"):format(pair.unit, pair.frame and pair.frame:GetName() or "(unnamed frame)"))
        end
    end

    if n > 0 then
        print("|cff00ff00KastaCD Debuff Display Debug|r -- live debuff scan (matched by name):")
        for _, unit in ipairs(GetDebuffDisplayUnits()) do
            if UnitExists(unit) then
                for spellId, entry in pairs(db.list) do
                    local expirationTime, duration, found = ScanUnitDebuff(unit, spellId, entry.name)
                    print(("  %s: %s (watching name=\"%s\") -> %s (duration=%s, expirationTime=%s)"):format(
                        unit, tostring(entry.name or spellId), tostring(entry.name),
                        found and "ACTIVE" or "not present", tostring(duration), tostring(expirationTime)))
                end

                print(("  %s's full debuff list (compare names above against this):"):format(unit))
                for i = 1, 40 do
                    local auraName, _, _, _, _, duration, expirationTime, _, _, _, sid = UnitAura(unit, i, "HARMFUL")
                    if not auraName then break end
                    print(("    %s (spellId=%s, duration=%s, expirationTime=%s)"):format(
                        auraName, tostring(sid), tostring(duration), tostring(expirationTime)))
                end
            end
        end
    end
end
