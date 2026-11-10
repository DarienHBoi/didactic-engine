local _, S = ...
S.UI = S.UI or {}

local STATUS_COLOR = { new = "|cff40c0ff", quoted = "|cffffd100", waiting = "|cffff9030", done = "|cff40ff40" }
local STATUS_LABEL = { new = "New", quoted = "Quoted", waiting = "Waiting", done = "Done" }
local CARD_H, CARD_W = 62, 236

local function realmName()
    return (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or nil
end

-- Every cached recipe (all professions), as the Match module expects.
local function enchantRecipes()
    local out = {}
    for _, r in ipairs(S.DB.char.recipes or {}) do
        out[#out + 1] = r
    end
    return out
end

-- What a customer wants: matched against everything they said (newest five lines).
local wantsCache = {}
local function wantsFor(c, recipes)
    local hit = wantsCache[c.name]
    if hit and hit.n == #c.msgs and hit.last == c.last and hit.rc == #recipes then return hit.w end
    local said = {}
    for i = #c.msgs, 1, -1 do
        if not c.msgs[i].out then said[#said + 1] = c.msgs[i].text end
        if #said >= 5 then break end
    end
    local w = S.Match.wants(table.concat(said, " "), recipes)
    wantsCache[c.name] = { n = #c.msgs, last = c.last, rc = #recipes, w = w }
    return w
end

local function clock(t)
    if date and t then return date("%H:%M", t) end
    return ""
end

local function newCard(parent)
    local b = CreateFrame("Button", nil, parent, S.UI.TEMPLATE)
    b:SetSize(CARD_W, CARD_H)
    S.UI.cardStyle(b)
    b.dot = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    b.dot:SetPoint("TOPLEFT", 8, -8)
    b.dot:SetText("!")
    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.name:SetPoint("TOPLEFT", 24, -9)
    b.name:SetWidth(120)
    b.name:SetJustifyH("LEFT")
    b.name:SetWordWrap(false)
    b.name:SetTextColor(1, 0.88, 0.24)
    b.status = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.status:SetPoint("TOPRIGHT", -10, -11)
    b.last = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.last:SetPoint("TOPLEFT", 24, -27)
    b.last:SetWidth(204)
    b.last:SetJustifyH("LEFT")
    b.last:SetWordWrap(false)
    b.last:SetTextColor(0.75, 0.75, 0.75)
    b.wants = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.wants:SetPoint("TOPLEFT", 24, -42)
    b.wants:SetWidth(204)
    b.wants:SetJustifyH("LEFT")
    b.wants:SetWordWrap(false)
    return b
end

-- Customers pane. hooks: getSelected(), select(name), quote(customer, recipe), status(msg)
function S.UI.buildCustomers(root, hooks)
    local cp = { root = root, cards = {}, quotes = {} }

    local left = S.UI.panel(root)
    left:SetPoint("TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", 0, 0)
    left:SetWidth(CARD_W + 30)
    local _, content = S.UI.scrollList(left, CARD_W)
    cp.listContent = content
    cp.empty = left:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cp.empty:SetPoint("CENTER")
    cp.empty:SetWidth(210)
    cp.empty:SetText("No customers yet. Whispers you receive will show up here.")

    local right = S.UI.panel(root)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, 0)
    right:SetPoint("BOTTOMRIGHT", 0, 0)
    cp.right = right
    local rc = CreateFrame("Frame", nil, right)
    rc:SetAllPoints()
    cp.detail = rc

    cp.name = rc:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    cp.name:SetPoint("TOPLEFT", 14, -12)
    cp.name:SetTextColor(1, 0.88, 0.24)
    cp.name:SetShadowColor(0, 0, 0, 1)
    cp.name:SetShadowOffset(1, -1)

    cp.invite = S.UI.button(rc, "Invite", 84, 26, true)
    cp.invite:SetPoint("TOPRIGHT", -14, -10)
    cp.invite:SetScript("OnClick", function()
        local name = hooks.getSelected()
        if name and hooks.invite then hooks.invite(name) end
    end)

    cp.statusBtns = {}
    for i, key in ipairs(S.Customers.STATUSES) do
        local b = S.UI.button(rc, STATUS_LABEL[key], 88, 26)
        b:SetPoint("TOPLEFT", 12 + (i - 1) * 92, -42)
        b:SetScript("OnClick", function()
            local name = hooks.getSelected()
            if not name then return end
            if key == "done" then
                local logged = S.Customers.complete(S.DB.char, name, time and time() or 0)
                hooks.status(logged and "Done. Quoted price added to your sales history." or "Marked done.")
            else
                S.Customers.setStatus(S.DB.char, name, key)
            end
            S.UI.refresh()
        end)
        cp.statusBtns[key] = b
    end

    local wantsLabel = rc:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wantsLabel:SetPoint("TOPLEFT", 14, -80)
    wantsLabel:SetText("They seem to want (click to fill a price reply)")
    cp.none = rc:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cp.none:SetPoint("TOPLEFT", 14, -98)
    cp.none:SetText("No enchant recognised. Type your own reply in the box below.")
    for i = 1, 3 do
        local b = S.UI.button(rc, "", 366, 30, true)
        b:SetPoint("TOPLEFT", 12, -96 - (i - 1) * 34)
        b:SetScript("OnClick", function()
            local name, recipe = hooks.getSelected(), b.recipe
            if name and recipe then hooks.quote(name, recipe) end
        end)
        cp.quotes[i] = b
    end

    local chatLabel = rc:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chatLabel:SetPoint("TOPLEFT", 14, -204)
    chatLabel:SetText("Conversation")
    local scroll = CreateFrame("ScrollFrame", nil, rc, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -222)
    scroll:SetPoint("BOTTOMRIGHT", -30, 84)
    local chat = CreateFrame("Frame", nil, scroll)
    chat:SetSize(496, 1)
    scroll:SetScrollChild(chat)
    cp.scroll = scroll
    cp.chatContent = chat
    cp.chat = chat:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cp.chat:SetPoint("TOPLEFT", 0, 0)
    cp.chat:SetWidth(496)
    cp.chat:SetJustifyH("LEFT")
    cp.chat:SetJustifyV("TOP")
    cp.chat:SetSpacing(3)

    -- Log what this customer really paid (moved here from the Enchants tab).
    local saleLabel = rc:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    saleLabel:SetPoint("BOTTOMLEFT", 14, 62)
    saleLabel:SetText("Sold for (gold):")
    cp.sale = CreateFrame("EditBox", nil, rc, "InputBoxTemplate")
    cp.sale:SetSize(70, 20)
    cp.sale:SetPoint("LEFT", saleLabel, "RIGHT", 12, 0)
    cp.sale:SetAutoFocus(false)
    cp.sale:SetMaxLetters(12)
    cp.saleFor = S.UI.button(rc, "Log sale", 84, 24, true)
    cp.saleFor:SetPoint("LEFT", cp.sale, "RIGHT", 8, 0)
    cp.saleWhat = rc:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cp.saleWhat:SetPoint("LEFT", cp.saleFor, "RIGHT", 10, 0)
    cp.saleWhat:SetWidth(210)
    cp.saleWhat:SetJustifyH("LEFT")
    cp.saleWhat:SetWordWrap(false)
    local function logIt()
        local name = hooks.getSelected()
        if not name then return end
        local copper = S.Money.parseGold(cp.sale:GetText())
        if not copper then hooks.status("Type the price in gold, like 4.5") return end
        hooks.logSale(name, cp.saleKey, copper, cp.saleLabelText)
        cp.sale:SetText("")
        cp.sale:ClearFocus()
        cp.saleForName = nil
    end
    cp.sale:SetScript("OnEnterPressed", logIt)
    cp.saleFor:SetScript("OnClick", logIt)

    local noteLabel = rc:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noteLabel:SetPoint("BOTTOMLEFT", 14, 30)
    noteLabel:SetText("Note")
    cp.note = CreateFrame("EditBox", nil, rc, "InputBoxTemplate")
    cp.note:SetSize(340, 22)
    cp.note:SetPoint("BOTTOMLEFT", 16, 8)
    cp.note:SetAutoFocus(false)
    cp.note:SetMaxLetters(200)
    local function saveNote(self)
        local name = hooks.getSelected()
        if name then S.Customers.setNote(S.DB.char, name, self:GetText()) end
    end
    cp.note:SetScript("OnEnterPressed", function(self) saveNote(self); self:ClearFocus() end)
    cp.note:SetScript("OnEditFocusLost", saveNote)

    function cp.update()
        local db = S.DB.char
        local recipes = enchantRecipes()
        local list = S.Customers.list(db)
        for _, b in ipairs(cp.cards) do b:Hide() end
        local selected = hooks.getSelected()
        if selected and not db.customers[selected] then selected = nil end
        if not selected and list[1] then selected = list[1].name; hooks.select(selected) end
        local realm = realmName()
        local y = 0
        for i, c in ipairs(list) do
            local b = cp.cards[i]
            if not b then b = newCard(cp.listContent); cp.cards[i] = b end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 0, -y)
            b.name:SetText(S.Customers.shortName(c.name, realm))
            b.dot:SetShown(c.unread and true or false)
            b.status:SetText((STATUS_COLOR[c.status] or "") .. (STATUS_LABEL[c.status] or c.status) .. "|r")
            local lastMsg = c.msgs[#c.msgs]
            b.last:SetText(lastMsg and ((lastMsg.out and "You: " or "") .. S.Customers.display(lastMsg.text)) or "")
            local w = wantsFor(c, recipes)
            b.wants:SetText(w[1] and ("|cffffd100Wants:|r " .. S.Group.shortName(w[1].recipe.name)
                .. (w[2] and (" +" .. (#w - 1)) or "")) or "")
            b:SetSelected(c.name == selected)
            b:SetScript("OnClick", function() hooks.select(c.name); S.UI.refresh() end)
            b:Show()
            y = y + CARD_H + 2
        end
        cp.listContent:SetHeight(math.max(1, y))
        cp.empty:SetShown(#list == 0)
        cp.detail:SetShown(selected ~= nil)
        if not selected then return end

        local c = db.customers[selected]
        S.Customers.markRead(db, selected)
        if S.UI.updateBadge then S.UI.updateBadge() end
        cp.name:SetText(S.Customers.shortName(c.name, realm))
        for key, b in pairs(cp.statusBtns) do b:SetAlpha(c.status == key and 1 or 0.55) end
        -- The sale is logged against the quoted enchant, else the first one recognised in their messages.
        local w0 = wantsFor(c, recipes)
        cp.saleKey, cp.saleLabelText = nil, nil
        if c.quote and c.quote.key then
            cp.saleKey = c.quote.key
            for _, r in ipairs(recipes) do if r.key == c.quote.key then cp.saleLabelText = S.Group.shortName(r.name) end end
        elseif w0[1] then
            cp.saleKey, cp.saleLabelText = w0[1].recipe.key, S.Group.shortName(w0[1].recipe.name)
        end
        cp.saleWhat:SetText(cp.saleLabelText and ("for " .. cp.saleLabelText) or "|cff999999no enchant recognised|r")
        if cp.saleForName ~= selected then
            cp.saleForName = selected
            cp.sale:SetText(c.quote and S.Money.goldText(c.quote.price) or "")
        end

        local w = wantsFor(c, recipes)
        cp.none:SetShown(#w == 0)
        for i, b in ipairs(cp.quotes) do
            local m = w[i]
            if m then
                local cost = S.Pricing.matsCost(m.recipe.reagents, S.Prices.lookup, 86400)
                local mg = (db.cardMargin and db.cardMargin[m.recipe.key]) or S.DB.global.margin
                local ask = S.Pricing.suggest(cost, mg)
                b.recipe = m.recipe
                b:SetText("Quote: " .. S.Group.shortName(m.recipe.name) .. "  " .. S.Money.format(ask))
                b:SetEnabled(ask ~= nil)
                b:Show()
            else
                b.recipe = nil
                b:Hide()
            end
        end

        local lines = {}
        for _, m in ipairs(c.msgs) do
            local who = m.out and "|cff80c0ffYou|r" or ("|cffffd100" .. S.Customers.shortName(c.name, realm) .. "|r")
            lines[#lines + 1] = "|cff888888" .. clock(m.t) .. "|r " .. who .. ": " .. S.Customers.display(m.text)
        end
        local function num(v) return type(v) == "number" and v or 0 end
        local sc = cp.scroll
        local wasBottom = num(sc.GetVerticalScroll and sc:GetVerticalScroll()) >= num(sc.GetVerticalScrollRange and sc:GetVerticalScrollRange()) - 4
        cp.chat:SetText(table.concat(lines, "\n"))
        cp.chatContent:SetHeight(math.max(1, cp.chat:GetStringHeight() + 4))
        if sc.UpdateScrollChildRect then sc:UpdateScrollChildRect() end
        if not (cp.note.HasFocus and cp.note:HasFocus()) then cp.note:SetText(c.note or "") end
        -- Jump to the newest line when you open a customer or were already at the bottom; never yank a scrolled-up view.
        local switched = cp.shown ~= selected
        cp.shown = selected
        if sc.SetVerticalScroll and (switched or wasBottom) then
            sc:SetVerticalScroll(num(sc.GetVerticalScrollRange and sc:GetVerticalScrollRange()))
        end
    end

    return cp
end

-- Whisper in (outgoing=false) or out (outgoing=true). Safe to call from any chat event.
function S.UI.onWhisper(text, name, outgoing)
    if not S.DB or not S.DB.char then return end
    if issecretvalue and (issecretvalue(text) or issecretvalue(name)) then return end
    local ok, c, isNew = pcall(S.Customers.record, S.DB.char, name, text, outgoing, time and time() or 0, S.UI.currentCustomer and S.UI.currentCustomer() or nil)
    if not ok or not c then return end
    if isNew and S.DB.global.alerts then
        local snd = (SOUNDKIT and SOUNDKIT.TELL_MESSAGE) or 3081
        pcall(PlaySound, snd)
    end
    if S.UI.updateBadge then S.UI.updateBadge() end
    if SalesmanWindow and SalesmanWindow:IsShown() then
        -- Only the Customers tab needs a redraw; the Enchants tab just updates its tab label.
        if S.UI.currentTab and S.UI.currentTab() == "customers" then S.UI.refresh() else S.UI.updateTabLabel() end
    end
end
