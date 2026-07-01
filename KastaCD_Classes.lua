-- =============================================================
-- KastaCD_Classes.lua
-- All class spell definitions merged into one file.
-- Appends to the shared global SPELL_DB table declared in
-- KastaCD_SpellDB.lua (which loads before this file).
-- =============================================================

SPELL_DB = SPELL_DB or {}

-- ── WARRIOR ──────────────────────────────────────────────────
SPELL_DB[871]    = { name="Shield Wall",          class="WARRIOR", icon=132362, duration=8,  cooldown=240, category="DEFENSIVE", specs={73},        minLevel=66 }
SPELL_DB[1160]   = { name="Demoralizing Shout",   class="WARRIOR", icon=132366, duration=8,  cooldown=45,  category="DEFENSIVE", specs={73},        minLevel=14 }
SPELL_DB[97462]  = { name="Rallying Cry",          class="WARRIOR", icon=132351, duration=10, cooldown=180, category="DEFENSIVE",                    minLevel=80 }
SPELL_DB[6552]   = { name="Pummel",                class="WARRIOR", icon=132938, duration=0,  cooldown=15,  category="INTERRUPT",                    minLevel=7  }
SPELL_DB[3411]   = { name="Intervene",             class="WARRIOR", icon=132365, duration=0,  cooldown=30,  category="UTILITY",                      minLevel=22 }
SPELL_DB[23920]  = { name="Spell Reflection",      class="WARRIOR", icon=132361, duration=5,  cooldown=25,  category="DEFENSIVE", specs={73},        minLevel=10 }
SPELL_DB[107570] = { name="Storm Bolt",            class="WARRIOR", icon=613534, duration=3,  cooldown=30,  category="UTILITY",   isTalent=true      }
SPELL_DB[1719]   = { name="Recklessness",          class="WARRIOR", icon=132109, duration=10, cooldown=90,  category="OFFENSIVE", specs={71,72},     minLevel=10 }
SPELL_DB[107574] = { name="Avatar",                class="WARRIOR", icon=613534, duration=20, cooldown=90,  category="OFFENSIVE", specs={71,73},     isTalent=true }
SPELL_DB[227847] = { name="Bladestorm",            class="WARRIOR", icon=132357, duration=6,  cooldown=60,  category="OFFENSIVE", specs={71},        isTalent=true }
SPELL_DB[118038] = { name="Die by the Sword",      class="WARRIOR", icon=132338, duration=8,  cooldown=90,  category="DEFENSIVE", specs={71},        minLevel=10 }
SPELL_DB[12975]  = { name="Last Stand",            class="WARRIOR", icon=135871, duration=15, cooldown=180, category="DEFENSIVE", specs={73},        minLevel=10 }
SPELL_DB[198304] = { name="Intercept",             class="WARRIOR", icon=132938, duration=3,  cooldown=30,  category="UTILITY",   specs={72},        minLevel=10 }

-- ── PALADIN ───────────────────────────────────────────────────
SPELL_DB[498]    = { name="Divine Protection",     class="PALADIN", icon=524353, duration=8,  cooldown=60,  category="DEFENSIVE",                    minLevel=10 }
SPELL_DB[633]    = { name="Lay on Hands",          class="PALADIN", icon=135928, duration=0,  cooldown=600, category="DEFENSIVE",                    minLevel=14 }
SPELL_DB[642]    = { name="Divine Shield",         class="PALADIN", icon=524354, duration=8,  cooldown=300, category="IMMUNITY",                     minLevel=18 }
SPELL_DB[1022]   = { name="Blessing of Protection",class="PALADIN", icon=135964, duration=10, cooldown=300, category="IMMUNITY",                     minLevel=4  }
SPELL_DB[96231]  = { name="Rebuke",                class="PALADIN", icon=523893, duration=0,  cooldown=15,  category="INTERRUPT",                    minLevel=10 }
SPELL_DB[853]    = { name="Hammer of Justice",     class="PALADIN", icon=135963, duration=6,  cooldown=60,  category="UTILITY",                      minLevel=4  }
SPELL_DB[6940]   = { name="Blessing of Sacrifice", class="PALADIN", icon=135966, duration=12, cooldown=120, category="DEFENSIVE",                    minLevel=22 }
SPELL_DB[31821]  = { name="Aura Mastery",          class="PALADIN", icon=135872, duration=8,  cooldown=180, category="DEFENSIVE", specs={65},        minLevel=10 }
SPELL_DB[31884]  = { name="Avenging Wrath",        class="PALADIN", icon=135875, duration=20, cooldown=120, category="OFFENSIVE", specs={65,70},     minLevel=10 }
SPELL_DB[31935]  = { name="Avenger's Shield",      class="PALADIN", icon=135874, duration=0,  cooldown=15,  category="INTERRUPT", specs={66},        minLevel=10 }
SPELL_DB[31850]  = { name="Ardent Defender",       class="PALADIN", icon=236264, duration=8,  cooldown=90,  category="DEFENSIVE", specs={66},        minLevel=10 }
SPELL_DB[184662] = { name="Shield of Vengeance",   class="PALADIN", icon=614521, duration=15, cooldown=120, category="DEFENSIVE", specs={70},        minLevel=10 }

-- ── HUNTER ───────────────────────────────────────────────────
SPELL_DB[109304] = { name="Exhilaration",          class="HUNTER",  icon=132121, duration=0,  cooldown=120, category="DEFENSIVE",                    minLevel=22 }
SPELL_DB[186265] = { name="Aspect of the Turtle",  class="HUNTER",  icon=132199, duration=8,  cooldown=180, category="IMMUNITY",                     minLevel=10 }
SPELL_DB[187650] = { name="Freezing Trap",         class="HUNTER",  icon=135834, duration=8,  cooldown=30,  category="UTILITY",                      minLevel=14 }
SPELL_DB[5384]   = { name="Feign Death",           class="HUNTER",  icon=132293, duration=0,  cooldown=30,  category="UTILITY",                      minLevel=30 }
SPELL_DB[147362] = { name="Counter Shot",          class="HUNTER",  icon=249170, duration=0,  cooldown=24,  category="INTERRUPT", specs={253,254},   minLevel=10 }
SPELL_DB[187707] = { name="Muzzle",                class="HUNTER",  icon=132312, duration=0,  cooldown=15,  category="INTERRUPT", specs={255},       minLevel=10 }
SPELL_DB[109248] = { name="Binding Shot",          class="HUNTER",  icon=463285, duration=3,  cooldown=45,  category="UTILITY",   specs={253,254},   isTalent=true }
SPELL_DB[19574]  = { name="Bestial Wrath",         class="HUNTER",  icon=132127, duration=15, cooldown=90,  category="OFFENSIVE", specs={253},       minLevel=10 }
SPELL_DB[193526] = { name="Trueshot",              class="HUNTER",  icon=613345, duration=15, cooldown=180, category="OFFENSIVE", specs={254},       minLevel=10 }
SPELL_DB[202800] = { name="Flanking Strike",       class="HUNTER",  icon=1380856,duration=0,  cooldown=30,  category="OFFENSIVE", specs={255},       minLevel=10 }

-- ── ROGUE ─────────────────────────────────────────────────────
SPELL_DB[1966]   = { name="Feint",                 class="ROGUE",   icon=132294, duration=5,  cooldown=15,  category="DEFENSIVE",                    minLevel=20 }
SPELL_DB[5277]   = { name="Evasion",               class="ROGUE",   icon=136205, duration=10, cooldown=120, category="DEFENSIVE",                    minLevel=22 }
SPELL_DB[31224]  = { name="Cloak of Shadows",      class="ROGUE",   icon=136177, duration=5,  cooldown=60,  category="IMMUNITY",                     minLevel=66 }
SPELL_DB[1766]   = { name="Kick",                  class="ROGUE",   icon=132219, duration=0,  cooldown=15,  category="INTERRUPT",                    minLevel=18 }
SPELL_DB[2094]   = { name="Blind",                 class="ROGUE",   icon=136175, duration=60, cooldown=120, category="UTILITY",                      minLevel=14 }
SPELL_DB[1856]   = { name="Vanish",                class="ROGUE",   icon=132331, duration=3,  cooldown=120, category="DEFENSIVE",                    minLevel=22 }
SPELL_DB[79140]  = { name="Vendetta",              class="ROGUE",   icon=132292, duration=20, cooldown=120, category="OFFENSIVE", specs={259},       minLevel=10 }
SPELL_DB[13750]  = { name="Adrenaline Rush",       class="ROGUE",   icon=136206, duration=20, cooldown=180, category="OFFENSIVE", specs={260},       minLevel=10 }
SPELL_DB[13877]  = { name="Blade Flurry",          class="ROGUE",   icon=132298, duration=12, cooldown=30,  category="OFFENSIVE", specs={260},       minLevel=10 }
SPELL_DB[121471] = { name="Shadow Blades",         class="ROGUE",   icon=606542, duration=20, cooldown=180, category="OFFENSIVE", specs={261},       minLevel=10 }
SPELL_DB[185313] = { name="Shadow Dance",          class="ROGUE",   icon=458726, duration=8,  cooldown=60,  category="OFFENSIVE", specs={261},       minLevel=10 }

-- ── PRIEST ────────────────────────────────────────────────────
SPELL_DB[8122]   = { name="Psychic Scream",        class="PRIEST",  icon=136184, duration=8,  cooldown=45,  category="UTILITY",                      minLevel=14 }
SPELL_DB[586]    = { name="Fade",                  class="PRIEST",  icon=135994, duration=10, cooldown=30,  category="DEFENSIVE",                    minLevel=10 }
SPELL_DB[33206]  = { name="Pain Suppression",      class="PRIEST",  icon=135936, duration=8,  cooldown=180, category="DEFENSIVE", specs={256},       minLevel=10 }
SPELL_DB[19236]  = { name="Desperate Prayer",      class="PRIEST",  icon=135955, duration=0,  cooldown=90,  category="DEFENSIVE", isTalent=true      }
SPELL_DB[47536]  = { name="Rapture",               class="PRIEST",  icon=135936, duration=8,  cooldown=90,  category="DEFENSIVE", specs={256},       minLevel=10 }
SPELL_DB[64843]  = { name="Divine Hymn",           class="PRIEST",  icon=135983, duration=8,  cooldown=180, category="DEFENSIVE", specs={257},       minLevel=10 }
SPELL_DB[62618]  = { name="Power Word: Barrier",   class="PRIEST",  icon=253400, duration=10, cooldown=180, category="DEFENSIVE", specs={256},       minLevel=10 }
SPELL_DB[47788]  = { name="Guardian Spirit",       class="PRIEST",  icon=135940, duration=10, cooldown=180, category="DEFENSIVE", specs={257},       minLevel=10 }
SPELL_DB[15487]  = { name="Silence",               class="PRIEST",  icon=136207, duration=5,  cooldown=45,  category="INTERRUPT", specs={258},       minLevel=10 }
SPELL_DB[65544]  = { name="Dispersion",            class="PRIEST",  icon=237563, duration=6,  cooldown=120, category="IMMUNITY",  specs={258},       minLevel=83 }

-- ── DEATH KNIGHT ──────────────────────────────────────────────
SPELL_DB[47476]  = { name="Strangulate",           class="DEATHKNIGHT", icon=136214, duration=5,  cooldown=60,  category="INTERRUPT",              minLevel=55 }
SPELL_DB[47528]  = { name="Mind Freeze",           class="DEATHKNIGHT", icon=237524, duration=0,  cooldown=15,  category="INTERRUPT",              minLevel=55 }
SPELL_DB[48792]  = { name="Icebound Fortitude",    class="DEATHKNIGHT", icon=237525, duration=8,  cooldown=180, category="DEFENSIVE",              minLevel=55 }
SPELL_DB[49039]  = { name="Lichborne",             class="DEATHKNIGHT", icon=136187, duration=10, cooldown=120, category="DEFENSIVE",              minLevel=55 }
SPELL_DB[48707]  = { name="Anti-Magic Shell",      class="DEATHKNIGHT", icon=136120, duration=5,  cooldown=60,  category="IMMUNITY",               minLevel=55 }
SPELL_DB[55233]  = { name="Vampiric Blood",        class="DEATHKNIGHT", icon=136168, duration=10, cooldown=90,  category="DEFENSIVE", specs={250}, minLevel=55 }
SPELL_DB[49028]  = { name="Dancing Rune Weapon",   class="DEATHKNIGHT", icon=135277, duration=8,  cooldown=120, category="OFFENSIVE", specs={250}, minLevel=55 }
SPELL_DB[51052]  = { name="Anti-Magic Zone",       class="DEATHKNIGHT", icon=136176, duration=10, cooldown=120, category="DEFENSIVE", specs={250}, isTalent=true }
SPELL_DB[207289] = { name="Unholy Frenzy",         class="DEATHKNIGHT", icon=136224, duration=30, cooldown=75,  category="OFFENSIVE", specs={252}, minLevel=55 }
SPELL_DB[42650]  = { name="Army of the Dead",      class="DEATHKNIGHT", icon=237511, duration=0,  cooldown=480, category="OFFENSIVE", specs={252}, minLevel=55 }
SPELL_DB[49206]  = { name="Summon Gargoyle",       class="DEATHKNIGHT", icon=458967, duration=30, cooldown=180, category="OFFENSIVE", specs={252}, minLevel=55 }

-- ── SHAMAN ────────────────────────────────────────────────────
SPELL_DB[57994]  = { name="Wind Shear",                  class="SHAMAN", icon=136018, duration=0,  cooldown=12,  category="INTERRUPT",              minLevel=18 }
SPELL_DB[108271] = { name="Astral Shift",                class="SHAMAN", icon=538565, duration=8,  cooldown=90,  category="DEFENSIVE",              minLevel=22 }
SPELL_DB[108280] = { name="Healing Tide Totem",          class="SHAMAN", icon=538569, duration=10, cooldown=180, category="DEFENSIVE", specs={264}, minLevel=10 }
SPELL_DB[98008]  = { name="Spirit Link Totem",           class="SHAMAN", icon=237586, duration=6,  cooldown=180, category="DEFENSIVE", specs={264}, minLevel=10 }
SPELL_DB[16191]  = { name="Mana Tide Totem",             class="SHAMAN", icon=538573, duration=12, cooldown=180, category="DEFENSIVE", specs={264}, minLevel=10 }
SPELL_DB[114050] = { name="Ascendance",                  class="SHAMAN", icon=571590, duration=15, cooldown=180, category="OFFENSIVE", isTalent=true }
SPELL_DB[51533]  = { name="Feral Spirit",                class="SHAMAN", icon=237577, duration=30, cooldown=120, category="OFFENSIVE", specs={263}, minLevel=10 }
SPELL_DB[192077] = { name="Wind Rush Totem",             class="SHAMAN", icon=538568, duration=15, cooldown=120, category="UTILITY",  isTalent=true }
SPELL_DB[207399] = { name="Ancestral Protection Totem",  class="SHAMAN", icon=839977, duration=30, cooldown=300, category="DEFENSIVE", specs={264}, isTalent=true }

-- ── MAGE ──────────────────────────────────────────────────────
SPELL_DB[2139]   = { name="Counterspell",          class="MAGE", icon=135856, duration=0,  cooldown=24,  category="INTERRUPT",              minLevel=22 }
SPELL_DB[45438]  = { name="Ice Block",             class="MAGE", icon=135841, duration=10, cooldown=240, category="IMMUNITY",               minLevel=22 }
SPELL_DB[110959] = { name="Greater Invisibility",  class="MAGE", icon=575584, duration=20, cooldown=120, category="DEFENSIVE", isTalent=true }
SPELL_DB[12042]  = { name="Arcane Power",          class="MAGE", icon=136048, duration=10, cooldown=90,  category="OFFENSIVE", specs={62},  minLevel=10 }
SPELL_DB[190319] = { name="Combustion",            class="MAGE", icon=135824, duration=10, cooldown=120, category="OFFENSIVE", specs={63},  minLevel=10 }
SPELL_DB[12472]  = { name="Icy Veins",             class="MAGE", icon=135838, duration=20, cooldown=180, category="OFFENSIVE", specs={64},  minLevel=10 }
SPELL_DB[113724] = { name="Ring of Frost",         class="MAGE", icon=464484, duration=10, cooldown=45,  category="UTILITY",  isTalent=true }
SPELL_DB[235219] = { name="Cold Snap",             class="MAGE", icon=135865, duration=0,  cooldown=300, category="DEFENSIVE", specs={64}, isTalent=true }

-- ── WARLOCK ───────────────────────────────────────────────────
SPELL_DB[104773] = { name="Unending Resolve",      class="WARLOCK", icon=136150, duration=8,  cooldown=180, category="DEFENSIVE", minLevel=10  }
SPELL_DB[5484]   = { name="Howl of Terror",        class="WARLOCK", icon=136175, duration=20, cooldown=40,  category="UTILITY",  isTalent=true }
SPELL_DB[111898] = { name="Grimoire of Sacrifice", class="WARLOCK", icon=538443, duration=0,  cooldown=30,  category="UTILITY",  isTalent=true }
SPELL_DB[152108] = { name="Cataclysm",             class="WARLOCK", icon=452693, duration=0,  cooldown=30,  category="OFFENSIVE", isTalent=true }
SPELL_DB[108416] = { name="Dark Pact",             class="WARLOCK", icon=538569, duration=20, cooldown=60,  category="DEFENSIVE", isTalent=true }

-- ── MONK ──────────────────────────────────────────────────────
SPELL_DB[116705] = { name="Spear Hand Strike",            class="MONK", icon=608939, duration=0,  cooldown=15,  category="INTERRUPT",                        minLevel=14 }
SPELL_DB[122278] = { name="Dampen Harm",                  class="MONK", icon=620827, duration=10, cooldown=120, category="DEFENSIVE", specs={268,269,270},   isTalent=true }
SPELL_DB[122783] = { name="Diffuse Magic",                class="MONK", icon=775460, duration=6,  cooldown=90,  category="DEFENSIVE", specs={268,269,270},   isTalent=true }
SPELL_DB[116849] = { name="Life Cocoon",                  class="MONK", icon=627485, duration=12, cooldown=180, category="DEFENSIVE", specs={270},           minLevel=10 }
SPELL_DB[115203] = { name="Fortifying Brew",              class="MONK", icon=627486, duration=15, cooldown=360, category="DEFENSIVE", specs={268},           minLevel=10 }
SPELL_DB[115176] = { name="Zen Meditation",               class="MONK", icon=642417, duration=8,  cooldown=300, category="IMMUNITY",  specs={270},           minLevel=10 }
SPELL_DB[137639] = { name="Storm, Earth, and Fire",       class="MONK", icon=642418, duration=15, cooldown=90,  category="OFFENSIVE", specs={269},           minLevel=10 }
SPELL_DB[123904] = { name="Invoke Xuen, the White Tiger", class="MONK", icon=620832, duration=20, cooldown=120, category="OFFENSIVE", specs={269},           minLevel=10 }

-- ── DRUID ─────────────────────────────────────────────────────
SPELL_DB[106839] = { name="Skull Bash",            class="DRUID", icon=236946,  duration=0,  cooldown=15,  category="INTERRUPT", specs={103,104},     minLevel=10 }
SPELL_DB[22812]  = { name="Barkskin",              class="DRUID", icon=136097,  duration=12, cooldown=60,  category="DEFENSIVE",                      minLevel=10 }
SPELL_DB[99]     = { name="Incapacitating Roar",   class="DRUID", icon=236937,  duration=3,  cooldown=30,  category="UTILITY",   specs={104},         minLevel=10 }
SPELL_DB[61336]  = { name="Survival Instincts",    class="DRUID", icon=236169,  duration=6,  cooldown=180, category="DEFENSIVE", specs={103,104},     minLevel=10 }
SPELL_DB[740]    = { name="Tranquility",           class="DRUID", icon=136107,  duration=8,  cooldown=180, category="DEFENSIVE", specs={105},         minLevel=10 }
SPELL_DB[102342] = { name="Ironbark",              class="DRUID", icon=572025,  duration=12, cooldown=90,  category="DEFENSIVE", specs={105},         minLevel=10 }
SPELL_DB[29166]  = { name="Innervate",             class="DRUID", icon=136048,  duration=10, cooldown=180, category="UTILITY",   specs={102,105},     minLevel=10 }
SPELL_DB[106951] = { name="Berserk",               class="DRUID", icon=236149,  duration=15, cooldown=180, category="OFFENSIVE", specs={103,104},     minLevel=10 }
SPELL_DB[194223] = { name="Celestial Alignment",   class="DRUID", icon=1396760, duration=20, cooldown=180, category="OFFENSIVE", specs={102},         minLevel=10 }

-- ── DEMON HUNTER ─────────────────────────────────────────────
SPELL_DB[183752] = { name="Consume Magic",         class="DEMONHUNTER", icon=1344654, duration=0,  cooldown=10,  category="UTILITY",                     minLevel=98 }
SPELL_DB[179057] = { name="Chaos Nova",            class="DEMONHUNTER", icon=1247261, duration=5,  cooldown=60,  category="UTILITY",                     minLevel=98 }
SPELL_DB[198589] = { name="Blur",                  class="DEMONHUNTER", icon=1305150, duration=10, cooldown=60,  category="DEFENSIVE", specs={577},      minLevel=98 }
SPELL_DB[209426] = { name="Darkness",              class="DEMONHUNTER", icon=1305149, duration=8,  cooldown=300, category="DEFENSIVE", specs={577},      minLevel=98 }
SPELL_DB[196555] = { name="Netherwalk",            class="DEMONHUNTER", icon=1220127, duration=5,  cooldown=180, category="IMMUNITY",  specs={577},      isTalent=true }
SPELL_DB[187827] = { name="Metamorphosis",         class="DEMONHUNTER", icon=1247262, duration=30, cooldown=300, category="OFFENSIVE", specs={577},      minLevel=98 }
SPELL_DB[203720] = { name="Demon Spikes",          class="DEMONHUNTER", icon=1305154, duration=6,  cooldown=20,  category="DEFENSIVE", specs={581},      minLevel=98 }
SPELL_DB[204021] = { name="Fiery Brand",           class="DEMONHUNTER", icon=1305156, duration=8,  cooldown=60,  category="DEFENSIVE", specs={581},      minLevel=98 }
