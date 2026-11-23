local _, ns = ...

-- Crafting > Explore: pick an item and see everything you can make from it, as a node graph.
--   Each box is something the item can become (up to three crafts deep), with what one of the
--   starting item is worth if you craft that far and sell. Box border = skill-up colour.
--   Gold lines and edge: the best route for gold. Orange: the best route for skill points.
--   Crafts that give no skill points and are worth less than selling raw are left out, and the
--   graph shrinks to fit the window.
-- Click a box to open its recipe in the profession window, right-click to explore from it,
-- shift-click to search the AH.

local NODE_W, NODE_H, ROW = 124, 42, 48
local PAD = 8
local GOLD = { 1, 0.82, 0 }
local LEVEL = { 1, 0.5, 0.25 }
local EDGE = { 0.45, 0.45, 0.5 }
local DIM = "|cff777777"

local state = { root = nil, history = {} }

local function nameOf(itemID) return ns.ItemName(itemID) or ("item " .. tostring(itemID)) end

-- names from the root down to node: "Cured Medium Hide > Medium Leather Vest"
local function routeText(node)
    local names = {}
    while node and node.parent do
        table.insert(names, 1, nameOf(node.itemID))
        node = node.parent
    end
    return table.concat(names, " > ")
end

local function plain(copper)
    return (ns.Money(copper):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- open Explore at this item (from any crafting view)
function ns.ExploreItem(itemID)
    if not itemID then return end
    if state.root and state.root ~= itemID then table.insert(state.history, state.root) end
    state.root = itemID
    ns.OpenView("crafting", "explore")
end

ns.RegisterPage("explore", "Explore", function(page)
    local W = ns.PAGE_WIDTH
    local LIST_W = 206
    local GX = LIST_W + 14
    local GW = W - GX
    local COL = (GW - 2 * PAD - NODE_W) / 3 -- column spacing, re-fitted to the tree's depth on each draw

    -- ---------------------------------------------------------------- item list
    local search = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    search:SetSize(LIST_W - 8, 20)
    search:SetPoint("TOPLEFT", 6, -2)
    search:SetAutoFocus(false)
    local placeholder = ns.Label(search, "GameFontDisableSmall", "Search your materials...")
    placeholder:SetPoint("LEFT", 2, 0)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEditFocusGained", function() placeholder:Hide() end)
    search:SetScript("OnEditFocusLost", function(self) placeholder:SetShown((self:GetText() or "") == "") end)
    search:SetScript("OnTextChanged", function() page:RefreshList() end)

    local list = ns.CreateTable(page, {
        { title = "Item", width = 150, icon = function(r) return ns.ItemIcon(r.itemID) end,
          text = function(r)
              local name = r.name or nameOf(r.itemID)
              if r.itemID == state.root then return "|cffffd100" .. name .. "|r" end
              return r.have > 0 and name or (DIM .. name .. "|r")
          end,
          sort = function(r) return (r.have > 0 and "0" or "1") .. (r.name or "") end, defaultAsc = true },
        { title = "Have", width = 40, align = "RIGHT", text = function(r) return r.have > 0 and r.have or "" end,
          sort = function(r) return r.have end },
    }, {
        rows = 21, sortCol = 1, sortDesc = false,
        empty = "No recipes read yet. Open your profession window once.",
        onEnter = function(r, frame)
            ns.ItemTooltip(frame, r.itemID, function(tip)
                tip:AddLine(" ")
                tip:AddDoubleLine("Goes into", r.uses .. (r.uses == 1 and " recipe you know" or " recipes you know"), 1, 1, 1, 1, 1, 1)
                if r.vendor then tip:AddLine("Sold by vendors.", 0.6, 0.6, 0.6) end
                tip:AddLine("Click: see what you can make with it.", 0.6, 0.6, 0.6)
            end)
        end,
        onClick = function(r)
            if r.itemID ~= state.root then
                if state.root then table.insert(state.history, state.root) end
                state.root = r.itemID
            end
            page:Refresh()
        end,
    })
    list:SetPoint("TOPLEFT", 0, -28)
    list:SetWidth(LIST_W)

    -- ---------------------------------------------------------------- header
    local back = ns.Button(page, "< Back", 64, function()
        local prev = table.remove(state.history)
        if prev then state.root = prev page:Refresh() end
    end)
    back:SetPoint("TOPLEFT", GX, 0)
    local title = ns.Label(page, "GameFontNormalLarge", "")
    title:SetPoint("LEFT", back, "RIGHT", 10, 0)
    title:SetWidth(GW - 250)
    title:SetWordWrap(false)
    local skillText = ns.Label(page, "GameFontHighlightSmall", "", "RIGHT")
    skillText:SetPoint("TOPRIGHT", 0, -5)

    -- two cards: best for gold, best for leveling
    local function card(x, accent, heading)
        local f = CreateFrame("Frame", nil, page, "BackdropTemplate")
        f:SetSize((GW - 8) / 2, 50)
        f:SetPoint("TOPLEFT", x, -28)
        ns.Backdrop(f, 0.09, 0.09, 0.11, 0.95)
        local strip = f:CreateTexture(nil, "ARTWORK")
        strip:SetPoint("TOPLEFT", 4, -4)
        strip:SetPoint("BOTTOMLEFT", 4, 4)
        strip:SetWidth(3)
        strip:SetColorTexture(accent[1], accent[2], accent[3], 1)
        f.heading = ns.Label(f, "GameFontDisableSmall", heading)
        f.heading:SetPoint("TOPLEFT", 13, -6)
        f.text = ns.Label(f, "GameFontHighlightSmall", "", "LEFT")
        f.text:SetPoint("TOPLEFT", 13, -19)
        f.text:SetPoint("BOTTOMRIGHT", -8, 4)
        f.text:SetJustifyV("TOP")
        f.text:SetSpacing(2)
        return f
    end
    local goldCard = card(GX, GOLD, "BEST FOR GOLD")
    local levelCard = card(GX + (GW - 8) / 2 + 8, LEVEL, "BEST FOR LEVELING")

    -- ---------------------------------------------------------------- graph area
    local clip = CreateFrame("Frame", nil, page, "BackdropTemplate")
    clip:SetPoint("TOPLEFT", GX, -84)
    clip:SetPoint("BOTTOMRIGHT", 0, 20)
    ns.Backdrop(clip, 0.05, 0.05, 0.06, 0.9)
    clip:SetClipsChildren(true)
    local canvas = CreateFrame("Frame", nil, clip)
    canvas:SetWidth(GW)

    local empty = ns.Label(clip, "GameFontDisable", "", "CENTER")
    empty:SetPoint("BOTTOM", 0, 30)
    empty:SetWidth(GW - 40)

    local legend = ns.Label(page, "GameFontDisableSmall", "", "LEFT")
    legend:SetPoint("BOTTOMLEFT", GX, 4)
    legend:SetWidth(GW)
    legend:SetWordWrap(false)

    -- ---------------------------------------------------------------- pan & zoom
    -- view.zoom is the canvas scale; view.x / view.y is where the canvas's top-left sits inside
    -- the graph area (graph-area units). w / h is the graph's own size (canvas units).
    local view = { zoom = 1, x = 0, y = 0, w = 1, h = 1 }
    local MAX_ZOOM, MAX_FIT, KEEP_VISIBLE = 2, 1.2, 60

    local function clipSize()
        local w, h = clip:GetWidth(), clip:GetHeight()
        if w <= 0 then w = GW end
        if h <= 0 then h = 354 end -- not laid out yet on the very first show
        return w, h
    end

    local function applyView()
        local cw, ch = clipSize()
        local sw, sh = view.w * view.zoom, view.h * view.zoom
        -- never lose the graph entirely
        view.x = math.max(math.min(view.x, cw - KEEP_VISIBLE), KEEP_VISIBLE - sw)
        view.y = math.max(math.min(view.y, ch - KEEP_VISIBLE), KEEP_VISIBLE - sh)
        canvas:SetScale(view.zoom)
        canvas:ClearAllPoints()
        -- a scaled frame's offsets are in its own units
        canvas:SetPoint("TOPLEFT", clip, "TOPLEFT", view.x / view.zoom, -view.y / view.zoom)
    end

    -- the whole graph, centred in the window
    local function fitView()
        local cw, ch = clipSize()
        view.fit = math.min(MAX_FIT, cw / view.w, ch / view.h)
        view.zoom = view.fit
        view.x = (cw - view.w * view.zoom) / 2
        view.y = (ch - view.h * view.zoom) / 2
        applyView()
    end

    local function cursorInClip()
        local x, y = GetCursorPosition()
        local s = clip:GetEffectiveScale()
        return x / s - (clip:GetLeft() or 0), (clip:GetTop() or 0) - y / s
    end

    -- zoom in or out around the cursor
    local function zoomAt(delta)
        local cx, cy = cursorInClip()
        local old = view.zoom
        local minZoom = math.min(view.fit or 1, 1) * 0.5
        local new = math.max(minZoom, math.min(MAX_ZOOM, old * (delta > 0 and 1.15 or 1 / 1.15)))
        if new == old then return end
        local px, py = (cx - view.x) / old, (cy - view.y) / old
        view.zoom = new
        view.x, view.y = cx - px * new, cy - py * new
        applyView()
    end

    local function stopDrag()
        clip.drag = nil
        clip:SetScript("OnUpdate", nil)
    end
    local function startDrag()
        local cx, cy = cursorInClip()
        clip.drag = { cx = cx, cy = cy, x = view.x, y = view.y }
        clip:SetScript("OnUpdate", function(self)
            local d = self.drag
            if not d then return end
            local nx, ny = cursorInClip()
            view.x, view.y = d.x + nx - d.cx, d.y + ny - d.cy
            applyView()
        end)
    end

    clip:EnableMouse(true)
    clip:EnableMouseWheel(true)
    clip:SetScript("OnMouseWheel", function(_, delta) zoomAt(delta) end)
    clip:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then startDrag() end end)
    clip:SetScript("OnMouseUp", stopDrag)
    clip:SetScript("OnHide", stopDrag)

    -- controls float above the graph
    local hud = CreateFrame("Frame", nil, clip)
    hud:SetAllPoints()
    hud:SetFrameLevel(clip:GetFrameLevel() + 30)
    local fitBtn = ns.Button(hud, "Fit", 44, function() fitView() end)
    fitBtn:SetPoint("TOPRIGHT", -6, -6)
    local zoomIn = ns.Button(hud, "+", 24, function()
        local cw, ch = clipSize()
        local old, new = view.zoom, math.min(MAX_ZOOM, view.zoom * 1.25)
        local px, py = (cw / 2 - view.x) / old, (ch / 2 - view.y) / old
        view.zoom, view.x, view.y = new, cw / 2 - px * new, ch / 2 - py * new
        applyView()
    end)
    zoomIn:SetPoint("RIGHT", fitBtn, "LEFT", -2, 0)
    local zoomOut = ns.Button(hud, "-", 24, function()
        local cw, ch = clipSize()
        local old = view.zoom
        local new = math.max(math.min(view.fit or 1, 1) * 0.5, old / 1.25)
        local px, py = (cw / 2 - view.x) / old, (ch / 2 - view.y) / old
        view.zoom, view.x, view.y = new, cw / 2 - px * new, ch / 2 - py * new
        applyView()
    end)
    zoomOut:SetPoint("RIGHT", zoomIn, "LEFT", -2, 0)
    local hint = ns.Label(hud, "GameFontDisableSmall", "Drag to move  -  scroll to zoom", "LEFT")
    hint:SetPoint("BOTTOMLEFT", 8, 6)

    -- connector pieces, reused between draws
    local pieces, used = {}, 0
    local function piece(x, y, w, h, color, alpha, layer)
        used = used + 1
        local t = pieces[used]
        if not t then
            t = canvas:CreateTexture(nil, "BORDER")
            pieces[used] = t
        end
        t:SetDrawLayer("BORDER", layer or 0)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", canvas, "TOPLEFT", x, -y)
        t:SetSize(math.max(1, w), math.max(1, h))
        t:SetColorTexture(color[1], color[2], color[3], alpha or 1)
        t:Show()
    end
    -- parent's right edge -> child's left edge, as an elbow
    local function elbow(p, c, color, thick, alpha, offset, layer)
        local x1, y1 = p.x + NODE_W, p.y + NODE_H / 2 + offset
        local x2, y2 = c.x, c.y + NODE_H / 2 + offset
        local mid = x1 + (x2 - x1) / 2 + offset
        local half = thick / 2
        piece(x1, y1 - half, mid - x1, thick, color, alpha, layer)
        piece(mid - half, math.min(y1, y2) - half, thick, math.abs(y2 - y1) + thick, color, alpha, layer)
        piece(mid, y2 - half, x2 - mid, thick, color, alpha, layer)
    end

    -- ---------------------------------------------------------------- nodes
    local nodes, nodeCount = {}, 0
    local moreLabels, moreCount = {}, 0
    local graph

    local function nodeTooltip(self)
        local n = self.node
        if not n then return end
        ns.ItemTooltip(self, n.itemID, function(tip)
            local rootName = nameOf(graph.root.itemID)
            tip:AddLine(" ")
            if not n.recipe then
                tip:AddDoubleLine("Sell as it is", ns.Money(n.sell) .. " each", 1, 1, 1, 1, 1, 1)
                if n.have > 0 then tip:AddDoubleLine("You have", n.have, 1, 1, 1, 1, 1, 1) end
                tip:AddLine(" ")
                tip:AddLine("Shift-click: search it on the AH.", 0.6, 0.6, 0.6)
                return
            end
            local r = n.recipe
            tip:AddLine(string.format("%s (%s)", r.name or "?", r.prof or "?"), 1, 0.82, 0)
            if r.diff then
                local c = ns.SKILL_COLORS[r.diff]
                local chance = r.diff == 0 and "a point every craft" or r.diff == 1 and "a point most crafts"
                    or r.diff == 2 and "a point now and then" or "no more points"
                tip:AddDoubleLine("Skill-up", ns.SKILL_NAMES[r.diff] .. ": " .. chance, 1, 1, 1, c[1], c[2], c[3])
            else
                tip:AddDoubleLine("Skill-up", "unknown (open the profession)", 1, 1, 1, 0.6, 0.6, 0.6)
            end
            tip:AddDoubleLine(string.format("Uses %d %s", n.qty, nameOf(n.parent.itemID)),
                string.format("makes %g", n.yield), 1, 1, 1, 1, 1, 1)
            if n.others > 0 then tip:AddDoubleLine("Other reagents", ns.Money(n.others), 1, 1, 1, 1, 1, 1) end
            tip:AddDoubleLine("Sells for", ns.Money(n.sell) .. " each", 1, 1, 1, 1, 1, 1)
            tip:AddLine(" ")
            tip:AddDoubleLine(string.format("Each %s becomes", rootName), ns.Money(n.rootValue), 1, 1, 1, 1, 1, 1)
            tip:AddDoubleLine("Selling it raw", ns.Money(graph.raw), 1, 1, 1, 1, 1, 1)
            tip:AddDoubleLine("Difference", ns.MoneyPL(n.gain), 1, 1, 1, 1, 1, 1)
            if n.chance and n.chance > 0 then
                tip:AddLine(" ")
                tip:AddDoubleLine("One craft", n.craftNet >= 0 and ("costs you " .. ns.Money(n.craftNet))
                    or ("earns you " .. ns.Money(-n.craftNet)), 1, 1, 1, 1, 1, 1)
                tip:AddDoubleLine("Per skill point (about)", n.costPerPoint >= 0 and ns.Money(n.costPerPoint)
                    or ("earns " .. ns.Money(-n.costPerPoint)), 1, 1, 1, 1, 1, 1)
            end
            if n.hidden and n.hidden > 0 then
                tip:AddLine(string.format("%d more uses not shown (less valuable).", n.hidden), 0.6, 0.6, 0.6)
            end
            tip:AddLine(" ")
            tip:AddLine("Click: open this recipe in " .. (r.prof or "the profession window") .. ".", 0.6, 0.6, 0.6)
            tip:AddLine("Right-click: explore from this item.  Shift-click: search the AH.", 0.6, 0.6, 0.6)
        end)
    end

    local function nodeClick(self, button)
        local n = self.node
        if not n then return end
        if IsShiftKeyDown() then
            ns.SearchAH({ nameOf(n.itemID) })
        elseif button == "RightButton" then
            if n.recipe then
                table.insert(state.history, state.root)
                state.root = n.itemID
                page:Refresh()
            end
        elseif n.recipe then
            ns.OpenRecipe(n.recipe)
        end
    end

    local function nodeFrame(i)
        local f = nodes[i]
        if f then return f end
        f = CreateFrame("Button", nil, canvas, "BackdropTemplate")
        f:SetSize(NODE_W, NODE_H)
        ns.Backdrop(f, 0.11, 0.11, 0.13, 1)
        f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        f.top = f:CreateTexture(nil, "ARTWORK")
        f.top:SetPoint("TOPLEFT", 4, -4)
        f.top:SetPoint("BOTTOMLEFT", f, "LEFT", 4, 0)
        f.top:SetWidth(3)
        f.bottom = f:CreateTexture(nil, "ARTWORK")
        f.bottom:SetPoint("TOPLEFT", f, "LEFT", 4, 0)
        f.bottom:SetPoint("BOTTOMLEFT", 4, 4)
        f.bottom:SetWidth(3)
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetSize(24, 24)
        f.icon:SetPoint("LEFT", 10, 0)
        f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f.name = ns.Label(f, "GameFontHighlightSmall", "", "LEFT")
        f.name:SetPoint("TOPLEFT", 38, -5)
        f.name:SetWidth(NODE_W - 44)
        f.name:SetWordWrap(false)
        f.value = ns.Label(f, "GameFontHighlightSmall", "", "LEFT")
        f.value:SetPoint("BOTTOMLEFT", 38, 6)
        f.value:SetWidth(NODE_W - 44)
        f.value:SetWordWrap(false)
        local hl = f:CreateTexture(nil, "HIGHLIGHT")
        hl:SetPoint("TOPLEFT", 3, -3)
        hl:SetPoint("BOTTOMRIGHT", -3, 3)
        hl:SetColorTexture(1, 1, 1, 0.07)
        f:SetScript("OnEnter", nodeTooltip)
        f:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f:SetScript("OnClick", nodeClick)
        f:EnableMouseWheel(true)
        f:SetScript("OnMouseWheel", function(_, delta) zoomAt(delta) end)
        nodes[i] = f
        return f
    end

    local function moreLabel(i)
        local l = moreLabels[i]
        if not l then
            l = ns.Label(canvas, "GameFontDisableSmall", "", "LEFT")
            moreLabels[i] = l
        end
        return l
    end

    local function drawNode(n)
        nodeCount = nodeCount + 1
        local f = nodeFrame(nodeCount)
        f.node = n
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", canvas, "TOPLEFT", n.x, -n.y)
        f.icon:SetTexture(ns.ItemIcon(n.itemID) or 134400)
        f.name:SetText(nameOf(n.itemID))
        if n.recipe then
            f.value:SetText(ns.MoneyPL(n.gain) .. DIM .. " each|r")
            local c = n.recipe.diff and ns.SKILL_COLORS[n.recipe.diff] or { 0.35, 0.35, 0.4 }
            f:SetBackdropBorderColor(c[1], c[2], c[3], 1)
        else
            f.value:SetText(plain(n.sell) .. DIM .. " raw" .. (n.have > 0 and ("  x" .. n.have) or "") .. "|r")
            f:SetBackdropBorderColor(0.9, 0.9, 0.9, 1)
        end
        -- left edge: top half gold when on the gold route, bottom half orange when on the leveling route
        local top = n.onProfit and GOLD or (n.onLevel and LEVEL) or nil
        local bottom = n.onLevel and LEVEL or (n.onProfit and GOLD) or nil
        f.top:SetShown(top ~= nil)
        f.bottom:SetShown(bottom ~= nil)
        if top then f.top:SetColorTexture(top[1], top[2], top[3], 1) end
        if bottom then f.bottom:SetColorTexture(bottom[1], bottom[2], bottom[3], 1) end
        f:Show()
    end

    -- ---------------------------------------------------------------- refresh
    function page:RefreshList()
        local filter = strlower(strtrim(search:GetText() or ""))
        local rows = {}
        for _, r in ipairs(self.items or {}) do
            local name = r.name or ns.ItemName(r.itemID) or ""
            r.name = r.name or ns.ItemName(r.itemID)
            if filter == "" or strlower(name):find(filter, 1, true) then rows[#rows + 1] = r end
        end
        list:SetData(rows)
    end

    local function pickDefault(items)
        -- the material you own that gains the most from crafting, else the first you own
        local best, bestGain
        for _, m in ipairs(ns.MaterialRows()) do
            if m.path and (not bestGain or m.totalGain > bestGain) then best, bestGain = m.itemID, m.totalGain end
        end
        if best then return best end
        for _, r in ipairs(items) do
            if r.have > 0 then return r.itemID end
        end
        return items[1] and items[1].itemID
    end

    function page:Refresh()
        self.items = ns.ExploreItems()
        if not state.root then state.root = pickDefault(self.items) end
        self:RefreshList()
        back:SetEnabled(#state.history > 0)

        for i = 1, nodeCount do nodes[i]:Hide() end
        for i = 1, moreCount do moreLabels[i]:Hide() end
        for i = 1, used do pieces[i]:Hide() end
        nodeCount, moreCount, used = 0, 0, 0

        if not state.root then
            title:SetText("")
            skillText:SetText("")
            goldCard.text:SetText("")
            levelCard.text:SetText("")
            legend:SetText("")
            empty:SetText("Open your profession window once so ZugDAQ can read your recipes.")
            empty:Show()
            return
        end

        graph = ns.CraftGraph(state.root)
        local root = graph.root
        local rootName = nameOf(root.itemID)
        title:SetText("|T" .. (ns.ItemIcon(root.itemID) or 134400) .. ":18:18|t  " .. rootName)
        local skill = graph.skill
        skillText:SetText(graph.prof and skill and string.format("%s %d / %d", graph.prof, skill.level or 0, skill.max or 0) or "")

        -- best for gold
        local p = graph.profit
        if p == root then
            goldCard.text:SetText(string.format("Sell it as it is: %s each.\nNothing you know crafts it into more.", ns.Money(graph.raw)))
        else
            local usable = p.usable or root.have
            local total = usable > 0 and string.format("  Your %d: %s", usable, ns.MoneyPL(p.gain * usable)) or ""
            goldCard.text:SetText(string.format("Craft %s, then sell.\n%s per %s%s", routeText(p),
                ns.MoneyPL(p.gain), rootName, total))
        end

        -- best for leveling
        local l = graph.level
        if l then
            local c = ns.SKILL_COLORS[l.recipe.diff]
            local colour = string.format("|cff%02x%02x%02x%s|r", c[1] * 255, c[2] * 255, c[3] * 255, ns.SKILL_NAMES[l.recipe.diff])
            local price = l.costPerPoint >= 0 and ("about " .. ns.Money(l.costPerPoint) .. " per point")
                or ("earns " .. ns.Money(-l.costPerPoint) .. " per point")
            levelCard.text:SetText(string.format("Craft %s (%s).\n%s", routeText(l), colour, price))
        elseif not graph.colours and #root.children > 0 then
            levelCard.text:SetText("Open " .. (graph.prof or "the profession") .. " once so ZugDAQ can read\nthe skill-up colours.")
        elseif #root.children > 0 then
            levelCard.text:SetText("Nothing made from this gives skill points any more (all grey).")
        else
            levelCard.text:SetText(DIM .. "-|r")
        end

        -- columns spread across the width for however deep this tree goes
        local maxDepth = 0
        local function depthOf(n)
            if n.depth > maxDepth then maxDepth = n.depth end
            for _, ch in ipairs(n.children) do depthOf(ch) end
        end
        depthOf(root)
        COL = maxDepth > 0 and math.min(220, (GW - 2 * PAD - NODE_W) / maxDepth) or 0

        -- lay the tree out left to right: leaves stacked, parents centred on their children
        local cursor = 0
        local function layout(n)
            n.x = PAD + n.depth * COL
            if #n.children == 0 then
                n.y = cursor
                cursor = cursor + ROW
            else
                for _, ch in ipairs(n.children) do layout(ch) end
                n.y = (n.children[1].y + n.children[#n.children].y) / 2
                if (n.hidden or 0) > 0 then
                    n.moreY = cursor - ROW + NODE_H + 2
                    cursor = cursor + 12
                end
            end
        end
        layout(root)
        local contentH = cursor - (ROW - NODE_H) + 2 * PAD
        local contentW = 2 * PAD + maxDepth * COL + NODE_W
        local function shift(n)
            n.y = n.y + PAD
            if n.moreY then n.moreY = n.moreY + PAD end
            for _, ch in ipairs(n.children) do shift(ch) end
        end
        shift(root)
        canvas:SetSize(contentW, contentH)
        view.w, view.h = contentW, contentH
        -- a new item opens fitted to the window; refreshes of the same one keep your pan and zoom
        if view.root ~= root.itemID then
            view.root = root.itemID
            fitView()
        else
            applyView()
        end

        -- connectors first (plain, then the routes on top), then the boxes
        local function edges(n)
            for _, ch in ipairs(n.children) do
                if not ch.onProfit and not ch.onLevel then elbow(n, ch, EDGE, 1, 0.8, 0, 0) end
                edges(ch)
            end
        end
        local function routes(n)
            for _, ch in ipairs(n.children) do
                if ch.onLevel then elbow(n, ch, LEVEL, 2, 1, ch.onProfit and 3 or 0, 2) end
                if ch.onProfit then elbow(n, ch, GOLD, 2, 1, 0, 3) end
                routes(ch)
            end
        end
        edges(root)
        routes(root)
        local function nodesOf(n)
            drawNode(n)
            if (n.hidden or 0) > 0 then
                moreCount = moreCount + 1
                local lbl = moreLabel(moreCount)
                lbl:ClearAllPoints()
                lbl:SetPoint("TOPLEFT", canvas, "TOPLEFT", PAD + (n.depth + 1) * COL + 4, -n.moreY)
                lbl:SetText(string.format("+%d more", n.hidden))
                lbl:Show()
            end
            for _, ch in ipairs(n.children) do nodesOf(ch) end
        end
        nodesOf(root)

        if #root.children == 0 then
            empty:SetText("Nothing you know uses " .. rootName .. ".")
            empty:Show()
        else
            empty:Hide()
        end

        local when = skill and skill.at and date("%d %b", skill.at)
        legend:SetText("|cffffd100Gold|r = best for gold   |cffff8040Orange|r = best for leveling   Border = skill-up colour" ..
            (when and (DIM .. " (as of " .. when .. ")|r") or "") ..
            (graph.culled > 0 and string.format("   %s%d hidden: no skill-ups, worth less than raw|r", DIM, graph.culled) or ""))
    end
end)
