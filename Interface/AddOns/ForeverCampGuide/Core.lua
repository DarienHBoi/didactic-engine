-- ForeverCampGuide - Core.lua
local ADDON, ns = ...
local L = ns.T
_G.ForeverCampGuide = ns

local DEFAULTS_ACCOUNT = { coords = {} }
local DEFAULTS_CHAR = {
    known = {}, scanned = {}, routes = {}, checks = {}, coords = {},
    lastPage = "howto", lastTab = {},
    settings = {
        minimap = true, minimapAngle = 215, tracker = true, tooltips = true,
        learnCoords = true, showOtherFaction = false, hideDone = false, lang = "auto",
    },
}

------------------------------------------------------------------------
-- Utilidades
------------------------------------------------------------------------
local function norm(s)
    if type(s) ~= "string" then return nil end
    return (s:lower():gsub("%s+", " "))
end
ns.norm = norm

function ns.Print(msg) print("|cffffd100Camp Guide:|r " .. tostring(msg)) end

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

-- "2447x9 3371x9" -> { {2447, 9}, {3371, 9} } (con caché)
local matsCache = {}
function ns.ParseMats(s)
    if not s then return {} end
    local t = matsCache[s]
    if t then return t end
    t = {}
    for id, n in s:gmatch("(%d+)x(%d+)") do t[#t + 1] = { tonumber(id), tonumber(n) } end
    matsCache[s] = t
    return t
end

function ns.PlayerFaction()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    return (f == "Horde" and "H") or (f == "Alliance" and "A") or nil
end

-- ¿Se muestra este PNJ con los ajustes actuales?
function ns.NPCVisible(npc)
    if not ns.db or ns.db.settings.showOtherFaction then return true end
    local mine = ns.PlayerFaction()
    return npc[1] == "N" or not mine or npc[1] == mine
end

------------------------------------------------------------------------
-- Índices
------------------------------------------------------------------------
ns.profByKey, ns.itemIndex, ns.spellProf, ns.npcIndex, ns.matIndex, ns.bpIndex, ns.crateIndex = {}, {}, {}, {}, {}, {}, {}

local function IndexNPC(npc, profKey)
    if type(npc) ~= "table" or not npc[3] then return end
    local e = ns.npcIndex[npc[3]]
    if not e then
        e = { npc = npc, profs = {} }
        ns.npcIndex[npc[3]] = e
    end
    if profKey then e.profs[profKey] = true end
end

local function IndexMats(s, profKey)
    for _, m in ipairs(ns.ParseMats(s)) do
        ns.matIndex[m[1]] = ns.matIndex[m[1]] or {}
        ns.matIndex[m[1]][profKey] = true
    end
end

local function IndexStep(step, profKey)
    if step.spell then ns.spellProf[step.spell] = ns.spellProf[step.spell] or profKey end
    IndexMats(step.mats, profKey)
    for _, v in ipairs(step.vendors or {}) do IndexNPC(v, profKey) end
    for _, a in ipairs(step.alt or {}) do IndexStep(a, profKey) end
    for _, a in ipairs(step.also or {}) do IndexStep(a, profKey) end
end

-- Recorre todos los pasos de un rango (pasos sueltos y rutas)
function ns.ForEachStepList(rank, fn)
    if rank.steps then fn(rank.steps, nil, nil) end
    for bi, block in ipairs(rank.blocks or {}) do
        if block.steps then fn(block.steps, block, nil) end
        for ri, route in ipairs(block.routes or {}) do fn(route.steps, block, ri) end
    end
end

local function BuildIndexes()
    for _, prof in ipairs(ns.professions) do
        ns.profByKey[prof.key] = prof
        for t = 1, 3 do
            local tier = prof.tiers[t]
            if tier then ns.itemIndex[tier.item] = { prof = prof, tier = t, data = tier } end
        end
    end
    for i, fire in ipairs(ns.campfires) do
        ns.itemIndex[fire.item] = { campfire = fire, tier = i }
        if fire.spell then ns.spellProf[fire.spell] = "cooking" end
        if fire.bp then ns.bpIndex[fire.bp] = { campfire = fire } end
        IndexMats(fire.mats, "cooking")
    end
    for _, prof in ipairs(ns.professions) do
        for t = 1, 3 do
            local tier = prof.tiers[t]
            if tier then
                if tier.spell then ns.spellProf[tier.spell] = prof.key end
                if tier.bp then ns.bpIndex[tier.bp] = { prof = prof, tier = t, data = tier } end
                IndexMats(tier.mats, prof.key)
            end
        end
    end
    for _, g in ipairs(ns.misc and ns.misc.guides or {}) do
        for _, st in ipairs(g.steps or {}) do IndexNPC(st.point) end
        for _, pt in ipairs(g.points or {}) do IndexNPC(pt) end
    end
    local m = ns.merchant
    if m then
        for _, camp in ipairs(m.camps) do for _, n in ipairs(camp.npcs) do IndexNPC(n, nil) end end
        for pk, rows in pairs(m.recipes) do
            for _, r in ipairs(rows) do ns.spellProf[r[1]] = ns.spellProf[r[1]] or pk end
        end
        for _, crate in ipairs(m.crates) do
            for ti, id in pairs(crate.items) do ns.crateIndex[id] = { crate = crate, tier = ti } end
        end
    end

    for key, g in pairs(ns.guides) do
        local profKey = (key == "fishcook") and "cooking" or key
        for _, n in ipairs(g.capitals or {}) do IndexNPC(n, profKey) end
        for _, s in ipairs(g.starting or {}) do for _, n in ipairs(s.npcs) do IndexNPC(n, profKey) end end
        for _, ex in ipairs(g.extras or {}) do for _, n in ipairs(ex.npcs or {}) do IndexNPC(n, profKey) end end
        for _, sh in ipairs(g.shopping or {}) do
            for _, row in ipairs(sh.rows) do IndexMats(row[1], profKey); IndexMats(row.alt, profKey) end
        end
        for _, rank in ipairs(g.ranks or {}) do
            for _, n in ipairs(rank.trainers or {}) do IndexNPC(n, profKey) end
            ns.ForEachStepList(rank, function(steps) for _, st in ipairs(steps) do IndexStep(st, profKey) end end)
        end
        for _, list in ipairs(g.lists or {}) do
            for _, n in ipairs(list.npcs or {}) do IndexNPC(n, profKey) end
            for _, row in ipairs(list.rows) do ns.spellProf[row[1]] = ns.spellProf[row[1]] or profKey end
        end
        for _, sec in ipairs(g.sections or {}) do
            local parts = { sec.H or {}, sec.A or {}, sec.all or {} }
            for _, opt in ipairs(sec.options or {}) do parts[#parts + 1] = opt.tasks end
            for _, part in ipairs(parts) do
                for _, task in ipairs(part) do
                    if task.npc then IndexNPC(task.npc, profKey) end
                    if task.spell then ns.spellProf[task.spell] = ns.spellProf[task.spell] or profKey end
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- Objetos y hechizos (compatibles con API clásica y moderna)
------------------------------------------------------------------------
local function RawItemInfo(id)
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if f then return f(id) end
end

function ns.GetItemName(id, fallback)
    local name
    if C_Item and C_Item.GetItemNameByID then name = C_Item.GetItemNameByID(id) end
    if not name then name = RawItemInfo(id) end
    return name or fallback or ("item:" .. id)
end

function ns.GetItemLink(id)
    local _, link = RawItemInfo(id)
    return link
end

local QUESTION_MARK = 134400
function ns.GetItemIcon(id, fallback)
    local icon
    if C_Item and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(id)
    elseif GetItemIcon then icon = GetItemIcon(id) end
    if icon and icon ~= QUESTION_MARK then return icon end
    if fallback then return ns.ICON_PATH .. fallback end
    return QUESTION_MARK
end

function ns.RequestItem(id)
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id)
    else RawItemInfo(id) end
end

function ns.GetItemCount(id)
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not f then return 0 end
    local ok, n = pcall(f, id, true)
    if ok and type(n) == "number" and not IsSecret(n) then return n end
    return 0
end

function ns.GetSpellName(id, fallback)
    local name
    if C_Spell and C_Spell.GetSpellName then name = C_Spell.GetSpellName(id)
    elseif GetSpellInfo then name = GetSpellInfo(id) end
    return name or fallback
end

function ns.GetSpellIcon(id, fallback)
    local tex
    if id then
        if C_Spell and C_Spell.GetSpellTexture then
            local ok, t = pcall(C_Spell.GetSpellTexture, id); if ok then tex = t end
        elseif GetSpellTexture then
            local ok, t = pcall(GetSpellTexture, id); if ok then tex = t end
        end
    end
    if tex and tex ~= QUESTION_MARK then return tex end
    if fallback then return ns.ICON_PATH .. fallback end
    return QUESTION_MARK
end

-- Cantidad de una moneda (nil si el cliente no la conoce)
function ns.GetCurrency(id)
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
        if ok and type(info) == "table" and type(info.quantity) == "number" and not IsSecret(info.quantity) then
            return info.quantity, info.name, info.iconFileID
        end
    elseif GetCurrencyInfo then
        local ok, name, amount, icon = pcall(GetCurrencyInfo, id)
        if ok and type(amount) == "number" and name and name ~= "" then return amount, name, icon end
    end
    return nil
end

function ns.GetSpellLink(id)
    if C_Spell and C_Spell.GetSpellLink then return C_Spell.GetSpellLink(id) end
    if GetSpellLink then return GetSpellLink(id) end
end

function ns.InsertLink(link)
    if not link then return end
    if ChatEdit_InsertLink then ChatEdit_InsertLink(link)
    elseif ChatFrameUtil and ChatFrameUtil.InsertLink then ChatFrameUtil.InsertLink(link) end
end

------------------------------------------------------------------------
-- Nivel de habilidad
------------------------------------------------------------------------
-- Compara nombres sin mayúsculas ni tildes ("Sastrería" = "sastreria" = "SASTRERÍA")
local ACCENTS = {
    ["á"] = "a", ["é"] = "e", ["í"] = "i", ["ó"] = "o", ["ú"] = "u", ["ü"] = "u", ["ñ"] = "n",
    ["Á"] = "a", ["É"] = "e", ["Í"] = "i", ["Ó"] = "o", ["Ú"] = "u", ["Ü"] = "u", ["Ñ"] = "n",
    ["à"] = "a", ["è"] = "e", ["ì"] = "i", ["ò"] = "o", ["ù"] = "u", ["â"] = "a", ["ê"] = "e", ["î"] = "i", ["ô"] = "o", ["û"] = "u",
    ["ä"] = "a", ["ë"] = "e", ["ï"] = "i", ["ö"] = "o", ["ç"] = "c", ["ã"] = "a", ["õ"] = "o",
    ["É"] = "e", ["È"] = "e", ["Ä"] = "a", ["Ö"] = "o", ["Ç"] = "c",
}
local function fold(s)
    if type(s) ~= "string" then return nil end
    s = s:gsub("[\195][\128-\191]", function(ch) return ACCENTS[ch] or ch end)
    s = s:lower():gsub("[%s%p]+", " "):gsub("^ ", ""):gsub(" $", "")
    return s
end
ns.fold = fold

-- Datos independientes del idioma: línea de habilidad, hechizo de la profesión y otros nombres que usan los clientes
local PROF_IDS = {
    alchemy        = { line = 171, spell = 2259 },
    blacksmithing  = { line = 164, spell = 2018 },
    enchanting     = { line = 333, spell = 7411 },
    engineering    = { line = 202, spell = 4036 },
    herbalism      = { line = 182, spell = 9134, extra = { "Herbalismo", "Botánica" } },
    leatherworking = { line = 165, spell = 2108, extra = { "Marroquinería" } },
    mining         = { line = 186, spell = 2575 },
    skinning       = { line = 393, spell = 8613, extra = { "Desollar" } },
    tailoring      = { line = 197, spell = 3908, extra = { "Costura", "Sastre" } },
    cooking        = { line = 185, spell = 2550 },
    firstaid       = { line = 129, spell = 3273 },
    fishing        = { line = 356, spell = 7620 },
}
ns.PROF_IDS = PROF_IDS

-- Tabla nombre plegado -> profesión. Se completa con los nombres que da el propio cliente,
-- así funciona en cualquier idioma aunque el juego use otro nombre que el de la guía.
local aliasMap, aliasComplete, lineMap
local function BuildAliases()
    if aliasMap and aliasComplete then return aliasMap end
    aliasMap, lineMap = aliasMap or {}, lineMap or {}
    local complete = true
    for _, prof in ipairs(ns.professions) do
        aliasMap[fold(prof.name)] = prof
        for _, n in ipairs(prof.names) do aliasMap[fold(n)] = prof end
        local ids = PROF_IDS[prof.key]
        if ids then
            lineMap[ids.line] = prof
            for _, n in ipairs(ids.extra or {}) do aliasMap[fold(n)] = aliasMap[fold(n)] or prof end
            local got = false
            if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName then
                local ok, n = pcall(C_TradeSkillUI.GetTradeSkillDisplayName, ids.line)
                if ok and type(n) == "string" and n ~= "" then aliasMap[fold(n)] = prof; got = true end
            end
            local ok, n = pcall(ns.GetSpellName, ids.spell)
            if ok and type(n) == "string" and n ~= "" then
                if not aliasMap[fold(n)] then aliasMap[fold(n)] = prof end
                got = true
            end
            if not got then complete = false end
        end
    end
    aliasComplete = complete
    return aliasMap
end

function ns.ProfFromName(name)
    local n = fold(name)
    if not n or n == "" then return nil end
    local map = BuildAliases()
    if map[n] then return map[n] end
    -- "Sastrería clásica", "Classic Tailoring"...: el nombre contiene el de la profesión
    local best, bestLen
    for alias, prof in pairs(map) do
        if #alias >= 5 and (" " .. n .. " "):find(" " .. alias .. " ", 1, true) and (not bestLen or #alias > bestLen) then
            best, bestLen = prof, #alias
        end
    end
    return best
end

local function AddSkill(result, name, rank, maxRank, line)
    if type(rank) ~= "number" or rank < 0 then return end
    local prof = (line and lineMap and lineMap[line]) or ns.ProfFromName(name)
    if prof then
        if not result[prof.key] then result[prof.key] = { rank = rank, max = maxRank, name = name } end
    elseif type(name) == "string" then
        result.unknown = result.unknown or {}
        result.unknown[#result.unknown + 1] = name
    end
end

local skillCache, skillCacheTime
local function ScanSkills()
    local now = GetTime and GetTime() or 0
    if skillCache and skillCacheTime == now then return skillCache end
    BuildAliases()
    local result = {}
    if GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() do
            local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
            if not isHeader then pcall(AddSkill, result, name, rank, maxRank) end
        end
    end
    if GetProfessions and GetProfessionInfo then
        local a, b, c, d, e, f = GetProfessions()
        for _, idx in pairs({ a, b, c, d, e, f }) do
            local name, _, rank, maxRank, _, _, line = GetProfessionInfo(idx)
            pcall(AddSkill, result, name, rank, maxRank, line)
        end
    end
    skillCache, skillCacheTime = result, now
    return result
end

-- rank, maxRank o nil si no conoces la profesión
function ns.GetProfessionSkill(prof)
    if type(prof) == "string" then prof = ns.profByKey[prof] end
    if not prof then return nil end
    local ok, skills = pcall(ScanSkills)
    if not ok or not skills then return nil end
    local s = skills[prof.key]
    if s then return s.rank, s.max end
    return nil
end

-- /fcg debug: lo que el addon ve en este cliente (para informar de errores)
function ns.Debug()
    local build, _, _, toc = "?", nil, nil, "?"
    if GetBuildInfo then build, _, _, toc = GetBuildInfo() end
    local version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("ForeverCampGuide", "Version"))
        or (GetAddOnMetadata and GetAddOnMetadata("ForeverCampGuide", "Version")) or "?"
    ns.Print(("v%s · %s · %s (%s) · lang=%s"):format(tostring(version), tostring(GetLocale and GetLocale()), tostring(build), tostring(toc), tostring(ns.LANG)))
    skillCache = nil
    local ok, skills = pcall(ScanSkills)
    if not ok then ns.Print("ScanSkills: " .. tostring(skills)); return end
    for _, prof in ipairs(ns.professions) do
        local s = skills[prof.key]
        local ids = PROF_IDS[prof.key]
        local client = ids and ns.GetSpellName(ids.spell) or "?"
        ns.Print(("%s [%s] = %s"):format(prof.key, tostring(client), s and (s.rank .. "/" .. tostring(s.max) .. " «" .. tostring(s.name) .. "»") or "-"))
    end
    if skills.unknown then ns.Print(L("Habilidades no reconocidas: ") .. table.concat(skills.unknown, ", ")) end
    if ns.lastError then ns.Print(L("Último error: ") .. tostring(ns.lastError)) end
end

------------------------------------------------------------------------
-- Recetas conocidas
------------------------------------------------------------------------
local function ScanModern()
    if not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeInfo) then return false end
    local profName
    if C_TradeSkillUI.GetBaseProfessionInfo then
        local info = C_TradeSkillUI.GetBaseProfessionInfo()
        profName = info and info.professionName
    end
    if not profName and GetTradeSkillLine then profName = GetTradeSkillLine() end
    local ids = C_TradeSkillUI.GetAllRecipeIDs()
    if type(ids) ~= "table" or #ids == 0 then return false end
    local known = ns.char.known
    for _, id in ipairs(ids) do
        local info = C_TradeSkillUI.GetRecipeInfo(id)
        if info and info.learned ~= nil then known[id] = info.learned and true or false end
    end
    local prof = ns.ProfFromName(profName)
    if prof then ns.char.scanned[prof.key] = time and time() or 1 end
    return true
end

local function ScanClassic(numFn, infoFn, linkFn, lineFn)
    if not (numFn and infoFn) then return false end
    local n = numFn()
    if not n or n == 0 then return false end
    local known, names = ns.char.known, {}
    for i = 1, n do
        local name, kind = infoFn(i)
        if name and kind ~= "header" then
            names[norm(name)] = true
            local link = linkFn and linkFn(i)
            local id = link and tonumber(link:match("enchant:(%d+)") or link:match("spell:(%d+)"))
            if id then known[id] = true end
        end
    end
    local prof = lineFn and ns.ProfFromName((lineFn()))
    if prof then
        ns.char.scanned[prof.key] = time and time() or 1
        -- por nombre: las recetas de la guía de esta profesión que no aparecen no se conocen
        for spell, pk in pairs(ns.spellProf) do
            if pk == prof.key then
                local sn = norm(ns.GetSpellName(spell))
                if sn and names[sn] then known[spell] = true
                elseif known[spell] == nil then known[spell] = false end
            end
        end
    end
    return true
end

function ns.ScanRecipes()
    if not ns.char then return end
    local ok = pcall(ScanModern)
    pcall(ScanClassic, GetNumTradeSkills, GetTradeSkillInfo, GetTradeSkillRecipeLink, GetTradeSkillLine)
    pcall(ScanClassic, GetNumCrafts, GetCraftInfo, GetCraftRecipeLink, GetCraftDisplaySkillLine)
    ns.RequestRefresh()
end

-- true = la conoces, false = no la conoces, nil = sin datos todavía
function ns.IsRecipeKnown(spell)
    if not spell or not ns.char then return nil end
    if IsPlayerSpell then
        local ok, r = pcall(IsPlayerSpell, spell)
        if ok and r == true then return true end
    end
    local k = ns.char.known[spell]
    if k ~= nil then return k end
    local pk = ns.spellProf[spell]
    if pk and ns.char.scanned[pk] then return false end
    return nil
end

------------------------------------------------------------------------
-- Misiones
------------------------------------------------------------------------
function ns.IsQuestDone(id)
    if type(id) == "table" then id = id[ns.PlayerFaction() or "A"] or id.A or id.H end
    if not id then return nil end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then return C_QuestLog.IsQuestFlaggedCompleted(id) and true or false end
    if IsQuestFlaggedCompleted then return IsQuestFlaggedCompleted(id) and true or false end
    return nil
end

------------------------------------------------------------------------
-- Coordenadas de PNJ (se aprenden en el juego)
------------------------------------------------------------------------
-- Coordenadas incluidas en el addon (NPCCoords.lua), resueltas al mapa del cliente actual
local builtinCache = {}
function ns.BuiltinCoords(name)
    local c = builtinCache[name]
    if c ~= nil then return c or nil end
    local d = ns.NPC_COORDS and ns.NPC_COORDS[name]
    if d then
        local m = ns.ClientMapID(d[1])
        if m then c = { m = m, x = d[2] / 100, y = d[3] / 100, p = true, builtin = true } end
    end
    builtinCache[name] = c or false
    return c
end

-- Orden: ubicación fijada a mano > coordenadas de la web > ubicación aprendida al verlo
function ns.GetCoords(name)
    local saved = ns.char and ((ns.acct and ns.acct.coords[name]) or ns.char.coords[name])
    if saved and saved.manual then return saved end
    return ns.BuiltinCoords(name) or saved
end

-- PNJ dentro de una mazmorra (sin coordenadas en el mapa)
function ns.InstanceInfo(name)
    return ns.NPC_INSTANCE and ns.NPC_INSTANCE[name]
end

function ns.SaveCoords(name, mapID, x, y, precise, manual)
    local c = { m = mapID, x = x, y = y, p = precise and true or nil, manual = manual and true or nil }
    if ns.acct then ns.acct.coords[name] = c end
    ns.char.coords[name] = c   -- copia por personaje (por si el cliente no recarga los datos de cuenta)
end

function ns.PlayerPosition()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or type(mapID) ~= "number" or IsSecret(mapID) then return nil end
    local ok2, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok2 or not pos then return nil end
    local ok3, x, y = pcall(pos.GetXY, pos)
    if not ok3 or type(x) ~= "number" or IsSecret(x) or (x == 0 and y == 0) then return nil end
    return mapID, x, y
end

local function TryLearn(unit, precise)
    if not (ns.char and ns.db.settings.learnCoords) then return end
    if UnitIsPlayer and UnitIsPlayer(unit) then return end
    local ok, name = pcall(UnitName, unit)
    if not ok or type(name) ~= "string" or IsSecret(name) then return end
    local entry = ns.npcIndex[name]
    if not entry then return end
    if ns.BuiltinCoords(name) or ns.InstanceInfo(name) then return end   -- ya tenemos sus coordenadas
    local old = ns.GetCoords(name)
    if old and old.p and not precise then return end   -- no pisar una posición exacta con una aproximada
    local mapID, x, y = ns.PlayerPosition()
    if not mapID then return end
    local firstTime = not old
    ns.SaveCoords(name, mapID, x, y, precise)
    if firstTime then
        ns.Print((L("Ubicación de |cffffffff%s|r guardada (%.1f, %.1f). Ya puedes marcarlo en el mapa.")):format(name, x * 100, y * 100))
    end
    ns.RequestRefresh()
end

------------------------------------------------------------------------
-- Marcadores
------------------------------------------------------------------------
function ns.SetWaypoint(name, mapID, x, y)
    local placed = false
    if TomTom and TomTom.AddWaypoint then
        pcall(TomTom.AddWaypoint, TomTom, mapID, x, y, { title = name, persistent = false, minimap = true, world = true })
        placed = true
    end
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        local ok = pcall(function()
            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
        end)
        placed = placed or ok
    end
    if placed then
        ns.Print((L("Marcador puesto en %s (%.1f, %.1f).")):format(name, x * 100, y * 100))
    else
        ns.Print((L("No se pudo poner el marcador. Coordenadas: %.1f, %.1f")):format(x * 100, y * 100))
    end
end

function ns.OpenWorldMap(mapID)
    if not mapID then return end
    if OpenWorldMap then pcall(OpenWorldMap, mapID); return end
    if WorldMapFrame then
        if not WorldMapFrame:IsShown() and ToggleWorldMap then ToggleWorldMap() end
        if WorldMapFrame.SetMapID then pcall(WorldMapFrame.SetMapID, WorldMapFrame, mapID) end
    end
end

------------------------------------------------------------------------
-- Tooltips
------------------------------------------------------------------------
local function AddTooltipLines(tt, id)
    if not (id and ns.db and ns.db.settings.tooltips) then return false end
    local added = false
    local info = ns.itemIndex[id]
    if info then
        if info.campfire then
            tt:AddLine((L("|cffffd100Camp Guide:|r fogata de Cocina, %d huecos (usar: Cocina %d)")):format(info.campfire.slots, info.campfire.use), 0.9, 0.9, 0.9, true)
        else
            tt:AddLine((L("|cffffd100Camp Guide:|r objeto de campamento de %s, nivel %d (habilidad %d)")):format(ns.ProfName(info.prof), info.tier, info.data.skill), 0.9, 0.9, 0.9, true)
        end
        added = true
    end
    local bp = ns.bpIndex[id]
    if bp then
        local what = bp.campfire and ns.GetItemName(bp.campfire.item, bp.campfire.name) or (ns.ProfName(bp.prof) .. " " .. bp.tier)
        tt:AddLine((L("|cffffd100Camp Guide:|r plano de campamento (%s)")):format(what), 0.9, 0.9, 0.9, true)
        added = true
    end
    local cr = ns.crateIndex[id]
    if cr then
        local fav = cr.crate.favor[cr.tier]
        tt:AddLine((L("|cffffd100Camp Guide:|r caja de Favor del mercader (%s, %s)")):format(L(ns.merchant.tiers[cr.tier].title),
            fav and ((L("%d de favor")):format(fav)) or L("favor desconocido")), 0.9, 0.9, 0.9, true)
        added = true
    end
    local mats = ns.matIndex[id]
    if mats then
        local names = {}
        for pk in pairs(mats) do names[#names + 1] = ns.profByKey[pk] and ns.ProfName(ns.profByKey[pk]) or pk end
        table.sort(names)
        tt:AddLine(L("|cffffd100Camp Guide:|r material usado en: ") .. table.concat(names, ", "), 0.9, 0.9, 0.9, true)
        added = true
    end
    return added
end

local function HookTooltips()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
            pcall(AddTooltipLines, tt, data and data.id)
        end)
    else
        local function OnSetItem(tt)
            pcall(function()
                local _, link = tt:GetItem()
                local id = link and tonumber(link:match("item:(%d+)"))
                if AddTooltipLines(tt, id) then tt:Show() end
            end)
        end
        for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
            if tt and tt.HookScript then pcall(tt.HookScript, tt, "OnTooltipSetItem", OnSetItem) end
        end
    end
end

------------------------------------------------------------------------
-- Botón del minimapa
------------------------------------------------------------------------
local function UpdateMinimapPos(b)
    local angle = math.rad(ns.db.settings.minimapAngle or 215)
    local r = (Minimap:GetWidth() / 2) + 6
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

function ns.CreateMinimapButton()
    if ns.minimapButton or not Minimap then return end
    local b = CreateFrame("Button", "ForeverCampGuideMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("AnyUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20); bg:SetPoint("TOPLEFT", 7, -5)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20); icon:SetPoint("TOPLEFT", 6, -5)
    icon:SetTexture(ns.LOGO)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53); border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then ns.ShowPage("options") else ns.Toggle() end
    end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(s)
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            ns.db.settings.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            UpdateMinimapPos(s)
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L("Guía de profesiones y campamento"))
        GameTooltip:AddLine(L("Clic: abrir / cerrar"), 1, 1, 1)
        GameTooltip:AddLine(L("Clic derecho: opciones"), 1, 1, 1)
        GameTooltip:AddLine(L("Arrastrar: mover el botón"), 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ns.minimapButton = b
    UpdateMinimapPos(b)
    b:SetShown(ns.db.settings.minimap)
end

------------------------------------------------------------------------
-- Refresco diferido (evita reconstruir la interfaz varias veces por segundo)
------------------------------------------------------------------------
local refreshPending = false
local refresher = CreateFrame("Frame")
refresher:Hide()
refresher:SetScript("OnUpdate", function(self, elapsed)
    self.t = (self.t or 0) + elapsed
    if self.t < 0.3 then return end
    self.t = 0
    self:Hide()
    refreshPending = false
    if ns.RefreshCurrent then ns.RefreshCurrent() end
    if ns.Tracker and ns.Tracker.Refresh then ns.Tracker.Refresh() end
end)
function ns.RequestRefresh()
    if refreshPending then return end
    refreshPending = true
    refresher.t = 0
    refresher:Show()
end

------------------------------------------------------------------------
-- Comandos
------------------------------------------------------------------------
local function FindProfession(query)
    query = ns.fold(query)
    if not query or query == "" then return nil end
    local exact = ns.ProfFromName(query)
    if exact then return exact end
    for _, prof in ipairs(ns.professions) do
        if prof.key:find(query, 1, true) == 1 or ns.fold(prof.name):find(query, 1, true) == 1 then return prof end
        for _, n in ipairs(prof.names) do
            if ns.fold(n):find(query, 1, true) == 1 then return prof end
        end
        for _, n in ipairs((ns.PROF_IDS[prof.key] or {}).extra or {}) do
            if ns.fold(n):find(query, 1, true) == 1 then return prof end
        end
    end
end

SLASH_FOREVERCAMPGUIDE1 = "/fcg"
SLASH_FOREVERCAMPGUIDE2 = "/campamento"
SlashCmdList.FOREVERCAMPGUIDE = function(msg)
    msg = strtrim(msg or "")
    local lower = msg:lower()
    if lower == "" then ns.Toggle()
    elseif lower == "opciones" or lower == "config" or lower == "options" or lower == "settings" then ns.ShowPage("options")
    elseif lower == "favor" or lower == "merchant" then ns.ShowPage("merchant")
    elseif lower == "fogatas" or lower == "campfires" then ns.ShowPage("campfires")
    elseif lower == "inicio" or lower == "start" then ns.ShowPage("first")
    elseif lower == "mapa" or lower == "map" then ns.Map.ShowZone(nil)
    elseif lower == "tracker" then
        ns.db.settings.tracker = not ns.db.settings.tracker
        ns.Print(L("Panel junto a la ventana de profesión: ") .. (ns.db.settings.tracker and L("activado") or L("desactivado")))
        if ns.Tracker then ns.Tracker.Refresh() end
    elseif lower == "minimap" then
        ns.db.settings.minimap = not ns.db.settings.minimap
        if ns.minimapButton then ns.minimapButton:SetShown(ns.db.settings.minimap) end
    elseif lower == "debug" or lower == "diagnostico" or lower == "diagnóstico" then ns.Debug()
    elseif lower == "varios" or lower == "misc" or lower == "saco" or lower == "antorcha" or lower == "torch" or lower == "sleeping bag" then ns.ShowPage("misc")
    elseif lower == "ayuda" or lower == "help" then
        ns.Print(L("/fcg - abrir o cerrar la guía"))
        ns.Print(L("/fcg <profesión> - abrir una profesión (ej.: /fcg alq, /fcg pesca)"))
        ns.Print(L("/fcg fogatas | inicio | favor | mapa | opciones"))
        ns.Print(L("/fcg tracker - panel junto a la ventana de profesión"))
        ns.Print(L("/fcg minimap - mostrar/ocultar el botón del minimapa"))
        ns.Print(L("/fcg varios - saco de dormir y antorcha"))
        ns.Print(L("/fcg debug - datos para informar de un error"))
    else
        local prof = FindProfession(msg)
        if prof then ns.ShowPage(prof.key) else ns.Print((L("No encontré «%s». Escribe /fcg ayuda.")):format(msg)) end
    end
end

function ForeverCampGuide_OnAddonCompartmentClick() ns.Toggle() end

------------------------------------------------------------------------
-- Eventos
------------------------------------------------------------------------
local events = CreateFrame("Frame")
local function Reg(e) pcall(events.RegisterEvent, events, e) end
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "SKILL_LINES_CHANGED", "GET_ITEM_INFO_RECEIVED", "BAG_UPDATE_DELAYED",
                     "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "TRADE_SKILL_CLOSE",
                     "NEW_RECIPE_LEARNED", "LEARNED_SPELL_IN_TAB", "CRAFT_SHOW", "CRAFT_UPDATE", "CRAFT_CLOSE",
                     "CURRENCY_DISPLAY_UPDATE", "UPDATE_MOUSEOVER_UNIT", "PLAYER_TARGET_CHANGED", "GOSSIP_SHOW", "TRAINER_SHOW", "MERCHANT_SHOW",
                     "QUEST_TURNED_IN", "CHAT_MSG_SKILL" }) do
    Reg(e)
end

local function InitDB()
    ForeverCampGuideDB = type(ForeverCampGuideDB) == "table" and ForeverCampGuideDB or {}
    ForeverCampGuideCharDB = type(ForeverCampGuideCharDB) == "table" and ForeverCampGuideCharDB or {}
    CopyDefaults(DEFAULTS_ACCOUNT, ForeverCampGuideDB)
    CopyDefaults(DEFAULTS_CHAR, ForeverCampGuideCharDB)
    ns.acct, ns.char = ForeverCampGuideDB, ForeverCampGuideCharDB
    ns.db = ns.char
    ns.ApplyLanguage(ns.db.settings.lang)
    -- unir coordenadas guardadas por este personaje con las de la cuenta
    for name, c in pairs(ns.char.coords) do
        if not ns.acct.coords[name] then ns.acct.coords[name] = c end
    end
end

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then
            BuildIndexes()
            InitDB()
        end
    elseif event == "PLAYER_LOGIN" then
        if not ns.char then InitDB() end
        for id in pairs(ns.itemIndex) do ns.RequestItem(id) end
        HookTooltips()
        ns.CreateMinimapButton()
    elseif event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" or event == "QUEST_TURNED_IN" then
        ns.RequestRefresh()
    elseif event == "GET_ITEM_INFO_RECEIVED" or event == "BAG_UPDATE_DELAYED" or event == "CURRENCY_DISPLAY_UPDATE" then
        ns.RequestRefresh()
    elseif event == "TRADE_SKILL_SHOW" or event == "CRAFT_SHOW" then
        ns.ScanRecipes()
        if ns.Tracker then ns.Tracker.OnProfessionOpen() end
    elseif event == "TRADE_SKILL_LIST_UPDATE" or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" or event == "CRAFT_UPDATE"
        or event == "NEW_RECIPE_LEARNED" or event == "LEARNED_SPELL_IN_TAB" then
        ns.ScanRecipes()
    elseif event == "TRADE_SKILL_CLOSE" or event == "CRAFT_CLOSE" then
        if ns.Tracker then ns.Tracker.OnProfessionClose() end
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        TryLearn("mouseover", false)
    elseif event == "PLAYER_TARGET_CHANGED" then
        TryLearn("target", false)
    elseif event == "GOSSIP_SHOW" or event == "TRAINER_SHOW" or event == "MERCHANT_SHOW" then
        TryLearn("npc", true)
    end
end)
