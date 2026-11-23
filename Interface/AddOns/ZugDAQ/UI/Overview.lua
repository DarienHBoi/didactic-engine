local _, ns = ...

-- The account page, laid out like a trading account: balance, profit and loss tiles,
-- green/red daily bars, profit and loss by source. Spending on skills and training is
-- kept out of every profit number and shown on its own in the bottom-right box.

local PERIODS = {
    { key = 7, text = "7D", width = 44 },
    { key = 14, text = "14D", width = 44 },
    { key = 30, text = "30D", width = 44 },
    { key = 90, text = "90D", width = 44 },
}
local MAX_SOURCES = 10

local function signOf(v) return v > 0 and 1 or v < 0 and -1 or 0 end

local function pctText(ratio)
    if not ratio then return "" end
    local color = ratio > 0 and "|cff38c75c+" or ratio < 0 and "|cffe64d4d" or "|cffaaaaaa"
    return string.format("%s%.1f%%|r", color, ratio * 100)
end

-- return on the gold you started the period with
local function returnOn(net, startDayKey)
    local start = ns.WealthOn(startDayKey)
    if start and start > 0 then return net / start end
end

local function totalsTip(title, t)
    local tip = { title, { "Earned", ns.Money(t.income) }, { "Spent", ns.Money(t.expense) },
                  { "Profit / loss", ns.MoneyPL(t.net) } }
    if t.skills ~= 0 then
        tip[#tip + 1] = { "|cff8080ffSkills & training|r", ns.Money(t.skills) }
        tip[#tip + 1] = "|cffaaaaaaSkills and training are kept out of profit and loss.|r"
    end
    return tip
end

local function sourceRows(t)
    local rows = {}
    local seen = {}
    local function add(cat)
        if seen[cat] then return end
        seen[cat] = true
        local inc, exp = t.inc[cat] or 0, t.exp[cat] or 0
        if inc ~= 0 or exp ~= 0 then
            rows[#rows + 1] = { cat = cat, inc = inc, exp = exp, value = inc - exp }
        end
    end
    for _, cat in ipairs(ns.CATEGORY_ORDER) do add(cat) end
    for cat in pairs(t.inc) do add(cat) end
    for cat in pairs(t.exp) do add(cat) end

    -- too many to show: keep the biggest movers, fold the rest together
    if #rows > MAX_SOURCES then
        table.sort(rows, function(a, b) return math.abs(a.value) > math.abs(b.value) end)
        local rest = { cat = "Everything else", inc = 0, exp = 0, value = 0 }
        for i = #rows, MAX_SOURCES, -1 do
            local r = table.remove(rows, i)
            rest.inc, rest.exp, rest.value = rest.inc + r.inc, rest.exp + r.exp, rest.value + r.value
        end
        rows[#rows + 1] = rest
    end
    table.sort(rows, function(a, b) return a.value > b.value end)

    for _, r in ipairs(rows) do
        r.label = r.cat
        r.tooltip = { r.cat }
        if r.inc > 0 then r.tooltip[#r.tooltip + 1] = { "Earned", ns.Money(r.inc) } end
        if r.exp > 0 then r.tooltip[#r.tooltip + 1] = { "Spent", ns.Money(r.exp) } end
        r.tooltip[#r.tooltip + 1] = { "Profit / loss", ns.MoneyPL(r.value) }
        if t.income > 0 and r.inc > 0 then
            r.tooltip[#r.tooltip + 1] = { "Share of earnings", ns.Percent(r.inc / t.income) }
        end
    end
    return rows
end

ns.RegisterPage("overview", "Overview", function(page)
    local W = ns.PAGE_WIDTH
    local LEFT_W = 440
    local GAP = 18
    local RIGHT_W = W - LEFT_W - GAP
    local RIGHT_X = LEFT_W + GAP
    page.days = ns.settings.overviewDays or 30
    page.mode = ns.settings.overviewMode or "daily"

    -- ---------------------------------------------------------------- balance header
    local balTitle = ns.Label(page, "GameFontDisableSmall", "ACCOUNT BALANCE  |cff777777(all characters)|r")
    balTitle:SetPoint("TOPLEFT", 0, -2)
    local balance = ns.Label(page, "GameFontNormalHuge", "")
    balance:SetTextColor(1, 1, 1)
    balance:SetPoint("TOPLEFT", 0, -16)

    local worthTitle = ns.Label(page, "GameFontDisableSmall", "NET WORTH  |cff777777(gold + items)|r")
    worthTitle:SetPoint("TOPLEFT", 260, -2)
    local worth = ns.Label(page, "GameFontHighlight", "")
    worth:SetPoint("TOPLEFT", 260, -18)
    local worthSub = ns.Label(page, "GameFontDisableSmall", "")
    worthSub:SetPoint("TOPLEFT", worth, "BOTTOMLEFT", 0, -3)

    local periods = ns.Toggles(page, PERIODS, function(days)
        page.days = days
        ns.settings.overviewDays = days
        page:Refresh()
    end)
    periods.first:SetPoint("TOPRIGHT", page, "TOPRIGHT", -3 * 48, -4)

    -- ---------------------------------------------------------------- tiles
    local TILE_GAP = 8
    local tileW = math.floor((W - 4 * TILE_GAP) / 5)
    local tiles = {}
    local titles = { "TODAY", "PERIOD", "ALL TIME", "GREEN DAYS", "PER HOUR PLAYED" }
    for i, title in ipairs(titles) do
        local t = ns.StatTile(page, tileW, 46, title)
        t:SetPoint("TOPLEFT", (i - 1) * (tileW + TILE_GAP), -50)
        tiles[i] = t
    end

    -- ---------------------------------------------------------------- chart
    local chartTitle = ns.Label(page, "GameFontNormal", "Profit & loss")
    chartTitle:SetPoint("TOPLEFT", 0, -110)
    local modes = ns.Toggles(page, {
        { key = "daily", text = "Daily", width = 66 },
        { key = "running", text = "Running", width = 66 },
    }, function(mode)
        page.mode = mode
        ns.settings.overviewMode = mode
        page:Refresh()
    end)
    modes.first:SetPoint("TOPLEFT", page, "TOPLEFT", LEFT_W - 136, -104)

    local chart = ns.CreateBarChart(page, LEFT_W, 166)
    chart:SetPoint("TOPLEFT", 0, -132)

    -- ---------------------------------------------------------------- by source
    local srcTitle = ns.Label(page, "GameFontNormal", "By source")
    srcTitle:SetPoint("TOPLEFT", RIGHT_X, -110)
    local srcNet = ns.Label(page, "GameFontHighlightSmall", "", "RIGHT")
    srcNet:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -112)
    local sources = ns.CreateDivergingBars(page, MAX_SOURCES, RIGHT_W, 16)
    sources:SetPoint("TOPLEFT", RIGHT_X, -134)

    -- ---------------------------------------------------------------- insights
    local box = CreateFrame("Frame", nil, page, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 0, -308)
    box:SetPoint("BOTTOMRIGHT", page, "BOTTOMLEFT", LEFT_W, 0)
    ns.Backdrop(box, 0.09, 0.09, 0.11, 0.9)
    local insightTitle = ns.Label(box, "GameFontNormal", "What's working, and what to change")
    insightTitle:SetPoint("TOPLEFT", 10, -8)
    local insights = ns.Label(box, "GameFontHighlightSmall", "", "LEFT")
    insights:SetPoint("TOPLEFT", 10, -28)
    insights:SetPoint("BOTTOMRIGHT", -10, 6)
    insights:SetSpacing(4)
    insights:SetJustifyV("TOP")

    -- ---------------------------------------------------------------- skills & training
    local skillBox = CreateFrame("Frame", nil, page, "BackdropTemplate")
    skillBox:SetPoint("TOPLEFT", RIGHT_X, -308)
    skillBox:SetPoint("BOTTOMRIGHT", 0, 0)
    ns.Backdrop(skillBox, 0.09, 0.09, 0.13, 0.9)
    local skillTitle = ns.Label(skillBox, "GameFontNormal", "Skills & training  |cff777777not in profit/loss|r")
    skillTitle:SetPoint("TOPLEFT", 10, -8)
    local skillRows = {}
    for i = 1, 7 do
        local left = ns.Label(skillBox, "GameFontHighlightSmall", "", "LEFT")
        left:SetPoint("TOPLEFT", 10, -28 - (i - 1) * 15)
        left:SetWidth(RIGHT_W - 100)
        left:SetWordWrap(false)
        local right = ns.Label(skillBox, "GameFontHighlightSmall", "", "RIGHT")
        right:SetPoint("TOPRIGHT", -10, -28 - (i - 1) * 15)
        right:SetWidth(80)
        skillRows[i] = { left = left, right = right }
    end

    local function setSkillRows(lines)
        for i, row in ipairs(skillRows) do
            local l = lines[i]
            row.left:SetText(l and l[1] or "")
            row.right:SetText(l and l[2] or "")
        end
    end

    -- ---------------------------------------------------------------- refresh
    function page:Refresh()
        periods:Select(self.days)
        modes:Select(self.mode)
        local now = time()
        local days = self.days
        local keys = ns.LastDays(days)
        local period = ns.Totals(keys)
        local today = ns.Totals({ keys[1] })
        local allKeys = ns.AllDayKeys()
        local all = ns.Totals(allKeys)
        local gold = ns.TotalGold()
        local items, bags, bank = ns.ItemWealth()

        -- header
        balance:SetText(ns.Money(gold))
        worth:SetText(ns.Money(gold + items))
        worthSub:SetText(string.format("items %s  |cff777777(bags %s, banks %s)|r", ns.Money(items), ns.Money(bags), ns.Money(bank)))

        -- one entry per day, oldest first
        local data, running = {}, 0
        local green, red, active = 0, 0, 0
        local best, worst
        for i = days, 1, -1 do
            local key = keys[i]
            local t = ns.Totals({ key })
            running = running + t.net
            if t.income > 0 or t.expense > 0 then
                active = active + 1
                if t.net > 0 then green = green + 1 elseif t.net < 0 then red = red + 1 end
                if not best or t.net > best.net then best = { net = t.net, key = key } end
                if not worst or t.net < worst.net then worst = { net = t.net, key = key } end
            end
            local stamp = now - (i - 1) * 86400
            local tip = totalsTip(date("%A %d %B", stamp), t)
            table.insert(tip, 5, { "Running total", ns.MoneyPL(running) })
            if t.online > 0 then tip[#tip + 1] = { "Played", ns.Duration(t.online) } end
            data[#data + 1] = {
                value = self.mode == "running" and running or t.net,
                label = tostring(tonumber(date("%d", stamp))),
                tooltip = tip,
            }
        end
        chart:SetData(data)
        chartTitle:SetText(self.mode == "running" and "Profit & loss, running total" or "Profit & loss per day")

        -- tiles
        local periodName = string.format("LAST %d DAYS", days)
        tiles[2].title:SetText(periodName)
        tiles[1]:Set(ns.MoneyPL(today.net), pctText(returnOn(today.net, ns.DayKey(now - 86400))),
            signOf(today.net), totalsTip("Today", today))

        local periodTip = totalsTip("Last " .. days .. " days", period)
        if best then periodTip[#periodTip + 1] = { "Best day", ns.MoneyPL(best.net) .. "|cffaaaaaa  " .. best.key .. "|r" } end
        if worst then periodTip[#periodTip + 1] = { "Worst day", ns.MoneyPL(worst.net) .. "|cffaaaaaa  " .. worst.key .. "|r" } end
        periodTip[#periodTip + 1] = "|cffaaaaaaThe % is against the gold you had when the period started.|r"
        tiles[2]:Set(ns.MoneyPL(period.net), pctText(returnOn(period.net, ns.DayKey(now - days * 86400))),
            signOf(period.net), periodTip)

        local since = allKeys[#allKeys]
        tiles[3]:Set(ns.MoneyPL(all.net), since and ("since " .. since) or "",
            signOf(all.net), totalsTip("Since tracking started", all))

        if active > 0 then
            local rate = green / active
            tiles[4]:Set(string.format("%d / %d", green, active), ns.Percent(rate), rate >= 0.5 and 1 or -1, {
                "Days you finished ahead",
                { "|cff38c75cGreen days|r", tostring(green) },
                { "|cffe64d4dRed days|r", tostring(red) },
                { "Days with no change", tostring(active - green - red) },
                "|cffaaaaaaCounts days you played in the last " .. days .. ".|r",
            })
        else
            tiles[4]:Set("|cffaaaaaa-|r", "", 0, { "Days you finished ahead", "No days played in this period yet." })
        end

        local hours = period.online / 3600
        if hours >= 0.5 then
            local rate = period.net / hours
            tiles[5]:Set(ns.MoneyPL(rate), ns.Duration(period.online), signOf(rate),
                { "Profit per hour played", "Over the last " .. days .. " days, all characters.",
                  { "Played", ns.Duration(period.online) } })
        else
            tiles[5]:Set("|cffaaaaaa-|r", "", 0, { "Profit per hour played", "Play at least 30 minutes in this period." })
        end

        -- by source
        sources:SetData(sourceRows(period))
        srcNet:SetText("net " .. ns.MoneyPL(period.net))

        -- skills & training
        local lines = {
            { "Today", ns.Money(today.skills) },
            { "Last " .. days .. " days", ns.Money(period.skills) },
            { "All time", ns.Money(all.skills) },
        }
        local recent = {}
        local log = ns.db.log
        for i = #log, 1, -1 do
            local e = log[i]
            if ns.SKILL_CATEGORIES[e.k] then
                recent[#recent + 1] = e
                if #recent >= 3 then break end
            end
        end
        if #recent > 0 then
            lines[#lines + 1] = { "|cffffd100Recent|r", "" }
            for _, e in ipairs(recent) do
                lines[#lines + 1] = {
                    string.format("|cffaaaaaa%s|r  %s", date("%d %b", e.t), e.d or e.k),
                    ns.Money(math.abs(e.a)),
                }
            end
        else
            lines[#lines + 1] = { "|cffaaaaaaTrainer and recipe purchases show up here.|r", "" }
        end
        setSkillRows(lines)

        -- insights
        local text = {}
        for _, item in ipairs(ns.Insights()) do
            text[#text + 1] = (ns.COLORS[item.kind] or "") .. "- |r" .. item.text
            if #text >= 6 then break end
        end
        insights:SetText(#text > 0 and table.concat(text, "\n") or
            "|cffaaaaaaPlay a bit with ZugDAQ running and tips show up here.|r")
    end
end)
