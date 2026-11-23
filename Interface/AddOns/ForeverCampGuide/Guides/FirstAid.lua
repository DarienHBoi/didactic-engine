local _, ns = ...
ns.guides = ns.guides or {}

ns.guides.firstaid = {
    intro = "Ruta más rápida de 1 a 300. Primeros auxilios no ocupa una de tus dos profesiones, así que cualquier personaje puede aprenderla. "
         .. "Las vendas te curan entre combates y, en Forever, esta profesión fabrica además las pociones de sanación que antes eran de Alquimia: merece la pena en todos tus personajes.",
    apprenticeNote = "Sin requisito de nivel. Todos los instructores enseñan también Primeros auxilios de oficial, y todas las zonas de inicio tienen instructor (casi siempre en la posada).",

    shopping = {
        { title = "1-225", note = "La beta se detiene en 225.", rows = {
            { "2589x130", alt = "2447x81" }, { "2589x24" }, { "2592x150" }, { "4306x134" },
            { "4338x17", alt = "4306x84" },
        } },
        { title = "225-300", note = "No es definitiva, pero los rangos casi no cambiaron.", rows = {
            { "8838x16" }, { "4338x60" }, { "14047x20" }, { "13464x30" },
        } },
    },

    capitals = {
        { "H", "Orgrimmar", "Arnok" }, { "H", "Undercity", "Mary Edras" }, { "H", "Thunder Bluff", "Pand Stonebinder" },
        { "A", "Stormwind City", "Shaina Fuller" }, { "A", "Ironforge", "Nissa Firestone" }, { "A", "Darnassus", "Dannelor" },
    },
    starting = {
        { race = "Orco, Trol", zone = "Durotar", npcs = { { "H", "Durotar", "Rawrk", "En los barracones de Cerrotajo (Razor Hill)." } } },
        { race = "Tauren", zone = "Mulgore", npcs = { { "H", "Mulgore", "Vira Younghoof", "Dentro de la posada del poblado Pezuña de Sangre." } } },
        { race = "No-muerto", zone = "Tirisfal Glades", npcs = { { "H", "Tirisfal Glades", "Nurse Neela", "Dentro de la posada de Rémol (Brill)." } } },
        { race = "Humano", zone = "Elwynn Forest", npcs = { { "A", "Elwynn Forest", "Michelle Belle", "En el piso de arriba de la posada de Villadorada." } } },
        { race = "Enano, Gnomo", zone = "Dun Morogh", npcs = { { "A", "Dun Morogh", "Thamner Pol", "En la destilería Cebatruenos de Kharanos." } } },
        { race = "Elfo de la noche", zone = "Teldrassil", npcs = { { "A", "Teldrassil", "Byancie", "En Dolanaar, en el edificio al norte de la posada." } } },
        { race = "Skyborne", zone = "Zephras Isle", npcs = {
            { "N", "Zephras Isle", "Melasa Fairmend", "En Valanaar." }, { "N", "Zephras Isle", "Naleeia Tattermend", "En el poblado Shen'dar." } } },
    },

    extras = {
        { title = "Especias y viales (pociones de sanación)",
          text = "Las especias suaves y picantes las venden los proveedores de cocina; el Vial vacío, los de alquimia. El Vial plomizo lo venden los de alquimia, comercio y víveres.",
          items = "2678x1 2692x1 3713x1 3371x1 3372x1 8925x1",
          npcs = {
            { "H", "Orgrimmar", "Xen'to", "Especias." }, { "H", "Orgrimmar", "Kor'geld", "Viales, en el Arrastradero." },
            { "H", "Undercity", "Felicia Doan", "Especias y viales, en el Barrio Comercial." },
            { "H", "Thunder Bluff", "Naal Mistrunner", "Especias." }, { "H", "Thunder Bluff", "Mani Winterhoof", "Viales." },
            { "H", "Durotar", "Flakk", "En Cerrotajo." }, { "H", "Mulgore", "Wunna Darkmane", "En el poblado Pezuña de Sangre." },
            { "H", "Tirisfal Glades", "Abigail Shiel", "En Rémol." },
            { "A", "Stormwind City", "Edna Mullby", "En el Distrito Comercial." },
            { "A", "Ironforge", "Emrul Riknussun", "Especias." }, { "A", "Ironforge", "Gwina Stonebranch", "Viales, junto al instructor." },
            { "A", "Darnassus", "Mythrin'dir" }, { "A", "Elwynn Forest", "Tharynn Bouden", "En Villadorada." },
            { "A", "Dun Morogh", "Golorn Frostbeard", "En Kharanos." }, { "A", "Teldrassil", "Narret Shadowgrove", "En Dolanaar." },
            { "N", "Zephras Isle", "Iallion Featherfall", "En Valanaar." }, { "N", "Zephras Isle", "Belandiel Farflight", "En el poblado Shen'dar." },
          } },
    },

    ranks = {
        { title = "Aprendiz", range = "1-75",
          blocks = {
            { title = "Pociones o vendas",
              text = "Si compraste hierbas, sigue la ruta de pociones; si tienes (o compraste) Paño de lino, la de vendas.",
              routes = {
                { title = "Pociones de sanación", steps = {
                    { r = "1-75", n = 81, spell = 1244431, name = "Minor Healing Potion", icon = "inv_potion_49", mats = "2447x81 2678x81 3371x81",
                      note = "Amarilla desde 55: compra algunas hierbas de más." },
                } },
                { title = "Vendas", steps = {
                    { r = "1-40", n = 50, spell = 3275, name = "Linen Bandage", icon = "inv_misc_bandage_15", mats = "2589x50" },
                    { r = "40-75", n = 40, spell = 3276, name = "Heavy Linen Bandage", icon = "inv_misc_bandage_18", mats = "2589x80",
                      note = "Amarilla desde 50." },
                } },
              } },
          } },
        { title = "Oficial", range = "75-150", req = "Primeros auxilios 50 y nivel 10. Lo enseña tu mismo instructor.",
          steps = {
            { r = "75-80", n = 12, spell = 3276, name = "Heavy Linen Bandage", icon = "inv_misc_bandage_18", mats = "2589x24",
              note = "Es verde: más o menos una de cada dos da punto." },
            { r = "80-115", n = 50, spell = 3277, name = "Wool Bandage", icon = "inv_misc_bandage_14", mats = "2592x50",
              note = "La enseña el instructor en 80. Amarilla todo el tramo." },
            { r = "115-150", n = 50, spell = 3278, name = "Heavy Wool Bandage", icon = "inv_misc_bandage_17", mats = "2592x100",
              note = "La enseña el instructor en 115. Amarilla todo el tramo." },
        } },
        { title = "Experto", range = "150-225",
          req = "Primeros auxilios 125 (sin requisito de nivel). Se aprende con el libro Expert First Aid - Under Wraps.",
          text = "Aprende la Venda de seda con tu instructor ANTES de irte: es la última receta que enseñan. "
              .. "Los vendedores del libro venden también los dos manuales siguientes: compra los tres (o búscalos en la subasta si eres de nivel bajo).",
          trainers = { { "A", "Arathi Highlands", "Deneb Walker", "Vende el libro y los manuales." },
                       { "H", "Dustwallow Marsh", "Balai Lok'Wein", "Vende el libro y los manuales." } },
          books = { 16084, 16112, 16113 },
          steps = {
            { r = "150-180", n = 42, spell = 7928, name = "Silk Bandage", icon = "inv_misc_bandage_01", mats = "4306x42",
              note = "Amarilla todo el tramo." },
            { r = "180-210", n = 46, spell = 7929, name = "Heavy Silk Bandage", icon = "inv_misc_bandage_02", mats = "4306x92", recipe = 16112,
              note = "Usa primero el manual para aprender la receta. Amarilla todo el tramo." },
            { r = "210-225", n = 17, spell = 10840, name = "Mageweave Bandage", icon = "inv_misc_bandage_19", mats = "4338x17", recipe = 16113,
              note = "Usa primero el manual.",
              alt = { { n = 42, spell = 7929, name = "Heavy Silk Bandage", icon = "inv_misc_bandage_02", mats = "4306x84",
                        note = "Beta: el Paño de tejido mágico casi no existe; sigue con vendas de seda gruesa hasta 225." } } },
        } },
        { title = "Artesano", range = "225-300", untested = true,
          req = "Primeros auxilios 225 y nivel 35. Se obtiene con la misión Triage.",
          text = "Primeros auxilios mantiene los rangos de Classic. Sin probar por el límite de la beta.\n"
              .. "Cómo completar Triage: recibes vendas de triaje y debes salvar a 15 pacientes, empezando por los críticos.\n"
              .. "1) Pulsa CTRL+V para ver las barras de vida (o activa los nombres de PNJ).\n"
              .. "2) Aleja la cámara en tercera persona para ver toda la sala.\n"
              .. "3) Pon en tu barra las Vendas de triaje que te da el doctor y usa esas, no las tuyas.\n"
              .. "4) Colócate en el centro de la sala.\n"
              .. "5) Al salvar 15, entrega la misión INMEDIATAMENTE: si esperas y mueren pacientes, puede pasar a fallida.",
          trainers = { { "H", "Arathi Highlands", "Doctor Gregory Victor", "En Sentencia (Hammerfall). Da la misión Triage." },
                       { "A", "Dustwallow Marsh", "Doctor Gustaf VanHowzen", "En Theramore. Da la misión Triage." } },
          steps = {
            { r = "225-240", n = 16, spell = 1244435, name = "Superior Healing Potion", icon = "inv_potion_53", mats = "8838x16 3713x16 8925x16", recipe = 255725,
              note = "Ningún vendedor vende el manual: probablemente cae de enemigos de nivel alto. Amarilla desde 230." },
            { r = "240-260", n = 30, spell = 10841, name = "Heavy Mageweave Bandage", icon = "inv_misc_bandage_20", mats = "4338x60",
              note = "La enseña el doctor en 240." },
            { r = "260-275", n = 20, spell = 18629, name = "Runecloth Bandage", icon = "inv_misc_bandage_11", mats = "14047x20",
              note = "La enseña el doctor en 260. Amarilla desde el principio." },
            { r = "275-300", n = 30, spell = 1244436, name = "Major Healing Potion", icon = "inv_potion_54", mats = "13464x30 3713x90 8925x30", recipe = 255729,
              note = "Ningún vendedor vende el manual: probablemente cae de enemigos de nivel alto." },
        } },
    },
}
