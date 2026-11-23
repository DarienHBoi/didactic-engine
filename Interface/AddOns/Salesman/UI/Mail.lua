local _, S = ...
S.UI = S.UI or {}

-- Mail tab: every incoming mail with gold or items, newest first, with income totals and filters.
local ROW_W, ROW_H = 790, 30
local COIN = "Interface\\Icons\\INV_Misc_Coin_01"
local KIND_COLOR = {
    ah_sold = "|cff40ff40", ah_won = "|cff80c0ff", ah_outbid = "|cffc0c0c0", ah_return = "|cffc0c0c0",
    cod = "|cffffd100", player = "|cffffd100", other = "|cffa0a0a0",
}

-- ---------- reading the mailbox ----------
local session, mailOpen, pending
local patterns

local function P()
    patterns = patterns or S.MailLog.patterns(_G)
    return patterns
end

local function now() return time and time() or 0 end

local function log()
    if not (S.DB and S.DB.char) then return nil end
    S.DB.char.mailLog = S.DB.char.mailLog or {}
    return S.DB.char.mailLog
end

local function charName()
    local ok, n = pcall(UnitName, "player")
    return ok and type(n) == "string" and n or nil
end

-- The inbox is only trusted while the mailbox is open (between MAIL_SHOW and close, or while MailFrame shows).
local function mailboxOpen()
    if mailOpen then return true end
    local ok, shown = pcall(function() return MailFrame and MailFrame:IsShown() end)
    return ok and shown and true or false
end

local function scanNow()
    pending = nil
    local l = log()
    if not l or not session or not mailboxOpen() then return end
    local t = now()
    local mails = S.MailLog.readInbox(_G, t, P())
    local r = S.MailLog.scan(l, mails, t, session, { patterns = P(), char = charName(), resolve = S.API.itemIDByName })
    if (r.added > 0 or r.collected > 0) and SalesmanWindow and SalesmanWindow:IsShown() then pcall(S.UI.refresh) end
end

local function schedule()
    if pending then return end
    pending = true
    if C_Timer and C_Timer.After then C_Timer.After(0.3, function() pcall(scanNow) end) else scanNow() end
end


function S.UI.onMailEvent(event)
    if not S.Mod.on("maillog") then return end -- switched off in NectarKit: the inbox is not read
    if event == "MAIL_SHOW" then
        -- Wait for MAIL_INBOX_UPDATE: the list shown before the server answers may be the last visit's.
        session, mailOpen = {}, true
    elseif event == "MAIL_INBOX_UPDATE" then
        if mailboxOpen() then
            session = session or {}
            schedule()
        end
    elseif event == "MAIL_CLOSED" then
        mailOpen, session = false, nil
    end
end

-- Switched off in NectarKit: forget the visit in progress (the mailbox must be reopened after switching back on).
S.Mod.listen("maillog", function() mailOpen, session, pending = false, nil, nil end)

-- A mail sent back to its sender is not "collected".
function S.UI.initMailHooks()
    -- MAIL_CLOSED may not fire on newer clients: the mail frame hiding also ends the visit.
    if MailFrame and MailFrame.HookScript then
        pcall(MailFrame.HookScript, MailFrame, "OnHide", function() mailOpen, session = false, nil end)
    end
    if not (hooksecurefunc and ReturnInboxItem) then return end
    pcall(hooksecurefunc, "ReturnInboxItem", function(index)
        if not S.Mod.on("maillog") then return end
        pcall(function()
            local l = log()
            if not l then return end
            local t = now()
            for _, m in ipairs(S.MailLog.readInbox(_G, t, P())) do
                if m.index == index then S.MailLog.markReturned(l, m, t) end
            end
        end)
    end)
end

-- ---------- the tab ----------
local function money(v) return (v and v > 0) and S.Money.format(v) or "-" end

local function fmtDate(t)
    local d = date or (os and os.date)
    if not (d and t) then return "" end
    local ok, s = pcall(d, "%b %d %H:%M", t)
    return ok and s or ""
end

local function statusText(e)
    if e.gone == "returned" then return "|cffc0c0c0returned|r" end
    if e.collected then return "|cff808080collected|r" end
    if e.gone == "expired" then return "|cffff4040expired|r" end
    if e.left and e.left.money < e.money then return "|cffff8800items left|r" end
    return "|cffff8800not collected|r"
end

local function title(e)
    if e.item then return e.item end
    local it = e.items and e.items[1]
    if it then
        local n = it.name or (it.link and it.link:match("%[(.-)%]")) or "item"
        return n .. ((it.count or 1) > 1 and (" x" .. it.count) or "") .. (#e.items > 1 and (" +" .. (#e.items - 1)) or "")
    end
    return e.subject ~= "" and e.subject or e.sender
end

local function newRow(parent)
    local b = CreateFrame("Button", nil, parent, S.UI.TEMPLATE)
    b:SetSize(ROW_W, ROW_H)
    S.UI.cardStyle(b)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(22, 22)
    b.icon:SetPoint("LEFT", 6, 0)
    local function fs(x, w, font, justify)
        local s = b:CreateFontString(nil, "OVERLAY", font)
        s:SetPoint("LEFT", x, 0)
        s:SetWidth(w)
        s:SetJustifyH(justify)
        s:SetWordWrap(false)
        return s
    end
    b.kind = fs(34, 96, "GameFontHighlightSmall", "LEFT")
    b.name = fs(132, 250, "GameFontNormal", "LEFT")
    b.from = fs(386, 130, "GameFontHighlightSmall", "LEFT")
    b.gold = fs(520, 100, "GameFontHighlight", "RIGHT")
    b.state = fs(628, 70, "GameFontHighlightSmall", "LEFT")
    b.when = fs(700, 86, "GameFontDisableSmall", "RIGHT")
    return b
end

local function paint(b, e)
    local it = e.items and e.items[1]
    b.icon:SetTexture((it and it.icon) or COIN)
    b.kind:SetText((KIND_COLOR[e.kind] or "") .. (S.MailLog.KIND_LABEL[e.kind] or e.kind or "?") .. "|r")
    b.name:SetText(title(e))
    b.from:SetText(e.sender or "")
    local g = money(e.money)
    if e.cod and e.cod > 0 then g = "CoD " .. S.Money.format(e.cod) end
    b.gold:SetText(g)
    b.state:SetText(statusText(e))
    b.when:SetText(fmtDate(e.seen))
end

local function showTip(owner, e)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local it = e.items and e.items[1]
    local ok = it and it.link and pcall(GameTooltip.SetHyperlink, GameTooltip, it.link)
    if not ok then GameTooltip:ClearLines() end
    if ok then GameTooltip:AddLine(" ") end
    GameTooltip:AddLine((S.MailLog.KIND_LABEL[e.kind] or "Mail") .. ": " .. (e.subject or ""), 1, 0.82, 0, true)
    GameTooltip:AddDoubleLine("From", e.sender or "?", 1, 1, 1, 1, 1, 1)
    if e.money > 0 then GameTooltip:AddDoubleLine("Gold", S.Money.format(e.money), 1, 1, 1, 1, 1, 1) end
    if e.cod > 0 then GameTooltip:AddDoubleLine("CoD to open", S.Money.format(e.cod), 1, 1, 1, 1, 0.5, 0) end
    local inv = e.invoice
    if inv then
        if inv.bid and inv.bid > 0 then GameTooltip:AddDoubleLine("Sale price", S.Money.format(inv.bid), 1, 1, 1, 1, 1, 1) end
        if inv.consignment and inv.consignment > 0 then GameTooltip:AddDoubleLine("AH cut", S.Money.format(inv.consignment), 1, 1, 1, 1, 0.5, 0.5) end
        if inv.deposit and inv.deposit > 0 then GameTooltip:AddDoubleLine("Deposit back", S.Money.format(inv.deposit), 1, 1, 1, 1, 1, 1) end
        if type(inv.playerName) == "string" and inv.playerName ~= "" then GameTooltip:AddDoubleLine("Buyer/seller", inv.playerName, 1, 1, 1, 1, 1, 1) end
    end
    for _, x in ipairs(e.items or {}) do
        local n = x.link or x.name or "item"
        GameTooltip:AddLine(n .. ((x.count or 1) > 1 and (" x" .. x.count) or ""), 1, 1, 1)
    end
    GameTooltip:AddDoubleLine("Seen", fmtDate(e.seen), 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
    if e.collected then GameTooltip:AddDoubleLine("Collected", fmtDate(e.collected), 0.7, 0.7, 0.7, 0.7, 0.7, 0.7) end
    if e.gone == "expired" then GameTooltip:AddLine("Expired before it was collected.", 1, 0.3, 0.3) end
    if e.gone == "returned" then GameTooltip:AddLine("Returned to the sender.", 0.8, 0.8, 0.8) end
    if e.char then GameTooltip:AddDoubleLine("Character", e.char, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7) end
    GameTooltip:Show()
end

local function dayStart(t)
    local d = date or (os and os.date)
    local mk = time or (os and os.time)
    if not (d and mk) then return t - (t % 86400) end
    local ok, v = pcall(function()
        local x = d("*t", t)
        x.hour, x.min, x.sec = 0, 0, 0
        return mk(x)
    end)
    return ok and v or t - (t % 86400)
end

local function pair(p) return "AH " .. money(p.ah) .. "  |  Players " .. money(p.players) end

function S.UI.buildMail(root)
    local panel = { frames = {}, shown = {}, filter = "all", search = "", filterBtns = {} }

    local head = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    head:SetPoint("TOPLEFT", 8, -6)
    head:SetText("Mail")
    panel.waiting = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.waiting:SetPoint("LEFT", head, "RIGHT", 12, -1)

    -- Totals strip: today / 7 days / all time.
    panel.today = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.today:SetPoint("TOPLEFT", 8, -30)
    panel.today:SetWidth(260)
    panel.today:SetJustifyH("LEFT")
    panel.week = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.week:SetPoint("LEFT", panel.today, "RIGHT", 10, 0)
    panel.week:SetWidth(260)
    panel.week:SetJustifyH("LEFT")
    panel.all = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.all:SetPoint("LEFT", panel.week, "RIGHT", 10, 0)
    panel.all:SetWidth(270)
    panel.all:SetJustifyH("LEFT")

    -- Filters and search.
    local prevBtn
    for _, key in ipairs(S.MailLog.FILTER_ORDER) do
        local b = S.UI.button(root, S.MailLog.FILTER_LABEL[key], 104, 24)
        if prevBtn then b:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 4, -48) end
        b:SetScript("OnClick", function() panel.filter = key; panel.update() end)
        panel.filterBtns[key] = b
        prevBtn = b
    end
    local search = CreateFrame("EditBox", nil, root, "SearchBoxTemplate")
    search:SetSize(200, 20)
    search:SetPoint("LEFT", prevBtn, "RIGHT", 14, 0)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function(self)
        if SearchBoxTemplate_OnTextChanged then SearchBoxTemplate_OnTextChanged(self) end
        panel.search = self:GetText() or ""
        panel.update()
    end)
    panel.searchBox = search

    local box = S.UI.panel(root)
    box:SetPoint("TOPLEFT", 0, -78)
    box:SetPoint("BOTTOMRIGHT", 0, 0)
    local _, content = S.UI.scrollList(box, ROW_W)
    panel.empty = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.empty:SetPoint("CENTER")
    panel.empty:SetWidth(440)

    local function getRow(i)
        if not panel.frames[i] then panel.frames[i] = newRow(content) end
        return panel.frames[i]
    end

    function panel.update()
        local l = log()
        local t = now()
        local tot = S.MailLog.totals(l, t, dayStart(t))
        panel.today:SetText("Today: " .. pair(tot.today))
        panel.week:SetText("7 days: " .. pair(tot.week))
        panel.all:SetText("All time: " .. pair(tot.all))
        local wait = S.MailLog.uncollectedAH(l)
        panel.waiting:SetText(wait > 0 and ("|cffff8800AH gold waiting in your mailbox: " .. S.Money.format(wait) .. "|r") or "")
        for key, b in pairs(panel.filterBtns) do b:SetAlpha(key == panel.filter and 1 or 0.6) end
        panel.shown = S.MailLog.filter(l, panel.filter, panel.search)
        for _, b in ipairs(panel.frames) do b:Hide() end
        local y = 0
        -- Draw at most 200 rows; the search narrows the rest.
        for i = 1, math.min(#panel.shown, 200) do
            local e = panel.shown[i]
            local b = getRow(i)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 0, -y)
            paint(b, e)
            b:SetScript("OnEnter", function(self) showTip(self, e) end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:Show()
            y = y + ROW_H + 2
        end
        content:SetHeight(math.max(1, y))
        panel.empty:SetShown(#panel.shown == 0)
        if not (l and l.entries and #l.entries > 0) then
            panel.empty:SetText("No mail logged yet. Open a mailbox: every mail with gold or items is logged.")
        else
            panel.empty:SetText("No mail matches this filter.")
        end
    end
    return panel
end
