local _, ns = ...

-- "From the app": what the ZugDAQ desktop app sent the game, as of its last write (/reload picks up a newer one).
--   plan   the crafting plan open in the app, step by step
--   shop   that plan's shopping list
--   sell   what the app says to sell, with when the AH buys most
--   deals  listings worth buying in the latest AH snapshot
--   trade  guild trade matches (when sharing is on in the app)
--   guild  everyone on the app's guild board
-- Each shows under the main tab it belongs to (see UI\Main.lua).

local KIND = {
    vendor = "|cff40ff40VENDOR|r", under = "|cff66bbffUNDERPRICED|r", thin = "|cffffd200THIN|r",
}

local function nameOf(id, fallback) return ns.ItemLabel(id, fallback) end

local function searchItem(id, fallback)
    local name = id and (ns.GetItemInfo(id)) or fallback
    if name then ns.SearchAH({ name }) end
end

ns.RegisterPage("app", "From the app", function(page)
    local W = ns.PAGE_WIDTH

    local headline = ns.Label(page, "GameFontHighlight", "", "LEFT")
    headline:SetPoint("TOPLEFT", 0, -4)
    headline:SetWidth(W)
    headline:SetSpacing(3)

    local tables = {}
    local function add(view, columns, opts)
        local t = ns.CreateTable(page, columns, opts)
        t:SetPoint("TOPLEFT", 0, -44)
        t:SetWidth(W)
        tables[view] = t
        return t
    end
    local function itemTip(row, frame, lines)
        ns.ItemTooltip(frame, row.id, function(tip)
            if lines then
                tip:AddLine(" ")
                for _, l in ipairs(lines) do tip:AddLine(l, 1, 1, 1, true) end
            end
            tip:AddLine(" ")
            tip:AddLine("Click: search it on the AH.", 0.6, 0.6, 0.6)
        end)
    end

    add("plan", {
        { title = "Skill", width = 70, text = function(s) return string.format("%d-%d", s.from or 0, s.to or 0) end },
        { title = "Craft", width = 330, icon = function(s) return ns.ItemIcon(s.id) end,
          text = function(s) return string.format("%dx %s", s.crafts or 0, s.name or nameOf(s.id)) end },
        { title = "Learn first", width = 360, wrap = true, text = function(s) return s.learn and ("|cff66bbff" .. s.learn .. "|r") or "" end },
    }, {
        rows = 13, rowHeight = 30, empty = "No plan sent. Open a profession plan in the ZugDAQ app and it shows here after a /reload.",
        onEnter = function(s, frame) itemTip(s, frame) end,
        onClick = function(s) searchItem(s.id, s.name) end,
    })

    add("shop", {
        { title = "Mat", width = 300, icon = function(l) return ns.ItemIcon(l.id) end, text = function(l) return nameOf(l.id) end },
        { title = "Buy", width = 60, align = "RIGHT", text = function(l) return tostring(l.buy or 0) end, sort = function(l) return l.buy or 0 end },
        { title = "Have", width = 60, align = "RIGHT", text = function(l) return tostring(l.have or 0) end },
        { title = "Each", width = 90, align = "RIGHT", text = function(l) return ns.Money(l.each or 0) end },
        { title = "Where", width = 230, text = function(l) return "|cffcccccc" .. (l.where or "") .. "|r" end },
    }, {
        rows = 18, sortCol = 2, empty = "Nothing to buy for the plan sent from the app.",
        onEnter = function(l, frame) itemTip(l, frame) end,
        onClick = function(l) searchItem(l.id) end,
    })

    add("sell", {
        { title = "Item", width = 250, icon = function(o) return ns.ItemIcon(o.id) end, text = function(o) return o.title or nameOf(o.id) end },
        { title = "Why", width = 420, wrap = true, text = function(o) return "|cffcccccc" .. (o.detail or "") .. "|r" end },
        { title = "Gold", width = 85, align = "RIGHT", text = function(o) return ns.Money(o.gold or 0) end, sort = function(o) return o.gold or 0 end },
    }, {
        rows = 12, rowHeight = 32, sortCol = 3, empty = "Nothing for the app to sell right now.",
        onEnter = function(o, frame) itemTip(o, frame) end,
        onClick = function(o) searchItem(o.id) end,
    })

    add("deals", {
        { title = "Kind", width = 90, text = function(d) return KIND[d.kind] or d.kind or "" end },
        { title = "Item", width = 230, icon = function(d) return ns.ItemIcon(d.id) end, text = function(d) return nameOf(d.id) end },
        { title = "Buy", width = 60, align = "RIGHT", text = function(d) return tostring(d.units or 0) end },
        { title = "Up to", width = 90, align = "RIGHT", text = function(d) return ns.Money(d.max or 0) end },
        { title = "Costs", width = 90, align = "RIGHT", text = function(d) return ns.Money(d.cost or 0) end },
        { title = "Resell each", width = 90, align = "RIGHT", text = function(d) return ns.Money(d.resell or 0) end },
        { title = "Profit", width = 85, align = "RIGHT", text = function(d) return ns.MoneyColored(d.profit or 0) end, sort = function(d) return d.profit or 0 end },
    }, {
        rows = 18, sortCol = 7, empty = "No deals in the app's latest snapshot.",
        onEnter = function(d, frame)
            local how = d.kind == "vendor" and "Sell them to any vendor."
                or d.kind == "thin" and "Buy them all and relist near the week's high. Risky: someone can list more."
                or "Relist near the usual price."
            itemTip(d, frame, { string.format("Buy %d at up to %s each, %s in all.", d.units or 0, ns.Money(d.max or 0), ns.Money(d.cost or 0)), how,
                "The snapshot is up to an hour old: some may be gone." })
        end,
        onClick = function(d) searchItem(d.id) end,
    })

    add("trade", {
        { title = "", width = 90, text = function(t) return t.give and "|cff40ff40THEY NEED|r" or "|cff66bbffTHEY HAVE|r" end },
        { title = "Item", width = 260, icon = function(t) return ns.ItemIcon(t.id) end, text = function(t) return nameOf(t.id) end },
        { title = "Guildmate", width = 160, text = function(t) return t.who or "" end },
        { title = "Count", width = 70, align = "RIGHT", text = function(t) return tostring(t.count or 0) end, sort = function(t) return t.count or 0 end },
        { title = "", width = 170, text = function(t) return t.give and "|cffccccccmail them yours|r" or "|cffccccccask before buying|r" end },
    }, {
        rows = 18, sortCol = 4, empty = "No guild trade matches. Turn on Guild Trade in the app's Guild tab.",
        onEnter = function(t, frame) itemTip(t, frame) end,
    })

    local function classColored(text, class)
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        return c and c.colorStr and ("|c" .. c.colorStr .. text .. "|r") or text
    end
    local function ago(t)
        if not t then return "" end
        local mins = math.floor((time() - t) / 60)
        if mins < 15 then return "|cff40ff40on now|r" end
        if mins < 60 then return mins .. "m ago" end
        if mins < 48 * 60 then return math.floor(mins / 60) .. "h ago" end
        return math.floor(mins / 1440) .. "d ago"
    end

    add("guild", {
        { title = "Name", width = 140, text = function(m)
            return classColored(m.name or "?", m.class) .. (m.you and " |cff40ff40(you)|r" or "") end },
        { title = "Character", width = 210, text = function(m)
            local cls = m.class and (m.class:sub(1, 1) .. m.class:sub(2):lower()) or ""
            local line = ((m.level and (m.level .. " ") or "") .. (m.race or "") .. " " .. cls):gsub("^%s+", "")
            if m.guild and m.guild ~= "" then line = line .. " |cffaaaaaa<" .. m.guild .. ">|r" end
            return line end },
        { title = "Professions", width = 190, wrap = true, text = function(m) return "|cffcccccc" .. (m.profs or "") .. "|r" end },
        { title = "This week", width = 90, align = "RIGHT", text = function(m) return ns.MoneyColored(m.week or 0) end,
          sort = function(m) return m.week or 0 end },
        { title = "Today", width = 80, align = "RIGHT", text = function(m) return ns.MoneyColored(m.today or 0) end,
          sort = function(m) return m.today or 0 end },
        { title = "Seen", width = 70, align = "RIGHT", text = function(m) return ago(m.seen) end, sort = function(m) return m.seen or 0 end },
    }, {
        rows = 13, rowHeight = 30, sortCol = 4,
        empty = "Nobody yet. The ZugDAQ app joins its guild board by itself when it's connected to the guild's server.",
    })

    function page:Refresh()
        local d = ns.AppData()
        local view = self.view or "plan"
        for key, t in pairs(tables) do t:SetShown(key == view) end
        if not d then
            headline:SetText("Nothing from the ZugDAQ app yet. Run the app with this addon installed, then /reload: "
                .. "it sends its market prices, plans, deals and what to sell.")
            tables[view]:SetData({})
            return
        end
        local age = "|cffaaaaaaSent " .. (ns.AppAge() or "?") .. ". /reload for the latest.|r"
        if view == "plan" then
            local plan = d.plan
            headline:SetText((plan and plan.title and ("|cffffd700" .. plan.title .. "|r  ") or "") .. age)
            tables.plan:SetData(plan and plan.steps or {})
        elseif view == "shop" then
            local plan = d.plan
            local total = 0
            for _, l in ipairs(plan and plan.shop or {}) do total = total + (l.buy or 0) * (l.each or 0) end
            headline:SetText(string.format("For %s: about %s to buy.  ", plan and plan.title or "the plan", ns.Money(total)) .. age)
            tables.shop:SetData(plan and plan.shop or {})
        elseif view == "sell" then
            local when = d.bestHour and string.format("The AH buys most from %02d:00 to %02d:00: post just before. ", d.bestHour, (d.bestHour + 3) % 24) or ""
            headline:SetText(when .. age)
            tables.sell:SetData(d.sell or {})
        elseif view == "deals" then
            local total = 0
            for _, deal in ipairs(d.deals or {}) do total = total + (deal.profit or 0) end
            headline:SetText(string.format("%d deals worth about %s in the snapshot from %s.  ", #(d.deals or {}), ns.Money(total),
                d.snapshot and date("%H:%M", d.snapshot) or "?") .. age)
            tables.deals:SetData(d.deals or {})
        elseif view == "guild" then
            local members, on = d.guild or {}, 0
            for _, m in ipairs(members) do
                if m.seen and time() - m.seen < 15 * 60 then on = on + 1 end
            end
            headline:SetText(string.format("%d in the guild using ZugDAQ, %d with it open.  ", #members, on) .. age)
            tables.guild:SetData(members)
        else
            headline:SetText(age)
            tables.trade:SetData(d.trade or {})
        end
    end
end)
