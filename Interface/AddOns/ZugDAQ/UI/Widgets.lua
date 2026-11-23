local _, ns = ...

-- Small home-made widgets (no scroll templates), so they behave the same on any client.

ns.COLORS = {
    good = "|cff40ff40", warn = "|cffffd200", bad = "|cffff5050", tip = "|cff66bbff",
    dim = "|cffaaaaaa", white = "|cffffffff", gold = "|cffffd700",
}

local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

function ns.Backdrop(frame, r, g, b, a)
    if not frame.SetBackdrop then Mixin(frame, BackdropTemplateMixin) end
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(r or 0.06, g or 0.06, b or 0.08, a or 0.95)
    frame:SetBackdropBorderColor(0.45, 0.45, 0.5, 1)
end

function ns.Label(parent, font, text, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetJustifyH(justify or "LEFT")
    if text then fs:SetText(text) end
    return fs
end

function ns.Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 90, 22)
    b:SetText(text)
    if onClick then
        b:SetScript("OnClick", function(...)
            if ns.Trace then ns.Trace("click " .. tostring(text)) end
            return onClick(...)
        end)
    end
    return b
end

-- a row of toggle buttons; onSelect(key)
function ns.Toggles(parent, items, onSelect)
    local group = { buttons = {} }
    local prev
    for _, item in ipairs(items) do
        local b = ns.Button(parent, item.text, item.width or 90)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) end
        b:SetScript("OnClick", function() group:Select(item.key) onSelect(item.key) end)
        group.buttons[item.key] = b
        if not group.first then group.first = b end
        prev = b
    end
    function group:Select(key)
        self.selected = key
        for k, b in pairs(self.buttons) do
            if k == key then b:LockHighlight() b:GetFontString():SetTextColor(1, 1, 1)
            else b:UnlockHighlight() b:GetFontString():SetTextColor(1, 0.82, 0) end
        end
    end
    return group
end

-- flat text tabs with a gold underline on the selected one; onSelect(key)
function ns.SubTabs(parent, items, onSelect)
    local group = { buttons = {} }
    local prev
    for _, item in ipairs(items) do
        local b = CreateFrame("Button", nil, parent)
        b:SetHeight(22)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.text:SetPoint("CENTER", 0, 1)
        b.text:SetText(item.text)
        b:SetWidth(math.max(60, b.text:GetStringWidth() + 26))
        b.line = b:CreateTexture(nil, "ARTWORK")
        b.line:SetHeight(2)
        b.line:SetPoint("BOTTOMLEFT", 6, 0)
        b.line:SetPoint("BOTTOMRIGHT", -6, 0)
        b.line:SetColorTexture(1, 0.82, 0, 1)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0) end
        b:SetScript("OnClick", function() group:Select(item.key) onSelect(item.key) end)
        group.buttons[item.key] = b
        group.first = group.first or b
        prev = b
    end
    function group:Select(key)
        self.selected = key
        for k, b in pairs(self.buttons) do
            b.line:SetShown(k == key)
            if k == key then b.text:SetTextColor(1, 1, 1) else b.text:SetTextColor(0.65, 0.65, 0.65) end
        end
    end
    function group:SetShown(shown)
        for _, b in pairs(self.buttons) do b:SetShown(shown) end
    end
    return group
end

function ns.ItemTooltip(owner, itemID, extra)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if itemID then
        local ok = pcall(GameTooltip.SetItemByID, GameTooltip, itemID)
        if not ok then GameTooltip:SetHyperlink("item:" .. itemID) end
    end
    if extra then extra(GameTooltip) end
    GameTooltip:Show()
end

-- ---------------------------------------------------------------- table

-- columns: { title, width, align, text = fn(row) -> string, sort = fn(row) -> value, icon = fn(row) -> texture,
--            bar = fn(row) -> value, {r, g, b}? : a bar from the cell's centre, green right / red left }
-- opts: rows (count), rowHeight, onEnter(row, frame), onClick(row, mouseButton, frame), sortCol, sortDesc, empty
function ns.CreateTable(parent, columns, opts)
    opts = opts or {}
    local rowHeight = opts.rowHeight or 18
    local t = CreateFrame("Frame", nil, parent)
    t.columns, t.data, t.offset = columns, {}, 0
    t.sortCol, t.sortDesc = opts.sortCol, opts.sortDesc ~= false
    t.numRows = opts.rows or 15

    local header = CreateFrame("Frame", nil, t)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(20)
    local hbg = header:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints()
    hbg:SetColorTexture(1, 1, 1, 0.06)

    t.headers = {}
    local x = 4
    for i, col in ipairs(columns) do
        local h = CreateFrame("Button", nil, header)
        h:SetPoint("LEFT", header, "LEFT", x, 0)
        h:SetSize(col.width, 20)
        local fs = ns.Label(h, "GameFontNormalSmall", col.title, col.align)
        fs:SetAllPoints()
        h.label = fs
        if col.sort then
            h:SetScript("OnClick", function()
                if t.sortCol == i then t.sortDesc = not t.sortDesc
                else t.sortCol, t.sortDesc = i, col.defaultAsc ~= true end
                t:Sort()
                t:Draw()
            end)
            h:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        end
        t.headers[i] = h
        x = x + col.width + 6
    end

    t.rows = {}
    for r = 1, t.numRows do
        local row = CreateFrame("Button", nil, t)
        row:SetHeight(rowHeight)
        row:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -(r - 1) * rowHeight)
        row:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -(r - 1) * rowHeight)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        if r % 2 == 0 then
            local stripe = row:CreateTexture(nil, "BACKGROUND")
            stripe:SetAllPoints()
            stripe:SetColorTexture(1, 1, 1, 0.03)
        end
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.82, 0, 0.12)
        row.cells = {}
        local cx = 4
        for i, col in ipairs(columns) do
            local left = cx
            if col.icon then
                local icon = row:CreateTexture(nil, "ARTWORK")
                icon:SetSize(rowHeight - 2, rowHeight - 2)
                icon:SetPoint("LEFT", row, "LEFT", cx, 0)
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                row.icon = icon
                left = cx + rowHeight
            end
            if col.bar then
                local center = cx + col.width / 2
                local mid = row:CreateTexture(nil, "BORDER")
                mid:SetColorTexture(1, 1, 1, 0.25)
                mid:SetSize(1, rowHeight - 2)
                mid:SetPoint("CENTER", row, "LEFT", center, 0)
                local bar = row:CreateTexture(nil, "ARTWORK")
                bar:SetHeight(math.max(4, rowHeight - 7))
                row.bars = row.bars or {}
                row.bars[i] = { tex = bar, center = center, half = col.width / 2 - 2 }
            end
            local fs = ns.Label(row, "GameFontHighlightSmall", nil, col.align)
            fs:SetPoint("LEFT", row, "LEFT", left, 0)
            fs:SetWidth(col.width - (left - cx))
            if col.wrap then
                -- tall rows can show two lines of text
                fs:SetWordWrap(true)
                fs:SetHeight(rowHeight - 2)
                fs:SetJustifyV("MIDDLE")
                if fs.SetMaxLines then fs:SetMaxLines(2) end
            else
                fs:SetWordWrap(false)
            end
            row.cells[i] = fs
            cx = cx + col.width + 6
        end
        row:SetScript("OnEnter", function(self)
            if self.data and opts.onEnter then opts.onEnter(self.data, self) end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", function(self, button)
            if self.data and opts.onClick then
                if ns.Trace then ns.Trace("row click " .. tostring(button)) end
                opts.onClick(self.data, button, self)
            end
        end)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta) t:Scroll(delta) end)
        t.rows[r] = row
    end

    t.footer = ns.Label(t, "GameFontDisableSmall", "", "RIGHT")
    t.footer:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -4, -t.numRows * rowHeight - 2)
    t.empty = ns.Label(t, "GameFontDisable", opts.empty or "Nothing here yet.", "CENTER")
    t.empty:SetPoint("TOP", header, "BOTTOM", 0, -30)
    t.empty:SetWidth(500)

    t:EnableMouseWheel(true)
    t:SetScript("OnMouseWheel", function(_, delta) t:Scroll(delta) end)
    t:SetHeight(20 + t.numRows * rowHeight + 16)

    function t:Scroll(delta)
        local maxOffset = math.max(0, #self.data - self.numRows)
        self.offset = math.max(0, math.min(maxOffset, self.offset - delta * 3))
        self:Draw()
    end

    function t:Sort()
        local col = self.columns[self.sortCol]
        if not col or not col.sort then return end
        -- sort keys live outside the rows: rows can be saved-variable tables
        local keys = {}
        for _, d in ipairs(self.data) do
            local ok, k = pcall(col.sort, d)
            keys[d] = ok and k or nil
        end
        local desc = self.sortDesc
        table.sort(self.data, function(a, b)
            local va, vb = keys[a], keys[b]
            if va == nil then return false end
            if vb == nil then return true end
            if type(va) ~= type(vb) then va, vb = tostring(va), tostring(vb) end
            if va == vb then return false end
            if desc then return va > vb end
            return va < vb
        end)
        for i, h in ipairs(self.headers) do
            local c = self.columns[i]
            h.label:SetText(c.title .. (i == self.sortCol and (desc and " v" or " ^") or ""))
        end
    end

    function t:SetData(data)
        self.data = data or {}
        -- bar columns scale to the biggest value in the data
        self.barMax = {}
        for i, col in ipairs(self.columns) do
            if col.bar then
                local max = 0
                for _, d in ipairs(self.data) do
                    local ok, v = pcall(col.bar, d)
                    if ok and type(v) == "number" then max = math.max(max, math.abs(v)) end
                end
                self.barMax[i] = max
            end
        end
        self:Sort()
        local maxOffset = math.max(0, #self.data - self.numRows)
        if self.offset > maxOffset then self.offset = maxOffset end
        self:Draw()
    end

    function t:Draw()
        for r, row in ipairs(self.rows) do
            local d = self.data[self.offset + r]
            row.data = d
            if d then
                for i, col in ipairs(self.columns) do
                    local ok, text = true, ""
                    if col.text then ok, text = pcall(col.text, d) end
                    row.cells[i]:SetText(ok and text or "?")
                    local b = col.bar and row.bars and row.bars[i]
                    if b then
                        local okBar, v, color = pcall(col.bar, d)
                        local max = self.barMax and self.barMax[i] or 0
                        if okBar and type(v) == "number" and v ~= 0 and max > 0 then
                            local c = color or (v > 0 and ns.GAIN or ns.LOSS)
                            b.tex:ClearAllPoints()
                            b.tex:SetWidth(math.max(1, b.half * math.abs(v) / max))
                            b.tex:SetColorTexture(c[1], c[2], c[3], 0.95)
                            if v > 0 then
                                b.tex:SetPoint("LEFT", row, "LEFT", b.center, 0)
                            else
                                b.tex:SetPoint("RIGHT", row, "LEFT", b.center, 0)
                            end
                            b.tex:Show()
                        else
                            b.tex:Hide()
                        end
                    end
                    if col.icon and row.icon then
                        local okIcon, tex = pcall(col.icon, d)
                        row.icon:SetTexture(okIcon and tex or 134400)
                    end
                end
                row:Show()
            else
                row:Hide()
            end
        end
        local n = #self.data
        self.empty:SetShown(n == 0)
        if n > self.numRows then
            self.footer:SetText(string.format("%d-%d of %d (scroll for more)", self.offset + 1,
                math.min(n, self.offset + self.numRows), n))
        else
            self.footer:SetText(n > 0 and (n .. (n == 1 and " row" or " rows")) or "")
        end
    end

    return t
end

-- ---------------------------------------------------------------- bar list

-- horizontal bars: SetData({ { label, value, text, r, g, b } }) scaled to the largest value
function ns.CreateBarList(parent, count, width, rowHeight)
    rowHeight = rowHeight or 16
    local list = CreateFrame("Frame", nil, parent)
    list:SetSize(width, count * rowHeight)
    list.rows = {}
    local labelWidth, valueWidth = math.floor(width * 0.36), 90
    for i = 1, count do
        local row = CreateFrame("Frame", nil, list)
        row:SetSize(width, rowHeight)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
        row.label = ns.Label(row, "GameFontHighlightSmall", nil, "LEFT")
        row.label:SetPoint("LEFT", 0, 0)
        row.label:SetWidth(labelWidth)
        row.label:SetWordWrap(false)
        row.bar = row:CreateTexture(nil, "ARTWORK")
        row.bar:SetPoint("LEFT", labelWidth + 4, 0)
        row.bar:SetHeight(rowHeight - 5)
        row.value = ns.Label(row, "GameFontHighlightSmall", nil, "RIGHT")
        row.value:SetPoint("RIGHT", 0, 0)
        row.value:SetWidth(valueWidth)
        list.rows[i] = row
    end
    local barSpace = width - labelWidth - valueWidth - 12
    function list:SetData(data)
        local max = 0
        for _, d in ipairs(data) do max = math.max(max, math.abs(d.value or 0)) end
        for i, row in ipairs(self.rows) do
            local d = data[i]
            if d then
                row.label:SetText(d.label)
                row.value:SetText(d.text or ns.Money(d.value))
                local w = max > 0 and math.max(1, barSpace * math.abs(d.value) / max) or 1
                row.bar:SetWidth(w)
                row.bar:SetColorTexture(d.r or 0.25, d.g or 0.7, d.b or 0.3, 0.85)
                row:Show()
            else
                row:Hide()
            end
        end
    end
    return list
end

-- ---------------------------------------------------------------- profit and loss

ns.GAIN = { 0.22, 0.78, 0.36 }
ns.LOSS = { 0.90, 0.30, 0.30 }

-- money as one colour: green and "+" for a gain, red and "-" for a loss, grey for nothing
function ns.MoneyPL(copper)
    copper = copper or 0
    local color = copper > 0 and "|cff38c75c" or copper < 0 and "|cffe64d4d" or "|cffaaaaaa"
    local plain = ns.Money(math.abs(copper)):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return color .. (copper > 0 and "+" or copper < 0 and "-" or "") .. plain .. "|r"
end

local function hoverable(frame)
    if frame.SetMouseMotionEnabled then frame:SetMouseMotionEnabled(true) else frame:EnableMouse(true) end
end

-- tooltip from a list: the first line is the title, { left, right } pairs become two columns
local function showLines(owner, lines, anchor)
    if not lines then return end
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    for i, line in ipairs(lines) do
        if type(line) == "table" then
            GameTooltip:AddDoubleLine(line[1], line[2], 0.8, 0.8, 0.8, 1, 1, 1)
        elseif i == 1 then
            GameTooltip:AddLine(line, 1, 0.82, 0)
        else
            GameTooltip:AddLine(line, 1, 1, 1, true)
        end
    end
    GameTooltip:Show()
end
ns.ShowLines = showLines

-- a boxed number with a coloured edge: tile:Set(valueText, subText, sign, tooltipLines)
function ns.StatTile(parent, width, height, title)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(width, height)
    ns.Backdrop(f, 0.09, 0.09, 0.11, 0.95)
    f.accent = f:CreateTexture(nil, "ARTWORK")
    f.accent:SetPoint("TOPLEFT", 4, -4)
    f.accent:SetPoint("BOTTOMLEFT", 4, 4)
    f.accent:SetWidth(3)
    f.title = ns.Label(f, "GameFontDisableSmall", title)
    f.title:SetPoint("TOPLEFT", 13, -8)
    f.value = ns.Label(f, "GameFontHighlightLarge", "")
    f.value:SetPoint("BOTTOMLEFT", 13, 8)
    f.sub = ns.Label(f, "GameFontDisableSmall", "", "RIGHT")
    f.sub:SetPoint("TOPRIGHT", -8, -8)
    hoverable(f)
    f:SetScript("OnEnter", function(self) showLines(self, self.tip, "ANCHOR_BOTTOM") end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    function f:Set(value, sub, sign, tip)
        self.value:SetText(value or "")
        self.sub:SetText(sub or "")
        -- sign: +1 green, -1 red, 0 grey, or an {r, g, b} colour
        local c = type(sign) == "table" and sign
            or (sign or 0) > 0 and ns.GAIN or (sign or 0) < 0 and ns.LOSS or { 0.4, 0.4, 0.45 }
        self.accent:SetColorTexture(c[1], c[2], c[3], 1)
        self.tip = tip
    end
    f:Set()
    return f
end

-- vertical bars around a zero line, green above and red below, with a value axis on the right.
-- SetData({ { value, label, tooltip = lines } }) lays the bars out to fit however many there are.
function ns.CreateBarChart(parent, width, height)
    local AXIS, LABELS = 70, 14
    local plotW, plotH = width - AXIS, height - LABELS
    local chart = CreateFrame("Frame", nil, parent)
    chart:SetSize(width, height)

    local function rule(alpha)
        local t = chart:CreateTexture(nil, "BORDER")
        t:SetColorTexture(1, 1, 1, alpha)
        t:SetHeight(1)
        return t
    end
    local top, mid, bottom, zero = rule(0.07), rule(0.04), rule(0.07), rule(0.35)
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT", -AXIS + 4, 0)
    bottom:SetPoint("BOTTOMLEFT", 0, LABELS)
    bottom:SetPoint("BOTTOMRIGHT", -AXIS + 4, LABELS)
    mid:SetPoint("LEFT", chart, "BOTTOMLEFT", 0, LABELS + plotH / 2)
    mid:SetPoint("RIGHT", chart, "BOTTOMRIGHT", -AXIS + 4, LABELS + plotH / 2)

    local function axisLabel()
        local fs = ns.Label(chart, "GameFontDisableSmall", "", "LEFT")
        fs:SetWidth(AXIS - 8)
        fs:SetWordWrap(false)
        return fs
    end
    local topLabel, zeroLabel, bottomLabel = axisLabel(), axisLabel(), axisLabel()
    topLabel:SetPoint("LEFT", chart, "TOPLEFT", plotW + 8, 0)
    bottomLabel:SetPoint("LEFT", chart, "BOTTOMLEFT", plotW + 8, LABELS)

    chart.empty = ns.Label(chart, "GameFontDisable", "No gold has moved in this period yet.", "CENTER")
    chart.empty:SetPoint("CENTER", chart, "BOTTOMLEFT", plotW / 2, LABELS + plotH / 2)

    chart.bars = {}
    local function bar(i)
        local hit = chart.bars[i]
        if hit then return hit end
        hit = CreateFrame("Frame", nil, chart)
        hit.hl = hit:CreateTexture(nil, "BACKGROUND")
        hit.hl:SetAllPoints()
        hit.hl:SetColorTexture(1, 1, 1, 0.07)
        hit.hl:Hide()
        hit.bar = hit:CreateTexture(nil, "ARTWORK")
        hit.label = ns.Label(chart, "GameFontDisableSmall", nil, "CENTER")
        hit.label:SetPoint("TOP", hit, "BOTTOM", 0, -2)
        hoverable(hit)
        hit:SetScript("OnEnter", function(self)
            self.hl:Show()
            showLines(self, self.tip, "ANCHOR_TOP")
        end)
        hit:SetScript("OnLeave", function(self)
            self.hl:Hide()
            GameTooltip:Hide()
        end)
        chart.bars[i] = hit
        return hit
    end

    function chart:SetData(data)
        local n = #data
        local maxPos, maxNeg, any = 0, 0, false
        for _, d in ipairs(data) do
            if d.value > maxPos then maxPos = d.value end
            if d.value < maxNeg then maxNeg = d.value end
            if d.value ~= 0 then any = true end
        end
        local range = maxPos - maxNeg
        if range <= 0 then range, maxPos = 1, 1 end
        local zeroY = plotH * (-maxNeg / range)
        zero:ClearAllPoints()
        zero:SetPoint("LEFT", chart, "BOTTOMLEFT", 0, LABELS + zeroY)
        zero:SetPoint("RIGHT", chart, "BOTTOMRIGHT", -AXIS + 4, LABELS + zeroY)
        zeroLabel:ClearAllPoints()
        zeroLabel:SetPoint("LEFT", chart, "BOTTOMLEFT", plotW + 8, LABELS + zeroY)
        zeroLabel:SetText("0")
        topLabel:SetText(any and maxPos > 0 and ns.MoneyPL(maxPos) or "")
        bottomLabel:SetText(maxNeg < 0 and ns.MoneyPL(maxNeg) or "")
        -- keep the axis labels from sitting on top of each other
        topLabel:SetShown(plotH - zeroY > 12)
        bottomLabel:SetShown(zeroY > 12)
        self.empty:SetShown(not any)

        local slot = n > 0 and plotW / n or plotW
        local every = math.max(1, math.ceil(n / 15))
        for i = 1, math.max(n, #self.bars) do
            local d = data[i]
            if d then
                local hit = bar(i)
                hit:ClearAllPoints()
                hit:SetPoint("BOTTOMLEFT", chart, "BOTTOMLEFT", (i - 1) * slot, LABELS)
                hit:SetSize(slot, plotH)
                hit.tip = d.tooltip
                -- label the newest bar and every few before it
                hit.label:SetText(((n - i) % every == 0) and (d.label or "") or "")
                hit.bar:ClearAllPoints()
                hit.bar:SetWidth(math.max(1, slot * (slot >= 8 and 0.72 or 0.85)))
                if d.value ~= 0 then
                    hit.bar:SetHeight(math.max(1, plotH * math.abs(d.value) / range))
                    local c = d.value > 0 and ns.GAIN or ns.LOSS
                    hit.bar:SetColorTexture(c[1], c[2], c[3], 0.95)
                    if d.value > 0 then
                        hit.bar:SetPoint("BOTTOM", hit, "BOTTOM", 0, zeroY)
                    else
                        hit.bar:SetPoint("TOP", hit, "BOTTOM", 0, zeroY)
                    end
                    hit.bar:Show()
                else
                    hit.bar:Hide()
                end
                hit:Show()
                hit.label:Show()
            elseif self.bars[i] then
                self.bars[i]:Hide()
                self.bars[i].label:Hide()
            end
        end
    end
    return chart
end

-- horizontal bars from a centre line: gains grow right in green, losses grow left in red.
-- SetData({ { label, value, tooltip = lines } })
function ns.CreateDivergingBars(parent, count, width, rowHeight)
    rowHeight = rowHeight or 16
    local LABEL, VALUE = 112, 78
    local barArea = width - LABEL - VALUE - 8
    local center = LABEL + 4 + barArea / 2
    local list = CreateFrame("Frame", nil, parent)
    list:SetSize(width, count * rowHeight)
    local line = list:CreateTexture(nil, "BORDER")
    line:SetColorTexture(1, 1, 1, 0.3)
    line:SetWidth(1)
    line:SetPoint("TOP", list, "TOPLEFT", center, 0)
    line:SetPoint("BOTTOM", list, "BOTTOMLEFT", center, 0)
    list.empty = ns.Label(list, "GameFontDisable", "Nothing yet.", "CENTER")
    list.empty:SetPoint("TOP", 0, -20)
    list.rows = {}
    for i = 1, count do
        local row = CreateFrame("Frame", nil, list)
        row:SetSize(width, rowHeight)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
        local hl = row:CreateTexture(nil, "BACKGROUND")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.82, 0, 0.1)
        hl:Hide()
        row.label = ns.Label(row, "GameFontHighlightSmall", nil, "LEFT")
        row.label:SetPoint("LEFT", 0, 0)
        row.label:SetWidth(LABEL)
        row.label:SetWordWrap(false)
        row.bar = row:CreateTexture(nil, "ARTWORK")
        row.bar:SetHeight(rowHeight - 5)
        row.value = ns.Label(row, "GameFontHighlightSmall", nil, "RIGHT")
        row.value:SetPoint("RIGHT", 0, 0)
        row.value:SetWidth(VALUE)
        hoverable(row)
        row:SetScript("OnEnter", function(self) hl:Show() showLines(self, self.tip) end)
        row:SetScript("OnLeave", function() hl:Hide() GameTooltip:Hide() end)
        list.rows[i] = row
    end
    function list:SetData(data)
        local max = 0
        for _, d in ipairs(data) do max = math.max(max, math.abs(d.value)) end
        for i, row in ipairs(self.rows) do
            local d = data[i]
            if d then
                row.label:SetText(d.label)
                row.value:SetText(ns.MoneyPL(d.value))
                row.tip = d.tooltip
                local w = max > 0 and math.max(1, (barArea / 2) * math.abs(d.value) / max) or 1
                local c = d.value >= 0 and ns.GAIN or ns.LOSS
                row.bar:ClearAllPoints()
                row.bar:SetWidth(w)
                row.bar:SetColorTexture(c[1], c[2], c[3], 0.95)
                if d.value >= 0 then
                    row.bar:SetPoint("LEFT", row, "LEFT", center, 0)
                else
                    row.bar:SetPoint("RIGHT", row, "LEFT", center, 0)
                end
                row:Show()
            else
                row:Hide()
            end
        end
        self.empty:SetShown(#data == 0)
    end
    return list
end
