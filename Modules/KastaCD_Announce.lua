-- =============================================================
-- KastaCD_Announce.lua
-- Interrupt announcement: optionally shouts a customizable chat message
-- whenever the PLAYER's own interrupt lands, so party/raid members who
-- don't have KastaCD (or any interrupt addon) still know a cast just got
-- stopped - and that it came from KastaCD specifically, for visibility.
-- Depends on: KastaCD_DB.lua (KastaCDDB must exist)
-- =============================================================

-- The "- KastaCD" branding is hardcoded and always appended after
-- placeholder substitution (see FormatAnnounce) - it is NOT part of the
-- editable template, by explicit request, so the player can't remove it.
local BRAND_SUFFIX     = " - KastaCD"
local DEFAULT_TEMPLATE = "{player} has interrupted {spell}"

-- -------------------------------------------------------------
-- DB accessor with lazy defaults - same pattern as GetIntDB/GetCCDB in
-- KastaCD_Interrupts.lua/KastaCD_CC.lua.
-- -------------------------------------------------------------
-- On by default (Yell) - the player has to manually opt out rather than
-- opt in, per an explicit request to make this the default behavior.
function GetAnnounceDB()
    if type(KastaCDDB) ~= "table" then
        return { enabled = true, channel = "YELL", template = DEFAULT_TEMPLATE }
    end
    if type(KastaCDDB.interruptAnnounce) ~= "table" then
        KastaCDDB.interruptAnnounce = {}
    end
    local db = KastaCDDB.interruptAnnounce
    if db.enabled  == nil then db.enabled  = true end
    if db.channel  == nil then db.channel  = "YELL" end
    if db.template == nil then db.template = DEFAULT_TEMPLATE end
    -- One-time migration: earlier versions saved "- KastaCD" as literal
    -- text inside the editable template. Strip it so it isn't duplicated
    -- now that the suffix is always appended automatically instead.
    if db.template:sub(-#BRAND_SUFFIX) == BRAND_SUFFIX then
        db.template = db.template:sub(1, -#BRAND_SUFFIX - 1)
    end
    return db
end

function GetDefaultAnnounceTemplate()
    return DEFAULT_TEMPLATE
end

-- -------------------------------------------------------------
-- Placeholder substitution - {player}/{spell}/{myspell}/{target} - plus
-- the hardcoded " - KastaCD" brand suffix, always appended last and
-- unconditionally, regardless of what the user's template contains.
-- Plain string replacement (not a format string), so a template that
-- omits a placeholder, repeats one, or is missing entirely from the
-- saved DB (fresh install) all still work without erroring.
-- -------------------------------------------------------------
local function FormatAnnounce(template, vars)
    local msg = template or DEFAULT_TEMPLATE
    msg = msg:gsub("{player}",  vars.player  or "")
    msg = msg:gsub("{spell}",   vars.spell   or "")
    msg = msg:gsub("{myspell}", vars.myspell or "")
    msg = msg:gsub("{target}",  vars.target  or "")
    return msg .. BRAND_SUFFIX
end

-- Real, clickable spell hyperlink (shows the actual spell tooltip on
-- hover/click, exactly like any spell link a player shift-clicks into
-- chat) when a spellId is known, falling back to the plain name
-- otherwise. GetSpellLink is a real Blizzard API/link type, unlike
-- KastaCD's own custom "kastacd:" chat links - those turned out to get
-- silently stripped by this server's chat sanitization, but spell links
-- are a first-class, universally-supported hyperlink type servers can't
-- reasonably break without breaking normal spell-linking too.
local function SpellLinkOrName(spellId, fallbackName)
    if spellId and GetSpellLink then
        local link = GetSpellLink(spellId)
        if link then return link end
    end
    return fallbackName or ""
end

-- interruptedSpellName/interruptedSpellId: the spell that got stopped
-- (SPELL_INTERRUPT's extraSpellName/extraSpellId). mySpellName/mySpellId:
-- the interrupt ability used (Kick, Rebuke, etc). targetName: who was
-- casting it.
function AnnounceInterrupt(mySpellName, interruptedSpellName, targetName, interruptedSpellId, mySpellId)
    local db = GetAnnounceDB()
    if not db.enabled then return end
    if not interruptedSpellName or interruptedSpellName == "" then return end

    local msg = FormatAnnounce(db.template, {
        player  = UnitName("player"),
        spell   = SpellLinkOrName(interruptedSpellId, interruptedSpellName),
        myspell = SpellLinkOrName(mySpellId, mySpellName),
        target  = targetName or "",
    })
    SendChatMessage(msg, db.channel or "SAY")
end

-- Fires a sample announcement using the current template/channel, for the
-- "Test" button in Settings - lets the user preview their customized
-- message without needing to land a real interrupt first. Uses two real,
-- well-known spell IDs (Pummel, Fireball) rather than fake names, so the
-- preview also demonstrates the clickable spell-link/tooltip behavior.
function TestAnnounceInterrupt()
    local db = GetAnnounceDB()
    local msg = FormatAnnounce(db.template, {
        player  = UnitName("player"),
        spell   = SpellLinkOrName(133, "Test Spell"),      -- Fireball
        myspell = SpellLinkOrName(6552, "Test Interrupt"), -- Pummel
        target  = "Target Dummy",
    })
    SendChatMessage(msg, db.channel or "SAY")
end
