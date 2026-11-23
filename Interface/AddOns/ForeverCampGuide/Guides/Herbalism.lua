local _, ns = ...
ns.guides = ns.guides or {}

ns.guides.herbalism = {
    gather = true, noRecipes = true,
    intro = "La forma más rápida de subir Herboristería de 1 a 300, con las mejores zonas para cada tramo. Combina con Alquimia, porque usas las hierbas para pociones y elixires; "
         .. "pero la ruta busca subir rápido, así que no siempre recoges las mejores hierbas para Alquimia. Forever añadió hierbas, semillas y objetos de campamento nuevos.",
    apprenticeNote = "Todas las capitales tienen instructor. Los nuevos instructores júnior de las zonas de inicio solo enseñan hasta 75: no enseñan Herboristería de oficial.",

    capitals = {
        { "H", "Orgrimmar", "Jandi" }, { "H", "Undercity", "Martha Alliestar" }, { "H", "Thunder Bluff", "Komin Winterhoof" },
        { "A", "Stormwind City", "Tannysa" }, { "A", "Ironforge", "Reyna Stonebranch" }, { "A", "Darnassus", "Firodren Mooncaller" },
    },
    starting = {
        { race = "Orco, Trol", zone = "Durotar", npcs = {
            { "H", "Durotar", "Zor'la", "En el Valle de los Retos (solo hasta 75)." }, { "H", "Durotar", "Mishiki", "En el poblado Sen'jin." } } },
        { race = "Tauren", zone = "Mulgore", npcs = {
            { "H", "Mulgore", "Garan Sunstrider", "En el Campamento Narache (solo hasta 75)." },
            { "H", "Thunder Bluff", "Komin Winterhoof", "Después, en Cima del Trueno." } } },
        { race = "No-muerto", zone = "Tirisfal Glades", npcs = {
            { "H", "Tirisfal Glades", "Florence Nightshade", "En el Camposanto (Deathknell), solo hasta 75." }, { "H", "Tirisfal Glades", "Faruza", "En Rémol (Brill)." } } },
        { race = "Humano", zone = "Elwynn Forest", npcs = {
            { "A", "Elwynn Forest", "Nancy Songflower", "Solo hasta 75." }, { "A", "Elwynn Forest", "Herbalist Pomeroy" } } },
        { race = "Enano, Gnomo", zone = "Dun Morogh", npcs = {
            { "A", "Dun Morogh", "Emrys Flintbeard", "Solo hasta 75." }, { "A", "Loch Modan", "Kali Healtouch", "Después, en Thelsamar, Loch Modan." } } },
        { race = "Elfo de la noche", zone = "Teldrassil", npcs = {
            { "A", "Teldrassil", "Eleyna Duskbreeze", "En Aldrassil, Cañada Umbría (solo hasta 75)." }, { "A", "Teldrassil", "Malorne Bladeleaf", "En Dolanaar." } } },
        { race = "Skyborne", zone = "Zephras Isle", npcs = {
            { "N", "Zephras Isle", "Syriel Nightrain", "En Valanaar." }, { "N", "Zephras Isle", "Halassa Fernbreeze", "En el poblado Shen'dar." } } },
    },

    extras = {
        { title = "Skyborne: Herboristería sin instructor",
          text = "En Thendal Village, donde empiezas, no hay instructor, pero no lo necesitas: Harvesting Windstones es una de las primeras misiones del pueblo. Elige Wild Harvest como recompensa y te enseña Herboristería." },
        { title = "Rastrear hierbas", spell = 2383,
          text = "Aprendes Buscar hierbas junto con Herboristería, pero no se activa solo: ábrelo desde la ventana de profesiones y arrástralo a tu barra, junto a los beneficios que te pones al morir. "
              .. "Solo puedes rastrear una cosa a la vez (hierbas o minerales) y el rastreo se apaga cada vez que mueres." },
        { title = "Bonificaciones de habilidad",
          text = "No son necesarias, pero ayudan cuando te faltan unos puntos: con +5 puedes recoger Sangrerregia desde 120 en vez de 125. "
              .. "Encantar guantes: herboristería (+2) y herboristería avanzada (+5) te los pone un encantador. Los Guantes de herborista (+5) son botín del mundo: búscalos en la subasta. "
              .. "El Té de espina de oro (+15) lo enseña Henry Stern en Zahúrda Rajacieno (Razorfen Downs) y pide Cocina 175: toma el camino de la izquierda al entrar, ve hasta los establos del fondo, derriba las paredes y habla con él. "
              .. "Lleva unos cuantos tés: sirven cuando encuentras una hierba que aún no puedes recoger por pocos puntos." },
    },

    ranks = {
        { title = "Aprendiz y oficial", range = "1-115", req = "Herboristería de oficial (para pasar de 75): Herboristería 50. Apréndela con tu instructor; los instructores júnior no la enseñan.",
          steps = {
            { r = "1-70", short = "Flor de paz, Hojaplata y Raíz de tierra en tu zona de inicio",
              text = "Todas las zonas de inicio están llenas de hierbas (Flor de paz, Hojaplata y Raíz de tierra, esta desde 15), así que da igual cuál elijas. "
                  .. "La reaparición es tan rápida que, sin montura, muchas veces ni terminas la vuelta: corre en círculos y recoge lo que veas.",
              zones = { "Durotar", "Mulgore", "Tirisfal Glades", "Elwynn Forest", "Dun Morogh", "Teldrassil", "Zephras Isle" } },
            { r = "70-115", short = "Marregal, Brezospina y Algaestrangulante (Argénteos, Loch Modan, Costa Oscura)",
              text = "Aprende Herboristería de oficial. Hierbas: Marregal, Brezospina y Algaestrangulante (esta desde 85). "
                  .. "En la parte baja de Bosque de Argénteos la reaparición permite correr en círculos pequeños. Loch Modan es muy fácil de seguir pero tiene algo menos de hierbas que Costa Oscura, donde hay hierbas por todas partes.",
              zones = { "Silverpine Forest", "Loch Modan", "Darkshore" } },
        } },
        { title = "Experto", range = "115-205", req = "Herboristería 125 (Herboristería de experto, para pasar de 150).",
          steps = {
            { r = "115-170", short = "Hierba cardenal, Acérita salvaje y más (Trabalomas, Sierra Espolón)",
              text = "Hierbas: Hierba cardenal, Acérita salvaje, Algaestrangulante, Sangrerregia (desde 125) y Vidarraíz (desde 150). Ve a las zonas marcadas en rojo de la web solo después de pasar 150. "
                  .. "Laderas de Trabalomas: la vuelta da tiempo a que reaparezcan. Sierra Espolón tiene tres zonas buenas; la más baja tiene enemigos de nivel 14-15 y es la más segura.",
              zones = { "Hillsbrad Foothills", "Stonetalon Mountains" } },
            { r = "170-205", short = "Sangrerregia, Vidarraíz, Hojapálida y Espina de oro (Tuercespina, Arathi)",
              text = "Hierbas: Sangrerregia, Vidarraíz, Hojapálida, Espina de oro y Mostacho de Khadgar (este desde 185). Desde aquí la web sigue las rutas de Classic; la mayor diferencia es la reaparición.",
              zones = { "Stranglethorn Vale", "Arathi Highlands" } },
        } },
        { title = "Artesano", range = "205-300", req = "Herboristería 200 (Herboristería de artesano, para pasar de 225).",
          steps = {
            { r = "205-230", short = "Loto púrpura y Flor de fuego (Tanaris, La Garganta de Fuego)",
              text = "Aprende Herboristería de artesano antes de ir: en Tanaris y La Garganta de Fuego no hay instructor y tendrías que volver en 225. Hierbas: Loto púrpura y Flor de fuego.",
              zones = { "Tanaris", "Searing Gorge" } },
            { r = "230-270", short = "Solea, Loto púrpura, Champiñón fantasma (Tierras del Interior)",
              text = "Hierbas: Solea, Loto púrpura, Champiñón fantasma y Sansam dorado. La cueva marcada en la web tiene muchos Champiñones fantasma, pero solo puedes recogerlos desde 245.",
              zones = { "The Hinterlands" } },
            { r = "270-300", short = "Hierbas de Frondavil",
              text = "Hierbas: Solea, Gromsanguina, Sansam dorado, Hojasueño, Salvia de montaña y Flor de peste.",
              zones = { "Felwood" } },
        } },
    },
}
