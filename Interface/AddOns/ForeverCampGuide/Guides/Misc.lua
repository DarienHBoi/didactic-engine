-- ForeverCampGuide - Guides/Misc.lua
-- Mini guías de objetos útiles que no son de profesión. Datos de method.gg y conquestcapped.com (2026-11-14).
-- Los puntos usan el mismo formato que los PNJ: { facción, zona, clave, nota, label = nombre visible }.
local _, ns = ...

local SB = { -- puntos del Saco de dormir
    westfall = { "N", "Westfall", "Sleeping Bag: Burned-Out Remains (Westfall)", "En la carreta rota de la Granja de Alexston.", label = "Restos calcinados (Páramos de Poniente)" },
    barrens  = { "N", "The Barrens", "Sleeping Bag: Burned-Out Remains (The Barrens)", "En la torre de vigilancia quemada al sur del Campamento Taurajo.", label = "Restos calcinados (Los Baldíos)" },
    camp     = { "N", "Stonetalon Mountains", "Sleeping Bag: Mountain Camp", "Campamento en la montaña, pasado el Refugio Roca del Sol (Sun Rock Retreat).", label = "Campamento de la montaña" },
    mound    = { "N", "Stonetalon Mountains", "Sleeping Bag: Mound of Dirt", "En la ladera, colina arriba al norte del campamento. Baja con cuidado.", label = "Montón de tierra" },
    dam      = { "N", "Loch Modan", "Sleeping Bag: Dam Ledge", "Cornisa bajo el centro de la Presa de las Tres Cabezas (Stonewrought Dam).", label = "Cornisa de la presa" },
    wall     = { "N", "Hillsbrad Foothills", "Sleeping Bag: Thoradin's Wall", "Encima de la Muralla de Thoradin, junto a la carreta rota.", label = "Saco en la Muralla de Thoradin" },
}

local function Guard(n, place, hint)
    return { "N", "Duskwood", "Night Watch Guard " .. n, hint, label = "Guardia de la Noche " .. n .. ": " .. place }
end

ns.misc = {
    sources = "method.gg · conquestcapped.com",
    guides = {
        {
            key = "sleepingbag", title = "Saco de dormir acogedor", item = 211527, doneQuest = 79976,
            intro = "El Saco de dormir acogedor (Cozy Sleeping Bag) cuenta como zona de descanso: puedes desconectarte en cualquier sitio y acumular experiencia descansada. "
                 .. "Además, dormir dentro te da +1% de experiencia por minuto, hasta +3%, durante 2 horas (vale para toda la experiencia, también la de misiones).",
            facts = {
                "Si lo usas antes de que caduque el beneficio, se renueva entero: basta con dormir 1 minuto en vez de 3.",
                "La cadena lleva unos 90 minutos (más para la Horda) y también da la Caja de herramientas vieja, una bolsa de 12 casillas.",
                "Nivel recomendado: 30 o más. Hay tramos por zonas de nivel alto y guardias hostiles.",
                "Pon tu piedra de hogar en una capital antes de empezar: Orgrimmar o Entrañas (Horda), Ventormenta o Forjaz (Alianza).",
            },
            bonusItem = 221498,
            steps = {
                { f = "A", point = SB.westfall, text = "Examina los Restos calcinados (Burned-Out Remains) dentro de la carreta rota para recibir la misión «...and that note you found»." },
                { f = "A", point = SB.barrens, quest = 79008,
                  text = "Entrega la nota en los restos de la torre quemada y recibe «Stepping Stones».",
                  travel = "Ruta: de Páramos de Poniente a Bosque del Ocaso (de paso coge la antorcha), baja por Tuercespina hasta Bahía del Botín y toma el barco a Trinquete (Ratchet). Es el tramo más peligroso por el nivel de Tuercespina." },
                { f = "H", point = SB.barrens, text = "Examina los Restos calcinados (Burned-Out Remains) de la torre de vigilancia quemada para recibir la misión «...and that note you found»." },
                { f = "H", point = SB.westfall, quest = 79007,
                  text = "Entrega la nota en los restos de la carreta rota y recibe «Stepping Stones».",
                  travel = "Ruta: zepelín de Orgrimmar a Grom'gol (Tuercespina), salta al mar y nada hasta la costa sur de Páramos de Poniente." },
                { point = SB.camp, quest = 79192,
                  text = "Entrega «Stepping Stones»: recibes la Caja de herramientas vieja (bolsa de 12 casillas) y la misión «Scramble».",
                  travel = "Alianza: desde la torre quemada ve al noroeste hacia Sierra Espolón evitando El Cruce. Horda: vuelve nadando a Grom'gol (hay nagas hostiles), zepelín a Orgrimmar sin gastar la piedra de hogar, vuela a El Cruce y sigue el camino al oeste." },
                { point = SB.mound, quest = 79980,
                  text = "Examina el Montón de tierra (Mound of Dirt) para completar «Scramble» y recibir «Wet Job».",
                  travel = "Desde el campamento sube la colina hacia el norte y déjate caer con cuidado hasta el montón, sin caer demasiado." },
                { point = SB.dam, quest = 79974,
                  text = "Ve al centro de la presa y déjate caer a la cornisa de abajo. Entrega «Wet Job» y recibe «Eagle's Fist».",
                  travel = "Alianza: piedra de hogar a Ventormenta o Forjaz (tranvía) y corre a Loch Modan; entra a la presa por el norte. Horda: piedra de hogar, zepelín a Entrañas y corre hasta Loch Modan (unos 40 minutos sin montura, con enemigos de hasta nivel 60); los guardias de la presa probablemente te maten por el camino." },
                { point = SB.wall, quest = 79975, final = 79976,
                  text = "Entrega «Eagle's Fist» en el saco de encima de la muralla, acepta «This Must Be the Place» y haz clic en el pergamino de al lado: recibes el Saco de dormir acogedor.",
                  travel = "Cruza Los Humedales y las Tierras Altas de Arathi hasta Laderas de Trabalomas. Al entrar gira a la derecha y sigue la muralla hasta el hueco con la carreta rota. "
                        .. "Carreta: salta al cilindro grande, luego a la segunda viga de la derecha, arriba del todo y corre hasta la muralla. "
                        .. "Muralla: salta a las rocas pequeñas de la izquierda, a las grandes del centro y a las de arriba a la derecha, y sube corriendo." },
            },
        },
        {
            key = "torch", title = "Antorcha del Guardia de la Noche", item = 280612, doneQuest = 98372,
            intro = "La Antorcha del Guardia de la Noche (Night Watchman's Torch) enciende una antorcha en tu mano durante 5 minutos (30 segundos de reutilización). "
                 .. "Es sobre todo estética, pero ayuda en cuevas y criptas oscuras. Sirve para ambas facciones y no pide nivel.",
            facts = {
                "Cómo conseguirla: busca en Bosque del Ocaso el cadáver de un Guardia de la Noche (Night Watch Guard). Tiene una misión instantánea, «An Unfortunate End»: acéptala y entrégala en el mismo cadáver.",
                "El cadáver cambia de sitio cada cierto tiempo entre los 9 puntos de abajo. Si no está, prueba el siguiente; varios jugadores pueden coger la misión del mismo cadáver.",
                "Algunas guías dicen que solo aparece de noche (desde las 20:00 del juego); otros jugadores lo han encontrado a cualquier hora. Si no lo ves de día, vuelve de noche.",
                "Se apaga al entrar en combate, nadar o entrar en un edificio, y no funciona en posadas ni capitales. No puedes desenvainar armas con ella encendida.",
                "Es única y se liga al recogerla. Si la borras, puedes volver a Bosque del Ocaso a por otra.",
                "Horda: zepelín de Orgrimmar a Grom'gol y sube al norte hasta Bosque del Ocaso.",
                "Según los jugadores, en las Ruinas de Ban'aethal (Zephras Isle) encender la antorcha revela la Empuñadura antigua de la cadena Dawn Waker.",
            },
            macro = "/target Night Watch Guard",
            pointsTitle = "Dónde puede aparecer el cadáver",
            points = {
                Guard(1, "Colina del Cuervo", "Detrás de la casa junto a Jitters, delante de la letrina. El punto más fiable."),
                Guard(2, "cementerio (arriba)", "En lo alto del Cementerio de la Colina del Cuervo, entre necrófagos de nivel 25."),
                Guard(3, "cementerio (abajo)", "En la parte baja del Cementerio de la Colina del Cuervo."),
                Guard(4, "Granja de Addle", "Dentro de la casita de Addle's Stead: no se alcanza a través de la pared."),
                Guard(5, "bosque del oeste", "En el bosque, al noreste de Addle's Stead."),
                Guard(6, "camino a la Arboleda", "En el sendero hacia la Arboleda del Crepúsculo (Twilight Grove)."),
                Guard(7, "camino a Tuercespina", "En el camino que baja al sur hacia Tuercespina."),
                Guard(8, "Arboleda Brightwood", "En Brightwood Grove."),
                Guard(9, "sur de Villa Oscura", "En la colina al sur de Villa Oscura, cerca del Cementerio Jardines Tranquilos."),
            },
        },
    },
}

-- Coordenadas (uiMapID de Classic, x, y)
local C = ns.NPC_COORDS
C[SB.westfall[3]] = { 1436, 37.1, 50.1 }
C[SB.barrens[3]]  = { 1413, 46.1, 74.3 }
C[SB.camp[3]]     = { 1442, 54.6, 52.4 }
C[SB.mound[3]]    = { 1442, 39.6, 49.9 }
C[SB.dam[3]]      = { 1432, 49.5, 12.9 }
C[SB.wall[3]]     = { 1424, 87.4, 49.6 }
local GUARD = { { 17.0, 54.8 }, { 20.9, 34.4 }, { 23.7, 33.4 }, { 21.8, 72.6 }, { 30.0, 67.4 }, { 47.8, 59.4 }, { 45.9, 78.3 }, { 66.1, 34.0 }, { 68.8, 69.7 } }
for i, xy in ipairs(GUARD) do C["Night Watch Guard " .. i] = { 1431, xy[1], xy[2] } end
