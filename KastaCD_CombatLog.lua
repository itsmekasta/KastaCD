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

    -- ── Interrupt announcement ─────────────────────────────────
    -- SPELL_INTERRUPT is a distinct sub-event from SPELL_CAST_SUCCESS -
    -- extraSpellName is the *interrupted* spell (what the enemy was
    -- casting), not the interrupt ability itself. Only announces the
    -- player's own interrupts, never party members' - this is a "let
    -- others know KastaCD is doing this" broadcast, not a tracker.
    -- Passes both spell IDs along too (extraSpellId for the interrupted
    -- spell, spellId for the interrupt ability itself) so the chat
    -- message can link them as real, clickable spell links instead of
    -- plain text - see AnnounceInterrupt in KastaCD_Announce.lua.
    if subEvent == "SPELL_INTERRUPT" and sourceGUID == UnitGUID("player") then
        if type(AnnounceInterrupt) == "function" then
            AnnounceInterrupt(spellName, extraSpellName, destName, extraSpellId, spellId)
        end
    end

    -- ── Interrupt tracker hook ─────────────────────────────────
    -- Check interrupt spells regardless of SPELL_DB membership so
    -- Priest/Warlock interrupts not in the main DB are still tracked.
    if subEvent == "SPELL_CAST_SUCCESS" and spellId and INT_SPELLS and INT_SPELLS[spellId] then
        if sourceGUID and type(HandleInterruptCast) == "function" then
            HandleInterruptCast(sourceGUID, spellId)
        end

        -- ── Interrupt announcement fallback (racials, e.g. Arcane
        -- Torrent) ───────────────────────────────────────────────
        -- Confirmed on this server: SPELL_INTERRUPT doesn't reliably fire
        -- for the Arcane Torrent racial the way it does for real class
        -- interrupts (the primary hook above handles those), so this
        -- falls back to SPELL_CAST_SUCCESS for exactly the isRacial
        -- entries in INT_SPELLS - the same detection path the Interrupt
        -- Tracker already uses successfully for this ability. There's no
        -- single-target SPELL_INTERRUPT payload to read the interrupted
        -- spell's name from here, so it's approximated from whatever the
        -- player's current target is casting/channeling at that instant;
        -- if nothing is found, the announcement is skipped rather than
        -- claiming an interrupt that can't be confirmed.
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

    -- ── Crowd-control tracker hook ─────────────────────────────
    -- Same rationale as the interrupt hook above: checked regardless of
    -- SPELL_DB membership so CC spells not tracked by the main icon
    -- system still drive the crowd-control bars.
    if subEvent == "SPELL_CAST_SUCCESS" and spellId and CC_SPELLS and CC_SPELLS[spellId] then
        if sourceGUID and type(HandleCCCast) == "function" then
            HandleCCCast(sourceGUID, spellId)
        end
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

    -- Charge tracking: consume one charge and record when it will recharge.
    -- The uptime/cooldown logic below proceeds normally; the ticker decides
    -- whether to enter cooldown phase based on state.charges after uptime.
    if state.maxCharges and state.maxCharges > 1 then
        state.charges = math.max(0, state.charges - 1)
        table.insert(state.rechargeEndTimes, now + (data.cooldown or 0))
        f.chargesText:SetText(tostring(state.charges))
    end

    if data.duration and data.duration > 0 then
        -- Spell has an active uptime window. Don't call ShowProcGlow
        -- directly here - the 0.1s ticker in KastaCD_Tracking.lua is the
        -- sole owner of triggering it, via its own f.glowing guard
        -- (ActionButton_ShowOverlayGlow restarts its flipbook animation
        -- on every call, so any second trigger while already glowing
        -- reads as a visible flash/reset). Calling it here too raced
        -- against that guard - it fired once directly, then again ~0.1s
        -- later since this call never set f.glowing, and for multi-charge
        -- spells like Survival Instincts, recasting the second charge
        -- while the first's uptime was still active fired it yet again.
        -- Just reset glowing=false and let the ticker pick it up cleanly,
        -- same as the rebuild-restore path already does.
        state.phase   = "uptime"
        state.endTime = now + data.duration
        -- Cooldown starts at the moment of casting, not when uptime ends -
        -- the "duration" window overlaps the front of the cooldown, it
        -- doesn't happen before it (e.g. Shield Wall's 240s cooldown
        -- starts the instant you cast it, even though the shield itself
        -- is only up for 8s of that). Precomputed here from `now` so the
        -- ticker's uptime->cooldown transition can use this real end time
        -- instead of restarting a fresh `data.cooldown`-length timer once
        -- uptime finishes, which silently added the duration on top of the
        -- cooldown and made the displayed timer run long/desync from the
        -- real spell cooldown.
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