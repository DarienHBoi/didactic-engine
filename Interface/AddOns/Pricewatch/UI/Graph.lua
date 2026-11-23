local _, P = ...
P.UI = P.UI or {}

-- The graph canvas: lines through CreateLine, markers as small squares, hover readout through the tooltip.
local COLORS = {
    market = { 1, 0.82, 0.25 },     -- gold line
    de = { 0.7, 0.45, 1 },          -- purple line (estimate)
    zug = { 0.3, 0.85, 0.85 },      -- teal line: ZugHistory server price
    listings = { 0.4, 0.75, 1 },    -- blue marker
    sales = { 0.35, 1, 0.4 },       -- green dot
    salesAssumed = { 1, 0.6, 0.2 }, -- orange dot: stack size unknown
    supply = { 0.55, 0.55, 0.55 },  -- thin grey bars: listed quantity
}
P.UI.GRAPH_COLORS = COLORS

local function money(v) return P.Money.format(math.floor(v + 0.5)) end

local SERIES_LABEL = { market = "Market low", listings = "Your listing", sales = "Your sale", de = "Disenchant (estimate)" }

-- parent: frame to hold the canvas; w, h: canvas size. Returns an object with :draw(series) and .canvas.
function P.UI.newGraph(parent, w, h)
    local g = { w = w, h = h, lines = {}, dots = {}, labels = {}, bars = {}, used = { lines = 0, dots = 0, labels = 0, bars = 0 } }
    local canvas = CreateFrame("Frame", nil, parent)
    canvas:SetSize(w, h)
    g.canvas = canvas
    canvas:EnableMouse(true)
    g.bg = canvas:CreateTexture(nil, "BACKGROUND")
    g.bg:SetAllPoints()
    g.bg:SetColorTexture(0.03, 0.03, 0.028, 0.9)
    g.hasLines = canvas.CreateLine ~= nil
    g.empty = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    g.empty:SetPoint("CENTER")
    g.empty:SetWidth(w - 40)

    local function line(x1, y1, x2, y2, c, thick, alpha)
        local i = g.used.lines + 1
        g.used.lines = i
        local l = g.lines[i]
        if not l then
            l = canvas:CreateLine(nil, "ARTWORK")
            g.lines[i] = l
        end
        l:SetThickness(thick or 1)
        l:SetColorTexture(c[1], c[2], c[3], alpha or 1)
        l:SetStartPoint("TOPLEFT", canvas, x1, -y1)
        l:SetEndPoint("TOPLEFT", canvas, x2, -y2)
        l:Show()
    end
    local function dot(x, y, c, size)
        local i = g.used.dots + 1
        g.used.dots = i
        local t = g.dots[i]
        if not t then
            t = canvas:CreateTexture(nil, "OVERLAY")
            g.dots[i] = t
        end
        t:SetSize(size, size)
        t:SetColorTexture(c[1], c[2], c[3], 1)
        t:ClearAllPoints()
        t:SetPoint("CENTER", canvas, "TOPLEFT", x, -y)
        t:Show()
    end
    -- A thin supply bar standing on the bottom of the plot.
    local function bar(x, height)
        local i = g.used.bars + 1
        g.used.bars = i
        local t = g.bars[i]
        if not t then
            t = canvas:CreateTexture(nil, "BORDER")
            g.bars[i] = t
        end
        t:SetSize(3, height)
        t:SetColorTexture(COLORS.supply[1], COLORS.supply[2], COLORS.supply[3], 0.5)
        t:ClearAllPoints()
        t:SetPoint("BOTTOM", canvas, "TOPLEFT", x, -(g.oy + g.lay.h))
        t:Show()
    end
    local function label(x, y, text, anchor)
        local i = g.used.labels + 1
        g.used.labels = i
        local fs = g.labels[i]
        if not fs then
            fs = canvas:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            g.labels[i] = fs
        end
        fs:ClearAllPoints()
        fs:SetPoint(anchor, canvas, "TOPLEFT", x, -y)
        fs:SetText(text)
        fs:Show()
    end

    function g:draw(series, e0)
        for _, l in ipairs(g.lines) do l:Hide() end
        for _, d in ipairs(g.dots) do d:Hide() end
        for _, f in ipairs(g.labels) do f:Hide() end
        for _, b in ipairs(g.bars) do b:Hide() end
        g.used = { lines = 0, dots = 0, labels = 0, bars = 0 }
        g.lay, g.e0 = nil, e0
        if not g.hasLines then
            g.empty:SetText("This client cannot draw lines (no CreateLine).")
            g.empty:Show()
            return
        end
        if not (series and series.hasData) then
            g.empty:SetText("No price history stored for this item yet.\nOpen the auction house and scan with Auctionator; Pricewatch copies the daily prices.")
            g.empty:Show()
            return
        end
        g.empty:Hide()
        local lay = P.Graph.layout(series, w - 70, h - 30)
        g.lay, g.ox, g.oy = lay, 62, 8
        -- gridlines and axis labels
        local values = {}
        for i, t in ipairs(lay.yTicks) do values[i] = t.value end
        local texts = P.Graph.axisLabels(values)
        for i, t in ipairs(lay.yTicks) do
            line(g.ox, g.oy + t.y, g.ox + lay.w, g.oy + t.y, { 0.5, 0.45, 0.3 }, 1, 0.25)
            label(g.ox - 4, g.oy + t.y, texts[i], "RIGHT")
        end
        for _, b in ipairs(lay.bars) do bar(g.ox + b.x, b.h) end
        for _, t in ipairs(lay.xTicks) do
            label(g.ox + t.x, g.oy + lay.h + 12, P.Days.label(t.day, e0), "CENTER")
        end
        for _, key in ipairs({ "zug", "de", "market" }) do
            for _, s in ipairs(lay.segments[key]) do
                line(g.ox + s.x1, g.oy + s.y1, g.ox + s.x2, g.oy + s.y2, COLORS[key], key == "market" and 2 or 1.5)
            end
            if #lay[key] == 1 then dot(g.ox + lay[key][1].x, g.oy + lay[key][1].y, COLORS[key], 5) end
        end
        for _, p in ipairs(lay.listings) do dot(g.ox + p.x, g.oy + p.y, COLORS.listings, 6) end
        for _, p in ipairs(lay.sales) do dot(g.ox + p.x, g.oy + p.y, p.assumed and COLORS.salesAssumed or COLORS.sales, 7) end
    end

    -- Hover: the nearest point shows its date and value.
    function g:hoverAt(x, y)
        if not g.lay then return nil end
        return P.Graph.hover(g.lay, x - g.ox, y - g.oy)
    end
    canvas:SetScript("OnUpdate", function(self)
        if not (self.IsMouseOver and self:IsMouseOver()) then
            if g.tipShown then GameTooltip:Hide(); g.tipShown = false end
            return
        end
        local cx, cy = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        local left, top = self:GetLeft(), self:GetTop()
        if not (cx and left and top and scale and scale > 0) then return end
        local p = g:hoverAt(cx / scale - left, top - cy / scale)
        if not p then
            if g.tipShown then GameTooltip:Hide(); g.tipShown = false end
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(SERIES_LABEL[p.series] or p.series, 1, 0.82, 0)
        GameTooltip:AddDoubleLine(P.Days.label(p.day, g.e0, nil), money(p.value), 1, 1, 1, 1, 1, 1)
        if p.series == "market" and p.qty then GameTooltip:AddLine(p.qty .. " listed", 0.7, 0.7, 0.7) end
        local scanNote = P.Graph.scanText(p)
        if scanNote then GameTooltip:AddLine(scanNote, 0.7, 0.7, 0.7) end
        if p.series == "sales" and p.assumed then GameTooltip:AddLine("Stack size unknown: one unit assumed", 1, 0.6, 0.2) end
        GameTooltip:Show()
        g.tipShown = true
    end)
    return g
end
