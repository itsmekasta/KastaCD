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

-- KCD5 bundles the full settings picture, not just the per-profile spell
-- list: Party Cooldowns' own global toggles (growLeft, medallion,
-- borders, master enable) plus BOTH trackers' settings (enabled, test
-- mode, bar size, font size, border, READY text, "Active in:", and their
-- anchor's saved screen position) - all of it, since intAnchor/ccAnchor
-- are global (not part of the switchable profile object `p`) in this
-- addon's data model, they're read/written straight to/from KastaCDDB
-- here rather than through `p`. This is what makes /kcdimport (and the
-- plain paste-import box) actually change something beyond the spell
-- list - previously KCD3 only ever touched
-- offsets/iconSize/iconsPerRow/enabled/contentTypes.
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
    local ia = KastaCDDB.intAnchor or {}
    for ct, v in pairs(ia.contentTypes or {}) do
        if v then table.insert(parts, "i" .. ct:gsub(" ", "_")) end
    end
    local ca = KastaCDDB.ccAnchor or {}
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
    }

    return "KCD5:" .. table.concat(fields, ":") .. ":" .. table.concat(parts, ",")
end

-- Deserialise — KCD5 is current (full settings + tracker anchor position,
-- see SerializeProfile); KCD4 is legacy (full settings, no position);
-- KCD1/2/3 are legacy (spell list + offsets only, tracker/global settings
-- left untouched). Global for the same reason as SerializeProfile above.
--
-- NOTE: for KCD4/KCD5 this has a side effect beyond building the returned
-- profile table `p` - it writes directly into KastaCDDB.growLeft/
-- medallionOutsidePvP/showIconBorders/iconsEnabled/intAnchor/ccAnchor,
-- since those are global settings the imported data is meant to replace,
-- not profile-scoped ones. Every caller should follow up with
-- RebuildInterruptBars()/RebuildCCBars() (not just RebuildIcons()) so the
-- live trackers pick up the change immediately.
function DeserializeProfile(str)
    local p = type(NewProfileData) == "function" and NewProfileData() or {}
    p.enabled = p.enabled or {}
    local ox, oy, isz, ipr, rest

    if str:sub(1, 5) == "KCD5:" then
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

        if type(KastaCDDB.intAnchor) ~= "table" then KastaCDDB.intAnchor = {} end
        local ia = KastaCDDB.intAnchor
        ia.enabled, ia.testMode = N(9) == 1, N(10) == 1
        ia.barWidth, ia.barHeight, ia.fontSize = N(11), N(12), N(13)
        ia.hideBorder, ia.showReady = N(14) == 1, N(15) == 1
        ia.contentTypes = {}
        local iaX, iaY = NOpt(16), NOpt(17)

        if type(KastaCDDB.ccAnchor) ~= "table" then KastaCDDB.ccAnchor = {} end
        local ca = KastaCDDB.ccAnchor
        ca.enabled, ca.testMode = N(18) == 1, N(19) == 1
        ca.barWidth, ca.barHeight, ca.fontSize = N(20), N(21), N(22)
        ca.hideBorder, ca.showReady = N(23) == 1, N(24) == 1
        ca.contentTypes = {}
        local caX, caY = NOpt(25), NOpt(26)

        rest = f[27] or ""

        -- SetIntAnchorPos/SetCCAnchorPos (not a raw db.savedX/savedY write)
        -- so the live frame actually jumps to the new position immediately
        -- instead of only taking effect after the next reload.
        if iaX and iaY and type(SetIntAnchorPos) == "function" then SetIntAnchorPos(iaX, iaY) end
        if caX and caY and type(SetCCAnchorPos) == "function" then SetCCAnchorPos(caX, caY) end
        if type(RebuildInterruptBars) == "function" then RebuildInterruptBars() end
        if type(RebuildCCBars) == "function" then RebuildCCBars() end
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

        if type(KastaCDDB.intAnchor) ~= "table" then KastaCDDB.intAnchor = {} end
        local ia = KastaCDDB.intAnchor
        ia.enabled, ia.testMode = N(9) == 1, N(10) == 1
        ia.barWidth, ia.barHeight, ia.fontSize = N(11), N(12), N(13)
        ia.hideBorder, ia.showReady = N(14) == 1, N(15) == 1
        ia.contentTypes = {}

        if type(KastaCDDB.ccAnchor) ~= "table" then KastaCDDB.ccAnchor = {} end
        local ca = KastaCDDB.ccAnchor
        ca.enabled, ca.testMode = N(16) == 1, N(17) == 1
        ca.barWidth, ca.barHeight, ca.fontSize = N(18), N(19), N(20)
        ca.hideBorder, ca.showReady = N(21) == 1, N(22) == 1
        ca.contentTypes = {}

        rest = f[23] or ""
        if type(RebuildInterruptBars) == "function" then RebuildInterruptBars() end
        if type(RebuildCCBars) == "function" then RebuildCCBars() end
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
    local ia2 = KastaCDDB.intAnchor
    local ca2 = KastaCDDB.ccAnchor
    for tok in ((rest or "") .. ","):gmatch("([^,]*),") do
        if tok ~= "" then
            local k, v = tok:sub(1, 1), tok:sub(2)
            if k == "e" then
                local sid = tonumber(v)
                if sid then p.enabled[sid] = true end
            elseif k == "c" then
                p.contentTypes[v:gsub("_", " ")] = true
            elseif k == "i" and ia2 then
                ia2.contentTypes = ia2.contentTypes or {}
                ia2.contentTypes[v:gsub("_", " ")] = true
            elseif k == "x" and ca2 then
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

    -- Master switch sits above everything else on the page (order 1) and
    -- hides the rest of the page's content when off, same treatment as
    -- the tracker pages' own Enable toggle.
    local isHidden = function() return KastaCDDB.iconsEnabled == false end

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
    return { type = "group", name = "Overshield Display", order = 6, args = args }
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
                KastaCDDB.profiles[nm] = copy
                KastaCDDB.activeProfile = nm
                if type(ApplyActiveProfile) == "function" then ApplyActiveProfile() end
                if type(RebuildIcons) == "function" then RebuildIcons() end
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
            },
            crowdcontrol = BuildAnchorGroup{
                name = "Crowd Control", order = 20, dbField = "ccAnchor",
                RebuildFn = RebuildCCBars, GetPos = GetCCAnchorPos, SetPos = SetCCAnchorPos,
                LockFn = LockCCAnchor, UnlockFn = UnlockCCAnchor,
            },
        },
    }

    -- "Misc" is a pure category header - Interrupt Announce/Overshield
    -- Display are the actual pages, nested as its children. Sits above
    -- Profiles in the sidebar.
    local misc = {
        type = "group", name = "Misc", order = 30,
        args = {
            desc = { type = "description", order = 1, name = "Select an option below." },
            interruptAnnounce = BuildInterruptAnnounceGroup(),
            overshieldDisplay = BuildOvershieldGroup(),
        },
    }

    local args = {
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
