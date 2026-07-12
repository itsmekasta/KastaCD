-- KastaCD_CombatLog.lua - handles COMBAT_LOG_EVENT_UNFILTERED: caches
-- spell sightings into KNOWN_UNIT_SPELLS and drives uptime/cooldown
-- phase transitions on tracked icons.
-- Depends on: KastaCD_SpellDB.lua, KastaCD_DB.lua, KastaCD_Tracking.lua

function HandleCombatLog(...)
    -- Some private servers pass fields as direct event args instead of
    -- via CombatLogGetCurrentEventInfo(). Try the API first, fall back.
    local timestamp, subEvent, hideCaster,
        sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
        destGUID, destName, destFlags, destRaidFlags,
        spellId, spellName, spellSchool,
        extraSpellId, extraSpellName, extraSchool

    if CombatLogGetCurrentEventInfo then
        timestamp, subEvent, hideCaster,
            sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
            destGUID, destName, destFlags, destRaidFlags,
            spellId, spellName, spellSchool,
            extraSpellId, extraSpellName, extraSchool = CombatLogGetCurrentEventInfo()
    end

    -- Fallback: pserver passed args directly via the event
    if not subEvent then
        timestamp, subEvent, hideCaster,
            sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
            destGUID, destName, destFlags, destRaidFlags,
            spellId, spellName, spellSchool,
            extraSpellId, extraSpellName, extraSchool = ...
    end

    -- Interrupt announcement - extraSpellName is the interrupted spell,
    -- not the interrupt ability. Player's own interrupts only.
    if subEvent == "SPELL_INTERRUPT" and sourceGUID == UnitGUID("player") then
        if type(AnnounceInterrupt) == "function" then
            AnnounceInterrupt(spellName, extraSpellName, destName, extraSpellId, spellId)
        end
    end

    -- Interrupt tracker hook - checked regardless of SPELL_DB membership
    -- so Priest/Warlock interrupts not in the main DB are still tracked.
    if subEvent == "SPELL_CAST_SUCCESS" and spellId and INT_SPELLS and INT_SPELLS[spellId] then
        if sourceGUID and type(HandleInterruptCast) == "function" then
            HandleInterruptCast(sourceGUID, spellId)
        end

        -- Racial fallback (Arcane Torrent): SPELL_INTERRUPT doesn't
        -- reliably fire for it, so approximate the interrupted spell from
        -- whatever the target is currently casting/channeling.
        if INT_SPELLS[spellId].isRacial and sourceGUID == UnitGUID("player")
        and type(AnnounceInterrupt) == "function" then
            local castName, castSpellId
            if UnitCastingInfo then
                castName, _, _, _, _, _, _, _, castSpellId = UnitCastingInfo("target")
            end
            if not castName and UnitChannelInfo then
                castName, _, _, _, _, _, _, _, castSpellId = UnitChannelInfo("target")
            end
            if castName then
                AnnounceInterrupt(spellName, castName, UnitName("target"), castSpellId, spellId)
            end
        end
    end

    -- Crowd-control tracker hook - same rationale as above, checked
    -- regardless of SPELL_DB membership.
    if subEvent == "SPELL_CAST_SUCCESS" and spellId and CC_SPELLS and CC_SPELLS[spellId] then
        if sourceGUID and type(HandleCCCast) == "function" then
            HandleCCCast(sourceGUID, spellId)
        end

        -- Cache the sighting and infer spec from a single-spec-restricted cast.
        if sourceGUID then
            KNOWN_UNIT_SPELLS[sourceGUID] = KNOWN_UNIT_SPELLS[sourceGUID] or {}
            KNOWN_UNIT_SPELLS[sourceGUID][spellId] = true

            -- A real cast is the strongest confirmation - clear any
            -- competing pick in the same mutually-exclusive talent row.
            if type(ClearCompetingCCTalents) == "function" then
                ClearCompetingCCTalents(sourceGUID, spellId)
            end

            local ccData = CC_SPELLS[spellId]
            if ccData.specs and #ccData.specs == 1 then
                UNIT_SPEC_CACHE[sourceGUID] = ccData.specs[1]
                if sourceGUID == UnitGUID("player") then
                    UNIT_SPEC_CACHE["player"] = ccData.specs[1]
                end
            end
        end
    end

    -- We only care about successful casts
    if subEvent ~= "SPELL_CAST_SUCCESS" then return end
    if not spellId or not SPELL_DB[spellId] then return end

    -- 1. Cache sighting, even if not enabled, so IsSpellKnownForUnit can
    -- show the icon once the user enables it.
    if sourceGUID then
        KNOWN_UNIT_SPELLS[sourceGUID] = KNOWN_UNIT_SPELLS[sourceGUID] or {}
        KNOWN_UNIT_SPELLS[sourceGUID][spellId] = true

        -- Spec inference: inspect is unreliable on many private servers,
        -- so a single-spec-restricted cast sets/corrects the spec cache directly.
        local castData = SPELL_DB[spellId]
        if castData.specs and #castData.specs == 1 then
            UNIT_SPEC_CACHE[sourceGUID] = castData.specs[1]
            -- GetUnitSpec("player") reads UNIT_SPEC_CACHE["player"], not
            -- the player's real GUID key.
            if sourceGUID == UnitGUID("player") then
                UNIT_SPEC_CACHE["player"] = castData.specs[1]
            end
        end
    end

    -- 2. Bail early if spell is not tracked.
    if not KastaCDDB.enabled[spellId] then return end

    -- 3. Resolve GUID -> unit token.
    local unit = nil
    for u, g in pairs(memberGUIDs) do
        if g == sourceGUID then unit = u; break end
    end
    if not unit then return end

    -- 4. Ensure an icon state exists (first sighting of a talent ability).
    local state = trackerState[unit] and trackerState[unit][spellId]
    if not state then
        RebuildIcons()
        state = trackerState[unit] and trackerState[unit][spellId]
        if not state then return end
    end

    -- 5. Drive phase transition.
    local data = SPELL_DB[spellId]
    local f    = state.frame
    local now  = GetTime()

    -- Charge tracking: consume one charge, record recharge time.
    if state.maxCharges and state.maxCharges > 1 then
        state.charges = math.max(0, state.charges - 1)
        table.insert(state.rechargeEndTimes, now + (data.cooldown or 0))
        f.chargesText:SetText(tostring(state.charges))
    end

    if state.phase == "uptime" and not state.maxCharges then
        -- Ignore a duplicate SPELL_CAST_SUCCESS while already mid-uptime
        -- (e.g. Ravager logs a fresh CAST_SUCCESS per ground-effect tick,
        -- not just the initial throw, which re-armed endTime each time).
        -- Multi-charge spells are excluded - a second-charge recast is real.
        return
    end

    if data.duration and data.duration > 0 then
        -- Don't call ShowProcGlow here - the 0.1s ticker in
        -- KastaCD_Tracking.lua is the sole owner of triggering it via its
        -- own f.glowing guard, to avoid a double-fire/flash. Just reset
        -- glowing=false and let the ticker pick it up.
        state.phase   = "uptime"
        state.endTime = now + data.duration
        -- Cooldown starts at cast time, not when uptime ends - duration
        -- overlaps the front of the cooldown rather than preceding it.
        state.cdEndTime = now + (data.cooldown or 0)
        f.glowing = false
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
        f.glowing = false
        f.bar:Hide()
        f.desat:Show()
        f.cdText:SetText(data.cooldown >= 60
            and string.format("%dm", math.ceil(data.cooldown / 60))
            or  string.format("%d",  math.ceil(data.cooldown)))
    end
end