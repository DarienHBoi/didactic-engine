local _, ns = ...
ns.guides = ns.guides or {}

ns.guides.engineering = {
    intro = "Ruta más rápida y barata de 1 a 300. Ingeniería va mejor con Minería, porque casi todo lo que fabricas pide piedra y barras; sin Minería tendrás que comprarlo todo en la subasta.",
    apprenticeNote = "Ingeniería de aprendiz no tiene requisito de nivel en Forever. Cima del Trueno y Darnassus no tienen instructor.",

    shopping = {
        { title = "1-225", note = "La beta se detiene en 225; usa esta parte si subes en la beta.", rows = {
            { "2835x60" }, { "2840x66" }, { "2589x50" }, { "2836x60" },
            { "2842x5", alt = "2318x30 818x10" },
            { "2841x110" }, { "2880x25", vendor = true }, { "1206x10" }, { "2838x30" }, { "2592x60" }, { "2319x15" }, { "3859x4" },
            { "7912x120", alt = "7912x20 3575x20 2838x20 4306x20", note = "La alternativa (Granada de hierro) es mejor opción en la beta." },
            { "3860x74" }, { "4338x20" },
        } },
        { title = "225-300", note = "No es definitiva, pero los rangos casi no cambiaron.", rows = {
            { "3860x84" }, { "12365x60" }, { "12359x225" }, { "14047x35" },
        } },
    },

    capitals = {
        { "H", "Orgrimmar", "Thund" }, { "H", "Undercity", "Graham Van Talen", "En el Barrio de los Pícaros." },
        { "A", "Stormwind City", "Sprite Jumpsprocket", "En el Distrito de los Enanos." }, { "A", "Ironforge", "Jemma Quikswitch" },
    },
    starting = {
        { race = "Orco, Trol", zone = "Durotar", npcs = { { "H", "Durotar", "Mukdrak", "En Cerrotajo (Razor Hill), cerca de la forja junto al camino a Orgrimmar." } } },
        { race = "Tauren", zone = "Mulgore", npcs = { { "N", "Mulgore", "Twizwick Sprocketgrind", "En la meseta sobre la mina de la Venture Co.: difícil de alcanzar a nivel bajo, sin yunque ni vendedor de Martillo de herrero cerca. La guía recomienda ir a Thund, en Orgrimmar." } } },
        { race = "No-muerto", zone = "Tirisfal Glades", npcs = { { "H", "Undercity", "Graham Van Talen", "No hay en Tirisfal: Barrio de los Pícaros de Entrañas." } } },
        { race = "Humano", zone = "Elwynn Forest", npcs = { { "A", "Stormwind City", "Sprite Jumpsprocket", "No hay en Elwynn: Distrito de los Enanos de Ventormenta." } } },
        { race = "Enano, Gnomo", zone = "Dun Morogh", npcs = { { "A", "Dun Morogh", "Bronk Guzzlegear", "En el Depósito de Steelgrill." } } },
        { race = "Elfo de la noche", zone = "Teldrassil", npcs = { { "A", "Darkshore", "Jenna Lemkenilli", "No hay en Teldrassil ni Darnassus: Auberdine, Costa Oscura." } } },
        { race = "Skyborne", zone = "Zephras Isle", npcs = { { "N", "Zephras Isle", "Strange Hermit", "En el bosque Shadowgale." } } },
    },

    extras = {
        { title = "Martillo de herrero", item = 5956,
          text = "Casi todas las recetas lo piden. La mayoría de instructores tienen cerca un proveedor de herrería o ingeniería que lo vende, salvo en Dun Morogh y Zephras Isle.",
          npcs = { { "A", "Dun Morogh", "Thrawn Boltar", "En Kharanos." }, { "N", "Zephras Isle", "Aedi Thriceforged", "En el poblado Shen'dar." } } },
        { title = "Gnomos",
          text = "El racial de los gnomos cambió en Forever: ya no da +15 de Ingeniería, sino que sus artilugios fallan o se vuelven en contra un 20% menos. Los gnomos suben Ingeniería igual que el resto." },
        { title = "Especialización",
          text = "Con Ingeniería 200 y nivel 30 puedes elegir Ingeniería gnómica o goblin. La misión debería ser la misma que en Classic y las recetas parecidas, pero aún no está probado del todo en Forever." },
    },

    ranks = {
        { title = "Aprendiz", range = "1-50", steps = {
            { r = "1-30", n = 60, spell = 3918, name = "Rough Blasting Powder", icon = "inv_misc_dust_01", mats = "2835x60",
              note = "Guárdalos todos: necesitas 60 para las bombas en 51. Amarillo desde 20, quizá termines algo por encima de 30." },
            { r = "30-50", n = 30, spell = 3922, name = "Handful of Copper Bolts", icon = "inv_misc_gear_06", mats = "2840x30",
              note = "Guárdalos también: los 30 son para las bombas." },
            { r = "50-51", n = 1, spell = 7430, name = "Arclight Spanner", icon = "inv_misc_wrench_01", mats = "2840x6",
              note = "Herramienta para fabricar recetas de Ingeniería: no la vendas." },
        } },
        { title = "Oficial", range = "50-150", req = "Ingeniería 50 y nivel 10.",
          trainers = {
            { "H", "Orgrimmar", "Nogg" }, { "H", "Undercity", "Franklin Lloyd" },
            { "A", "Stormwind City", "Lilliam Sparkspindle" }, { "A", "Ironforge", "Trixie Quikswitch" }, { "A", "Duskwood", "Finbus Geargrind" } },
          steps = {
            { r = "51-75", n = 30, spell = 3923, name = "Rough Copper Bomb", icon = "inv_misc_bomb_09", mats = "2840x30 4359x30 4357x60 2589x30",
              note = "Podrías pasar de 75: aprende Ingeniería de oficial antes de fabricarlas en AFK. Amarillas desde 60." },
            { r = "75-90", n = 60, spell = 3929, name = "Coarse Blasting Powder", icon = "inv_misc_dust_02", mats = "2836x60",
              note = "Guárdalos: los 60 son para la dinamita en 90. Amarillo desde 85." },
            { r = "90-100", n = 20, spell = 3931, name = "Coarse Dynamite", icon = "inv_misc_bomb_06", mats = "4364x60 2589x20",
              note = "Amarilla todo el tramo; con 20 deberían bastar." },
            { r = "100-105", n = 5, spell = 3973, name = "Silver Contact", icon = "inv_ingot_04", mats = "2842x5",
              alt = { { n = 5, spell = 3934, name = "Flying Tiger Goggles", icon = "inv_helmet_47", mats = "2318x30 818x10", note = "Si la Barra de plata es cara." } } },
            { r = "105-125", n = 25, spell = 3938, name = "Bronze Tube", icon = "inv_gizmo_pipe_01", mats = "2841x50 2880x25",
              note = "El Fundente débil lo vende el proveedor de ingeniería junto al instructor. Amarillo todo el tramo: si te faltan unos puntos, empieza ya con las miras." },
            { r = "125-135", n = 10, spell = 3978, name = "Standard Scope", icon = "inv_misc_spyglass_02", mats = "4371x10 1206x10",
              note = "Usa 10 de los tubos que acabas de hacer. Sin Ágata musgosa (o si es muy cara), pasa directamente al Polvo explosivo denso." },
            { r = "135-150", n = 30, spell = 3945, name = "Heavy Blasting Powder", icon = "inv_misc_dust_06", mats = "2838x30",
              note = "Haz AMBAS cosas y en este orden; las dos se usan para las ovejas en 160.",
              also = { { n = 15, spell = 3942, name = "Whirring Bronze Gizmo", icon = "inv_gizmo_02", mats = "2841x30 2592x15" } } },
        } },
        { title = "Experto", range = "150-200", req = "Ingeniería 125, nivel 20 y 50 de plata.",
          trainers = { { "H", "Orgrimmar", "Roxxik" }, { "A", "Ironforge", "Springspindle Fizzlegear" } },
          steps = {
            { r = "150-160", n = 15, spell = 3953, name = "Bronze Framework", icon = "inv_gizmo_bronzeframework_01", mats = "2841x30 2319x15 2592x15",
              note = "Guárdalos para las ovejas. Probablemente pases de 160; no pasa nada." },
            { r = "160-175", n = 15, spell = 3955, name = "Explosive Sheep", icon = "spell_nature_polymorph", mats = "4377x30 4375x15 4382x15 2592x30",
              note = "Guarda 5 por si eliges Ingeniería goblin en 200 (en la beta puedes venderlas todas)." },
            { r = "175-194", n = 60, spell = 12585, name = "Solid Blasting Powder", icon = "inv_misc_powder_black", mats = "7912x120",
              note = "Guárdalos para más adelante.",
              alt = { { n = 10, spell = 12585, name = "Solid Blasting Powder", icon = "inv_misc_powder_black", mats = "7912x20",
                        note = "Beta: la Piedra sólida es cara y con el límite solo usarías 20. Haz 10 de estos y después las granadas.",
                        also = { { n = 20, spell = 3962, name = "Iron Grenade", icon = "inv_misc_bomb_08", mats = "3575x20 4377x20 4306x20" } } } } },
            { r = "194-195", n = 1, spell = 12590, name = "Gyromatic Micro-Adjustor", icon = "inv_misc_screwdriver_02", mats = "3859x4",
              note = "Herramienta para algunas recetas: guárdala. Si no llegaste a 195, haz alguna Granada de hierro más." },
            { r = "195-200", n = 6, spell = 12589, name = "Mithril Tube", icon = "inv_musket_01", mats = "3860x18",
              note = "Guárdalos todos: quizá los necesites para la Ingeniería gnómica en 200." },
        } },
        { title = "Artesano", range = "200-300", untested = true,
          req = "Ingeniería 200 y nivel 35 para pasar de 225.",
          text = "Ingeniería mantiene todos los rangos de Classic, así que la ruta de Classic debería servir tal cual. Sin probar por el límite de la beta. "
              .. "El instructor de Artesano también enseña las recetas de más de 200: ve en cuanto llegues a 200.",
          trainers = { { "N", "Tanaris", "Buzzek Bracketswing", "En Gadgetzan, justo fuera de la posada, junto al buzón." } },
          steps = {
            { r = "200-215", n = 20, spell = 12591, name = "Unstable Trigger", icon = "inv_battery_01", mats = "3860x20 4338x20 10505x20",
              note = "Guárdalos: los 20 son para las bombas en 238." },
            { r = "215-238", n = 40, spell = 12599, name = "Mithril Casing", icon = "inv_gizmo_mithrilcasing_01", mats = "3860x120",
              note = "Guárdalos también. Amarillos desde el principio y verdes desde 235." },
            { r = "238-250", n = 20, spell = 12619, name = "Hi-Explosive Bomb", icon = "inv_misc_bomb_07", mats = "10561x40 10560x20 10505x40",
              note = "Amarillas todo el tramo: probablemente necesites algunas extra." },
            { r = "250-260", n = 30, spell = 19788, name = "Dense Blasting Powder", icon = "inv_misc_ammo_gunpowder_01", mats = "12365x60",
              note = "Amarillo desde 250: quizá más de 30." },
            { r = "260-285", n = 35, spell = 19791, name = "Thorium Widget", icon = "inv_gizmo_04", mats = "12359x105 14047x35", recipe = 16042,
              note = "Amarillo desde 280; si no llegas a 285, haz algún tubo más en el siguiente paso.",
              vendors = { { "H", "Orgrimmar", "Sovik" }, { "A", "Ironforge", "Gearcutter Cogspinner" } } },
            { r = "285-300", n = 20, spell = 19795, name = "Thorium Tube", icon = "inv_gizmo_pipe_04", mats = "12359x120", recipe = 16047,
              note = "En Forever el esquema se liga al recogerlo: cómpralo con el ingeniero.",
              vendors = { { "N", "Winterspring", "Xizzer Fizzbolt", "En Vista Eterna (Everlook), primer edificio a la derecha tras la puerta." } } },
        } },
    },
}
