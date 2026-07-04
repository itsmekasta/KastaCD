-- =============================================================
-- KastaCD_UI.lua
-- Settings menu bootstrap. The actual options table (every panel,
-- slider, toggle, and picker) lives in KastaCD_Options.lua and is
-- rendered by the bundled AceConfig-3.0/AceGUI-3.0 framework - this
-- file just registers it and exposes kcdMenu / CreateKastaCDMenu()
-- for KastaCD_Events.lua's /kcd slash handler, unchanged.
-- Depends on: KastaCD_DB.lua, KastaCD_Options.lua, KastaCD_libs.xml
-- =============================================================

-- Exposed so KastaCD_Events.lua can call them from the slash handler
kcdMenu                = nil
refreshClassPanelsFns  = {}

-- =============================================================
-- Defensive DB normalization
-- ---------------------------------------------------------------
-- This file used to assume KastaCD_DB.lua had already fully populated
-- KastaCDDB (offsetX, iconSize, contentTypes, etc.)
-- by the time CreateKastaCDMenu() ran. That's true for an existing
-- install whose SavedVariables already have every field, but it's
-- NOT guaranteed for:
--   - a brand new install (no KastaCDDB on disk yet)
--   - someone upgrading from an older save shape missing newer fields
--     like new fields added in later versions
--   - any case where the other files' ADDON_LOADED-triggered init
--     didn't run before /kcd was typed
-- When any of those fields were nil, widgets like
-- Slider:SetValue(nil) threw immediately, aborting CreateKastaCDMenu
-- before kcdMenu ever got assigned - which is exactly why /kcd worked
-- for the author (whose DB already had every field) but silently
-- failed for other users. This function makes the menu self-healing
-- regardless of what the other files did or didn't set up.
-- =============================================================
local function EnsureMenuDBDefaults()
    if type(KastaCDDB) ~= "table" then KastaCDDB = {} end

    if type(KastaCDDB.profiles) ~= "table" then KastaCDDB.profiles = {} end
    if type(KastaCDDB.activeProfile) ~= "string"
    or not KastaCDDB.profiles[KastaCDDB.activeProfile] then
        KastaCDDB.activeProfile = "Default"
    end
    if type(KastaCDDB.profiles["Default"]) ~= "table" then
        KastaCDDB.profiles["Default"] = type(NewProfileData) == "function"
            and NewProfileData() or {}
    end

    if type(KastaCDDB.enabled) ~= "table" then KastaCDDB.enabled = {} end
    if type(KastaCDDB.offsetX) ~= "number" then KastaCDDB.offsetX = 0 end
    if type(KastaCDDB.offsetY) ~= "number" then KastaCDDB.offsetY = 0 end
    if type(KastaCDDB.iconSize) ~= "number" then KastaCDDB.iconSize = 22 end
    if type(KastaCDDB.iconsPerRow) ~= "number" then KastaCDDB.iconsPerRow = 5 end

    if type(KastaCDDB.contentTypes) ~= "table" then KastaCDDB.contentTypes = {} end
    if type(CONTENT_TYPES) == "table" then
        for _, ct in ipairs(CONTENT_TYPES) do
            if KastaCDDB.contentTypes[ct] == nil then
                KastaCDDB.contentTypes[ct] = true
            end
        end
    end

    -- Anchor frame positions (global, not profile-specific)
    if type(KastaCDDB.anchorPos)  ~= "table" then KastaCDDB.anchorPos     = {} end
    if KastaCDDB.anchorsLocked     == nil     then KastaCDDB.anchorsLocked  = true end
    if KastaCDDB.growLeft          == nil     then KastaCDDB.growLeft       = false end
    if KastaCDDB.showIconBorders   == nil     then KastaCDDB.showIconBorders = false end
end

-- =============================================================
-- EnsureOptionsRegistered  –  registers the AceConfig options table and
-- embeds it into Blizzard's own ESC > Interface > AddOns category list,
-- so KastaCD shows up there too instead of only being reachable via
-- /kcd's standalone popup. Split out from CreateKastaCDMenu (below) and
-- called unconditionally at the bottom of this file so the AddOns-list
-- entry exists from login, not only after /kcd has been typed once.
-- =============================================================
local optionsRegistered = false
local function EnsureOptionsRegistered()
    if optionsRegistered then return end
    optionsRegistered = true

    -- Must run before BuildKastaCDOptions()'s get/set closures touch
    -- KastaCDDB.* - see the big comment on EnsureMenuDBDefaults above
    -- for why this is the actual fix for "menu works for me, not for
    -- other users."
    EnsureMenuDBDefaults()

    local AceConfig       = LibStub("AceConfig-3.0")
    local AceConfigDialog = LibStub("AceConfigDialog-3.0")

    AceConfig:RegisterOptionsTable("KastaCD", BuildKastaCDOptions())
    AceConfigDialog:SetDefaultSize("KastaCD", 860, 620)
    AceConfigDialog:AddToBlizOptions("KastaCD", "KastaCD")
    -- No forced default-tab selection - the sidebar naturally lands on
    -- whichever entry sorts first by `order`, which is "Info" (order=5).
end

-- =============================================================
-- RefreshKastaCDOptionsTable  –  rebuilds the ENTIRE registered options
-- table from scratch and forces any open dialog to re-render.
--
-- AceConfig's `args` on a group must be a plain table, never a function
-- (AceConfigRegistry's validator enforces this), so a group whose row
-- count actually changes at runtime - like KastaPlates' per-dungeon,
-- per-NPC list, which grows/shrinks as the user adds/removes entries -
-- can't just rely on `hidden`/`get`/`set` closures re-evaluating (that
-- only updates EXISTING rows, e.g. the CC Tracker's class filter
-- buttons). The whole table has to be thrown away and rebuilt fresh from
-- the current SavedVariables, then re-registered under the same name -
-- AceConfig:RegisterOptionsTable simply replaces whatever was already
-- registered for that name. Call this after any add/remove to a dynamic
-- list, not after a plain value change (toggles/sliders/etc. already
-- update live via their own get/set - this is comparatively expensive
-- and only needed when the SHAPE of the table changed).
-- =============================================================
function RefreshKastaCDOptionsTable()
    if not optionsRegistered then return end
    local AceConfig       = LibStub("AceConfig-3.0")
    local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
    AceConfig:RegisterOptionsTable("KastaCD", BuildKastaCDOptions())
    AceConfigRegistry:NotifyChange("KastaCD")
end

-- =============================================================
-- CreateKastaCDMenu  –  materialize the /kcd standalone popup (once)
-- =============================================================
function CreateKastaCDMenu()
    if kcdMenu then return end

    EnsureOptionsRegistered()

    local AceConfigDialog = LibStub("AceConfigDialog-3.0")

    -- AceConfigDialog's standalone "Frame" window releases its underlying
    -- AceGUI widget back into the shared widget pool the instant it's
    -- hidden (AceGUIContainer-Frame.lua wires the real frame's OnHide
    -- script straight to that release), so holding on to a raw widget
    -- reference across repeated show/hide cycles isn't safe - it can be
    -- silently handed off to a completely different widget afterwards.
    -- kcdMenu is instead a thin shim over AceConfigDialog's documented
    -- Open/Close API, which re-creates the frame on demand. The /kcd
    -- slash handler in KastaCD_Events.lua only ever calls
    -- :IsShown()/:Hide()/:Show() on it, so this swap is transparent.
    kcdMenu = {
        IsShown = function() return AceConfigDialog.OpenFrames["KastaCD"] ~= nil end,
        -- Reverted: passing "settings" as a path here made AceConfigDialog
        -- drop straight into that sub-page instead of opening the full
        -- app (with its sidebar tree of Info/Party Cooldowns/Tracker
        -- Bars/Misc/Profiles) - a completely different, broken-looking
        -- window compared to the normal /kcd experience. Back to the
        -- plain call; the sidebar's first entry by order (now "Info")
        -- is selected on open, same as it's always worked.
        Show    = function() AceConfigDialog:Open("KastaCD") end,
        Hide    = function() AceConfigDialog:Close("KastaCD") end,
    }
end

-- Registers the options table (and the Interface Options AddOns-list
-- entry) immediately, so the category exists even if /kcd is never typed.
EnsureOptionsRegistered()
