-- =============================================================
-- KastaCD_CombatLog.lua
-- Handles COMBAT_LOG_EVENT_UNFILTERED.
-- Responsibilities:
--   1. Cache spell sightings into KNOWN_UNIT_SPELLS (secondary
--      availability signal used by IsSpellKnownForUnit in DB.lua).
--   2. Trigger uptime / cooldown phase transitions on tracked icons
--      when an enabled spell is cast by a group member.
-- Depends on: KastaCD_SpellDB.lua, KastaCD_DB.lua, KastaCD_Tracking.lua
-- =============================================================

function HandleCombatLog(...)
    -- Private servers (TrinityCore/AzerothCore 7.3.5) are inconsistent:
    -- some pass combat log fields as direct event args (old pre-Legion style),
    -- others implement CombatLogGetCurrentEventInfo(). Try the API first;
    -- if it returns nothing fall back to the varargs passed in.
    local timestamp, subEvent, hideCaster,
        sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
        destGUID, destName, destFlags, destRaidFlags,
        spellId, spellName, spellSchool

    if CombatLogGetCurrentEventInfo then
        timestamp, subEvent, hideCaster,
            sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
            destGUID, destName, destFlags, destRaidFlags,
            spellId, spellName, spellSchool = CombatLogGetCurrentEventInfo()
    end

    -- Fallback: pserver passed args directly via the event
    if not subEvent then
        timestamp, subEvent, hideCaster,
            sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
            destGUID, destName, destFlags, destRaidFlags,
            spellId, spellName, spellSchool = ...
    end

    -- We only care about successful casts
    if subEvent ~= "SPELL_CAST_SUCCESS" then return end
    if not spellId or not SPELL_DB[spellId] then return end

    -- ── 1. Cache sighting ──────────────────────────────────────
    -- Even if this spell isn't enabled we still record the sighting
    -- so IsSpellKnownForUnit can show the icon once the user enables it.
    if sourceGUID then
        KNOWN_UNIT_SPELLS[sourceGUID] = KNOWN_UNIT_SPELLS[sourceGUID] or {}
        KNOWN_UNIT_SPELLS[sourceGUID][spellId] = true

        -- Spec inference: GetInspectSpecialization/NotifyInspect is unreliable
        -- on many private servers and can leave UNIT_SPEC_CACHE permanently nil,
        -- which made SpellMatchesSpec's "spec unknown" fallback show every spec's
        -- abilities at once. A spell restricted to exactly one spec is ground
        -- truth the moment it's cast - use it to set/correct the spec cache
        -- directly, independent of whether inspect ever resolves.
        local castData = SPELL_DB[spellId]
        if castData.specs and #castData.specs == 1 then
            UNIT_SPEC_CACHE[sourceGUID] = castData.specs[1]
            -- GetUnitSpec("player") reads UNIT_SPEC_CACHE["player"] specifically
            -- (see KastaCD_DB.lua), not the player's real GUID key. Without this,
            -- the player's own cast of a spec-exclusive spell never resolved
            -- their own spec - only PollUnitSpec's GetSpecialization() call did,
            -- which is the one path with no combat-log fallback if it's broken.
            if sourceGUID == UnitGUID("player") then
                UNIT_SPEC_CACHE["player"] = castData.specs[1]
            end
        end
    end

    -- ── 2. Bail early if spell is not tracked ──────────────────
    if not KastaCDDB.enabled[spellId] then return end

    -- ── 3. Resolve GUID → unit token ──────────────────────────
    local unit = nil
    for u, g in pairs(memberGUIDs) do
        if g == sourceGUID then unit = u; break end
    end
    if not unit then return end

    -- ── 4. Ensure an icon state exists ────────────────────────
    -- The spell may be a talent ability seen for the first time.
    -- RebuildIcons will create the frame; we then re-look-up the state.
    local state = trackerState[unit] and trackerState[unit][spellId]
    if not state then
        RebuildIcons()
        state = trackerState[unit] and trackerState[unit][spellId]
        if not state then return end
    end

    -- ── 5. Drive phase transition ──────────────────────────────
    local data = SPELL_DB[spellId]
    local f    = state.frame
    local now  = GetTime()

    if data.duration and data.duration > 0 then
        -- Spell has an active uptime window
        state.phase   = "uptime"
        state.endTime = now + data.duration
        ShowProcGlow(f)
        f.bar:Show()
        f.bar:SetWidth(f:GetWidth())
        f.desat:Hide()
        f.cdText:SetText(data.duration >= 60
            and string.format("%dm", math.ceil(data.duration / 60))
            or  string.format("%d",  math.ceil(data.duration)))

    elseif data.cooldown and data.cooldown > 0 then
        -- Instant effect — go straight to cooldown
        state.phase   = "cooldown"
        state.endTime = now + data.cooldown
        HideProcGlow(f)
        f.bar:Hide()
        f.desat:Show()
        f.cdText:SetText(data.cooldown >= 60
            and string.format("%dm", math.ceil(data.cooldown / 60))
            or  string.format("%d",  math.ceil(data.cooldown)))
    end
end