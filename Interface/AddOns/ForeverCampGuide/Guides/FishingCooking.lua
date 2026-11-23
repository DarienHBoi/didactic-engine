local _, ns = ...
ns.guides = ns.guides or {}

-- Guía combinada en forma de lista de tareas (casillas que se guardan por personaje).
-- Cada sección tiene tareas comunes (all), separadas por facción (H / A) u opciones de zona
-- (options = { { f = "H"|"A"|"N", title, tasks } }).
-- tarea: { id único, texto, npc = NPC opcional, items = "id x n", quest = ID, skill = { "fishing"|"cooking", objetivo } }
ns.guides.fishcook = {
    title = "Pesca y Cocina juntas",
    intro = "Subir Pesca lleva mucho tiempo, así que conviene hacerlo junto con Cocina: cada pez que sacas es también una receta y tu Cocina sube gratis mientras pescas. "
         .. "Marca cada tarea al completarla; las casillas se guardan por personaje. Desde el nivel 35 la ruta es la de Classic y aún no está probada en la beta.",

    sections = {
        { title = "Pesca hasta 75",
          note = "Elige una zona de tu facción. Las recomendadas son Mulgore (Horda) y el Bosque de Elwynn (Alianza).",
          options = {
            { f = "H", title = "Mulgore (recomendada)", tasks = {
                { "v2_hm1", "Compra las recetas de Pececillo brillante y Pargo boquilargo, una Caña de pescar, Baratijas brillantes y cualquier Atrayente acuadinámico que veas.",
                  npc = { "H", "Mulgore", "Harn Longcast", "En el poblado Pezuña de Sangre." }, items = "6325x1 6328x1 6256x1 6529x5" },
                { "v2_hm2", "Aprende Pesca si aún no la tienes.", npc = { "H", "Mulgore", "Uthan Stillwater", "En el lago Stonebull." } },
                { "v2_hm3", "Equípate la caña, pon la baratija y pesca en el lago Stonebull hasta 75 (unos 45 Pececillos brillantes y 30 Pargos boquilargos).",
                  skill = { "fishing", 75 }, zone = "Mulgore" },
                { "v2_hm4", "Aprende Pesca de oficial (nivel 10).", npc = { "H", "Mulgore", "Uthan Stillwater" } },
            } },
            { f = "H", title = "Durotar", tasks = {
                { "v2_hd1", "Aprende Pesca si aún no la tienes.", npc = { "H", "Durotar", "Lau'Tiki", "En la costa al sur del poblado Sen'jin." } },
                { "v2_hd2", "Compra la receta de Caballa de piel de serpiente, una Caña de pescar, Baratijas brillantes y cualquier Atrayente.",
                  npc = { "H", "Durotar", "Zansoa", "En el poblado Sen'jin." }, items = "6326x1 6256x1 6529x5" },
                { "v2_hd3", "Pesca en la costa junto a Lau'Tiki hasta 75 (unas 70 Caballas de piel de serpiente).", skill = { "fishing", 75 }, zone = "Durotar" },
                { "v2_hd4", "Aprende Pesca de oficial (nivel 10).", npc = { "H", "Durotar", "Lau'Tiki" } },
            } },
            { f = "H", title = "Claros de Tirisfal", tasks = {
                { "v2_ht1", "Aprende Pesca si aún no la tienes.", npc = { "H", "Tirisfal Glades", "Clyde Kellen", "En el lago Brightwater." } },
                { "v2_ht2", "Compra la receta de Pececillo brillante, una Caña de pescar, Baratijas brillantes y cualquier Atrayente.",
                  npc = { "H", "Tirisfal Glades", "Martine Tramblay", "En la Parada de la Guardia de la Muerte, al sureste de Rémol." }, items = "6325x1 6256x1 6529x5" },
                { "v2_ht3", "Pesca en el lago Brightwater hasta 75 (unos 30 Pececillos brillantes, 20 Pargos boquilargos, algunos Pescados de aspecto enfermizo y basura).",
                  skill = { "fishing", 75 }, zone = "Tirisfal Glades" },
                { "v2_ht4", "Aprende Pesca de oficial (nivel 10).", npc = { "H", "Tirisfal Glades", "Clyde Kellen" } },
            } },
            { f = "N", title = "Zephras Isle", tasks = {
                { "v2_z1", "Aprende Pesca si aún no la tienes (también la enseña Baelann Swiftcurrent en Valanaar).",
                  npc = { "N", "Zephras Isle", "Fenn Fairweather", "En el poblado Shen'dar." } },
                { "v2_z2", "Compra una Caña de pescar, Baratijas brillantes y cualquier Atrayente (también los vende Baelann Swiftcurrent en Valanaar).",
                  npc = { "N", "Zephras Isle", "Belandiel Farflight", "En el poblado Shen'dar." }, items = "6256x1 6529x5" },
                { "v2_z3", "Pesca en cualquier lago o río de la isla hasta 75 (unos 45 Pececillos brillantes y 30 Pargos boquilargos). Guarda todos los peces.",
                  skill = { "fishing", 75 }, zone = "Zephras Isle" },
                { "v2_z4", "Aprende Pesca de oficial (nivel 10).", npc = { "N", "Zephras Isle", "Fenn Fairweather" } },
                { "v2_z5", "En Valanaar, compra las recetas de Pececillo brillante y Pargo boquilargo.",
                  npc = { "N", "Zephras Isle", "Nyalah Brightfire", "En Valanaar." }, items = "6325x1 6328x1" },
            } },
            { f = "A", title = "Bosque de Elwynn (recomendada)", tasks = {
                { "v2_ae1", "Aprende Pesca si aún no la tienes.", npc = { "A", "Elwynn Forest", "Lee Brown", "En el Lago de Cristal, al este de Villadorada." } },
                { "v2_ae2", "Compra las recetas de Pececillo brillante y Pargo boquilargo, una Caña de pescar, Baratijas brillantes y cualquier Atrayente.",
                  npc = { "A", "Elwynn Forest", "Tharynn Bouden", "En Villadorada." }, items = "6325x1 6328x1 6256x1 6529x5" },
                { "v2_ae3", "Pesca en el Lago de Cristal hasta 75 (unos 45 Pececillos brillantes y 30 Pargos boquilargos).", skill = { "fishing", 75 }, zone = "Elwynn Forest" },
                { "v2_ae4", "Aprende Pesca de oficial (nivel 10).", npc = { "A", "Elwynn Forest", "Lee Brown" } },
            } },
            { f = "A", title = "Dun Morogh", tasks = {
                { "v2_ad1", "Aprende Pesca si aún no la tienes.", npc = { "A", "Dun Morogh", "Paxton Ganter", "En el lago Iceflow." } },
                { "v2_ad2", "Compra la receta de Pececillo brillante, una Caña de pescar, Baratijas brillantes y cualquier Atrayente.",
                  npc = { "A", "Dun Morogh", "Gretta Ganter", "En el lago Iceflow." }, items = "6325x1 6256x1 6529x5" },
                { "v2_ad3", "Pesca en el lago Iceflow hasta 75 (unos 45 Pececillos brillantes y 30 Pargos boquilargos).", skill = { "fishing", 75 }, zone = "Dun Morogh" },
                { "v2_ad4", "Aprende Pesca de oficial (nivel 10).", npc = { "A", "Dun Morogh", "Paxton Ganter" } },
            } },
            { f = "A", title = "Teldrassil", tasks = {
                { "v2_at1", "Aprende Pesca en Darnassus: no hay instructor de Pesca en Dolanaar.", npc = { "A", "Darnassus", "Astaia" } },
                { "v2_at2", "Compra las recetas de Pececillo brillante y Pargo boquilargo.", npc = { "A", "Teldrassil", "Nyoma", "En Dolanaar." }, items = "6325x1 6328x1" },
                { "v2_at3", "Compra una Caña de pescar, Baratijas brillantes y cualquier Atrayente.",
                  npc = { "A", "Teldrassil", "Narret Shadowgrove", "En Dolanaar." }, items = "6256x1 6529x5" },
                { "v2_at4", "Pesca en el lago Al'Ameth (al sur de Dolanaar) hasta 75 (unos 45 Pececillos brillantes y 30 Pargos boquilargos).",
                  skill = { "fishing", 75 }, zone = "Teldrassil" },
                { "v2_at5", "Aprende Pesca de oficial (nivel 10).", npc = { "A", "Darnassus", "Astaia" } },
            } },
          } },

        { title = "Pesca (75-130) y Cocina (1-100)",
          H = {
            { "v2_h7", "Pesca en una capital hasta 130: el estanque junto a la casa de subastas de Cima del Trueno, los canales de Entrañas (un tercio es basura) o el estanque del Valle del Honor en Orgrimmar. Objetivo: unos 20 Pececillos, 60 Pargos y 30 Bagres.",
              skill = { "fishing", 130 }, zone = "Thunder Bluff" },
            { "v2_h8", "Compra la receta de Bagre bigotudo (y la de Pargo boquilargo si no la tienes). En Entrañas las venden Ronald Burch (Bagre) y Lizbeth Cromwell (Pargo); en Orgrimmar no hay vendedor.",
              npc = { "H", "Thunder Bluff", "Naal Mistrunner" }, items = "6330x1" },
            { "v2_h9", "Cocina 1-50: aprende Cocina (Aska Mistrunner, Eunice Burch o Zamja), luego el Pececillo brillante (o la Caballa si pescaste caballas) y cocina todo tu pescado.",
              npc = { "H", "Thunder Bluff", "Aska Mistrunner" }, skill = { "cooking", 50 }, spell = 7751 },
            { "v2_h10", "Cocina 50-100: aprende Cocina de oficial con el mismo instructor, luego el Pargo boquilargo y cocina todos.",
              skill = { "cooking", 100 }, spell = 7753 },
          },
          A = {
            { "v2_a7", "Pesca en los canales de Ventormenta hasta 130 (unos 20 Pececillos, 60 Pargos y 30 Bagres).", skill = { "fishing", 130 }, zone = "Stormwind City" },
            { "v2_a8", "Compra la receta de Bagre bigotudo. Si no tienes la de Pargo boquilargo, cómprala a Tharynn Bouden en Villadorada.",
              npc = { "A", "Stormwind City", "Catherine Leland" }, items = "6330x1" },
            { "v2_a9", "Beta: aún no compres los 20 Quesos de Alterac: la misión de Cocina de artesano todavía no está en el juego.",
              npc = { "A", "Stormwind City", "Ben Trias" } },
            { "v2_a10", "Cocina 1-50: aprende Cocina, luego el Pececillo brillante y cocina todo tu pescado.",
              npc = { "A", "Stormwind City", "Stephen Ryback" }, skill = { "cooking", 50 }, spell = 7751 },
            { "v2_a11", "Cocina 50-100: aprende Cocina de oficial, luego el Pargo boquilargo y cocina todos.", skill = { "cooking", 100 }, spell = 7753 },
          } },

        { title = "Bahía del Botín", note = "Pesca de experto pide nivel 20 y Pesca 125; Cocina de experto, Cocina 125.",
          all = {
            { "v2_c1", "Horda: ve a Trinquete (Los Baldíos) y toma el barco a Bahía del Botín. Alianza: ve a Bahía del Botín (Vega de Tuercespina)." },
            { "v2_c2", "Compra y lee Expert Fishing - The Bass and You.", npc = { "N", "Stranglethorn Vale", "Old Man Heming" }, items = "16083x1" },
            { "v2_c3", "Compra las recetas de Trucha cabeza de mitril y Filete de agallaroja.", npc = { "N", "Stranglethorn Vale", "Kelsey Yance" }, items = "17062x1 13941x1" },
          } },

        { title = "Pesca (130-205) y Cocina (100-175)",
          H = {
            { "v2_h11", "Vuelve a Trinquete, vuela al Refugio Roca del Sol y compra 5 Lombrices: guarda 2 hasta 150 y 3 para el Marjal Revolcafango.",
              npc = { "H", "Stonetalon Mountains", "Kulwia" }, items = "6530x5" },
            { "v2_h12", "Pon una Lombriz y pesca en aguas abiertas hasta 205 (unos 95 Pargos y 145 Bagres).", skill = { "fishing", 205 }, zone = "Stonetalon Mountains" },
            { "v2_h13", "Vuela al poblado Shadowprey (Desolace) y compra el Libro de cocina experto (último piso del edificio más al este).",
              npc = { "H", "Desolace", "Wulan" }, items = "16072x1" },
            { "v2_h14", "Beta: aún no compres los 20 Quesos de Alterac: la misión de Cocina de artesano todavía no está en el juego.",
              npc = { "H", "Desolace", "Innkeeper Sikewa" } },
          },
          A = {
            { "v2_a12", "Vuela de Trinquete a Astranaar, ve al sureste hasta el Lago Mystral y compra el Libro de cocina experto y 5 Lombrices (guarda 2 hasta 150 y 3 para el Marjal Revolcafango).",
              npc = { "A", "Ashenvale", "Shandrina" }, items = "16072x1 6530x5" },
            { "v2_a13", "Pon una Lombriz y pesca en aguas abiertas del Lago Mystral hasta 205 (unos 95 Pargos y 145 Bagres).", skill = { "fishing", 205 }, zone = "Ashenvale" },
          },
          all = {
            { "v2_c4", "Cocina los Pargos si sigues por debajo de 100. Lee el Libro de cocina experto en 125: sin él dejas de ganar puntos en 150." },
            { "v2_c5", "Aprende el Bagre bigotudo y haz todos los que puedas, hasta cerca de 175.", skill = { "cooking", 175 }, spell = 7755 },
          } },

        { title = "Misión de Pesca de artesano", note = "Desde aquí todo pide nivel 35 y aún no está probado en la beta.",
          all = {
            { "v2_c6", "Si no tienes Lombrices, compra 3 en Trinquete: en el Marjal Revolcafango nadie las vende.", npc = { "N", "The Barrens", "Kilxx", "En Trinquete." }, items = "6530x3" },
            { "v2_c7", "Pesca en aguas interiores del Marjal Revolcafango (no en el mar) hasta 225, con una Lombriz puesta.", skill = { "fishing", 225 }, zone = "Dustwallow Marsh" },
            { "v2_c8", "Acepta Nat Pagle, Angler Extreme (nivel 35, Pesca 225).", npc = { "N", "Dustwallow Marsh", "Nat Pagle", "Cala Tidefury." }, quest = 6607 },
            { "v2_c9", "Pesca los 4 peces de la misión: Feralas (usa un Atrayente acuadinámico o Baratijas resplandecientes de Sheendra Tallgrass o Vivianna), Pantano de las Penas, Desolace y Vega de Tuercespina.",
              items = "16967x1 16970x1 16968x1 16969x1" },
          } },

        { title = "Pesca hasta 255 y Cocina hasta 225",
          all = {
            { "v2_c10", "Con la misión hecha, sigue pescando en el Marjal Revolcafango hasta 255.", skill = { "fishing", 255 }, zone = "Dustwallow Marsh" },
            { "v2_c11", "Cocina en Brackenwall (Horda), en Isla Theramore (Alianza) o en tu propia fogata. Si sigues por debajo de 175, cocina los Bagres." },
            { "v2_c12", "Aprende la Trucha cabeza de mitril y cocina hasta 225. Para en 225 y guarda las truchas que sobren.", skill = { "cooking", 225 }, spell = 20916 },
          } },

        { title = "Misión de Cocina de artesano",
          all = {
            { "v2_c13", "Vuela a Gadgetzan (Tanaris) y toma Clamlette Surprise (nivel 35, Cocina 225). La recompensa es Cocina de artesano.",
              npc = { "N", "Tanaris", "Dirge Quikcleave" }, quest = 6610 },
            { "v2_c14", "Reúne 12 Huevos gigantes (los Rocs de Tanaris), 10 Carnes de almeja sabrosa (de las Almejas bocagrande de los Steeljaw Snappers y Surf Gliders) y los 20 Quesos de Alterac.",
              items = "12207x12 7974x10 8932x20" },
            { "v2_c15", "Compra las recetas de Sopa de aleta nocturna, Salmón escamasol escalfado y Cola amarilla moteada.",
              npc = { "N", "Tanaris", "Gikkix", "En el Puerto Bonvapor (Steamwheedle Port)." }, items = "13945x1 13946x1 13939x1" },
          } },

        { title = "Pesca hasta 300 en Feralas",
          H = {
            { "v2_h15", "Vuela al Campamento Mojache y compra la receta de Salmón al horno y 10 Lombrices.", npc = { "H", "Feralas", "Sheendra Tallgrass" }, items = "13949x1 6530x10" },
          },
          A = {
            { "v2_a14", "Vuela al Bastión Plumaluna y compra la receta de Salmón al horno y 10 Lombrices.", npc = { "A", "Feralas", "Vivianna" }, items = "13949x1 6530x10" },
          },
          all = {
            { "v2_c16", "Pesca en aguas interiores de Feralas (cualquiera salvo el lago Jademir) hasta 300, poniendo una Lombriz nueva cada 10 minutos.",
              skill = { "fishing", 300 }, zone = "Feralas" },
          } },

        { title = "Cocina hasta 300",
          all = {
            { "v2_c17", "225-250: cocina las truchas que guardaste; luego aprende el Filete de agallaroja y haz todos los que puedas.", skill = { "cooking", 250 }, spell = 18241 },
            { "v2_c18", "250-300: aprende la Sopa de aleta nocturna y el Salmón escamasol escalfado y haz todos los que puedas. En 275 puedes aprender el Salmón al horno si sacaste Salmones escamablanca crudos. "
                .. "Si te faltan peces, pesca un poco más o compra algunos en la subasta.", skill = { "cooking", 300 }, spell = 18244, items = "13889x1" },
          } },
    },
}
