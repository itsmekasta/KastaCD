-- KastaCD_Announce.lua - optionally shouts a customizable chat message
-- when the player's own interrupt lands. Depends on KastaCD_DB.lua.

local BRAND_SUFFIX     = " - KastaCD"
local DEFAULT_TEMPLATE = "{player} has interrupted {spell}"

-- On by default (Yell) - opt-out rather than opt-in.
function GetAnnounceDB()
    if type(KastaCDDB) ~= "table" then
        return { enabled = true, channel = "YELL", template = DEFAULT_TEMPLATE }
    end
    if type(KastaCDDB.interruptAnnounce) ~= "table" then
        KastaCDDB.interruptAnnounce = {}
    end
    local db = KastaCDDB.interruptAnnounce
    if db.enabled   == nil then db.enabled   = true end
    if db.channel   == nil then db.channel   = "YELL" end
    if db.template  == nil then db.template  = DEFAULT_TEMPLATE end
    db.showBrand = nil
    -- Strip any legacy literal "- KastaCD" text saved inside the template.
    if db.template:sub(-#BRAND_SUFFIX) == BRAND_SUFFIX then
        db.template = db.template:sub(1, -#BRAND_SUFFIX - 1)
    end
    return db
end

function GetDefaultAnnounceTemplate()
    return DEFAULT_TEMPLATE
end

-- Placeholder substitution - {player}/{spell}/{myspell}/{target}. Plain
-- string replacement, so a missing/repeated placeholder never errors.
local function FormatAnnounce(template, vars)
    local msg = template or DEFAULT_TEMPLATE
    msg = msg:gsub("{player}",  vars.player  or "")
    msg = msg:gsub("{spell}",   vars.spell   or "")
    msg = msg:gsub("{myspell}", vars.myspell or "")
    msg = msg:gsub("{target}",  vars.target  or "")
    return msg
end

-- Real clickable spell hyperlink when spellId is known, else plain name.
-- Uses GetSpellLink, not KastaCD's own "kastacd:" links - those get
-- silently stripped by this server's chat sanitization.
local function SpellLinkOrName(spellId, fallbackName)
    if spellId and GetSpellLink then
        local link = GetSpellLink(spellId)
        if link then return link end
    end
    return fallbackName or ""
end

-- interruptedSpellName/interruptedSpellId: the spell that got stopped.
-- mySpellName/mySpellId: the interrupt used. targetName: who was casting it.
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

-- Sample announcement for the "Test" button in Settings.
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
