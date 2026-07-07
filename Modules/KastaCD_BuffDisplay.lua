-- =============================================================
-- KastaCD_BuffDisplay.lua
-- User-defined buff/debuff watch list. Unlike the main party-cooldown
-- tracker (which is driven by a curated SPELL_DB and shows a bar the
-- moment a known ability is CAST), this tracks real aura PRESENCE via
-- UnitAura - a buff like Ironbark can land on any party member from
-- any source, not just from a self-cast, so casting is the wrong signal
-- to key off of here. Each watched spell shows its own icon centered on
-- whichever party member currently carries that aura, anchored directly
-- to their real unit frame (FindUnitFrames(), from KastaCD_Tracking.lua
-- - works with ElvUI/VuhDo/CompactRaidFrame/vanilla alike).
-- Depends on: KastaCD_DB.lua, KastaCD_Tracking.lua (FindUnitFrames,
-- ShowProcGlow/HideProcGlow, HasGroup, IsRaidUnit)
-- =============================================================

local PARTY_UNITS = { "player", "party1", "party2", "party3", "party4" }

-- Party by default; raid1-N instead while genuinely in a raid AND the
-- user has opted in via this feature's OWN "Show in Raid Groups" toggle
-- - deliberately a separate field from the main tracker's
-- KastaCDDB.showInRaidGroups (independent, per explicit request), so
-- turning one on doesn't silently affect the other.
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

-- Best-effort class lookup for a spellId, purely for the options UI's
-- class tabs - arbitrary user-added spells have no inherent class
-- metadata, so this borrows it from SPELL_DB/CC_SPELLS when the spellId
-- happens to already exist in one of those (common case: most
-- interesting party buffs are already class cooldowns tracked elsewhere
-- in this addon). Falls back to "OTHER" when neither has it - still
-- watchable, just sorts into its own bucket in the UI. Defined ABOVE
-- GetBuffDisplayDB (which calls it on every access to keep entries'
-- .class self-healing - see the backfill loop below) since this is a
-- local function and Lua locals are only visible to code written after
-- their declaration in the same file.

-- Small curated fallback for well-known external buffs that aren't
-- tracked anywhere else in this addon (SPELL_DB only covers cooldown-
-- tracker spells, CC_SPELLS only covers crowd control) - without this,
-- watching something like Ironbark would always land in the generic
-- "Other" bucket even though it's obviously a Druid spell. Not
-- exhaustive, just the common externals someone would realistically add.
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
    -- Test Mode: force every enabled watched spell to show on every found
    -- party frame with a fake timer, regardless of whether the aura is
    -- actually present - lets the user confirm icon position/size/glow
    -- work at all without needing to reproduce the real buff first.
    if db.testMode == nil then db.testMode = false end
    -- Global position offset - ONE shared Offset X/Y for every watched
    -- spell's icon (not per-spell). Party and raid get independent
    -- values, same split as the main tracker's own offsetX/offsetY vs
    -- raidOffsetX/raidOffsetY (see GetIconSettingsFor in
    -- KastaCD_Tracking.lua) - a raid's frames are usually laid out very
    -- differently from a 5-man party's.
    if db.offsetX == nil then db.offsetX = 0 end
    if db.offsetY == nil then db.offsetY = 0 end
    if db.raidOffsetX == nil then db.raidOffsetX = 0 end
    if db.raidOffsetY == nil then db.raidOffsetY = 0 end
    if db.showInRaidGroups == nil then db.showInRaidGroups = false end
    -- Which way the row/column of icons grows when 2+ watched spells are
    -- active on the same unit at once (see LayoutUnitBuffIcons) -
    -- CENTER/LEFT/RIGHT lay out a horizontal row, UP/DOWN a vertical
    -- column. CENTER (grows symmetrically outward, the original/default
    -- behavior) unless the user picks something else.
    if db.growDirection == nil then db.growDirection = "CENTER" end
    -- Global, same as the main tracker's own "Icon Borders" toggle
    -- (KastaCDDB.showIconBorders / ApplyIconBorders in KastaCD_Tracking.lua)
    -- - crops the icon texture's edge art in vs out for every watched
    -- spell's icon, not per-spell.
    if db.showIconBorders == nil then db.showIconBorders = false end
    -- Backfill entries added before aura-matching switched to name-based
    -- (see ScanUnitAura) - a no-op once every entry has a name, so this
    -- stays cheap on every call after the first. Class, unlike name, is
    -- ALWAYS re-resolved (not just backfilled when missing) - this
    -- self-heals a spell that landed in "Other" before SPELL_DB/
    -- CC_SPELLS/COMMON_BUFF_CLASS gained coverage for it, without
    -- needing to remove and re-add it.
    for spellId, entry in pairs(db.list) do
        if not entry.name and GetSpellInfo then
            entry.name = GetSpellInfo(spellId)
        end
        entry.class = GuessSpellClass(spellId)
    end
    return db
end

-- Resolves a user-typed spell ID or exact spell name to a real spellId,
-- and adds it to the watch list with sensible defaults. Returns
-- true, name on success or false, errorMessage on failure - callers
-- (the options UI) show errorMessage back to the user rather than
-- silently no-op'ing on a bad entry.
function AddBuffDisplaySpell(input)
    input = strtrim and strtrim(tostring(input or "")) or tostring(input or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if input == "" then return false, "Enter a spell ID or name." end

    if not GetSpellInfo then return false, "Spell lookup unavailable." end
    -- Deliberately NOT "GetSpellInfo and GetSpellInfo(input)" here - the
    -- `and` short-circuit idiom collapses a multi-return call down to
    -- just its first value, which would silently leave spellId (the 7th
    -- return) nil on every single call. Guarded above instead so this
    -- call keeps its full return list.
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
        -- Kept alongside spellId specifically for aura matching (see
        -- ScanUnitAura below) - this server can report a different
        -- spellId on the live UnitAura than GetSpellInfo resolves for the
        -- same buff by name (same reason KastaCD_AffixCallouts.lua's
        -- Quaking watcher matches by name, not ID).
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

-- -------------------------------------------------------------
-- Icon frames  –  one per (unit, spellId) pair, created lazily and
-- reused for the lifetime of the session (cheap to keep around, just
-- Hide()/Show()'d as auras come and go).
-- -------------------------------------------------------------
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

-- Scans one unit's full aura list (both HELPFUL and HARMFUL - a watched
-- entry could just as easily be a debuff someone wants to keep an eye
-- on, not only a friendly buff) for the given spell. Matches by NAME
-- first when available - this server can report a different spellId on
-- the live UnitAura than GetSpellInfo resolved when the entry was added.
--
-- This client's UnitAura returns the OLDER (pre-Legion-trim) signature:
-- name, rank, icon, count, debuffType, duration, expirationTime, caster,
-- isStealable, shouldConsolidate, spellId - confirmed via /kcdbuffdebug,
-- which showed duration=nil (that slot is actually debuffType, nil for
-- buffs) and spellId=false (that slot is actually the shouldConsolidate
-- boolean) on every aura. The extra "rank" return shifts every following
-- value up by one compared to the modern 10-value signature this used to
-- assume.
--
-- Returns expirationTime, duration, found - found is true whenever a
-- matching aura was located, even if expirationTime/duration came back
-- as 0 (some auras, e.g. Devotion Aura, are genuinely permanent/no-
-- duration - see the fallback-duration handling in RefreshBuffDisplay).
-- Distinct from expirationTime itself so callers can tell "found, but no
-- real timer data" apart from "not present at all".
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

-- Arranges every currently-active icon for one unit in a row or column
-- anchored on that unit's frame, instead of every icon sitting dead-center
-- on top of each other (which is what happens if 2+ watched spells are up
-- on the same person at once, since they'd otherwise all target the exact
-- same CENTER point). Sorted by spellId for a stable, consistent order
-- across refreshes. offsetX/offsetY is the ONE shared position (party or
-- raid, picked by the caller) applied on top of every icon's slot - not
-- per-spell, so the whole group moves together.
--
-- growDirection (GetBuffDisplayDB().growDirection):
--   CENTER (default) - horizontal row, grows outward both ways from center
--   LEFT / RIGHT      - horizontal row, grows only in that direction
--   UP / DOWN         - vertical column, grows only in that direction
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

    -- CENTER starts the row half its total width to the left so it ends
    -- up straddling the anchor evenly; LEFT starts a full width to the
    -- left so the row's right edge lands ON the anchor (extends further
    -- left as more icons show up); RIGHT starts at 0 so the row's left
    -- edge sits on the anchor instead.
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

-- -------------------------------------------------------------
-- RefreshBuffDisplay  –  full re-scan of every watched spell against
-- every tracked unit (party, or raid1-N while Show in Raid Groups is on
-- and you're actually raided - see GetBuffDisplayUnits above). Cheap
-- enough to call from the self-heal ticker AND straight off UNIT_AURA
-- (mirrors the existing SpecPollTicker/RebuildIcons self-heal philosophy
-- elsewhere in this addon: correctness through frequent, near-free
-- re-evaluation rather than trying to track every possible add/remove/
-- frame-recycle edge case by hand).
-- -------------------------------------------------------------
function RefreshBuffDisplay()
    local db = GetBuffDisplayDB()
    if not db.enabled or not next(db.list) or not HasGroup() then
        HideAllBuffDisplayIcons()
        return
    end

    -- Test Mode forces every enabled entry to show on every found frame
    -- with a fake 30s timer, so the user can confirm position/size/glow
    -- without needing the real aura up.
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

-- -------------------------------------------------------------
-- Timer text ticker (0.2s) - purely cosmetic countdown text on top of
-- whatever RefreshBuffDisplay already decided is shown/hidden; doesn't
-- touch FindUnitFrames or aura scanning, so it's cheap to run often.
-- -------------------------------------------------------------
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

-- -------------------------------------------------------------
-- Self-heal ticker (1s, same cadence/philosophy as SpecPollTicker in
-- KastaCD_Events.lua) - catches group roster changes, unit-frame
-- addon reloads, and newly-added watch-list entries without needing a
-- dedicated event for every one of those cases.
-- -------------------------------------------------------------
C_Timer.NewTicker(1.0, function()
    if type(RefreshBuffDisplay) == "function" then RefreshBuffDisplay() end
end)

-- -------------------------------------------------------------
-- UNIT_AURA - immediate refresh the instant a watched unit's aura list
-- actually changes, instead of waiting up to 1s for the self-heal
-- ticker above to catch it.
-- -------------------------------------------------------------
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

-- =============================================================
-- /kcdbuffdebug - dumps live state so a "not showing" report can be
-- diagnosed from chat output instead of guessing blind: whether the
-- feature/entries are enabled, what FindUnitFrames() sees right now,
-- and (for each watched spell) which units actually have the aura per
-- a fresh UnitAura scan.
-- =============================================================
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
