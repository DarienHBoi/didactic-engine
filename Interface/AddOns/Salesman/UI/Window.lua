local _, S = ...
S.UI = S.UI or {}

local STALE_SECS = 86400
local STACK = 20
local state = { cats = {}, ench = {}, channelKey = nil, cat = nil, search = "", tab = "enchants", customer = nil, pendingQuote = nil, picked = {}, queue = nil }
local guard = S.SendGuard.new(GetTime)

local function joinedChannels()
    local out = {}
    local list = { GetChannelList() }
    for i = 1, #list, 3 do
        if list[i + 1] then out[#out + 1] = { id = list[i], name = list[i + 1], disabled = list[i + 2] and true or false } end
    end
    return out
end

local function channelList() return S.Channels.list(joinedChannels()) end

local function findChannel(list, key)
    for i, e in ipairs(list) do
        if e.key == key then return e, i end
    end
end

local function rowMargin(recipe)
    local own = S.DB.char.cardMargin and S.DB.char.cardMargin[recipe.key]
    if own ~= nil then return own end
    return S.DB.global.margin
end

local function cost(recipe)
    return S.Pricing.matsCost(recipe.reagents, S.Prices.lookup, STALE_SECS)
end

-- How many of each material the player holds (bags and bank) against a recipe.
local function itemCount(id)
    local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
    return fn and fn(id, true) or 0
end
local function stockOf(recipe)
    return S.Stock.check(recipe, itemCount)
end
S.UI.stockOf = stockOf

local SORTS = { "price_desc", "price_asc", "name" }
local SORT_LABELS = { price_desc = "Sort: Price high-low", price_asc = "Sort: Price low-high", name = "Sort: Name" }

-- The profession shown in the list: the saved choice if it still exists, else Enchanting, else the first found.
local function professions() return S.Recipes.professions(S.DB.char and S.DB.char.recipes) end
local function currentProfession()
    local list = professions()
    local want = S.DB.global and S.DB.global.profession
    for _, p in ipairs(list) do if p == want then return p end end
    for _, p in ipairs(list) do if p == (S.Recipes.enchantingName or "Enchanting") then return p end end
    return list[1]
end
local function inProfession(r)
    local cur = currentProfession()
    return cur == nil or S.Recipes.professionOf(r) == cur
end

local function statsOf(recipe)
    local fn = (C_Item and C_Item.GetItemStats) or GetItemStats
    return S.Stats.forRecipe(recipe, fn, S.DB.global.statsOverride)
end

local function setStatus(msg)
    if state.frame then state.frame.status:SetText(msg or "") end
end

-- A real clickable item link when the client has the item cached, else the plain name.
local function matLink(r)
    local getItem = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if getItem and r[1] then
        local _, link = getItem(r[1])
        if link then return link end
    end
    return r.name or ("item " .. tostring(r[1]))
end

local function matsText(recipe)
    local parts = {}
    for _, r in ipairs(recipe.reagents) do
        parts[#parts + 1] = "x" .. tostring(r[2]) .. " " .. matLink(r)
    end
    return table.concat(parts, ", ")
end

-- Adverts can be switched off in NectarKit: nothing is posted to a public channel (whispers to customers still go).
local function advertsOff(entry)
    if S.Mod.on("adverts") or (entry and entry.chatType == "WHISPER") then return false end
    setStatus("Adverts are switched off in NectarKit (/nk options).")
    return true
end

local function deliver(entry, text, confirmId)
    if advertsOff(entry) then return end
    local verdict = guard:check(entry.key, text)
    if verdict == "cooldown" then setStatus("Wait a moment before sending again.") return end
    if verdict == "confirm" and state.confirmId ~= confirmId then
        state.confirmId = confirmId
        setStatus("Same message sent recently. Click again to resend.")
        return
    end
    state.confirmId = nil
    SendChatMessage(text, entry.chatType, nil, entry.channelID or entry.target)
    guard:record(entry.key, text)
    setStatus("Sent to " .. entry.label)
    -- A whispered quote is remembered on the customer so Done can log the sale.
    if entry.chatType == "WHISPER" and state.pendingQuote and state.pendingQuote.name == entry.target
        and state.pendingQuote.text == text then
        S.Customers.setQuote(S.DB.char, entry.target, state.pendingQuote.key, state.pendingQuote.price)
    end
    if entry.chatType == "WHISPER" then state.pendingQuote = nil end
    return true
end

-- With "Edit first" on, buttons fill the message box instead of posting; Post sends what the box holds.
local function route(entry, text, confirmId, source)
    if advertsOff(entry) then return end
    if S.DB.global.editFirst and state.frame then
        state.source = source
        state.frame.box:SetText(text)
        state.frame.box:SetCursorPosition(0)
        setStatus("Edit the message if you like, then click Post.")
        return
    end
    deliver(entry, text, confirmId)
end

local WORDING_KEY = { mats = "template", byo = "templateBYO", skill = "templateSkill", reply = "templateReply" }
local WORDING_LABEL = { mats = "mats included", byo = "you bring", skill = "skill link", reply = "customer reply" }

-- After a post of edited ad text, keep the edit as the new wording for that ad type when it can be saved exactly.
local function saveWording(text)
    local src = state.source
    if not src or not src.link or text == src.text or not text:find(src.link, 1, true) then return nil end
    local subs = { link = src.link, price = src.kind ~= "skill" and S.Money.format(src.copper) or nil, mats = src.mats, stats = src.stats }
    local rebuild
    if src.kind == "skill" then
        rebuild = function(t) return S.Message.buildSkill(t, src.link, src.prof) end
    elseif src.kind == "byo" then
        rebuild = function(t) return S.Message.build(t, src.link, src.copper, src.mats, src.stats) end
    else
        rebuild = function(t) return S.Message.build(t, src.link, src.copper, nil, src.stats) end
    end
    local tpl, why = S.Wording.derive(text, subs, rebuild)
    if not tpl then return "Wording not saved: " .. why end
    S.DB.global[WORDING_KEY[src.kind]] = tpl
    src.text = text
    return "Saved your wording for the " .. WORDING_LABEL[src.kind] .. " ad."
end

local function postBox()
    local f = state.frame
    if not f then return end
    local entry
    if state.tab == "customers" then
        -- Customers tab: the box is a whisper to the selected customer, only on this click.
        if not state.customer then setStatus("Pick a customer first.") return end
        entry = { key = "whisper:" .. state.customer, label = "whisper to " .. S.Customers.shortName(state.customer, nil),
                  chatType = "WHISPER", target = state.customer }
    else
        local list = channelList()
        if not state.channelKey then setStatus("Choose a channel first (click the channel button).") return end
        local ok, why = S.Channels.canSend(list, state.channelKey)
        if not ok then setStatus(why) state.channelKey = nil S.UI.refresh() return end
        entry = findChannel(list, state.channelKey)
    end
    local text, err = S.Message.validate(f.box:GetText())
    if not text then setStatus("Not sent: " .. err) return end
    local sent = deliver(entry, text, "box|" .. entry.key .. "|" .. text)
    local note = sent and saveWording(text) or nil
    if note then f.status:SetText((f.status:GetText() or "") .. "  " .. note) end
    if state.tab == "customers" then S.UI.refresh() end
    -- Multi-ad queue: move to the next line only after the current one was really sent.
    if note and not state.queue then S.UI.refresh() end
    if sent and state.queue and S.Queue.current(state.queue) == text then
        local total = S.Queue.total(state.queue)
        local nxt = S.Queue.advance(state.queue)
        if nxt then
            f.box:SetText(nxt)
            f.box:SetCursorPosition(0)
            state.source = state.queueInfo and state.queueInfo[nxt] or nil
            setStatus("Sent. Ad " .. S.Queue.position(state.queue) .. " of " .. total .. " is ready: click Post." .. (note and ("  " .. note) or ""))
        else
            state.queue = nil
            state.source = nil
            f.box:SetText("")
            setStatus("All " .. total .. " ads sent." .. (note and ("  " .. note) or ""))
        end
    end
end

-- Whisper target: sends the message box to your current target (a player you sought out). An empty box sends the
-- customer-reply wording for the selected enchant. The target becomes a quoted customer so Done can log the sale.
local function whisperTarget()
    local f = state.frame
    if not f then return end
    local name, why = S.Target.name()
    if not name then setStatus(why) return end
    local recipe = state.selectedRecipe
    local raw = f.box:GetText() or ""
    local text, err, quote
    if raw:match("^%s*$") then
        if not recipe then setStatus("Pick an enchant first.") return end
        local ask = S.Pricing.suggest(cost(recipe), rowMargin(recipe))
        text, err = S.Message.build(S.DB.global.templateReply, recipe.link, ask, nil, statsOf(recipe))
        if not text then setStatus("Not sent: " .. err) return end
        quote = { key = recipe.key, price = ask }
        state.source = { kind = "reply", link = recipe.link, copper = ask, stats = statsOf(recipe), text = text }
    else
        text, err = S.Message.validate(raw)
        if not text then setStatus("Not sent: " .. err) return end
        local src = state.source
        if src and src.kind == "skill" then quote = nil
        elseif src and src.key and src.copper then quote = { key = src.key, price = src.copper }
        elseif recipe then quote = { key = recipe.key, price = S.Pricing.suggest(cost(recipe), rowMargin(recipe)) } end
    end
    local short = S.Customers.shortName(name, nil)
    local entry = { key = "whisper:" .. name, label = "whisper to " .. short, chatType = "WHISPER", target = name }
    local sent = deliver(entry, text, "target|" .. name .. "|" .. text)
    if sent then
        -- Only after a real send (cooldown / confirm return without sending). The game's whisper echo arrives later
        -- and is recorded on this customer.
        if quote then S.Customers.pitch(S.DB.char, name, quote.key, quote.price, time and time() or 0, state.customer) end
        local note = saveWording(text)
        if note then f.status:SetText((f.status:GetText() or "") .. "  " .. note) end
    end
end

-- Posts the Enchanting profession link itself (not one recipe).
local function sendSkill()
    local list = channelList()
    if not state.channelKey then setStatus("Choose a channel first (click the channel button).") return end
    local ok, why = S.Channels.canSend(list, state.channelKey)
    if not ok then setStatus(why) state.channelKey = nil S.UI.refresh() return end
    local entry = findChannel(list, state.channelKey)
    local prof = currentProfession()
    local skillLink = (S.DB.char.skillLinks and prof and S.DB.char.skillLinks[prof]) or S.DB.char.skillLink
    local text, err = S.Message.buildSkill(S.DB.global.templateSkill, skillLink, prof)
    if not text then setStatus("Not sent: " .. err) return end
    route(entry, text, "skill|" .. entry.key .. "|" .. text, { kind = "skill", link = skillLink, text = text, prof = prof })
end

-- mode "mats": enchant link, mats included. mode "byo": enchant link, labour only, mat links listed.
local function matsNames(recipe)
    local parts = {}
    for _, r in ipairs(recipe.reagents) do
        local live = r[1] and C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(r[1])
        parts[#parts + 1] = tostring(r[2]) .. " " .. (live or r.name or ("item " .. tostring(r[1])))
    end
    return table.concat(parts, ", ")
end

local function buildText(recipe, mode)
    local c = cost(recipe)
    if mode == "byo" then
        local labour = S.Pricing.labour(c, rowMargin(recipe))
        local matsStr = matsText(recipe)
        local text, err = S.Message.build(S.DB.global.templateBYO, recipe.link, labour, matsStr, statsOf(recipe))
        if not text and err and err:find("255", 1, true) then
            -- Item links are long: retry with plain material names so the ad still fits in one chat line.
            matsStr = matsNames(recipe)
            text, err = S.Message.build(S.DB.global.templateBYO, recipe.link, labour, matsStr, statsOf(recipe))
        end
        return text, err, { kind = "byo", key = recipe.key, link = recipe.link, copper = labour, mats = matsStr, stats = statsOf(recipe), text = text }
    end
    local ask = S.Pricing.suggest(c, rowMargin(recipe))
    local text, err = S.Message.build(S.DB.global.template, recipe.link, ask, nil, statsOf(recipe))
    return text, err, { kind = "mats", key = recipe.key, link = recipe.link, copper = ask, stats = statsOf(recipe), text = text }
end

local function send(recipe, mode)
    local list = channelList()
    if not state.channelKey then setStatus("Choose a channel first (click the channel button).") return end
    local ok, why = S.Channels.canSend(list, state.channelKey)
    if not ok then setStatus(why) state.channelKey = nil S.UI.refresh() return end
    local entry = findChannel(list, state.channelKey)
    local text, err, info = buildText(recipe, mode)
    if not text then setStatus("Not sent: " .. err) return end
    route(entry, text, recipe.key .. "|" .. mode .. "|" .. entry.key .. "|" .. text, info)
end

local GOLD_HEX = "|cffffd100"

-- Hover card: the game's own enchant tooltip (effect, reagents) plus Salesman's price view.
local function showTip(owner, r)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local ref = r.link and r.link:match("|H(enchant:%d+)")
    -- A recipe that makes an item shows that item's own tooltip; enchants show the enchant's effect.
    local ok = r.resultLink and pcall(GameTooltip.SetHyperlink, GameTooltip, r.resultLink)
    if not ok then ok = ref and pcall(GameTooltip.SetHyperlink, GameTooltip, ref) end
    if not ok then
        GameTooltip:ClearLines()
        GameTooltip:AddLine(r.name, 1, 0.82, 0)
    end
    local c = cost(r)
    local m = rowMargin(r)
    local ask, labour = S.Pricing.suggest(c, m), S.Pricing.labour(c, m)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Salesman", 1, 0.82, 0)
    for _, l in ipairs(S.Breakdown.compute(r, S.Prices.lookup, STACK).lines) do
        GameTooltip:AddDoubleLine(l.count .. "x " .. l.name, S.Money.format(l.line), 1, 1, 1, 1, 1, 1)
    end
    GameTooltip:AddDoubleLine("Mats cost", S.Money.format(c.copper) .. (c.state == "stale" and " (old)" or ""), 1, 1, 1, 1, 0.82, 0)
    GameTooltip:AddDoubleLine("Ask (mats included, " .. m .. "%)", S.Money.format(ask), 1, 1, 1, 1, 0.82, 0)
    GameTooltip:AddDoubleLine("Ask (you bring mats)", S.Money.format(labour), 1, 1, 1, 1, 0.82, 0)
    local profit = S.Profit.of(ask, c.copper)
    if profit then
        if profit < 0 then GameTooltip:AddDoubleLine("Profit", S.UI.signedMoney(profit), 1, 1, 1, 1, 0.25, 0.25)
        else GameTooltip:AddDoubleLine("Profit", S.UI.signedMoney(profit), 1, 1, 1, 0.25, 1, 0.25) end
    end
    local resultID = S.Prices.itemIDFromLink(r.resultLink)
    if resultID then
        local ah = S.Prices.auction(resultID)
        local res = ah.copper and S.Profit.craft(ah.copper, c.copper)
        if res then
            local old = (ah.ageSecs and ah.ageSecs >= 86400) and " (old)" or ""
            GameTooltip:AddDoubleLine("Sells on AH" .. old, S.Money.format(res.sell), 1, 1, 1, 1, 0.82, 0)
            GameTooltip:AddDoubleLine("After " .. math.floor(S.Profit.AH_CUT * 100 + 0.5) .. "% AH cut", S.Money.format(res.net), 1, 1, 1, 1, 0.82, 0)
            if res.profit then
                local txt = S.UI.signedMoney(res.profit) .. (res.margin and ("  (" .. res.margin .. "%)") or "")
                if res.profit < 0 then GameTooltip:AddDoubleLine("Resale profit", txt, 1, 1, 1, 1, 0.25, 0.25)
                else GameTooltip:AddDoubleLine("Resale profit", txt, 1, 1, 1, 0.25, 1, 0.25) end
            end
        else
            GameTooltip:AddLine("AH price: no data (scan the auction house with Auctionator)", 0.6, 0.6, 0.6)
        end
    end
    local sales = S.DB.char.sales[r.key]
    if sales and #sales > 0 then
        GameTooltip:AddDoubleLine("Median sold (" .. #sales .. ")", S.Money.format(S.Sales.median(sales)), 1, 1, 1, 1, 0.82, 0)
    end
    GameTooltip:AddLine("Click to select. Star = favourite.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function pickedCount()
    local n = 0
    for _ in pairs(state.picked) do n = n + 1 end
    return n
end

-- Builds one mats-included ad per ticked enchant (best price first) and puts the first in the message box.
local function startQueue()
    local f = state.frame
    if not f then return end
    if advertsOff() then return end
    local n = pickedCount()
    if n == 0 then setStatus("Tick the enchants you want to post first.") return end
    local list = {}
    for _, r in ipairs(S.DB.char.recipes or {}) do
        if inProfession(r) and state.picked[r.key] then list[#list + 1] = r end
    end
    list = S.Group.sort(list, "price_desc", function(r) return S.Pricing.suggest(cost(r), rowMargin(r)) end)
    local infos = {}
    local texts, skipped = S.Queue.build(list, state.picked, function(r)
        local t, e, info = buildText(r, "mats")
        if t then infos[t] = info end
        return t, e
    end)
    state.queueInfo = infos
    state.queue = S.Queue.new(texts)
    if not state.queue then
        setStatus("Nothing to post: " .. (skipped[1] and (skipped[1].name .. ": " .. skipped[1].reason) or "no ads built"))
        return
    end
    f.box:SetText(S.Queue.current(state.queue))
    f.box:SetCursorPosition(0)
    state.source = infos[S.Queue.current(state.queue)]
    setStatus("Ad 1 of " .. #texts .. " is ready: click Post." .. (#skipped > 0 and ("  (" .. #skipped .. " skipped: price unknown)") or ""))
end

local function clearPicks()
    state.picked = {}
    state.queue = nil
    S.UI.refresh()
end

local function getCat(i)
    if not state.cats[i] then state.cats[i] = S.UI.newCategory(state.frame.catContent) end
    return state.cats[i]
end

local function getEnch(i)
    if not state.ench[i] then state.ench[i] = S.UI.newEnchant(state.frame.listContent) end
    return state.ench[i]
end

local function sortMode()
    local m = S.DB.global.sort
    for _, k in ipairs(SORTS) do if k == m then return m end end
    return "price_desc"
end

local function hooks()
    return {
        cost = cost,
        tip = showTip,
        earned = function(r) return S.Ledger.byKey(S.DB.char, r.key) end,
        stock = stockOf,
        margin = rowMargin,
        setMargin = function(r, m)
            S.DB.char.selected = r.key
            S.DB.char.cardMargin[r.key] = m
            S.UI.refresh()
        end,
        preview = buildText,
        send = send,
        toggleFav = function(r) S.DB.toggleFavourite(r.key); S.UI.refresh() end,
        stats = function(r) return statsOf(r) end,
        setStats = function(r, text)
            local ok, why = S.Stats.setOverride(S.DB.global.statsOverride, r.name, text)
            if not ok then setStatus(why) return end
            setStatus((text and text:match("%S")) and "Stats saved for this enchant." or "Stats override removed.")
            S.UI.refresh()
        end,
        status = setStatus,
        canSend = function() return state.channelKey ~= nil end,
    }
end

local function customerHooks()
    return {
        getSelected = function() return state.customer end,
        select = function(name)
            if name ~= state.customer then
                state.pendingQuote = nil
                state.source = nil
                if state.frame then state.frame.box:SetText("") end
            end
            state.customer = name
            S.Customers.markRead(S.DB.char, name)
            if S.UI.updateBadge then S.UI.updateBadge() end
        end,
        status = setStatus,
        logSale = function(name, key, copper, label)
            if S.Ledger.logSale(S.DB.char, name, key, copper, time and time() or 0) then
                setStatus("Sale logged: " .. S.Money.format(copper) .. (label and (" for " .. label) or "") .. ". Customer marked done.")
                S.UI.refresh()
            else
                setStatus("Could not log that sale.")
            end
        end,
        invite = function(name)
            local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
            if not fn or not name then setStatus("Cannot invite from here.") return end
            local ok = pcall(fn, name)
            setStatus(ok and ("Invite sent to " .. S.Customers.shortName(name) .. ".") or "Invite failed.")
        end,
        quote = function(name, recipe)
            local c = cost(recipe)
            local ask = S.Pricing.suggest(c, rowMargin(recipe))
            local text, err = S.Message.build(S.DB.global.templateReply, recipe.link, ask, nil, statsOf(recipe))
            if not text then setStatus("Cannot build reply: " .. err) return end
            state.frame.box:SetText(text)
            state.frame.box:SetCursorPosition(0)
            state.pendingQuote = { name = name, key = recipe.key, price = ask, text = text }
            state.source = { kind = "reply", key = recipe.key, link = recipe.link, copper = ask, stats = statsOf(recipe), text = text }
            setStatus("Reply ready. Edit it if you like, then click Post to whisper it.")
        end,
    }
end

-- For the board, a mat with no price at all is one you farm: it counts as free (and is tagged).
local function farmedCost(recipe)
    return S.Pricing.matsCostFarmed(recipe.reagents, S.Prices.lookup, STALE_SECS)
end

-- Best crafts tab: rank every crafted item; a click opens that recipe in its profession view.
local function boardHooks()
    return {
        rows = function()
            return S.Board.rank(S.DB.char.recipes, { cost = farmedCost, auction = S.Prices.auction, history = S.Prices.history, staleSecs = STALE_SECS,
                sort = S.DB.global.boardSort,
                outcomes = function(id) return SalesmanAPI.outcomes(id) end,
                sold = function(r) return S.MailLog.soldFor(S.DB.char.mailLog, r) end })
        end,
        select = function(r)
            local prof = S.Recipes.professionOf(r)
            if prof and prof ~= currentProfession() then
                S.DB.global.profession = prof
                state.picked, state.queue = {}, nil
            end
            state.cat = "*all"
            S.DB.char.selected = r.key
            if state.frame and state.search ~= "" then
                state.search = ""
                state.frame.search:SetText("")
            end
            S.UI.setTab("enchants")
        end,
        status = setStatus,
    }
end

function S.UI.currentTab() return state.tab end
function S.UI.currentCustomer() return state.customer end
function S.UI.updateTabLabel()
    local f = state.frame
    if not f or not S.DB.char then return end
    local unread = S.Customers.unreadCount(S.DB.char)
    f.tabCustomers:SetText("Customers" .. (unread > 0 and (" (" .. unread .. ")") or ""))
end

-- The Customers, Best crafts and Mail tabs follow their NectarKit switches; a switched-off tab is hidden and cannot be opened.
local TABS = { { "tabCustomers", "customers", "customers" }, { "tabBoard", "board", "bestcrafts" }, { "tabMail", "mail", "maillog" } }
local function tabAllowed(tab)
    for _, t in ipairs(TABS) do
        if t[2] == tab then return S.Mod.on(t[3]) end
    end
    return true
end

-- Shows the tabs that are on, in a row, with the search box after the last one.
local function layoutTabs(f)
    local prev = f.tabEnchants
    for _, t in ipairs(TABS) do
        local b, on = f[t[1]], S.Mod.on(t[3])
        b:SetShown(on)
        if on then
            b:ClearAllPoints()
            b:SetPoint("LEFT", prev, "RIGHT", 6, 0)
            prev = b
        end
    end
    f.search:ClearAllPoints()
    f.search:SetPoint("LEFT", prev, "RIGHT", 12, 0)
end

function S.UI.setTab(tab)
    local f = state.frame
    if not f then return end
    if not tabAllowed(tab) then tab = "enchants" end
    if tab ~= state.tab then
        state.pendingQuote = nil
        state.queue = nil
        state.source = nil
        f.box:SetText("")
    end
    state.tab = tab
    for _, w in ipairs(f.enchantWidgets) do w:SetShown(tab == "enchants") end
    f.croot:SetShown(tab == "customers")
    f.broot:SetShown(tab == "board")
    f.mroot:SetShown(tab == "mail")
    f.tabEnchants:SetAlpha(tab == "enchants" and 1 or 0.55)
    f.tabCustomers:SetAlpha(tab == "customers" and 1 or 0.55)
    f.tabBoard:SetAlpha(tab == "board" and 1 or 0.55)
    f.tabMail:SetAlpha(tab == "mail" and 1 or 0.55)
    S.UI.refresh()
end

function S.UI.refresh()
    local f = state.frame
    if not f then return end
    local n = S.Ledger.count(S.DB.char)
    if f.whisperTarget then f.whisperTarget:SetText(S.Target.label((S.Target.name()))) end
    f.earned:SetText("Earned: |cffffd100" .. S.Money.format(S.Ledger.total(S.DB.char)) .. "|r" .. (n > 0 and ("  (" .. n .. " sales)") or ""))
    -- AH and mail income is its own figure beside service earnings (trades and logged sales), plus the combined total.
    local mail = S.MailLog.income(S.DB.char.mailLog)
    f.mailEarned:SetText(mail > 0 and ("AH & mail: |cffffd100" .. S.Money.format(mail) .. "|r   Total: |cffffd100"
        .. S.Money.format(S.Ledger.total(S.DB.char) + mail) .. "|r") or "")
    local waiting = S.MailLog.waitingCount(S.DB.char.mailLog)
    f.tabMail:SetText("Mail" .. (waiting > 0 and (" (" .. waiting .. ")") or ""))
    local unread = S.Customers.unreadCount(S.DB.char)
    f.tabCustomers:SetText("Customers" .. (unread > 0 and (" (" .. unread .. ")") or ""))
    if state.tab == "customers" then
        f.customers.update()
        f.channel:SetText(state.customer and ("Whisper: " .. S.Customers.shortName(state.customer, nil)) or "Pick a customer")
        return
    end
    if state.tab == "board" then
        f.banner:SetShown(not S.Prices.available())
        f.board.update()
        return
    end
    if state.tab == "mail" then
        f.banner:SetShown(false)
        f.mail.update()
        return
    end
    local recipes = S.DB.char.recipes or {}
    f.banner:SetShown(not S.Prices.available())
    state.confirmId = nil
    local list = channelList()
    if state.channelKey and not findChannel(list, state.channelKey) then
        state.channelKey = nil
        setStatus("Channel no longer available. Choose a channel.")
    end
    local needle = state.search:lower()
    local keepFn = function(r)
        if not inProfession(r) then return false end
        return needle == "" or r.name:lower():find(needle, 1, true) ~= nil
    end
    -- Ask prices are computed once per refresh so sorting does not repeat Auctionator lookups.
    local askCache = {}
    local askFn = function(r)
        local v = askCache[r.key]
        if v == nil then
            v = S.Pricing.suggest(cost(r), rowMargin(r)) or false
            askCache[r.key] = v
        end
        return v or nil
    end

    -- Left pane: All, Favourites, then the game's own categories in sellable-first order.
    local groups = S.CategoryRank.order(S.Group.byCategory(recipes, keepFn))
    local all, favs = {}, {}
    for _, g in ipairs(groups) do
        for _, r in ipairs(g.items) do
            all[#all + 1] = r
            if S.DB.char.favourites[r.key] then favs[#favs + 1] = r end
        end
    end
    local entries = { { id = "*all", name = "All enchants", items = all }, { id = "*fav", name = "Favourites", items = favs } }
    for _, g in ipairs(groups) do
        entries[#entries + 1] = { id = g.name, name = g.name, items = g.items, dim = not S.CategoryRank.sellable(g.name) }
    end
    local current
    for _, e in ipairs(entries) do if e.id == state.cat then current = e end end
    if not current then current = entries[1]; state.cat = current.id end

    for _, b in ipairs(state.cats) do b:Hide() end
    local y = 0
    for i, e in ipairs(entries) do
        local b = getCat(i)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 0, -y)
        local first = e.items[1]
        b.icon:SetTexture((e.id:sub(1, 1) ~= "*" and first and first.icon) or "Interface\\Icons\\Trade_Engraving")
        b.label:SetText(e.name)
        if e.dim then b.label:SetTextColor(0.6, 0.6, 0.6) else b.label:SetTextColor(1, 1, 1) end
        b.count:SetText(#e.items)
        b:SetSelected(e.id == state.cat)
        b:SetScript("OnClick", function() state.cat = e.id; S.UI.refresh() end)
        b:Show()
        y = y + S.UI.CAT_H + 2
    end
    f.catContent:SetHeight(math.max(1, y))

    -- Middle pane: the chosen category, sorted.
    local items = S.Group.sort(current.items, sortMode(), askFn)
    local selected
    for _, r in ipairs(items) do if r.key == S.DB.char.selected then selected = r end end
    if not selected then selected = items[1] end
    state.selectedRecipe = selected
    for _, b in ipairs(state.ench) do b:Hide() end
    local label = S.Group.labeler(items)
    y = 0
    for i, r in ipairs(items) do
        local b = getEnch(i)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 0, -y)
        local c = cost(r)
        b.icon:SetTexture(r.icon or S.UI.QUESTION)
        b.name:SetText(label(r.name))
        b.sub:SetText("Mats " .. S.Money.format(c.copper) .. (c.state == "stale" and " |cffff8800(old)|r" or "")
            .. "   Ask " .. GOLD_HEX .. S.Money.format(askFn(r)) .. "|r")
        local can = stockOf(r).craftable
        b.stock:SetText((can and can > 0) and ("|cff40ff40" .. can .. "|r") or "")
        if b.icon.SetDesaturated then b.icon:SetDesaturated(can == 0) end
        if S.DB.char.favourites[r.key] then b.star.label:SetTextColor(1, 0.82, 0) else b.star.label:SetTextColor(0.4, 0.4, 0.4) end
        b.star:SetScript("OnClick", function() S.DB.toggleFavourite(r.key); S.UI.refresh() end)
        b:SetSelected(selected ~= nil and r.key == selected.key)
        b.pick:SetChecked(state.picked[r.key] and true or false)
        b.pick:SetScript("OnClick", function(self)
            state.picked[r.key] = self:GetChecked() and true or nil
            state.queue = nil
            S.UI.refresh()
        end)
        b:SetScript("OnClick", function()
            -- An ad built for the previously selected enchant is cleared so it can't be posted for this one.
            if not state.queue and state.source and state.source.key and state.source.key ~= r.key then
                state.source = nil
                state.frame.box:SetText("")
            end
            S.DB.char.selected = r.key
            S.UI.refresh()
        end)
        b:SetScript("OnEnter", function(self) showTip(self, r) end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:Show()
        y = y + S.UI.ENCH_H + 2
    end
    f.listContent:SetHeight(math.max(1, y))
    f.empty:SetShown(#items == 0)
    if #items == 0 then
        if #recipes == 0 and not S.Hooks.apiAvailable() then
            f.empty:SetText("Unsupported client: no profession API found.")
        elseif #recipes == 0 then
            f.empty:SetText("Open your Enchanting window once to load your recipes.")
        elseif current.id == "*fav" then
            f.empty:SetText("No favourites yet. Click the star on an enchant.")
        else
            f.empty:SetText("No enchants match.")
        end
    end

    -- Right pane.
    f.detail.update(selected)

    local chosen = state.channelKey and findChannel(list, state.channelKey)
    f.channel:SetText(chosen and ("Channel: " .. chosen.label) or "Choose channel...")
    f.sort:SetText(SORT_LABELS[sortMode()])
    f.tabEnchants:SetText(currentProfession() or "Enchanting")
    local n = pickedCount()
    f.postSel:SetText("Post selected (" .. n .. ")")
    f.postSel:SetEnabled(n > 0)
    f.clearSel:SetEnabled(n > 0)
end

local function makeFrame()
    local ok, f = pcall(CreateFrame, "Frame", "SalesmanWindow", UIParent, "ButtonFrameTemplate")
    if ok and f then
        f.skin = "blizzard"
        if ButtonFrameTemplate_HidePortrait then pcall(ButtonFrameTemplate_HidePortrait, f) end
        if f.SetTitle then f:SetTitle("Salesman") elseif f.TitleText then f.TitleText:SetText("Salesman") end
        if f.Inset then f.Inset:Hide() end
        return f
    end
    f = CreateFrame("Frame", "SalesmanWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f.skin = "flat"
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    f:SetBackdropColor(0.04, 0.035, 0.03, 0.97)
    f:SetBackdropBorderColor(0.6, 0.48, 0.15, 1)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOP", 0, -8)
    title:SetText("Salesman")
    title:SetTextColor(1, 0.82, 0)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    return f
end

local function build()
    local f = makeFrame()
    f:SetSize(860, 660)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, "SalesmanWindow")

    -- Bottom-left row beside "Reset wording" (the Blizzard title bar hides anything placed on it).
    f.scaleMinus = S.UI.button(f, "-", 24, 22)
    f.scaleMinus:SetPoint("BOTTOMLEFT", 170, 8)
    f.scaleText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.scaleText:SetPoint("LEFT", f.scaleMinus, "RIGHT", 4, 0)
    f.scaleText:SetWidth(40)
    f.scalePlus = S.UI.button(f, "+", 24, 22)
    f.scalePlus:SetPoint("LEFT", f.scaleText, "RIGHT", 2, 0)
    f.earned = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.earned:SetPoint("LEFT", f.scalePlus, "RIGHT", 14, 0)
    f.earned:SetWordWrap(false)
    f.mailEarned = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.mailEarned:SetPoint("LEFT", f.earned, "RIGHT", 12, 0)
    f.mailEarned:SetWordWrap(false)
    local function setScale(v)
        S.DB.global.scale = S.Scale.clamp(v)
        f:SetScale(S.DB.global.scale)
        f.scaleText:SetText(S.Scale.label(S.DB.global.scale))
    end
    f.scalePlus:SetScript("OnClick", function() setScale(S.Scale.step(S.DB.global.scale, 1)) end)
    f.scaleMinus:SetScript("OnClick", function() setScale(S.Scale.step(S.DB.global.scale, -1)) end)
    setScale(S.DB.global.scale)

    -- Top bar: tabs on the left
    f.tabEnchants = S.UI.button(f, "Enchanting", 122, 28, true)
    f.tabEnchants:SetPoint("TOPLEFT", 20, -33)
    f.tabEnchants:SetScript("OnClick", function()
        local list = professions()
        if state.tab == "enchants" and #list > 1 then
            -- Clicking the active profession tab switches to the next profession.
            local cur, idx = currentProfession(), 1
            for i, p in ipairs(list) do if p == cur then idx = i end end
            S.DB.global.profession = list[idx % #list + 1]
            state.cat, state.picked, state.queue = nil, {}, nil
            setStatus("Profession: " .. S.DB.global.profession .. " (click the tab again to switch)")
            S.UI.refresh()
        else
            S.UI.setTab("enchants")
        end
    end)
    f.tabCustomers = S.UI.button(f, "Customers", 104, 28, true)
    f.tabCustomers:SetPoint("LEFT", f.tabEnchants, "RIGHT", 6, 0)
    f.tabCustomers:SetScript("OnClick", function() S.UI.setTab("customers") end)
    f.tabBoard = S.UI.button(f, "Best crafts", 100, 28, true)
    f.tabBoard:SetPoint("LEFT", f.tabCustomers, "RIGHT", 6, 0)
    f.tabBoard:SetScript("OnClick", function() S.UI.setTab("board") end)
    f.tabMail = S.UI.button(f, "Mail", 76, 28, true)
    f.tabMail:SetPoint("LEFT", f.tabBoard, "RIGHT", 6, 0)
    f.tabMail:SetScript("OnClick", function() S.UI.setTab("mail") end)
    local search = CreateFrame("EditBox", nil, f, "SearchBoxTemplate")
    search:SetSize(118, 20)
    search:SetPoint("LEFT", f.tabMail, "RIGHT", 12, 0)
    search:SetAutoFocus(false)
    f.search = search
    layoutTabs(f)
    search:SetScript("OnTextChanged", function(self)
        if SearchBoxTemplate_OnTextChanged then SearchBoxTemplate_OnTextChanged(self) end
        state.search = self:GetText() or ""
        S.UI.refresh()
    end)

    local sortBtn = S.UI.button(f, "", 140, 28)
    sortBtn:SetPoint("LEFT", search, "RIGHT", 10, 0)
    sortBtn:SetScript("OnClick", function()
        local cur, idx = sortMode(), 1
        for i, m in ipairs(SORTS) do if m == cur then idx = i end end
        S.DB.global.sort = SORTS[idx % #SORTS + 1]
        S.UI.refresh()
    end)
    f.sort = sortBtn

    local mlabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    mlabel:SetPoint("LEFT", sortBtn, "RIGHT", 10, 0)
    mlabel:SetText("Default %")
    local margin = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    margin:SetSize(38, 20)
    margin:SetPoint("LEFT", mlabel, "RIGHT", 8, 0)
    margin:SetAutoFocus(false)
    margin:SetMaxLetters(5)
    margin:SetScript("OnEnterPressed", function(self)
        local m = S.Pricing.parseMargin(self:GetText())
        if m == nil then setStatus("Margin must be a plain number like 15 or 12.5.") else S.DB.global.margin = m end
        self:ClearFocus()
        S.UI.refresh()
    end)
    f.margin = margin

    -- Lives in the bottom bar (right of "Edit first") so the top bar has room for three tabs.
    local skillBtn = S.UI.button(f, "Link my skill", 130, 28, true)
    skillBtn:SetPoint("BOTTOMRIGHT", -16, 56)
    skillBtn:SetScript("OnClick", sendSkill)

    -- Three panes
    local left = S.UI.panel(f)
    left:SetPoint("TOPLEFT", 14, -66)
    left:SetPoint("BOTTOMLEFT", 14, 92)
    left:SetWidth(S.UI.CAT_W + 30)
    local _, catContent = S.UI.scrollList(left, S.UI.CAT_W)
    f.catContent = catContent

    local mid = S.UI.panel(f)
    mid:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, 0)
    mid:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT", 6, 0)
    mid:SetWidth(S.UI.ENCH_W + 30)
    local midScroll, listContent = S.UI.scrollList(mid, S.UI.ENCH_W)
    midScroll:SetPoint("BOTTOMRIGHT", -24, 42)
    f.listContent = listContent
    f.postSel = S.UI.button(mid, "Post selected (0)", 154, 30, true)
    f.postSel:SetPoint("BOTTOMLEFT", 6, 6)
    f.postSel:SetScript("OnClick", startQueue)
    f.clearSel = S.UI.button(mid, "Clear", 64, 30)
    f.clearSel:SetPoint("LEFT", f.postSel, "RIGHT", 6, 0)
    f.clearSel:SetScript("OnClick", clearPicks)

    local right = S.UI.panel(f)
    right:SetPoint("TOPLEFT", mid, "TOPRIGHT", 6, 0)
    right:SetPoint("BOTTOMRIGHT", -14, 92)
    f.detail = S.UI.buildDetail(right, hooks())
    f.enchantWidgets = { search, sortBtn, mlabel, margin, skillBtn, left, mid, right }

    local croot = CreateFrame("Frame", nil, f)
    croot:SetPoint("TOPLEFT", 14, -66)
    croot:SetPoint("BOTTOMRIGHT", -14, 92)
    f.croot = croot
    f.customers = S.UI.buildCustomers(croot, customerHooks())
    croot:Hide()
    local broot = CreateFrame("Frame", nil, f)
    broot:SetPoint("TOPLEFT", 14, -66)
    broot:SetPoint("BOTTOMRIGHT", -14, 92)
    f.broot = broot
    f.board = S.UI.buildBoard(broot, boardHooks())
    broot:Hide()
    local mroot = CreateFrame("Frame", nil, f)
    mroot:SetPoint("TOPLEFT", 14, -66)
    mroot:SetPoint("BOTTOMRIGHT", -14, 92)
    f.mroot = mroot
    f.mail = S.UI.buildMail(mroot)
    mroot:Hide()
    f.tabEnchants:SetAlpha(1)
    f.tabCustomers:SetAlpha(0.55)
    f.tabBoard:SetAlpha(0.55)
    f.tabMail:SetAlpha(0.55)

    -- Bottom bar: the message that will post, then the channel and status.
    local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    box:SetPoint("BOTTOMLEFT", 24, 58)
    box:SetSize(390, 24)
    box:SetAutoFocus(false)
    box:SetMaxLetters(255)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus(); postBox() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.box = box
    local postBtn = S.UI.button(f, "Post", 80, 28, true)
    postBtn:SetPoint("LEFT", box, "RIGHT", 8, 0)
    postBtn:SetScript("OnClick", postBox)
    -- Whisper target: the label follows your target so you can see who gets it before clicking.
    local wt = S.UI.button(f, "Whisper target", 130, 28, true)
    wt:SetPoint("LEFT", postBtn, "RIGHT", 6, 0)
    wt:SetScript("OnClick", whisperTarget)
    wt:SetScript("OnEvent", function(self)
        self:SetText(S.Target.label((S.Target.name())))
    end)
    pcall(wt.RegisterEvent, wt, "PLAYER_TARGET_CHANGED")
    if wt.SetMotionScriptsWhileDisabled then wt:SetMotionScriptsWhileDisabled(true) end
    wt:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Whisper your target")
        GameTooltip:AddLine("Sends the message box to the player you have targeted. If the box is empty, sends the customer-reply wording for the selected enchant at your margin. They are added to Customers as quoted.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    wt:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.whisperTarget = wt
    local editFirst = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    editFirst:SetSize(24, 24)
    editFirst:SetPoint("LEFT", wt, "RIGHT", 6, 0)
    editFirst:SetScript("OnClick", function(self) S.DB.global.editFirst = self:GetChecked() and true or false; S.UI.refresh() end)
    local editLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    editLabel:SetPoint("LEFT", editFirst, "RIGHT", 0, 0)
    editLabel:SetText("Edit first")
    f.editFirst = editFirst

    -- Click cycles to the next channel, right-click goes back.
    local channel = S.UI.button(f, "Choose channel...", 240, 32, true)
    channel:SetPoint("BOTTOMRIGHT", -16, 18)
    channel:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    channel:SetScript("OnClick", function(_, btn)
        if state.tab == "customers" then return end
        local list = channelList()
        local _, i = findChannel(list, state.channelKey)
        if i then
            i = (i - 1 + (btn == "RightButton" and -1 or 1)) % #list + 1
        else
            i = 1
        end
        state.channelKey = list[i].key
        S.UI.refresh()
    end)
    f.channel = channel

    f.resetWording = S.UI.button(f, "Reset wording", 130, 22)
    f.resetWording:SetPoint("BOTTOMLEFT", 24, 8)
    f.resetWording:SetScript("OnClick", function()
        S.DB.resetWording()
        -- The box may hold an ad built with the old wording: clear it so the next Use button rebuilds it.
        if not state.queue then state.source = nil; f.box:SetText("") end
        setStatus("Ad wording reset to the defaults.")
        S.UI.refresh()
    end)
    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.status:SetPoint("BOTTOMLEFT", 24, 32)
    f.empty = mid:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.empty:SetPoint("CENTER")
    f.empty:SetWidth(200)
    f.banner = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.banner:SetPoint("BOTTOMLEFT", 170, 14)
    f.banner:SetTextColor(1, 0.5, 0)
    f.banner:SetText("Auctionator not found: prices unavailable")
    f:SetScript("OnShow", function()
        f.margin:SetText(tostring(S.DB.global.margin))
        f.editFirst:SetChecked(S.DB.global.editFirst)
        S.UI.refresh()
    end)
    f:Hide()
    state.frame = f
    S.UI.skin = f.skin
    return f
end

-- Trade tracking: remember who you trade with and the gold they offer, count it when the client says the trade completed.
local tradeToken = 0
local function targetGold()
    local ok, g = pcall(function() return GetTargetTradeMoney and GetTargetTradeMoney() end)
    if ok and type(g) == "number" then S.Tracker.setGold(g) end
end
function S.UI.onTradeEvent(event, a1, a2)
    if not S.Mod.on("trades") then return end
    if event == "TRADE_SHOW" then
        tradeToken = tradeToken + 1
        local ok, name = pcall(UnitName, "NPC")
        S.Tracker.open(ok and name or nil)
        targetGold()
    elseif event == "TRADE_MONEY_CHANGED" or event == "TRADE_ACCEPT_UPDATE" then
        targetGold()
    elseif event == "TRADE_CLOSED" then
        -- The completion message can arrive just after the close event, so close a moment later.
        local token = tradeToken
        local close = function() if token == tradeToken then S.Tracker.close() end end
        if C_Timer and C_Timer.After then C_Timer.After(2, close) else close() end
    elseif event == "UI_INFO_MESSAGE" then
        local ok, done = pcall(function() return a2 == (ERR_TRADE_COMPLETE or "Trade complete.") end)
        if not (ok and done) then return end
        local r = S.Tracker.complete(S.DB.char, time and time() or 0)
        if not r then return end
        local msg
        if r.counted then
            msg = "Trade with " .. S.Customers.shortName(r.name) .. " complete: " .. S.Money.format(r.copper) .. " added to your earnings."
        elseif r.matched then
            msg = "Trade with " .. S.Customers.shortName(r.name) .. " finished with no gold, so nothing was counted."
        elseif r.copper > 0 then
            msg = "Trade gold " .. S.Money.format(r.copper) .. " was not counted: that player is not in your Customers tab."
        end
        if msg then print("|cffffd100Salesman:|r " .. msg); setStatus(msg) end
        if state.frame and state.frame:IsShown() then S.UI.refresh() end
    end
end

function S.UI.toggle()
    local f = state.frame or build()
    f:SetShown(not f:IsShown())
end

-- NectarKit switches, live: tabs come and go; a switched-off tab that is open gives way to Enchants.
for _, key in ipairs({ "customers", "bestcrafts", "maillog" }) do
    S.Mod.listen(key, function()
        local f = state.frame
        if not f then return end
        layoutTabs(f)
        if not tabAllowed(state.tab) then S.UI.setTab("enchants") elseif f:IsShown() then S.UI.refresh() end
    end)
end
