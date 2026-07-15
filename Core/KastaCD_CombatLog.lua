-- KastaCD_CombatLog.lua - handles COMBAT_LOG_EVENT_UNFILTERED: caches
-- spell sightings into KNOWN_UNIT_SPELLS and drives uptime/cooldown
-- phase transitions on tracked icons.
-- Depends on: KastaCD_SpellDB.lua, KastaCD_DB.lua, KastaCD_Tracking.lua

-- [guid] = { name, notInterruptible } of the unit's last cast/channel.
local castInterruptCache = {}

function TrackCastInterruptible(unit)
    local guid = unit and UnitGUID(unit)
    if not guid then return end
    local name, notInterruptible
    if UnitCastingInfo then
        name, _, _, _, _, _, notInterruptible = UnitCastingInfo(unit)
    end
    if not name and UnitChannelInfo then
        name, _, _, _, _, _, _, notInterruptible = UnitChannelInfo(unit)
    end
    if not name then return end
    castInterruptCache[guid] = { name = name, notInterruptible = notInterruptible }
end

local function ReduceTrackerCooldown(unit, spellId, seconds)
    local state = trackerState[unit] and trackerState[unit][spellId]
    if not state then return end
    local now = GetTime()
    if state.phase == "uptime" and state.cdEndTime then
        state.cdEndTime = math.max(now, state.cdEndTime - seconds)
    elseif state.phase == "cooldown" and state.endTime then
        state.endTime = math.max(now, state.endTime - seconds)
    end
end

local ODYNS_CHAMPION_BUFF_NAME = "Champion of the Valarjar"
local RAMPAGE_SPELL_ID         = 184367
local RECKLESSNESS_SPELL_ID    = 1719
local ODYNS_CHAMPION_REDUCTION = 1

local SOLAR_BEAM_SPELL_ID       = 78675
local LIGHT_OF_THE_SUN_SPELL_ID = 202918
local LIGHT_OF_THE_SUN_REDUCTION = 15

-- Face Palm: Tiger Palm has a chance to shave time off Fortifying Brew.
-- The proc chance itself isn't visible in the combat log, so this applies
-- on every Tiger Palm cast (an approximation, not a per-proc trigger).
local FORTIFYING_BREW_SPELL_ID = 115203
local TIGER_PALM_SPELL_ID      = 100780
local FACE_PALM_SPELL_ID       = 213116
local FACE_PALM_REDUCTION      = 1

-- Blackout Combo: Keg Smash reduces Fortifying Brew's cooldown further.
local KEG_SMASH_SPELL_ID          = 121253
local BLACKOUT_COMBO_SPELL_ID     = 22104
local BLACKOUT_COMBO_REDUCTION    = 2

local hasOdynsChampion = false

local function RefreshOdynsChampionBuff()
    for i = 1, 40 do
        local name = UnitAura("player", i, "HELPFUL")
        if not name then break end
        if name == ODYNS_CHAMPION_BUFF_NAME then
            hasOdynsChampion = true
            return
        end
    end
    hasOdynsChampion = false
end

local odynWatcher = CreateFrame("Frame")
odynWatcher:RegisterEvent("UNIT_AURA")
odynWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
odynWatcher:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" and unit ~= "player" then return end
    RefreshOdynsChampionBuff()
end)

SLASH_KASTACDODYNDEBUG1 = "/kcdodyndebug"
SlashCmdList["KASTACDODYNDEBUG"] = function()
    print("|cff00ff00KastaCD Odyn's Champion Debug|r -- hasOdynsChampion=" .. tostring(hasOdynsChampion))
end

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
    -- not the interrupt ability. Player's own interrupts only. Skipped
    -- when castInterruptCache confirms that cast wasn't interruptible.
    if subEvent == "SPELL_INTERRUPT" and sourceGUID == UnitGUID("player") then
        local cached = destGUID and castInterruptCache[destGUID]
        local blocked = cached and cached.notInterruptible and cached.name == extraSpellName
        if not blocked and type(AnnounceInterrupt) == "function" then
            AnnounceInterrupt(spellName, extraSpellName, destName, extraSpellId, spellId)
        end

        -- Light of the Sun: Solar Beam interrupt refunds its own cooldown.
        if spellId == SOLAR_BEAM_SPELL_ID and IsPlayerSpell and IsPlayerSpell(LIGHT_OF_THE_SUN_SPELL_ID) then
            ReduceTrackerCooldown("player", SOLAR_BEAM_SPELL_ID, LIGHT_OF_THE_SUN_REDUCTION)
            if type(ReduceInterruptCooldown) == "function" then
                ReduceInterruptCooldown("player", SOLAR_BEAM_SPELL_ID, LIGHT_OF_THE_SUN_REDUCTION)
            end
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
        -- whatever the target is currently casting/channeling. Only
        -- announces if that cast is actually interruptible.
        if INT_SPELLS[spellId].isRacial and sourceGUID == UnitGUID("player")
        and type(AnnounceInterrupt) == "function" then
            local castName, castSpellId, notInterruptible
            if UnitCastingInfo then
                castName, _, _, _, _, _, notInterruptible, castSpellId = UnitCastingInfo("target")
            end
            if not castName and UnitChannelInfo then
                castName, _, _, _, _, _, _, notInterruptible, castSpellId = UnitChannelInfo("target")
            end
            if castName and not notInterruptible then
                AnnounceInterrupt(spellName, castName, UnitName("target"), castSpellId, spellId)
            end
        end
    end

    -- Cross-spell cooldown reduction (e.g. Smite -> Chastise)
    if subEvent == "SPELL_CAST_SUCCESS" and spellId and sourceGUID and type(HandleCCCooldownReducer) == "function" then
        HandleCCCooldownReducer(sourceGUID, spellId)
    end

    -- Odyn's Champion: Rampage cast while buffed shaves 1s off Recklessness.
    if subEvent == "SPELL_CAST_SUCCESS" and spellId == RAMPAGE_SPELL_ID
    and sourceGUID == UnitGUID("player") and hasOdynsChampion then
        ReduceTrackerCooldown("player", RECKLESSNESS_SPELL_ID, ODYNS_CHAMPION_REDUCTION)
    end

    -- Face Palm: Tiger Palm shaves time off Fortifying Brew.
    if subEvent == "SPELL_CAST_SUCCESS" and spellId == TIGER_PALM_SPELL_ID
    and sourceGUID == UnitGUID("player") and IsPlayerSpell and IsPlayerSpell(FACE_PALM_SPELL_ID) then
        ReduceTrackerCooldown("player", FORTIFYING_BREW_SPELL_ID, FACE_PALM_REDUCTION)
    end

    -- Blackout Combo: Keg Smash reduces Fortifying Brew's cooldown further.
    if subEvent == "SPELL_CAST_SUCCESS" and spellId == KEG_SMASH_SPELL_ID
    and sourceGUID == UnitGUID("player") and IsPlayerSpell and IsPlayerSpell(BLACKOUT_COMBO_SPELL_ID) then
        ReduceTrackerCooldown("player", FORTIFYING_BREW_SPELL_ID, BLACKOUT_COMBO_REDUCTION)
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