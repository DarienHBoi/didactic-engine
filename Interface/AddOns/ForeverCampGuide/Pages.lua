-- ForeverCampGuide - Pages.lua
-- Constructores de las páginas. Cada uno recibe el lienzo (c) y el contexto (ctx).
local _, ns = ...
local L = ns.T
local W = ns.W
local P = {}
ns.P = P

local GOLD, WHITE, GREY, GREEN, RED, ORANGE = W.GOLD, W.WHITE, W.GREY, W.GREEN, W.RED, W.ORANGE

local RACE_TOKENS = {}
local RACE_FACTION = { Orc = "H", Troll = "H", Tauren = "H", Scourge = "H", Undead = "H",
                       Human = "A", Dwarf = "A", Gnome = "A", NightElf = "A" }

------------------------------------------------------------------------
-- Piezas comunes
------------------------------------------------------------------------
local function NPCTooltip(npc)
    return function(tt)
        tt:SetText(npc.label and L(npc.label) or npc[3], 1, 0.82, 0)
        tt:AddLine(ns.ZoneName(npc[2]), 1, 1, 1)
        if npc[4] then tt:AddLine(L(npc[4]), 0.85, 0.85, 0.85, true) end
        local c = ns.GetCoords(npc[3])
        local inst = ns.InstanceInfo(npc[3])
        if c then tt:AddLine((L("Coordenadas: %.1f, %.1f")):format(c.x * 100, c.y * 100), 0.25, 1, 0.25)
        elseif inst then tt:AddLine((L("Dentro de la mazmorra %s")):format(ns.DungeonName(inst.dungeon)), 1, 0.6, 0.2)
        else tt:AddLine(L("Sin coordenadas"), 1, 0.6, 0.2) end
        tt:AddLine(L("Clic: ver en el mapa"), 0.55, 0.55, 0.55)
    end
end

function P.NPC(c, npc, x, force)
    x = x or 0
    if not force and not ns.NPCVisible(npc) then return false end
    local f = c:BeginFlow(x + 6, 17)
    local col = (npc[1] == "H" and { 1, 0.36, 0.29 }) or (npc[1] == "A" and { 0.29, 0.64, 1 }) or { 1, 0.82, 0 }
    f:Link(npc.label and L(npc.label) or npc[3], function() ns.Map.ShowNPC(npc) end, NPCTooltip(npc), "GameFontNormal", col)
    f:Text(GREY .. ns.ZoneName(npc[2]) .. "|r")
    local coords = ns.GetCoords(npc[3])
    if coords then
        f:Link(("[%.0f, %.0f]"):format(coords.x * 100, coords.y * 100),
            function() ns.SetWaypoint(npc[3], coords.m, coords.x, coords.y) end,
            L("Clic: poner un marcador en el mapa del juego"), "GameFontHighlightSmall", { 0.3, 1, 0.3 })
    end
    f:End(0)
    if npc[4] then c:Small(GREY .. L(npc[4]) .. "|r", x + 16, 4) end
    return true
end

function P.NPCList(c, list, x)
    local shown, hidden = 0, 0
    for _, n in ipairs(list or {}) do
        if P.NPC(c, n, x) then shown = shown + 1 else hidden = hidden + 1 end
    end
    if hidden > 0 and shown == 0 then
        c:Small(GREY .. L("(Solo hay PNJ de la otra facción. Puedes mostrarlos en Opciones.)|r"), (x or 0) + 6)
    end
end

-- Materiales con recuento de tus bolsas y banco. Devuelve true si los tienes todos.
-- left/n: si solo te quedan 'left' de 'n' fabricaciones, las cantidades se reducen.
-- plain: solo la lista (tramo ya completado), sin recuento.
function P.Mats(c, s, x, prefix, left, n, plain)
    local mats = ns.ScaleMats(s, left, n)
    if #mats == 0 then return true end
    local f = c:BeginFlow(x or 0, 19)
    if prefix then f:Text(prefix) end
    local all = true
    for _, m in ipairs(mats) do
        local id, need, total = m[1], m[2], m[3]
        f:Icon(16, "item", id, ns.GetItemIcon(id), ns.GetItemName(id, "..."))
        if plain then
            f:Text(("%s%dx %s|r"):format(GREY, total, ns.GetItemName(id, "...")))
        else
            local have = ns.GetItemCount(id)
            if have < need then all = false end
            local col = (have >= need and GREEN) or (have > 0 and ORANGE) or WHITE
            local extra = (need < total) and (GREY .. (L(" (de %d)")):format(total) .. "|r") or ""
            f:Text(("%s%d/%d|r%s %s"):format(col, have, need, extra, ns.GetItemName(id, "...")))
        end
    end
    f:End(2)
    return all
end

function P.KnownIcon(spell)
    local k = ns.IsRecipeKnown(spell)
    return (k == true and W.READY) or (k == false and W.NOT_READY) or W.WAITING
end

function P.KnownText(spell, needsRecipe)
    local k = ns.IsRecipeKnown(spell)
    if k == true then return W.READY .. " " .. GREEN .. L("Receta conocida|r") end
    if k == false then
        return W.NOT_READY .. " " .. RED .. L("No la conoces|r ") .. GREY .. (needsRecipe and L("(necesitas la receta)") or L("(apréndela en el instructor)")) .. "|r"
    end
    return W.WAITING .. " " .. GREY .. L("Abre la ventana de la profesión para saber si la conoces|r")
end

local function ItemLine(c, x, id, label)
    local have = ns.GetItemCount(id)
    local f = c:BeginFlow(x, 20)
    if label then f:Text(label) end
    f:Icon(18, "item", id, ns.GetItemIcon(id), ns.GetItemName(id))
    f:Text(WHITE .. ns.GetItemName(id, "...") .. "|r  " .. (have > 0 and (GREEN .. L("Tienes ") .. have .. "|r") or (GREY .. L("No lo tienes|r"))))
    f:End(2)
end

function P.CreateMacro(m)
    if InCombatLockdown and InCombatLockdown() then ns.Print(L("No se pueden crear macros en combate.")); return end
    if not CreateMacro then ns.Print(L("Tu cliente no permite crear macros desde addons. Escribe /macro y pega:")); print(m.body); return end
    local idx = GetMacroIndexByName and GetMacroIndexByName(m.name) or 0
    if not idx or idx == 0 then
        local ok, res = pcall(CreateMacro, m.name, m.icon, m.body, nil)
        if not ok or not res then ok, res = pcall(CreateMacro, m.name, m.icon, m.body, true) end
        idx = ok and res or 0
    end
    if idx and idx > 0 then
        ns.Print(L("Macro «") .. m.name .. L("» lista. Te la dejo en el cursor: suéltala en tu barra de acción."))
        if PickupMacro then PickupMacro(idx) end
    else
        ns.Print(L("No se pudo crear (¿no quedan huecos de macro?). Escribe /macro y pega estas líneas:"))
        print(m.body)
    end
end

------------------------------------------------------------------------
-- Pasos
------------------------------------------------------------------------
function P.Step(c, step, ctx, x, label, depth, parentR)
    x = x or 0
    local from, to = ns.ParseRange(step.r)
    local skill = ctx.skill
    local accent
    if step == ctx.current then accent = "current"
    elseif not depth and to and skill and skill >= to then accent = "done" end
    -- Lo que te queda de este tramo según tu habilidad
    local left, total, frac = ns.StepRemaining(step, skill, parentR)
    local partial = left and total and left > 0 and left < total

    local startY = c.y
    if step == ctx.current then ctx.currentY = startY end
    c:Space(6)
    local top = c.y
    local tx = x + 48
    local iconPath = (step.spell and ns.GetSpellIcon(step.spell, step.icon)) or (step.icon and (ns.ICON_PATH .. step.icon)) or (ctx.prof and (ns.ICON_PATH .. ctx.prof.icon))
    c:IconButton(x + 9, top, 32, step.spell and "spell" or nil, step.spell, iconPath,
        step.spell and ns.GetSpellName(step.spell, step.name) or (ctx.prof and ns.ProfName(ctx.prof)))

    local t = label or ""
    if step.r and (not depth or step.r ~= parentR) then t = t .. GOLD .. "[" .. step.r .. "]|r  " end
    if step.pick and not depth then t = t .. GOLD .. L("Opción 1:|r ") end
    if step.spell then
        local count = ""
        if partial then count = left .. "x "
        elseif step.n then count = step.n .. "x " end
        t = t .. WHITE .. count .. ns.GetSpellName(step.spell, step.name) .. "|r"
        if partial then t = t .. GREY .. (L("  (te quedan %d de %d)")):format(left, total) .. "|r" end
    elseif not step.text then
        t = t .. WHITE .. (step.name or "") .. "|r"
    end
    if step == ctx.current then t = t .. "   " .. GOLD .. L("<< AHORA|r") end
    c:Text(t, { x = tx, font = "GameFontNormal", gap = 3 })
    if step.text then c:Text(L(step.text), { x = tx, gap = 3 }) end

    -- Estado: receta conocida y progreso del tramo
    local status = {}
    if step.spell then status[#status + 1] = P.KnownText(step.spell, step.recipe ~= nil) end
    if from and to and skill and (not depth or step.r ~= parentR) then
        if skill >= to then status[#status + 1] = GREEN .. L("Tramo completado|r")
        elseif skill >= from then
            if partial then
                status[#status + 1] = GOLD .. (L("En curso: %d/%d (faltan %d puntos, unas %d fabricaciones)")):format(skill, to, to - skill, left) .. "|r"
            else
                status[#status + 1] = GOLD .. (L("En curso: %d/%d (faltan %d)")):format(skill, to, to - skill) .. "|r"
            end
        else status[#status + 1] = GREY .. (L("Empieza en %d")):format(from) .. "|r" end
    end
    if #status > 0 then c:Small(table.concat(status, "    "), tx, 3) end

    if left == 0 then
        P.Mats(c, step.mats, tx, GREY .. L("Materiales:|r "), nil, nil, true)
    elseif partial then
        P.Mats(c, step.mats, tx, GOLD .. L("Te falta:|r "), left, total)
    else
        P.Mats(c, step.mats, tx)
    end
    if step.note then c:Small(GREY .. L(step.note) .. "|r", tx, 3) end
    if step.recipe then ItemLine(c, tx, step.recipe, GOLD .. L("Receta:|r")) end
    if step.quest then
        local done = ns.IsQuestDone(step.quest)
        c:Small((done and (W.READY .. GREEN .. L(" Misión de la receta completada|r")) or (W.WAITING .. GREY .. L(" Misión de la receta pendiente|r"))), tx, 3)
    end
    if step.vendors then
        c:Small(GOLD .. L("Dónde conseguirla:|r"), tx, 2)
        P.NPCList(c, step.vendors, tx - 4)
    end
    if step.zones then
        local f = c:BeginFlow(tx, 17)
        f:Text(GOLD .. L("Zonas:|r"))
        for _, z in ipairs(step.zones) do
            f:Link(ns.ZoneName(z), function() ns.Map.ShowZone(z) end, L("Clic: ver la zona en el mapa"), "GameFontHighlightSmall", { 0.6, 0.85, 1 })
        end
        f:End(3)
    end
    if c.y > top - 36 then c.y = top - 36 end
    c:Space(2)

    local r = step.r or parentR
    for i, a in ipairs(step.alt or {}) do
        P.Step(c, a, ctx, x + 18, step.pick and (GOLD .. L("Opción ") .. (i + 1) .. ":|r ") or (ORANGE .. L("Alternativa:|r ")), (depth or 0) + 1, r)
    end
    for _, a in ipairs(step.also or {}) do
        P.Step(c, a, ctx, x + 18, GREEN .. L("Además:|r "), (depth or 0) + 1, r)
    end

    local endY = c.y - 2
    c:CardBackground(x, startY, endY, accent)
    c.y = endY - 6
end

local function RouteButtonWidth(text) return math.max(110, #text * 6 + 30) end

function P.Block(c, block, ri, bi, ctx)
    if block.title then c:SubHeader(L(block.title)) end
    if block.text then c:Small(L(block.text), 0, 6) end
    for _, s in ipairs(block.steps or {}) do P.Step(c, s, ctx, 0) end
    if block.routes then
        local idx, key = ns.RouteIndex(ctx.guideKey, ri, bi, block)
        local f = c:BeginFlow(0, 26)
        f:Text(GOLD .. L("Ruta:|r"), "GameFontNormal")
        for i, route in ipairs(block.routes) do
            local label = (i == idx and "» " or "") .. L(route.title)
            local b = f:Button(RouteButtonWidth(label), label, function()
                ns.db.routes[key] = i
                ns.RefreshCurrent()
            end, i == idx and L("Ruta seleccionada") or L("Cambiar a esta ruta (se recuerda para este personaje)"))
            if i == idx then b:Disable() end
        end
        f:End(6)
        for _, s in ipairs(block.routes[idx].steps) do P.Step(c, s, ctx, 0) end
    end
end

function P.Rank(c, rank, ri, ctx)
    local _, to = ns.ParseRange(rank.range)
    local done = ctx.skill and to and ctx.skill >= to
    c:Header(L(rank.title) .. "  " .. GREY .. "(" .. rank.range .. ")|r" .. (done and ("  " .. W.READY) or ""))
    if done and ns.db.settings.hideDone then
        c:Small(GREY .. L("Rango completado (oculto).|r"), 0, 4)
        c:Separator()
        return
    end
    if rank.untested then c:Text(ORANGE .. L("Sin probar: esta parte aún no se ha podido comprobar en la beta (límite de nivel).|r"), { font = "GameFontHighlightSmall", gap = 4 }) end
    if rank.req then c:Text(GOLD .. L("Requisitos:|r ") .. L(rank.req), { gap = 5 }) end
    if rank.trainers then
        c:SubHeader(L("Dónde aprenderlo"))
        P.NPCList(c, rank.trainers, 0)
    end
    if rank.books or rank.bookItem then
        for _, id in ipairs(rank.books or { rank.bookItem }) do ItemLine(c, 6, id, GOLD .. L("Libro:|r")) end
    end
    if rank.quests then
        for _, q in ipairs(rank.quests) do
            local qd = ns.IsQuestDone(q[1])
            c:Text((qd and W.READY or W.WAITING) .. L(" Misión: ") .. WHITE .. L(q[2]) .. "|r" .. (qd and (GREEN .. L("  completada|r")) or ""), { x = 6, gap = 3 })
        end
    end
    if rank.questItems then
        c:Small(GOLD .. L("Objetos para la misión:|r"), 6, 2)
        P.Mats(c, rank.questItems, 6)
    end
    if rank.questZones then
        local f = c:BeginFlow(6, 20)
        f:Text(GOLD .. L("Dónde pescarlos:|r"))
        for _, qz in ipairs(rank.questZones) do
            f:Icon(16, "item", qz[1], ns.GetItemIcon(qz[1]), ns.GetItemName(qz[1]))
            f:Link(ns.ZoneName(qz[2]), function() ns.Map.ShowZone(qz[2]) end, L("Clic: ver la zona en el mapa"), "GameFontHighlightSmall", { 0.6, 0.85, 1 })
        end
        f:End(4)
    end
    if rank.text then c:Text(L(rank.text), { font = "GameFontHighlightSmall", gap = 8 }) end
    local hasSteps = false
    for _, s in ipairs(rank.steps or {}) do P.Step(c, s, ctx, 0); hasSteps = true end
    for bi, block in ipairs(rank.blocks or {}) do P.Block(c, block, ri, bi, ctx); hasSteps = true end
    if not hasSteps then c:Small(GREY .. L("La guía aún no publica pasos para este tramo.|r"), 0, 6) end
    c:Separator()
end

function P.Extra(c, ex)
    c:SubHeader(L(ex.title))
    if ex.text then c:Text(L(ex.text), { font = "GameFontHighlightSmall", gap = 5 }) end
    if ex.item then ItemLine(c, 6, ex.item) end
    if ex.items then P.Mats(c, ex.items, 6) end
    if ex.spell then
        local f = c:BeginFlow(6, 20)
        f:Icon(18, "spell", ex.spell, nil, ns.GetSpellName(ex.spell))
        f:Text(WHITE .. (ns.GetSpellName(ex.spell, "") or "") .. "|r  " .. P.KnownText(ex.spell))
        f:End(2)
    end
    if ex.macro then
        c:Text(GREY .. ex.macro.body:gsub("\n", "   ·   ") .. "|r", { font = "GameFontHighlightSmall", x = 6, gap = 4 })
        c:Button(6, c.y, 160, L("Crear la macro"), function() P.CreateMacro(ex.macro) end, L("Crea la macro y te la deja en el cursor para ponerla en tu barra."))
        c.y = c.y - 28
    end
    if ex.npcs then P.NPCList(c, ex.npcs, 0) end
    c:Space(6)
end

------------------------------------------------------------------------
-- Pestañas de profesión
------------------------------------------------------------------------
function P.GuideTab(c, ctx)
    local g = ctx.guide
    c:Text(L(g.intro), { gap = 6 })
    if g.apprenticeNote then c:Small(GREY .. L(g.apprenticeNote) .. "|r", 0, 6) end
    local cap = ns.CapWarning(ctx.skill, ctx.max)
    if cap then c:Text(ORANGE .. cap .. "|r", { gap = 6 }) end
    local y = c.y
    c:Check(0, y + 2, ns.db.settings.hideDone, function(_, v) ns.db.settings.hideDone = v; ns.RefreshCurrent() end)
    c:Text(L("Ocultar rangos completados"), { x = 24, y = y - 2, noAdvance = true, width = 200 })
    c:Button(240, y, 150, L("Ir al paso actual"), function() ns.ScrollToCurrent() end, L("Baja hasta el paso que te toca según tu habilidad."))
    c.y = y - 28
    c:Separator()
    for _, ex in ipairs(g.extras or {}) do P.Extra(c, ex) end
    if g.extras then c:Separator() end
    for ri, rank in ipairs(g.ranks or {}) do P.Rank(c, rank, ri, ctx) end
    c:Small(GREY .. L("Fuente: ") .. L("wow-professions.com (guías de la beta de WoW Forever). Materiales y requisitos pueden cambiar en el lanzamiento.|r"))
end

local function RaceRowVisible(row, mine)
    if mine or ns.db.settings.showOtherFaction then return true end
    local tokens = RACE_TOKENS[row.race]
    local fac = tokens and RACE_FACTION[tokens[1]]
    return not fac or fac == ns.PlayerFaction() or not ns.PlayerFaction()
end

function P.TrainersTab(c, ctx)
    local g = ctx.guide
    c:Text(L("Haz clic en el nombre de un PNJ para verlo en el mapa de su zona, o en las coordenadas [x, y] para poner un marcador en el mapa del juego (y en TomTom si lo tienes)."),
        { font = "GameFontHighlightSmall", gap = 8 })
    if g.capitals then
        c:Header(L("Aprendiz: capitales"))
        if g.apprenticeNote then c:Small(GREY .. L(g.apprenticeNote) .. "|r", 0, 5) end
        P.NPCList(c, g.capitals, 0)
        c:Space(6)
    end
    if g.starting then
        c:Header(L("Zonas de inicio (el más cercano)"))
        local _, race = UnitRace("player")
        for _, row in ipairs(g.starting) do
            local mine = false
            for _, tk in ipairs(RACE_TOKENS[row.race] or {}) do if race and tk:lower() == race:lower() then mine = true end end
            if RaceRowVisible(row, mine) then
                c:Text((mine and (GREEN .. ">> |r") or "") .. GOLD .. L(row.race) .. "|r  " .. GREY .. "(" .. ns.ZoneName(row.zone) .. ")|r" .. (mine and (GREEN .. L("  tu raza|r")) or ""), { gap = 2 })
                for _, n in ipairs(row.npcs) do P.NPC(c, n, 10, true) end
                c:Space(3)
            end
        end
    end
    for _, rank in ipairs(g.ranks or {}) do
        if rank.trainers then
            c:Header(L(rank.title) .. "  " .. GREY .. "(" .. rank.range .. ")|r")
            if rank.req then c:Small(GOLD .. L("Requisitos:|r ") .. L(rank.req), 0, 4) end
            P.NPCList(c, rank.trainers, 0)
            c:Space(6)
        end
    end
    -- Vendedores de recetas
    local first = true
    local function addVendors(step)
        if step.vendors then
            if first then c:Separator(); c:Header(L("Vendedores de recetas y materiales")); first = false end
            local f = c:BeginFlow(0, 20)
            if step.spell then f:Icon(16, "spell", step.spell, ns.ICON_PATH .. (step.icon or "INV_Misc_QuestionMark"), step.name) end
            f:Text(WHITE .. (step.spell and ns.GetSpellName(step.spell, step.name) or step.name or "") .. "|r  " .. GREY .. (step.r or "") .. "|r", "GameFontHighlight")
            f:End(1)
            P.NPCList(c, step.vendors, 8)
        end
        for _, a in ipairs(step.alt or {}) do addVendors(a) end
        for _, a in ipairs(step.also or {}) do addVendors(a) end
    end
    for _, rank in ipairs(g.ranks or {}) do
        ns.ForEachStepList(rank, function(steps) for _, s in ipairs(steps) do addVendors(s) end end)
    end
    for _, ex in ipairs(g.extras or {}) do
        if ex.npcs then
            c:Separator(); c:Header(L(ex.title))
            P.NPCList(c, ex.npcs, 0)
        end
    end
end

-- Lo que aún te falta según tu habilidad (calculado a partir de los pasos)
function P.RemainingList(c, ctx)
    local list, steps = ns.RemainingMaterials(ctx.guideKey, ctx.skill)
    if #list == 0 then
        local _, any = ns.RemainingMaterials(ctx.guideKey, nil)
        if ctx.skill and any > 0 then
            c:Header(L("Lo que aún te falta"))
            c:Small(GREEN .. L("No te faltan materiales para los pasos que quedan.|r"), 0, 8)
        end
        return
    end
    c:Header(L("Lo que aún te falta"))
    if ctx.skill then
        c:Small((L("Calculado desde tu habilidad actual (%d), con las rutas que tienes elegidas y la opción principal de cada tramo. Si ya estás dentro de un tramo, solo cuenta la parte que te queda. Los productos intermedios que fabricas en la guía (rollos, cuero, barras...) ya están descontados.")):format(ctx.skill), 0, 6)
    else
        c:Small(L("No se pudo leer tu habilidad: se muestra todo lo que pide la guía desde el principio, con las rutas que tienes elegidas y la opción principal de cada tramo."), 0, 6)
    end
    local okCount = 0
    local f
    for i, m in ipairs(list) do
        local id, need = m[1], m[2]
        local have = ns.GetItemCount(id)
        if have >= need then okCount = okCount + 1 end
        local col = (have >= need and GREEN) or (have > 0 and ORANGE) or WHITE
        f = c:BeginFlow(24, 19)
        f:Icon(16, "item", id, ns.GetItemIcon(id), ns.GetItemName(id, "..."))
        f:Text(("%s%d/%d|r %s"):format(col, have, need, ns.GetItemName(id, "...")))
        f:End(1)
    end
    c:Small((L("%sTienes suficiente de %d de %d materiales.|r")):format(okCount == #list and GREEN or GREY, okCount, #list), 0, 10)
end

function P.ShoppingTab(c, ctx)
    local g = ctx.guide
    if not g.shopping then
        P.RemainingList(c, ctx)
        c:Text(L("La web no publica una lista de compra para esta guía."), { gap = 6 })
        if ctx.prof.key == "cooking" then
            c:Small(L("En Cocina cada tramo ofrece varias recetas: haz la que tengas ingredientes. Mira los materiales (con lo que llevas encima) en la pestaña «Subir»."))
        elseif ctx.prof.key == "fishing" then
            c:Small(L("Para pescar solo necesitas una caña y algunos cebos: los tienes en la pestaña «Subir»."))
        end
        return
    end
    P.RemainingList(c, ctx)
    c:Header(L("Listas de la guía (desde 1)"))
    c:Small(L("Cantidades estimadas: cuando una receta se vuelve amarilla no siempre da punto. Una alternativa sustituye la fila entera: compra la opción más barata. ")
        .. L("Los números cuentan lo que tienes en bolsas y banco (verde = suficiente)."), 0, 8)
    for _, sec in ipairs(g.shopping) do
        c:Header(L("Lista ") .. sec.title)
        if sec.note then c:Small(GREY .. L(sec.note) .. "|r", 0, 6) end
        local okRows = 0
        for _, row in ipairs(sec.rows) do
            local start = c.y
            local ok = P.Mats(c, row[1], 24)
            local okAlt = row.alt and P.Mats(c, row.alt, 24, ORANGE .. L("o bien:|r "))
            if row.vendor then c:Small(GREY .. L("Se compra a un vendedor.|r"), 24, 2) end
            if row.note then c:Small(GREY .. L(row.note) .. "|r", 24, 2) end
            local fine = ok or okAlt
            if fine then okRows = okRows + 1 end
            c:Text(fine and W.READY or W.WAITING, { x = 2, y = start - 1, noAdvance = true, width = 20 })
            c:Space(3)
        end
        c:Small((L("%sTienes %d de %d filas completas.|r")):format(okRows == #sec.rows and GREEN or GREY, okRows, #sec.rows), 0, 8)
    end
    c:Small(GREY .. L("Truco: pasa el ratón por un material en tus bolsas para ver en qué guías se usa.|r"))
end

function P.RecipesTab(c, ctx)
    local g = ctx.guide
    local spells = ns.GuideSpells(ctx.guideKey)
    local known = 0
    for _, e in ipairs(spells) do if ns.IsRecipeKnown(e.spell) then known = known + 1 end end
    c:Text((L("Conoces %s%d|r de las %d recetas que usa la guía.")):format(GREEN, known, #spells), { font = "GameFontNormal", gap = 4 })
    if not ns.db.scanned[ctx.prof.key] then
        c:Small(ORANGE .. L("Abre una vez tu ventana de ") .. ns.ProfName(ctx.prof) .. L(" para que el addon lea qué recetas conoces (se guarda por personaje).|r"), 0, 6)
    else
        c:Small(GREY .. L("Se actualiza cada vez que abres la ventana de la profesión.|r"), 0, 6)
    end
    c:Small(W.READY .. L(" conocida    ") .. W.NOT_READY .. L(" no la conoces    ") .. W.WAITING .. L(" sin datos"), 0, 8)
    local lastRank
    for _, e in ipairs(spells) do
        if e.rank ~= lastRank then c:SubHeader(L(e.rank.title) .. "  " .. GREY .. "(" .. e.rank.range .. ")|r"); lastRank = e.rank end
        local f = c:BeginFlow(8, 21)
        f:Icon(18, "spell", e.spell, ns.ICON_PATH .. e.icon, e.name)
        f:Text(P.KnownIcon(e.spell) .. " " .. WHITE .. ns.GetSpellName(e.spell, e.name) .. "|r", "GameFontHighlight")
        if e.step.r then f:Text(GREY .. "[" .. e.step.r .. "]|r") end
        if e.step.recipe then
            f:Icon(16, "item", e.step.recipe, ns.GetItemIcon(e.step.recipe), ns.GetItemName(e.step.recipe))
            f:Text(GREY .. L("receta aparte|r"))
        end
        f:End(1)
    end
    for _, list in ipairs(g.lists or {}) do
        c:Separator()
        c:Header(L(list.title))
        if list.text then c:Small(L(list.text), 0, 6) end
        if list.npcs then P.NPCList(c, list.npcs, 0) end
        for _, row in ipairs(list.rows) do
            local f = c:BeginFlow(8, 21)
            f:Icon(18, "spell", row[1], ns.ICON_PATH .. row[3], row[2])
            f:Text(P.KnownIcon(row[1]) .. " " .. WHITE .. ns.GetSpellName(row[1], row[2]) .. "|r", "GameFontHighlight")
            if row[4] then f:Text(GREY .. L(row[4]) .. "|r") end
            f:End(1)
        end
    end
    if ns.merchant and ns.merchant.recipeNotes[ctx.prof.key] then
        c:Separator()
        c:Header(L("Recetas de Favor del mercader"))
        P.MerchantRecipes(c, ctx.prof.key)
        c:Link(0, c.y, L("Cómo conseguir Favor del mercader"), function() ns.ShowPage("merchant") end, nil, "GameFontHighlightSmall", { 0.6, 0.85, 1 })
        c.y = c.y - 20
    end
end

local REP_TEXT = { F = "Amistoso", H = "Honorable" }

-- Tabla de recetas de Favor del mercader de una profesión
function P.MerchantRecipes(c, profKey)
    local m = ns.merchant
    local note = m.recipeNotes[profKey]
    if note then c:Small(GREY .. L(note) .. "|r", 0, 5) end
    local rows = m.recipes[profKey]
    if not rows then return end
    local favor = ns.GetCurrency(m.currency)
    local skill = ns.GetProfessionSkill(profKey)
    local level = UnitLevel and UnitLevel("player") or nil
    local known = 0
    for _, r in ipairs(rows) do if ns.IsRecipeKnown(r[1]) then known = known + 1 end end
    c:Small((L("Conoces %s%d|r de %d.")):format(GREEN, known, #rows) .. "   " .. GREY .. L("Nivel · habilidad · coste · reputación") .. "|r", 0, 6)
    for _, r in ipairs(rows) do
        local f = c:BeginFlow(8, 21)
        f:Icon(18, "spell", r[1], ns.GetSpellIcon(r[1], ns.profByKey[profKey].icon), r[2])
        f:Text(P.KnownIcon(r[1]) .. " " .. WHITE .. ns.GetSpellName(r[1], r[2]) .. "|r", "GameFontHighlight")
        local parts = {}
        if r[3] then parts[#parts + 1] = ((level and level < r[3]) and RED or GREY) .. L("nv. ") .. r[3] .. "|r" end
        parts[#parts + 1] = ((skill and skill < r[4]) and RED or GREY) .. r[4] .. "|r"
        parts[#parts + 1] = ((favor and favor < r[5]) and ORANGE or GREEN) .. r[5] .. " " .. L("favor") .. "|r"
        if r[6] then parts[#parts + 1] = ORANGE .. L(REP_TEXT[r[6]]) .. "|r" end
        f:Text(table.concat(parts, GREY .. " · |r"))
        f:End(0)
        if r[7] then c:Small(GREY .. L(r[7]) .. "|r", 34, 3) end
    end
end

local function CampCard(c, item, name, icon, lines, need, skill, profName, extra)
    local startY = c.y
    c:Space(6)
    local top = c.y
    c:IconButton(9, top, 36, "item", item, ns.GetItemIcon(item, icon), name)
    c:Text(GOLD .. ns.GetItemName(item, name) .. "|r", { x = 54, font = "GameFontNormal", gap = 3 })
    for _, l in ipairs(lines) do c:Small(l, 54, 3) end
    extra = extra or {}
    if extra.spell then c:Small(P.KnownText(extra.spell, extra.bp ~= nil), 54, 3) end
    if extra.mats then P.Mats(c, extra.mats, 54, GOLD .. L("Materiales:|r")) end
    if extra.bp then
        ItemLine(c, 54, extra.bp, GOLD .. L("Plano:|r"))
        if extra.drop then
            c:Small((L("Lo suelta %s en %s.")):format(WHITE .. extra.drop[1] .. "|r", WHITE .. ns.DungeonName(extra.drop[2]) .. "|r"), 54, 3)
        else
            c:Small(GREY .. L("Aún no se sabe dónde cae este plano.") .. "|r", 54, 3)
        end
    end
    local have = ns.GetItemCount(item)
    local status
    local accent
    if not skill then status = GREY .. L("Requiere ") .. profName .. " " .. need .. ".|r"
    elseif skill >= need then status = W.READY .. " " .. GREEN .. L("Tienes la habilidad necesaria (") .. need .. ").|r"; accent = "done"
    else status = W.NOT_READY .. " " .. RED .. L("Te faltan ") .. (need - skill) .. L(" puntos (necesitas ") .. need .. ").|r"; accent = "warn" end
    if have > 0 then status = status .. "   " .. GREEN .. L("Llevas ") .. have .. L(" en las bolsas.|r") end
    c:Small(status, 54, 3)
    if c.y > top - 40 then c.y = top - 40 end
    local endY = c.y - 4
    c:CardBackground(0, startY, endY, accent)
    c.y = endY - 8
end

function P.CampfireCards(c)
    local skill = ns.GetProfessionSkill("cooking")
    for _, fire in ipairs(ns.campfires) do
        CampCard(c, fire.item, fire.name, ns.CAMPFIRE_ICON, {
            (L("Capacidad: %s%d objetos de campamento|r")):format(WHITE, fire.slots),
            (L("Aprender la receta: Cocina %d  -  %s")):format(fire.learn, L(fire.source)),
            (L("Usar el kit: Cocina %d")):format(fire.use),
        }, fire.use, skill, L("Cocina"), { spell = fire.spell, mats = fire.mats, bp = fire.bp, drop = fire.drop })
    end
end

function P.CampTab(c, ctx)
    local prof = ctx.prof
    c:Small(GREY .. L("Objetos de campamento: se colocan junto a una fogata y dan su efecto a quien se siente o fabrique allí. Cada nivel sustituye al anterior y conserva todo lo que este daba.|r"), 0, 8)
    for t = 1, 3 do
        local tier = prof.tiers[t]
        if tier then
            local effect = L(tier.effect) .. (tier.copies and (GREY .. L(" (versión débil de ") .. L(tier.copies) .. ")|r") or "")
            CampCard(c, tier.item, tier.name, tier.icon, {
                GOLD .. L("Nivel ") .. t .. "|r - " .. WHITE .. effect .. "|r",
                GREY .. L("Receta: ") .. L(ns.TIER_SOURCE[t]) .. "|r" .. (tier.station and ("  " .. ORANGE .. L("Estación de fabricación") .. "|r") or ""),
            }, tier.skill, ctx.skill, ns.ProfName(prof), { spell = tier.spell, mats = tier.mats, bp = tier.bp, drop = tier.drop })
        elseif prof.noTier1 and t == 1 then
            c:Text(GOLD .. L("Nivel 1:|r ") .. L(prof.noTier1), { gap = 8 })
        end
    end
    if prof.key == "cooking" then
        c:Separator()
        c:Header(L("Fogatas"))
        P.CampfireCards(c)
    end
end

-- Lista de tareas de Pesca + Cocina
local function Task(c, t)
    local auto = false
    if t.skill then
        local s = ns.GetProfessionSkill(t.skill[1])
        auto = s ~= nil and s >= t.skill[2]
    end
    if t.quest and ns.IsQuestDone(t.quest) then auto = true end
    local checked = ns.db.checks[t[1]] or auto
    local y = c.y
    c:Check(0, y + 3, checked, function(_, v) ns.db.checks[t[1]] = v or nil; ns.RefreshCurrent() end)
    c:Text((checked and GREY or WHITE) .. L(t[2]) .. "|r" .. (auto and (GREEN .. L("  (hecho)|r")) or ""), { x = 26, gap = 3 })
    if t.npc then P.NPC(c, t.npc, 20, true) end
    if t.items then P.Mats(c, t.items, 26) end
    if t.zone then
        c:Link(26, c.y, L("Ver ") .. ns.ZoneName(t.zone) .. L(" en el mapa"), function() ns.Map.ShowZone(t.zone) end, nil, "GameFontHighlightSmall", { 0.6, 0.85, 1 })
        c.y = c.y - 18
    end
    if t.spell then c:Small(P.KnownText(t.spell) .. "  " .. GREY .. ns.GetSpellName(t.spell, "") .. "|r", 26, 3) end
    if t.quest then
        local qd = ns.IsQuestDone(t.quest)
        c:Small(qd and (W.READY .. GREEN .. L(" Misión completada|r")) or (W.WAITING .. GREY .. L(" Misión pendiente|r")), 26, 3)
    end
    if c.y > y - 24 then c.y = y - 24 end
    c:Space(4)
end

function P.ComboTab(c)
    local g = ns.guides.fishcook
    c:Text(L(g.intro), { gap = 6 })
    local fs, cs = ns.GetProfessionSkill("fishing"), ns.GetProfessionSkill("cooking")
    c:Text((L("Tu Pesca: %s%s|r     Tu Cocina: %s%s|r")):format(WHITE, fs or "-", WHITE, cs or "-"), { font = "GameFontNormal", gap = 8 })
    local fac = ns.PlayerFaction()
    local showAll = ns.db.settings.showOtherFaction or not fac
    for _, sec in ipairs(g.sections) do
        c:Header(L(sec.title))
        if sec.note then c:Small(GREY .. L(sec.note) .. "|r", 0, 6) end
        for _, part in ipairs({ "H", "A" }) do
            if sec[part] and (showAll or part == fac) then
                if showAll then c:SubHeader(part == "H" and L("Horda") or L("Alianza")) end
                for _, t in ipairs(sec[part]) do Task(c, t) end
            end
        end
        for _, opt in ipairs(sec.options or {}) do
            if showAll or opt.f == "N" or opt.f == fac then
                c:SubHeader(W.FactionColor(opt.f) .. L(opt.title) .. "|r")
                for _, t in ipairs(opt.tasks) do Task(c, t) end
                c:Space(4)
            end
        end
        for _, t in ipairs(sec.all or {}) do Task(c, t) end
        c:Separator()
    end
end

------------------------------------------------------------------------
-- Páginas generales
------------------------------------------------------------------------
function P.HowTo(c)
    c:Header(L("Cómo funciona el campamento"))
    c:Bullet(L("Alguien coloca una fogata y cada jugador cercano puede añadir un objeto de campamento de su profesión, usándolo desde las bolsas junto al fuego."))
    c:Bullet(L("Siéntate (/sit) o fabrica junto al fuego durante un minuto y recibirás durante una hora lo que aporten esos objetos: bonificaciones, un vendedor, reparaciones o estaciones de fabricación."))
    c:Bullet(L("No necesitas ninguna profesión para beneficiarte: basta con sentarte en la fogata de otro jugador."))
    c:Bullet(L("La fogata es de Cocina (habilidad 1) y se coloca desde las bolsas. Básica: 3 huecos. Oficial: 5. Experta: 10."))
    c:Bullet(L("Cada profesión tiene tres niveles de objeto (habilidad 20, 140 y 300). Cada nivel sustituye al anterior y conserva lo que este daba."))
    c:Bullet(L("Solo un objeto por jugador en cada fogata. Al colocar uno, todos tus objetos de campamento quedan 1 hora en reutilización."))
    c:Bullet(L("Las bonificaciones de nivel 1 son versiones más débiles de bonificaciones de clase y no se acumulan con ellas."))
    c:Separator()
    c:SubHeader(L("Consejo: también sirve jugando en solitario"))
    c:Text(L("Mientras subes de nivel, monta un campamento cada vez que te detengas y bufféate casi gratis. Cualquier profesión llega rápido a 20. ")
        .. L("Fabrica en casa un montón de kits de fogata básica (ocupan un solo hueco) y ya no necesitas llevar pedernal ni leña. ")
        .. L("El objeto de nivel 1 de Pesca da +8% a todas las estadísticas y sirve a cualquier clase."), { gap = 10 })
    c:Separator()
    c:SubHeader(L("Objeto de nivel 1 de cada profesión"))
    for _, prof in ipairs(ns.professions) do
        local t1 = prof.tiers[1]
        if t1 then
            local f = c:BeginFlow(4, 20)
            f:Icon(18, "item", t1.item, ns.GetItemIcon(t1.item, t1.icon), t1.name)
            f:Link(ns.ProfName(prof), function() ns.ShowPage(prof.key, "camp") end, L("Abrir la profesión"), "GameFontNormal")
            f:Text(WHITE .. ns.GetItemName(t1.item, t1.name) .. "|r " .. GREY .. "-|r " .. L(t1.effect) .. (t1.copies and (GREY .. L(" (como ") .. L(t1.copies) .. ")|r") or ""), "GameFontHighlightSmall")
            f:End(3)
        end
    end
    c:Separator()
    P.Blueprints(c)
    c:Separator()
    c:Small(GREY .. L("Datos: ") .. ns.SOURCE_URL .. L(" (beta de WoW Forever).|r"))
end

function P.First(c)
    c:Header(L("Tu primer campamento"))
    c:Text(L("Todo empieza con la misión ") .. WHITE .. L("The Great Outdoors|r, disponible desde nivel 4 en tu zona de inicio. Cada zona tiene su propia versión:"), { gap = 8 })
    local _, race = UnitRace("player")
    for _, q in ipairs(ns.quests) do
        local mine = false
        for _, r in ipairs(q.races) do if race and r:lower() == race:lower() then mine = true end end
        local done = ns.IsQuestDone(q.quest)
        local line = (done and W.READY or W.WAITING) .. " " .. (mine and (GREEN .. ">> |r") or "") .. GOLD .. L(q.raceText) .. "|r  " .. GREY .. ns.ZoneName(q.zone) .. L("|r  -  PNJ: ") .. WHITE .. q.npc .. "|r"
            .. (mine and (GREEN .. L("  (tu raza)|r")) or "") .. (done and (GREEN .. L("  completada|r")) or "")
        c:Text(line, { x = 6, gap = 3 })
        if mine then c:Link(30, c.y, L("Ver ") .. ns.ZoneName(q.zone) .. L(" en el mapa"), function() ns.Map.ShowZone(q.zone) end, nil, "GameFontHighlightSmall", { 0.6, 0.85, 1 }); c.y = c.y - 18 end
    end
    c:Separator()
    c:SubHeader(L("Pasos"))
    c:Text(GOLD .. L("1.|r Completa The Great Outdoors: te guía para montar tu primer campamento."), { x = 6, gap = 5 })
    c:Text(GOLD .. L("2.|r Aprende Cocina en la ciudad más cercana. Con ella recibes la receta del kit de fogata básica."), { x = 6, gap = 5 })
    local f = c:BeginFlow(26, 18)
    f:Link(L("Instructores de Cocina"), function() ns.ShowPage("cooking", "trainers") end, nil, "GameFontHighlightSmall", { 0.6, 0.85, 1 })
    f:End(4)
    c:Text(GOLD .. L("3.|r Haz la misión ") .. WHITE .. L("Camping 101|r de cada una de tus profesiones y entrégala a su instructor. Con habilidad 20 te enseña el objeto de campamento de nivel 1."), { x = 6, gap = 8 })
    c:Separator()
    c:SubHeader(L("Recetas de nivel 2 y 3"))
    c:Text(L("Los niveles 2 (habilidad 140) y 3 (habilidad 300) se aprenden con un ") .. WHITE .. L("plano (Blueprint)|r. Los encontrados hasta ahora caían en mazmorras, así que probablemente todos se consigan allí."))
end

function P.Campfires(c)
    c:Header(L("Fogatas"))
    c:Text(L("Las fogatas son de Cocina y todo campamento empieza por una. Solo se diferencian en cuántos objetos de campamento admiten. El kit básico lo enseña el instructor; los otros dos necesitan un plano."), { gap = 6 })
    local skill, max = ns.GetProfessionSkill("cooking")
    c:Text(skill and (L("Tu habilidad de Cocina: ") .. WHITE .. skill .. "|r / " .. tostring(max or "?")) or (GREY .. L("No conoces Cocina.|r")), { gap = 8 })
    P.CampfireCards(c)
    c:Text(GOLD .. L("Ojo:|r para usar los kits Oficial y Experto hace falta más habilidad (140 y 220) que para aprender la receta (90 y 200). Es lo contrario de lo habitual y podría ser un error de la beta."), { font = "GameFontHighlightSmall", gap = 8 })
    c:Separator()
    P.Extra(c, ns.guides.cooking.extras[1])
end

function P.Forever(c)
    c:Header(L("Novedades de las profesiones en Forever"))
    c:Bullet(L("Todas las profesiones de aprendiz se pueden aprender sin requisito de nivel."))
    c:Bullet(L("Requisitos de rango: Oficial = profesión 50 y nivel 10. Experto = 125, nivel 20 y 50 de plata. Artesano = 200 y nivel 35."))
    c:Bullet(L("Las pociones de sanación ya no son de Alquimia: ahora las fabrica Primeros auxilios."))
    c:Bullet(L("Encantamiento tiene recetas nuevas de nivel bajo con Mota de magia, que abaratan los primeros 70 puntos."))
    c:Bullet(L("El racial de Ingeniería de los gnomos ya no da +15 de habilidad: hace que sus artilugios fallen un 20% menos."))
    c:Bullet(L("Muchos rangos de Herrería, Peletería y Sastrería cambiaron (recetas que se vuelven grises 25-45 puntos antes que en Classic). Encantamiento, Ingeniería, Alquimia, Cocina y Primeros auxilios mantienen casi todo."))
    c:Bullet(L("Varias recetas que antes se compraban en la subasta ahora se ligan al recogerlas: cómpralas con el personaje que sube la profesión."))
    c:Bullet(L("La beta tiene límite de nivel (20, luego 30), por eso las guías marcan rutas «beta» y los tramos altos como «sin probar»."))
    c:Separator()
    c:SubHeader(L("Facciones de profesión: Favor del mercader"))
    c:Text(L("Hay campamentos donde entregas cajas de suministros a cambio de Favor del mercader, y allí se venden recetas que se ligan al recogerlas."), { gap = 4 })
    c:Link(0, c.y, L("Abrir la guía de Favor del mercader"), function() ns.ShowPage("merchant") end, nil, "GameFontNormal", { 0.6, 0.85, 1 })
    c.y = c.y - 22
    c:Separator()
    c:SubHeader(L("Guías por profesión"))
    local f = c:BeginFlow(0, 20)
    for _, prof in ipairs(ns.professions) do
        if ns.guides[prof.key] then
            f:Link(ns.ProfName(prof), function() ns.ShowPage(prof.key, "guide") end, nil, "GameFontNormal")
        end
    end
    f:Link(L("Pesca + Cocina"), function() ns.ShowPage("fishcook") end, nil, "GameFontNormal")
    f:End(6)
    c:Small(GREY .. L("Herboristería, Minería y Desuello no tienen guía de subida de Forever en la web; sus páginas muestran la información de campamento.|r"))
end

-- Dónde caen los planos y qué objetos son estaciones de fabricación
function P.Blueprints(c)
    c:Header(L("Planos y estaciones de fabricación"))
    c:Small(L("Los niveles 2 y 3 se aprenden con un plano. Las estaciones las necesitan algunas recetas: hay que colocarlas en una fogata (cualquiera del campamento puede usarlas). No se han encontrado estaciones en el mundo abierto."), 0, 6)
    for _, prof in ipairs(ns.professions) do
        for t = 2, 3 do
            local tier = prof.tiers[t]
            if tier then
                local fl = c:BeginFlow(4, 20)
                fl:Icon(18, "item", tier.item, ns.GetItemIcon(tier.item, tier.icon), tier.name)
                fl:Link(ns.ProfName(prof) .. " " .. t, function() ns.ShowPage(prof.key, "camp") end, L("Abrir la profesión"), "GameFontNormalSmall")
                fl:Text(WHITE .. ns.GetItemName(tier.item, tier.name) .. "|r" .. (tier.station and (" " .. ORANGE .. L("(estación)") .. "|r") or ""))
                if tier.drop then
                    fl:Text(GREY .. "- " .. tier.drop[1] .. ", " .. ns.DungeonName(tier.drop[2]) .. "|r")
                else
                    fl:Text(GREY .. "- " .. L("origen desconocido") .. "|r")
                end
                local have = tier.bp and ns.GetItemCount(tier.bp) or 0
                if have > 0 then fl:Text(GREEN .. L("(tienes el plano)") .. "|r") end
                fl:End(1)
            end
        end
    end
    for _, fire in ipairs(ns.campfires) do
        if fire.bp then
            local fl = c:BeginFlow(4, 20)
            fl:Icon(18, "item", fire.item, ns.GetItemIcon(fire.item, ns.CAMPFIRE_ICON), fire.name)
            fl:Text(WHITE .. ns.GetItemName(fire.item, fire.name) .. "|r")
            fl:Text(GREY .. "- " .. (fire.drop and (fire.drop[1] .. ", " .. ns.DungeonName(fire.drop[2])) or L("origen desconocido")) .. "|r")
            fl:End(1)
        end
    end
end

-- Guía de Favor del mercader
function P.Merchant(c)
    local m = ns.merchant
    c:Text(L(m.intro), { gap = 6 })
    local favor, cname = ns.GetCurrency(m.currency)
    if favor then
        c:Text((L("Tu Favor del mercader: %s%d|r")):format(WHITE, favor), { font = "GameFontNormal", gap = 8 })
    else
        c:Small(GREY .. L("Tu cliente no muestra esta moneda todavía (aparece al conseguir la primera).") .. "|r", 0, 8)
    end
    c:Separator()

    c:Header(L("Campamentos y vendedores"))
    local fac = ns.PlayerFaction()
    for _, camp in ipairs(m.camps) do
        if ns.db.settings.showOtherFaction or not fac or camp.f == fac then
            c:SubHeader(W.FactionColor(camp.f) .. L(camp.title) .. "|r  " .. GREY .. ns.ZoneName(camp.zone) .. "|r")
            c:Small(L(camp.where), 6, 3)
            for _, n in ipairs(camp.npcs) do P.NPC(c, n, 6, true) end
            c:Space(4)
        end
    end
    c:Small(GREY .. L(m.campNote) .. "|r", 0, 4)
    c:Separator()

    c:Header(L("Cajas desviadas: cómo conseguir favor"))
    for i, st in ipairs(m.crateSteps) do c:Text(GOLD .. i .. ".|r " .. L(st), { x = 6, gap = 4 }) end
    c:Small(GREY .. L(m.crateNote) .. "|r", 0, 4)
    ItemLine(c, 6, m.label.item, GOLD .. L("Etiqueta de envío:|r"))
    c:Small(L(m.label.text), 6, 8)
    c:Small(L("Cada fila es un tipo de caja. Llénala con UNA de las opciones; en verde, las que ya puedes completar con lo que llevas."), 0, 6)
    local level = UnitLevel and UnitLevel("player") or nil
    for ti, tier in ipairs(m.tiers) do
        local lvlCol = (level and level < tier.level) and RED or GREY
        c:SubHeader(L(tier.title) .. "  " .. lvlCol .. "(" .. L("nivel") .. " " .. tier.level .. ")|r")
        for _, crate in ipairs(m.crates) do
            local opts = crate.bundles[ti]
            if opts then
                local fl = c:BeginFlow(8, 20)
                local id = crate.items[ti]
                if id then
                    local have = ns.GetItemCount(id)
                    fl:Icon(18, "item", id, ns.GetItemIcon(id), crate.name, nil, have > 0 and ((L("Tienes %d")):format(have)) or nil)
                end
                local fav = crate.favor[ti]
                fl:Text(WHITE .. L(crate.name) .. "|r " .. (fav and (GREEN .. "+" .. fav .. "|r") or (GREY .. "?|r")), "GameFontHighlight")
                for oi, o in ipairs(opts) do
                    local mats = ns.ParseMats(o)
                    local ok = true
                    for _, mm in ipairs(mats) do if ns.GetItemCount(mm[1]) < mm[2] then ok = false end end
                    for _, mm in ipairs(mats) do
                        fl:Icon(16, "item", mm[1], ns.GetItemIcon(mm[1]), ns.GetItemName(mm[1]))
                        fl:Text((ok and GREEN or GREY) .. mm[2] .. " " .. ns.GetItemName(mm[1], "...") .. "|r")
                    end
                    if oi < #opts then fl:Text(GREY .. L("o") .. "|r") end
                end
                fl:End(2)
            end
        end
        if ti == 4 then c:Small(GREY .. L(m.artisanNote) .. "|r", 8, 4) end
        c:Space(4)
    end
    c:Separator()

    c:Header(L("Reputación: encargos de artesano"))
    c:Text(L(m.writs.text), { font = "GameFontHighlightSmall", gap = 4 })
    local rk = { "Oficial", "Experto", "Artesano" }
    local fl = c:BeginFlow(6, 20)
    for i, id in ipairs(m.writs.items) do
        fl:Icon(18, "item", id, ns.GetItemIcon(id), L(rk[i]))
        fl:Text(WHITE .. L(rk[i]) .. "|r " .. GREEN .. "+" .. m.writs.rep[i] .. " " .. L("rep.") .. "|r")
    end
    fl:End(4)
    c:Small(ORANGE .. L(m.writs.beta) .. "|r", 0, 8)
    c:SubHeader(L("Truco del recibo (desde Amistoso)"))
    c:Small(L(m.scribe.text), 0, 4)
    for i, st in ipairs(m.scribe.steps) do c:Text(GOLD .. i .. ".|r " .. L(st), { x = 6, font = "GameFontHighlightSmall", gap = 3 }) end
    local fl2 = c:BeginFlow(6, 20)
    for _, id in ipairs({ m.scribe.receipt, m.scribe.quill, m.scribe.container }) do
        fl2:Icon(18, "item", id, ns.GetItemIcon(id), ns.GetItemName(id))
        fl2:Text(GREY .. ns.GetItemName(id, "...") .. "|r")
    end
    fl2:End(6)
    c:SubHeader(L("Consejos"))
    for _, t in ipairs(m.tips) do c:Bullet(L(t)) end
    c:Separator()

    c:Header(L("Recetas por profesión"))
    c:Small(L("Rojo: aún no tienes el nivel o la habilidad. Naranja: te falta favor o la reputación indicada (el addon no puede leer tu reputación con el campamento)."), 0, 6)
    for _, pk in ipairs({ "alchemy", "blacksmithing", "cooking", "enchanting", "engineering", "leatherworking", "tailoring" }) do
        local prof = ns.profByKey[pk]
        c:SubHeader(W.Icon(ns.ICON_PATH .. prof.icon, 16) .. " " .. ns.ProfName(prof))
        P.MerchantRecipes(c, pk)
        c:Space(4)
    end
    c:Small(GREY .. L("Datos: ") .. "wow-professions.com/forever/merchants-favor-durotar-supply-azeroth-commerce" .. L(" (beta de WoW Forever).|r"))
end

------------------------------------------------------------------------
-- Misceláneos: mini guías (saco de dormir, antorcha...)
------------------------------------------------------------------------
local function MiscOwned(g)
    if ns.GetItemCount(g.item) > 0 then return true end
    return ns.IsQuestDone(g.doneQuest) == true
end

function P.Misc(c)
    local m = ns.misc
    c:Text(L("Objetos útiles que no dependen de ninguna profesión. Haz clic en el nombre de un punto para verlo marcado en el mapa, o en sus coordenadas para poner un marcador."), { gap = 4 })
    c:Small(GREY .. L("Fuentes: ") .. m.sources .. L(". Las coordenadas son las publicadas por esas guías.") .. "|r", 0, 8)
    local fac = ns.PlayerFaction()
    for gi, g in ipairs(m.guides) do
        if gi > 1 then c:Separator() end
        local owned = MiscOwned(g)
        local f = c:BeginFlow(0, 26)
        f:Icon(24, "item", g.item, ns.GetItemIcon(g.item), L(g.title))
        f:Text(GOLD .. L(g.title) .. "|r", "GameFontNormalLarge")
        f:Text(owned and (W.READY .. GREEN .. L(" Ya lo tienes|r")) or (GREY .. L("Aún no lo tienes|r")))
        f:End(4)
        c:Text(L(g.intro), { gap = 6 })
        for _, t in ipairs(g.facts or {}) do c:Bullet(L(t)) end
        if g.bonusItem then ItemLine(c, 6, g.bonusItem, GOLD .. L("También recibes:|r")) end
        if g.macro then
            c:Small(GOLD .. L("Macro para seleccionar el cadáver aunque no lo veas:|r ") .. WHITE .. g.macro .. "|r", 6, 4)
        end
        c:Space(4)

        if g.steps then
            c:SubHeader(L("Pasos") .. (fac and "" or (GREY .. L("  (se muestran las dos facciones)|r"))))
            local n, nextShown = 0, owned
            for _, st in ipairs(g.steps) do
                if not st.f or not fac or st.f == fac then
                    n = n + 1
                    local done = owned or (st.quest and ns.IsQuestDone(st.quest) == true) or false
                    if st.final then done = owned end
                    local isNext = not done and not nextShown
                    if isNext then nextShown = true end
                    local startY = c.y
                    c:Space(6)
                    local mark = done and W.READY or W.WAITING
                    local head = mark .. " " .. GOLD .. n .. ".|r "
                    if st.f and not fac then head = head .. W.FactionColor(st.f) .. (st.f == "H" and L("Horda") or L("Alianza")) .. ":|r " end
                    c:Text(head .. WHITE .. L(st.text) .. "|r" .. (isNext and ("   " .. GOLD .. L("<< AHORA|r")) or ""), { x = 10, gap = 3 })
                    if st.travel then c:Small(GREY .. L(st.travel) .. "|r", 28, 3) end
                    P.NPC(c, st.point, 22, true)
                    local endY = c.y - 2
                    c:CardBackground(0, startY, endY, isNext and "current" or (done and "done" or nil))
                    c.y = endY - 6
                end
            end
        end
        if g.points then
            c:SubHeader(L(g.pointsTitle))
            for _, pt in ipairs(g.points) do P.NPC(c, pt, 6, true) end
            local y = c.y - 4
            c:Button(6, y, 220, L("Ver los 9 puntos en el mapa"), function() ns.Map.ShowZone(g.points[1][2]) end)
            c.y = y - 30
        end
    end
end

function P.Options(c)
    local s = ns.db.settings
    c:Header(L("Opciones"))
    local function Opt(key, label, desc, after)
        local y = c.y
        c:Check(0, y + 3, s[key], function(_, v)
            s[key] = v
            if after then after(v) end
            ns.RefreshCurrent()
        end)
        c:Text(WHITE .. label .. "|r", { x = 26, gap = 1 })
        if desc then c:Small(GREY .. desc .. "|r", 26, 6) end
        if c.y > y - 24 then c.y = y - 24 end
    end
    Opt("minimap", L("Botón en el minimapa"), nil, function(v) if ns.minimapButton then ns.minimapButton:SetShown(v) end end)
    Opt("tracker", L("Panel junto a la ventana de profesión"), L("Muestra el paso actual y sus materiales cuando abres una profesión con guía."),
        function() if ns.Tracker then ns.Tracker.Refresh() end end)
    Opt("tooltips", L("Información en los tooltips"), L("Añade a los objetos si son de campamento o materiales de alguna guía."))
    Opt("learnCoords", L("Guardar ubicaciones de PNJ automáticamente"), L("Solo para los PNJ que no tienen coordenadas en el addon: al pasar el ratón, seleccionarlos o hablar con ellos se guarda su posición."))
    Opt("showOtherFaction", L("Mostrar PNJ de la otra facción"))
    Opt("hideDone", L("Ocultar rangos completados en las guías"))
    c:Separator()

    c:Header(L("Idioma"))
    local pref = s.lang or "auto"
    local fl = c:BeginFlow(0, 26)
    for _, o in ipairs({ { "auto", L("Automático") }, { "es", "Español" }, { "en", "English" } }) do
        local b = fl:Button(120, (pref == o[1] and "» " or "") .. o[2], function()
            s.lang = o[1]
            if ReloadUI then ReloadUI() end
        end, L("Cambia el idioma (recarga la interfaz)."))
        if pref == o[1] then b:Disable() end
    end
    fl:End(6)
    c:Separator()

    c:Header(L("Datos guardados"))
    local nKnown, nCoords, nTotal = 0, 0, 0
    for _, v in pairs(ns.db.known) do if v then nKnown = nKnown + 1 end end
    local names = {}
    for name in pairs(ns.npcIndex) do
        nTotal = nTotal + 1
        if ns.GetCoords(name) then nCoords = nCoords + 1 end
        if (ns.acct and ns.acct.coords[name]) or ns.char.coords[name] then names[#names + 1] = name end
    end
    table.sort(names)
    c:Text((L("Recetas leídas como conocidas: %s%d|r     PNJ con coordenadas: %s%d|r de %d")):format(WHITE, nKnown, WHITE, nCoords, nTotal), { gap = 8 })
    local y = c.y
    c:Button(0, y, 170, L("Olvidar recetas leídas"), function() wipe(ns.db.known); wipe(ns.db.scanned); ns.RefreshCurrent() end, L("Se volverán a leer al abrir cada profesión."))
    c:Button(176, y, 190, L("Desmarcar Pesca + Cocina"), function() wipe(ns.db.checks); ns.RefreshCurrent() end)
    c:Button(372, y, 170, L("Olvidar ubicaciones"), function()
        wipe(ns.db.coords); if ns.acct then wipe(ns.acct.coords) end; ns.RefreshCurrent()
    end, L("Borra las ubicaciones que guardaste tú y vuelve a usar las de la web."))
    c.y = y - 32
    if #names > 0 then
        c:SubHeader(L("Ubicaciones guardadas por ti"))
        for _, name in ipairs(names) do P.NPC(c, ns.npcIndex[name].npc, 0, true) end
    else
        c:Small(GREY .. L("No has guardado ninguna ubicación propia: el addon usa las coordenadas de wow-professions.com.|r"))
    end
    c:Separator()
    c:Small(GREY .. L("Comandos: /fcg  ·  /fcg <profesión>  ·  /fcg mapa  ·  /fcg opciones  ·  /fcg tracker  ·  /fcg minimap|r"))
end

-- Asociar texto de raza -> identificadores (a partir de los datos de misiones)
for _, q in ipairs(ns.quests) do RACE_TOKENS[q.raceText] = q.races end
