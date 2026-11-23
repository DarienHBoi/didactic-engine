-- ForeverCampGuide - Logic.lua
local _, ns = ...
local L = ns.T

function ns.ParseRange(r)
    if type(r) ~= "string" then return nil end
    local a, b = r:match("(%d+)%-(%d+)")
    return tonumber(a), tonumber(b)
end

-- Ruta elegida en un bloque con varias rutas
function ns.RouteKey(guideKey, rankIndex, blockIndex, block)
    return block.group or (guideKey .. ":" .. rankIndex .. ":" .. blockIndex)
end

function ns.RouteIndex(guideKey, rankIndex, blockIndex, block)
    local key = ns.RouteKey(guideKey, rankIndex, blockIndex, block)
    local idx = ns.db and ns.db.routes[key] or 1
    if not block.routes[idx] then idx = 1 end
    return idx, key
end

-- Lista ordenada de los pasos principales según las rutas elegidas
function ns.OrderedSteps(guideKey)
    local g = ns.guides[guideKey]
    local list = {}
    if not g then return list end
    for ri, rank in ipairs(g.ranks or {}) do
        for _, s in ipairs(rank.steps or {}) do list[#list + 1] = { step = s, rank = rank } end
        for bi, block in ipairs(rank.blocks or {}) do
            for _, s in ipairs(block.steps or {}) do list[#list + 1] = { step = s, rank = rank } end
            if block.routes then
                local idx = ns.RouteIndex(guideKey, ri, bi, block)
                for _, s in ipairs(block.routes[idx].steps) do list[#list + 1] = { step = s, rank = rank } end
            end
        end
    end
    return list
end

-- Paso en el que estás según tu habilidad
function ns.CurrentStep(guideKey, skill)
    if not skill then return nil end
    for i, e in ipairs(ns.OrderedSteps(guideKey)) do
        local _, b = ns.ParseRange(e.step.r)
        if b and skill < b then return e, i end
    end
end

function ns.NextStepAfter(guideKey, index)
    local list = ns.OrderedSteps(guideKey)
    return list[(index or 0) + 1]
end

local RANKS = { [75] = "Aprendiz", [150] = "Oficial", [225] = "Experto", [300] = "Artesano" }
function ns.RankName(maxSkill)
    return L(RANKS[maxSkill or 0])
end

-- Aviso si estás en el tope de tu rango
function ns.CapWarning(skill, maxSkill)
    if skill and maxSkill and maxSkill < 300 and skill >= maxSkill then
        local nextRank = L(RANKS[maxSkill + 75]) or L("el siguiente rango")
        return (L("Has llegado al tope (%d). Aprende %s para seguir subiendo.")):format(maxSkill, nextRank)
    end
end

-- Todos los hechizos de receta de una guía, en orden y sin repetir
function ns.GuideSpells(guideKey)
    local g = ns.guides[guideKey]
    local out, seen = {}, {}
    local function add(step, rank)
        if step.spell and not seen[step.spell] then
            seen[step.spell] = true
            out[#out + 1] = { spell = step.spell, name = step.name, icon = step.icon, rank = rank, step = step }
        end
        for _, a in ipairs(step.alt or {}) do add(a, rank) end
        for _, a in ipairs(step.also or {}) do add(a, rank) end
    end
    for _, rank in ipairs(g and g.ranks or {}) do
        ns.ForEachStepList(rank, function(steps) for _, s in ipairs(steps) do add(s, rank) end end)
    end
    return out
end

------------------------------------------------------------------------
-- Cantidades según tu habilidad actual
-- Si un tramo va de 'from' a 'to' con n fabricaciones y ya estás dentro,
-- solo te queda la parte proporcional (aproximada: las recetas amarillas
-- no siempre dan punto).
------------------------------------------------------------------------

-- Fracción del tramo que te queda: 1 = entero, 0 = completado
function ns.StepFraction(r, skill)
    local from, to = ns.ParseRange(r)
    if not (from and to and skill) or to <= from then return 1 end
    if skill >= to then return 0 end
    if skill <= from then return 1 end
    return (to - skill) / (to - from)
end

-- Fabricaciones que te quedan de un paso. r = rango del paso padre (alternativas).
-- Devuelve left (o nil si el paso no tiene cantidad), total, fracción
function ns.StepRemaining(step, skill, r)
    local frac = ns.StepFraction(step.r or r, skill)
    if not step.n then return nil, nil, frac end
    if frac >= 1 then return step.n, step.n, frac end
    if frac <= 0 then return 0, step.n, frac end
    return math.max(1, math.ceil(step.n * frac - 1e-6)), step.n, frac
end

-- Materiales reducidos a las fabricaciones que quedan: { { id, necesitas, total } }
function ns.ScaleMats(s, left, n)
    local out = {}
    for _, m in ipairs(ns.ParseMats(s)) do
        local need = m[2]
        if left and n and n > 0 and left < n then need = math.ceil(m[2] * left / n - 1e-6) end
        out[#out + 1] = { m[1], need, m[2] }
    end
    return out
end

-- Productos intermedios que fabricas en un paso y gastas en otro (hechizo -> objeto)
ns.CRAFTS = {
    -- Sastrería
    [2963] = 2996, [2964] = 2997, [3839] = 4305, [3865] = 4339, [18401] = 14048,
    -- Peletería
    [2881] = 2318, [20648] = 2319, [20649] = 4234, [3816] = 4231, [3817] = 4233, [3818] = 4236,
    -- Herrería
    [2660] = 2862, [3320] = 3470, [3326] = 3478, [3337] = 3486, [9920] = 7966, [16641] = 12404, [7818] = 6338,
    -- Ingeniería
    [3918] = 4357, [3922] = 4359, [3929] = 4364, [3938] = 4371, [3942] = 4375, [3945] = 4377, [3953] = 4382,
    [3973] = 4404, [12585] = 10505, [12589] = 10559, [12591] = 10560, [12599] = 10561, [19788] = 15992, [19791] = 15994, [19795] = 16000,
    -- Encantamiento
    [7421] = 6218, [7795] = 6339, [13628] = 11130, [13702] = 11145, [20051] = 16207,
    -- Minería
    [2657] = 2840, [3304] = 3576, [2659] = 2841, [2658] = 2842, [3307] = 3575, [3308] = 3577,
}

-- Lo que aún necesitas para terminar la guía desde tu habilidad actual, siguiendo
-- las rutas elegidas y la opción principal de cada tramo. Los productos intermedios
-- que la propia guía te hace fabricar se descuentan.
-- Devuelve { { id, need }, ... } en orden de aparición, y el número de pasos que cuentan.
function ns.RemainingMaterials(guideKey, skill)
    local need, made, order, steps = {}, {}, {}, 0
    for _, e in ipairs(ns.OrderedSteps(guideKey)) do
        local s = e.step
        local function add(st, r)
            local left, n = ns.StepRemaining(st, skill, r)
            if not (left and left > 0) then return end
            steps = steps + 1
            for _, m in ipairs(ns.ScaleMats(st.mats, left, n)) do
                if m[2] > 0 then
                    if not need[m[1]] then need[m[1]] = 0; order[#order + 1] = m[1] end
                    need[m[1]] = need[m[1]] + m[2]
                end
            end
            local out = st.spell and ns.CRAFTS[st.spell]
            if out then made[out] = (made[out] or 0) + left end
        end
        if ns.ParseRange(s.r) then
            add(s)
            for _, a in ipairs(s.also or {}) do add(a, s.r) end
        end
    end
    local list = {}
    for _, id in ipairs(order) do
        local n = need[id] - (made[id] or 0)
        if n > 0 then list[#list + 1] = { id, n } end
    end
    return list, steps
end
