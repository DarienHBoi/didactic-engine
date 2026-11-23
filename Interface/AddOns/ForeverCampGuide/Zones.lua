-- ForeverCampGuide - Zones.lua
-- Clave = nombre en inglés (el que usan las guías). es = nombre en español.
-- c = uiMapID de Classic Era, r = uiMapID del cliente moderno. El addon comprueba en el juego
-- cuál existe y, si ninguno coincide, busca la zona por nombre en el mapa del mundo.
local _, ns = ...

ns.ZONES = {
    ["Orgrimmar"]            = { es = "Orgrimmar",                     c = 1454, r = 85 },
    ["Undercity"]            = { es = "Entrañas",                      c = 1458, r = 90 },
    ["Thunder Bluff"]        = { es = "Cima del Trueno",               c = 1456, r = 88 },
    ["Stormwind City"]       = { es = "Ventormenta",                   c = 1453, r = 84 },
    ["Ironforge"]            = { es = "Forjaz",                        c = 1455, r = 87 },
    ["Darnassus"]            = { es = "Darnassus",                     c = 1457, r = 89 },
    ["Durotar"]              = { es = "Durotar",                       c = 1411, r = 1 },
    ["Mulgore"]              = { es = "Mulgore",                       c = 1412, r = 7 },
    ["The Barrens"]          = { es = "Los Baldíos",                   c = 1413, r = 10 },
    ["Alterac Mountains"]    = { es = "Montañas de Alterac",           c = 1416 },
    ["Arathi Highlands"]     = { es = "Tierras Altas de Arathi",       c = 1417, r = 14 },
    ["Badlands"]             = { es = "Tierras Inhóspitas",            c = 1418, r = 15 },
    ["Tirisfal Glades"]      = { es = "Claros de Tirisfal",            c = 1420, r = 18 },
    ["Silverpine Forest"]    = { es = "Bosque de Argénteos",           c = 1421, r = 21 },
    ["Western Plaguelands"]  = { es = "Tierras de la Peste del Oeste", c = 1422, r = 22 },
    ["Hillsbrad Foothills"]  = { es = "Laderas de Trabalomas",         c = 1424, r = 25 },
    ["The Hinterlands"]      = { es = "Tierras del Interior",          c = 1425, r = 26 },
    ["Dun Morogh"]           = { es = "Dun Morogh",                    c = 1426, r = 27 },
    ["Elwynn Forest"]        = { es = "Bosque de Elwynn",              c = 1429, r = 37 },
    ["Duskwood"]             = { es = "Bosque del Ocaso",              c = 1431, r = 47 },
    ["Loch Modan"]           = { es = "Loch Modan",                    c = 1432, r = 48 },
    ["Redridge Mountains"]   = { es = "Montañas Crestagrana",          c = 1433, r = 49 },
    ["Stranglethorn Vale"]   = { es = "Vega de Tuercespina",           c = 1434, r = 224 },
    ["Swamp of Sorrows"]     = { es = "Pantano de las Penas",          c = 1435, r = 51 },
    ["Westfall"]             = { es = "Páramos de Poniente",           c = 1436, r = 52 },
    ["Wetlands"]             = { es = "Los Humedales",                 c = 1437, r = 56 },
    ["Teldrassil"]           = { es = "Teldrassil",                    c = 1438, r = 57 },
    ["Darkshore"]            = { es = "Costa Oscura",                  c = 1439, r = 62 },
    ["Ashenvale"]            = { es = "Vallefresno",                   c = 1440, r = 63 },
    ["Thousand Needles"]     = { es = "Las Mil Agujas",                c = 1441, r = 64 },
    ["Stonetalon Mountains"] = { es = "Sierra Espolón",                c = 1442, r = 65 },
    ["Desolace"]             = { es = "Desolace",                      c = 1443, r = 66 },
    ["Feralas"]              = { es = "Feralas",                       c = 1444, r = 69 },
    ["Dustwallow Marsh"]     = { es = "Marjal Revolcafango",           c = 1445, r = 70 },
    ["Tanaris"]              = { es = "Tanaris",                       c = 1446, r = 71 },
    ["Felwood"]              = { es = "Frondavil",                     c = 1448, r = 77 },
    ["Un'Goro Crater"]       = { es = "Cráter de Un'Goro",             c = 1449, r = 78 },
    ["Moonglade"]            = { es = "Claro de la Luna",              c = 1450, r = 80 },
    ["Silithus"]             = { es = "Silithus",                      c = 1451, r = 81 },
    ["Winterspring"]         = { es = "Cuna del Invierno",             c = 1452, r = 83 },
    ["Eastern Plaguelands"]  = { es = "Tierras de la Peste del Este",  c = 1423, r = 23 },
    ["Blasted Lands"]        = { es = "Las Tierras Devastadas",        c = 1419, r = 17 },
    ["Searing Gorge"]        = { es = "La Garganta de Fuego",          c = 1427, r = 32 },
    ["Burning Steppes"]      = { es = "Las Estepas Ardientes",         c = 1428, r = 36 },
    ["Zephras Isle"]         = { es = "Zephras Isle",                  c = 2521 },   -- zona nueva de Forever
}

-- uiMapID de Classic -> clave de zona (para las coordenadas de NPCCoords.lua)
local CLASSIC_TO_KEY
function ns.ZoneKeyFromClassicID(id)
    if not CLASSIC_TO_KEY then
        CLASSIC_TO_KEY = {}
        for key, z in pairs(ns.ZONES) do if z.c then CLASSIC_TO_KEY[z.c] = key end end
    end
    return CLASSIC_TO_KEY[id]
end

-- Convierte un uiMapID de Classic al del cliente actual (o nil si la zona no existe)
function ns.ClientMapID(classicID)
    local key = ns.ZoneKeyFromClassicID(classicID)
    if key then return ns.ResolveMapID(key) end
    if C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(classicID) then return classicID end
    return nil
end

-- Mazmorras donde caen los planos de campamento
ns.DUNGEONS = {
    ["The Deadmines"]             = "Las Minas de la Muerte",
    ["Wailing Caverns"]           = "Cuevas de los Lamentos",
    ["Shadowfang Keep"]           = "Castillo de Colmillo Oscuro",
    ["Blackfathom Deeps"]         = "Cavernas de Brazanegra",
    ["Ruins of Lordaeron"]        = "Ruinas de Lordaeron",
    ["City of Dalaran"]           = "Ciudad de Dalaran",
    ["Excavation Site: Wetlands"] = "Excavación: Los Humedales",
    ["Uldaman"]                   = "Uldaman",
}
function ns.DungeonName(key)
    if ns.LANG ~= "es" then return key end
    return ns.DUNGEONS[key] or key
end

-- Nombre visible de una zona
function ns.ZoneName(key)
    if ns.LANG ~= "es" then return key end
    local z = ns.ZONES[key]
    return z and z.es or key
end

------------------------------------------------------------------------
-- Resolución del uiMapID en el cliente actual
------------------------------------------------------------------------
local resolved = {}
local nameIndex

local function norm(s)
    if type(s) ~= "string" then return "" end
    return (s:lower():gsub("[%s%p]", ""))
end

local function BuildNameIndex()
    nameIndex = {}
    if not (C_Map and C_Map.GetMapChildrenInfo) then return end
    for _, root in ipairs({ 947, 1414, 1415, 12, 13 }) do
        local ok, children = pcall(C_Map.GetMapChildrenInfo, root, nil, true)
        if ok and type(children) == "table" then
            for _, info in ipairs(children) do
                if info.name and info.mapID then
                    local k = norm(info.name)
                    if not nameIndex[k] then nameIndex[k] = info.mapID end
                end
            end
        end
    end
end

local function NameMatches(mapID, key)
    if not (C_Map and C_Map.GetMapInfo) then return false end
    local info = C_Map.GetMapInfo(mapID)
    if not info or not info.name then return false end
    local z = ns.ZONES[key]
    local n = norm(info.name)
    return n == norm(key) or (z and n == norm(z.es))
end

function ns.ResolveMapID(key)
    if resolved[key] ~= nil then return resolved[key] or nil end
    local z = ns.ZONES[key] or {}
    local result
    for _, id in ipairs({ z.c, z.r }) do
        if id and NameMatches(id, key) then result = id; break end
    end
    if not result then
        if not nameIndex then BuildNameIndex() end
        result = nameIndex[norm(key)] or (z.es and nameIndex[norm(z.es)])
    end
    if not result and C_Map and C_Map.GetMapInfo then
        -- último recurso: el ID que exista (cliente en otro idioma)
        for _, id in ipairs({ z.c, z.r }) do
            if id and C_Map.GetMapInfo(id) then result = id; break end
        end
    end
    resolved[key] = result or false
    return result
end
