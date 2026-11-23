-- Formato de las guías (igual en todos los archivos de Guides/):
--  NPC:   { facción ("H", "A" o "N"), zona (inglés, para el mapa), nombre, indicación }
--  mats:  "itemID x cantidad" separados por espacios -> se cuentan en tus bolsas
--  paso:  { r = "desde-hasta", n = cantidad, spell = ID de receta, name, icon, mats,
--           note, recipe = ID del objeto receta, vendors = { NPC... },
--           alt = { pasos alternativos }, also = { pasos que se hacen además } }
local _, ns = ...
ns.guides = ns.guides or {}

ns.guides.alchemy = {
    intro = "Ruta más rápida y barata de 1 a 300. Combina muy bien con Herboristería, así no compras las hierbas en la casa de subastas. "
         .. "En Forever las pociones de sanación pasaron a Primeros auxilios, por eso la ruta cambia respecto a Classic.",
    apprenticeNote = "Alquimia de aprendiz no tiene requisito de nivel en Forever: puedes aprenderla con un personaje recién creado.",

    shopping = {
        { title = "1-225", note = "La beta se detiene en 225; usa esta parte si subes en la beta.", rows = {
            { "2447x91" }, { "765x45" }, { "785x50" }, { "2449x54" }, { "2450x60" }, { "3820x82" },
            { "6359x40 3356x15", alt = "785x42 3820x42" },
            { "3356x36" }, { "3357x36" },
        } },
        { title = "225-300", note = "No es definitiva y se detiene en 290; los rangos casi no cambiaron, así que debería acercarse mucho.", rows = {
            { "3357x12" }, { "3820x12" }, { "8836x45" }, { "8838x60" }, { "8839x60" },
        } },
    },

    capitals = {
        { "H", "Orgrimmar", "Whuut", "Dentro del edificio de alquimia de Yelmak, en el Arrastradero (The Drag), bajo la rampa de la planta baja. Enseña hasta 75." },
        { "H", "Undercity", "Doctor Martin Felben" },
        { "H", "Thunder Bluff", "Kray" },
        { "A", "Stormwind City", "Tel'Athir" },
        { "A", "Ironforge", "Vosur Brakthel" },
        { "A", "Darnassus", "Milla Fairancora" },
    },
    starting = {
        { race = "Orco, Trol", zone = "Durotar", npcs = { { "H", "Durotar", "Miao'zan", "En el poblado Sen'jin." } } },
        { race = "Tauren", zone = "Mulgore", npcs = { { "H", "Thunder Bluff", "Kray", "No hay instructor en Mulgore: está en la meseta central de Cima del Trueno." } } },
        { race = "No-muerto", zone = "Tirisfal Glades", npcs = { { "H", "Tirisfal Glades", "Carolai Anise", "En la casita del extremo noroeste de Rémol (Brill)." } } },
        { race = "Humano", zone = "Elwynn Forest", npcs = { { "A", "Elwynn Forest", "Alchemist Mallory", "En una casa de campo en las colinas entre Ventormenta y Villanorte." } } },
        { race = "Enano, Gnomo", zone = "Dun Morogh", npcs = { { "A", "Ironforge", "Vosur Brakthel", "No hay instructor en Dun Morogh: está en Ciudad Manitas (Tinker Town), Forjaz." } } },
        { race = "Elfo de la noche", zone = "Teldrassil", npcs = { { "A", "Teldrassil", "Cyndra Kindwhisper", "En una casita al este de la posada de Dolanaar." } } },
        { race = "Skyborne", zone = "Zephras Isle", npcs = {
            { "N", "Zephras Isle", "Iaadaria Bitterwind", "En Valanaar." },
            { "N", "Zephras Isle", "Valiena Swiftgale", "En Valanaar." },
            { "N", "Zephras Isle", "Nyassa Swiftdraught", "En el poblado Shen'dar." } } },
    },

    ranks = {
        { title = "Aprendiz", range = "1-55", steps = {
            { r = "1-10", n = 9, spell = 1245246, name = "Minor Arcane Elixir", icon = "inv_potion_106", mats = "2447x9 3371x9",
              note = "Los viales los venden los proveedores de suministros de alquimia, casi siempre junto al instructor.",
              vendors = { { "H", "Undercity", "Algernon", "Viales en Entrañas." }, { "A", "Teldrassil", "Narret Shadowgrove", "Viales en Dolanaar." } },
              alt = { { n = 9, spell = 1245250, name = "Elixir of Minor Force", icon = "inv_potion_77", mats = "765x9 3371x9", note = "Si la Hojaplata es más barata." } } },
            { r = "10-55", n = 45, spell = 7183, name = "Elixir of Minor Defense", icon = "inv_potion_63", mats = "765x45 2447x45 3371x45" },
        } },
        { title = "Oficial", range = "55-150", req = "Alquimia 50 y nivel 10.",
          trainers = {
            { "H", "Orgrimmar", "Yelmak" }, { "H", "Undercity", "Doctor Marsh" }, { "H", "Thunder Bluff", "Bena Winterhoof" },
            { "A", "Stormwind City", "Lilyssia Nightbreeze" }, { "A", "Ironforge", "Tally Berryfizz" }, { "A", "Darnassus", "Sylvanna Forestmoon" } },
          steps = {
            { r = "55-65", n = 10, spell = 2331, name = "Minor Mana Potion", icon = "inv_potion_70", mats = "785x10 2447x10 3371x10" },
            { r = "65-90", n = 27, spell = 2334, name = "Elixir of Minor Fortitude", icon = "inv_potion_42", mats = "2449x54 2447x27 3371x27",
              note = "Se vuelve amarillo en 80: los últimos 10 puntos piden algunas fabricaciones más." },
            { r = "90-120", n = 30, spell = 3171, name = "Elixir of Wisdom", icon = "inv_potion_06", mats = "785x30 2450x60 3371x30",
              note = "Si también subes Sastrería, guárdalos: los necesitarás para los Guantes de meditación." },
            { r = "120-130", n = 10, spell = 3173, name = "Lesser Mana Potion", icon = "inv_potion_71", mats = "785x10 3820x10 3371x10" },
            { r = "130-150", n = 20, spell = 7837, name = "Fire Oil", icon = "inv_potion_38", mats = "6359x40 3371x20",
              note = "Cada fabricación da 2 aceites. Guarda 30 para el Elixir de poder de fuego del siguiente tramo.",
              alt = { { n = 20, spell = 3173, name = "Lesser Mana Potion", icon = "inv_potion_71", mats = "785x20 3820x20 3371x20",
                        note = "Si el Pargo aletafuego es caro o escaso en la subasta." } } },
        } },
        { title = "Experto", range = "150-225", req = "Alquimia 125, nivel 20 y 50 de plata.",
          trainers = { { "H", "Undercity", "Doctor Herbert Halsey" }, { "A", "Darnassus", "Ainethil" } },
          steps = {
            { r = "150-165", n = 15, spell = 7845, name = "Elixir of Fire Power", icon = "inv_potion_55", mats = "6371x30 3356x15 3372x15",
              note = "Usa los Aceites de fuego que guardaste.",
              alt = { { n = 22, spell = 3173, name = "Lesser Mana Potion", icon = "inv_potion_71", mats = "785x22 3820x22 3371x22",
                        note = "Si hiciste pociones de maná en vez de aceite, sigue con ellas hasta 165." } } },
            { r = "165-195", n = 36, spell = 3452, name = "Mana Potion", icon = "inv_potion_72", mats = "3820x36 3356x36 3372x36" },
            { r = "195-225", n = 36, spell = 7259, name = "Nature Protection Potion", icon = "inv_potion_06", mats = "3357x36 3820x36 3372x36", recipe = 6057,
              note = "La receta se liga al recogerla: cómprala con el personaje alquimista.",
              vendors = { { "H", "Feralas", "Bronk" }, { "A", "Feralas", "Logannas" },
                          { "N", "Stranglethorn Vale", "Glyx Brewright" }, { "N", "Tanaris", "Alchemist Pestlezugg" } } },
        } },
        { title = "Artesano", range = "225-300", req = "Alquimia 200 y nivel 35.", untested = true,
          text = "Los rangos de Alquimia son los mismos que en Classic; solo se sustituyeron los pasos de pociones de sanación. Sin probar por el límite de nivel de la beta.",
          trainers = { { "H", "Swamp of Sorrows", "Rogvar", "En Rocal (Stonard)." }, { "A", "Feralas", "Kylanna Windwhisper", "En el Bastión Plumaluna (Feathermoon)." } },
          steps = {
            { r = "225-230", n = 12, spell = 7259, name = "Nature Protection Potion", icon = "inv_potion_06", mats = "3357x12 3820x12 3372x12",
              note = "Es amarilla: quizá una o dos más." },
            { r = "230-265", n = 45, spell = 11460, name = "Draught of Detect Undead", icon = "inv_potion_53", mats = "8836x45 8925x45",
              note = "Amarilla desde 245; probablemente necesites algunas extra." },
            { r = "265-275", n = 10, spell = 17553, name = "Superior Mana Potion", icon = "inv_potion_74", mats = "8838x20 8839x20 8925x10", recipe = 13477,
              vendors = { { "H", "Undercity", "Algernon" }, { "A", "Darnassus", "Ulthir" } } },
            { r = "275-290", n = 20, spell = 17553, name = "Superior Mana Potion", icon = "inv_potion_74", mats = "8838x40 8839x40 8925x20",
              note = "Mira la subasta y haz la más barata de las tres opciones. Las tres son amarillas o lo serán pronto.",
              alt = {
                { n = 17, spell = 17554, name = "Elixir of Greater Defense", icon = "inv_potion_66", mats = "13423x34 8838x17 8925x17", recipe = 13478,
                  note = "Amarillo desde 280.", vendors = { { "H", "Orgrimmar", "Kor'geld" }, { "A", "Ironforge", "Soolie Berryfizz" } } },
                { n = 27, spell = 11476, name = "Elixir of Shadow Power", icon = "inv_potion_48", mats = "8845x81 8925x27", recipe = 9301,
                  vendors = { { "H", "Undercity", "Algernon" }, { "A", "Stormwind City", "Maria Lumere" } } } } },
            { r = "290-300", text = "La web aún no ha decidido estos últimos 10 puntos (en Classic salían de la Poción de sanación sublime, que en Forever es de Primeros auxilios). "
                .. "Puedes seguir con cualquiera de las recetas de 275-290 o usar una receta de Favor del mercader o de las tablas de la pestaña Recetas.",
              alt = {
                { n = 17, spell = 1251740, name = "Major Frenzy Potion", icon = "inv_potione_6", mats = "13466x51 8839x34 18256x17",
                  note = "Receta de Favor del mercader (240 de favor y Honorable), ligada al recogerla. Amarilla desde 295.",
                  vendors = { { "H", "The Barrens", "Apothecary Durelle", "Campamento de Suministros y Logística de Durotar, junto a la Encrucijada." },
                              { "A", "Redridge Mountains", "Nina Surefire", "Campamento de la Autoridad de Comercio de Azeroth en Tres Caminos." } } },
              } },
        } },
    },

    lists = {
        { title = "Recetas de la casa de subastas (botín de enemigos)",
          text = "Aprender / amarillo / gris y materiales.",
          rows = {
            { 17555, "Elixir of the Sages", "inv_potion_29", "270 / 285 / 325 - 1 Dreamfoil, 2 Plaguebloom, 1 Crystal Vial" },
            { 17557, "Elixir of Brute Force", "inv_potion_40", "275 / 290 / 330 - 2 Gromsblood, 2 Plaguebloom, 1 Crystal Vial" },
            { 17571, "Elixir of the Mongoose", "inv_potion_32", "280 / 295 / 335 - 2 Mountain Silversage, 2 Plaguebloom, 1 Crystal Vial" },
            { 17570, "Greater Stoneshield Potion", "inv_potion_69", "280 / 295 / 335 - 3 Stonescale Oil, 1 Thorium Ore, 1 Crystal Vial" },
            { 17573, "Greater Arcane Elixir", "inv_potion_109", "285 / 300 / 340 - 3 Dreamfoil, 1 Mountain Silversage, 1 Crystal Vial" },
            { 17572, "Purification Potion", "inv_potion_31", "285 / 300 / 340 - 2 Icecap, 2 Plaguebloom, 1 Crystal Vial" },
            { 17577, "Greater Arcane Protection Potion", "inv_potion_83", "290 / 305 / 345 - 1 Dream Dust, 1 Dreamfoil, 1 Crystal Vial" },
            { 17574, "Greater Fire Protection Potion", "inv_potion_24", "290 / 305 / 345 - 1 Elemental Fire, 1 Dreamfoil, 1 Crystal Vial" },
            { 17575, "Greater Frost Protection Potion", "inv_potion_20", "290 / 305 / 345 - 1 Elemental Water, 1 Dreamfoil, 1 Crystal Vial" },
            { 17579, "Greater Holy Protection Potion", "inv_potion_09", "290 / 305 / 345 - 1 Elemental Air, 1 Dreamfoil, 1 Crystal Vial" },
            { 17576, "Greater Nature Protection Potion", "inv_potion_22", "290 / 305 / 345 - 1 Elemental Earth, 1 Dreamfoil, 1 Crystal Vial" },
            { 17578, "Greater Shadow Protection Potion", "inv_potion_23", "290 / 305 / 345 - 1 Shadow Oil, 1 Dreamfoil, 1 Crystal Vial" },
          } },
        { title = "Recetas de vendedor (275-310)",
          text = "Rin'wosho está en la isla Yojamba (Vega de Tuercespina) y pide reputación con la tribu Zandalar; Magnus Frostwake está en las Tierras de la Peste del Oeste.",
          npcs = { { "N", "Stranglethorn Vale", "Rin'wosho the Trader", "Isla Yojamba. Reputación con la tribu Zandalar." },
                   { "N", "Western Plaguelands", "Magnus Frostwake" } },
          rows = {
            { 24366, "Greater Dreamless Sleep Potion", "inv_potion_83", "275 / 290 / 330 - Rin'wosho, Amistoso" },
            { 24368, "Major Troll's Blood Elixir", "inv_potion_82", "290 / 305 / 345 - Rin'wosho, Honorable" },
            { 24365, "Mageblood Elixir", "inv_potion_137", "275 / 290 / 330 - Rin'wosho, Venerado" },
            { 24367, "Living Action Potion", "inv_potion_07", "285 / 300 / 340 - Rin'wosho, Exaltado" },
            { 17580, "Major Mana Potion", "inv_potion_76", "295 / 310 / 350 - Magnus Frostwake" },
          } },
        { title = "Otras recetas de Favor del mercader",
          text = "Las venden los mismos proveedores que la Major Frenzy Potion, pero se vuelven grises en 295: solo sirven para la mitad del último tramo.",
          rows = {
            { 1250792, "Elixir of Nature Power", "inv_potion_97" },
            { 1250785, "Elixir of Wicked Regeneration", "trade_alchemy_dpotion_a22" },
            { 1251734, "Major Spellblasting Potion", "inv_potione_4" },
          } },
    },
}
