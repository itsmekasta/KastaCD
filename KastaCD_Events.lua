-- =============================================================
-- KastaCD_Events.lua
-- Event frame: registers all WoW events KastaCD cares about,
-- routes them to the correct handler, and registers the /kcd
-- slash command.
-- Depends on: everything else (loaded last).
-- =============================================================

local kcdEvent = CreateFrame("Frame")

-- =============================================================
-- Version-check over the add-on comm channel (BigWigs-style).
-- Every client broadcasts its own version to party/raid/guild;
-- when we hear a HIGHER version than ours, we tell the player
-- once. WoW add-ons cannot contact GitHub directly, so this
-- peer-to-peer gossip is how updates get advertised in-game.
-- =============================================================
local COMM_PREFIX = "KastaCD"
local notifiedNewVersion = false

C_ChatInfo.RegisterAddonMessagePrefix(COMM_PREFIX)

-- "1.2" / "1.10.3" -> { 1, 2 } / { 1, 10, 3 } so we compare
-- numbers, not text ("1.9" < "1.10" is false as a string!).
local function ParseVersion(str)
    local parts = {}
    for n in tostring(str):gmatch("%d+") do
        parts[#parts + 1] = tonumber(n)
    end
    return parts
end

-- Is version string a NEWER than version string b?
local function IsNewer(a, b)
    local va, vb = ParseVersion(a), ParseVersion(b)
    for i = 1, math.max(#va, #vb) do
        local x, y = va[i] or 0, vb[i] or 0
        if x ~= y then return x > y end
    end
    return false
end

-- Announce my version to whatever channels are valid right now.
local function BroadcastVersion()
    local msg = "V:" .. KASTACD_VERSION
    if IsInRaid() then
        C_ChatInfo.SendAddonMessage(COMM_PREFIX, msg, "RAID")
    elseif IsInGroup() then
        C_ChatInfo.SendAddonMessage(COMM_PREFIX, msg, "PARTY")
    end
    if IsInGuild() then
        C_ChatInfo.SendAddonMessage(COMM_PREFIX, msg, "GUILD")
    end
end

kcdEvent:RegisterEvent("ADDON_LOADED")
kcdEvent:RegisterEvent("CHAT_MSG_ADDON")
kcdEvent:RegisterEvent("PLAYER_ENTERING_WORLD")
kcdEvent:RegisterEvent("PLAYER_LOGOUT")
kcdEvent:RegisterEvent("GROUP_ROSTER_UPDATE")
kcdEvent:RegisterEvent("ZONE_CHANGED_NEW_AREA")
kcdEvent:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
kcdEvent:RegisterEvent("SPELLS_CHANGED")
kcdEvent:RegisterEvent("CHARACTER_POINTS_CHANGED")
kcdEvent:RegisterEvent("PLAYER_TALENT_UPDATE")
kcdEvent:RegisterEvent("INSPECT_READY")

-- Shared helper: populate memberGUIDs from CompactRaidFrames + direct unit tokens.
local function RefreshMemberGUIDs()
    memberGUIDs = {}
    -- Always include the player themselves
    memberGUIDs["player"] = UnitGUID("player")
    -- CompactRaidFrames (default Blizzard UI)
    for i = 1, 40 do
        local f = _G["CompactRaidFrame" .. i]
        if not f then break end
        local unit = f.unit or f.displayedUnit
        if unit and UnitExists(unit) then
            memberGUIDs[unit] = UnitGUID(unit)
        end
    end
    -- Direct unit-token fallback: covers party1-4 even when
    -- CompactRaidFrames haven't populated yet (common on pservers)
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) then
            memberGUIDs[unit] = UnitGUID(unit)
        end
    end
end

kcdEvent:SetScript("OnEvent", function(self, event, ...)
    -- ── ADDON_LOADED ───────────────────────────────────────────
    if event == "ADDON_LOADED" then
        if select(1, ...) == "KastaCD" then
            KastaCDInitDB()
        end
        return
    end

    -- ── CHAT_MSG_ADDON ─ someone announced their version ───────
    if event == "CHAT_MSG_ADDON" then
        local prefix, message = ...
        if prefix == COMM_PREFIX and message:sub(1, 2) == "V:" then
            local theirVersion = message:sub(3)
            if not notifiedNewVersion and IsNewer(theirVersion, KASTACD_VERSION) then
                notifiedNewVersion = true
                print("|cffff7f00[KastaCD]|r A new version (" .. theirVersion ..
                      ") is available! Get it at https://github.com/itsmekasta/KastaCD")
            end
        end
        return
    end

    -- ── PLAYER_LOGOUT ──────────────────────────────────────────
    if event == "PLAYER_LOGOUT" then
        PersistActiveProfile()
        return
    end

    -- ── PLAYER_ENTERING_WORLD ──────────────────────────────────
    if event == "PLAYER_ENTERING_WORLD" then
        KastaCDInitDB()
        C_Timer.After(1.5, function()
            RefreshMemberGUIDs()
            RebuildIcons()
        end)
        -- Announce our version once channels are ready.
        C_Timer.After(5, BroadcastVersion)
        return
    end

    -- ── GROUP_ROSTER_UPDATE ────────────────────────────────────
    if event == "GROUP_ROSTER_UPDATE" then
        if not HasGroup() then
            ClearIcons()
            return
        end
        C_Timer.After(0.8, function()
            if not HasGroup() then ClearIcons(); return end
            RefreshMemberGUIDs()
            RebuildIcons()
        end)
        -- New people joined: re-announce so they hear our version
        -- and we hear theirs.
        C_Timer.After(3, BroadcastVersion)
        return
    end

    -- ── ZONE_CHANGED_NEW_AREA ──────────────────────────────────
    if event == "ZONE_CHANGED_NEW_AREA" then
        C_Timer.After(1, RebuildIcons)
        return
    end

    -- ── Talent / spell changes ─────────────────────────────────
    if event == "SPELLS_CHANGED"
    or event == "CHARACTER_POINTS_CHANGED"
    or event == "PLAYER_TALENT_UPDATE" then
        C_Timer.After(0.5, RebuildIcons)
        return
    end

    -- ── COMBAT_LOG_EVENT_UNFILTERED ───────────────────────────
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        HandleCombatLog(...)
        return
    end

    -- ── INSPECT_READY ─────────────────────────────────────────
    if event == "INSPECT_READY" then
        local guid = select(1, ...)
        if guid and UNIT_SPEC_CACHE and UNIT_SPEC_CACHE[guid] == false then
            UNIT_SPEC_CACHE[guid] = nil
            C_Timer.After(0.1, RebuildIcons)
        end
        return
    end
end)

-- =============================================================
-- Slash command  /kcd  –  open / close the settings menu
-- =============================================================
SLASH_KASTACD1 = "/kcd"
SlashCmdList["KASTACD"] = function()
    CreateKastaCDMenu()
    if kcdMenu:IsShown() then
        kcdMenu:Hide()
    else
        kcdMenu:Show()
    end
end
