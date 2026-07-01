-- =============================================================
-- KastaCD_Options.lua
-- Builds the AceConfig-3.0 options table consumed by KastaCD_UI.lua's
-- CreateKastaCDMenu(). This is the GladiusEx-style rewrite of the old
-- hand-built settings frame: same KastaCDDB fields and same tracker
-- functions, expressed as an Ace3 options table instead of raw frames.
-- Depends on: KastaCD_SpellDB.lua, KastaCD_DB.lua, KastaCD_Tracking.lua,
--             KastaCD_Interrupts.lua, KastaCD_CC.lua, KastaCD_libs.xml
-- =============================================================

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

local CATEGORY_ORDER = { "OFFENSIVE", "INTERRUPT", "DEFENSIVE", "IMMUNITY", "UTILITY" }
local CATEGORY_NAMES = {
    OFFENSIVE="Offensive", INTERRUPT="Interrupt",
    DEFENSIVE="Defensive", IMMUNITY="Immunity", UTILITY="Utility",
}

-- ── Profile export/import scratch state (dialog-local, not saved) ──
local newProfileNameVal = ""

local function SerializeProfile(p)
    local parts = {}
    for sid, v in pairs(p.enabled or {}) do
        if v then table.insert(parts, "e" .. sid) end
    end
    for ct, v in pairs(p.contentTypes or {}) do
        if v then table.insert(parts, "c" .. ct:gsub(" ", "_")) end
    end
    table.sort(parts)
    return string.format("KCD3:%d:%d:%d:%d:%s",
        p.offsetX or 0, p.offsetY or 0, p.iconSize or 22, p.iconsPerRow or 5,
        table.concat(parts, ","))
end

-- Deserialise — KCD3 is current; KCD1/KCD2 are legacy (group data ignored)
local function DeserializeProfile(str)
    local p = type(NewProfileData) == "function" and NewProfileData() or {}
    p.enabled = p.enabled or {}
    local ox, oy, isz, ipr, rest =
        str:match("^KCD3:(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(.*)$")
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
    for tok in ((rest or "") .. ","):gmatch("([^,]*),") do
        if tok ~= "" then
            local k, v = tok:sub(1, 1), tok:sub(2)
            if k == "e" then
                local sid = tonumber(v)
                if sid then p.enabled[sid] = true end
            elseif k == "c" then
                p.contentTypes[v:gsub("_", " ")] = true
            end
        end
    end
    return p
end

local function NotifyRefresh()
    LibStub("AceConfigRegistry-3.0"):NotifyChange("KastaCD")
end

-- =============================================================
-- Settings group (offsets, icon layout, misc toggles, content types)
-- =============================================================
local function BuildSettingsGroup()
    local args = {
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
        growLeft = {
            type = "toggle", order = 50, name = "Grow Left",
            get = function() return KastaCDDB.growLeft == true end,
            set = function(_, v) KastaCDDB.growLeft = v; if type(RebuildIcons) == "function" then RebuildIcons() end end,
        },
        miscHeader = { type = "header", order = 60, name = "Misc" },
        pvpMedallion = {
            type = "toggle", order = 70, name = "PvP Medallion",
            get = function() return KastaCDDB.enabled[208683] == true end,
            set = function(_, v)
                KastaCDDB.enabled[208683] = v and true or nil
                if type(RebuildIcons) == "function" then RebuildIcons() end
            end,
        },
        medallionOutsidePvP = {
            type = "toggle", order = 80, name = "Medallion outside PvP",
            get = function() return KastaCDDB.medallionOutsidePvP == true end,
            set = function(_, v)
                KastaCDDB.medallionOutsidePvP = v and true or false
                if type(RebuildIcons) == "function" then RebuildIcons() end
            end,
        },
        showIconBorders = {
            type = "toggle", order = 90, name = "Icon Borders",
            get = function() return KastaCDDB.showIconBorders == true end,
            set = function(_, v)
                KastaCDDB.showIconBorders = v and true or false
                if type(ApplyIconBorders) == "function" then ApplyIconBorders() end
            end,
        },
        contentHeader = { type = "header", order = 100, name = "Active in" },
    }

    local ctOrder = 110
    for _, ct in ipairs(CONTENT_TYPES or {}) do
        local ctName = ct
        args["content_" .. ctName:gsub(" ", "_")] = {
            type = "toggle", order = ctOrder, name = ctName,
            get = function() return KastaCDDB.contentTypes[ctName] == true end,
            set = function(_, v)
                KastaCDDB.contentTypes[ctName] = v
                if type(RebuildIcons) == "function" then RebuildIcons() end
            end,
        }
        ctOrder = ctOrder + 10
    end

    return { type = "group", name = "Settings", order = 10, args = args }
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

    local args = {
        enabled = {
            type = "toggle", order = 10, name = "Enable",
            get = function() return GetAnchorDB().enabled ~= false end,
            set = function(_, v)
                GetAnchorDB().enabled = v and true or false
                if type(opts.RebuildFn) == "function" then opts.RebuildFn() end
            end,
        },
        testMode = {
            type = "toggle", order = 20, name = "Test Mode",
            get = function() return GetAnchorDB().testMode == true end,
            set = function(_, v)
                GetAnchorDB().testMode = v and true or false
                if type(opts.RebuildFn) == "function" then opts.RebuildFn() end
            end,
        },
        barWidth = {
            type = "range", order = 30, name = "Bar Width", min = 100, max = 400, step = 1,
            get = function() return GetAnchorDB().barWidth or 200 end,
            set = function(_, v)
                GetAnchorDB().barWidth = v
                if type(opts.RebuildFn) == "function" then opts.RebuildFn() end
            end,
        },
        barHeight = {
            type = "range", order = 40, name = "Bar Height", min = 14, max = 40, step = 1,
            get = function() return GetAnchorDB().barHeight or 20 end,
            set = function(_, v)
                GetAnchorDB().barHeight = v
                if type(opts.RebuildFn) == "function" then opts.RebuildFn() end
            end,
        },
        positionX = {
            type = "range", order = 50, name = "Position X", min = -2000, max = 2000, step = 1,
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
            type = "range", order = 60, name = "Position Y", min = -2000, max = 2000, step = 1,
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
        font = {
            type = "select", order = 70, name = "Font",
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
            type = "select", order = 80, name = "Texture",
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
            type = "range", order = 90, name = "Font Size", min = 8, max = 18, step = 1,
            get = function() return GetAnchorDB().fontSize or 10 end,
            set = function(_, v)
                GetAnchorDB().fontSize = v
                if type(opts.RebuildFn) == "function" then opts.RebuildFn() end
            end,
        },
        locked = {
            type = "toggle", order = 100, name = "Unlock Anchor (drag to reposition)",
            get = function() return GetAnchorDB().locked == false end,
            set = function(_, v)
                if v then
                    if type(opts.UnlockFn) == "function" then opts.UnlockFn() end
                else
                    if type(opts.LockFn) == "function" then opts.LockFn() end
                end
            end,
        },
        hideBorder = {
            type = "toggle", order = 110, name = "Hide Border",
            get = function() return GetAnchorDB().hideBorder == true end,
            set = function(_, v)
                GetAnchorDB().hideBorder = v and true or false
                if type(opts.RebuildFn) == "function" then opts.RebuildFn() end
            end,
        },
    }

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
            type = "execute", order = 60, name = "Copy Current As New",
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
                NotifyRefresh()
                print("KastaCD: Imported as '" .. nm .. "'.")
            end,
        },
    }

    return { type = "group", name = "Profiles", order = 500, args = args }
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
                    name = string.format("|T%s:16|t %s", tostring(icon), data.name),
                    desc = data.name,
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
        args = args,
    }
end

-- =============================================================
-- BuildKastaCDOptions  –  top-level tree
-- =============================================================
function BuildKastaCDOptions()
    local args = {
        settings = BuildSettingsGroup(),
        interrupts = BuildAnchorGroup{
            name = "Interrupt Tracker", order = 20, dbField = "intAnchor",
            RebuildFn = RebuildInterruptBars, GetPos = GetIntAnchorPos, SetPos = SetIntAnchorPos,
            LockFn = LockIntAnchor, UnlockFn = UnlockIntAnchor,
        },
        crowdcontrol = BuildAnchorGroup{
            name = "Crowd Control Tracker", order = 30, dbField = "ccAnchor",
            RebuildFn = RebuildCCBars, GetPos = GetCCAnchorPos, SetPos = SetCCAnchorPos,
            LockFn = LockCCAnchor, UnlockFn = UnlockCCAnchor,
        },
        profiles = BuildProfilesGroup(),
    }

    local classOrder = 100
    for _, ci in ipairs(CLASS_INFO or {}) do
        args[ci.key] = BuildClassGroup(ci, classOrder)
        classOrder = classOrder + 10
    end

    return {
        type = "group",
        name = string.format("Kasta|cffff7f00CD|r – Party Cooldowns  |cff808080v%s|r",
            tostring(KASTACD_VERSION or "?")),
        childGroups = "tree",
        args = args,
    }
end
