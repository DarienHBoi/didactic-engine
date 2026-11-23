local _, ns = ...
ns.guides = ns.guides or {}

local PICK_VENDORS = {
    { "H", "Durotar", "Norzsh", "En el Valle de los Retos." }, { "H", "Durotar", "Flakk", "En Cerrotajo (Razor Hill)." },
    { "H", "Mulgore", "Vartha Rockmane", "En el Campamento Narache." }, { "H", "Mulgore", "Wunna Darkmane", "En el poblado Pezuña de Sangre." },
    { "H", "Tirisfal Glades", "Walter Mason", "En el Camposanto (Deathknell)." }, { "H", "Tirisfal Glades", "Abigail Shiel", "En Rémol (Brill)." },
    { "H", "Orgrimmar", "Gorina", "En el Valle del Honor." }, { "H", "Undercity", "Elizabeth Van Talen", "En el Barrio de los Pícaros." },
    { "H", "Thunder Bluff", "Kurm Stonehoof" },
    { "A", "Elwynn Forest", "Brother Danil", "En el Valle de Villanorte." }, { "A", "Elwynn Forest", "Tharynn Bouden", "En Villadorada (Goldshire)." },
    { "A", "Dun Morogh", "Thrawn Boltar", "En Kharanos." },
    { "A", "Teldrassil", "Fanorran Stilloak", "En Aldrassil, Cañada Umbría." }, { "A", "Teldrassil", "Narret Shadowgrove", "En Dolanaar." },
    { "A", "Stormwind City", "Brooke Stonebraid", "En el Distrito de los Enanos." }, { "A", "Ironforge", "Thurgrum Deepforge", "En la Gran Fundición." },
    { "A", "Darnassus", "Mythrin'dir" },
    { "N", "Zephras Isle", "Uualia Suncrest", "En Thendal Village." }, { "N", "Zephras Isle", "Belandiel Farflight", "En el poblado Shen'dar." },
}

ns.guides.mining = {
    gather = true,
    intro = "La forma más rápida de subir Minería de 1 a 300, con las mejores zonas para cada tramo. Minería sirve a Herrería e Ingeniería, así que combina muy bien con cualquiera de las dos. "
         .. "Forever añadió minerales, barras y objetos de campamento nuevos.",
    apprenticeNote = "Todas las capitales salvo Darnassus tienen instructor. Los nuevos instructores júnior de las zonas de inicio solo enseñan hasta 75: no enseñan Minería de oficial.",

    shopping = {
        { title = "Fundir hasta 105", note = "Solo si eliges la ruta de fundición. Fundir es casi siempre amarillo y verde: quizá necesites algún mineral más.", rows = {
            { "2770x140" }, { "2771x70" },
            { "2775x45", note = "Opcional (105-120): mira antes el precio del Mineral de plata y de la Barra de plata." },
        } },
    },

    capitals = {
        { "H", "Orgrimmar", "Makaru" }, { "H", "Undercity", "Brom Killian" }, { "H", "Thunder Bluff", "Brek Stonehoof" },
        { "A", "Stormwind City", "Gelman Stonehand" }, { "A", "Ironforge", "Geofram Bouldertoe" },
        { "A", "Darkshore", "Kurdram Stonehammer", "Darnassus no tiene instructor: el más cercano está en Auberdine, Costa Oscura." },
    },
    starting = {
        { race = "Orco, Trol", zone = "Durotar", npcs = {
            { "H", "Durotar", "Norzsh", "En el Valle de los Retos (solo hasta 75)." }, { "H", "Durotar", "Krunn", "En Cerrotajo (Razor Hill)." } } },
        { race = "Tauren", zone = "Mulgore", npcs = { { "H", "Mulgore", "Vartha Rockmane", "En el Campamento Narache (solo hasta 75)." } } },
        { race = "No-muerto", zone = "Tirisfal Glades", npcs = { { "H", "Tirisfal Glades", "Walter Mason", "En el Camposanto (Deathknell), solo hasta 75." } } },
        { race = "Humano", zone = "Elwynn Forest", npcs = { { "A", "Elwynn Forest", "Kelsey Fargo", "Solo hasta 75." } } },
        { race = "Enano, Gnomo", zone = "Dun Morogh", npcs = {
            { "A", "Dun Morogh", "Sally Swiftwrench", "Solo hasta 75." }, { "A", "Dun Morogh", "Yarr Hammerstone", "En el Depósito de Steelgrill." },
            { "A", "Dun Morogh", "Dank Drizzlecut", "En la Cantera de Gol'Bolar." } } },
        { race = "Elfo de la noche", zone = "Teldrassil", npcs = {
            { "A", "Teldrassil", "Fanorran Stilloak", "En Aldrassil, Cañada Umbría (solo hasta 75)." },
            { "A", "Darkshore", "Kurdram Stonehammer", "Después, en Auberdine, Costa Oscura." } } },
        { race = "Skyborne", zone = "Zephras Isle", npcs = {
            { "N", "Zephras Isle", "Halavuul Cragwind", "En Valanaar." }, { "N", "Zephras Isle", "Messana Crestwind", "En el poblado Shen'dar." } } },
    },

    extras = {
        { title = "Skyborne: Minería sin instructor",
          text = "En Thendal Village, donde empiezas, no hay instructor, pero no lo necesitas: Harvesting Windstones es una de las primeras misiones del pueblo. Elige Mining for Dummies como recompensa y te enseña Minería." },
        { title = "Rastrear minerales", spell = 2580,
          text = "Aprendes Buscar minerales junto con Minería, pero no se activa solo: ábrelo desde la ventana de profesiones y arrástralo a tu barra, junto a los beneficios que te pones al morir. "
              .. "Solo puedes rastrear una cosa a la vez (minerales o hierbas) y el rastreo se apaga cada vez que mueres." },
        { title = "Bonificaciones de habilidad",
          text = "No son necesarias, pero ayudan cuando te faltan unos puntos: con +5 puedes extraer Depósitos de hierro desde 120 en vez de 125 y saltarte los últimos puntos lentos del Estaño. "
              .. "Encantar guantes: minería (+2) y minería avanzada (+5) te los pone un encantador. El Casco de minero goblin (+5) lo fabrican los ingenieros (necesitas Ingeniería 205 para llevarlo). "
              .. "La Capa de minero (+2) cae de Miner Johnson en Las Minas de la Muerte." },
        { title = "Pico de minero", item = 2901,
          text = "Cómpralo al proveedor de suministros de minería junto a tu instructor o al propio instructor: tiene que estar en tus bolsas para extraer.",
          npcs = PICK_VENDORS },
    },

    ranks = {
        { title = "Aprendiz y oficial", range = "1-125", req = "Minería de oficial (para pasar de 75): Minería 50. Apréndela con tu instructor; los instructores júnior no la enseñan.",
          blocks = {
            { title = "Fundir o extraer", group = "mining1",
              text = "Puedes saltarte los primeros 105 puntos comprando mineral en la subasta y fundiéndolo. Si tienes el oro, la web lo recomienda: ahorra mucho tiempo y a veces las barras se venden casi por lo mismo que el mineral.",
              routes = {
                { title = "Fundir (comprando mineral)", steps = {
                    { r = "1-65", n = 130, spell = 2657, name = "Smelt Copper", icon = "inv_ingot_02", mats = "2770x130",
                      note = "Entre 120 y 140 fundiciones hasta 65. Guarda 70 Barras de cobre para el Bronce." },
                    { r = "65-75", n = 70, spell = 3304, name = "Smelt Tin", icon = "inv_ingot_05", mats = "2771x70",
                      note = "Aprende Minería de oficial, Fundir estaño y Fundir bronce. Se vuelve gris en 75, pero necesitas las 70 Barras de estaño para el Bronce igualmente." },
                    { r = "75-105", n = 70, spell = 2659, name = "Smelt Bronze", icon = "inv_ingot_bronze", mats = "2840x70 3576x70",
                      note = "Acabarás entre 100 y 110: quizá necesites alguna más." },
                    { r = "105-120", n = 40, spell = 2658, name = "Smelt Silver", icon = "inv_ingot_01", mats = "2775x40",
                      note = "Opcional: mira antes el precio de la Plata. Entre 35 y 45 hasta 120; los últimos 5 puntos hasta 125 pueden costar unos 50 minerales más, así que mejor ponte a extraer desde 120." },
                    { r = "120-125", short = "Extrae Estaño hasta 125 (o Hierro con +5)",
                      text = "Extrae en las zonas de 65-125. Con +5 de bonificación de habilidad puedes extraer Depósitos de hierro desde 120 y pasar directamente al tramo siguiente.",
                      zones = { "Wetlands", "Silverpine Forest", "Westfall", "Hillsbrad Foothills", "The Barrens", "Ashenvale", "Stonetalon Mountains" } },
                } },
                { title = "Extraer", steps = {
                    { r = "1-65", short = "Extrae Cobre en tu zona de inicio",
                      text = "Una o dos vueltas por la zona te dan Mineral de cobre suficiente para llegar a 65 fundiéndolo. La reaparición es muy rápida en Forever. "
                          .. "Horda: Durotar (funde en Cerrotajo), la cueva de Mulgore con 5 vetas (puedes quedarte dentro; funde en la Excavación Bael'dun, con enanos hostiles) o Tirisfal (funde en Rémol). "
                          .. "Alianza: Elwynn (ida y vuelta por la ruta y la cueva; funde en Villadorada), Dun Morogh (funde en Kharanos) o las dos cuevas de Teldrassil (no hay forja: la más cercana está en la Terraza del Guerrero de Darnassus). "
                          .. "Zephras Isle: alrededor del poblado Shen'dar, donde funde.",
                      zones = { "Durotar", "Mulgore", "Tirisfal Glades", "Elwynn Forest", "Dun Morogh", "Teldrassil", "Zephras Isle" } },
                    { r = "65-125", short = "Estaño, Cobre y Plata (Humedales, Argénteos, Trabalomas...)",
                      text = "Aprende Minería de oficial. Si te queda Mineral de cobre o de estaño, fúndelo y haz Bronce antes de salir: fundir deja de dar puntos hacia 105. Vetas de estaño desde 65 y de plata desde 75. "
                          .. "Alianza: la cueva de Los Humedales es la mejor con diferencia (Estaño e Incendicita con reaparición muy rápida). Horda: la cueva de Bosque de Argénteos (3 vetas, unos 2 minutos de reaparición) o Laderas de Trabalomas. "
                          .. "Las demás están muy igualadas. En Forever los enemigos de las cuevas reaparecen mucho más rápido: sácales bastantes niveles.",
                      zones = { "Wetlands", "Silverpine Forest", "Westfall", "Hillsbrad Foothills", "The Barrens", "Ashenvale", "Stonetalon Mountains" } },
                } },
              } },
          } },
        { title = "Experto", range = "125-175", req = "Minería 125 (Minería de experto, para pasar de 150).",
          steps = {
            { r = "125-175", short = "Hierro, Estaño y Oro (Arathi, Las Mil Agujas, Desolace)",
              text = "Depósitos de hierro desde 125 y vetas de oro desde 155. Con un personaje de nivel 30 quédate en Las Mil Agujas, la ruta más segura; con más nivel o montura, Tierras Altas de Arathi. "
                  .. "En Arathi hay 4 cuevas: llega hasta el fondo de cada una (desde la entrada no ves todas las vetas). Con poco nivel sáltate las cuevas, y si eres de la Alianza da un rodeo por el sur de Sentencia (Hammerfall). "
                  .. "Desde aquí la web sigue las rutas de Classic; la mayor diferencia es la reaparición, así que probablemente puedas hacer rutas más cortas.",
              zones = { "Arathi Highlands", "Thousand Needles", "Desolace" },
              also = {
                { r = "125-135", n = 20, spell = 3307, name = "Smelt Iron", icon = "inv_ingot_iron", mats = "2772x20",
                  note = "Opcional, antes de salir: unas 20 hasta 135. Después casi nunca da punto." },
                { r = "155-175", n = 22, spell = 3308, name = "Smelt Gold", icon = "inv_ingot_03", mats = "2776x22",
                  note = "Opcional: se aprende en 155 y da punto siempre hasta 170, así que unos 22 Minerales de oro te llevan a 175. Mira antes el precio del Oro." },
              } },
        } },
        { title = "Artesano", range = "175-300", req = "Minería 200 (Minería de artesano, para pasar de 225).",
          steps = {
            { r = "175-245", short = "Mitril y Veraplata (Tierras del Interior, Tanaris)",
              text = "Depósitos de mitril desde 175 y de veraplata desde 230. Aprende Minería de artesano al llegar a 200. "
                  .. "Tierras del Interior: los personajes de nivel bajo deben saltarse la ruta llena de élites de nivel 62 y quizá la cueva marcada. Tanaris: por debajo de nivel 60 sáltate sus 4 cuevas.",
              zones = { "The Hinterlands", "Tanaris" } },
            { r = "245-275", short = "Torio pequeño (Un'Goro, Tierras Devastadas, Frondavil)",
              text = "Vetas pequeñas de torio desde 245. Un'Goro: 2 o 3 vetas en las dos cuevas (con poco nivel sáltate la del sur). "
                  .. "Tierras Devastadas: sus dos cuevas están llenas de enemigos, solo para nivel 60 con buen equipo o druidas y pícaros con sigilo; la Alianza no puede extraer en la Garrison Armory. "
                  .. "Frondavil: la cueva pequeña suele tener 2 vetas y merece la pena; sáltate las otras dos de Jaedenar.",
              zones = { "Un'Goro Crater", "Blasted Lands", "Felwood" } },
            { r = "275-300", short = "Torio rico (Un'Goro, Tierras de la Peste del Este...)",
              text = "Desde 275 también puedes extraer Vetas de torio enriquecido. Un'Goro: casi la misma ruta que antes. Tierras de la Peste del Este: parte de la ruta está llena de élites de nivel 57-58. "
                  .. "Cuna del Invierno: la cueva se puede limpiar, pero el desfiladero tiene muchas élites patrullando. Las Estepas Ardientes: dos cuevas con enemigos de nivel 50.",
              zones = { "Un'Goro Crater", "Eastern Plaguelands", "Winterspring", "Burning Steppes" } },
        } },
    },
}
