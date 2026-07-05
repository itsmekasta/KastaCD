-- =============================================================
-- KastaCD_Options.lua
-- Builds the AceConfig-3.0 options table consumed by KastaCD_UI.lua's
-- CreateKastaCDMenu(). This is the GladiusEx-style rewrite of the old
-- hand-built settings frame: same KastaCDDB fields and same tracker
-- functions, expressed as an Ace3 options table instead of raw frames.
-- Depends on: KastaCD_SpellDB.lua, KastaCD_DB.lua, KastaCD_Tracking.lua,
--             KastaCD_Interrupts.lua, KastaCD_CC.lua, KastaCD_libs.xml
-- =============================================================

-- Shared dark/flat theme for the settings menu's Ace3 widgets (see the
-- KastaCD-local patches in libs/AceGUI-3.0/widgets/*.lua). A single global
-- table instead of hardcoding colors in every widget file so the whole
-- menu stays visually consistent and can be re-tuned in one place. This
-- file loads before KastaCD_UI.lua opens the menu, and the widget files
-- (loaded even earlier, via KastaCD_libs.xml) only read KASTACD_THEME from
-- inside functions that run at actual widget-creation time - never at
-- file-load time - so the load-order difference doesn't matter.
KASTACD_THEME = {
    flatTex   = "Interface\\Buttons\\WHITE8x8",       -- solid 1x1 texture, tinted via color below
    bgWindow  = { 0.07, 0.07, 0.07, 0.97 },            -- outer settings window
    bgPanel   = { 0.11, 0.11, 0.11, 0.95 },            -- inline group / tab / tree panels
    bgElement = { 0.16, 0.16, 0.16, 1.00 },            -- sliders, dropdowns, edit boxes
    border    = { 0.24, 0.24, 0.24, 1.00 },            -- subtle panel/element borders
    accent    = { 1.00, 0.55, 0.00, 1.00 },            -- KastaCD's existing orange brand color
    text      = { 0.92, 0.92, 0.92, 1.00 },
    textDim   = { 0.60, 0.60, 0.60, 1.00 },
}

local LSM = LibStub("LibSharedMedia-3.0")

-- LibSharedMedia-3.0 ships with statusbar textures pre-registered but NO
-- fonts at all - font entries normally come from a standalone SharedMedia
-- data addon (see KastaCD.toc's OptionalDeps). Without this, the LSM30_Font
-- picker below would have zero selectable entries for anyone who doesn't
-- have that addon installed. :Register() is a no-op if the name is already
-- taken (e.g. by that addon's own registrations), so this is always safe -
-- same fallback set the old hand-rolled MakeMediaPicker used.
LSM:Register(LSM.MediaType.FONT, "Friz Quadrata", "Fonts\\FRIZQT__.TTF")
LSM:Register(LSM.MediaType.FONT, "Arial Narrow",  "Fonts\\ARIALN.TTF")
LSM:Register(LSM.MediaType.FONT, "Morpheus",      "Fonts\\MORPHEUS.TTF")
LSM:Register(LSM.MediaType.FONT, "Skurri",        "Fonts\\SKURRI.TTF")
LSM:Register(LSM.MediaType.STATUSBAR, "Solid", "Interface\\Buttons\\WHITE8x8")

local CLASS_ICON_TEXTURE = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"

-- Matches the main party-icon tracker's own border technique (see
-- ApplyIconBorders in KastaCD_Tracking.lua): the full texture region shows
-- the art's natural edge, a small inset crops it away. Applied
-- proportionally to the class icon's own quadrant of the shared class
-- atlas rather than a flat 0-1 range, since each class only occupies a
-- small sub-rectangle of that shared texture. A function (not a static
-- table) so it re-evaluates live if "Icon Borders" is toggled while the
-- menu is open.
local function ClassIconCoords(classKey)
    local c = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classKey]
    if not c then return { 0, 1, 0, 1 } end
    if KastaCDDB and KastaCDDB.showIconBorders then return c end
    local l, r, t, b = c[1], c[2], c[3], c[4]
    local w, h = r - l, b - t
    local pad = 0.08
    return { l + w * pad, r - w * pad, t + h * pad, b - h * pad }
end

local CATEGORY_ORDER = { "OFFENSIVE", "INTERRUPT", "DEFENSIVE", "IMMUNITY", "UTILITY" }
local CATEGORY_NAMES = {
    OFFENSIVE="Offensive", INTERRUPT="Interrupt",
    DEFENSIVE="Defensive", IMMUNITY="Immunity", UTILITY="Utility",
}

-- ── Profile export/import scratch state (dialog-local, not saved) ──
local newProfileNameVal = ""

-- ── KastaPlates "Add a Priority NPC" dropdown scratch state (dialog-
-- local, not saved) - which dungeon/NPC is currently picked in the two
-- Add-a-Priority-NPC dropdowns, before the Add button commits it.
local kpSelectedDungeon = nil
local kpSelectedNPC = nil

local function SplitColon(str)
    local t, pos = {}, 1
    while true do
        local s, e = str:find(":", pos, true)
        if not s then
            table.insert(t, str:sub(pos))
            break
        end
        table.insert(t, str:sub(pos, s - 1))
        pos = e + 1
    end
    return t
end

local function B(v) return v and 1 or 0 end

-- Recursive plain-table copy - used wherever a profile (or one of its
-- nested settings tables like intAnchor/ccAnchor) needs to be duplicated
-- into a NEW profile without the two ending up sharing the same nested
-- table by reference (which would make editing one silently edit the
-- other). Values are assumed to be plain data (numbers/strings/booleans/
-- tables) - KastaCDDB never stores functions or other non-serializable
-- values, so a naive recursive copy is safe here.
local function DeepCopyTable(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = DeepCopyTable(v)
    end
    return copy
end

-- KCD5 bundles the full settings picture, not just the per-profile spell
-- list: Party Cooldowns' own global toggles (growLeft, medallion,
-- borders, master enable) plus BOTH trackers' settings (enabled, test
-- mode, bar size, font size, border, READY text, "Active in:", and their
-- anchor's saved screen position) - all of it. intAnchor/ccAnchor are
-- themselves per-profile fields on `p` (see KastaCD_DB.lua's
-- NewProfileData/ApplyActiveProfile), so SerializeProfile/
-- DeserializeProfile read/write them straight off `p` like every other
-- profile field. This is what makes /kcdimport (and the plain paste-import
-- box) actually change something beyond the spell list - previously KCD3
-- only ever touched offsets/iconSize/iconsPerRow/enabled/contentTypes.
--
-- Font/texture *choice* is deliberately NOT included - safely encoding
-- arbitrary SharedMedia-registered names in this delimited format risks
-- collisions with the format's own separators, for a cosmetic setting
-- that's the least likely thing anyone actually wants transplanted from
-- someone else's setup.
--
-- Global (not local) so KastaCD_ProfileShare.lua can reuse the exact same
-- string format for chat-shared profile links, instead of duplicating it.
function SerializeProfile(p)
    local parts = {}
    for sid, v in pairs(p.enabled or {}) do
        if v then table.insert(parts, "e" .. sid) end
    end
    for ct, v in pairs(p.contentTypes or {}) do
        if v then table.insert(parts, "c" .. ct:gsub(" ", "_")) end
    end
    -- intAnchor/ccAnchor are per-profile fields on p itself (not global
    -- KastaCDDB fields) - see KastaCD_DB.lua's NewProfileData/
    -- ApplyActiveProfile for why. Reading straight off p keeps this
    -- correct even if p isn't the currently-active profile.
    local ia = p.intAnchor or {}
    for ct, v in pairs(ia.contentTypes or {}) do
        if v then table.insert(parts, "i" .. ct:gsub(" ", "_")) end
    end
    local ca = p.ccAnchor or {}
    for ct, v in pairs(ca.contentTypes or {}) do
        if v then table.insert(parts, "x" .. ct:gsub(" ", "_")) end
    end
    table.sort(parts)

    -- savedX/savedY are left as "" (not 0) when nil - the sender's anchor
    -- has never been manually positioned yet, still sitting at its
    -- CENTER-relative default. Encoding that as 0/0 would make the
    -- receiver's tracker jump to the screen corner on import, the exact
    -- "snaps to corner" bug already fixed once for the Position sliders
    -- (see GetIntAnchorPos's comment) - so DeserializeProfile below only
    -- calls SetIntAnchorPos/SetCCAnchorPos when both fields are present.
    local fields = {
        p.offsetX or 0, p.offsetY or 0, p.iconSize or 22, p.iconsPerRow or 5,
        B(KastaCDDB.growLeft), B(KastaCDDB.medallionOutsidePvP), B(KastaCDDB.showIconBorders),
        B(KastaCDDB.iconsEnabled ~= false),
        B(ia.enabled ~= false), B(ia.testMode), ia.barWidth or 200, ia.barHeight or 20,
        ia.fontSize or 10, B(ia.hideBorder), B(ia.showReady ~= false),
        ia.savedX or "", ia.savedY or "",
        B(ca.enabled ~= false), B(ca.testMode), ca.barWidth or 200, ca.barHeight or 20,
        ca.fontSize or 10, B(ca.hideBorder), B(ca.showReady ~= false),
        ca.savedX or "", ca.savedY or "",
        -- KCD6 additions: raid-group visibility + its own offset/size
        -- settings (KastaCD_DB.lua's raidOffsetX etc.), and both
        -- trackers' click-through toggle.
        B(KastaCDDB.showInRaidGroups),
        p.raidOffsetX or 0, p.raidOffsetY or 0, p.raidIconSize or 22, p.raidIconsPerRow or 5,
        B(ia.clickThrough), B(ca.clickThrough),
    }

    return "KCD6:" .. table.concat(fields, ":") .. ":" .. table.concat(parts, ",")
end

-- Deserialise — KCD6 is current (adds raid-group settings + click-through
-- on top of KCD5); KCD5 is legacy (full settings + tracker anchor
-- position); KCD4 is legacy (full settings, no position); KCD1/2/3 are
-- legacy (spell list + offsets only, tracker settings left untouched).
-- Importing an older format simply leaves the newer fields at their
-- defaults (GetIntDB()/GetCCDB() and KastaCDInitDB's own lazy-fill logic
-- already handle a missing clickThrough/raidOffsetX/etc. safely) rather
-- than erroring. Global for the same reason as SerializeProfile above.
--
-- For KCD4/KCD5 this also still writes KastaCDDB.growLeft/
-- medallionOutsidePvP/showIconBorders/iconsEnabled directly, since those
-- ARE global (not profile-scoped) settings the imported data is meant to
-- replace outright. Interrupt/CC tracker settings, by contrast, are
-- profile-scoped (see KastaCD_DB.lua's NewProfileData/ApplyActiveProfile)
-- so they're written onto the returned profile table `p` (p.intAnchor/
-- p.ccAnchor) instead of the live KastaCDDB globals - the caller installs
-- `p` as a new/updated profile and switches to it, at which point
-- ApplyActiveProfile() copies p.intAnchor/p.ccAnchor down into
-- KastaCDDB.intAnchor/.ccAnchor for the live trackers to pick up. Writing
-- them straight to KastaCDDB here (as this used to) would instead mutate
-- whichever OTHER profile happened to be active at import time.
function DeserializeProfile(str)
    local p = type(NewProfileData) == "function" and NewProfileData() or {}
    p.enabled   = p.enabled   or {}
    p.intAnchor = p.intAnchor or {}
    p.ccAnchor  = p.ccAnchor  or {}
    local ox, oy, isz, ipr, rest

    if str:sub(1, 5) == "KCD6:" then
        local f = SplitColon(str:sub(6))
        if #f < 33 then return nil, "Bad format." end
        local function N(i) return tonumber(f[i]) or 0 end
        -- Empty field ("") means the sender's anchor was never manually
        -- positioned - see the comment on savedX/savedY in
        -- SerializeProfile above.
        local function NOpt(i)
            local s = f[i]
            if not s or s == "" then return nil end
            return tonumber(s)
        end
        ox, oy, isz, ipr = N(1), N(2), N(3), N(4)

        KastaCDDB.growLeft            = N(5) == 1
        KastaCDDB.medallionOutsidePvP = N(6) == 1
        KastaCDDB.showIconBorders     = N(7) == 1
        KastaCDDB.iconsEnabled        = N(8) == 1

        local ia = p.intAnchor
        ia.enabled, ia.testMode = N(9) == 1, N(10) == 1
        ia.barWidth, ia.barHeight, ia.fontSize = N(11), N(12), N(13)
        ia.hideBorder, ia.showReady = N(14) == 1, N(15) == 1
        ia.contentTypes = {}
        ia.savedX, ia.savedY = NOpt(16), NOpt(17)

        local ca = p.ccAnchor
        ca.enabled, ca.testMode = N(18) == 1, N(19) == 1
        ca.barWidth, ca.barHeight, ca.fontSize = N(20), N(21), N(22)
        ca.hideBorder, ca.showReady = N(23) == 1, N(24) == 1
        ca.contentTypes = {}
        ca.savedX, ca.savedY = NOpt(25), NOpt(26)

        KastaCDDB.showInRaidGroups = N(27) == 1
        p.raidOffsetX, p.raidOffsetY = N(28), N(29)
        p.raidIconSize, p.raidIconsPerRow = N(30), N(31)
        ia.clickThrough = N(32) == 1
        ca.clickThrough = N(33) == 1

        rest = f[34] or ""
    end

    if not ox and str:sub(1, 5) == "KCD5:" then
        local f = SplitColon(str:sub(6))
        if #f < 26 then return nil, "Bad format." end
        local function N(i) return tonumber(f[i]) or 0 end
        -- Empty field ("") means the sender's anchor was never manually
        -- positioned - leave it alone instead of forcing 0/0, which would
        -- snap the receiver's tracker to the screen corner (see the
        -- comment on savedX/savedY in SerializeProfile above).
        local function NOpt(i)
            local s = f[i]
            if not s or s == "" then return nil end
            return tonumber(s)
        end
        ox, oy, isz, ipr = N(1), N(2), N(3), N(4)

        KastaCDDB.growLeft            = N(5) == 1
        KastaCDDB.medallionOutsidePvP = N(6) == 1
        KastaCDDB.showIconBorders     = N(7) == 1
        KastaCDDB.iconsEnabled        = N(8) == 1

        local ia = p.intAnchor
        ia.enabled, ia.testMode = N(9) == 1, N(10) == 1
        ia.barWidth, ia.barHeight, ia.fontSize = N(11), N(12), N(13)
        ia.hideBorder, ia.showReady = N(14) == 1, N(15) == 1
        ia.contentTypes = {}
        ia.savedX, ia.savedY = NOpt(16), NOpt(17)

        local ca = p.ccAnchor
        ca.enabled, ca.testMode = N(18) == 1, N(19) == 1
        ca.barWidth, ca.barHeight, ca.fontSize = N(20), N(21), N(22)
        ca.hideBorder, ca.showReady = N(23) == 1, N(24) == 1
        ca.contentTypes = {}
        ca.savedX, ca.savedY = NOpt(25), NOpt(26)

        rest = f[27] or ""
    end

    if not ox and str:sub(1, 5) == "KCD4:" then
        local f = SplitColon(str:sub(6))
        if #f < 22 then return nil, "Bad format." end
        local function N(i) return tonumber(f[i]) or 0 end
        ox, oy, isz, ipr = N(1), N(2), N(3), N(4)

        KastaCDDB.growLeft            = N(5) == 1
        KastaCDDB.medallionOutsidePvP = N(6) == 1
        KastaCDDB.showIconBorders     = N(7) == 1
        KastaCDDB.iconsEnabled        = N(8) == 1

        local ia = p.intAnchor
        ia.enabled, ia.testMode = N(9) == 1, N(10) == 1
        ia.barWidth, ia.barHeight, ia.fontSize = N(11), N(12), N(13)
        ia.hideBorder, ia.showReady = N(14) == 1, N(15) == 1
        ia.contentTypes = {}

        local ca = p.ccAnchor
        ca.enabled, ca.testMode = N(16) == 1, N(17) == 1
        ca.barWidth, ca.barHeight, ca.fontSize = N(18), N(19), N(20)
        ca.hideBorder, ca.showReady = N(21) == 1, N(22) == 1
        ca.contentTypes = {}

        rest = f[23] or ""
    end

    if not ox then
        ox, oy, isz, ipr, rest =
            str:match("^KCD3:(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(.*)$")
    end
    if not ox then
        local _, _, _, a, b, c, d, r =
            str:match("^KCD2:(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(.*)$")
        if a then ox, oy, isz, ipr, rest = a, b, c, d, r end
    end
    if not ox then
        local _, a, b, c, d, r =
            str:match("^KCD%d+:(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(.*)$")
        if a then ox, oy, isz, ipr, rest = a, b, c, d, r end
    end
    if not ox then return nil, "Bad format." end
    p.offsetX     = tonumber(ox)  or 0
    p.offsetY     = tonumber(oy)  or 0
    p.iconSize    = tonumber(isz) or 22
    p.iconsPerRow = tonumber(ipr) or 5
    p.contentTypes = {}
    local ia2 = p.intAnchor
    local ca2 = p.ccAnchor
    for tok in ((rest or "") .. ","):gmatch("([^,]*),") do
        if tok ~= "" then
            local k, v = tok:sub(1, 1), tok:sub(2)
            if k == "e" then
                local sid = tonumber(v)
                if sid then p.enabled[sid] = true end
            elseif k == "c" then
                p.contentTypes[v:gsub("_", " ")] = true
            elseif k == "i" then
                ia2.contentTypes = ia2.contentTypes or {}
                ia2.contentTypes[v:gsub("_", " ")] = true
            elseif k == "x" then
                ca2.contentTypes = ca2.contentTypes or {}
                ca2.contentTypes[v:gsub("_", " ")] = true
            end
        end
    end
    return p
end

local function NotifyRefresh()
    LibStub("AceConfigRegistry-3.0"):NotifyChange("KastaCD")
end

-- Blank vertical-gap option - used around buttons that don't already sit
-- next to a header divider for a visual break (e.g. Interrupt Announce's
-- Reset/Test buttons).
local function Spacer(order)
    return { type = "description", order = order, name = " ", fontSize = "large" }
end

-- =============================================================
-- Settings group (offsets, icon layout, misc toggles, content types)
-- =============================================================
local function BuildSettingsGroup()
    -- Grouped into three inline "cells" so related settings are visually
    -- separated without adding extra tab navigation: Position (every
    -- slider), Misc (everything else toggle-like), Visibility (borders +
    -- "Active in:" content-type gating).
    local positionArgs = {
        offsetX = {
            type = "range", order = 10, name = "Offset X", min = -200, max = 200, step = 1,
            get = function() return KastaCDDB.offsetX end,
            set = function(_, v) KastaCDDB.offsetX = v; if type(RebuildIcons) == "function" then RebuildIcons() end end,
        },
        offsetY = {
            type = "range", order = 20, name = "Offset Y", min = -200, max = 200, step = 1,
            get = function() return KastaCDDB.offsetY end,
            set = function(_, v) KastaCDDB.offsetY = v; if type(RebuildIcons) == "function" then RebuildIcons() end end,
        },
        iconSize = {
            type = "range", order = 30, name = "Icon Size", min = 12, max = 48, step = 1,
            get = function() return KastaCDDB.iconSize end,
            set = function(_, v) KastaCDDB.iconSize = v; if type(RebuildIcons) == "function" then RebuildIcons() end end,
        },
        iconsPerRow = {
            type = "range", order = 40, name = "Icons per Row", min = 1, max = 10, step = 1,
            get = function() return KastaCDDB.iconsPerRow end,
            set = function(_, v) KastaCDDB.iconsPerRow = v; if type(RebuildIcons) == "function" then RebuildIcons() end end,
        },
    }

    local miscArgs = {
        growLeft = {
            type = "toggle", order = 10, name = "Grow Left",
            get = function() return KastaCDDB.growLeft == true end,
            set = function(_, v) KastaCDDB.growLeft = v; if type(RebuildIcons) == "function" then RebuildIcons() end end,
        },
        pvpMedallion = {
            type = "toggle", order = 20, name = "PvP Medallion",
            get = function() return KastaCDDB.enabled[208683] == true end,
            set = function(_, v)
                KastaCDDB.enabled[208683] = v and true or nil
                if type(RebuildIcons) == "function" then RebuildIcons() end
            end,
        },
        medallionOutsidePvP = {
            type = "toggle", order = 30, name = "Medallion outside PvP",
            get = function() return KastaCDDB.medallionOutsidePvP == true end,
            set = function(_, v)
                KastaCDDB.medallionOutsidePvP = v and true or false
                if type(RebuildIcons) == "function" then RebuildIcons() end
            end,
        },
    }

    local visibilityArgs = {
        showIconBorders = {
            type = "toggle", order = 10, name = "Icon Borders",
            get = function() return KastaCDDB.showIconBorders == true end,
            set = function(_, v)
                KastaCDDB.showIconBorders = v and true or false
                if type(ApplyIconBorders) == "function" then ApplyIconBorders() end
                NotifyRefresh() -- re-crop the class tree icons to match
            end,
        },
        showInRaidGroups = {
            type = "toggle", order = 15, name = "Show in Raid Groups",
            desc = "Party Cooldown icons are hidden by default once your group grows past a party (there'd normally be too many members to anchor icons to usefully). Turn this on to show them for the whole raid roster instead - see the Raid Groups section below for separate offset/size options.",
            get = function() return KastaCDDB.showInRaidGroups == true end,
            set = function(_, v)
                KastaCDDB.showInRaidGroups = v and true or false
                if type(RebuildIcons) == "function" then RebuildIcons() end
            end,
        },
        contentHeader = { type = "header", order = 20, name = "Active in" },
    }
    local ctOrder = 30
    for _, ct in ipairs(CONTENT_TYPES or {}) do
        local ctName = ct
        visibilityArgs["content_" .. ctName:gsub(" ", "_")] = {
            type = "toggle", order = ctOrder, name = ctName,
            get = function() return KastaCDDB.contentTypes[ctName] == true end,
            set = function(_, v)
                KastaCDDB.contentTypes[ctName] = v
                if type(RebuildIcons) == "function" then RebuildIcons() end
            end,
        }
        ctOrder = ctOrder + 10
    end

    -- Separate offset/size/per-row controls for raid1-40 units, only
    -- relevant (and only shown) once "Show in Raid Groups" above is on -
    -- a 40-member raid usually wants smaller icons/different placement
    -- than a 5-person party, so these deliberately don't share the
    -- Position cell's values (see raidOffsetX etc. in KastaCD_DB.lua).
    local raidArgs = {
        raidOffsetX = {
            type = "range", order = 10, name = "Offset X", min = -200, max = 200, step = 1,
            get = function() return KastaCDDB.raidOffsetX end,
            set = function(_, v) KastaCDDB.raidOffsetX = v; if type(RebuildIcons) == "function" then RebuildIcons() end end,
        },
        raidOffsetY = {
            type = "range", order = 20, name = "Offset Y", min = -200, max = 200, step = 1,
            get = function() return KastaCDDB.raidOffsetY end,
            set = function(_, v) KastaCDDB.raidOffsetY = v; if type(RebuildIcons) == "function" then RebuildIcons() end end,
        },
        raidIconSize = {
            type = "range", order = 30, name = "Icon Size", min = 12, max = 48, step = 1,
            get = function() return KastaCDDB.raidIconSize end,
            set = function(_, v) KastaCDDB.raidIconSize = v; if type(RebuildIcons) == "function" then RebuildIcons() end end,
        },
        raidIconsPerRow = {
            type = "range", order = 40, name = "Icons per Row", min = 1, max = 10, step = 1,
            get = function() return KastaCDDB.raidIconsPerRow end,
            set = function(_, v) KastaCDDB.raidIconsPerRow = v; if type(RebuildIcons) == "function" then RebuildIcons() end end,
        },
    }

    -- Master switch sits above everything else on the page (order 1) and
    -- hides the rest of the page's content when off, same treatment as
    -- the tracker pages' own Enable toggle.
    local isHidden = function() return KastaCDDB.iconsEnabled == false end
    local isRaidCellHidden = function()
        return KastaCDDB.iconsEnabled == false or not KastaCDDB.showInRaidGroups
    end

    local args = {
        enabled = {
            type = "toggle", order = 1, name = "Enable",
            get = function() return KastaCDDB.iconsEnabled ~= false end,
            set = function(_, v)
                KastaCDDB.iconsEnabled = v and true or false
                if type(RebuildIcons) == "function" then RebuildIcons() end
            end,
        },
    }
    args.position   = { type = "group", inline = true, order = 10, name = "Position",   hidden = isHidden, args = positionArgs }
    args.misc       = { type = "group", inline = true, order = 20, name = "Misc",       hidden = isHidden, args = miscArgs }
    args.visibility = { type = "group", inline = true, order = 30, name = "Visibility", hidden = isHidden, args = visibilityArgs }
    args.raidGroups = { type = "group", inline = true, order = 40, name = "Raid Groups", hidden = isRaidCellHidden, args = raidArgs }

    return { type = "group", name = "Party Cooldowns", order = 10, args = args }
end

-- =============================================================
-- Interrupt Announce - chat message on the player's own successful
-- interrupt (see KastaCD_Announce.lua for the actual announce logic).
-- Placed as its own tab under Party Cooldowns for now.
-- =============================================================
local function BuildInterruptAnnounceGroup()
    local args = {
        enabled = {
            type = "toggle", order = 10, name = "Enable", width = "full",
            desc = "Announces your own successful interrupts to chat, so party/raid members without an interrupt addon still see it land.",
            get = function() return GetAnnounceDB().enabled == true end,
            set = function(_, v) GetAnnounceDB().enabled = v and true or false end,
        },
        channel = {
            type = "select", order = 20, name = "Chat Channel",
            values = { SAY = "Say", YELL = "Yell" },
            get = function() return GetAnnounceDB().channel end,
            set = function(_, v) GetAnnounceDB().channel = v end,
        },
        messageHeader = { type = "header", order = 30, name = "Message" },
        placeholderDesc = {
            type = "description", order = 40,
            name = "Customize your announcement text. Available placeholders:\n" ..
                "|cffffd200{player}|r - your name\n" ..
                "|cffffd200{spell}|r - the spell you interrupted (posted as a clickable spell link)\n" ..
                "|cffffd200{myspell}|r - the interrupt ability you used (also a clickable spell link)\n" ..
                "|cffffd200{target}|r - who you interrupted",
        },
        template = {
            type = "input", order = 50, name = "Announcement Text", width = "full",
            multiline = 2,
            get = function() return GetAnnounceDB().template end,
            set = function(_, v)
                if not v or v == "" then return end
                GetAnnounceDB().template = v
            end,
        },
        resetBtnSpacer = Spacer(55),
        resetBtn = {
            type = "execute", order = 60, name = "Reset to Default",
            func = function()
                GetAnnounceDB().template = GetDefaultAnnounceTemplate()
                NotifyRefresh()
            end,
        },
        testBtn = {
            type = "execute", order = 70, name = "Test",
            desc = "Sends a sample announcement with your current settings, without needing a real interrupt.",
            func = function()
                if type(TestAnnounceInterrupt) == "function" then TestAnnounceInterrupt() end
            end,
        },
    }

    return { type = "group", name = "Interrupt Announce", order = 5, args = args }
end

-- =============================================================
-- Overshield Display - ported from Derangement's Shield Meters (see
-- KastaCD_Overshield.lua for the actual hook logic). Extends Blizzard's
-- default absorb-bar overlay so shield amounts past max HP stay
-- visible, on party/raid frames and player/target/focus/pet frames.
-- =============================================================
local function BuildOvershieldGroup()
    local args = {
        enabled = {
            type = "toggle", order = 10, name = "Enable", width = "full",
            desc = "Shows the full shield/absorb amount on unit frames (party, raid, player, target, focus, pet) even past max HP, instead of Blizzard's default which hides the extra shield once a unit is at full health.",
            get = function() return GetOvershieldDB().enabled == true end,
            set = function(_, v) GetOvershieldDB().enabled = v and true or false end,
        },
        alwaysShowGlow = {
            type = "toggle", order = 20, name = "Always Show Glow", width = "full",
            desc = "Shows a faint glow to the left of the shield overlay whenever a unit has any overshield, not just while it's changing.",
            get = function() return GetOvershieldDB().alwaysShowGlow == true end,
            set = function(_, v) GetOvershieldDB().alwaysShowGlow = v and true or false end,
        },
    }
    return { type = "group", name = "Overshield Display", order = 10, inline = true, args = args }
end

-- =============================================================
-- Keystone Helper - adds Ready Check / Pull Timer buttons to the Mythic+
-- keystone frame (Font of Power) and best-effort auto-inserts the
-- player's keystone when that frame opens (KastaCD_Keystone.lua). Also
-- houses the Mob Count toggle (KastaCD_MobCount.lua) - both are Mythic+
-- run helpers, merged into one box instead of two separate ones.
-- =============================================================
local function BuildKeystoneGroup()
    -- Split into three compact nested boxes (General / Pull Timer / Key
    -- Announcer) instead of one long flat list - each concern gets its
    -- own labeled group, and simple checkboxes drop `width="full"` so
    -- they sit two-per-row instead of each eating a whole line.
    local generalArgs = {
        enabled = {
            type = "toggle", order = 10, name = "Enable",
            desc = "Adds Ready Check and Pull Timer buttons to the Mythic+ keystone frame that appears at a Font of Power.",
            get = function() return GetKeystoneDB().enabled == true end,
            set = function(_, v) GetKeystoneDB().enabled = v and true or false end,
        },
        autoInsert = {
            type = "toggle", order = 20, name = "Auto-Insert Keystone",
            desc = "Automatically uses your Mythic Keystone as soon as the Font of Power frame opens, the same as right-clicking it in your bags. Turn this off if it ever inserts the wrong item or misbehaves.",
            get = function() return GetKeystoneDB().autoInsert == true end,
            set = function(_, v) GetKeystoneDB().autoInsert = v and true or false end,
        },
        mobCountEnabled = {
            type = "toggle", order = 30, name = "Mob Contribution",
            desc = "Shows each Mythic+ trash mob's enemy-forces completion percentage next to its nameplate while inside a Mythic Keystone run.",
            get = function() return GetMobCountDB().enabled == true end,
            set = function(_, v)
                GetMobCountDB().enabled = v and true or false
                if type(RefreshMobCountPlates) == "function" then RefreshMobCountPlates() end
            end,
        },
    }

    local pullTimerArgs = {
        pullTimerSeconds = {
            type = "select", order = 10, name = "Duration", width = "half",
            desc = "How many seconds the Pull Timer button's countdown runs (/rt pull timer <seconds>). Requires the Exorsus Raid Tools (ExRT) addon - that's what actually implements the /rt command and countdown.",
            values = { [3] = "3 seconds", [5] = "5 seconds", [10] = "10 seconds" },
            get = function() return GetKeystoneDB().pullTimerSeconds end,
            set = function(_, v) GetKeystoneDB().pullTimerSeconds = v end,
        },
        pullTimerHint = {
            type = "description", order = 20,
            name = "|cffffd200Requires the Exorsus Raid Tools (ExRT) addon|r.",
        },
    }

    local keyAnnouncerArgs = {
        keyAnnouncerTriggerInfo = {
            type = "description", order = 1, fontSize = "medium",
            name = "|cffffd200Type \"keys please\" in chat (no slash) to have it announce your Mythic Keystone.|r",
        },
        keyAnnouncerEnabled = {
            type = "toggle", order = 10, name = "Enable",
            desc = "Responds to \"keys please\" in chat (or /kcdkeys) by announcing your currently-owned Mythic Keystone's dungeon and level.",
            get = function() return GetKeyAnnouncerDB().enabled == true end,
            set = function(_, v) GetKeyAnnouncerDB().enabled = v and true or false end,
        },
        keyAnnouncerTrigger = {
            type = "toggle", order = 20, name = "Respond to \"keys please\"",
            desc = "Watches party/raid/instance/guild chat for the literal message \"keys please\" and responds automatically (subject to Response Mode and cooldown below). Turn off to only ever announce via /kcdkeys.",
            get = function() return GetKeyAnnouncerDB().triggerEnabled == true end,
            set = function(_, v) GetKeyAnnouncerDB().triggerEnabled = v and true or false end,
        },
        keyAnnouncerColor = {
            type = "toggle", order = 30, name = "Color Formatting",
            desc = "Colors the dungeon name and key level in the announced chat message.",
            get = function() return GetKeyAnnouncerDB().colorFormatting == true end,
            set = function(_, v) GetKeyAnnouncerDB().colorFormatting = v and true or false end,
        },
        keyAnnouncerMode = {
            type = "select", order = 40, name = "Response Mode", width = "half",
            desc = "Auto: announces immediately when someone types keys please. Semi-Auto: shows a confirmation popup first. Manual: never responds automatically - only /kcdkeys announces.",
            values = { AUTO = "Auto", SEMI = "Semi-Auto", MANUAL = "Manual" },
            get = function() return GetKeyAnnouncerDB().mode end,
            set = function(_, v) GetKeyAnnouncerDB().mode = v end,
        },
        keyAnnouncerChannel = {
            type = "select", order = 50, name = "Announce Channel", width = "half",
            desc = "Auto picks the best available channel (instance chat > raid > party). The others force that specific channel and print an error if it isn't currently available.",
            values = { AUTO = "Auto", PARTY = "Party", RAID = "Raid", INSTANCE = "Instance", GUILD = "Guild" },
            get = function() return GetKeyAnnouncerDB().channel end,
            set = function(_, v) GetKeyAnnouncerDB().channel = v end,
        },
        keyAnnouncerCooldown = {
            type = "range", order = 60, name = "Cooldown (seconds)", width = "full", min = 5, max = 60, step = 1,
            desc = "Minimum seconds between keys please responses, both globally and per-sender, to avoid spamming chat.",
            get = function() return GetKeyAnnouncerDB().cooldown end,
            set = function(_, v) GetKeyAnnouncerDB().cooldown = v end,
        },
        keyAnnouncerHint = {
            type = "description", order = 70,
            name = "|cffffd200/kcdkeys|r announce your own key - |cffffd200/kcdkeys ask|r sends \"keys please\" so others respond - |cffffd200/kcdkeys test|r preview - |cffffd200/kcdkeys guild|r force guild chat.",
        },
    }

    local args = {
        general = { type = "group", inline = true, order = 10, name = "General", args = generalArgs },
        pullTimer = { type = "group", inline = true, order = 20, name = "Pull Timer", args = pullTimerArgs },
        keyAnnouncer = { type = "group", inline = true, order = 30, name = "Key Announcer", args = keyAnnouncerArgs },
    }
    return { type = "group", name = "Keystone Helper", order = 20, inline = true, args = args }
end

-- =============================================================
-- Affix Call-outs - warns about Explosive orb spawns and Quaking debuffs
-- during a Mythic Keystone run. See KastaCD_AffixCallouts.lua.
-- =============================================================
local function BuildAffixCalloutGroup()
    local args = {
        enabled = {
            type = "toggle", order = 10, name = "Enable", width = "full",
            desc = "Warns about time-critical Mythic+ affix mechanics (Explosive orb spawns, Quaking) with a raid-warning-style screen message.",
            get = function() return GetAffixCalloutDB().enabled == true end,
            set = function(_, v) GetAffixCalloutDB().enabled = v and true or false end,
        },
        explosive = {
            type = "toggle", order = 20, name = "Explosive Orbs", width = "full",
            desc = "Warns the moment an Explosive orb spawns.",
            get = function() return GetAffixCalloutDB().explosive == true end,
            set = function(_, v) GetAffixCalloutDB().explosive = v and true or false end,
        },
        quaking = {
            type = "toggle", order = 30, name = "Quaking", width = "full",
            desc = "Warns when the Quaking debuff lands on you, so you can move away from the group before it pops.",
            get = function() return GetAffixCalloutDB().quaking == true end,
            set = function(_, v) GetAffixCalloutDB().quaking = v and true or false end,
        },
        sound = {
            type = "toggle", order = 40, name = "Play Sound", width = "full",
            desc = "Also plays the raid warning sound alongside the screen message.",
            get = function() return GetAffixCalloutDB().sound == true end,
            set = function(_, v) GetAffixCalloutDB().sound = v and true or false end,
        },
    }
    return { type = "group", name = "Affix Call-outs", order = 40, inline = true, args = args }
end

-- =============================================================
-- Personal Leaderboard - records your own best Mythic+ completion time
-- per dungeon (no cross-player sync). See KastaCD_Leaderboard.lua and
-- the /kcdboard slash command.
-- =============================================================
local function BuildLeaderboardGroup()
    local args = {
        enabled = {
            type = "toggle", order = 10, name = "Enable", width = "full",
            desc = "Records your personal best Mythic+ completion time per dungeon. View them with /kcdboard, or /kcdboard reset to clear.",
            get = function() return GetLeaderboardDB().enabled == true end,
            set = function(_, v) GetLeaderboardDB().enabled = v and true or false end,
        },
        hint = {
            type = "description", order = 20,
            name = "Type |cffffd200/kcdboard|r in chat to view your recorded best times.",
        },
    }
    return { type = "group", name = "Personal Leaderboard", order = 50, inline = true, args = args }
end

-- =============================================================
-- KastaPlates - recolors nameplates for user-flagged priority NPCs, per
-- dungeon (see KastaCD_KastaPlates.lua). The per-dungeon/per-NPC list
-- grows and shrinks at runtime (Add Target/Mouseover, Remove), which
-- AceConfig's static `args` tables can't reflect just by re-evaluating
-- get/set/hidden closures - every add/remove calls
-- RefreshKastaCDOptionsTable() (KastaCD_UI.lua) to rebuild the whole
-- options table fresh instead.
-- =============================================================
local function BuildKastaPlatesGroup()
    local function GetKPDB() return GetKastaPlatesDB() end

    local args = {
        enabled = {
            type = "toggle", order = 10, name = "Enable", width = "full",
            desc = "Recolors a nameplate's health bar for enemies you've flagged as priority targets in the current dungeon.",
            get = function() return GetKPDB().enabled == true end,
            set = function(_, v)
                GetKPDB().enabled = v and true or false
                if type(RefreshKastaPlates) == "function" then RefreshKastaPlates() end
            end,
        },
        pickHeader = { type = "header", order = 20, name = "Customize an NPC" },
        pickDesc = {
            type = "description", order = 21,
            name = "Pick a dungeon and an NPC - every NPC in it is already known from Mythic Dungeon " ..
                "Tools' data, nothing to add first. Color/mark controls appear below once you've picked one.",
        },
        -- No explicit width on either - both default to the same ~170px
        -- column width, which is what keeps them on the same row instead
        -- of each claiming the full width and wrapping to its own line.
        pickDungeon = {
            type = "select", order = 22, name = "Dungeon",
            values = function() return KASTAPLATES_DUNGEONS or {} end,
            get = function() return kpSelectedDungeon end,
            set = function(_, v)
                kpSelectedDungeon = v
                kpSelectedNPC = nil
            end,
        },
        pickNPC = {
            type = "select", order = 23, name = "NPC",
            disabled = function() return kpSelectedDungeon == nil end,
            values = function()
                return (kpSelectedDungeon and KASTAPLATES_DUNGEON_NPCS[kpSelectedDungeon]) or {}
            end,
            get = function() return kpSelectedNPC end,
            set = function(_, v) kpSelectedNPC = v end,
        },
        -- 3D model preview of the selected NPC, with its name/NPC ID as
        -- text to the model's right - both live inside ONE custom widget
        -- (KastaCD_ModelWidget.lua) that positions them itself, rather
        -- than two separate option entries relying on AceGUI's Flow
        -- layout to land side by side (tried first, didn't reliably keep
        -- them on the same row). `name` (-> the widget's SetLabel) carries
        -- the info text; `get` (-> SetText) carries the stringified
        -- displayID. KASTAPLATES_NPC_DISPLAYID is a flat npcID -> creature
        -- displayID lookup (KastaCD_KastaPlatesData.lua).
        pickModel = {
            type = "input", dialogControl = "KastaCDModel",
            order = 24, width = "full",
            hidden = function() return kpSelectedDungeon == nil or kpSelectedNPC == nil end,
            name = function()
                local roster = kpSelectedDungeon and KASTAPLATES_DUNGEON_NPCS[kpSelectedDungeon]
                local name = roster and roster[kpSelectedNPC] or "Unknown"
                return "|cffffd200" .. name .. "|r\n\nNPC ID " .. tostring(kpSelectedNPC)
            end,
            get = function()
                local displayID = KASTAPLATES_NPC_DISPLAYID and KASTAPLATES_NPC_DISPLAYID[kpSelectedNPC]
                return displayID and tostring(displayID) or ""
            end,
        },
        -- Reading never creates a saved entry (avoids cluttering the list
        -- below with every NPC someone merely glanced at) - only writing
        -- a color/mark actually different from the default does, via
        -- GetOrCreateKastaPlatesEntry (KastaCD_KastaPlates.lua).
        pickColor = {
            type = "color", order = 26, name = "Color",
            hidden = function() return kpSelectedDungeon == nil or kpSelectedNPC == nil end,
            get = function()
                local bucket = GetKPDB().dungeons[kpSelectedDungeon]
                local entry = bucket and bucket.npcs[kpSelectedNPC]
                local c = (entry and entry.color) or DefaultKastaPlatesColor(kpSelectedNPC)
                return c[1], c[2], c[3]
            end,
            set = function(_, r, g, b)
                local entry = GetOrCreateKastaPlatesEntry(kpSelectedDungeon, kpSelectedNPC)
                if entry then
                    entry.color = { r, g, b }
                    if type(RefreshKastaPlates) == "function" then RefreshKastaPlates() end
                    if type(RefreshKastaCDOptionsTable) == "function" then RefreshKastaCDOptionsTable() end
                end
            end,
        },
        pickMark = {
            type = "select", order = 27, name = "Mark",
            hidden = function() return kpSelectedDungeon == nil or kpSelectedNPC == nil end,
            values = function() return KASTAPLATES_MARKS or {} end,
            get = function()
                local bucket = GetKPDB().dungeons[kpSelectedDungeon]
                local entry = bucket and bucket.npcs[kpSelectedNPC]
                return (entry and entry.mark) or 0
            end,
            set = function(_, v)
                local entry = GetOrCreateKastaPlatesEntry(kpSelectedDungeon, kpSelectedNPC)
                if entry then
                    entry.mark = v
                    -- Missing before - meant a picked mark never actually
                    -- got applied to a currently-visible plate until
                    -- something else happened to re-trigger it.
                    if type(RefreshKastaPlates) == "function" then RefreshKastaPlates() end
                    if type(RefreshKastaCDOptionsTable) == "function" then RefreshKastaCDOptionsTable() end
                end
            end,
        },
    }

    -- One TAB per dungeon that has at least one tracked NPC (not inline -
    -- childGroups="tab" on the returned group below turns these into
    -- actual browsable tabs, same non-inline + childGroups="tab" pattern
    -- BuildClassGroup already uses successfully for Party Cooldowns' own
    -- per-class category tabs, at the same nesting depth: Misc >
    -- Kastaplates > [this tab strip], matching Party Cooldowns > [class]
    -- > [category tabs]). Each NPC is its own row: name label, color
    -- picker, raid-mark dropdown, remove button.
    local dungeonOrder = 100
    local db = GetKPDB()
    local instanceIDs = {}
    for instanceID in pairs(db.dungeons) do table.insert(instanceIDs, instanceID) end
    table.sort(instanceIDs, function(a, b)
        return (db.dungeons[a].name or "") < (db.dungeons[b].name or "")
    end)

    for _, instanceID in ipairs(instanceIDs) do
        local bucket = db.dungeons[instanceID]
        local npcArgs = {}
        local npcOrder = 10

        local npcIDs = {}
        for npcID in pairs(bucket.npcs) do table.insert(npcIDs, npcID) end
        table.sort(npcIDs, function(a, b)
            return (bucket.npcs[a].name or "") < (bucket.npcs[b].name or "")
        end)

        for _, npcID in ipairs(npcIDs) do
            local entry = bucket.npcs[npcID]
            -- width here is a plain string keyword only ("half"/"double"/
            -- "full"/nil) - AceConfigRegistry's validator rejects a raw
            -- number outright (hit and fixed once already this session).
            npcArgs["name" .. npcID] = {
                type = "description", order = npcOrder, width = "double",
                name = entry.name or ("NPC " .. npcID),
            }
            npcArgs["color" .. npcID] = {
                type = "color", order = npcOrder + 1, name = "Color", width = "half",
                get = function()
                    local c = entry.color or DefaultKastaPlatesColor(npcID)
                    return c[1], c[2], c[3]
                end,
                set = function(_, r, g, b)
                    entry.color = { r, g, b }
                    if type(RefreshKastaPlates) == "function" then RefreshKastaPlates() end
                end,
            }
            npcArgs["mark" .. npcID] = {
                type = "select", order = npcOrder + 2, name = "Mark", width = "half",
                values = function() return KASTAPLATES_MARKS or {} end,
                get = function() return entry.mark or 0 end,
                set = function(_, v)
                    entry.mark = v
                    -- Missing before - see the matching fix on pickMark
                    -- above for why this is what made mark changes not
                    -- actually take effect on an already-visible plate.
                    if type(RefreshKastaPlates) == "function" then RefreshKastaPlates() end
                end,
            }
            npcArgs["remove" .. npcID] = {
                type = "execute", order = npcOrder + 3, name = "Remove", width = "half",
                confirm = true, confirmText = "Remove " .. tostring(entry.name) .. " from this list?",
                func = function()
                    RemoveKastaPlatesNPC(instanceID, npcID)
                    if type(RefreshKastaPlates) == "function" then RefreshKastaPlates() end
                    if type(RefreshKastaCDOptionsTable) == "function" then RefreshKastaCDOptionsTable() end
                end,
            }
            npcOrder = npcOrder + 10
        end

        args["dungeon" .. instanceID] = {
            type = "group", order = dungeonOrder, name = bucket.name or ("Instance " .. instanceID),
            args = npcArgs,
        }
        dungeonOrder = dungeonOrder + 10
    end

    -- Cast Highlight - generic "this unit is casting something" tint,
    -- independent of the per-NPC list above (works on any nameplate, not
    -- just tracked ones) since it reads UnitCastingInfo/UnitChannelInfo
    -- directly rather than needing a curated spell database.
    local chArgs = {
        enabled = {
            type = "toggle", order = 10, name = "Enable", width = "full",
            desc = "Tints any nameplate whose unit is currently casting or channeling a spell - color depends on whether it can be interrupted.",
            get = function() return GetKPDB().castHighlight.enabled == true end,
            set = function(_, v)
                GetKPDB().castHighlight.enabled = v and true or false
                if type(RefreshKastaPlates) == "function" then RefreshKastaPlates() end
            end,
        },
        interruptibleColor = {
            type = "color", order = 20, name = "Interruptible Cast Color",
            desc = "Color while the unit is casting something that CAN be interrupted.",
            get = function()
                local c = GetKPDB().castHighlight.interruptibleColor
                return c[1], c[2], c[3]
            end,
            set = function(_, r, g, b) GetKPDB().castHighlight.interruptibleColor = { r, g, b } end,
        },
        nonInterruptibleColor = {
            type = "color", order = 30, name = "Non-Interruptible Cast Color",
            desc = "Color while the unit is casting something that CANNOT be interrupted - usually the more dangerous case.",
            get = function()
                local c = GetKPDB().castHighlight.nonInterruptibleColor
                return c[1], c[2], c[3]
            end,
            set = function(_, r, g, b) GetKPDB().castHighlight.nonInterruptibleColor = { r, g, b } end,
        },
    }
    args.castHighlight = {
        type = "group", inline = true, order = 200, name = "Cast Highlight", args = chArgs,
    }

    -- childGroups="tab" turns the non-inline "dungeon<id>" groups above
    -- into a browsable tab strip; the "Cast Highlight" group stays
    -- inline=true so it's exempt and keeps rendering as a fixed box
    -- alongside the enable toggle/picker controls above the tab strip,
    -- per AceConfigDialog's own documented rule (inline groups never
    -- become tab/tree nodes regardless of childGroups on their parent).
    return { type = "group", name = "Kastaplates", order = 60, childGroups = "tab", args = args }
end

-- =============================================================
-- Info tab - top-level page above Party Cooldowns in the sidebar.
-- Same logo + greeting/Twitch/Discord layout as KastaUI's own Info panel
-- (media/kastalogo.tga copied into KastaCD/media rather than referencing
-- KastaUI's copy directly, so this doesn't silently break for anyone who
-- has KastaCD without also having KastaUI installed).
-- =============================================================
local function BuildInfoGroup()
    -- Plain left-aligned stock AceConfig descriptions - no image (the
    -- logo texture rendered green through AceConfig's "image" field even
    -- with a confirmed-good file/format) and no custom widget for text
    -- centering (rendered as real, truncated edit boxes instead of plain
    -- text - worse than what it was trying to fix). Just simple spacers
    -- between the three text blocks.
    local args = {
        topGap = { type = "description", order = 1, name = "\n\n\n\n\n\n", fontSize = "large" },
        greeting = {
            type = "description", order = 20, fontSize = "large",
            name = "Hey champ, thanks for using Kasta|cffff7f00CD|r.",
        },
        socialGap = Spacer(25),
        social = {
            type = "description", order = 30, fontSize = "large",
            name = "|cffffffffTwitch:|r |cff9b59b6twitch.tv/kastaqt|r\n|cffffffffDiscord:|r |cff7289dakastaqt|r",
        },
        creditsGap = Spacer(35),
        credits = {
            type = "description", order = 40, fontSize = "large",
            name = "\nCredits to |cffffd200Ruuku|r and |cffffd200Legendary <Defiance>|r for helping with the Spell DB.",
        },
    }
    return { type = "group", name = "Info", order = 5, args = args }
end

-- =============================================================
-- Interrupt Tracker / Crowd Control Tracker groups
-- Both share identical shape - anchor field name ("intAnchor"/
-- "ccAnchor") and the tracker's own accessor functions are the only
-- difference, so one builder handles both.
-- =============================================================
local function BuildAnchorGroup(opts)
    -- opts: { name, order, dbField, RebuildFn, GetPos, SetPos, LockFn, UnlockFn }
    local dbField = opts.dbField

    local function GetAnchorDB()
        if type(KastaCDDB[dbField]) ~= "table" then KastaCDDB[dbField] = {} end
        return KastaCDDB[dbField]
    end

    -- Grouped into four inline "cells": Position (placement + size
    -- sliders), Misc (enable/test/lock toggles), Visibility (this
    -- tracker's OWN independent "Active in:" choice - no longer shared
    -- with the other two trackers), Customize (everything about how the
    -- bar looks: texture, font, font size, border).
    local positionArgs = {
        barWidth = {
            type = "range", order = 10, name = "Bar Width", min = 100, max = 400, step = 1,
            get = function() return GetAnchorDB().barWidth or 200 end,
            set = function(_, v)
                GetAnchorDB().barWidth = v
                if type(opts.RebuildFn) == "function" then opts.RebuildFn() end
            end,
        },
        barHeight = {
            type = "range", order = 20, name = "Bar Height", min = 14, max = 40, step = 1,
            get = function() return GetAnchorDB().barHeight or 20 end,
            set = function(_, v)
                GetAnchorDB().barHeight = v
                if type(opts.RebuildFn) == "function" then opts.RebuildFn() end
            end,
        },
        positionX = {
            type = "range", order = 30, name = "Position X", min = -2000, max = 2000, step = 1,
            get = function()
                local x = 0
                if type(opts.GetPos) == "function" then x = opts.GetPos() end
                return x
            end,
            set = function(_, v)
                local _, y = 0, 0
                if type(opts.GetPos) == "function" then _, y = opts.GetPos() end
                if type(opts.SetPos) == "function" then opts.SetPos(v, y) end
            end,
        },
        positionY = {
            type = "range", order = 40, name = "Position Y", min = -2000, max = 2000, step = 1,
            get = function()
                local _, y = 0, 0
                if type(opts.GetPos) == "function" then _, y = opts.GetPos() end
                return y
            end,
            set = function(_, v)
                local x = 0
                if type(opts.GetPos) == "function" then x = opts.GetPos() end
                if type(opts.SetPos) == "function" then opts.SetPos(x, v) end
            end,
        },
        growDirection = {
            -- KastaCD-local: string keys ("up"/"down"), not booleans -
            -- AceConfigDialog sorts a select option's `values` keys with
            -- plain table.sort, and Lua's default `<` comparator errors on
            -- booleans ("attempt to compare two boolean values"), which
            -- silently kept this whole option from rendering at all.
            type = "select", order = 50, name = "Grow Direction",
            desc = "Which way new bars stack. Grow Down keeps the header fixed at the top and adds bars below it (the anchor's saved position is its top-left corner). Grow Up keeps the header fixed at the bottom and adds bars above it (the anchor's saved position is its bottom-left corner instead) - drag/reposition again after switching to re-anchor from the new corner.",
            values = { down = "Grow Down", up = "Grow Up" },
            get = function() return GetAnchorDB().growUp and "up" or "down" end,
            set = function(_, v)
                GetAnchorDB().growUp = (v == "up")
                GetAnchorDB().savedX, GetAnchorDB().savedY = nil, nil
                if type(opts.RebuildFn) == "function" then opts.RebuildFn() end
            end,
        },
    }

    local visibilityArgs = {
        contentHeader = { type = "header", order = 10, name = "Active in" },
    }
    local ctOrder = 20
    for _, ct in ipairs(CONTENT_TYPES or {}) do
        local ctName = ct
        visibilityArgs["content_" .. ctName:gsub(" ", "_")] = {
            type = "toggle", order = ctOrder, name = ctName,
            get = function() return GetAnchorDB().contentTypes and GetAnchorDB().contentTypes[ctName] == true end,
            set = function(_, v)
                local db = GetAnchorDB()
                db.contentTypes = db.contentTypes or {}
                db.contentTypes[ctName] = v
                if type(opts.RebuildFn) == "function" then opts.RebuildFn() end
            end,
        }
        ctOrder = ctOrder + 10
    end

    local customizeArgs = {
        font = {
            type = "select", order = 10, name = "Font",
            dialogControl = "LSM30_Font",
            values = LSM:HashTable(LSM.MediaType.FONT),
            get = function()
                local cur = GetAnchorDB().fontPath or "Fonts\\FRIZQT__.TTF"
                for name, path in pairs(LSM:HashTable(LSM.MediaType.FONT)) do
                    if path == cur then return name end
                end
                return "Friz Quadrata"
            end,
            set = function(_, name)
                GetAnchorDB().fontPath = LSM:Fetch(LSM.MediaType.FONT, name)
                if type(opts.RebuildFn) == "function" then opts.RebuildFn() end
            end,
        },
        texture = {
            type = "select", order = 20, name = "Texture",
            dialogControl = "LSM30_Statusbar",
            values = LSM:HashTable(LSM.MediaType.STATUSBAR),
            get = function()
                local cur = GetAnchorDB().texturePath or "Interface\\TargetingFrame\\UI-StatusBar"
                for name, path in pairs(LSM:HashTable(LSM.MediaType.STATUSBAR)) do
                    if path == cur then return name end
                end
                return "Blizzard"
            end,
            set = function(_, name)
                GetAnchorDB().texturePath = LSM:Fetch(LSM.MediaType.STATUSBAR, name)
                if type(opts.RebuildFn) == "function" then opts.RebuildFn() end
            end,
        },
        fontSize = {
            type = "range", order = 30, name = "Font Size", min = 8, max = 18, step = 1,
            get = function() return GetAnchorDB().fontSize or 10 end,
            set = function(_, v)
                GetAnchorDB().fontSize = v
                if type(opts.RebuildFn) == "function" then opts.RebuildFn() end
            end,
        },
        hideBorder = {
            type = "toggle", order = 40, name = "Hide Border",
            get = function() return GetAnchorDB().hideBorder == true end,
            set = function(_, v)
                GetAnchorDB().hideBorder = v and true or false
                if type(opts.RebuildFn) == "function" then opts.RebuildFn() end
            end,
        },
        showReady = {
            type = "toggle", order = 50, name = "Show \"READY\" Text",
            desc = "Shows green \"READY\" text on the bar when off cooldown. Turn off to leave that side of the bar blank instead.",
            get = function() return GetAnchorDB().showReady ~= false end,
            set = function(_, v) GetAnchorDB().showReady = v and true or false end,
        },
        clickThrough = {
            type = "toggle", order = 60, name = "Click-through",
            desc = "Lets clicks pass through the bar to whatever's underneath it (nameplates, action bars, etc.) instead of the bar itself catching them. Only applies while locked - unlock the bar to reposition it as usual.",
            get = function() return GetAnchorDB().clickThrough == true end,
            set = function(_, v)
                GetAnchorDB().clickThrough = v and true or false
                if type(opts.RebuildFn) == "function" then opts.RebuildFn() end
            end,
        },
    }

    -- Master switch sits above everything else on the page (order 1) and
    -- hides the rest of the page's content when off, instead of just
    -- living buried inside Misc - unchecking it is meant to read as
    -- "nothing else here matters right now."
    local isHidden = function() return GetAnchorDB().enabled == false end

    local args = {
        enabled = {
            type = "toggle", order = 1, name = "Enable",
            get = function() return GetAnchorDB().enabled ~= false end,
            set = function(_, v)
                GetAnchorDB().enabled = v and true or false
                if type(opts.RebuildFn) == "function" then opts.RebuildFn() end
            end,
        },
        -- KastaCD-local: Test Mode/Unlock moved up to the top layer next
        -- to Enable (were previously buried inside the "Misc" inline
        -- section) - Enable > Test Mode > Unlock reads as the natural
        -- order for getting a tracker visible and positioned.
        testMode = {
            type = "toggle", order = 2, name = "Test Mode", hidden = isHidden,
            get = function() return GetAnchorDB().testMode == true end,
            set = function(_, v)
                GetAnchorDB().testMode = v and true or false
                if type(opts.RebuildFn) == "function" then opts.RebuildFn() end
            end,
        },
        locked = {
            type = "toggle", order = 3, name = "Unlock", hidden = isHidden,
            get = function() return GetAnchorDB().locked == false end,
            set = function(_, v)
                if v then
                    if type(opts.UnlockFn) == "function" then opts.UnlockFn() end
                else
                    if type(opts.LockFn) == "function" then opts.LockFn() end
                end
            end,
        },
    }
    args.position   = { type = "group", inline = true, order = 10, name = "Position",   hidden = isHidden, args = positionArgs }
    args.visibility = { type = "group", inline = true, order = 30, name = "Visibility", hidden = isHidden, args = visibilityArgs }
    args.customize  = { type = "group", inline = true, order = 40, name = "Customize",  hidden = isHidden, args = customizeArgs }

    -- Extra top-level toggles/entries specific to ONE tracker (not shared
    -- between Interrupts and CC) - e.g. Interrupts' "Show Arcane Torrent".
    -- Callers building these get access to this same isHidden/GetAnchorDB
    -- closure by passing a builder function rather than a plain table, so
    -- they behave identically to enabled/testMode/locked above instead of
    -- being bolted on from outside with their own separate DB access.
    if type(opts.BuildExtraArgs) == "function" then
        for key, entry in pairs(opts.BuildExtraArgs(GetAnchorDB, isHidden)) do
            args[key] = entry
        end
    end

    return { type = "group", name = opts.name, order = opts.order, args = args }
end

-- =============================================================
-- Profiles group
-- =============================================================
local function BuildProfilesGroup()
    local args = {
        activeProfile = {
            type = "select", order = 10, name = "Active Profile",
            values = function()
                local t = {}
                for n in pairs(KastaCDDB.profiles) do t[n] = n end
                return t
            end,
            get = function() return KastaCDDB.activeProfile end,
            set = function(_, name)
                if type(PersistActiveProfile) == "function" then PersistActiveProfile() end
                KastaCDDB.activeProfile = name
                if type(ApplyActiveProfile) == "function" then ApplyActiveProfile() end
                if type(RebuildIcons) == "function" then RebuildIcons() end
                if type(RebuildInterruptBars) == "function" then RebuildInterruptBars() end
                if type(RebuildCCBars) == "function" then RebuildCCBars() end
                NotifyRefresh()
                print("KastaCD: Switched to '" .. name .. "'.")
            end,
        },
        deleteProfile = {
            type = "execute", order = 20, name = "Delete Active Profile",
            confirm = true,
            confirmText = "Delete the active profile? This cannot be undone.",
            func = function()
                local name = KastaCDDB.activeProfile
                if name == "Default" then
                    print("KastaCD: Can't delete Default.")
                    return
                end
                KastaCDDB.profiles[name] = nil
                if type(PersistActiveProfile) == "function" then PersistActiveProfile() end
                KastaCDDB.activeProfile = "Default"
                if type(ApplyActiveProfile) == "function" then ApplyActiveProfile() end
                if type(RebuildIcons) == "function" then RebuildIcons() end
                if type(RebuildInterruptBars) == "function" then RebuildInterruptBars() end
                if type(RebuildCCBars) == "function" then RebuildCCBars() end
                NotifyRefresh()
                print("KastaCD: Deleted '" .. name .. "'.")
            end,
        },
        newProfileHeader = { type = "header", order = 30, name = "Create / Copy" },
        newProfileName = {
            type = "input", order = 40, name = "New Profile Name", width = "double",
            get = function() return newProfileNameVal end,
            set = function(_, v) newProfileNameVal = v end,
        },
        createProfile = {
            type = "execute", order = 50, name = "Create",
            func = function()
                local nm = newProfileNameVal
                if not nm or nm == "" then print("KastaCD: Enter a name."); return end
                if KastaCDDB.profiles[nm] then print("KastaCD: Already exists."); return end
                if type(PersistActiveProfile) == "function" then PersistActiveProfile() end
                KastaCDDB.profiles[nm] = type(NewProfileData) == "function" and NewProfileData() or {}
                KastaCDDB.activeProfile = nm
                if type(ApplyActiveProfile) == "function" then ApplyActiveProfile() end
                if type(RebuildIcons) == "function" then RebuildIcons() end
                if type(RebuildInterruptBars) == "function" then RebuildInterruptBars() end
                if type(RebuildCCBars) == "function" then RebuildCCBars() end
                NotifyRefresh()
                print("KastaCD: Created '" .. nm .. "'.")
            end,
        },
        copyProfile = {
            -- KastaCD-local: width="full" - this button ends up alone on
            -- its row (createProfile above it already pairs with the
            -- name input), so without an explicit width it left a dead
            -- gap to the right instead of filling the row.
            type = "execute", order = 60, name = "Copy Current As New", width = "full",
            func = function()
                local nm = newProfileNameVal
                if not nm or nm == "" then print("KastaCD: Enter a name."); return end
                if KastaCDDB.profiles[nm] then print("KastaCD: Already exists."); return end
                if type(PersistActiveProfile) == "function" then PersistActiveProfile() end
                local cur  = KastaCDDB.profiles[KastaCDDB.activeProfile]
                local copy = type(NewProfileData) == "function" and NewProfileData() or {}
                copy.enabled      = copy.enabled      or {}
                copy.contentTypes = copy.contentTypes or {}
                for sid, v in pairs(cur.enabled or {})       do copy.enabled[sid]     = v end
                copy.offsetX     = cur.offsetX     or 0
                copy.offsetY     = cur.offsetY     or 0
                copy.iconSize    = cur.iconSize    or 22
                copy.iconsPerRow = cur.iconsPerRow or 5
                for ct, v in pairs(cur.contentTypes or {}) do copy.contentTypes[ct] = v end
                -- Deep-copy (not reference-share) both trackers' settings
                -- too, so the new profile gets its own independent bar
                -- position/size/font/toggles instead of the two profiles
                -- silently editing the same table.
                copy.intAnchor = DeepCopyTable(cur.intAnchor) or {}
                copy.ccAnchor  = DeepCopyTable(cur.ccAnchor)  or {}
                KastaCDDB.profiles[nm] = copy
                KastaCDDB.activeProfile = nm
                if type(ApplyActiveProfile) == "function" then ApplyActiveProfile() end
                if type(RebuildIcons) == "function" then RebuildIcons() end
                if type(RebuildInterruptBars) == "function" then RebuildInterruptBars() end
                if type(RebuildCCBars) == "function" then RebuildCCBars() end
                NotifyRefresh()
                print("KastaCD: Copied to '" .. nm .. "'.")
            end,
        },
        exportImportHeader = { type = "header", order = 70, name = "Export / Import" },
        exportBox = {
            type = "input", order = 80, name = "Export (select all + copy)", width = "full",
            get = function()
                if type(PersistActiveProfile) == "function" then PersistActiveProfile() end
                return SerializeProfile(KastaCDDB.profiles[KastaCDDB.activeProfile])
            end,
            set = function() end,
        },
        importBox = {
            type = "input", order = 90, name = "Import (paste + press Enter)", width = "full",
            get = function() return "" end,
            set = function(_, value)
                local p, err = DeserializeProfile(value)
                if not p then
                    print("KastaCD: Import failed — " .. tostring(err))
                    return
                end
                local nm = "Imported"
                local n  = 1
                while KastaCDDB.profiles[nm] do n = n + 1; nm = "Imported " .. n end
                if type(PersistActiveProfile) == "function" then PersistActiveProfile() end
                KastaCDDB.profiles[nm] = p
                KastaCDDB.activeProfile = nm
                if type(ApplyActiveProfile) == "function" then ApplyActiveProfile() end
                if type(RebuildIcons) == "function" then RebuildIcons() end
                if type(RebuildInterruptBars) == "function" then RebuildInterruptBars() end
                if type(RebuildCCBars) == "function" then RebuildCCBars() end
                NotifyRefresh()
                print("KastaCD: Imported as '" .. nm .. "'.")
            end,
        },
        shareHeader = { type = "header", order = 100, name = "Share via Chat" },
        shareDesc = {
            type = "description", order = 110,
            name = "Posts a short message instead of the full export string, to whatever " ..
                "chat you last used (Say, Party, Whisper, etc.) - anyone with KastaCD who " ..
                "receives it can type |cffffd200/kcdimport <your name>|r to import your active " ..
                "profile (a clickable link is also included, but some servers strip it in " ..
                "transit - the slash command always works). Shares everything: Party " ..
                "Cooldowns' spell list and layout, plus both trackers' settings and their " ..
                "on-screen position.",
        },
        shareBtn = {
            -- KastaCD-local: width="full" - alone on its row (nothing to
            -- its right), so it left a dead gap without this.
            type = "execute", order = 120, name = "Post to Chat", width = "full",
            func = function()
                if type(PersistActiveProfile) == "function" then PersistActiveProfile() end
                local profile = KastaCDDB.profiles[KastaCDDB.activeProfile]
                if type(BroadcastProfileToChat) ~= "function" then
                    print("KastaCD: Chat sharing unavailable.")
                    return
                end
                local ok, msg = BroadcastProfileToChat(profile)
                if not ok then
                    print("|cffff0000KastaCD:|r " .. tostring(msg))
                elseif msg then
                    print("|cffffcc00KastaCD:|r " .. msg)
                end
            end,
        },
    }

    return { type = "group", name = "Profiles", order = 500, args = args }
end

-- Ace's toggle tooltip only supports a plain-text `desc` (see
-- AceConfigDialog-3.0.lua's OptionOnMouseOver - it can't call
-- GameTooltip:SetSpellByID like the old hand-rolled row tooltips did), so
-- this builds an equivalent text blurb instead: the spell's real flavor
-- text plus cooldown/duration/spec/level, queried live each hover (a
-- function, not a precomputed string) so it self-heals if the client
-- hadn't cached the spell's data yet on the first hover.
local function BuildSpellDesc(sid, data)
    return function()
        local parts = {}
        local flavor = GetSpellDescription and GetSpellDescription(sid)
        if flavor and flavor ~= "" then table.insert(parts, flavor) end
        if data.cooldown and data.cooldown > 0 then
            table.insert(parts, string.format("Cooldown: %ds", data.cooldown))
        end
        if data.duration and data.duration > 0 then
            table.insert(parts, string.format("Duration: %ds", data.duration))
        end
        if data.specs then
            local names = {}
            for _, specId in ipairs(data.specs) do
                local specName = GetSpecializationInfoByID and select(2, GetSpecializationInfoByID(specId))
                table.insert(names, specName or ("Spec " .. specId))
            end
            table.insert(parts, "Spec: " .. table.concat(names, ", "))
        end
        if data.minLevel then
            table.insert(parts, "Requires level " .. data.minLevel)
        end
        return table.concat(parts, "\n")
    end
end

-- =============================================================
-- Per-class spell groups (category sub-tabs)
-- =============================================================
local function BuildClassGroup(ci, order)
    local byCategory = {}
    for sid, data in pairs(SPELL_DB or {}) do
        if data.class == ci.key then
            local cat = data.category or "UTILITY"
            byCategory[cat] = byCategory[cat] or {}
            table.insert(byCategory[cat], { sid = sid, data = data })
        end
    end
    for _, spells in pairs(byCategory) do
        table.sort(spells, function(a, b) return a.data.name < b.data.name end)
    end

    local args = {}
    local catOrder = 10
    for _, catKey in ipairs(CATEGORY_ORDER) do
        local spells = byCategory[catKey]
        if spells and #spells > 0 then
            local catArgs = {}
            local spellOrder = 10
            for _, entry in ipairs(spells) do
                local sid, data = entry.sid, entry.data
                local icon = (GetSpellTexture and GetSpellTexture(sid)) or data.icon
                catArgs["s" .. sid] = {
                    type = "toggle", order = spellOrder,
                    name = data.name,
                    -- Real anchored icon (AceGUI CheckBox's native `image`
                    -- field) instead of an inline |Tpath:size|t escape in
                    -- the name string - the inline form was getting its
                    -- top edge clipped by the label font's line-height,
                    -- and inconsistently so between different icons.
                    image = icon,
                    desc = BuildSpellDesc(sid, data),
                    get = function() return KastaCDDB.enabled[sid] == true end,
                    set = function(_, v)
                        KastaCDDB.enabled[sid] = v and true or nil
                        if type(RebuildIcons) == "function" then RebuildIcons() end
                    end,
                }
                spellOrder = spellOrder + 10
            end
            args[catKey] = {
                type = "group", order = catOrder, name = CATEGORY_NAMES[catKey] or catKey,
                args = catArgs,
            }
            catOrder = catOrder + 10
        end
    end

    return {
        type = "group", name = ci.label, order = order, childGroups = "tab",
        icon = CLASS_ICON_TEXTURE,
        iconCoords = function() return ClassIconCoords(ci.key) end,
        args = args,
    }
end

-- Dialog-local (not saved) - which class's spells the "Tracked Spells"
-- cell row is currently filtered to. nil = show every class.
local ccSpellClassFilter = nil

local function RGBHex(ci)
    return string.format("%02x%02x%02x", (ci.r or 1) * 255, (ci.g or 1) * 255, (ci.b or 1) * 255)
end

-- Tracked Spells is the LAST section on the Crowd Control page (order=50,
-- highest of that page's args), sitting right below the class button row.
-- Snapping the scroll to the very bottom after a class toggle - instead of
-- the top - is what actually lands the newly shown/hidden spell box in
-- view without the user having to scroll down themselves. offset is an
-- oversized pixel value on purpose: AceGUIContainer-ScrollFrame's FixScroll
-- clamps whatever's stored here to the real max on next layout pass, so
-- this doesn't need to know the page's actual (variable) height.
local function ScrollCCToBottom()
    local AceConfigDialog = LibStub("AceConfigDialog-3.0", true)
    if not AceConfigDialog then return end
    local status = AceConfigDialog:GetStatusTable("KastaCD", { "trackerbars", "crowdcontrol" })
    if status.scroll then
        status.scroll.offset = 999999
        status.scroll.scrollvalue = 1000
    end
end

-- =============================================================
-- CC Tracker: per-spell enable/disable ("Tracked Spells" sub-tab)
--
-- Every CC_SPELLS entry is shown by default (unchanged pre-existing
-- behavior) - unchecking one here explicitly excludes it via
-- KastaCDDB.ccAnchor.disabledSpells (KastaCD_CC.lua's IsCCSpellEnabled),
-- regardless of what PickGuessCC's guessing or a real witnessed cast
-- would otherwise show. CC_SPELLS entries don't carry a `.name` field the
-- way SPELL_DB's do, so the label comes from GetSpellInfo(sid) instead.
--
-- Class navigation: a real AceConfig `type="group"` child would normally
-- become a tab/tree node - but that requires this whole box to stop being
-- inline, and per AceConfigDialog-3.0's own documented rule ("When a group
-- is displayed inline, all descendants will also be inline members of the
-- group"), everything under an inline parent is forced flat regardless of
-- what the child itself sets. This exact box being non-inline was also
-- the earlier "Tracked Spells doesn't show at all" bug (nested 4 levels
-- deep with no working tab/tree owner above it). So instead of fighting
-- AceConfig's nesting rules again, class selection here is a manual
-- filter: a row of small class-colored buttons ("cells") sets
-- ccSpellClassFilter and each class's own (still inline, still
-- proven-safe) box hides itself unless it matches - same net effect
-- (click a class, see only its spells) without touching group nesting.
local function BuildCCSpellToggleGroup()
    local function GetCCAnchorDB()
        if type(KastaCDDB.ccAnchor) ~= "table" then KastaCDDB.ccAnchor = {} end
        local db = KastaCDDB.ccAnchor
        if type(db.disabledSpells) ~= "table" then db.disabledSpells = {} end
        return db
    end

    local byClass = {}
    for sid, data in pairs(CC_SPELLS or {}) do
        if data.class and data.class ~= "ALL" then
            byClass[data.class] = byClass[data.class] or {}
            table.insert(byClass[data.class], { sid = sid, data = data })
        end
    end
    for _, spells in pairs(byClass) do
        table.sort(spells, function(a, b)
            local nameA = (GetSpellInfo and GetSpellInfo(a.sid)) or tostring(a.sid)
            local nameB = (GetSpellInfo and GetSpellInfo(b.sid)) or tostring(b.sid)
            return nameA < nameB
        end)
    end

    -- Reset the filter if it points at a class that (no longer) has any
    -- CC_SPELLS entries, so the list can't get stuck permanently hidden.
    if ccSpellClassFilter and not (byClass[ccSpellClassFilter] and #byClass[ccSpellClassFilter] > 0) then
        ccSpellClassFilter = nil
    end

    local args = {}

    -- Class cell row - one small button per class with at least one
    -- CC_SPELLS entry. Every class box defaults to hidden
    -- (ccSpellClassFilter starts nil) so the page opens collapsed instead
    -- of dumping every class's spells at once - click a class to show
    -- just it, click it again to collapse back down.
    --
    -- No "All"/"Close All" button - that toggle never actually collapsed
    -- the list back down once every class was shown (AceConfigDialog
    -- quirk that wasn't worth continuing to chase), so it's been dropped
    -- in favor of just the single-class cells below.
    --
    -- order=1..~12 (well under classOrder's 100+ below) so this row can
    -- never collide with - and get sorted in among - the class boxes
    -- themselves, regardless of how many classes end up listed.
    local cellOrder = 1
    for _, ci in ipairs(CLASS_INFO or {}) do
        local spells = byClass[ci.key]
        if spells and #spells > 0 then
            -- Death Knight's class color (dark red) is nearly invisible
            -- against these buttons' own red background - white reads
            -- clearly there instead, same as every other class's color
            -- already does against it.
            local hex = (ci.key == "DEATHKNIGHT") and "ffffff" or RGBHex(ci)
            local label = "|cff" .. hex .. ci.label .. "|r"
            args["filter" .. ci.key] = {
                -- "half" (~85px), not a raw number - AceConfig's width
                -- field only ever accepts "half"/"double"/"full"/nil (a
                -- plain number like 0.8 fails AceConfigRegistry's own
                -- validation outright, AND AceConfigDialog's renderer
                -- silently ignores anything that isn't one of those three
                -- keywords anyway, falling back to a default single-column
                -- width - so a raw number was never actually doing
                -- anything useful here even before it started erroring).
                type = "execute", order = cellOrder, width = "half",
                name = function()
                    return (ccSpellClassFilter == ci.key) and ("[" .. label .. "]") or label
                end,
                func = function()
                    ccSpellClassFilter = (ccSpellClassFilter == ci.key) and nil or ci.key
                    ScrollCCToBottom()
                    NotifyRefresh()
                end,
            }
            cellOrder = cellOrder + 1
        end
    end

    -- Starts well above the cell row's order range (see above) so a class
    -- box can never sort in between two button cells.
    local classOrder = 100
    for _, ci in ipairs(CLASS_INFO or {}) do
        local spells = byClass[ci.key]
        if spells and #spells > 0 then
            local classArgs = {}
            local spellOrder = 10
            for _, entry in ipairs(spells) do
                local sid, data = entry.sid, entry.data
                local name = (GetSpellInfo and GetSpellInfo(sid)) or ("Spell " .. sid)
                local icon = (GetSpellTexture and GetSpellTexture(sid)) or data.icon
                classArgs["s" .. sid] = {
                    type = "toggle", order = spellOrder,
                    name = name,
                    image = icon,
                    desc = BuildSpellDesc(sid, data),
                    get = function() return not GetCCAnchorDB().disabledSpells[sid] end,
                    set = function(_, v)
                        GetCCAnchorDB().disabledSpells[sid] = (not v) or nil
                        if type(RebuildCCBars) == "function" then RebuildCCBars() end
                    end,
                }
                spellOrder = spellOrder + 10
            end
            args[ci.key] = {
                type = "group", inline = true, order = classOrder, name = ci.label,
                hidden = function() return ccSpellClassFilter ~= ci.key end,
                args = classArgs,
            }
            classOrder = classOrder + 10
        end
    end

    return { type = "group", name = "Tracked Spells", order = 50, inline = true, args = args }
end

-- =============================================================
-- BuildKastaCDOptions  –  top-level tree
-- =============================================================
function BuildKastaCDOptions()
    -- "Party Cooldowns" doubles as both a real content page (offsets,
    -- layout, content types - see BuildSettingsGroup) AND the collapsible
    -- parent for all 12 class groups, nested directly into its own args.
    -- AceConfig's tree natively supports a group having both its own
    -- widgets and child sub-groups at once - clicking the row shows its
    -- page, clicking the separate +/- toggle expands/collapses the
    -- children, independent of each other.
    local partyCooldowns = BuildSettingsGroup()
    local classOrder = 100
    for _, ci in ipairs(CLASS_INFO or {}) do
        partyCooldowns.args[ci.key] = BuildClassGroup(ci, classOrder)
        classOrder = classOrder + 10
    end

    -- "Tracker Bars" is a pure category header - Interrupts and Crowd
    -- Control are the actual pages, nested as its children.
    local trackerBars = {
        type = "group", name = "Tracker Bars", order = 20,
        args = {
            desc = { type = "description", order = 1, name = "Select a tracker below." },
            interrupts = BuildAnchorGroup{
                name = "Interrupts", order = 10, dbField = "intAnchor",
                RebuildFn = RebuildInterruptBars, GetPos = GetIntAnchorPos, SetPos = SetIntAnchorPos,
                LockFn = LockIntAnchor, UnlockFn = UnlockIntAnchor,
                -- Interrupt-tracker-only: every INT_SPELLS isRacial entry
                -- is a resource-type variant of the same Blood Elf racial
                -- (Arcane Torrent) - not applicable to the CC tracker
                -- (BuildAnchorGroup is shared between both), so passed in
                -- here rather than living in the shared function.
                BuildExtraArgs = function(GetAnchorDB, isHidden)
                    return {
                        showArcaneTorrent = {
                            type = "toggle", order = 4, name = "Show Arcane Torrent", hidden = isHidden,
                            desc = "Shows a separate bar for the Blood Elf Arcane Torrent racial interrupt, in addition to each unit's class interrupt.",
                            get = function() return GetAnchorDB().showArcaneTorrent ~= false end,
                            set = function(_, v)
                                GetAnchorDB().showArcaneTorrent = v and true or false
                                if type(RebuildInterruptBars) == "function" then RebuildInterruptBars() end
                            end,
                        },
                    }
                end,
            },
            crowdcontrol = (function()
                local g = BuildAnchorGroup{
                    name = "Crowd Control", order = 20, dbField = "ccAnchor",
                    RebuildFn = RebuildCCBars, GetPos = GetCCAnchorPos, SetPos = SetCCAnchorPos,
                    LockFn = LockCCAnchor, UnlockFn = UnlockCCAnchor,
                }
                g.args.spells = BuildCCSpellToggleGroup()
                return g
            end)(),
        },
    }

    -- "Misc" holds Overshield Display and Keystone Helper directly as
    -- inline sub-sections on this same page (not separate sub-tabs) -
    -- Interrupt Announce is the only child that's still a real, separate
    -- navigable sub-tab, since its settings page is bigger/template-based
    -- and reads better on its own. Sits above Profiles in the sidebar.
    local misc = {
        type = "group", name = "Misc", order = 30,
        args = {
            interruptAnnounce = BuildInterruptAnnounceGroup(),
            overshieldDisplay = BuildOvershieldGroup(),
            keystoneHelper = BuildKeystoneGroup(),
            affixCallouts = BuildAffixCalloutGroup(),
            leaderboard = BuildLeaderboardGroup(),
            kastaplates = BuildKastaPlatesGroup(),
        },
    }

    local args = {
        info = BuildInfoGroup(),
        settings = partyCooldowns,
        trackerbars = trackerBars,
        misc = misc,
        profiles = BuildProfilesGroup(),
    }

    return {
        type = "group",
        name = string.format("Kasta|cffff7f00CD|r – Party Cooldowns  |cff808080v%s|r",
            tostring(KASTACD_VERSION or "?")),
        childGroups = "tree",
        args = args,
    }
end
