local _, ns = ...

-- Crafting > Sales plan: plan getting something onto the AH, step by step, and tick the steps off as you go.
--   In game     pick an item (recently checked on the AH first, then what you can craft; type to search), how many,
--               and make the plan from the AH as it is now. Check AH prices first so buying is costed listing by
--               listing (see Planner.lua).
--   From the app  the plan made on the app's Desk tab (Send to game, then /reload).

local STEP = {
    COLLECT = "|cff66bbffCOLLECT|r", BUY = "|cffff8000BUY|r", CRAFT = "|cffffd200CRAFT|r", POST = "|cff40ff40POST|r",
}
local DONE = "|TInterface\\RaidFrame\\ReadyCheck-Ready:16|t"

local function nameOf(id) return ns.ItemName(id) or ("item " .. tostring(id)) end

-- which steps are ticked, per plan (a new plan starts clean)
local function doneFor(store, made)
    if not made then return {} end
    local done = ns.db[store]
    if not done or done.made ~= made then
        done = { made = made }
        ns.db[store] = done
    end
    return done
end

-- every word typed has to be in the name, in any order
local function matches(query, text)
    text = text:lower()
    for word in query:lower():gmatch("%S+") do
        if not text:find(word, 1, true) then return false end
    end
    return true
end

ns.RegisterPage("planner", "Sales plan", function(page)
    local W = ns.PAGE_WIDTH
    local mode = "game"
    local chosen, qty, useStock = nil, 1, true

    -- ---------------------------------------------------------------- top row: whose plan
    local toggles = ns.Toggles(page, {
        { key = "game", text = "Plan in game", width = 110 },
        { key = "app", text = "From the app", width = 110 },
    }, function(key) mode = key page:Refresh() end)
    toggles.first:SetPoint("TOPRIGHT", page, "TOPRIGHT", -114, -2)
    toggles:Select("game")

    -- ---------------------------------------------------------------- picking the item (in game)
    local search = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    search:SetSize(230, 20)
    search:SetPoint("TOPLEFT", 6, -4)
    search:SetAutoFocus(false)
    local placeholder = ns.Label(search, "GameFontDisableSmall", "Search items...")
    placeholder:SetPoint("LEFT", 2, 0)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    search:SetScript("OnTextChanged", function(self)
        placeholder:SetShown(self:GetText() == "")
        page:Refresh()
    end)

    local howMany = ns.Label(page, "GameFontNormal", "How many", "LEFT")
    howMany:SetPoint("LEFT", search, "RIGHT", 14, 0)
    local count = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    count:SetSize(44, 20)
    count:SetPoint("LEFT", howMany, "RIGHT", 8, 0)
    count:SetAutoFocus(false)
    count:SetNumeric(true)
    count:SetText("1")
    count:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    count:SetScript("OnTextChanged", function(self) qty = math.max(1, tonumber(self:GetText()) or 1) end)

    local stockBox = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    stockBox:SetSize(24, 24)
    stockBox:SetPoint("LEFT", count, "RIGHT", 10, 0)
    stockBox:SetChecked(true)
    stockBox:SetScript("OnClick", function(self) useStock = self:GetChecked() and true or false end)
    local stockLabel = ns.Label(page, "GameFontHighlightSmall", "Use what I hold", "LEFT")
    stockLabel:SetPoint("LEFT", stockBox, "RIGHT", 0, 0)

    local status = ns.Label(page, "GameFontHighlightSmall", "", "LEFT")

    local checkBtn = ns.Button(page, "Check AH prices", 120, function()
        if not chosen then status:SetText("|cffff8080Pick an item first.|r") return end
        if not ns.InContext("auction") then status:SetText("|cffff8080Open the Auction House to check prices.|r") return end
        local items = ns.SalePlanCheckItems(chosen)
        status:SetText(string.format("Checking %d item%s on the AH...", #items, #items == 1 and "" or "s"))
        ns.CheckPrices(items, function()
            status:SetText("Prices checked: buying is costed listing by listing.")
            page:Refresh()
        end)
    end)
    checkBtn:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -6, -8)
    local makeBtn = ns.Button(page, "Make plan", 100, function()
        if not chosen then status:SetText("|cffff8080Pick an item first.|r") return end
        ns.db.gamePlan = ns.MakeSalePlan(chosen, qty, useStock)
        status:SetText("")
        page:Refresh()
    end)
    makeBtn:SetPoint("LEFT", checkBtn, "RIGHT", 6, 0)
    status:SetPoint("LEFT", makeBtn, "RIGHT", 10, 0)
    status:SetWidth(W - 260)

    local picker = ns.CreateTable(page, {
        { title = "Item", width = 330, icon = function(r) return ns.ItemIcon(r.id) end, text = function(r)
              local label = ns.ItemLabel(r.id, r.name)
              return r.id == chosen and ("|cff40ff40> |r" .. label) or label
          end, sort = function(r) return r.name or "" end },
        { title = "Why", width = 170, text = function(r) return "|cffcccccc" .. (r.why or "") .. "|r" end },
        { title = "Lowest", width = 90, align = "RIGHT", text = function(r) return r.low and ns.Money(r.low) or "" end,
          sort = function(r) return r.low or 0 end },
        { title = "Listed", width = 60, align = "RIGHT", text = function(r) return r.listed and tostring(r.listed) or "" end,
          sort = function(r) return r.listed or 0 end },
        { title = "Checked", width = 90, align = "RIGHT", text = function(r) return r.age and ns.AgeColored(r.age) or "|cff777777-|r" end,
          sort = function(r) return -(r.age or 1e9) end },
    }, {
        rows = 5, empty = "Nothing checked on the AH lately, and no recipes found. Type to search, or open the AH and check some prices.",
        onEnter = function(r, frame) ns.ItemTooltip(frame, r.id) end,
        onClick = function(r)
            chosen = r.id
            page:Refresh()
        end,
    })
    picker:SetPoint("TOPLEFT", checkBtn, "BOTTOMLEFT", 6, -8)
    picker:SetWidth(W)

    -- ---------------------------------------------------------------- the steps (both views)
    local headline = ns.Label(page, "GameFontHighlight", "", "LEFT")
    headline:SetWidth(W)
    headline:SetSpacing(2)

    local function stepsTable(rows, anchorY)
        local t = ns.CreateTable(page, {
            { title = "", width = 34, align = "CENTER", text = function(s) return s.done and DONE or ("|cffffd200" .. s.n .. "|r") end },
            { title = "Step", width = 320, wrap = true, icon = function(s) return s.id and ns.ItemIcon(s.id) or nil end,
              text = function(s) return s.done and ("|cff888888" .. (s.t or "") .. "|r") or ((STEP[s.k] or s.k or "") .. "  " .. (s.t or "")) end },
            { title = "How", width = 340, wrap = true, text = function(s) return "|cffcccccc" .. (s.d or "") .. "|r" end },
            { title = "Gold", width = 80, align = "RIGHT", text = function(s) return (s.g or 0) ~= 0 and ns.Money(s.g) or "" end },
        }, {
            rows = rows, rowHeight = 40,
            empty = "No plan yet.",
            onEnter = function(s, frame)
                if s.id then
                    ns.ItemTooltip(frame, s.id, function(tip) tip:AddLine(" ") tip:AddLine("Click: mark this step done (or not).", 0.6, 0.6, 0.6) end)
                end
            end,
            onClick = function(s)
                local done = s.store and doneFor(s.store, s.made) or {}
                done[s.n] = not done[s.n] or nil
                page:Refresh()
            end,
        })
        t:SetWidth(W)
        return t
    end
    local gameSteps = stepsTable(4)
    local appSteps = stepsTable(8)

    -- ---------------------------------------------------------------- the item list for the picker
    local function pickerRows()
        local query = search:GetText() or ""
        local rows, seen = {}, {}
        local function add(id, why)
            if not id or seen[id] then return end
            local n = nameOf(id)
            if query ~= "" and not matches(query, n) then return end
            seen[id] = true
            local live = ns.LiveListings(id)
            rows[#rows + 1] = { id = id, name = n, why = why, age = ns.PriceAge(id),
                                low = (live and live.listings[1] and live.listings[1].price) or ns.AuctionPrice(id),
                                listed = live and live.total or nil }
        end
        -- recently checked on the AH first (newest first), then what the account can craft, then (searching) anything priced
        local recent = {}
        for id, entry in pairs(ns.db.live or {}) do recent[#recent + 1] = { id = id, t = entry.t or 0, by = entry.by } end
        table.sort(recent, function(a, b) return a.t > b.t end)
        for _, r in ipairs(recent) do add(r.id, r.by and ("checked by " .. r.by) or "you checked it") end
        for id, makers in pairs(ns.AccountRecipes()) do add(id, (makers[1] and makers[1].crafter or "you") .. " crafts it") end
        if query ~= "" then
            for id in pairs(ns.db.priceSeen or {}) do add(id, "seen on the AH") end
            local d = ns.AppData()
            for id in pairs(d and d.prices or {}) do
                if #rows >= 200 then break end
                add(id, "on the AH")
            end
        end
        return rows
    end

    local function stepRows(plan, store)
        local rows = {}
        if not plan then return rows end
        local done = doneFor(store, plan.made)
        for i, s in ipairs(plan.steps or {}) do
            rows[#rows + 1] = { n = i, k = s.k, t = s.t, d = s.d, g = s.g, id = s.id, done = done[i] and true or false,
                                store = store, made = plan.made }
        end
        return rows
    end

    local function summary(plan, rows)
        local left = 0
        for _, r in ipairs(rows) do if not r.done then left = left + 1 end end
        local profit = (plan.revenue or 0) - (plan.spend or 0)
        local text = string.format("|cffffd700Sell %d %s at %s|r: spend %s, brings in %s, profit %s.  %s",
            plan.qty or 0, nameOf(plan.id), ns.Money(plan.price or 0), ns.Money(plan.spend or 0), ns.Money(plan.revenue or 0),
            ns.MoneyColored and ns.MoneyColored(profit) or ns.Money(profit),
            left == 0 and "|cff40ff40All done!|r" or string.format("%d step%s to go: click one when it's done.", left, left == 1 and "" or "s"))
        if plan.warnings and #plan.warnings > 0 then text = text .. "\n|cffff8000" .. table.concat(plan.warnings, "  ") .. "|r" end
        return text
    end

    function page:Refresh()
        local inGame = mode == "game"
        for _, w in ipairs({ search, howMany, count, stockBox, stockLabel, checkBtn, makeBtn, status, picker, gameSteps }) do w:SetShown(inGame) end
        appSteps:SetShown(not inGame)
        headline:ClearAllPoints()
        if inGame then
            picker:SetData(pickerRows())
            headline:SetPoint("TOPLEFT", picker, "BOTTOMLEFT", 0, -10)
            gameSteps:ClearAllPoints()
            gameSteps:SetPoint("TOPLEFT", headline, "BOTTOMLEFT", 0, -6)
            local plan = ns.db.gamePlan
            local rows = stepRows(plan, "gamePlanDone")
            gameSteps:SetData(rows)
            headline:SetText(plan and summary(plan, rows)
                or (chosen and ("Ready to plan |cffffffff" .. nameOf(chosen) .. "|r: set how many, then Make plan. With the AH open, Check AH prices first.")
                or "Pick something to sell from the list, or type to search."))
        else
            headline:SetPoint("TOPLEFT", 0, -34)
            appSteps:ClearAllPoints()
            appSteps:SetPoint("TOPLEFT", headline, "BOTTOMLEFT", 0, -6)
            local d = ns.AppData()
            local plan = d and d.sale
            local rows = stepRows(plan, "saleDone")
            appSteps:SetData(rows)
            headline:SetText(plan and (summary(plan, rows) .. "  |cffaaaaaa(sent " .. (ns.AppAge() or "?") .. ")|r")
                or "No plan from the app. Make one on the app's Desk tab (Sales Planner), press Send to game, then /reload.")
        end
    end
end)
