local _, ns = ...
ns.guides = ns.guides or {}

ns.guides.tailoring = {
    intro = "Ruta más rápida y barata de 1 a 300. El tejido cae de los humanoides, así que no necesitas profesión de recolección y puedes combinar Sastrería con cualquier cosa. "
         .. "Encantamiento es la pareja más popular: desencantas lo que fabricas y usas el polvo para subirlo.",
    apprenticeNote = "Sastrería de aprendiz no tiene requisito de nivel en Forever.",

    shopping = {
        { title = "1-150", rows = {
            { "2589x60" }, { "2592x459" }, { "3383x29", note = "Lo compras en la subasta o a un alquimista." }, { "4306x216" }, { "4338x115" },
        } },
        { title = "150-225", rows = {
            { "4306x520" },
            { "4338x785", alt = "4339x157" },
        } },
        { title = "225-265", note = "Aún no es definitiva, pero los rangos vienen de los datos del juego, así que debería acercarse mucho. Se detiene en 265.", rows = {
            { "14047x1220" }, { "8170x172" },
        } },
    },

    capitals = {
        { "H", "Orgrimmar", "Snang", "En el Arrastradero (The Drag)." }, { "H", "Undercity", "Victor Ward" }, { "H", "Thunder Bluff", "Vhan", "En la meseta central." },
        { "A", "Stormwind City", "Lawrence Schneider" }, { "A", "Ironforge", "Uthrar Threx", "En la Gran Fundición." },
        { "A", "Darnassus", "Trianna", "En la Terraza de los Artesanos." },
    },
    starting = {
        { race = "Orco, Trol", zone = "Durotar", npcs = { { "H", "Orgrimmar", "Snang", "No hay en Durotar: Arrastradero de Orgrimmar." } } },
        { race = "Tauren", zone = "Mulgore", npcs = { { "H", "Thunder Bluff", "Vhan", "No hay en Mulgore: meseta central de Cima del Trueno." } } },
        { race = "No-muerto", zone = "Tirisfal Glades", npcs = { { "H", "Tirisfal Glades", "Bowen Brisboise", "En la casita de la Mansión Corazón Frío (Cold Hearth Manor), al suroeste de Rémol." } } },
        { race = "Humano", zone = "Elwynn Forest", npcs = { { "A", "Elwynn Forest", "Eldrin", "En una casa del Campamento Maderero de Vallefresno (Eastvale Logging Camp)." } } },
        { race = "Enano, Gnomo", zone = "Dun Morogh", npcs = { { "A", "Ironforge", "Uthrar Threx", "No hay en Dun Morogh: Gran Fundición de Forjaz." } } },
        { race = "Elfo de la noche", zone = "Teldrassil", npcs = { { "A", "Darnassus", "Trianna", "No hay en Teldrassil: Terraza de los Artesanos de Darnassus." } } },
        { race = "Skyborne", zone = "Zephras Isle", npcs = {
            { "N", "Zephras Isle", "Othesia Evengale", "En Valanaar." }, { "N", "Zephras Isle", "Taleen Shimmerthread", "En el poblado Shen'dar." } } },
    },

    extras = {
        { title = "Hilo y tintes",
          text = "Casi todos los instructores tienen al lado un proveedor de suministros de sastrería (hilos y tintes), salvo el de Tirisfal. Allí compra el Hilo basto en Rémol:",
          npcs = { { "H", "Tirisfal Glades", "Abigail Shiel", "En Rémol (Brill)." } } },
    },

    ranks = {
        { title = "Aprendiz", range = "1-55", steps = {
            { r = "1-30", n = 30, spell = 2963, name = "Bolt of Linen Cloth", icon = "inv_fabric_linen_02", mats = "2589x60",
              note = "Guarda los rollos: los necesitas todos para los cinturones." },
            { r = "30-55", n = 28, spell = 8776, name = "Linen Belt", icon = "inv_belt_05", mats = "2996x28 2320x28" },
        } },
        { title = "Oficial", range = "55-125", req = "Sastrería 50 y nivel 10.",
          trainers = {
            { "H", "Orgrimmar", "Magar" }, { "H", "Undercity", "Rhiannon Davis" }, { "H", "Thunder Bluff", "Tepa" },
            { "A", "Stormwind City", "Sellandus" }, { "A", "Ironforge", "Jormund Stonebrow" }, { "A", "Darnassus", "Me'lynn" } },
          steps = {
            { r = "55-80", n = 45, spell = 2964, name = "Bolt of Woolen Cloth", icon = "inv_fabric_wool_03", mats = "2592x135",
              note = "Aprende Sastrería de oficial antes: pasado 75 no subes hasta tenerla. Guarda los rollos: hasta 140 necesitas 153 (459 de Tejido de lana), así que puedes hacerlos todos ahora." },
            { r = "80-95", n = 22, spell = 2402, name = "Woolen Cape", icon = "inv_misc_cape_10", mats = "2997x22 2321x22",
              note = "Si los rollos te llevaron más allá de 80, haz capas hasta 95." },
            { r = "95-100", n = 5, spell = 3848, name = "Double-stitched Woolen Shoulders", icon = "inv_shoulder_06", mats = "2997x15 2321x10" },
            { r = "100-120", n = 54, spell = 3839, name = "Bolt of Silk Cloth", icon = "inv_fabric_silk_03", mats = "4306x216",
              note = "Guarda los rollos: hasta 190 necesitas 184 (736 de Paño de seda), así que puedes hacerlos todos ahora." },
            { r = "120-125", n = 5, spell = 3852, name = "Gloves of Meditation", icon = "inv_gauntlets_05", mats = "2997x20 2321x15 3383x5",
              note = "El Elixir de sabiduría lo compras en la subasta o a un alquimista." },
        } },
        { title = "Experto", range = "125-225", req = "Sastrería 125, nivel 20 y 50 de plata.",
          trainers = { { "H", "Undercity", "Josef Gregorian" }, { "A", "Stormwind City", "Georgio Bolero" } },
          steps = {
            { r = "125-140", n = 24, spell = 3852, name = "Gloves of Meditation", icon = "inv_gauntlets_05", mats = "2997x96 2321x72 3383x24",
              note = "Amarillos todo el tramo: quizá necesites alguno más." },
            { r = "140-150", n = 23, spell = 3865, name = "Bolt of Mageweave", icon = "inv_fabric_mageweave_03", mats = "4338x115",
              note = "Guarda los rollos: hasta 225 necesitas 180 (900 de Tejido mágico), así que puedes hacerlos todos ahora." },
            { r = "150-170", n = 20, spell = 8791, name = "Crimson Silk Vest", icon = "inv_shirt_04", mats = "4305x80 2604x40 2321x40" },
            { r = "170-190", n = 26, spell = 8799, name = "Crimson Silk Pantaloons", icon = "inv_pants_06", mats = "4305x104 2604x52 4291x52",
              note = "Amarillos desde 180: quizá necesites alguno más." },
            { r = "190-215", n = 38, spell = 12053, name = "Black Mageweave Gloves", icon = "inv_gauntlets_05", mats = "4339x76 8343x76",
              note = "Amarillos desde 195 y verdes desde 210: probablemente necesites alguno más." },
            { r = "215-225", n = 26, spell = 12065, name = "Mageweave Bag", icon = "inv_misc_bag_10_black", mats = "4339x104 4291x52" },
        } },
        { title = "Artesano", range = "225-300", req = "Sastrería 200 y nivel 35.", untested = true,
          text = "Aún no se ha podido probar por el límite de nivel de la beta. Muchos rangos cambiaron respecto a Classic Era (la mayoría de recetas se vuelven grises entre 25 y 45 puntos antes): no sigas la guía de Classic para este tramo.",
          trainers = { { "H", "Hillsbrad Foothills", "Daryl Stack", "En Molino Tarren (Tarren Mill)." }, { "A", "Dustwallow Marsh", "Timothy Worthington", "En Isla Theramore." } },
          steps = {
            { r = "225-240", n = 24, spell = 18402, name = "Runecloth Belt", icon = "inv_belt_13", mats = "14048x72 14341x24",
              note = "Se aprende con los dos instructores de artesano. Amarillo todo el tramo: quizá necesites alguno más. Hasta 265 necesitas 244 Rollos de paño rúnico (1220 de Paño rúnico); los rollos ya no dan puntos, así que puedes hacerlos todos ahora." },
            { r = "240-265", n = 43, spell = 18417, name = "Runecloth Gloves", icon = "inv_gauntlets_18", mats = "14048x172 8170x172 14341x43",
              note = "Amarillos desde 245 y verdes desde 260: probablemente necesites alguno más.",
              vendors = { { "N", "Winterspring", "Qia", "Vende el patrón en Vista Eterna (Everlook)." } } },
            { r = "265-300",
              text = "La web aún no publica este tramo: no hay receta de instructor ni de vendedor para pasar de 265. Las candidatas son dos patrones que caen en el mundo (materiales para una fabricación):",
              alt = {
                { spell = 18449, name = "Runecloth Shoulders", icon = "inv_shoulder_02", mats = "14048x7 4337x2 8170x4 14341x1" },
                { spell = 18450, name = "Wizardweave Turban", icon = "inv_helmet_29", mats = "14048x6 11176x4 7910x1 14341x1" },
              } },
          } },
    },
}
