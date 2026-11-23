local _, ns = ...

-- The same main tabs as the ZugDAQ app, each with its own row of sub-tabs. A sub-tab shows a page, and can set
-- the page's view (pages with several tables read page.view in Refresh). What the app sends (page "app") sits
-- under the tab it belongs to, next to what the game works out itself.

local WIDTH, HEIGHT = 820, 570
ns.PAGE_WIDTH = WIDTH - 32

local SECTIONS = {
    { key = "overview", title = "Overview", subs = {
        { key = "account", title = "Account", page = "overview" },
        { key = "todo", title = "To do", page = "todo" },
    } },
    { key = "inventory", title = "Inventory", subs = {
        { key = "bags", title = "My bags", page = "market", view = "bags" },
        { key = "sell", title = "What to sell", page = "app", view = "sell" },
        { key = "mats", title = "My mats", page = "crafting", view = "mats" },
    } },
    { key = "crafting", title = "Crafting", subs = {
        { key = "explore", title = "Explore", page = "explore" },
        { key = "skillups", title = "Skill-ups", page = "skillups", view = "crafts" },
        { key = "toget", title = "Recipes to get", page = "skillups", view = "get" },
        { key = "sale", title = "Sales plan", page = "planner" },
        { key = "plan", title = "Plan", page = "app", view = "plan" },
        { key = "shop", title = "Shopping", page = "app", view = "shop" },
        { key = "recipes", title = "Recipes", page = "crafting", view = "recipes" },
        { key = "flip", title = "Buy & craft", page = "crafting", view = "flip" },
    } },
    { key = "guild", title = "Guild", subs = {
        { key = "members", title = "Members", page = "app", view = "guild" },
        { key = "trade", title = "Guild trade", page = "app", view = "trade" },
    } },
}
local sectionByKey = {}
for _, s in ipairs(SECTIONS) do sectionByKey[s.key] = s end

local pages = {}
local frame
local current -- the page key on screen

-- modules add their page here: build(page) runs the first time it's shown, page:Refresh() on updates
function ns.RegisterPage(key, _, build)
    pages[key] = { key = key, build = build }
end

local function findSub(section, key)
    for _, sub in ipairs(section.subs) do
        if sub.key == key then return sub end
    end
end

local function showSub(sectionKey, subKey)
    local section = sectionByKey[sectionKey] or SECTIONS[1]
    ns.settings.sub = ns.settings.sub or {}
    local sub = findSub(section, subKey or ns.settings.sub[section.key] or "") or section.subs[1]
    ns.settings.sub[section.key] = sub.key

    for key, p in pairs(pages) do
        if key ~= sub.page and p.frame then p.frame:Hide() end
    end
    local p = pages[sub.page]
    if p then
        if not p.frame then
            p.frame = CreateFrame("Frame", nil, frame.content)
            p.frame:SetAllPoints()
            p.build(p.frame)
        end
        if sub.view then p.frame.view = sub.view end
        current = sub.page
        p.frame:Show()
        if p.frame.Refresh then p.frame:Refresh() end
    end

    frame.tabs:Select(section.key)
    for key, strip in pairs(frame.subTabs) do
        strip:SetShown(key == section.key)
        if key == section.key then strip:Select(sub.key) end
    end
end

local function build()
    frame = CreateFrame("Frame", "ZugDAQFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("MEDIUM") -- same layer as game windows, so a profession window it opens can sit on top
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    ns.Backdrop(frame)
    tinsert(UISpecialFrames, "ZugDAQFrame")

    local title = ns.Label(frame, "GameFontNormalLarge", "|TInterface\\Icons\\INV_Misc_Coin_02:18:18|t  ZugDAQ")
    title:SetPoint("TOPLEFT", 14, -12)
    frame.gold = ns.Label(frame, "GameFontHighlight", "", "RIGHT")
    frame.gold:SetPoint("TOPRIGHT", -40, -14)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    -- a newer addon is waiting (the app says so): a red warning in the title bar, the details on hover
    local notice = CreateFrame("Button", nil, frame)
    notice:SetSize(330, 20)
    notice:SetPoint("TOP", -20, -11)
    notice.text = ns.Label(notice, "GameFontNormal", "", "CENTER")
    notice.text:SetAllPoints()
    notice:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("ZugDAQ addon")
        GameTooltip:AddLine(ns.AddonUpdateText() or "Up to date.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    notice:SetScript("OnLeave", function() GameTooltip:Hide() end)
    notice:Hide()
    frame.notice = notice

    local items = {}
    for _, s in ipairs(SECTIONS) do items[#items + 1] = { key = s.key, text = s.title, width = 124 } end
    frame.tabs = ns.Toggles(frame, items, function(key) showSub(key) end)
    frame.tabs.first:SetPoint("TOPLEFT", 14, -40)

    frame.subTabs = {}
    for _, s in ipairs(SECTIONS) do
        local subItems = {}
        for _, sub in ipairs(s.subs) do subItems[#subItems + 1] = { key = sub.key, text = sub.title } end
        local strip = ns.SubTabs(frame, subItems, function(key) showSub(s.key, key) end)
        strip.first:SetPoint("TOPLEFT", 14, -68)
        frame.subTabs[s.key] = strip
    end
    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(1, 1, 1, 0.12)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 14, -91)
    rule:SetPoint("TOPRIGHT", -14, -91)

    frame.content = CreateFrame("Frame", nil, frame)
    frame.content:SetPoint("TOPLEFT", 16, -100)
    frame.content:SetPoint("BOTTOMRIGHT", -16, 12)

    -- resize: drag the bottom-right corner to make the whole window bigger or smaller (it scales,
    -- so every tab keeps its layout); the top-left corner stays put. Double-click it to reset.
    local MIN_SCALE, MAX_SCALE = 0.6, 1.8
    frame:SetScale(math.max(MIN_SCALE, math.min(MAX_SCALE, ns.settings.scale or 1)))

    local function cursor() -- in UIParent units
        local x, y = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        return x / s, y / s
    end
    local function setScale(scale, left, top)
        scale = math.max(MIN_SCALE, math.min(MAX_SCALE, scale))
        frame:SetScale(scale)
        frame:ClearAllPoints()
        -- a scaled frame's offsets are in its own units
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / scale, top / scale)
        ns.settings.scale = scale
    end

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetFrameLevel(frame:GetFrameLevel() + 20)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local scale = frame:GetScale()
        local cx, cy = cursor()
        local start = { scale = scale, left = frame:GetLeft() * scale, top = frame:GetTop() * scale, cx = cx, cy = cy }
        self:SetScript("OnUpdate", function()
            local x, y = cursor()
            local w0, h0 = WIDTH * start.scale, HEIGHT * start.scale
            local ratio = math.max((w0 + x - start.cx) / w0, (h0 + start.cy - y) / h0)
            setScale(start.scale * ratio, start.left, start.top)
        end)
    end)
    grip:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
    grip:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
    grip:SetScript("OnDoubleClick", function()
        local scale = frame:GetScale()
        setScale(1, frame:GetLeft() * scale, frame:GetTop() * scale)
    end)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Drag to resize")
        GameTooltip:AddLine("Double-click to reset the size.", 1, 1, 1)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)

    frame:SetScript("OnShow", function() ns.RefreshVisible() end)
    frame:Hide()
end

function ns.RefreshVisible()
    if not frame or not frame:IsShown() then return end
    frame.gold:SetText("All characters: " .. ns.Money(ns.TotalGold()))
    local state, version = ns.AddonUpdate()
    frame.notice:SetShown(state ~= nil)
    if state == "reload" then
        frame.notice.text:SetText("|cffffd200New version " .. version .. " installed: /reload|r")
    elseif state then
        frame.notice.text:SetText("|cffff5050Addon out of date: update it in the ZugDAQ app|r")
    end
    local p = current and pages[current]
    if p and p.frame and p.frame:IsShown() and p.frame.Refresh then p.frame:Refresh() end
end
ns.Listen("REFRESH", ns.RefreshVisible)

-- open the window at a main tab and (optionally) one of its sub-tabs
function ns.OpenView(sectionKey, subKey)
    if not frame then build() end
    frame:Show()
    showSub(sectionKey, subKey)
end

-- no argument: toggle, opening on the account overview. Otherwise a main tab, sub-tab or page key.
function ns.ToggleFrame(tab)
    if not frame then build() end
    if frame:IsShown() and not tab then
        frame:Hide()
        return
    end
    if not tab then return ns.OpenView("overview", "account") end
    if sectionByKey[tab] then return ns.OpenView(tab) end
    for _, s in ipairs(SECTIONS) do
        for _, sub in ipairs(s.subs) do
            if sub.key == tab or sub.page == tab then return ns.OpenView(s.key, sub.key) end
        end
    end
    ns.OpenView("overview", "account")
end
