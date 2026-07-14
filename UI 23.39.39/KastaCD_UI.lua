-- KastaCD_UI.lua - settings menu bootstrap. The options table lives in
-- KastaCD_Options.lua and is rendered by AceConfig-3.0/AceGUI-3.0; this
-- file registers it and exposes kcdMenu / CreateKastaCDMenu() for the
-- /kcd slash handler.
-- Depends on: KastaCD_DB.lua, KastaCD_Options.lua, KastaCD_libs.xml

-- Exposed so KastaCD_Events.lua can call them from the slash handler
kcdMenu                = nil
refreshClassPanelsFns  = {}

-- Defensive DB normalization: a brand new install, an upgrade from an
-- older save shape, or a /kcd typed before other files' ADDON_LOADED
-- init ran can all leave KastaCDDB fields nil, which crashes widgets
-- like Slider:SetValue(nil). Makes the menu self-healing regardless.
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

-- Registers the AceConfig options table and embeds it into Blizzard's
-- ESC > Interface > AddOns list. Called unconditionally at file bottom
-- so the entry exists from login, not only after /kcd is typed.
local optionsRegistered = false
local function EnsureOptionsRegistered()
    if optionsRegistered then return end
    optionsRegistered = true

    -- Must run before BuildKastaCDOptions()'s get/set closures touch KastaCDDB.*.
    EnsureMenuDBDefaults()

    local AceConfig       = LibStub("AceConfig-3.0")
    local AceConfigDialog = LibStub("AceConfigDialog-3.0")

    AceConfig:RegisterOptionsTable("KastaCD", BuildKastaCDOptions())
    AceConfigDialog:SetDefaultSize("KastaCD", 860, 620)
    AceConfigDialog:AddToBlizOptions("KastaCD", "KastaCD")
end

-- Rebuilds the entire registered options table and forces any open
-- dialog to re-render. AceConfig's `args` must be a plain table, so a
-- group whose row count changes at runtime (e.g. KastaPlates' per-NPC
-- list) has to be thrown away and rebuilt, not just re-evaluated via
-- get/set closures. Call after add/remove to a dynamic list, not after
-- a plain value change (those already update live).
function RefreshKastaCDOptionsTable()
    if not optionsRegistered then return end
    local AceConfig       = LibStub("AceConfig-3.0")
    local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
    AceConfig:RegisterOptionsTable("KastaCD", BuildKastaCDOptions())
    AceConfigRegistry:NotifyChange("KastaCD")
end

-- Materializes the /kcd standalone popup (once).
function CreateKastaCDMenu()
    if kcdMenu then return end

    EnsureOptionsRegistered()

    local AceConfigDialog = LibStub("AceConfigDialog-3.0")

    -- AceConfigDialog's standalone Frame window releases its widget back
    -- into the shared pool on hide, so holding a raw reference isn't
    -- safe. kcdMenu is a thin shim over AceConfigDialog's Open/Close API instead.
    kcdMenu = {
        IsShown = function() return AceConfigDialog.OpenFrames["KastaCD"] ~= nil end,
        Show    = function() AceConfigDialog:Open("KastaCD") end,
        Hide    = function() AceConfigDialog:Close("KastaCD") end,
    }
end

-- Registers the options table (and Interface Options entry) immediately,
-- so the category exists even if /kcd is never typed.
EnsureOptionsRegistered()
