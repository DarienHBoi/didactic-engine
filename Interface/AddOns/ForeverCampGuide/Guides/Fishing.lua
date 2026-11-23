local _, ns = ...
ns.guides = ns.guides or {}

ns.guides.fishing = {
    intro = "Ruta más rápida de 1 a 300. Pescar requiere paciencia (hay que sacar muchísimos peces), pero no necesitas materiales: solo una caña y algunos cebos. "
         .. "Si aún no has subido Cocina, sigue la guía de Pesca y Cocina juntas (pestaña de abajo): lo que pescas sube Cocina a la vez.",
    apprenticeNote = "Sin requisito de nivel. Todos los instructores enseñan también Pesca de oficial. Todos los de las zonas de inicio están junto al agua.",

    capitals = {
        { "H", "Orgrimmar", "Lumak" }, { "H", "Undercity", "Armand Cromwell" }, { "H", "Thunder Bluff", "Kah Mistrunner" },
        { "A", "Stormwind City", "Arnold Leland" }, { "A", "Ironforge", "Grimnur Stonebrand" }, { "A", "Darnassus", "Astaia" },
    },
    starting = {
        { race = "Orco, Trol", zone = "Durotar", npcs = { { "H", "Durotar", "Lau'Tiki", "En la costa del poblado Sen'jin." } } },
        { race = "Tauren", zone = "Mulgore", npcs = { { "H", "Mulgore", "Uthan Stillwater", "En el lago Stonebull, junto al poblado Pezuña de Sangre." } } },
        { race = "No-muerto", zone = "Tirisfal Glades", npcs = { { "H", "Tirisfal Glades", "Clyde Kellen", "En el lago Brightwater, al este de Rémol." } } },
        { race = "Humano", zone = "Elwynn Forest", npcs = { { "A", "Elwynn Forest", "Lee Brown", "En el Lago de Cristal, al este de Villadorada." } } },
        { race = "Enano, Gnomo", zone = "Dun Morogh", npcs = { { "A", "Dun Morogh", "Paxton Ganter", "En el lago Iceflow, de camino a Gnomeregan." } } },
        { race = "Elfo de la noche", zone = "Teldrassil", npcs = { { "A", "Teldrassil", "Androl Oakhand", "En el poblado Rut'theran, en la orilla junto al muelle." } } },
        { race = "Skyborne", zone = "Zephras Isle", npcs = {
            { "N", "Zephras Isle", "Baelann Swiftcurrent", "En Valanaar." }, { "N", "Zephras Isle", "Fenn Fairweather", "En el poblado Shen'dar." } } },
    },

    extras = {
        { title = "Caña y cebos",
          text = "Compra una Caña de pescar y algunas Baratijas brillantes a un proveedor de suministros de pesca o de comercio. En las capitales están junto al instructor; además:",
          items = "6256x1 6529x5",
          npcs = { { "H", "Durotar", "Zansoa", "En el poblado Sen'jin." }, { "H", "Mulgore", "Wunna Darkmane", "En el poblado Pezuña de Sangre." },
                   { "H", "Tirisfal Glades", "Martine Tramblay", "En la Parada de la Guardia de la Muerte, al sureste de Rémol." },
                   { "H", "Orgrimmar", "Shankys" }, { "H", "Undercity", "Lizbeth Cromwell" }, { "H", "Thunder Bluff", "Sewa Mistrunner" },
                   { "H", "Ashenvale", "Wik'Tar", "En el Puesto Zoram'gar." },
                   { "H", "The Hinterlands", "Katoom the Angler", "En el poblado Revantusk (también es instructor)." },
                   { "A", "Elwynn Forest", "Tharynn Bouden", "En Villadorada." }, { "A", "Dun Morogh", "Gretta Ganter", "En el lago Iceflow." },
                   { "A", "Teldrassil", "Nessa Shadowsong", "En el poblado Rut'theran." },
                   { "A", "Stormwind City", "Catherine Leland" }, { "A", "Ironforge", "Tansy Puddlefizz" }, { "A", "Darnassus", "Voloren" },
                   { "A", "Loch Modan", "Khara Deepwater", "Junto al lago." }, { "A", "Wetlands", "Stuart Fleming", "En Puerto de Menethil." },
                   { "A", "Redridge Mountains", "Vernon Hale", "En el lago Everstill." }, { "A", "Hillsbrad Foothills", "Lindea Rabonne", "En Costasur." },
                   { "N", "Zephras Isle", "Baelann Swiftcurrent", "En Valanaar." }, { "N", "Zephras Isle", "Belandiel Farflight", "En el poblado Shen'dar." } } },
        { title = "Cómo pescar",
          text = "1) Abre la ventana de Profesiones.\n2) Pulsa el botón del martillo en la fila de botones de la derecha (NO la pestaña de Pesca).\n"
              .. "3) Arrastra el botón Pesca a tu barra de acción.\n4) Equípate la caña y aplica la Baratija brillante.\n"
              .. "5) Ponte frente a un lago, estanque o río y pulsa el botón de pesca.\n6) Pasa el ratón sobre el corcho y, cuando salpique, haz clic derecho.",
          spell = 7731 },
    },

    ranks = {
        { title = "Aprendiz", range = "1-75", steps = {
            { r = "1-75", text = "Pesca en cualquier lago, estanque o río de una zona de inicio hasta 75. Ojo: las capitales NO cuentan como zona de inicio.",
              zones = { "Dun Morogh", "Durotar", "Elwynn Forest", "Mulgore", "Teldrassil", "Tirisfal Glades", "Zephras Isle" }, mats = "6529x5" },
        } },
        { title = "Oficial", range = "75-150", req = "Pesca 50 y nivel 10. Lo enseña tu mismo instructor.",
          steps = {
            { r = "75-150", text = "Pesca hasta 150 en una capital (Darnassus, Ventormenta, Orgrimmar, Entrañas, Cima del Trueno) o en estas zonas. "
                .. "Si se te escapan los peces, compra Lombrices a un proveedor de pesca (requieren Pesca 50).",
              zones = { "Darnassus", "Stormwind City", "Orgrimmar", "Undercity", "Thunder Bluff", "The Barrens", "Darkshore", "Ironforge", "Loch Modan", "Silverpine Forest", "Westfall" },
              mats = "6530x5" },
        } },
        { title = "Experto", range = "150-225", req = "Nivel 20 y Pesca 125. Se aprende con el libro Expert Fishing - The Bass and You.",
          trainers = { { "N", "Stranglethorn Vale", "Old Man Heming", "En el centro de Bahía del Botín, abajo del todo, junto al cartel de pesca. Vende el libro y Baratijas resplandecientes. El libro también se vende en la subasta." } },
          books = { 16083 },
          steps = {
            { r = "150-225", text = "Compra muchas Baratijas resplandecientes antes de irte, ve al Marjal Revolcafango, aplícalas y pesca hasta 225 "
                .. "(allí empieza la misión de Pesca de artesano). También sirven estas zonas:",
              zones = { "Dustwallow Marsh", "Alterac Mountains", "Arathi Highlands", "Desolace", "Stranglethorn Vale", "Swamp of Sorrows", "Thousand Needles" },
              mats = "6532x10" },
        } },
        { title = "Artesano", range = "225-300", req = "Nivel 35 y Pesca 225. Se obtiene con la misión Nat Pagle, Angler Extreme.",
          trainers = { { "N", "Dustwallow Marsh", "Nat Pagle", "En la Cala Tidefury (Tidefury Cove)." } },
          quests = { { 6607, "Nat Pagle, Angler Extreme" } },
          text = "Para la misión debes pescar 4 peces especiales en cuatro zonas distintas. Usa Baratijas resplandecientes en Feralas para que no se escapen; en las demás zonas tu habilidad ya basta.",
          questItems = "16967x1 16970x1 16968x1 16969x1",
          questZones = { { 16967, "Feralas" }, { 16970, "Swamp of Sorrows" }, { 16968, "Desolace" }, { 16969, "Stranglethorn Vale" } },
          steps = {
            { r = "225-300", text = "Con la misión completada, pesca en cualquiera de estas zonas. ¡Usa Baratijas resplandecientes para que no se escapen!",
              zones = { "Felwood", "Feralas", "The Hinterlands", "Tanaris", "Un'Goro Crater", "Western Plaguelands" }, mats = "6532x10" },
        } },
    },
}
