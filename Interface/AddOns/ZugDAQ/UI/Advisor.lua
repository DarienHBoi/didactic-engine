local _, ns = ...

-- "To do": everything worth doing right now, as plain instructions, best first

local function verbText(a)
    local style = ns.ACTION_STYLE[a.verb]
    return (style and style.color or "") .. a.verb .. "|r"
end

local function tooltip(a, frame)
    local function body(tip)
        tip:AddLine(" ")
        tip:AddLine(a.title, 1, 0.82, 0)
        tip:AddLine(a.detail, 1, 1, 1, true)
        local m = a.material
        if m then
            tip:AddLine(" ")
            tip:AddDoubleLine("Selling them raw", ns.Money(m.raw * m.usable), 1, 1, 1, 1, 1, 1)
            tip:AddDoubleLine("Crafting them", ns.Money(m.best * m.usable), 1, 1, 1, 1, 1, 1)
            tip:AddDoubleLine("Extra gold", ns.MoneyColored(m.totalGain), 1, 1, 1, 1, 1, 1)
        end
        if a.items then
            tip:AddLine(" ")
            for i, b in ipairs(a.items) do
                if i > 20 then tip:AddLine("...", 0.7, 0.7, 0.7) break end
                tip:AddDoubleLine(string.format("%s x%d", ns.ItemLabel(b.itemID, b.name), b.count), ns.Money(b.total),
                    1, 1, 1, 1, 1, 1)
            end
        end
        if a.search or a.recipe then tip:AddLine(" ") end
        if a.search then tip:AddLine("Click: search this on the AH.", 0.6, 0.6, 0.6) end
        if a.recipe then tip:AddLine("Right-click: open the recipe in the profession window.", 0.6, 0.6, 0.6) end
    end
    if a.itemID then
        ns.ItemTooltip(frame, a.itemID, body)
    else
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
        body(GameTooltip)
        GameTooltip:Show()
    end
end

ns.RegisterPage("todo", "To do", function(page)
    local W = ns.PAGE_WIDTH

    local headline = ns.Label(page, "GameFontHighlight", "", "LEFT")
    headline:SetPoint("TOPLEFT", 0, -4)
    headline:SetWidth(W)
    headline:SetSpacing(3)

    local tbl = ns.CreateTable(page, {
        { title = "#", width = 22, align = "RIGHT", text = function(a) return a.rank end, sort = function(a) return a.rank end, defaultAsc = true },
        { title = "Do", width = 55, text = verbText, sort = function(a) return ns.ACTION_STYLE[a.verb].order end, defaultAsc = true },
        { title = "What", width = 230, wrap = true, icon = function(a) return a.itemID and ns.ItemIcon(a.itemID) or 133784 end,
          text = function(a) return a.title end, sort = function(a) return a.title end, defaultAsc = true },
        { title = "How", width = 360, wrap = true, text = function(a) return "|cffcccccc" .. a.detail .. "|r" end },
        { title = "Gold", width = 85, align = "RIGHT", text = function(a) return a.goldText or "" end, sort = function(a) return a.gold end },
    }, {
        rows = 12, rowHeight = 30, sortCol = 1, sortDesc = false,
        empty = "Nothing to do right now. Scan the AH with Auctionator and open your profession window, and this fills in.",
        onEnter = tooltip,
        onClick = function(a, button)
            if button == "RightButton" then
                if a.recipe then ns.OpenRecipe(a.recipe) end
            elseif a.search then
                ns.SearchAH(a.search)
            end
        end,
    })
    tbl:SetPoint("TOPLEFT", 0, -40)
    tbl:SetWidth(W)

    function page:Refresh()
        local actions = ns.Actions()
        tbl:SetData(actions)
        local craft, sell, vendor = 0, 0, 0
        for _, a in ipairs(actions) do
            if a.verb == "CRAFT" then craft = craft + a.gold
            elseif a.verb == "SELL" then sell = sell + a.gold
            elseif a.verb == "VENDOR" then vendor = vendor + a.gold end
        end
        local parts = {}
        if craft > 0 then parts[#parts + 1] = "one of each craft adds " .. ns.MoneyColored(craft) end
        if sell > 0 then parts[#parts + 1] = "AH sales bring about " .. ns.Money(sell) end
        if vendor > 0 then parts[#parts + 1] = "the vendor pays " .. ns.Money(vendor) end
        if #parts > 0 then
            headline:SetText("Work down the list from the top. Doing it all: " .. table.concat(parts, ", ") .. ".")
        else
            headline:SetText("Work down the list from the top.")
        end
    end
end)
