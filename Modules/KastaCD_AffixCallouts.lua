-- KastaCD_AffixCallouts.lua - warns about time-critical Mythic+ affix
-- mechanics: Explosive orb spawns and the Quaking debuff. Detects by
-- matching in-game unit/aura NAME text rather than a numeric spell/NPC
-- ID, since no addon has a reusable ID table for these and names are
-- reliable while guessed IDs aren't.
-- Only active during a real Mythic Keystone run (difficulty 8 +
-- C_ChallengeMode.GetActiveChallengeMapID()).
-- Run /kcdaffixdebug to dump exactly what's currently detected.

function GetAffixCalloutDB()
    KastaCDDB = KastaCDDB or {}
    local db = KastaCDDB.affixCallouts
    if not db then
        db = {}
        KastaCDDB.affixCallouts = db
    end
    if db.enabled   == nil then db.enabled   = true end
    if db.explosive == nil then db.explosive = true end
    if db.quaking   == nil then db.quaking   = true end
    if db.sound     == nil then db.sound     = true end
    return db
end

local function IsInMythicPlus()
    local _, _, difficultyID = GetInstanceInfo()
    return difficultyID == 8 and C_ChallengeMode.GetActiveChallengeMapID() ~= nil
end

-- Big centered screen text, same mechanism boss-mod addons use for raid warnings.
local function BigWarning(msg)
    if RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
    end
    if GetAffixCalloutDB().sound and PlaySound then
        PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
    end
    print("|cffff4444KastaCD Affix:|r " .. msg)
end

-- Explosive: watches new nameplate units for the literal name "Explosive
-- Orb". Warns once per orb (tracked by GUID).
local warnedExplosiveGUIDs = {}

local function CheckExplosiveUnit(unitToken)
    if not GetAffixCalloutDB().explosive then return end
    if not UnitExists(unitToken) then return end

    local name = UnitName(unitToken)
    if name ~= "Explosive Orb" then return end

    local guid = UnitGUID(unitToken)
    if not guid or warnedExplosiveGUIDs[guid] then return end
    warnedExplosiveGUIDs[guid] = true

    BigWarning("Explosive Orb!")
end

-- Quaking: watches the player's own aura list for a debuff named
-- "Quaking", which deals split damage and interrupts casts.
local hasQuaking = false

local function CheckOwnQuaking()
    if not GetAffixCalloutDB().quaking then return end

    local found = false
    for i = 1, 40 do
        local name = UnitAura("player", i, "HARMFUL")
        if not name then break end
        if name == "Quaking" then
            found = true
            break
        end
    end

    if found and not hasQuaking then
        hasQuaking = true
        BigWarning("Quaking on YOU - move away from the group!")
    elseif not found then
        hasQuaking = false
    end
end

-- Events
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("NAME_PLATE_UNIT_ADDED")
watcher:RegisterEvent("UNIT_AURA")
watcher:RegisterEvent("CHALLENGE_MODE_START")
watcher:RegisterEvent("CHALLENGE_MODE_COMPLETED")
watcher:RegisterEvent("CHALLENGE_MODE_RESET")
watcher:SetScript("OnEvent", function(_, event, arg1)
    if not GetAffixCalloutDB().enabled or not IsInMythicPlus() then return end

    if event == "NAME_PLATE_UNIT_ADDED" then
        CheckExplosiveUnit(arg1)
    elseif event == "UNIT_AURA" and arg1 == "player" then
        CheckOwnQuaking()
    elseif event == "CHALLENGE_MODE_START" then
        wipe(warnedExplosiveGUIDs)
        hasQuaking = false
    end
end)

-- /kcdaffixdebug - dumps nearby nameplate names and player debuffs.
SLASH_KASTACDAFFIXDEBUG1 = "/kcdaffixdebug"
SlashCmdList["KASTACDAFFIXDEBUG"] = function()
    print("|cff00ff00KastaCD Affix Debug|r -- IsInMythicPlus: " .. tostring(IsInMythicPlus()))

    print("|cff00ff00KastaCD Affix Debug|r -- nearby nameplate unit names:")
    local found = false
    if C_NamePlate then
        for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
            local unit = plate.namePlateUnitToken
            if unit and UnitExists(unit) then
                found = true
                print(("  %s (guid=%s)"):format(tostring(UnitName(unit)), tostring(UnitGUID(unit))))
            end
        end
    end
    if not found then print("  (no nameplates visible)") end

    print("|cff00ff00KastaCD Affix Debug|r -- player debuffs:")
    found = false
    for i = 1, 40 do
        local name, _, count, _, duration, expirationTime = UnitAura("player", i, "HARMFUL")
        if not name then break end
        found = true
        print(("  %s (stacks=%s, duration=%s, remaining=%.1fs)"):format(
            name, tostring(count), tostring(duration),
            expirationTime and (expirationTime - GetTime()) or -1))
    end
    if not found then print("  (no debuffs)") end
end
