local _, ns = ...
ns.guides = ns.guides or {}

ns.guides.enchanting = {
    intro = "Ruta más rápida y barata de 1 a 300. Combina bien con Sastrería: ninguna de las dos necesita profesión de recolección y puedes desencantar lo que fabriques. "
         .. "Forever añadió recetas nuevas de nivel bajo (Mota de magia), así que los primeros 70 puntos son más baratos que en Classic.",
    apprenticeNote = "Encantamiento de aprendiz no tiene requisito de nivel en Forever.",

    shopping = {
        { title = "1-225", note = "La beta se detiene en 225; usa esta parte si subes en la beta.", rows = {
            { "247786x19", vendor = true }, { "6217x1", vendor = true },
            { "10938x309", alt = "10940x272", note = "Según la ruta que elijas en 20 (esencias o polvo)." },
            { "6338x1" }, { "1210x1" }, { "10938x4" }, { "10940x3" }, { "11083x39" },
            { "11128x1" }, { "5500x1" }, { "11082x1" }, { "17034x32", vendor = true }, { "3372x41", vendor = true },
            { "11137x46", alt = "11137x31 11083x22" },
            { "11144x1" }, { "7971x1" }, { "11135x1" }, { "17036x50", vendor = true },
        } },
        { title = "225-300", note = "No es definitiva, pero los rangos casi no cambiaron.", rows = {
            { "11137x75" }, { "11176x212" }, { "8831x20" }, { "8925x20", vendor = true }, { "16206x1" }, { "13926x1" },
            { "16204x50" }, { "16203x4" }, { "14343x4" }, { "14344x2" },
        } },
    },

    capitals = {
        { "H", "Orgrimmar", "Jhag" }, { "H", "Undercity", "Malcomb Wynn" }, { "H", "Thunder Bluff", "Mot Dawnstrider" },
        { "A", "Stormwind City", "Betty Quin", "En el Barrio de los Magos." }, { "A", "Ironforge", "Thonys Pillarstone", "En la Gran Fundición." },
        { "A", "Darnassus", "Lalina Summermoon" },
    },
    starting = {
        { race = "Orco, Trol", zone = "Durotar", npcs = { { "H", "Durotar", "Pa'zula", "En el poblado Sen'jin." } } },
        { race = "Tauren", zone = "Mulgore", npcs = { { "H", "Thunder Bluff", "Mot Dawnstrider", "No hay en Mulgore: meseta central de Cima del Trueno." } } },
        { race = "No-muerto", zone = "Tirisfal Glades", npcs = { { "H", "Tirisfal Glades", "Vance Undergloom", "En el piso de arriba de la posada de Rémol (Brill)." } } },
        { race = "Humano", zone = "Elwynn Forest", npcs = { { "A", "Stormwind City", "Betty Quin", "No hay en Elwynn: Barrio de los Magos de Ventormenta." } } },
        { race = "Enano, Gnomo", zone = "Dun Morogh", npcs = { { "A", "Ironforge", "Thonys Pillarstone", "No hay en Dun Morogh: Gran Fundición de Forjaz." } } },
        { race = "Elfo de la noche", zone = "Teldrassil", npcs = { { "A", "Teldrassil", "Alanna Raveneye", "En el Claro del Oráculo, al noroeste de Teldrassil." } } },
        { race = "Skyborne", zone = "Zephras Isle", npcs = {
            { "N", "Zephras Isle", "Eaysaa Brightgust", "En Valanaar." },
            { "N", "Zephras Isle", "Nasalanna Windsinger", "En el poblado Shen'dar." } } },
    },

    extras = {
        { title = "Proveedor de suministros",
          text = "La Varilla de cobre y la Mota de magia las vende el proveedor de suministros de encantamiento junto al instructor; no las compres en la subasta. "
              .. "Los instructores de las zonas de inicio no tienen proveedor cerca, salvo en Zephras Isle (allí los vende la propia instructora). Los demás deben ir al instructor de su capital." },
        { title = "Macro para subir más rápido",
          text = "Pulsa el botón Crear y confirma el aviso de reemplazar el encantamiento. Uso: ponla en tu barra, abre la ventana de Encantamiento, elige el encantamiento correcto, coloca el objeto en la ranura de objetivo y pulsa la macro repetidamente.",
          macro = { name = "FCG Encantar", icon = "INV_Misc_QuestionMark",
                    body = "/run ProfessionsFrame.CraftingPage.CreateButton:Click()\n/run StaticPopup1Button1:Click()" } },
    },

    ranks = {
        { title = "Aprendiz", range = "1-70",
          blocks = {
            { steps = {
                { r = "1-2", n = 1, spell = 7421, name = "Runed Copper Rod", icon = "inv_staff_goldfeathered_01", mats = "6217x1 247786x1",
                  note = "Varilla y Mota se compran al proveedor de suministros junto al instructor de tu capital (o en Zephras Isle)." },
                { r = "2-20", n = 18, spell = 7418, name = "Enchant Bracer - Inferior Stamina", icon = "spell_holy_greaterheal", mats = "247786x18" },
            } },
            { title = "Esencias o polvo", group = "enchanting20",
              text = "Elige según el precio en la subasta: la ruta de Esencia mágica inferior o la de Polvo extraño. La elección se recuerda de 20 a 150.",
              routes = {
                { title = "Esencia mágica inferior", steps = {
                    { r = "20-70", n = 50, spell = 7428, name = "Enchant Bracer - Minor Deflect", icon = "spell_holy_greaterheal", mats = "10938x50",
                      note = "Una Esencia mágica superior se convierte en 3 inferiores con clic derecho." },
                } },
                { title = "Polvo extraño", steps = {
                    { r = "20-70", n = 50, spell = 7420, name = "Enchant Chest - Inferior Stamina", icon = "spell_holy_greaterheal", mats = "10940x50",
                      note = "También puedes desencantar objetos verdes en lugar de comprar el polvo." },
                } },
              } },
          } },
        { title = "Oficial", range = "70-150", req = "Encantamiento 50 y nivel 10.",
          trainers = {
            { "H", "Orgrimmar", "Godan" }, { "H", "Undercity", "Lavinia Crowe" }, { "H", "Thunder Bluff", "Teg Dawnstrider" },
            { "A", "Stormwind City", "Lucan Cordell" }, { "A", "Ironforge", "Gimble Thistlefuzz" }, { "A", "Darnassus", "Taladan" } },
          blocks = {
            { title = "Esencias o polvo", group = "enchanting20",
              text = "Sigue con la misma ruta que elegiste en 20.",
              routes = {
                { title = "Esencia mágica inferior", steps = {
                    { r = "70-100", n = 33, spell = 7426, name = "Enchant Chest - Minor Absorption", icon = "spell_holy_greaterheal", mats = "10938x33",
                      note = "Requiere Encantamiento de oficial." },
                    { r = "100-109", n = 18, spell = 7426, name = "Enchant Chest - Minor Absorption", icon = "spell_holy_greaterheal", mats = "10938x18" },
                    { r = "109-110", n = 1, spell = 7795, name = "Runed Silver Rod", icon = "inv_staff_01", mats = "6338x1 10940x3 10938x4 1210x1",
                      note = "Todas las varillas de la guía (plata, oro, veraplata, arcanita) las fabrican los herreros: cómpralas en la subasta." },
                    { r = "110-130", n = 20, spell = 7793, name = "Enchant 2H Weapon - Lesser Intellect", icon = "spell_holy_greaterheal", mats = "10938x80", recipe = 6349,
                      note = "Compra también a estos vendedores las fórmulas de Aceite de maná menor y Aceite de zahorí inferior: las necesitarás en 150 y 200.",
                      vendors = { { "H", "Orgrimmar", "Kithas" }, { "H", "Thunder Bluff", "Nata Dawnstrider" }, { "H", "Silverpine Forest", "Leo Sarn" }, { "A", "Ironforge", "Tilli Thistlefuzz" } },
                      alt = { { n = 32, spell = 7771, name = "Enchant Cloak - Minor Protection", icon = "spell_holy_greaterheal", mats = "10940x64",
                                note = "Sin la fórmula." } } },
                    { r = "130-150", n = 32, spell = 7793, name = "Enchant 2H Weapon - Lesser Intellect", icon = "spell_holy_greaterheal", mats = "10938x128",
                      alt = { { n = 20, spell = 7863, name = "Enchant Boots - Minor Stamina", icon = "spell_holy_greaterheal", mats = "10940x80",
                                note = "Sin la fórmula." } } },
                } },
                { title = "Polvo extraño", steps = {
                    { r = "70-100", n = 30, spell = 7457, name = "Enchant Bracer - Minor Stamina", icon = "spell_holy_greaterheal", mats = "10940x60",
                      note = "Requiere Encantamiento de oficial." },
                    { r = "100-109", n = 9, spell = 7771, name = "Enchant Cloak - Minor Protection", icon = "spell_holy_greaterheal", mats = "10940x18" },
                    { r = "109-110", n = 1, spell = 7795, name = "Runed Silver Rod", icon = "inv_staff_01", mats = "6338x1 10940x3 10938x4 1210x1",
                      note = "Todas las varillas de la guía (plata, oro, veraplata, arcanita) las fabrican los herreros: cómpralas en la subasta." },
                    { r = "110-130", n = 32, spell = 7771, name = "Enchant Cloak - Minor Protection", icon = "spell_holy_greaterheal", mats = "10940x64" },
                    { r = "130-150", n = 20, spell = 7863, name = "Enchant Boots - Minor Stamina", icon = "spell_holy_greaterheal", mats = "10940x80",
                      alt = { { n = 20, spell = 13501, name = "Enchant Bracer - Lesser Stamina", icon = "spell_holy_greaterheal", mats = "11083x20",
                                note = "Solo si 20 Polvos de alma cuestan menos que 80 Polvos extraños." } } },
                } },
              } },
          } },
        { title = "Experto", range = "150-225", req = "Encantamiento 125, nivel 20 y 50 de plata. Solo hay un instructor por facción.",
          trainers = {
            { "H", "Stonetalon Mountains", "Hgarth", "En el Refugio Roca del Sol (Sun Rock Retreat), arriba en la colina sobre el poblado." },
            { "A", "Elwynn Forest", "Kitta Firewind", "En lo alto de la Torre de Azora." } },
          steps = {
            { r = "150-151", n = 1, spell = 13628, name = "Runed Golden Rod", icon = "inv_staff_10", mats = "11128x1 5500x1 11082x1 11083x1" },
            { r = "151-165", n = 16, spell = 25125, name = "Minor Mana Oil", icon = "inv_potion_100", mats = "11083x16 17034x32 3372x16", recipe = 20752,
              note = "Compra también la Fórmula: Aceite de zahorí inferior. La Semilla de arce la venden los proveedores de componentes; el Vial plomizo, los de suministros de alquimia.",
              vendors = { { "H", "Orgrimmar", "Kithas" }, { "H", "Thunder Bluff", "Nata Dawnstrider" }, { "H", "Undercity", "Thaddeus Webb" }, { "A", "Darnassus", "Vaean" }, { "A", "Ironforge", "Tilli Thistlefuzz" }, { "A", "Stormwind City", "Jessara Cordell" } } },
            { r = "165-185", n = 22, spell = 13637, name = "Enchant Boots - Lesser Agility", icon = "spell_holy_greaterheal", mats = "11083x22",
              note = "En la beta el Polvo de visión es caro y el de alma no: sigue con este hasta 200 si te conviene." },
            { r = "185-200", n = 15, spell = 13661, name = "Enchant Bracer - Strength", icon = "spell_holy_greaterheal", mats = "11137x15" },
            { r = "200-201", n = 1, spell = 13702, name = "Runed Truesilver Rod", icon = "inv_staff_11", mats = "11144x1 7971x1 11135x1 11137x1" },
            { r = "201-220", n = 25, spell = 25126, name = "Lesser Wizard Oil", icon = "inv_potion_101", mats = "11137x25 17036x50 3372x25", recipe = 20753,
              note = "La Semilla de Tuercespina la venden los proveedores de componentes; el Vial plomizo, los de suministros de alquimia.",
              vendors = { { "H", "Orgrimmar", "Kithas" }, { "H", "Thunder Bluff", "Nata Dawnstrider" }, { "H", "Undercity", "Thaddeus Webb" }, { "A", "Darnassus", "Vaean" }, { "A", "Ironforge", "Tilli Thistlefuzz" }, { "A", "Stormwind City", "Jessara Cordell" } } },
            { r = "220-225", n = 5, spell = 13746, name = "Enchant Cloak - Greater Defense", icon = "spell_holy_greaterheal", mats = "11137x5" },
        } },
        { title = "Artesano", range = "225-300", untested = true,
          req = "Encantamiento 200 y nivel 35. Annora, en Uldaman, es la ÚNICA instructora de Encantamiento artesano.",
          text = "Casi todos los rangos de Encantamiento siguen igual que en Classic, así que la ruta de Classic debería servir. "
              .. "Los instructores de las capitales solo enseñan hasta 225. Annora enseña recetas que nadie más tiene: lleva oro para aprenderlo todo y materiales para llegar a 250 "
              .. "(unos 100 Polvos de visión), o tendrás que volver a Uldaman.",
          trainers = { { "N", "Badlands", "Annora", "Dentro de Uldaman. Usa la entrada trasera (no se puede hacer solo a nivel 35: ve en grupo o con ayuda de un nivel 60). Annora solo aparece cuando matas todos los enemigos de su zona." } },
          steps = {
            { r = "225-230", n = 5, spell = 13815, name = "Enchant Gloves - Agility", icon = "spell_holy_greaterheal", mats = "11137x5",
              note = "Requiere Encantamiento de artesano (Annora)." },
            { r = "230-235", n = 5, spell = 13836, name = "Enchant Boots - Stamina", icon = "spell_holy_greaterheal", mats = "11137x10" },
            { r = "235-250", n = 20, spell = 13858, name = "Enchant Chest - Superior Stamina", icon = "spell_holy_greaterheal", mats = "11137x60",
              note = "Amarillo desde 240. Busca en la subasta la Fórmula: Brazales - Aguante superior (botín del mundo): es la mejor receta de 245 a 265 (3 Polvos de sueño cada una).",
              recipe = 11225 },
            { r = "250-265", n = 20, spell = 25127, name = "Lesser Mana Oil", icon = "inv_potion_99", mats = "11176x20 8831x20 8925x20", recipe = 20754,
              note = "Amarillo desde 260. Los Viales de cristal los vende Mishta en Silithus o cualquier proveedor de suministros.",
              vendors = { { "N", "Silithus", "Kania", "Fórmula: en el piso de arriba de la posada." }, { "N", "Silithus", "Mishta", "Viales de cristal." } },
              alt = { { n = 15, spell = 13939, name = "Enchant Bracer - Greater Strength", icon = "spell_holy_greaterheal", mats = "11176x15 11174x30",
                        note = "Si no tienes Loto morado: 1 Polvo de sueño y 2 Esencias abisales inferiores cada uno. Lo enseña Annora." } } },
            { r = "265-294", n = 32, spell = 20017, name = "Enchant Shield - Greater Stamina", icon = "spell_holy_greaterheal", mats = "11176x192", recipe = 16217,
              note = "Amarillo desde 285. La fórmula se liga al recogerla: no la compres con un alter.",
              vendors = { { "H", "Undercity", "Daniel Bartlett" }, { "A", "Darnassus", "Mythrin'dir" } } },
            { r = "294-295", n = 1, spell = 20051, name = "Runed Arcanite Rod", icon = "inv_wand_09", mats = "16206x1 13926x1 16204x10 16203x4 14343x4 14344x2", recipe = 16243,
              note = "Lorelae Wintersong también vende la fórmula del siguiente paso: compra las dos antes de irte.",
              vendors = { { "N", "Moonglade", "Lorelae Wintersong", "En Nighthaven (Amparo de la Noche)." } } },
            { r = "295-300", n = 5, spell = 20015, name = "Enchant Cloak - Superior Defense", icon = "spell_holy_greaterheal", mats = "16204x40", recipe = 16224,
              note = "También puedes seguir con Escudo - Aguante mayor si tienes mucho Polvo de sueño o el de ilusión es muy caro.",
              vendors = { { "N", "Moonglade", "Lorelae Wintersong" } } },
        } },
    },

    lists = {
        { title = "Recetas que enseña Annora (Uldaman)",
          text = "Aprende todo antes de salir de Uldaman: las recetas desde 230 no las enseña nadie más. Habilidad requerida y coste.",
          rows = {
            { 13917, "Enchant Chest - Superior Intellect", "spell_holy_greaterheal", "230 - coste 54" },
            { 13905, "Enchant Shield - Greater Spirit", "spell_holy_greaterheal", "230 - coste 54" },
            { 13935, "Enchant Boots - Agility", "spell_holy_greaterheal", "235 - coste 58" },
            { 13937, "Enchant 2H Weapon - Greater Impact", "spell_holy_greaterheal", "240 - coste 62" },
            { 13939, "Enchant Bracer - Greater Strength", "spell_holy_greaterheal", "240 - coste 62" },
            { 13941, "Enchant Chest - Stats", "spell_holy_greaterheal", "245 - coste 62" },
            { 13943, "Enchant Weapon - Greater Striking", "spell_holy_greaterheal", "245 - coste 62" },
            { 13948, "Enchant Gloves - Minor Haste", "spell_holy_greaterheal", "250 - coste 65" },
            { 17181, "Enchanted Leather", "inv_misc_rune_05", "250 - coste 1" },
            { 17180, "Enchanted Thorium", "inv_ingot_eternium", "250 - coste 1" },
          } },
    },
}
