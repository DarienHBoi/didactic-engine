local _, ns = ...

-- Income, styled like a broker's statement:
--   Statement  (Finances > Statement) each source's earned, spent and net, a green/red bar, change
--              against the period before, share and number of transactions. Click a source to see its activity.
--   Activity   (Finances > Activity) the transaction history, IN / OUT / SKILL, filterable.
-- Skills and training are listed in purple and never counted in earned, spent or net.

local PERIODS = {
    { key = 1, text = "1D", width = 44 },
    { key = 7, text = "7D", width = 44 },
    { key = 30, text = "30D", width = 44 },
    { key = 90, text = "90D", width = 44 },
    { key = 0, text = "ALL", width = 44 },
}
local SKILL = { 0.5, 0.5, 1 }
local SKILL_HEX = "|cff8080ff"
local GAIN_HEX, LOSS_HEX, DIM_HEX = "|cff38c75c", "|cffe64d4d", "|cff777777"

-- the `days` days ending `offset` days ago, newest first; days = 0 means all of them
local function periodKeys(days, offset)
    if days == 0 then
        if offset > 0 then return nil end
        return ns.AllDayKeys()
    end
    local keys, now = {}, time()
    for i = offset, offset + days - 1 do keys[#keys + 1] = ns.DayKey(now - i * 86400) end
    return keys
end

local function periodName(days)
    if days == 0 then return "all time" end
    if days == 1 then return "today" end
    return "the last " .. days .. " days"
end

local function prevName(days)
    if days == 1 then return "yesterday" end
    return "the " .. days .. " days before"
end

-- change against the previous period as a coloured %; invert when going up is bad (spending)
local function changeText(cur, prev, invert)
    if prev == nil then return "" end
    if prev == 0 then return cur ~= 0 and (DIM_HEX .. "new|r") or "" end
    local ratio = (cur - prev) / math.abs(prev)
    if math.abs(ratio) < 0.005 then return DIM_HEX .. "0%|r" end
    local good = (ratio > 0) ~= (invert == true)
    local color = good and GAIN_HEX or LOSS_HEX
    if ratio >= 10 then return color .. "+999%|r" end
    return string.format("%s%s%d%%|r", color, ratio > 0 and "+" or "", math.floor(ratio * 100 + 0.5))
end

local function signOf(v) return v > 0 and 1 or v < 0 and -1 or 0 end

local function sideOf(e)
    if ns.SKILL_CATEGORIES[e.k] then return "skill" end
    return e.a > 0 and "in" or "out"
end

local SIDE_TEXT = { ["in"] = GAIN_HEX .. "IN|r", out = LOSS_HEX .. "OUT|r", skill = SKILL_HEX .. "SKILL|r" }

local function amountText(e)
    if ns.SKILL_CATEGORIES[e.k] then return SKILL_HEX .. ns.MoneyPL(e.a):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "|r" end
    return ns.MoneyPL(e.a)
end

ns.RegisterPage("income", "Income", function(page)
    local W = ns.PAGE_WIDTH
    page.days = ns.settings.incomeDays or 30
    page.view = "statement"
    page.filter = "all"
    page.source = nil

    -- ---------------------------------------------------------------- controls
    local periods = ns.Toggles(page, PERIODS, function(days)
        page.days = days
        ns.settings.incomeDays = days
        page:Refresh()
    end)
    periods.first:SetPoint("TOPLEFT", 0, 0)

    local filters = ns.Toggles(page, {
        { key = "all", text = "All", width = 52 },
        { key = "in", text = "In", width = 52 },
        { key = "out", text = "Out", width = 52 },
        { key = "skill", text = "Skills", width = 52 },
    }, function(key) page.filter = key page:Refresh() end)
    filters.first:SetPoint("TOPLEFT", 260, 0)

    -- ---------------------------------------------------------------- tiles
    local TILE_GAP = 8
    local tileW = math.floor((W - 4 * TILE_GAP) / 5)
    local tiles = {}
    for i, title in ipairs({ "EARNED", "SPENT", "NET PROFIT / LOSS", "PER HOUR PLAYED", "SKILLS & TRAINING" }) do
        local t = ns.StatTile(page, tileW, 46, title)
        t:SetPoint("TOPLEFT", (i - 1) * (tileW + TILE_GAP), -32)
        tiles[i] = t
    end

    -- ---------------------------------------------------------------- statement
    local function statementTip(r, frame)
        local tip = { r.cat }
        if r.inc > 0 then tip[#tip + 1] = { "Earned", ns.Money(r.inc) } end
        if r.exp > 0 then tip[#tip + 1] = { "Spent", ns.Money(r.exp) } end
        if r.skill then
            tip[#tip + 1] = SKILL_HEX .. "Spending on skills. Not counted in profit and loss.|r"
        else
            tip[#tip + 1] = { "Profit / loss", ns.MoneyPL(r.net) }
        end
        if r.prev then tip[#tip + 1] = { "In " .. prevName(page.days), ns.MoneyPL(r.prev) } end
        tip[#tip + 1] = { "Transactions", tostring(r.count) }
        if r.top and #r.top > 0 then
            tip[#tip + 1] = " "
            tip[#tip + 1] = "|cffffd100Biggest|r"
            for _, e in ipairs(r.top) do
                tip[#tip + 1] = { string.format("%s%s|r  %s", DIM_HEX, date("%d %b", e.t), e.d or ""), amountText(e) }
            end
        end
        tip[#tip + 1] = " "
        tip[#tip + 1] = DIM_HEX .. "Click to see these transactions.|r"
        ns.ShowLines(frame, tip)
    end

    local statement = ns.CreateTable(page, {
        { title = "Source", width = 150, text = function(r) return r.label end, sort = function(r) return r.cat end, defaultAsc = true },
        { title = "Earned", width = 88, align = "RIGHT",
          text = function(r) return r.inc > 0 and ns.MoneyPL(r.inc) or (DIM_HEX .. "-|r") end, sort = function(r) return r.inc end },
        { title = "Spent", width = 88, align = "RIGHT",
          text = function(r)
              if r.exp <= 0 then return DIM_HEX .. "-|r" end
              return r.skill and (SKILL_HEX .. "-" .. ns.Money(r.exp):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "|r") or ns.MoneyPL(-r.exp)
          end,
          sort = function(r) return r.exp end },
        { title = "Net", width = 92, align = "RIGHT",
          text = function(r) return r.skill and (DIM_HEX .. "separate|r") or ns.MoneyPL(r.net) end,
          sort = function(r) return r.skill and -math.huge or r.net end },
        { title = "", width = 130, bar = function(r) return r.net, r.skill and SKILL or nil end },
        { title = "vs prev", width = 64, align = "RIGHT",
          text = function(r) return changeText(r.net, r.prev) end,
          sort = function(r) return (r.prev and r.prev ~= 0) and (r.net - r.prev) / math.abs(r.prev) or nil end },
        { title = "Share", width = 56, align = "RIGHT",
          text = function(r) return r.share and ns.Percent(r.share) or "" end, sort = function(r) return r.share or 0 end },
        { title = "Txns", width = 40, align = "RIGHT",
          text = function(r) return tostring(r.count) end, sort = function(r) return r.count end },
    }, {
        rows = 17, sortCol = 4, empty = "No gold has moved in this period yet.",
        onEnter = statementTip,
        onClick = function(r)
            page.source = r.cat
            page.filter = "all"
            ns.OpenView("profile", "activity")
        end,
    })
    statement:SetPoint("TOPLEFT", 0, -88)
    statement:SetWidth(W)

    -- ---------------------------------------------------------------- activity
    local activity = ns.CreateTable(page, {
        { title = "When", width = 100, text = function(e) return date("%d %b %H:%M", e.t) end, sort = function(e) return e.t end },
        { title = "Character", width = 90, text = function(e) return (e.c or ""):match("^[^-]+") or "" end,
          sort = function(e) return e.c or "" end, defaultAsc = true },
        { title = "Side", width = 44, text = function(e) return SIDE_TEXT[sideOf(e)] end, sort = sideOf, defaultAsc = true },
        { title = "Source", width = 130, text = function(e) return e.k end, sort = function(e) return e.k end, defaultAsc = true },
        { title = "What", width = 250, text = function(e) return e.d or (DIM_HEX .. "-|r") end,
          sort = function(e) return e.d or "" end, defaultAsc = true },
        { title = "Amount", width = 100, align = "RIGHT", text = amountText, sort = function(e) return e.a end },
    }, { rows = 17, sortCol = 1, empty = "No transactions match." })
    activity:SetPoint("TOPLEFT", 0, -88)
    activity:SetWidth(W)

    local clearSource = ns.Button(page, "", 320, function()
        page.source = nil
        page:Refresh()
    end)
    clearSource:SetPoint("BOTTOMLEFT", 0, 0)

    -- ---------------------------------------------------------------- refresh
    function page:Refresh()
        periods:Select(self.days)
        filters:Select(self.filter)
        local days = self.days
        local keys = periodKeys(days, 0)
        local prevKeys = periodKeys(days, days)
        local totals = ns.Totals(keys)
        local prev = prevKeys and ns.Totals(prevKeys)

        -- transactions in the period, per source
        local inPeriod = {}
        for _, key in ipairs(keys) do inPeriod[key] = true end
        local entries, count, bySource = {}, {}, {}
        for _, e in ipairs(ns.db.log) do
            if inPeriod[ns.DayKey(e.t)] then
                entries[#entries + 1] = e
                count[e.k] = (count[e.k] or 0) + 1
                bySource[e.k] = bySource[e.k] or {}
                table.insert(bySource[e.k], e)
            end
        end
        local function biggest(cat)
            local list = bySource[cat]
            if not list then return nil end
            local copy = {}
            for i, e in ipairs(list) do copy[i] = e end
            table.sort(copy, function(a, b) return math.abs(a.a) > math.abs(b.a) end)
            for i = #copy, 4, -1 do copy[i] = nil end
            return copy
        end

        -- tiles
        local since = days == 0 and ns.AllDayKeys() or nil
        since = since and since[#since]
        local subPrev = function(cur, before, invert)
            if since then return DIM_HEX .. "since " .. since .. "|r" end
            return changeText(cur, before, invert)
        end
        local vsLine = prev and ("Change is against " .. prevName(days) .. ".") or nil

        local function topSources(map, total)
            local list = {}
            for cat, v in pairs(map) do list[#list + 1] = { cat = cat, v = v } end
            table.sort(list, function(a, b) return a.v > b.v end)
            local out = {}
            for i = 1, math.min(4, #list) do
                out[#out + 1] = { list[i].cat, ns.Money(list[i].v) .. DIM_HEX .. "  " .. ns.Percent(total > 0 and list[i].v / total) .. "|r" }
            end
            return out
        end

        local earnedTip = { "Earned in " .. periodName(days) }
        for _, l in ipairs(topSources(totals.inc, totals.income)) do earnedTip[#earnedTip + 1] = l end
        if prev then earnedTip[#earnedTip + 1] = { "In " .. prevName(days), ns.Money(prev.income) } end
        if vsLine then earnedTip[#earnedTip + 1] = DIM_HEX .. vsLine .. "|r" end
        tiles[1]:Set(ns.MoneyPL(totals.income), subPrev(totals.income, prev and prev.income), 1, earnedTip)

        local spentTip = { "Spent in " .. periodName(days) }
        for _, l in ipairs(topSources(totals.exp, totals.expense)) do spentTip[#spentTip + 1] = l end
        if prev then spentTip[#spentTip + 1] = { "In " .. prevName(days), ns.Money(prev.expense) } end
        spentTip[#spentTip + 1] = DIM_HEX .. "Skills and training are not included.|r"
        tiles[2]:Set(ns.MoneyPL(-totals.expense), subPrev(totals.expense, prev and prev.expense, true), -1, spentTip)

        local netTip = { "Profit / loss, " .. periodName(days), { "Earned", ns.Money(totals.income) },
                         { "Spent", ns.Money(totals.expense) }, { "Net", ns.MoneyPL(totals.net) } }
        if prev then netTip[#netTip + 1] = { "In " .. prevName(days), ns.MoneyPL(prev.net) } end
        tiles[3]:Set(ns.MoneyPL(totals.net), subPrev(totals.net, prev and prev.net), signOf(totals.net), netTip)

        local hours = totals.online / 3600
        if hours >= 0.5 then
            local rate = totals.net / hours
            local prevRate = prev and prev.online >= 1800 and prev.net / (prev.online / 3600) or nil
            local tip = { "Profit per hour played", { "Played", ns.Duration(totals.online) } }
            if prevRate then tip[#tip + 1] = { "In " .. prevName(days), ns.MoneyPL(prevRate) .. "/h" } end
            tiles[4]:Set(ns.MoneyPL(rate), since and ns.Duration(totals.online) or changeText(rate, prevRate),
                signOf(rate), tip)
        else
            tiles[4]:Set(DIM_HEX .. "-|r", "", 0, { "Profit per hour played", "Play at least 30 minutes in this period." })
        end

        local skillTip = { "Skills & training, " .. periodName(days) }
        for _, cat in ipairs(ns.SKILL_ORDER) do
            if (totals.skill[cat] or 0) ~= 0 then skillTip[#skillTip + 1] = { cat, ns.Money(totals.skill[cat]) } end
        end
        skillTip[#skillTip + 1] = DIM_HEX .. "Trainers (class skills, professions, riding) and recipes from vendors. Kept out of profit and loss.|r"
        tiles[5]:Set(SKILL_HEX .. ns.Money(totals.skills):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "|r",
            since and "" or changeText(totals.skills, prev and prev.skills, true), SKILL, skillTip)

        -- the visible table
        statement:SetShown(self.view == "statement")
        activity:SetShown(self.view == "log")
        for _, b in pairs(filters.buttons) do b:SetShown(self.view == "log") end

        if self.view == "statement" then
            clearSource:Hide()
            local rows, seen = {}, {}
            local function add(cat)
                if seen[cat] then return end
                seen[cat] = true
                local inc, exp = totals.inc[cat] or 0, totals.exp[cat] or 0
                if inc ~= 0 or exp ~= 0 then
                    local net = inc - exp
                    local share
                    if net >= 0 and totals.income > 0 then share = inc / totals.income
                    elseif net < 0 and totals.expense > 0 then share = exp / totals.expense end
                    rows[#rows + 1] = {
                        cat = cat, label = cat, inc = inc, exp = exp, net = net, share = share,
                        prev = prev and ((prev.inc[cat] or 0) - (prev.exp[cat] or 0)) or nil,
                        count = count[cat] or 0, top = biggest(cat),
                    }
                end
            end
            for _, cat in ipairs(ns.CATEGORY_ORDER) do add(cat) end
            for cat in pairs(totals.inc) do add(cat) end
            for cat in pairs(totals.exp) do add(cat) end
            for _, cat in ipairs(ns.SKILL_ORDER) do
                local spent = totals.skill[cat] or 0
                if spent ~= 0 then
                    rows[#rows + 1] = {
                        cat = cat, label = SKILL_HEX .. cat .. "|r", skill = true, inc = 0, exp = spent, net = -spent,
                        prev = prev and -(prev.skill[cat] or 0) or nil, count = count[cat] or 0, top = biggest(cat),
                    }
                end
            end
            statement:SetData(rows)
        else
            local rows = {}
            for _, e in ipairs(entries) do
                if (not self.source or e.k == self.source)
                    and (self.filter == "all" or sideOf(e) == self.filter) then
                    rows[#rows + 1] = e
                end
            end
            activity:SetData(rows)
            if self.source then
                clearSource:SetText("Showing " .. self.source .. " only  (show all)")
                clearSource:Show()
            else
                clearSource:Hide()
            end
        end
    end
end)
