local _, S = ...
S.UI = S.UI or {}

local STACK = 20
local MAX_REAGENTS = 5
local GOLD = "|cffffd100"
local GREEN = "|cff40ff40"
local RED = "|cffff4040"

local function label(parent, text, x, y, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function wrapped(parent, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetWidth(368)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    return fs
end

local function button(parent, text, w, x, y, h, primary)
    local b = S.UI.button(parent, text, w, h or 26, primary)
    b:SetPoint("TOPLEFT", x, y)
    return b
end

-- Right pane. hooks: cost(r), margin(r), setMargin(r, m|nil), preview(r, mode), send(r, mode),
-- logSale(r, copper), toggleFav(r), status(msg), canSend()
function S.UI.buildDetail(pane, hooks)
    local d = { pane = pane }

    d.content = CreateFrame("Frame", nil, pane)
    d.content:SetAllPoints()
    local c = d.content

    d.icon = c:CreateTexture(nil, "ARTWORK")
    d.icon:SetSize(40, 40)
    d.icon:SetPoint("TOPLEFT", 12, -10)
    d.name = c:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    d.name:SetPoint("TOPLEFT", 60, -12)
    d.name:SetWidth(290)
    d.name:SetJustifyH("LEFT")
    d.name:SetWordWrap(false)
    d.cat = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d.cat:SetPoint("TOPLEFT", 60, -32)
    d.star = CreateFrame("Button", nil, c)
    d.star:SetSize(24, 24)
    d.star:SetPoint("TOPRIGHT", -10, -10)
    d.star.label = d.star:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    d.star.label:SetPoint("CENTER", 0, -4)
    d.star.label:SetText("*")
    d.star:SetScript("OnClick", function() if d.recipe then hooks.toggleFav(d.recipe) end end)

    -- Reagent table
    label(c, "Reagent", 38, -60)
    label(c, "Each", 192, -60)
    label(c, "Line", 256, -60)
    label(c, "Stack of " .. STACK, 320, -60)
    d.reagents = {}
    for i = 1, MAX_REAGENTS do
        local r = S.UI.newReagent(c)
        r:SetPoint("TOPLEFT", 0, -74 - (i - 1) * S.UI.REAG_H)
        d.reagents[i] = r
    end
    d.more = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    d.more:SetPoint("TOPLEFT", 38, -74 - MAX_REAGENTS * S.UI.REAG_H)

    -- Everything below the reagent rows moves up when an enchant has fewer than the maximum rows.
    local lower = CreateFrame("Frame", nil, c)
    lower:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
    lower:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 0)
    d.lower = lower

    -- Totals
    d.totals = lower:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    d.totals:SetPoint("TOPLEFT", 12, -196)
    d.totals:SetWidth(368)
    d.totals:SetJustifyH("LEFT")
    d.totals:SetSpacing(3)
    d.stockLine = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d.stockLine:SetPoint("TOPLEFT", 60, -46)
    d.stockLine:SetWidth(310)
    d.stockLine:SetJustifyH("LEFT")

    -- Margin slider + number box
    label(lower, "Margin %", 12, -268, "GameFontNormal")
    d.slider = nil
    local ok, slider = pcall(CreateFrame, "Slider", nil, lower, "OptionsSliderTemplate")
    if ok and slider then
        d.slider = slider
        slider:SetPoint("TOPLEFT", 84, -270)
        slider:SetSize(150, 16)
        slider:SetMinMaxValues(0, 100)
        slider:SetValueStep(1)
        if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
        for _, k in ipairs({ "Text", "Low", "High" }) do
            if slider[k] then slider[k]:SetText("") end
        end
        slider:SetScript("OnValueChanged", function(_, v)
            if d.busy or not d.recipe then return end
            hooks.setMargin(d.recipe, math.floor(v + 0.5))
        end)
    end
    d.margin = CreateFrame("EditBox", nil, lower, "InputBoxTemplate")
    d.margin:SetSize(40, 20)
    d.margin:SetPoint("TOPLEFT", 250, -266)
    d.margin:SetAutoFocus(false)
    d.margin:SetMaxLetters(5)
    d.margin:SetScript("OnEnterPressed", function(self)
        if not d.recipe then return end
        local txt = self:GetText()
        if txt == nil or txt == "" then
            hooks.setMargin(d.recipe, nil)
        else
            local m = S.Pricing.parseMargin(txt)
            if m == nil then hooks.status("Margin must be a plain number like 15 or 12.5.") else hooks.setMargin(d.recipe, m) end
        end
        self:ClearFocus()
    end)
    d.reset = button(lower, "Default", 58, 296, -264, 24)
    d.reset:SetScript("OnClick", function() if d.recipe then hooks.setMargin(d.recipe, nil) end end)

    -- Ad previews (exactly what will post)
    label(lower, "Ad: mats included", 12, -298)
    d.adMats = wrapped(lower, 12, -312)
    label(lower, "Ad: you bring the mats", 12, -358)
    d.adByo = wrapped(lower, 12, -372)

    d.sendMats = button(lower, "Use: Mats incl.", 180, 12, -402, 36, true)
    d.sendByo = button(lower, "Use: You bring", 180, 198, -402, 36, true)
    d.sendMats:SetScript("OnClick", function() if d.recipe then hooks.send(d.recipe, "mats") end end)
    d.sendByo:SetScript("OnClick", function() if d.recipe then hooks.send(d.recipe, "byo") end end)

    -- Sales log (sales are logged from the Customers tab)
    label(lower, "Stats in ad:", 12, -452)
    d.stats = CreateFrame("EditBox", nil, lower, "InputBoxTemplate")
    d.stats:SetSize(210, 20)
    d.stats:SetPoint("TOPLEFT", 92, -448)
    d.stats:SetAutoFocus(false)
    d.stats:SetMaxLetters(40)
    d.stats:SetScript("OnEnterPressed", function(self)
        if d.recipe and hooks.setStats then hooks.setStats(d.recipe, self:GetText()) end
        self:ClearFocus()
    end)
    d.stats:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    d.statsHint = lower:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    d.statsHint:SetPoint("LEFT", d.stats, "RIGHT", 6, 0)
    d.statsHint:SetText("Enter to save")
    d.recent = wrapped(lower, 12, -476)

    d.empty = pane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    d.empty:SetPoint("CENTER")
    d.empty:SetText("Pick an enchant on the left")

    -- Redraws everything for one recipe (nil clears the pane).
    function d.update(recipe)
        local prev = d.recipe
        d.recipe = recipe
        c:SetShown(recipe ~= nil)
        d.empty:SetShown(recipe == nil)
        if not recipe then return end
        d.busy = true
        local cst = hooks.cost(recipe)
        local m = hooks.margin(recipe)
        local ask = S.Pricing.suggest(cst, m)
        local labour = S.Pricing.labour(cst, m)
        d.ask = ask
        d.icon:SetTexture(recipe.icon or S.UI.QUESTION)
        d.name:SetText(recipe.name)
        d.cat:SetText(recipe.category or "")
        if S.DB.char.favourites[recipe.key] then d.star.label:SetTextColor(1, 0.82, 0) else d.star.label:SetTextColor(0.4, 0.4, 0.4) end

        local b = S.Breakdown.compute(recipe, S.Prices.lookup, STACK)
        local stock = hooks.stock and hooks.stock(recipe) or { lines = {}, missing = {} }
        for i = 1, MAX_REAGENTS do
            local row, l = d.reagents[i], b.lines[i]
            if l then
                row.itemID = l.itemID or nil
                row.icon:SetTexture(S.UI.itemIcon(l.itemID))
                local live = l.itemID and C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(l.itemID)
                local sl = stock.lines[i]
                local tag = ""
                if sl and sl.have then
                    tag = (sl.ok and "|cff40ff40" or "|cffff5050") .. sl.have .. "/" .. sl.need .. "|r  "
                end
                row.name:SetText(tag .. (live or l.name))
                row.unit:SetText(S.Money.format(l.unit))
                row.line:SetText(S.Money.format(l.line))
                row.stack:SetText(S.Money.format(l.stack))
                row:Show()
            else
                row:Hide()
            end
        end
        local shown = math.min(#b.lines, MAX_REAGENTS)
        d.lower:ClearAllPoints()
        d.lower:SetPoint("TOPLEFT", c, "TOPLEFT", 0, (MAX_REAGENTS - shown) * S.UI.REAG_H)
        d.lower:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 0)
        d.more:SetText(#b.lines > MAX_REAGENTS and ("+ " .. (#b.lines - MAX_REAGENTS) .. " more reagents (totals include them)") or "")

        local profit = S.Profit.of(ask, cst.copper)
        local real = S.Profit.marginFromAsk(ask, cst.copper)
        local pcol = (profit and profit < 0) and RED or GREEN
        if d.stats and not (d.stats.HasFocus and d.stats:HasFocus()) then d.stats:SetText((hooks.stats and hooks.stats(recipe)) or "") end
        d.stockLine:SetText((stock.craftable == nil and "|cff999999Stock unknown|r"
                or (stock.craftable > 0 and ("You have:  |cff40ff40enough for " .. stock.craftable .. "|r")
                or ("You have:  |cffff5050missing " .. table.concat((function()
                    local t = {}
                    for _, m in ipairs(stock.missing) do t[#t + 1] = m.short .. " " .. (b.lines[m.index] and b.lines[m.index].name or "?") end
                    return t
                end)(), ", ") .. "|r"))))
        d.totals:SetText(table.concat({
            "Mats cost:  " .. GOLD .. S.Money.format(cst.copper) .. "|r" .. (cst.state == "stale" and "  |cffff8800(old prices)|r" or ""),
            "Ask, mats included:  " .. GOLD .. S.Money.format(ask) .. "|r",
            "Ask, you bring mats:  " .. GOLD .. S.Money.format(labour) .. "|r",
            "Profit:  " .. pcol .. S.UI.signedMoney(profit) .. "|r" .. (real and ("   (" .. real .. "% over mats)") or ""),
        }, "\n"))

        if not (d.margin.HasFocus and d.margin:HasFocus()) then d.margin:SetText(tostring(m)) end
        if d.slider then d.slider:SetValue(math.min(100, math.max(0, m))) end

        local function show(fs, mode)
            local text, err = hooks.preview(recipe, mode)
            if text then
                fs:SetText(text .. "  |cff888888(" .. #text .. "/255)|r")
            else
                fs:SetText(RED .. err .. "|r")
            end
        end
        show(d.adMats, "mats")
        show(d.adByo, "byo")
        local can = hooks.canSend()
        local verb = S.DB.global.editFirst and "Use: " or "Post: "
        d.sendMats:SetText(verb .. "Mats incl.")
        d.sendByo:SetText(verb .. "You bring")
        d.sendMats:SetEnabled(can and ask ~= nil)
        d.sendByo:SetEnabled(can and labour ~= nil)

        local sales = S.DB.char.sales[recipe.key]
        local recent = S.Sales.recent(sales, 5)
        if #recent == 0 then
            d.recent:SetText("No sales logged yet. Sales you log from the Customers tab show here.")
        else
            local parts = {}
            for _, s in ipairs(recent) do parts[#parts + 1] = S.Money.format(s.copper) end
            d.recent:SetText("Recent: " .. table.concat(parts, ", ") .. "\nMedian of " .. #sales .. " sales: "
                .. GOLD .. S.Money.format(S.Sales.median(sales)) .. "|r   (suggested ask " .. S.Money.format(ask) .. ")")
        end
        d.busy = false
    end

    return d
end
