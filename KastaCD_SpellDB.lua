-- =============================================================
-- KastaCD_SpellDB.lua
-- Static data: spell definitions, class info, position configs,
-- subtab definitions, and other compile-time constants.
-- No WoW API calls here — pure data tables.
--
-- specs field: list of spec IDs that have this ability.
-- nil/absent = all specs of that class share this spell.
-- Spec IDs (7.3.5):
--   WARRIOR:     71=Arms, 72=Fury, 73=Protection
--   PALADIN:     65=Holy, 66=Protection, 70=Retribution
--   HUNTER:     253=Beast Mastery, 254=Marksmanship, 255=Survival
--   ROGUE:      259=Assassination, 260=Outlaw, 261=Subtlety
--   PRIEST:     256=Discipline, 257=Holy, 258=Shadow
--   DEATHKNIGHT:250=Blood, 251=Frost, 252=Unholy
--   SHAMAN:     262=Elemental, 263=Enhancement, 264=Restoration
--   MAGE:       62=Arcane, 63=Fire, 64=Frost
--   WARLOCK:    265=Affliction, 266=Demonology, 267=Destruction
--   MONK:       268=Brewmaster, 269=Windwalker, 270=Mistweaver
--   DRUID:      102=Balance, 103=Feral, 104=Guardian, 105=Restoration
--   DEMONHUNTER:577=Havoc, 581=Vengeance
-- =============================================================

SPELL_DB = {
    -- ── WARRIOR ─────────────────────────────────────────────────
    -- Shared (all specs)
    [871]    = { name="Shield Wall",          class="WARRIOR", icon=132362,  duration=8,  cooldown=240, category="DEFENSIVE" },  -- Prot baseline; Arms/Fury get it via talent but it's broadly shared
    [1160]   = { name="Demoralizing Shout",   class="WARRIOR", icon=132366,  duration=8,  cooldown=45,  category="DEFENSIVE" },  -- All specs
    [97462]  = { name="Rallying Cry",         class="WARRIOR", icon=132351,  duration=10, cooldown=180, category="DEFENSIVE" },  -- All specs
    [6552]   = { name="Pummel",               class="WARRIOR", icon=132938,  duration=0,  cooldown=15,  category="INTERRUPT" },  -- All specs
    [3411]   = { name="Intervene",            class="WARRIOR", icon=132365,  duration=0,  cooldown=30,  category="UTILITY"   },  -- All specs
    -- Spec-specific
    [23920]  = { name="Spell Reflection",     class="WARRIOR", icon=132361,  duration=5,  cooldown=25,  category="DEFENSIVE", specs={73}       },  -- Protection only
    [107570] = { name="Storm Bolt",           class="WARRIOR", icon=613534,  duration=3,  cooldown=30,  category="UTILITY",   specs={71,72}    },  -- Arms/Fury talent
    [1719]   = { name="Recklessness",         class="WARRIOR", icon=132109,  duration=10, cooldown=90,  category="OFFENSIVE", specs={71,72}    },  -- Arms/Fury
    [107574] = { name="Avatar",               class="WARRIOR", icon=613534,  duration=20, cooldown=90,  category="OFFENSIVE", specs={71,73}    },  -- Arms/Prot talent
    [227847] = { name="Bladestorm",           class="WARRIOR", icon=132357,  duration=6,  cooldown=60,  category="OFFENSIVE", specs={71}       },  -- Arms only
    [118038] = { name="Die by the Sword",     class="WARRIOR", icon=132338,  duration=8,  cooldown=90,  category="DEFENSIVE", specs={71}       },  -- Arms only
    [12975]  = { name="Last Stand",           class="WARRIOR", icon=135871,  duration=15, cooldown=180, category="DEFENSIVE", specs={73}       },  -- Protection only
    [198304] = { name="Intercept",            class="WARRIOR", icon=132938,  duration=3,  cooldown=30,  category="UTILITY",   specs={72}       },  -- Fury only
    -- ── PALADIN ─────────────────────────────────────────────────
    -- Shared (all specs)
    [498]    = { name="Divine Protection",        class="PALADIN", icon=524353, duration=8,  cooldown=60,  category="DEFENSIVE" },  -- All specs
    [633]    = { name="Lay on Hands",             class="PALADIN", icon=135928, duration=0,  cooldown=600, category="DEFENSIVE" },  -- All specs
    [642]    = { name="Divine Shield",            class="PALADIN", icon=524354, duration=8,  cooldown=300, category="IMMUNITY"  },  -- All specs
    [1022]   = { name="Blessing of Protection",   class="PALADIN", icon=135964, duration=10, cooldown=300, category="IMMUNITY"  },  -- All specs
    [96231]  = { name="Rebuke",                   class="PALADIN", icon=523893, duration=0,  cooldown=15,  category="INTERRUPT" },  -- All specs
    [853]    = { name="Hammer of Justice",        class="PALADIN", icon=135963, duration=6,  cooldown=60,  category="UTILITY"   },  -- All specs
    [6940]   = { name="Blessing of Sacrifice",    class="PALADIN", icon=135966, duration=12, cooldown=120, category="DEFENSIVE" },  -- All specs
    -- Spec-specific
    [31821]  = { name="Aura Mastery",             class="PALADIN", icon=135872, duration=8,  cooldown=180, category="DEFENSIVE", specs={65}    },  -- Holy only
    [31884]  = { name="Avenging Wrath",           class="PALADIN", icon=135875, duration=20, cooldown=120, category="OFFENSIVE", specs={65,70} },  -- Holy/Ret
    [31935]  = { name="Avenger's Shield",         class="PALADIN", icon=135874, duration=0,  cooldown=15,  category="INTERRUPT", specs={66}    },  -- Protection only
    [31850]  = { name="Ardent Defender",          class="PALADIN", icon=236264, duration=8,  cooldown=90,  category="DEFENSIVE", specs={66}    },  -- Protection only
    [184662] = { name="Shield of Vengeance",      class="PALADIN", icon=614521, duration=15, cooldown=120, category="DEFENSIVE", specs={70}    },  -- Retribution only
    -- ── HUNTER ──────────────────────────────────────────────────
    -- Shared (all specs)
    [109304] = { name="Exhilaration",        class="HUNTER", icon=132121, duration=0,  cooldown=120, category="DEFENSIVE" },  -- All specs
    [186265] = { name="Aspect of the Turtle",class="HUNTER", icon=132199, duration=8,  cooldown=180, category="IMMUNITY"  },  -- All specs
    [187650] = { name="Freezing Trap",       class="HUNTER", icon=135834, duration=8,  cooldown=30,  category="UTILITY"   },  -- All specs
    [5384]   = { name="Feign Death",         class="HUNTER", icon=132293, duration=0,  cooldown=30,  category="UTILITY"   },  -- All specs
    -- Spec-specific
    [147362] = { name="Counter Shot",        class="HUNTER", icon=249170, duration=0,  cooldown=24,  category="INTERRUPT", specs={253,254}  },  -- BM/MM (Survival uses Muzzle)
    [187707] = { name="Muzzle",              class="HUNTER", icon=132312, duration=0,  cooldown=15,  category="INTERRUPT", specs={255}      },  -- Survival only
    [109248] = { name="Binding Shot",        class="HUNTER", icon=463285, duration=3,  cooldown=45,  category="UTILITY",   specs={253,254}  },  -- BM/MM talent
    [19574]  = { name="Bestial Wrath",       class="HUNTER", icon=132127, duration=15, cooldown=90,  category="OFFENSIVE", specs={253}      },  -- Beast Mastery only
    [193526] = { name="Trueshot",            class="HUNTER", icon=613345, duration=15, cooldown=180, category="OFFENSIVE", specs={254}      },  -- Marksmanship only
    [202800] = { name="Flanking Strike",     class="HUNTER", icon=1380856,duration=0,  cooldown=30,  category="OFFENSIVE", specs={255}      },  -- Survival only
    -- ── ROGUE ───────────────────────────────────────────────────
    -- Shared (all specs)
    [1966]   = { name="Feint",            class="ROGUE", icon=132294, duration=5,  cooldown=15,  category="DEFENSIVE" },  -- All specs
    [5277]   = { name="Evasion",          class="ROGUE", icon=136205, duration=10, cooldown=120, category="DEFENSIVE" },  -- All specs
    [31224]  = { name="Cloak of Shadows", class="ROGUE", icon=136177, duration=5,  cooldown=60,  category="IMMUNITY"  },  -- All specs
    [1766]   = { name="Kick",             class="ROGUE", icon=132219, duration=0,  cooldown=15,  category="INTERRUPT" },  -- All specs
    [2094]   = { name="Blind",            class="ROGUE", icon=136175, duration=60, cooldown=120, category="UTILITY"   },  -- All specs
    [1856]   = { name="Vanish",           class="ROGUE", icon=132331, duration=3,  cooldown=120, category="DEFENSIVE" },  -- All specs
    -- Spec-specific
    [79140]  = { name="Vendetta",         class="ROGUE", icon=132292, duration=20, cooldown=120, category="OFFENSIVE", specs={259}      },  -- Assassination only
    [13750]  = { name="Adrenaline Rush",  class="ROGUE", icon=136206, duration=20, cooldown=180, category="OFFENSIVE", specs={260}      },  -- Outlaw only
    [13877]  = { name="Blade Flurry",     class="ROGUE", icon=132298, duration=12, cooldown=30,  category="OFFENSIVE", specs={260}      },  -- Outlaw only
    [121471] = { name="Shadow Blades",    class="ROGUE", icon=606542, duration=20, cooldown=180, category="OFFENSIVE", specs={261}      },  -- Subtlety only
    [185313] = { name="Shadow Dance",     class="ROGUE", icon=458726, duration=8,  cooldown=60,  category="OFFENSIVE", specs={261}      },  -- Subtlety only
    -- ── PRIEST ──────────────────────────────────────────────────
    -- Shared (all specs)
    [8122]   = { name="Psychic Scream",       class="PRIEST", icon=136184, duration=8,  cooldown=45,  category="UTILITY"   },  -- All specs
    -- Spec-specific
    [33206]  = { name="Pain Suppression",     class="PRIEST", icon=135936, duration=8,  cooldown=180, category="DEFENSIVE", specs={256}      },  -- Discipline only
    [19236]  = { name="Desperate Prayer",     class="PRIEST", icon=135955, duration=0,  cooldown=90,  category="DEFENSIVE", specs={257}      },  -- All specs
    [62618]  = { name="Power Word: Barrier",  class="PRIEST", icon=253400, duration=10, cooldown=180, category="DEFENSIVE", specs={256}      },  -- Discipline only
    [64843]  = { name="Divine Hymn",          class="PRIEST", icon=135982, duration=8,  cooldown=180, category="DEFENSIVE", specs={257}      },  -- Holy only
    [47788]  = { name="Guardian Spirit",      class="PRIEST", icon=237544, duration=10, cooldown=180, category="DEFENSIVE", specs={257}      },  -- Holy only
    [47585]  = { name="Dispersion",           class="PRIEST", icon=237563, duration=6,  cooldown=120, category="IMMUNITY",  specs={258}      },  -- Shadow only
    [15487]  = { name="Silence",              class="PRIEST", icon=458230, duration=5,  cooldown=45,  category="INTERRUPT", specs={258}      },  -- Shadow only
    [88625]  = { name="Holy Word: Chastise",  class="PRIEST", icon=237510, duration=4,  cooldown=60,  category="INTERRUPT", specs={257}      },  -- Holy only
    [10060]  = { name="Power Infusion",       class="PRIEST", icon=135939, duration=20, cooldown=120, category="OFFENSIVE", specs={256}      },  -- Discipline only
    [34433]  = { name="Shadowfiend",          class="PRIEST", icon=136199, duration=15, cooldown=180, category="OFFENSIVE", specs={256,257}  },  -- Disc/Holy (Shadow uses Mindbender)
    -- ── DEATH KNIGHT ────────────────────────────────────────────
    -- Shared (all specs)
    [48707]  = { name="Anti-Magic Shell",      class="DEATHKNIGHT", icon=237506, duration=5,  cooldown=60,  category="DEFENSIVE" },  -- All specs
    [47528]  = { name="Mind Freeze",           class="DEATHKNIGHT", icon=237527, duration=0,  cooldown=15,  category="INTERRUPT" },  -- All specs
    [49576]  = { name="Death Grip",            class="DEATHKNIGHT", icon=237532, duration=0,  cooldown=25,  category="UTILITY"   },  -- All specs
    [42650]  = { name="Army of the Dead",      class="DEATHKNIGHT", icon=237511, duration=40, cooldown=480, category="OFFENSIVE" },  -- All specs
    -- Spec-specific
    [48792]  = { name="Icebound Fortitude",    class="DEATHKNIGHT", icon=237525, duration=8,  cooldown=180, category="DEFENSIVE", specs={250,251,252} },  -- All specs but triggered differently; keep all
    [206977] = { name="Darkness",              class="DEATHKNIGHT", icon=136146, duration=8,  cooldown=120, category="DEFENSIVE", specs={250}          },  -- Blood only (talent)
    [47476]  = { name="Strangulate",           class="DEATHKNIGHT", icon=136214, duration=5,  cooldown=60,  category="UTILITY",   specs={250}          },  -- Blood only
    [49028]  = { name="Dancing Rune Weapon",   class="DEATHKNIGHT", icon=135277, duration=8,  cooldown=120, category="OFFENSIVE", specs={250}          },  -- Blood only
    [55233]  = { name="Vampiric Blood",        class="DEATHKNIGHT", icon=237514, duration=10, cooldown=90,  category="DEFENSIVE", specs={250}          },  -- Blood only
    [221562] = { name="Asphyxiate",            class="DEATHKNIGHT", icon=613615, duration=5,  cooldown=45,  category="UTILITY",   specs={251,252}      },  -- Frost/Unholy talent
    -- ── SHAMAN ──────────────────────────────────────────────────
    -- Shared (all specs)
    [108271] = { name="Astral Shift",        class="SHAMAN", icon=538564, duration=8,  cooldown=90,  category="DEFENSIVE" },  -- All specs
    [57994]  = { name="Wind Shear",          class="SHAMAN", icon=136018, duration=0,  cooldown=12,  category="INTERRUPT" },  -- All specs
    [51514]  = { name="Hex",                 class="SHAMAN", icon=236548, duration=60, cooldown=30,  category="UTILITY"   },  -- All specs
    -- Spec-specific
    [98008]  = { name="Spirit Link Totem",   class="SHAMAN", icon=237586, duration=6,  cooldown=180, category="DEFENSIVE", specs={264}      },  -- Restoration only
    [192058] = { name="Wind Rush Totem",     class="SHAMAN", icon=537025, duration=5,  cooldown=120, category="UTILITY",   specs={264}      },  -- Restoration only
    [114049] = { name="Ascendance",          class="SHAMAN", icon=571600, duration=15, cooldown=180, category="OFFENSIVE", specs={262,263,264} },  -- All specs (different effect per spec)
    [51533]  = { name="Feral Spirit",        class="SHAMAN", icon=237585, duration=15, cooldown=120, category="OFFENSIVE", specs={263}      },  -- Enhancement only
    [198067] = { name="Fire Elemental",      class="SHAMAN", icon=135790, duration=30, cooldown=150, category="OFFENSIVE", specs={262}      },  -- Elemental only
    [2825]   = { name="Bloodlust",           class="SHAMAN", icon=136012, duration=40, cooldown=300, category="OFFENSIVE" },  -- All specs
    -- ── MAGE ────────────────────────────────────────────────────
    -- Shared (all specs)
    [45438]  = { name="Ice Block",            class="MAGE", icon=135841, duration=10, cooldown=240, category="IMMUNITY"  },  -- All specs
    [55021]  = { name="Counterspell",         class="MAGE", icon=135856, duration=0,  cooldown=24,  category="INTERRUPT" },  -- All specs
    [1953]   = { name="Blink",                class="MAGE", icon=135736, duration=0,  cooldown=15,  category="UTILITY"   },  -- All specs (Shimmer replaces for Arcane but same base)
    [122]    = { name="Frost Nova",           class="MAGE", icon=135848, duration=8,  cooldown=25,  category="UTILITY"   },  -- All specs
    -- Spec-specific
    [110959] = { name="Greater Invisibility", class="MAGE", icon=609815, duration=3,  cooldown=120, category="DEFENSIVE", specs={62,64}    },  -- Arcane/Frost talent
    [12051]  = { name="Evocation",            class="MAGE", icon=136075, duration=6,  cooldown=90,  category="UTILITY",   specs={62}       },  -- Arcane only
    [113724] = { name="Ring of Frost",        class="MAGE", icon=464484, duration=10, cooldown=45,  category="UTILITY",   specs={64}       },  -- Frost talent
    [190319] = { name="Combustion",           class="MAGE", icon=135824, duration=10, cooldown=120, category="OFFENSIVE", specs={63}       },  -- Fire only
    [12472]  = { name="Icy Veins",            class="MAGE", icon=135838, duration=20, cooldown=180, category="OFFENSIVE", specs={64}       },  -- Frost only
    [12042]  = { name="Arcane Power",         class="MAGE", icon=136048, duration=10, cooldown=90,  category="OFFENSIVE", specs={62}       },  -- Arcane only
    -- ── WARLOCK ─────────────────────────────────────────────────
    -- Shared (all specs)
    [104773] = { name="Unending Resolve",     class="WARLOCK", icon=136150, duration=8,  cooldown=180, category="DEFENSIVE" },  -- All specs
    [5782]   = { name="Fear",                 class="WARLOCK", icon=136183, duration=20, cooldown=30,  category="UTILITY"   },  -- All specs
    [30283]  = { name="Shadowfury",           class="WARLOCK", icon=136201, duration=3,  cooldown=30,  category="UTILITY",   specs={266,267}  },  -- Demo/Destro talent
    -- Spec-specific
    [6789]   = { name="Mortal Coil",          class="WARLOCK", icon=136175, duration=3,  cooldown=45,  category="UTILITY",   specs={265}      },  -- Affliction talent
    [113861] = { name="Dark Soul: Knowledge", class="WARLOCK", icon=463284, duration=20, cooldown=120, category="OFFENSIVE", specs={265}      },  -- Affliction only
    [1122]   = { name="Summon Infernal",      class="WARLOCK", icon=136219, duration=30, cooldown=180, category="OFFENSIVE", specs={267}      },  -- Destruction only
    -- ── MONK ────────────────────────────────────────────────────
    -- Shared (all specs)
    [116705] = { name="Spear Hand Strike",            class="MONK", icon=608953, duration=0,  cooldown=15,  category="INTERRUPT" },  -- All specs
    [115078] = { name="Paralysis",                    class="MONK", icon=629534, duration=60, cooldown=45,  category="UTILITY"   },  -- All specs
    -- Spec-specific
    [116849] = { name="Life Cocoon",                  class="MONK", icon=627485, duration=12, cooldown=180, category="DEFENSIVE", specs={270}      },  -- Mistweaver only
    [122783] = { name="Diffuse Magic",                class="MONK", icon=775460, duration=6,  cooldown=90,  category="DEFENSIVE", specs={268,269,270} },  -- All specs talent
    [122278] = { name="Dampen Harm",                  class="MONK", icon=620827, duration=10, cooldown=120, category="DEFENSIVE", specs={268,269,270} },  -- All specs talent
    [115203] = { name="Fortifying Brew",              class="MONK", icon=627486, duration=15, cooldown=360, category="DEFENSIVE", specs={268}      },  -- Brewmaster only
    [115176] = { name="Zen Meditation",               class="MONK", icon=642417, duration=8,  cooldown=300, category="IMMUNITY",  specs={270}      },  -- Mistweaver only
    [137639] = { name="Storm, Earth, and Fire",       class="MONK", icon=642418, duration=15, cooldown=90,  category="OFFENSIVE", specs={269}      },  -- Windwalker only
    [123904] = { name="Invoke Xuen, the White Tiger", class="MONK", icon=620832, duration=20, cooldown=120, category="OFFENSIVE", specs={269}      },  -- Windwalker only
    -- ── DRUID ───────────────────────────────────────────────────
    -- Shared (all specs)
    [22812]  = { name="Barkskin",            class="DRUID", icon=136097,  duration=12, cooldown=60,  category="DEFENSIVE" },  -- All specs
    [106839] = { name="Skull Bash",          class="DRUID", icon=236946,  duration=0,  cooldown=15,  category="INTERRUPT", specs={103,104} },  -- Feral/Guardian (melee forms only)
    -- Spec-specific
    [99]     = { name="Incapacitating Roar", class="DRUID", icon=236937,  duration=3,  cooldown=30,  category="UTILITY",   specs={104}      },  -- Guardian only
    [61336]  = { name="Survival Instincts",  class="DRUID", icon=236169,  duration=6,  cooldown=180, category="DEFENSIVE", specs={103,104}  },  -- Feral/Guardian
    [740]    = { name="Tranquility",         class="DRUID", icon=136107,  duration=8,  cooldown=180, category="DEFENSIVE", specs={105}      },  -- Restoration only
    [102342] = { name="Ironbark",            class="DRUID", icon=572025,  duration=12, cooldown=90,  category="DEFENSIVE", specs={105}      },  -- Restoration only
    [29166]  = { name="Innervate",           class="DRUID", icon=136048,  duration=10, cooldown=180, category="UTILITY",   specs={105}      },  -- Restoration only
    [106951] = { name="Berserk",             class="DRUID", icon=236149,  duration=15, cooldown=180, category="OFFENSIVE", specs={103,104}  },  -- Feral/Guardian
    [194223] = { name="Celestial Alignment", class="DRUID", icon=1396760, duration=20, cooldown=180, category="OFFENSIVE", specs={102}      },  -- Balance only
    -- ── DEMON HUNTER ────────────────────────────────────────────
    -- Shared (all specs)
    [183752] = { name="Consume Magic", class="DEMONHUNTER", icon=1344654, duration=0,  cooldown=10,  category="UTILITY"   },  -- All specs
    [179057] = { name="Chaos Nova",    class="DEMONHUNTER", icon=1247261, duration=5,  cooldown=60,  category="UTILITY"   },  -- All specs
    -- Spec-specific
    [198589] = { name="Blur",           class="DEMONHUNTER", icon=1305150, duration=10, cooldown=60,  category="DEFENSIVE", specs={577} },  -- Havoc only
    [209426] = { name="Darkness (DH)", class="DEMONHUNTER", icon=1305149, duration=8,  cooldown=300, category="DEFENSIVE", specs={577} },  -- Havoc only
    [196555] = { name="Netherwalk",    class="DEMONHUNTER", icon=1220127, duration=5,  cooldown=180, category="IMMUNITY",  specs={577} },  -- Havoc only
    [187827] = { name="Metamorphosis", class="DEMONHUNTER", icon=1247262, duration=30, cooldown=300, category="OFFENSIVE", specs={577} },  -- Havoc only
    [203720] = { name="Demon Spikes",  class="DEMONHUNTER", icon=1305154, duration=6,  cooldown=20,  category="DEFENSIVE", specs={581} },  -- Vengeance only
    [204021] = { name="Fiery Brand",   class="DEMONHUNTER", icon=1305156, duration=8,  cooldown=60,  category="DEFENSIVE", specs={581} },  -- Vengeance only
}

-- Subtabs shown in the per-class UI panels
SUBTAB_DEFS = {
    { key="OFFENSIVE", label="Offensives" },
    { key="DEFENSIVE", label="Defensives" },
    { key="INTERRUPT", label="Interrupts" },
    { key="IMMUNITY",  label="Immunity"   },
}

-- Maps each spell category to which subtab it lives under
-- (UTILITY spells appear on the Defensives subtab)
CATEGORY_TO_SUBTAB = {
    OFFENSIVE="OFFENSIVE", DEFENSIVE="DEFENSIVE",
    INTERRUPT="INTERRUPT", IMMUNITY="IMMUNITY", UTILITY="DEFENSIVE",
}

-- Class display info: key, human label, and WoW class colour
CLASS_INFO = {
    { key="WARRIOR",     label="Warrior",      r=0.78, g=0.61, b=0.43 },
    { key="PALADIN",     label="Paladin",       r=0.96, g=0.55, b=0.73 },
    { key="HUNTER",      label="Hunter",        r=0.67, g=0.83, b=0.45 },
    { key="ROGUE",       label="Rogue",         r=1.00, g=0.96, b=0.41 },
    { key="PRIEST",      label="Priest",        r=1.00, g=1.00, b=1.00 },
    { key="DEATHKNIGHT", label="Death Knight",  r=0.77, g=0.12, b=0.23 },
    { key="SHAMAN",      label="Shaman",        r=0.00, g=0.44, b=0.87 },
    { key="MAGE",        label="Mage",          r=0.25, g=0.78, b=0.92 },
    { key="WARLOCK",     label="Warlock",       r=0.53, g=0.53, b=0.93 },
    { key="MONK",        label="Monk",          r=0.00, g=1.00, b=0.59 },
    { key="DRUID",       label="Druid",         r=1.00, g=0.49, b=0.04 },
    { key="DEMONHUNTER", label="Demon Hunter",  r=0.64, g=0.19, b=0.79 },
}

-- Human-readable labels for the position dropdown
POSITION_OPTS = {
    "Top Left (inside)",     "Top Right (inside)",
    "Bottom Left (inside)",  "Bottom Right (inside)",
    "Center (inside)",
    "Top Left (outside)",    "Top Right (outside)",
    "Bottom Left (outside)", "Bottom Right (outside)",
}

-- Anchor configs matching POSITION_OPTS by index
POSITION_CFG = {
    { anchor="TOPLEFT",     relAnchor="TOPLEFT",     inside=true  },
    { anchor="TOPRIGHT",    relAnchor="TOPRIGHT",    inside=true  },
    { anchor="BOTTOMLEFT",  relAnchor="BOTTOMLEFT",  inside=true  },
    { anchor="BOTTOMRIGHT", relAnchor="BOTTOMRIGHT", inside=true  },
    { anchor="CENTER",      relAnchor="CENTER",      inside=true  },
    { anchor="TOPRIGHT",    relAnchor="TOPLEFT",     inside=false },
    { anchor="TOPLEFT",     relAnchor="TOPRIGHT",    inside=false },
    { anchor="BOTTOMRIGHT", relAnchor="BOTTOMLEFT",  inside=false },
    { anchor="BOTTOMLEFT",  relAnchor="BOTTOMRIGHT", inside=false },
}

CONTENT_TYPES     = { "Open World", "Dungeon", "Arena", "Battleground" }
SPELL_GROUP_COUNT = 3