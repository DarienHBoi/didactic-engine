local _, ns = ...
ns.guides = ns.guides or {}

-- Proveedores de Leña simple y Yesquero (para fabricar kits de fogata)
local WOOD_VENDORS = {
    { "H", "Orgrimmar", "Xen'to", "Junto al instructor." }, { "H", "Undercity", "Ronald Burch", "Junto al instructor." },
    { "H", "Thunder Bluff", "Naal Mistrunner", "Junto al instructor." }, { "H", "Durotar", "Jark", "En los barracones de Cerrotajo." },
    { "H", "Mulgore", "Moorat Longstride", "En el poblado Pezuña de Sangre." }, { "H", "Tirisfal Glades", "Mrs. Winters", "En Rémol (Brill)." },
    { "A", "Stormwind City", "Erika Tate", "Junto al instructor." }, { "A", "Ironforge", "Emrul Riknussun", "Junto al instructor." },
    { "A", "Darnassus", "Fyldan", "Junto al instructor." }, { "A", "Elwynn Forest", "Brog Hamfist", "En Villadorada." },
    { "A", "Dun Morogh", "Kreg Bilmn", "En la destilería Cebatruenos." }, { "A", "Teldrassil", "Nyoma", "En Dolanaar." },
    { "N", "Zephras Isle", "Antelariaa Cloudgaze", "En Valanaar." }, { "N", "Zephras Isle", "Zerril Softbreeze", "Instructora de Cocina en el poblado Shen'dar." },
}

local V = {   -- vendedores de recetas que se repiten
    smallfish = { { "H", "Mulgore", "Harn Longcast" }, { "H", "Thunder Bluff", "Sewa Mistrunner" }, { "H", "Tirisfal Glades", "Martine Tramblay" },
                  { "H", "Undercity", "Lizbeth Cromwell" }, { "A", "Dun Morogh", "Gretta Ganter" }, { "A", "Elwynn Forest", "Tharynn Bouden" },
                  { "A", "Loch Modan", "Khara Deepwater" }, { "A", "Stormwind City", "Catherine Leland" }, { "A", "Teldrassil", "Nyoma" } },
    mackerel  = { { "H", "Durotar", "Zansoa" }, { "H", "Tirisfal Glades", "Martine Tramblay" }, { "A", "Ironforge", "Tansy Puddlefizz" },
                  { "A", "Teldrassil", "Nessa Shadowsong" }, { "A", "Westfall", "Kriggon Talsone" } },
    longjaw   = { { "H", "Mulgore", "Harn Longcast" }, { "H", "Silverpine Forest", "Killian Sanatha" }, { "H", "Thunder Bluff", "Naal Mistrunner" },
                  { "H", "Undercity", "Lizbeth Cromwell" }, { "A", "Elwynn Forest", "Tharynn Bouden" }, { "A", "Ironforge", "Tansy Puddlefizz" },
                  { "A", "Loch Modan", "Khara Deepwater" }, { "A", "Teldrassil", "Nyoma" } },
    albacore  = { { "H", "Durotar", "Zansoa" }, { "H", "Orgrimmar", "Shankys" }, { "H", "Silverpine Forest", "Killian Sanatha" },
                  { "H", "Undercity", "Ronald Burch" }, { "A", "Darkshore", "Heldan Galesong" }, { "A", "Stormwind City", "Catherine Leland" },
                  { "A", "Teldrassil", "Nessa Shadowsong" }, { "A", "Westfall", "Kriggon Talsone" }, { "A", "Wetlands", "Stuart Fleming" },
                  { "N", "The Barrens", "Kilxx" } },
    catfish   = { { "H", "Hillsbrad Foothills", "Derak Nightfall" }, { "H", "Thunder Bluff", "Naal Mistrunner" }, { "H", "Thunder Bluff", "Sewa Mistrunner" },
                  { "H", "Undercity", "Ronald Burch" }, { "A", "Hillsbrad Foothills", "Lindea Rabonne" }, { "A", "Stormwind City", "Catherine Leland" },
                  { "N", "The Barrens", "Kilxx" } },
    omelet    = { { "A", "Stormwind City", "Kendor Kabonka" }, { "H", "Arathi Highlands", "Keena" } },
    lion      = { { "H", "The Barrens", "Zargh" } },
    trout     = { { "H", "Ashenvale", "Wik'Tar" }, { "H", "Orgrimmar", "Shankys" }, { "N", "Stranglethorn Vale", "Kelsey Yance" },
                  { "H", "Undercity", "Lizbeth Cromwell" }, { "A", "Ironforge", "Tansy Puddlefizz" }, { "A", "Wetlands", "Stuart Fleming" },
                  { "H", "Desolace", "Wulan" }, { "A", "Darkshore", "Heldan Galesong" }, { "A", "Hillsbrad Foothills", "Lindea Rabonne" } },
    raptor    = { { "A", "Arathi Highlands", "Hammon Karwn" }, { "H", "Arathi Highlands", "Keena" }, { "H", "Dustwallow Marsh", "Ogg'marr" } },
    turtle    = { { "H", "Hillsbrad Foothills", "Christoph Jeffcoat" }, { "A", "Hillsbrad Foothills", "Chef Jessen" } },
    gikkix    = { { "N", "Tanaris", "Gikkix", "En el Puerto Bonvapor (Steamwheedle Port)." } },
}

ns.guides.cooking = {
    intro = "Ruta más rápida y barata de 1 a 300. Cocina no ocupa una de tus dos profesiones, así que cualquier personaje puede aprenderla. "
         .. "Casi todas las recetas solo piden carne o pescado que caen mientras subes de nivel, por eso cada tramo ofrece varias recetas: haz la que tengas ingredientes. "
         .. "Si también quieres subir Pesca, mira la guía combinada de Pesca y Cocina (en la página de Pesca).",
    apprenticeNote = "Cocina de aprendiz no tiene requisito de nivel. Todos los instructores enseñan también Cocina de oficial. Todas las zonas de inicio tienen instructor (casi siempre en la posada).",

    capitals = {
        { "H", "Orgrimmar", "Zamja" }, { "H", "Undercity", "Eunice Burch" }, { "H", "Thunder Bluff", "Aska Mistrunner" },
        { "A", "Stormwind City", "Stephen Ryback" }, { "A", "Ironforge", "Daryl Riknussun" }, { "A", "Darnassus", "Alegorn" },
    },
    starting = {
        { race = "Orco, Trol", zone = "Durotar", npcs = { { "H", "Durotar", "Cook Torka", "En Cerrotajo (Razor Hill)." } } },
        { race = "Tauren", zone = "Mulgore", npcs = { { "H", "Mulgore", "Pyall Silentstride", "Dentro de la tienda grande del poblado Pezuña de Sangre." } } },
        { race = "No-muerto", zone = "Tirisfal Glades", npcs = { { "H", "Tirisfal Glades", "William Pickman", "Dentro de la posada de Rémol (Brill)." } } },
        { race = "Humano", zone = "Elwynn Forest", npcs = { { "A", "Elwynn Forest", "Tomas", "En la cocina de la posada de Villadorada." } } },
        { race = "Enano, Gnomo", zone = "Dun Morogh", npcs = { { "A", "Dun Morogh", "Gremlock Pilsnor", "En la destilería Cebatruenos de Kharanos." } } },
        { race = "Elfo de la noche", zone = "Teldrassil", npcs = { { "A", "Teldrassil", "Zarrin", "En Dolanaar." } } },
        { race = "Skyborne", zone = "Zephras Isle", npcs = {
            { "N", "Zephras Isle", "Nyalah Brightfire", "En Valanaar." }, { "N", "Zephras Isle", "Zerril Softbreeze", "En el poblado Shen'dar." } } },
    },

    extras = {
        { title = "La fogata",
          text = "Necesitas una fogata para cocinar; a menudo hay una encendida junto al instructor. En Forever la fogata es un objeto: aprendes el Kit de fogata básica junto con Cocina y la colocas desde las bolsas. "
              .. "Para fabricar los kits necesitas Leña simple y un Yesquero (el yesquero solo se usa para fabricar, no para colocar el fuego). Más detalles en la sección Campamento.",
          spell = 1229737, items = "4470x1 4471x1", npcs = WOOD_VENDORS },
        { title = "Especias y agua",
          text = "Las especias suaves, picantes y calmantes y el Agua de manantial refrescante las vende el proveedor de suministros de cocina junto a tu instructor: no las compres en la subasta.",
          items = "2678x1 2692x1 3713x1 159x1" },
    },

    ranks = {
        { title = "Aprendiz", range = "1-50", steps = {
            { r = "1-50", n = 55, pick = true, spell = 7751, name = "Brilliant Smallfish", icon = "inv_misc_fish_07", mats = "6291x55", vendors = V.smallfish,
              note = "Haz unas 55 de UNA de estas recetas.",
              alt = {
                { n = 55, spell = 7752, name = "Slitherskin Mackerel", icon = "inv_misc_fish_24", mats = "6303x55", vendors = V.mackerel },
                { n = 55, spell = 2538, name = "Charred Wolf Meat", icon = "inv_misc_food_18", mats = "2672x55", note = "Instructor." },
                { n = 55, spell = 2540, name = "Roasted Boar Meat", icon = "inv_misc_food_18", mats = "769x55", note = "Instructor." },
                { n = 55, spell = 8604, name = "Herb Baked Egg", icon = "inv_egg_03", mats = "6889x55 2678x55", note = "Instructor." },
                { n = 55, spell = 15935, name = "Crispy Bat Wing", icon = "inv_misc_food_46", mats = "12223x55", note = "Solo Horda.",
                  vendors = { { "H", "Tirisfal Glades", "Abigail Shiel" } } },
                { n = 55, spell = 6413, name = "Scorpid Surprise", icon = "inv_misc_food_10", mats = "5466x55", note = "Solo Horda.",
                  vendors = { { "H", "Durotar", "Grimtak" } } },
                { n = 55, spell = 6412, name = "Kaldorei Spider Kabob", icon = "inv_misc_food_68", mats = "5465x55", quest = 4161,
                  note = "Solo Alianza. Recompensa de la misión Recipe of the Kaldorei (Zarrin, en Teldrassil).",
                  vendors = { { "A", "Teldrassil", "Zarrin", "Da la misión." } } },
              } },
        } },
        { title = "Oficial", range = "50-150", req = "Cocina 50 y nivel 10. Lo enseña tu mismo instructor.",
          text = "Aprende Cocina de oficial ANTES de seguir, sobre todo si cocinas en AFK: sin ella dejas de ganar puntos en 75.",
          steps = {
            { r = "50-100", n = 55, pick = true, spell = 7753, name = "Longjaw Mud Snapper", icon = "inv_misc_fish_32", mats = "6289x55", vendors = V.longjaw,
              note = "Haz unas 55 de cualquiera. La Carne de oso ahumada se vuelve amarilla antes: haz más o cocínala primero.",
              alt = {
                { n = 55, spell = 7827, name = "Rainbow Fin Albacore", icon = "inv_misc_fish_27", mats = "6361x55", vendors = V.albacore },
                { n = 70, spell = 8607, name = "Smoked Bear Meat", icon = "inv_misc_food_13", mats = "3173x70", note = "Entre 65 y 75.",
                  vendors = { { "H", "Silverpine Forest", "Andrew Hilbert" }, { "A", "Loch Modan", "Drac Roughcut" } } },
                { n = 55, spell = 6499, name = "Boiled Clams", icon = "inv_misc_shell_02", mats = "5503x55 159x55", note = "Instructor." },
                { n = 55, spell = 2541, name = "Coyote Steak", icon = "inv_misc_food_65", mats = "2673x55", note = "Instructor." },
                { n = 55, spell = 6416, name = "Strider Stew", icon = "inv_misc_bowl_01", mats = "5469x55 4536x55", quest = 2178,
                  note = "Horda: Tari'qa en Los Baldíos. Alianza: recompensa de la misión Easy Strider Living.",
                  vendors = { { "H", "The Barrens", "Tari'qa" } } },
              } },
            { r = "100-130", n = 30, pick = true, spell = 7755, name = "Bristle Whisker Catfish", icon = "inv_misc_fish_30", mats = "6308x55", vendors = V.catfish,
              note = "Haz unas 30-40 de cualquiera. Si eliges el Bagre, compra unos 55 (25 son para 130-150); en la beta compra unos 125, porque lo seguirás haciendo hasta 175.",
              alt = {
                { n = 40, spell = 2544, name = "Crab Cake", icon = "inv_misc_food_08", mats = "2674x40 2678x40", note = "Instructor." },
                { n = 35, spell = 2546, name = "Dry Pork Ribs", icon = "inv_misc_food_48", mats = "2677x35 2678x35", note = "Instructor." },
                { n = 35, spell = 2545, name = "Cooked Crab Claw", icon = "inv_misc_birdbeck_02", mats = "2675x35 2678x35", note = "Solo Alianza.",
                  vendors = { { "A", "Stormwind City", "Kendor Kabonka" } } },
              } },
            { r = "130-150", n = 25, pick = true, spell = 7755, name = "Bristle Whisker Catfish", icon = "inv_misc_fish_30", mats = "6308x25", vendors = V.catfish,
              note = "Haz unas 20-25 de cualquiera.",
              alt = {
                { n = 20, spell = 3376, name = "Curiously Tasty Omelet", icon = "inv_egg_04", mats = "3685x20 2692x20", vendors = V.omelet },
                { n = 25, spell = 6500, name = "Goblin Deviled Clams", icon = "inv_misc_shell_01", mats = "5504x25 2692x25", note = "Instructor." },
                { n = 25, spell = 3398, name = "Hot Lion Chops", icon = "inv_misc_food_18", mats = "3731x25 2692x25", note = "Solo Horda.", vendors = V.lion },
              } },
        } },
        { title = "Experto", range = "150-225",
          req = "Nivel 20 y Cocina 125. Se aprende comprando el Libro de cocina experto.",
          trainers = { { "H", "Desolace", "Wulan", "En el poblado Shadowprey. Vende el Libro de cocina experto." },
                       { "A", "Ashenvale", "Shandrina", "En el Lago Mystral. Vende el Libro de cocina experto." } },
          bookItem = 16072,
          steps = {
            { r = "150-175", n = 25, pick = true, spell = 3376, name = "Curiously Tasty Omelet", icon = "inv_egg_04", mats = "3685x25 2692x25", vendors = V.omelet,
              note = "Haz unas 25 de una de estas. La tortilla es amarilla desde 170.",
              alt = {
                { n = 25, spell = 3398, name = "Hot Lion Chops", icon = "inv_misc_food_18", mats = "3731x25 2692x25", note = "Solo Horda.", vendors = V.lion },
                { n = 70, spell = 7755, name = "Bristle Whisker Catfish", icon = "inv_misc_fish_30", mats = "6308x70", vendors = V.catfish,
                  note = "Beta: los Huevos de raptor y la Carne de león son difíciles de conseguir con el límite. Verde desde 160, así que necesitarás muchas." },
              } },
            { r = "175-225", n = 50, pick = true, spell = 20916, name = "Mithril Headed Trout", icon = "inv_misc_fish_02", mats = "8365x50", vendors = V.trout,
              note = "Haz unas 50 de una de estas. Las tres son amarillas desde 215.",
              alt = {
                { n = 50, spell = 15855, name = "Roast Raptor", icon = "inv_misc_food_50", mats = "12184x50 2692x50", vendors = V.raptor },
                { n = 50, spell = 3400, name = "Soothing Turtle Bisque", icon = "inv_misc_bowl_01", mats = "3712x50 3713x50", quest = { H = 7321, A = 555 },
                  note = "También es recompensa de la misión Soothing Turtle Bisque (Laderas de Trabalomas).", vendors = V.turtle },
              } },
        } },
        { title = "Artesano", range = "225-300", untested = true,
          req = "Nivel 35 y Cocina 225. Se obtiene con la misión Clamlette Surprise.",
          text = "Cocina mantiene todos los rangos de Classic, así que la ruta de Classic debería servir. Sin probar por el límite de la beta.\n"
              .. "1) Horda: toma To Gadgetzan You Go! de Zamja (Orgrimmar). Alianza: toma I Know A Guy... de Daryl Riknussun (Forjaz).\n"
              .. "2) Reúne 12 Huevos gigantes, 10 Carnes de almeja sabrosa y 20 Quesos de Alterac ANTES de ir a Gadgetzan, o harás el viaje dos veces.\n"
              .. "3) Busca a Dirge Quikcleave en Gadgetzan, toma Clamlette Surprise y entrega los objetos: te enseña Cocina de artesano en el momento. Compra TODAS las recetas de Gikkix en el Puerto Bonvapor.",
          quests = { { 6611, "To Gadgetzan You Go! (Horda)" }, { 6612, "I Know A Guy... (Alianza)" }, { 6610, "Clamlette Surprise" } },
          questItems = "12207x12 7974x10 8932x20",
          trainers = { { "N", "Tanaris", "Dirge Quikcleave", "En Gadgetzan." }, { "H", "Orgrimmar", "Zamja", "Misión inicial (Horda)." },
                       { "A", "Ironforge", "Daryl Riknussun", "Misión inicial (Alianza)." } },
          steps = {
            { r = "225-275", n = 65, pick = true, spell = 18238, name = "Spotted Yellowtail", icon = "inv_misc_fish_01", mats = "4603x65", vendors = V.gikkix,
              note = "Haz unas 65 de una de estas (hasta 285 si la carne o el pescado son muy baratos).",
              alt = {
                { n = 65, spell = 18241, name = "Filet of Redgill", icon = "inv_misc_fish_06", mats = "13758x65", vendors = { { "N", "Stranglethorn Vale", "Kelsey Yance" } } },
                { n = 65, spell = 20626, name = "Undermine Clam Chowder", icon = "inv_drink_17", mats = "7974x130 2692x65 1179x65",
                  note = "La Leche helada la venden casi todos los posaderos.", vendors = { { "N", "Tanaris", "Jabbey" } } },
                { n = 65, spell = 15933, name = "Monster Omelet", icon = "inv_misc_food_06", mats = "12207x65 3713x130",
                  vendors = { { "N", "Winterspring", "Himmik" }, { "A", "Felwood", "Malygen" }, { "H", "Felwood", "Bale" } } },
                { n = 65, spell = 22480, name = "Tender Wolf Steak", icon = "inv_misc_food_47", mats = "12208x65 3713x65",
                  vendors = { { "N", "Tanaris", "Dirge Quikcleave" } } },
              } },
            { r = "275-300", n = 35, pick = true, spell = 18244, name = "Poached Sunscale Salmon", icon = "inv_misc_fish_19", mats = "13760x35", vendors = V.gikkix,
              note = "Haz unas 35 de una de estas (o sigue con las anteriores hasta 285 si estas son caras). Amarillas desde 290.",
              alt = {
                { n = 35, spell = 18243, name = "Nightfin Soup", icon = "inv_drink_17", mats = "13759x35 159x35", vendors = V.gikkix },
                { n = 15, spell = 24801, name = "Smoked Desert Dumplings", icon = "inv_misc_food_64", mats = "20424x15 3713x15", quest = 8313,
                  note = "Receta de dos misiones en Silithus: Desert Recipe y Sharing the Knowledge (en Classic pide Cocina 285). La Carne de gusano de arena cae de los Dredge Strikers y Dredge Crushers de Silithus." },
              } },
        } },
    },
}
