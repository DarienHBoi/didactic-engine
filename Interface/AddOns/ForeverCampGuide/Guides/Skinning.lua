local _, ns = ...
ns.guides = ns.guides or {}

ns.guides.skinning = {
    gather = true, noRecipes = true,
    intro = "La forma más rápida de subir Desuello de 1 a 300, con los mejores sitios para cada tramo. Está pensada para personajes de nivel alto que cambian de profesión, pero también sirve para los de nivel bajo. "
         .. "Es fácil pero muy repetitivo: tendrás que desollar cientos de bichos. Combina con Peletería, porque usas el cuero que consigues.",
    apprenticeNote = "Todas las capitales tienen instructor. Los nuevos instructores júnior de las zonas de inicio solo enseñan hasta 75: no enseñan Desuello de oficial.",

    capitals = {
        { "H", "Orgrimmar", "Thuwd" }, { "H", "Undercity", "Killian Hagey" }, { "H", "Thunder Bluff", "Mooranta" },
        { "A", "Stormwind City", "Maris Granger" }, { "A", "Ironforge", "Balthus Stoneflayer" }, { "A", "Darnassus", "Eladriel" },
    },
    starting = {
        { race = "Orco, Trol", zone = "Durotar", npcs = {
            { "H", "Durotar", "Kagil", "En el Valle de los Retos (solo hasta 75)." }, { "H", "Orgrimmar", "Thuwd", "Después, en Orgrimmar." } } },
        { race = "Tauren", zone = "Mulgore", npcs = {
            { "H", "Mulgore", "Nawka Wildsong", "En el Campamento Narache (solo hasta 75)." }, { "H", "Mulgore", "Yonn Deepcut", "En el poblado Pezuña de Sangre." } } },
        { race = "No-muerto", zone = "Tirisfal Glades", npcs = {
            { "H", "Tirisfal Glades", "Margaret Weaver", "En el Camposanto (Deathknell), solo hasta 75." }, { "H", "Tirisfal Glades", "Rand Rhobart" } } },
        { race = "Humano", zone = "Elwynn Forest", npcs = {
            { "A", "Elwynn Forest", "Riley Peltskinner", "En el Valle de Villanorte (solo hasta 75)." }, { "A", "Elwynn Forest", "Helene Peltskinner", "En Villadorada (Goldshire)." } } },
        { race = "Enano, Gnomo", zone = "Dun Morogh", npcs = {
            { "A", "Dun Morogh", "Brighid Stormflayer", "Solo hasta 75." }, { "A", "Ironforge", "Balthus Stoneflayer", "Después, en Forjaz." } } },
        { race = "Elfo de la noche", zone = "Teldrassil", npcs = {
            { "A", "Teldrassil", "Terunne Bearshaper", "En Aldrassil, Cañada Umbría (solo hasta 75)." }, { "A", "Teldrassil", "Radnaal Maneweaver" } } },
        { race = "Skyborne", zone = "Zephras Isle", npcs = {
            { "N", "Zephras Isle", "Ishlee Breezewhisper", "En Valanaar." }, { "N", "Zephras Isle", "Mendalass Tattermend", "En el poblado Shen'dar." } } },
    },

    extras = {
        { title = "Skyborne: Desuello sin instructor",
          text = "En Thendal Village, donde empiezas, no hay instructor, pero no lo necesitas: Harvesting Windstones es una de las primeras misiones del pueblo. Elige Pelt Collecting for Beginners como recompensa y te enseña Desuello." },
        { title = "Cuchillo de desollar", item = 7005,
          text = "Lo venden los proveedores de suministros de peletería junto a tu instructor y casi todos los vendedores de objetos generales. No hace falta equiparlo, pero sin él en las bolsas no puedes desollar." },
        { title = "Qué bichos puedes desollar",
          text = "Necesitas 5 veces el nivel del bicho en Desuello: uno de nivel 30 pide Desuello 150. Por debajo de nivel 20 es menos: hasta nivel 10 basta con 1; de 11 a 19, 10 para nivel 11 y 10 más por cada nivel (nivel 15 pide 50, nivel 19 pide 90). "
              .. "Si sigues la guía no tienes que preocuparte. Con Encantar guantes: desuello puedes desollar bichos un nivel por encima de lo normal." },
    },

    ranks = {
        { title = "Aprendiz", range = "1-75",
          steps = {
            { r = "1-75", short = "Desuella en tu zona de inicio",
              text = "En Forever los bichos de las zonas de inicio se pueden desollar y dan puntos hasta 75. Si subes un personaje nuevo, desuella todo lo que mates en tu zona. "
                  .. "Si ya tienes un personaje de nivel alto: Horda, los Jabalíes moteados (Mottled Boar) del Valle de los Retos en Durotar; Alianza, los Lobos jóvenes y Lobos del bosque (Young Wolf, Timber Wolf) del Valle de Villanorte en Elwynn. Nivel 1-2.",
              zones = { "Durotar", "Elwynn Forest" } },
        } },
        { title = "Oficial", range = "75-150", req = "Desuello 50 (Desuello de oficial). Vuelve en 125 para aprender Desuello de experto y pasar de 150.",
          steps = {
            { r = "75-150", short = "Horda: Los Baldíos · Alianza: Loch Modan y Los Humedales",
              text = "Horda: Los Baldíos, en el pequeño campamento de raptores al oeste del Bastión del Norte (Northwatch Hold). Desuella Sunscale Scytheclaw, Zhevra Charger y Ornery Plainstrider: los de nivel 16-17 hasta 80 y desde 80 también los de 18. Quédate hasta 150; los últimos 10 puntos son verdes pero reaparecen rápido. "
                  .. "Alianza: de 75 a 125 en Loch Modan (Elder Mountain Boar, Black Bear Patriarch y los Loch Crocolisk de la orilla, nivel 16-17); de 125 a 150 en Los Humedales, en la Excavación de Whelgar (Mottled Scytheclaw y Mottled Razormaw, nivel 25-27).",
              zones = { "The Barrens", "Loch Modan", "Wetlands" } },
        } },
        { title = "Experto", range = "150-225",
          steps = {
            { r = "150-225", short = "Yetis de Laderas de Trabalomas o huargos de Bosque del Ocaso",
              text = "Cuevas de las Colinas (Foothill Caverns) en Laderas de Trabalomas, la cueva de yetis en el límite con Alterac: Cave Yeti y Ferocious Yeti, nivel 30-32. Reaparecen tan rápido que puedes quedarte dentro todo el rato. La Horda llega desde Molino Tarren y la Alianza desde Costa Sur. "
                  .. "Alternativa: Bosque del Ocaso (la Horda llega desde Grom'gol): Nightbane Worgen, Shadow Weaver y Dark Runner, nivel 26-29. Limpia fuera y dentro de la cueva de Roland's Doom y luego ve al Huerto Podrido (Rotting Orchard) mientras reaparecen.",
              zones = { "Hillsbrad Foothills", "Alterac Mountains", "Duskwood" } },
        } },
        { title = "Artesano", range = "225-300", req = "Desuello 200 (Desuello de artesano, para pasar de 225).",
          steps = {
            { r = "225-280", short = "Yetis de Feral Scar Vale, Feralas",
              text = "Ve con montura a la cueva de yetis de Feral Scar Vale, al sur de Feralas: Feral Scar Yeti, Enraged Feral Scar y Hulking Feral Scar, nivel 43-46. La Horda llega desde el Campamento Mojache y la Alianza desde el Bastión Plumaluna.",
              zones = { "Feralas" } },
            { r = "280-300", short = "Dinosaurios del oeste de Un'Goro",
              text = "Vuela al Refugio del Señor (Marshal's Refuge) y desuella los dinosaurios del oeste de Un'Goro: Diemetradon, Pterrordax, Elder Diemetradon y Frenzied Pterrordax, nivel 50-55.",
              zones = { "Un'Goro Crater" } },
        } },
    },
}
