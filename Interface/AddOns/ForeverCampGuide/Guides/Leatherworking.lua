local _, ns = ...
ns.guides = ns.guides or {}

ns.guides.leatherworking = {
    intro = "Ruta más rápida y barata de 1 a 300. Cuando dos recetas cuestan parecido, la guía da las dos con una regla sencilla para elegir. "
         .. "Combina mejor con Desuello (el cuero es casi todo el coste), pero también puedes comprarlo todo en la subasta.",
    apprenticeNote = "Peletería de aprendiz no tiene requisito de nivel en Forever.",

    shopping = {
        { title = "1-225", rows = {
            { "2934x100", alt = "2318x60" },
            { "2318x251" },
            { "2319x180", alt = "783x27 2318x165", note = "Según lo que elijas en 30 y en 100 (Pantalones de cuero oscuro o de cuero ligero)." },
            { "2319x307" },
            { "4232x10", alt = "2319x220" },
            { "4235x20 4234x120", alt = "4234x240 2319x140 1206x17 7071x5", note = "Según la ruta que elijas en 130 (con o sin Piel pesada)." },
            { "4234x97" },
            { "4236x26", alt = "4235x26" },
            { "4304x315" },
        } },
        { title = "225-300", note = "Aún no es definitiva: esta parte no se ha podido probar.", rows = {
            { "4304x192" }, { "8170x1030" }, { "14047x530" },
        } },
    },

    capitals = {
        { "H", "Orgrimmar", "Kamari", "En el Arrastradero (The Drag)." }, { "H", "Undercity", "Dan Golthas" }, { "H", "Thunder Bluff", "Mak" },
        { "A", "Stormwind City", "Randal Worth" }, { "A", "Ironforge", "Gretta Finespindle", "En la Gran Fundición." }, { "A", "Darnassus", "Darianna" },
    },
    starting = {
        { race = "Orco, Trol", zone = "Durotar", npcs = { { "H", "Orgrimmar", "Kamari", "No hay en Durotar: Arrastradero de Orgrimmar." } } },
        { race = "Tauren", zone = "Mulgore", npcs = { { "H", "Mulgore", "Chaw Stronghide", "En el poblado Pezuña de Sangre (Bloodhoof Village)." } } },
        { race = "No-muerto", zone = "Tirisfal Glades", npcs = { { "H", "Tirisfal Glades", "Shelene Rhobart", "En el cruce de caminos al sureste de Rémol (Brill)." } } },
        { race = "Humano", zone = "Elwynn Forest", npcs = { { "A", "Elwynn Forest", "Adele Fielder", "En la casita junto al Lago de Cristal, al noreste de Villadorada." } } },
        { race = "Enano, Gnomo", zone = "Dun Morogh", npcs = { { "A", "Ironforge", "Gretta Finespindle", "No hay en Dun Morogh: Gran Fundición de Forjaz." } } },
        { race = "Elfo de la noche", zone = "Teldrassil", npcs = { { "A", "Teldrassil", "Nadyia Maneweaver", "En la casita junto al camino a Darnassus." } } },
        { race = "Skyborne", zone = "Zephras Isle", npcs = {
            { "N", "Zephras Isle", "Emerii Tallgust", "En Valanaar." }, { "N", "Zephras Isle", "Indari Sunseam", "En el poblado Shen'dar." } } },
    },

    extras = {
        { title = "Hilo, tintes y sal",
          text = "Casi todos los instructores tienen al lado un proveedor de suministros de peletería (hilo, tintes, sal), salvo los de Elwynn y Tirisfal. Allí compra la Sal y el Hilo basto en estos vendedores:",
          npcs = { { "A", "Elwynn Forest", "Tharynn Bouden", "En Villadorada (Goldshire)." }, { "H", "Tirisfal Glades", "Abigail Shiel", "En Rémol (Brill)." } } },
    },

    ranks = {
        { title = "Aprendiz", range = "1-55", steps = {
            { r = "1-30", n = 33, spell = 2881, name = "Light Leather", icon = "inv_misc_leatherscrap_03", mats = "2934x100",
              note = "Amarillo desde 20, así que algunas fabricaciones no dan punto.",
              alt = { { n = 30, spell = 2152, name = "Light Armor Kit", icon = "inv_misc_armorkit_17", mats = "2318x30",
                        note = "Si compraste Cuero ligero en vez de restos." } } },
            { r = "30-55", n = 25, spell = 9062, name = "Small Leather Ammo Pouch", icon = "inv_misc_ammo_bullet_01", mats = "2318x75 2320x100",
              alt = { { n = 27, spell = 3816, name = "Cured Light Hide", icon = "inv_misc_pelt_wolf_ruin_02", mats = "783x27 4289x27",
                        note = "Si vas a hacer los Pantalones de cuero ligero en 100: guarda 24 pieles curtidas." } } },
        } },
        { title = "Oficial", range = "55-130", req = "Peletería 50 y nivel 10.",
          trainers = {
            { "H", "Orgrimmar", "Karolek" }, { "H", "Undercity", "Arthur Moore" }, { "H", "Thunder Bluff", "Tarn" },
            { "A", "Stormwind City", "Simon Tanner" }, { "A", "Ironforge", "Fimble Finespindle" }, { "A", "Darnassus", "Faldron" } },
          steps = {
            { r = "55-75", n = 21, spell = 3756, name = "Embossed Leather Gloves", icon = "inv_gauntlets_05", mats = "2318x63 2320x42" },
            { r = "75-80", n = 8, spell = 20648, name = "Medium Leather", icon = "inv_misc_leatherscrap_05", mats = "2318x32" },
            { r = "80-90", n = 10, spell = 3817, name = "Cured Medium Hide", icon = "inv_misc_pelt_bear_02", mats = "4232x10 4289x10",
              note = "Guárdalas para los Cinturones de cuero oscuro en 115.",
              alt = { { n = 10, spell = 2165, name = "Medium Armor Kit", icon = "inv_misc_armorkit_16", mats = "2319x40 2320x10",
                        note = "Si no tienes Piel mediana: luego haz Pantalones de cuero oscuro en vez de cinturones en 115." } } },
            { r = "90-100", n = 19, spell = 3763, name = "Fine Leather Belt", icon = "inv_belt_04", mats = "2318x114 2320x38",
              note = "Guarda 10 para los Cinturones de cuero oscuro en 115." },
            { r = "100-115", n = 15, spell = 7135, name = "Dark Leather Pants", icon = "inv_pants_02", mats = "2319x180 4340x15 2321x15",
              alt = { { n = 24, spell = 9068, name = "Light Leather Pants", icon = "inv_pants_09", mats = "2318x240 4231x24 2321x24",
                        note = "Si hiciste Piel ligera curtida en 30." } } },
            { r = "115-125", n = 10, spell = 3766, name = "Dark Leather Belt", icon = "inv_belt_03", mats = "4246x10 4233x10 2321x20 4340x10",
              alt = { { n = 15, spell = 7135, name = "Dark Leather Pants", icon = "inv_pants_02", mats = "2319x180 4340x15 2321x15",
                        note = "Si hiciste Equipos de armadura medianos en 80." } } },
            { r = "125-130", n = 7, spell = 20649, name = "Heavy Leather", icon = "inv_misc_leatherscrap_07", mats = "2319x35" },
        } },
        { title = "Experto", range = "130-210", req = "Peletería 125, nivel 20 y 50 de plata.",
          trainers = { { "H", "Thunder Bluff", "Una" }, { "A", "Darnassus", "Telonis" } },
          blocks = {
            { title = "Con o sin Piel pesada",
              text = "Si 20 Pieles pesadas cuestan menos que unos 120 Cueros pesados, 140 Cueros medios y 17 Ágatas musgosas, elige la ruta con Piel pesada curtida; si no, la otra.",
              routes = {
                { title = "Con Piel pesada curtida", steps = {
                    { r = "130-140", n = 20, spell = 3818, name = "Cured Heavy Hide", icon = "inv_misc_pelt_wolf_02", mats = "4235x20 4289x60",
                      note = "Las necesitarás más adelante." },
                    { r = "140-155", n = 20, spell = 3764, name = "Hillman's Leather Gloves", icon = "inv_gauntlets_05", mats = "2319x280 2321x80" },
                    { r = "155-165", n = 10, spell = 7151, name = "Barbaric Shoulders", icon = "inv_shoulder_08", mats = "4234x80 4236x10 2321x20" },
                    { r = "165-175", n = 10, spell = 7156, name = "Guardian Gloves", icon = "inv_gauntlets_05", mats = "4234x40 4236x10 4291x10" },
                } },
                { title = "Sin Piel pesada", steps = {
                    { r = "130-155", n = 30, spell = 3764, name = "Hillman's Leather Gloves", icon = "inv_gauntlets_05", mats = "2319x420 2321x120" },
                    { r = "155-170", n = 17, spell = 7149, name = "Barbaric Leggings", icon = "inv_pants_12", mats = "4234x170 2321x34 1206x17",
                      vendors = { { "H", "Thousand Needles", "Jandia" }, { "H", "Arathi Highlands", "Keena" },
                                  { "A", "Arathi Highlands", "Hammon Karwn" }, { "A", "Ashenvale", "Lardan" } } },
                    { r = "170-175", n = 5, spell = 6661, name = "Barbaric Harness", icon = "inv_chest_leather_04", mats = "4234x70 2321x10 7071x5" },
                } },
              } },
            { steps = {
                { r = "175-195", n = 26, spell = 7156, name = "Guardian Gloves", icon = "inv_gauntlets_05", mats = "4234x104 4236x26 4291x26",
                  note = "Si compraste Piel pesada, cúrtelas antes (3 de Sal cada una)." },
                { r = "195-210", n = 21, spell = 10507, name = "Nightscape Headband", icon = "inv_belt_24", mats = "4304x105 4291x42" },
            } },
          } },
        { title = "Artesano", range = "210-300", req = "Peletería 200 y nivel 35.", untested = true,
          text = "Desde 225 aún no se ha podido probar por el límite de nivel de la beta. Muchos rangos cambiaron respecto a Classic Era (la mayoría de recetas se vuelven grises 25 puntos antes): no sigas la guía de Classic para este tramo.",
          trainers = { { "H", "Feralas", "Hahrana Ironhide", "En el Campamento Mojache." }, { "A", "The Hinterlands", "Drakk Stonehand", "En el Pico Nidal (Aerie Peak)." } },
          steps = {
            { r = "210-225", n = 15, spell = 10548, name = "Nightscape Pants", icon = "inv_pants_11", mats = "4304x210 4291x60",
              note = "Los instructores de experto de Cima del Trueno y Darnassus no la enseñan: apréndela con un instructor de artesano." },
            { r = "225-235", n = 12, spell = 10558, name = "Nightscape Boots", icon = "inv_boots_08", mats = "4304x192 8343x24" },
            { r = "235-250", n = 15, spell = 19049, name = "Wicked Leather Gauntlets", icon = "inv_gauntlets_31", mats = "8170x120 2325x15 14341x15",
              vendors = { { "H", "Tirisfal Glades", "Werg Thickblade", "Vende el patrón." }, { "A", "Western Plaguelands", "Leonard Porter", "Vende el patrón." } } },
            { r = "250-265", n = 21, spell = 19049, name = "Wicked Leather Gauntlets", icon = "inv_gauntlets_31", mats = "8170x168 2325x21 14341x21" },
            { r = "265-285", n = 20, spell = 19082, name = "Runic Leather Headband", icon = "inv_misc_bandana_01", mats = "8170x280 14047x200 14341x20",
              vendors = { { "N", "Eastern Plaguelands", "Jase Farlane", "En la Capilla de la Esperanza de la Luz (Light's Hope Chapel). Vende el patrón." } } },
            { r = "285-300", n = 33, spell = 19082, name = "Runic Leather Headband", icon = "inv_misc_bandana_01", mats = "8170x462 14047x330 14341x33",
              note = "Si las alternativas salen más baratas, haz unas 15 de una de ellas.",
              alt = {
                { n = 15, spell = 19100, name = "Heavy Scorpid Shoulders", icon = "inv_shoulder_15", mats = "8170x210 15408x210 15407x15 14341x30" },
                { n = 15, spell = 19098, name = "Wicked Leather Armor", icon = "inv_chest_leather_07", mats = "8170x300 15407x30 14256x90 2325x60 14341x30" },
                { n = 15, spell = 1255018, name = "Tooled Leather Pants", icon = "inv_pants_leather_09", mats = "8170x270 15407x15 6261x15 14341x15" },
              } },
          } },
    },
}
