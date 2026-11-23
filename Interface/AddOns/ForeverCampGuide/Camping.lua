-- ForeverCampGuide - Camping.lua
-- Datos tomados de la guía de campamento de wow-professions.com (beta de WoW Forever).
-- Los nombres de objeto en inglés son solo respaldo: en el juego se muestra el nombre
-- localizado que devuelve el cliente a partir del ID del objeto.
--
-- Campos de cada nivel:
--   item  = objeto de campamento que se coloca     spell = receta que lo fabrica
--   mats  = materiales ("id x cantidad")           bp    = objeto plano (Blueprint)
--   drop  = { jefe, mazmorra } que suelta el plano  station = estación de fabricación

local ADDON, ns = ...

ns.ICON_PATH     = "Interface\\Icons\\"
ns.CAMPFIRE_ICON = "inv_camelot_camping_welcomingcampfire"
ns.LOGO          = "Interface\\AddOns\\ForeverCampGuide\\Media\\logo"
ns.SOURCE_URL    = "wow-professions.com/forever/camping-guide"
ns.DATA_DATE     = "2026-10-14"

-- Cómo se consigue la receta de cada nivel
ns.TIER_SOURCE = {
    [1] = "Instructor de la profesión al llegar a 20 (tras la misión Camping 101).",
    [2] = "Plano (Blueprint) que suelta un jefe de mazmorra.",
    [3] = "Plano (Blueprint). Aún no se sabe dónde se consigue.",
}

local WORKSTATION = "Estación de trabajo para las recetas de la profesión que la necesitan."

-- names: nombres de la profesión tal como los muestra el cliente (EN, ES, FR, DE)
-- se usan para leer tu nivel de habilidad.
ns.professions = {
    {
        key = "alchemy", name = "Alquimia", icon = "Trade_Alchemy",
        names = { "Alchemy", "Alquimia", "Alchimie" },
        tiers = {
            [1] = { item = 279956, spell = 1230564, name = "Mana Well", icon = "spell_arcane_manatap", skill = 20,
                    effect = "Bonificación de regeneración de maná.", copies = "Bendición de sabiduría",
                    mats = "2447x1 3371x1" },
            [2] = { item = 279970, spell = 1263005, name = "Fermenter", icon = "inv_alchemy_90_cauldron", skill = 140,
                    effect = "Necesario para algunas recetas de Alquimia.", station = true,
                    mats = "3372x1 3356x1 2452x1", bp = 273085, drop = { "Rath'mael", "Ruins of Lordaeron" } },
            [3] = { item = 279990, spell = 1263078, name = "Alchemy Laboratory", icon = "10prof_portabletable_alchemy01", skill = 300,
                    effect = WORKSTATION, station = true,
                    mats = "273125x1 8925x1 13463x2", bp = 273112 },
        },
    },
    {
        key = "blacksmithing", name = "Herrería", icon = "Trade_BlackSmithing",
        names = { "Blacksmithing", "Herrería", "Forge", "Schmiedekunst" },
        tiers = {
            [1] = { item = 279944, spell = 1230171, name = "Sharpening Wheel", icon = "inv_stone_grindingstone_01", skill = 20,
                    effect = "Bonificación de Fuerza.", copies = "Tótem de Fuerza de la Tierra",
                    mats = "2835x1 2840x1" },
            [2] = { item = 279988, spell = 1263041, name = "Anvil", icon = "inv_blacksmith_anvil", skill = 140,
                    effect = "Un yunque de verdad para tus recetas de Herrería.",
                    mats = "2841x5 3478x2 2319x2", bp = 273086, drop = { "Gilnid", "The Deadmines" } },
            [3] = { item = 279955, spell = 1263073, name = "Master Forge", icon = "inv_mace_1h_blacksmithing_b_01_black", skill = 300,
                    effect = "Necesaria para muchas recetas de Herrería.", station = true,
                    mats = "273127x1 12359x5 8170x2", bp = 273113 },
        },
    },
    {
        key = "enchanting", name = "Encantamiento", icon = "Trade_Engraving",
        names = { "Enchanting", "Encantamiento", "Enchantement", "Verzauberkunst" },
        tiers = {
            [1] = { item = 279976, spell = 1230643, name = "Enchanted Lute", icon = "inv_10_enchanting2_magicswirl_bronze", skill = 20,
                    effect = "Bonificación de armadura, todas las estadísticas y resistencias.", copies = "Marca de lo Salvaje",
                    mats = "4470x1 10940x1" },
            [2] = { item = 279985, spell = 1263056, name = "Arcane Salvager", icon = "inv_eng_bottledelements", skill = 140,
                    effect = "Desencantar es más eficiente.",
                    mats = "11137x2 11174x1", bp = 273103, drop = { "Shade of the Archmage", "City of Dalaran" } },
            [3] = { item = 279987, spell = 1263082, name = "Arcane Forge", icon = "inv_enchanting_modifiedcraftingreagent_indigo", skill = 300,
                    effect = WORKSTATION, station = true,
                    mats = "273128x1 14344x2 16203x4", bp = 273116 },
        },
    },
    {
        key = "engineering", name = "Ingeniería", icon = "Trade_Engineering",
        names = { "Engineering", "Ingeniería", "Ingénierie", "Ingenieurskunst" },
        tiers = {
            [1] = { item = 279950, spell = 1230656, name = "Reagent Bot", icon = "inv_misc_enggizmos_13", skill = 20,
                    effect = "Vendedor de componentes de clase y suministros de profesión para todos los que estén en el campamento.",
                    mats = "4359x1 4361x1" },
            [2] = { item = 279949, spell = 1263034, name = "Repair Bot", icon = "inv_robotpet", skill = 140,
                    effect = "Repara el equipo de todos los que estén en el campamento.",
                    mats = "4375x2 4371x1 4234x1", bp = 273092, drop = { "Sneed", "The Deadmines" } },
            [3] = { item = 279989, spell = 1263083, name = "Anarchist's Workbench", icon = "inv_10_specialization_professionbook_engineering_color1", skill = 300,
                    effect = WORKSTATION, station = true,
                    mats = "273129x1 15994x2", bp = 273117 },
        },
    },
    {
        key = "herbalism", name = "Herboristería", icon = "INV_Misc_Flower_02",
        names = { "Herbalism", "Herboristería", "Herboristerie", "Kräuterkunde" },
        tiers = {
            [1] = { item = 279962, spell = 1229705, name = "Incense Candle", icon = "inv_misc_candle_02", skill = 20,
                    effect = "Bonificación de Intelecto.", copies = "Intelecto Arcano",
                    mats = "2447x1 765x1" },
            [2] = { item = 279964, spell = 1262980, name = "Greenhouse", icon = "inv_misc_herb_08", skill = 140,
                    effect = "Cultiva hierbas con el tiempo a partir de las semillas que plantes.",
                    mats = "4470x2 8836x1 8831x1", bp = 273106, drop = { "Shadetooth", "Excavation Site: Wetlands" } },
            [3] = { item = 279947, spell = 1263070, name = "Seed Hybridizer", icon = "inv_farm_herbseed", skill = 300,
                    effect = "Multiplica semillas o combínalas para obtener categorías más raras.",
                    mats = "13465x4 8925x1 14047x2", bp = 273120 },
        },
    },
    {
        key = "leatherworking", name = "Peletería", icon = "INV_Misc_ArmorKit_17",
        names = { "Leatherworking", "Peletería", "Travail du cuir", "Lederverarbeitung" },
        tiers = {
            [1] = { item = 279978, spell = 1229432, name = "Camp Tent", icon = "inv_misc_leatherscrap_01", skill = 20,
                    effect = "Experiencia de descanso de hasta un 5% de un nivel, una vez por hora (un perjuicio lo bloquea mientras tanto).",
                    mats = "2318x5" },
            [2] = { item = 279941, spell = 1263031, name = "Tanning Rack", icon = "inv_10_skinning_leather_rarehide_color1", skill = 140,
                    effect = "Necesario para muchas recetas de Peletería.", station = true,
                    mats = "2319x5 2321x3 4470x2", bp = 273096, drop = { "Razorclaw the Butcher", "Shadowfang Keep" } },
            [3] = { item = 279945, spell = 1263079, name = "Sewing Machine", icon = "inv_tailoring_modifiedcraftingreagent_orange", skill = 300,
                    effect = "Necesaria para muchas recetas de Peletería.", station = true,
                    mats = "273130x1 8170x5 14341x1", bp = 273121 },
        },
    },
    {
        key = "mining", name = "Minería", icon = "Trade_Mining",
        names = { "Mining", "Minería", "Minage", "Bergbau" },
        tiers = {
            [1] = { item = 279960, spell = 1230161, name = "Lodestone", icon = "inv_misc_rune_06", skill = 20,
                    effect = "Bonificación de poder de ataque cuerpo a cuerpo.", copies = "Bendición de poderío",
                    mats = "2835x1 2840x1" },
            [2] = { item = 279948, spell = 1262975, name = "Rock Garden", icon = "inv_misc_powder_iron", skill = 140,
                    effect = "Hace aparecer con el tiempo un filón de mineral común.",
                    mats = "2838x2 2772x1 2842x1", bp = 273097, drop = { "Relic Guardian", "Excavation Site: Wetlands" } },
            [3] = { item = 279952, spell = 1263071, name = "Molten Foundry", icon = "inv_blacksmithingalloys_red", skill = 300,
                    effect = "Necesaria para Fundir torio pesado.", station = true,
                    mats = "12359x5 12365x2 6037x1", bp = 273122 },
        },
    },
    {
        key = "skinning", name = "Desuello", icon = "INV_Misc_Pelt_Wolf_01",
        names = { "Skinning", "Desuello", "Dépeçage", "Kürschnerei" },
        tiers = {
            [1] = { item = 279979, spell = 1229517, name = "Camp Chair", icon = "inv_crate_01", skill = 20,
                    effect = "+2% de probabilidad de golpe crítico.", copies = "Aura de lechúcico lunar",
                    mats = "2318x3 4470x2" },
            [2] = { item = 279969, spell = 1262985, name = "Field Guide", icon = "inv_misc_book_03", skill = 140,
                    effect = "Cualquiera puede leerla para obtener Rastrear bestias.",
                    mats = "2319x3 5784x2 2321x1", bp = 273098, drop = { "Lady Anacondra", "Wailing Caverns" } },
            [3] = { item = 279938, spell = 1262982, name = "Trapper's Workbench", icon = "inv_misc_kobysstools_knifetrap_color3", skill = 300,
                    effect = "Incluye 1 trampa.",
                    mats = "4470x2 4234x4 3575x1", bp = 273109 },
        },
    },
    {
        key = "tailoring", name = "Sastrería", icon = "Trade_Tailoring",
        names = { "Tailoring", "Sastrería", "Couture", "Schneiderei" },
        tiers = {
            [1] = { item = 279972, spell = 1229504, name = "Faction Banner", icon = "inv_banner_03", skill = 20,
                    effect = "Bonificación de Espíritu para tu propia facción (Horda y Alianza tienen cada una su estandarte).",
                    copies = "Espíritu divino", mats = "2996x1 2320x1" },
            [2] = { item = 279943, spell = 1263032, name = "Spinning Wheel", icon = "10prof_table_tailoring01", skill = 140,
                    effect = "Necesaria para muchas recetas de Sastrería.", station = true,
                    mats = "4470x2 4305x5 2321x3", bp = 273099, drop = { "Unstable Sentinel", "City of Dalaran" } },
            [3] = { item = 279959, spell = 1263080, name = "Loom", icon = "inv_tailoring_80_tidespraylinen", skill = 300,
                    effect = "Necesario para muchas recetas de Sastrería.", station = true,
                    mats = "273131x1 14048x4 4470x4", bp = 273124 },
        },
    },
    {
        key = "cooking", name = "Cocina", icon = "INV_Misc_Food_15",
        names = { "Cooking", "Cocina", "Cuisine", "Kochkunst" },
        noTier1 = "Cocina no tiene objeto de nivel 1: en su lugar fabrica las fogatas sobre las que se monta todo campamento.",
        tiers = {
            [2] = { item = 279957, spell = 1262978, name = "Cookie's Feast", icon = "inv_cooking_80_majorfeast", skill = 140,
                    effect = "Comida de Aguante para todo el campamento.",
                    mats = "12037x2 12204x1 3713x1", bp = 273102, drop = { "Cookie", "The Deadmines" } },
            [3] = { item = 279982, spell = 1263067, name = "Iron Oven", icon = "achievement_cooking_masteroftheoven", skill = 300,
                    effect = "Estación de trabajo para las recetas de Cocina más avanzadas.", station = true,
                    mats = "10284x10 159x5 3713x4", bp = 273115 },
        },
    },
    {
        key = "firstaid", name = "Primeros auxilios", icon = "Spell_Holy_SealOfSacrifice",
        names = { "First Aid", "Primeros auxilios", "Secourisme", "Erste Hilfe" },
        tiers = {
            [1] = { item = 279968, spell = 1230117, name = "First Aid Kit", icon = "inv_misc_bandage_11", skill = 20,
                    effect = "Bonificación de Aguante.", copies = "Palabra de poder: entereza",
                    mats = "1251x3 159x1" },
            [2] = { item = 279940, spell = 1262996, name = "Toxin Study", icon = "inv_misc_potiona3", skill = 140,
                    effect = "Pociones de sanación y antídoto.",
                    mats = "6452x1 8544x2 4470x2", bp = 273105, drop = { "Commander Springvale", "Shadowfang Keep" } },
            [3] = { item = 279951, spell = 1263001, name = "Plague Doctor's Laboratory", icon = "inv_10_alchemy_incenseholder_color1", skill = 300,
                    effect = "Pociones de sanación y cataplasmas.",
                    mats = "4470x2 6453x2 14530x5", bp = 273118 },
        },
    },
    {
        key = "fishing", name = "Pesca", icon = "Trade_Fishing",
        names = { "Fishing", "Pesca", "Pêche", "Angeln" },
        tiers = {
            [1] = { item = 279967, spell = 1229745, name = "Fish Bowl", icon = "inv_magicalfishpet", skill = 20,
                    effect = "+8% a todas las estadísticas. Sirve a cualquier clase.", copies = "Bendición de reyes",
                    mats = "6291x1 3371x1" },
            [2] = { item = 279965, spell = 1262990, name = "Fishing Rack", icon = "inv_misc_2h_draenorfishingpole_a_01", skill = 140,
                    effect = "Durante 1 hora puedes pescar peces poco comunes; además da cebos de pesca.",
                    mats = "4470x2 8925x1 8365x2", bp = 273141, drop = { "Gelihast", "Blackfathom Deeps" } },
            [3] = { item = 279966, spell = 1262998, name = "Fishing Hut", icon = "inv_fishingchair", skill = 300,
                    effect = "Durante 1 hora puedes pescar peces raros; además da cebos de pesca.",
                    mats = "4470x5 14048x2 273295x1", bp = 273119 },
        },
    },
}

-- Fogatas (todas de Cocina). learn = habilidad para aprender la receta, use = habilidad para usar el kit.
ns.campfires = {
    { item = 279981, spell = 1229737, name = "Basic Campfire Kit",      learn = 1,   use = 1,   slots = 3,
      mats = "4470x1", source = "Instructor de Cocina (viene al aprender Cocina)." },
    { item = 279961, name = "Journeyman Campfire Kit", learn = 90,  use = 140, slots = 5,
      mats = "11291x1", bp = 273087, drop = { "Lord Serpentis", "Wailing Caverns" }, source = "Plano (Blueprint)." },
    { item = 279974, name = "Expert Campfire Kit",     learn = 200, use = 220, slots = 10,
      mats = "272941x1", bp = 273101, source = "Plano (Blueprint). Aún no se sabe dónde se consigue." },
}

-- Misión inicial "The Great Outdoors" (desde nivel 4, en tu zona de inicio).
-- races = identificadores en inglés que devuelve UnitRace("player") (2º valor).
ns.quests = {
    { races = { "Orc", "Troll" },     raceText = "Orco, Trol",   zone = "Durotar",           npc = "Brakk",              quest = 96604 },
    { races = { "Tauren" },           raceText = "Tauren",       zone = "Mulgore",           npc = "Kaga Wildhoof",      quest = 96605 },
    { races = { "Scourge", "Undead" },raceText = "No-muerto",    zone = "Tirisfal Glades", npc = "Eleanor Shackleton", quest = 96607 },
    { races = { "Human" },            raceText = "Humano",       zone = "Elwynn Forest", npc = "Sam Sarsaparilla",   quest = 95998 },
    { races = { "Dwarf", "Gnome" },   raceText = "Enano, Gnomo", zone = "Dun Morogh",        npc = "Eric Brighthammer",  quest = 96608 },
    { races = { "NightElf" },         raceText = "Elfo de la noche", zone = "Teldrassil",    npc = "Lyreena Duskblade",  quest = 96606 },
    { races = { "Skyborne" },         raceText = "Skyborne",     zone = "Zephras Isle",      npc = "Raan Wildwind",      quest = 96101 },
}
