-- =============================================================
-- KastaCD_KastaPlatesData.lua
-- Static per-dungeon NPC name/ID database for KastaPlates' dungeon +
-- NPC dropdown pickers (KastaCD_Options.lua's BuildKastaPlatesGroup).
--
-- Extracted from MethodDungeonTools' own per-dungeon route-planning data
-- (Addons/MethodDungeonTools/<Dungeon>.lua's dungeonBosses/dungeonEnemies
-- tables) rather than hand-typed from memory, since MDT's NPC IDs have to
-- be pixel-accurate for its own pull-planning feature to work at all -
-- confirmed consistent with this addon's own live data too (91785
-- "Wandering Shellback" in Eye of Azshara matched a live-tested entry).
--
-- Dungeon keys are the real GetInstanceInfo() instanceID (8th return) -
-- the same value KastaCD_MobCount.lua and KastaCD_KastaPlates.lua's own
-- CurrentInstance() already use, confirmed via LibObjectiveProgress-1.0's
-- own ProgressWeightData.lua (MapBasedWeights keys + comments). Return to
-- Karazhan's Lower/Upper wings share one instanceID (1651), matching how
-- the game itself treats them as a single instance.
-- =============================================================

-- Dungeon dropdown - order matches values shown, sorted alphabetically.
KASTAPLATES_DUNGEONS = {
    [1501] = "Black Rook Hold",
    [1677] = "Cathedral of Eternal Night",
    [1571] = "Court of Stars",
    [1466] = "Darkheart Thicket",
    [1456] = "Eye of Azshara",
    [1477] = "Halls of Valor",
    [1492] = "Maw of Souls",
    [1458] = "Neltharion's Lair",
    [1651] = "Return to Karazhan",
    [1753] = "Seat of the Triumvirate",
    [1516] = "The Arcway",
    [1493] = "Vault of the Wardens",
}

-- Per-dungeon NPC roster - [instanceID] = { [npcID] = "Name", ... }
KASTAPLATES_DUNGEON_NPCS = {
    [1501] = { -- Black Rook Hold
        [98542] = "Amalgam of Souls",
        [101549] = "Arcane Minion",
        [98813] = "Bloodscent Felhound",
        [100485] = "Soul-torn Vanguard",
        [100486] = "Risen Arcanist",
        [102781] = "Fel Bat Pup",
        [98706] = "Commander Shemdah'sohn",
        [102788] = "Felspite Dominator",
        [98370] = "Ghostly Councilor",
        [98368] = "Ghostly Protector",
        [98366] = "Ghostly Retainer",
        [98696] = "Illysanna Ravencrest",
        [98965] = "Kur'talos Ravencrest",
        [98538] = "Lady Velandras Ravencrest",
        [98521] = "Lord Etheldrin Ravencrest",
        [98280] = "Risen Arcanist",
        [98275] = "Risen Archer",
        [101839] = "Risen Companion",
        [102095] = "Risen Lancer",
        [98691] = "Risen Scout",
        [102094] = "Risen Swordsman",
        [98677] = "Rook Spiderling",
        [98681] = "Rook Spinner",
        [98949] = "Smashspite the Hateful",
        [98243] = "Soul-Torn Champion",
        [98362] = "Troubled Soul",
        [98810] = "Wrathguard Bladelord",
        [98792] = "Wyrmtongue Scavenger",
        [98900] = "Wyrmtongue Trickster",
    },
    [1677] = { -- Cathedral of Eternal Night
        [117193] = "Agronox",
        [118716] = "Bilespray Lasher",
        [118804] = "Domatrax",
        [121553] = "Dreadhunter",
        [119930] = "Dreadwing",
        [118704] = "Dul'zak",
        [118700] = "Felblight Stalker",
        [118703] = "Felborne Botanist",
        [119952] = "Felguard Destroyer",
        [120770] = "Felguard Destroyer (No Count)",
        [118712] = "Felstrider Enforcer",
        [118713] = "Felstrider Orbcaster",
        [119978] = "Fulminating Lasher",
        [118723] = "Gazerax",
        [118724] = "Helblaze Felbringer",
        [120779] = "Helblaze Felbringer (No Count)",
        [118717] = "Helblaze Imp",
        [119923] = "Helblaze Soulmender",
        [120366] = "Hellblaze Temptress",
        [116944] = "Mephistroth",
        [118705] = "Nal'asha",
        [118706] = "Necrotic Spiderling",
        [119977] = "Stranglevine Lasher",
        [117194] = "Thrashbite the Scornful",
        [121569] = "Vilebark Walker",
        [120550] = "Wrathguard Invader",
        [120778] = "Wrathguard Invader (No Count)",
        [118719] = "Wyrmtongue Scavenger",
    },
    [1571] = { -- Court of Stars
        [104218] = "Advisor Melandrus",
        [105704] = "Arcane Manifestation",
        [120651] = "Explosives",
        [104274] = "Baalgar the Watchful",
        [104295] = "Blazing Imp",
        [105705] = "Bound Energy",
        [104247] = "Duskwatch Arcanist",
        [111563] = "Duskwatch Guard",
        [104251] = "Duskwatch Sentry",
        [104278] = "Felbound Enforcer",
        [108151] = "Gerenth the Vile",
        [104270] = "Guardian Construct",
        [104275] = "Imacu'tya",
        [104273] = "Jazshariu",
        [104277] = "Legion Hound",
        [105699] = "Mana Saber",
        [105703] = "Mana Wyrm",
        [104215] = "Patrol Captain Gerdo",
        [104300] = "Shadow Mistress",
        [104217] = "Talixae Flamewreath",
        [105715] = "Watchful Inquisitor",
    },
    [1466] = { -- Darkheart Thicket
        [96512] = "Archdruid Glaidalis",
        [100531] = "Bloodtainted Fury",
        [100532] = "Bloodtainted Burster",
        [95766] = "Crazed Razorbeak",
        [100527] = "Dreadfire Imp",
        [101679] = "Dreadsoul Poisoner",
        [95771] = "Dreadsoul Ruiner",
        [99200] = "Dresaron",
        [95779] = "Festerhide Grizzly",
        [95772] = "Frenzied Nightclaw",
        [100529] = "Hatespawn Slime",
        [95769] = "Mindshattered Screecher",
        [101991] = "Nightmare Dweller",
        [103344] = "Oakheart",
        [99358] = "Rotheart Dryad",
        [99359] = "Rotheart Keeper",
        [99192] = "Shade of Xavius",
        [100539] = "Taintheart Deadeye",
        [99365] = "Taintheart Stalker",
        [99366] = "Taintheart Summoner",
        [100526] = "Tormented Bloodseeker",
        [99360] = "Vilethorn Blossom",
    },
    [1456] = { -- Eye of Azshara
        [95920] = "Animated Storm",
        [100250] = "Binder Ashioi",
        [99630] = "Bitterbrine Scavenger",
        [106787] = "Bitterbrine Slave",
        [100249] = "Channeler Varisz",
        [91787] = "Cove Seagull",
        [91786] = "Gritslime Snail",
        [97171] = "Hatecoil Arcanist",
        [91782] = "Hatecoil Crusher",
        [95861] = "Hatecoil Oracle",
        [91783] = "Hatecoil Stormweaver",
        [111637] = "Hatecoil Warrior",
        [97170] = "Hatecoil Wavebinder",
        [100216] = "Hatecoil Wrangler",
        [91797] = "King Deepbeard",
        [91789] = "Lady Hatecoil",
        [95947] = "Mak'rana Hardshell",
        [91790] = "Mak'rana Siltwalker",
        [98173] = "Mystic Ssa'veh",
        [97173] = "Restless Tides",
        [100248] = "Ritualist Lesha",
        [91794] = "Saltscale Lurker",
        [101414] = "Saltscale Skulker",
        [97172] = "Saltsea Droplet",
        [91793] = "Seaspray Crab",
        [91808] = "Serpentrix",
        [95939] = "Skrog Tidestomper",
        [91796] = "Skrog Wavecrasher",
        [91792] = "Stormwake Hydra",
        [91785] = "Wandering Shellback",
        [91784] = "Warlord Parjesh",
        [96028] = "Wrath of Azshara",
    },
    [1477] = { -- Halls of Valor
        [96611] = "Angerhoof Bull",
        [96608] = "Ebonclaw Worg",
        [99868] = "Fenryr",
        [95674] = "Fenryr",
        [96609] = "Gildedfur Stag",
        [95675] = "God-King Skovald",
        [94960] = "Hymdall",
        [95833] = "Hyrja",
        [97081] = "King Bjorn",
        [95843] = "King Haldor",
        [97083] = "King Ranulf",
        [97084] = "King Tor",
        [95676] = "Odyn",
        [97202] = "Olmyr the Enlightened",
        [97219] = "Solsten",
        [96677] = "Steeljaw Grizzly",
        [97068] = "Storm Drake",
        [96574] = "Stormforged Sentinel",
        [101637] = "Valarjar Aspirant",
        [97087] = "Valarjar Champion",
        [99804] = "Valarjar Falconer",
        [96640] = "Valarjar Marksman",
        [95834] = "Valarjar Mystic",
        [97197] = "Valarjar Purifier",
        [96664] = "Valarjar Runecarver",
        [95832] = "Valarjar Shieldmaiden",
        [101639] = "Valarjar Shieldmaiden (No Count)",
        [95842] = "Valarjar Thundercaller",
        [96934] = "Valarjar Trapper",
    },
    [1492] = { -- Maw of Souls
        [97163] = "Cursed Falke",
        [102104] = "Enslaved Shieldmaiden",
        [96754] = "Harbaron",
        [97097] = "Helarjar Champion",
        [99033] = "Helarjar Mistcaller",
        [96759] = "Helya",
        [97182] = "Night Watch Mariner",
        [102375] = "Runecarver Slave",
        [114712] = "Runecarver Slave",
        [97365] = "Seacursed Mistmender",
        [97043] = "Seacursed Slaver",
        [97200] = "Seacursed Soulkeeper",
        [98919] = "Seacursed Swiftblade",
        [97119] = "Shroud Hound",
        [98973] = "Skeletal Warrior",
        [99307] = "Skjal",
        [97185] = "The Grimewalker",
        [99188] = "Waterlogged Soul Guard",
        [96756] = "Ymiron, the Fallen King",
    },
    [1458] = { -- Neltharion's Lair
        [92612] = "Mightstone Breaker",
        [90998] = "Blightshard Shaper",
        [101437] = "Burning Geode",
        [91007] = "Dargrul",
        [92387] = "Drums of War",
        [113537] = "Emberhusk Dominator",
        [98406] = "Embershard Scorpion",
        [90997] = "Mightstone Breaker",
        [91006] = "Rockback Gnasher",
        [103459] = "Rockback Snapper",
        [91008] = "Rockbound Pelter",
        [102232] = "Rockbound Trapper",
        [91003] = "Rokmora",
        [102404] = "Stoneclaw Grubmaster",
        [91332] = "Stoneclaw Hunter",
        [91001] = "Tarspitter Lurker",
        [102430] = "Tarspitter Slug",
        [91004] = "Ularogg Cragshaper",
        [102253] = "Understone Demolisher",
        [105636] = "Understone Drudge",
        [92610] = "Understone Drummer",
        [101438] = "Vileshard Chunk",
        [96247] = "Vileshard Crawler",
        [91000] = "Vileshard Hulk",
    },
    [1651] = { -- Return to Karazhan
        [115765] = "Abstract Nullifier",
        [115419] = "Ancient Tome",
        [114624] = "Arcane Warden",
        [115020] = "Arcanid",
        [114264] = "Attumen the Huntsman",
        [116549] = "Backup Singer",
        [115115] = "Coldmist Stalker",
        [115019] = "Coldmist Widow",
        [114334] = "Damaged Golem",
        [115486] = "Erudite Slayer",
        [115484] = "Fel Bat",
        [114626] = "Forlorn Spirit",
        [114716] = "Ghostly Baker",
        [114715] = "Ghostly Chef",
        [114542] = "Ghostly Philanthropist",
        [114714] = "Ghostly Steward",
        [114526] = "Ghostly Understudy",
        [115488] = "Infused Pyromancer",
        [115388] = "King",
        [113971] = "Maiden of Virtue",
        [114338] = "Mana Confluence",
        [114252] = "Mana Devourer",
        [115831] = "Mana Devourer",
        [114364] = "Mana-Gorged Wyrm",
        [114312] = "Moroes",
        [114284] = "Opera Hall: Wikket",
        [114584] = "Phantom Crew",
        [114636] = "Phantom Guardsman",
        [114625] = "Phantom Guest",
        [115417] = "Rat",
        [114783] = "Reformed Maiden",
        [114350] = "Shade of Medivh",
        [114627] = "Shrieking Terror",
        [114794] = "Skeletal Hound",
        [114544] = "Skeletal Usher",
        [114628] = "Skeletal Waiter",
        [114801] = "Spectral Apprentice",
        [114632] = "Spectral Attendant",
        [114804] = "Spectral Charger",
        [114802] = "Spectral Journeyman",
        [114541] = "Spectral Patron",
        [116550] = "Spectral Patron",
        [114629] = "Spectral Retainer",
        [114637] = "Spectral Sentry",
        [114803] = "Spectral Stable Hand",
        [114633] = "Spectral Valet",
        [115418] = "Spider",
        [114247] = "The Curator",
        [114634] = "Undying Servant",
        [114792] = "Virtuous Lady",
        [114790] = "Viz'aduum the Watcher",
        [114796] = "Wholesome Hostess",
        [115757] = "Wrathguard Flamebringer",
    },
    [1753] = { -- Seat of the Triumvirate
        [122412] = "Bound Voidlord",
        [122322] = "Famished Broken",
        [122423] = "Grand Shadow-Weaver",
        [124729] = "L'ura",
        [125857] = "Lashing Voidling",
        [122571] = "Rift Warden",
        [125860] = "Rift Warden",
        [122398] = "Sapped Voidlord",
        [122316] = "Saprish",
        [122560] = "Shadow Stalker",
        [122408] = "Shadow Stalker",
        [122403] = "Shadowguard Champion",
        [122405] = "Shadowguard Conjurer",
        [122413] = "Shadowguard Riftstalker",
        [124171] = "Shadowguard Subjugator",
        [122401] = "Shadowguard Trickster",
        [122404] = "Shadowguard Voidbender",
        [122421] = "Umbral War-Adept",
        [122056] = "Viceroy Nezhar",
        [122478] = "Void Discharge",
        [124947] = "Void Flayer",
        [122407] = "Warp Stalker",
        [122313] = "Zuraal the Ascended",
    },
    [1516] = { -- The Arcway
        [98728] = "Acidic Bile",
        [98756] = "Arcane Anomaly",
        [98205] = "Corstilax",
        [105651] = "Dreadborne Seer",
        [105876] = "Enchanted Broodling",
        [105617] = "Eredar Chaosbringer",
        [105682] = "Felguard Destroyer",
        [113699] = "Forgotten Spirit",
        [98206] = "General Xakal",
        [98203] = "Ivanyr",
        [102351] = "Mana Wyrm",
        [98207] = "Nal'tira",
        [105915] = "Nightborne Reclaimer",
        [105921] = "Nightborne Spellsword",
        [98732] = "Plagued Rat",
        [105706] = "Priestess of Misery",
        [98425] = "Unstable Amalgamation",
        [98759] = "Vicious Manafang",
        [106059] = "Warp Shade",
        [98733] = "Withered Fiend",
        [105952] = "Withered Manawraith",
        [98770] = "Wrathguard Felblade",
        [105629] = "Wyrmtongue Scavenger",
    },
    [1493] = { -- Vault of the Wardens
        [97678] = "Aranasi Broodmother",
        [95886] = "Ash'Golm",
        [97677] = "Barbed Spiderling",
        [96657] = "Blade Dancer Illianna",
        [98963] = "Blazing Imp",
        [95888] = "Cordana Felsong",
        [99649] = "Dreadlord Mendacius",
        [102583] = "Fel Scorcher",
        [99956] = "Fel-Infused Fury",
        [96587] = "Felsworn Infester",
        [98954] = "Felsworn Myrmidon",
        [98533] = "Foul Mother",
        [98177] = "Glayvianna Soulrender",
        [95887] = "Glazer",
        [102566] = "Grimhorn the Enslaver",
        [96584] = "Immoliant Fury",
        [96015] = "Inquisitor Tormentorum",
        [102584] = "Malignant Defiler",
        [98926] = "Shadow Hunter",
        [100364] = "Spirit of Vengeance",
        [95885] = "Tirathon Saltheril",
        [96480] = "Viletongue Belcher",
    },
}

-- Flat NPC ID -> creature displayID lookup, used to preview the NPC's
-- actual 3D model next to the picker (Model:SetDisplayInfo) so picking a
-- name out of a dropdown isn't a total guess at what/where it is. Not
-- nested per-dungeon since npcID alone is already a unique lookup key.
KASTAPLATES_NPC_DISPLAYID = {
    [98243] = 65762,
    [98275] = 65743,
    [98280] = 65718,
    [98362] = 65812,
    [98366] = 65785,
    [98368] = 65786,
    [98370] = 65787,
    [98521] = 65814,
    [98538] = 65833,
    [98542] = 65837,
    [98677] = 35688,
    [98681] = 42742,
    [98691] = 65950,
    [98696] = 65951,
    [98706] = 65954,
    [98792] = 64476,
    [98810] = 63994,
    [98813] = 65054,
    [98900] = 64483,
    [98949] = 65304,
    [98965] = 66853,
    [101549] = 67018,
    [101839] = 64620,
    [102094] = 67488,
    [102095] = 67478,
    [102788] = 5047,
    [116944] = 74999,
    [117193] = 74482,
    [117194] = 76022,
    [118700] = 6172,
    [118703] = 71875,
    [118704] = 20865,
    [118705] = 67636,
    [118706] = 74522,
    [118712] = 74871,
    [118713] = 74639,
    [118716] = 76261,
    [118717] = 76629,
    [118719] = 64476,
    [118723] = 71753,
    [118724] = 75823,
    [118804] = 75613,
    [119923] = 75828,
    [119930] = 66118,
    [119952] = 18342,
    [119977] = 76018,
    [119978] = 75988,
    [120366] = 74870,
    [120550] = 20045,
    [120770] = 18342,
    [120778] = 20045,
    [120779] = 75823,
    [121553] = 68246,
    [121569] = 2078,
    [104215] = 68521,
    [104217] = 69267,
    [104218] = 70592,
    [104247] = 70563,
    [104251] = 70566,
    [104270] = 68553,
    [104273] = 9018,
    [104274] = 63588,
    [104275] = 17543,
    [104277] = 62513,
    [104278] = 68765,
    [104295] = 17035,
    [104300] = 10923,
    [105699] = 64620,
    [105703] = 70565,
    [105704] = 54282,
    [105705] = 55561,
    [105715] = 68418,
    [108151] = 66917,
    [111563] = 70561,
    [95766] = 64535,
    [95769] = 64536,
    [95771] = 64539,
    [95772] = 64385,
    [95779] = 66633,
    [96512] = 69815,
    [99192] = 71688,
    [99200] = 71675,
    [99358] = 69689,
    [99359] = 69688,
    [99360] = 69687,
    [99365] = 66740,
    [99366] = 66131,
    [100526] = 61828,
    [100527] = 12190,
    [100529] = 47926,
    [100531] = 29278,
    [100539] = 64486,
    [101679] = 67296,
    [101991] = 71636,
    [103344] = 68127,
    [91782] = 66813,
    [91783] = 66152,
    [91784] = 65114,
    [91785] = 51124,
    [91786] = 51219,
    [91787] = 39490,
    [91789] = 66397,
    [91790] = 61620,
    [91792] = 55460,
    [91793] = 42978,
    [91794] = 1763,
    [91796] = 66819,
    [91797] = 67254,
    [91808] = 65110,
    [95861] = 66153,
    [95920] = 23504,
    [95939] = 66820,
    [95947] = 66063,
    [96028] = 66741,
    [97170] = 19365,
    [97171] = 66163,
    [97172] = 25675,
    [97173] = 36212,
    [98173] = 29934,
    [99630] = 66508,
    [100216] = 18393,
    [100248] = 66534,
    [100249] = 66535,
    [100250] = 66536,
    [101414] = 1763,
    [106787] = 66508,
    [111637] = 66499,
    [94960] = 67773,
    [95674] = 64466,
    [95675] = 65873,
    [95676] = 67230,
    [95832] = 25801,
    [95833] = 72718,
    [95834] = 64208,
    [95842] = 67277,
    [95843] = 28086,
    [96574] = 67429,
    [96608] = 70154,
    [96609] = 45090,
    [96611] = 65853,
    [96640] = 25811,
    [96664] = 64200,
    [96677] = 41014,
    [96934] = 67281,
    [97068] = 67203,
    [97081] = 28085,
    [97083] = 28087,
    [97084] = 28088,
    [97087] = 67274,
    [97197] = 64200,
    [97202] = 64464,
    [97219] = 64575,
    [99804] = 25811,
    [99868] = 64466,
    [101637] = 70645,
    [101639] = 25801,
    [96754] = 67556,
    [96756] = 65079,
    [96759] = 65043,
    [97043] = 66091,
    [97097] = 66181,
    [97119] = 64467,
    [97163] = 25630,
    [97182] = 67179,
    [97185] = 30710,
    [97200] = 66090,
    [97365] = 70529,
    [98919] = 66103,
    [98973] = 66184,
    [99033] = 70528,
    [99188] = 66102,
    [99307] = 66121,
    [102104] = 25801,
    [102375] = 66119,
    [114712] = 66119,
    [90997] = 64679,
    [90998] = 65780,
    [91000] = 65783,
    [91001] = 37550,
    [91003] = 62386,
    [91004] = 62390,
    [91006] = 65050,
    [91007] = 62392,
    [91008] = 67568,
    [91332] = 64667,
    [92387] = 63017,
    [92610] = 64336,
    [96247] = 34068,
    [98406] = 65795,
    [101437] = 33425,
    [101438] = 64606,
    [102232] = 64665,
    [102253] = 64783,
    [102404] = 64667,
    [102430] = 66603,
    [103459] = 66336,
    [105636] = 64776,
    [113537] = 70784,
    [113971] = 16198,
    [114247] = 16958,
    [114252] = 73157,
    [114264] = 73811,
    [114284] = 17550,
    [114312] = 16540,
    [114334] = 61850,
    [114338] = 55144,
    [114350] = 73834,
    [114364] = 62387,
    [114526] = 73302,
    [114541] = 16555,
    [114542] = 73336,
    [114544] = 73313,
    [114584] = 73338,
    [114624] = 61125,
    [114625] = 16464,
    [114626] = 26404,
    [114627] = 10698,
    [114628] = 73472,
    [114629] = 73465,
    [114632] = 16514,
    [114633] = 16494,
    [114634] = 73417,
    [114636] = 16454,
    [114637] = 16458,
    [114714] = 16535,
    [114715] = 16524,
    [114716] = 16529,
    [114783] = 16551,
    [114790] = 73709,
    [114792] = 16547,
    [114794] = 73458,
    [114796] = 16543,
    [114801] = 16417,
    [114802] = 73470,
    [114803] = 16397,
    [114804] = 16407,
    [115019] = 16050,
    [115020] = 72245,
    [115115] = 16051,
    [115388] = 16293,
    [115417] = 73857,
    [115418] = 73858,
    [115419] = 73859,
    [115484] = 73837,
    [115486] = 73838,
    [115488] = 63419,
    [115757] = 73944,
    [115765] = 74335,
    [115831] = 62384,
    [116549] = 74235,
    [116550] = 16555,
    [122056] = 78415,
    [122313] = 77871,
    [122316] = 76771,
    [122322] = 75479,
    [122398] = 56285,
    [122401] = 75005,
    [122403] = 76939,
    [122404] = 76423,
    [122405] = 75011,
    [122407] = 75244,
    [122408] = 76593,
    [122412] = 71758,
    [122413] = 75003,
    [122421] = 76899,
    [122423] = 76900,
    [122478] = 76601,
    [122560] = 76593,
    [122571] = 76471,
    [124171] = 76542,
    [124729] = 78182,
    [124947] = 78264,
    [125857] = 29209,
    [125860] = 76471,
    [98203] = 65741,
    [98205] = 65791,
    [98206] = 65792,
    [98207] = 65793,
    [98425] = 33922,
    [98728] = 46333,
    [98732] = 27972,
    [98733] = 70160,
    [98756] = 55131,
    [98759] = 65920,
    [98770] = 64693,
    [102351] = 19285,
    [105617] = 63997,
    [105629] = 65211,
    [105651] = 67378,
    [105682] = 39908,
    [105706] = 21542,
    [105876] = 69416,
    [105915] = 69432,
    [105921] = 69434,
    [105952] = 70161,
    [106059] = 31471,
    [113699] = 70550,
    [95885] = 65074,
    [95886] = 65155,
    [95887] = 66204,
    [95888] = 66480,
    [96015] = 64719,
    [96480] = 73258,
    [96584] = 65666,
    [96587] = 64253,
    [96657] = 58479,
    [97677] = 65922,
    [97678] = 65926,
    [98177] = 70670,
    [98533] = 67347,
    [98926] = 70675,
    [98954] = 64727,
    [98963] = 65894,
    [99649] = 66917,
    [99956] = 70673,
    [100364] = 66403,
    [102566] = 64805,
    [102583] = 62511,
    [102584] = 65542,
}

-- Preset default colors, filtered down from a much larger multi-expansion
-- NPC-color export (a Plater-style "[id, isBoss, colorName, mobName,
-- dungeonName]" list) to only the entries whose dungeon is one of the 12
-- Legion dungeons this addon actually supports - everything else in that
-- list was for retail dungeons that don't exist in this Legion 7.3.5
-- client and could never match anything here. Flat npcID -> {r,g,b},
-- consumed as the DEFAULT color (instead of plain red) wherever a
-- KastaPlates entry doesn't have its own saved color yet - see
-- GetOrCreateKastaPlatesEntry (KastaCD_KastaPlates.lua) and the
-- pickColor/per-dungeon-list color get()s (KastaCD_Options.lua).
-- "HUNTER" in the source data mapped to WoW's actual Hunter class color
-- (matches CLASS_INFO's own HUNTER entry in KastaCD_SpellDB.lua) rather
-- than a literal named color.
KASTAPLATES_PRESET_COLORS = {
    -- Court of Stars
    [120651] = { 1.00, 0.549, 0 },      -- Explosives (darkorange)
    [104295] = { 1, 0, 1 },             -- Blazing Imp (fuchsia)
    [105704] = { 1, 0, 1 },             -- Arcane Manifestation (fuchsia)
    [105715] = { 1, 0, 1 },             -- Watchful Inquisitor (fuchsia)
    [104247] = { 1, 0, 1 },             -- Duskwatch Arcanist (fuchsia)
    [104300] = { 1, 0, 1 },             -- Shadow Mistress (fuchsia)

    -- Darkheart Thicket
    [99359]  = { 0.420, 0.557, 0.137 }, -- Rotheart Keeper (olivedrab)
    [99360]  = { 0.5, 0, 0.5 },         -- Vilethorn Blossom (purple)
    [99366]  = { 0.5, 0, 0.5 },         -- Taintheart Summoner (purple)
    [100527] = { 0.5, 0, 0.5 },         -- Dreadfire Imp (purple)
    [100529] = { 0.827, 0.827, 0.827 }, -- Hatespawn Slime (lightgray)
    [100531] = { 0, 1, 1 },             -- Bloodtainted Fury (aqua)
    [100532] = { 0.5, 0, 0.5 },         -- Bloodtainted Burster (purple)
    [103344] = { 0, 1, 1 },             -- Oakheart (aqua)

    -- Neltharion's Lair
    [90997]  = { 0, 1, 1 },             -- Mightstone Breaker (aqua)
    [92612]  = { 0, 1, 1 },             -- Mightstone Breaker (aqua)
    [90998]  = { 1, 0, 1 },             -- Blightshard Shaper (fuchsia)
    [91000]  = { 0, 1, 1 },             -- Vileshard Hulk (aqua)
    [91006]  = { 1, 0, 1 },             -- Rockback Gnasher (fuchsia)

    -- Black Rook Hold
    [101549] = { 0.67, 0.83, 0.45 },    -- Arcane Minion (HUNTER class color)
    [98677]  = { 0.827, 0.827, 0.827 }, -- Rook Spiderling (lightgray)
    [98813]  = { 0.5, 0, 0.5 },         -- Bloodscent Felhound (purple)
    [98243]  = { 0, 1, 1 },             -- Soul-Torn Champion (aqua)
    [98370]  = { 1, 0, 1 },             -- Ghostly Councilor (fuchsia)
    [98691]  = { 0.5, 0, 0.5 },         -- Risen Scout (purple)
    [100485] = { 0.5, 0, 0.5 },         -- Soul-torn Vanguard (purple)
    [100486] = { 1, 0, 1 },             -- Risen Arcanist (fuchsia)
    [102781] = { 0.827, 0.827, 0.827 }, -- Fel Bat Pup (lightgray)
    [102788] = { 0.420, 0.557, 0.137 }, -- Felspite Dominator (olivedrab)

    -- Halls of Valor
    [97197]  = { 1, 0, 1 },             -- Valarjar Purifier (fuchsia)
    [95842]  = { 1, 0, 1 },             -- Valarjar Thundercaller (fuchsia)
    [95834]  = { 0, 1, 0 },             -- Valarjar Mystic
    [96664]  = { 0.2, 0.5, 1 },         -- Valarjar Runecarver
    [97081]  = { 1, 0.84, 0 },          -- King Bjorn
    [97084]  = { 1, 0.5, 0 },           -- King Tor
    [95843]  = { 0, 1, 1 },             -- King Haldor
    [97083]  = { 1, 0.4, 0.7 },         -- King Ranulf

    -- Maw of Souls (no colors given by the user for this batch -
    -- individually assigned from a rotating palette instead)
    [97200]  = { 1, 0, 0 },             -- Seacursed Soulkeeper
    [97043]  = { 1, 0.5, 0 },           -- Seacursed Slaver
    [102104] = { 1, 1, 0 },             -- Enslaved Shieldmaiden
    [102375] = { 0, 1, 0 },             -- Runecarver Slave
    [99188]  = { 0, 1, 1 },             -- Waterlogged Soul Guard
    [97182]  = { 0.2, 0.5, 1 },         -- Night Watch Mariner
    [97097]  = { 0.5, 0, 0.5 },         -- Helarjar Champion
    [97365]  = { 1, 0, 1 },             -- Seacursed Mistmender
    [99033]  = { 1, 0.4, 0.7 },         -- Helarjar Mistcaller
    [99307]  = { 1, 0.84, 0 },          -- Skjal

    -- The Arcway
    [98425]  = { 1, 0, 0 },             -- Unstable Amalgamation
    [105651] = { 1, 0.5, 0 },           -- Deadborne Seer
    [98770]  = { 1, 1, 0 },             -- Wrathguard Felblade
    [105617] = { 0, 1, 0 },             -- Eredar Chaosbringer
    [105706] = { 0, 1, 1 },             -- Priestess of Misery
    [105682] = { 0.2, 0.5, 1 },         -- Felguard Destroyer
    [105952] = { 0.5, 0, 0.5 },         -- Withered Manawraith
    [105921] = { 1, 0, 1 },             -- Nightborne Spellsword
    [105915] = { 1, 0.4, 0.7 },         -- Nightborne Reclaimer
    [106059] = { 1, 0.84, 0 },          -- Warp Shade
    [113699] = { 0.6, 1, 0.2 },         -- Forgotten Spirit
    [98756]  = { 0, 0.6, 0.6 },         -- Arcane Anomaly
    [98728]  = { 0.29, 0, 0.51 },       -- Acidic Bile

    -- Vault of the Wardens
    [100364] = { 1, 0, 0 },             -- Spirit of Vengeance
    [97678]  = { 1, 0.5, 0 },           -- Aranasi Broodmother
    [96657]  = { 1, 1, 0 },             -- Blade Dancer Illianna
    [96584]  = { 0, 1, 0 },             -- Immoliant Fury
    [96587]  = { 0, 1, 1 },             -- Felsworn Infester
    [98954]  = { 0.2, 0.5, 1 },         -- Felsworn Myrmidon

    -- Court of Stars (additions)
    [105703] = { 0.5, 0, 0.5 },         -- Duskwatch Sentry
    [104270] = { 1, 0.4, 0.7 },         -- Guardian Construct
    [105699] = { 1, 0.84, 0 },          -- Mana Saber
    [104273] = { 0, 0.6, 0.6 },         -- Felbound Enforcer

    -- Darkheart Thicket (additions)
    [95769]  = { 1, 0, 0 },             -- Mindshattered Screecher
    [95772]  = { 1, 0.5, 0 },           -- Frenzied Nightclaw
    [99358]  = { 1, 1, 0 },             -- Rotheart Dryad
    [99365]  = { 0.2, 0.5, 1 },         -- Taintheart Stalker

    -- Black Rook Hold (additions)
    [98368]  = { 1, 0, 0 },             -- Ghostly Protector
    [98366]  = { 1, 0.5, 0 },           -- Ghostly Retainer
    [98521]  = { 1, 0.84, 0 },          -- Lord Etheldrin Ravencrest
    [98280]  = { 1, 1, 0 },             -- Risen Arcanist
    [98275]  = { 0, 1, 0 },             -- Risen Archer
    [101839] = { 0, 1, 1 },             -- Risen Companion
    [98810]  = { 0.2, 0.5, 1 },         -- Wrathguard Bladelord
    [98792]  = { 1, 0.4, 0.7 },         -- Wyrmtongue Scavenger
    [102094] = { 0, 0.6, 0.6 },         -- Risen Swordsman

    -- Eye of Azshara
    [95861]  = { 1, 0, 0 },             -- Hatecoil Oracle
    [91783]  = { 1, 0.5, 0 },           -- Hatecoil Stormweaver
    [97171]  = { 1, 1, 0 },             -- Hatecoil Arcanist
    [100248] = { 0, 1, 0 },             -- Ritualist Lesha
    [100249] = { 0, 1, 1 },             -- Channeler Varisz
    [100250] = { 0.2, 0.5, 1 },         -- Binder Ashioi
    [98173]  = { 0.5, 0, 0.5 },         -- Mystic Ssa'veh
    [91790]  = { 1, 0, 1 },             -- Mak'rana Siltwalker

    -- Neltharion's Lair (additions) - the user's list repeats 90997
    -- ("Stoneclaw Grubmaster") which is already the ID for "Mightstone
    -- Breaker" above under a different name - kept the existing name
    -- rather than overwrite it, since 90997 can only mean one thing.
    [91008]  = { 1, 0.4, 0.7 },         -- Rockbound Pelter
}
