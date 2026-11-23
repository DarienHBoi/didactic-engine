local _, root = ...
root.PG = root.PG or {}
local ns = root.PG

-- The professions guide (was Profession Guide): a page on the main window's Crafting tab, with two views:
--   crafts  the cheapest way to the next skill point from what you know
--   get     recipes to go and get, by where they come from
-- Nothing is attached to Blizzard's profession window: the open profession is read through C_TradeSkillUI events,
-- and a click on a recipe asks the game to open it (C_TradeSkillUI.OpenRecipe), from the click itself.

local ROW_H, HEADER_H = 34, 24
local SORTS = {
    { key = "costPerPoint", label = "Sort: cost / point" },
    { key = "chance", label = "Sort: skill-up chance" },
    { key = "craftable", label = "Sort: craftable now" },
    { key = "name", label = "Sort: name" },
}

local f, scrollBox, view
local selectedSkillLine

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------

local function professionsShown()
    return ProfessionsFrame and ProfessionsFrame:IsShown()
end

local function pct(x) return string.format("%d%%", math.floor(x * 100 + 0.5)) end

local function colorize(text, rgb)
    return string.format("|cff%02x%02x%02x%s|r", rgb[1] * 255, rgb[2] * 255, rgb[3] * 255, text)
end

local function professionChoices()
    local live = ns.PlayerProfessions()
    local list, seen = {}, {}
    for skillLine, info in pairs(live) do
        table.insert(list, { id = skillLine, name = info.name })
        seen[skillLine] = true
    end
    for skillLine, entry in pairs(ZugDAQ_ProfCharDB.professions) do
        if not seen[skillLine] then table.insert(list, { id = skillLine, name = entry.name }) end
    end
    table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
    return list, live
end

local function currentSkillLine()
    -- a profession picked with the button wins until the profession window switches
    if selectedSkillLine then return selectedSkillLine end
    if professionsShown() and ns.currentSkillLine then return ns.currentSkillLine end
    local list = professionChoices()
    for _, choice in ipairs(list) do
        if ZugDAQ_ProfCharDB.professions[choice.id] then return choice.id end
    end
    return list[1] and list[1].id
end

-- only through Blizzard's own API: selecting a row in the profession window's recipe list ourselves taints the
-- window, and the game then blocks its own Create button and blames this addon
local function openRecipe(recipeID)
    if root.Trace then root.Trace("professions OpenRecipe " .. tostring(recipeID)) end
    if InCombatLockdown and InCombatLockdown() then return end
    if C_TradeSkillUI.OpenRecipe then pcall(C_TradeSkillUI.OpenRecipe, recipeID) end
end

local function insertLink(link)
    if not link then return false end
    if ChatEdit_InsertLink then return ChatEdit_InsertLink(link) end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then return ChatFrameUtil.InsertLink(link) end
    return false
end

local function linkRecipe(recipeID)
    local link = C_TradeSkillUI.GetRecipeLink and C_TradeSkillUI.GetRecipeLink(recipeID)
    if not link and C_Spell and C_Spell.GetSpellLink then link = C_Spell.GetSpellLink(recipeID) end
    insertLink(link)
end

---------------------------------------------------------------------------
-- tooltips
---------------------------------------------------------------------------

local function craftTooltip(row, data)
    local tip = GameTooltip
    tip:SetOwner(row, "ANCHOR_RIGHT")
    local color = ns.DIFF_COLORS[data.diff] or { 1, 1, 1 }
    tip:AddLine(data.name, color[1], color[2], color[3])
    local chanceText = pct(data.chance)
    if not data.measured then
        chanceText = chanceText .. " |cffaaaaaa(typical for " .. (ns.DIFF_NAMES[data.diff] or "?") .. ")|r"
    end
    tip:AddDoubleLine("Skill-up chance", chanceText, 1, 0.82, 0, 1, 1, 1)
    if data.diff == ns.DIFF.OPTIMAL and (data.recipe.ups or 1) > 1 then
        tip:AddDoubleLine("Points per craft", tostring(data.recipe.ups), 1, 0.82, 0, 1, 1, 1)
    end
    if data.expected > 0 then
        tip:AddDoubleLine("Crafts per skill point", string.format("~%.1f", data.craftsPerPoint), 1, 0.82, 0, 1, 1, 1)
        tip:AddDoubleLine("Weighted cost per point", ns.Money(data.costPerPoint), 1, 0.82, 0, 1, 1, 1)
        tip:AddDoubleLine("Gold to spend per point", ns.Money(data.spendPerPoint), 1, 0.82, 0, 1, 1, 1)
    end
    tip:AddDoubleLine("Craftable from bags", tostring(data.craftable), 1, 0.82, 0, 1, 1, 1)
    if #data.reagents > 0 then
        tip:AddLine(" ")
        tip:AddLine("Reagents per craft")
        for _, r in ipairs(data.reagents) do
            local quality = ns.ItemQuality(r.itemID)
            local left = string.format("%dx %s%s|r", r.qty, ns.QualityColor(quality), ns.ItemName(r.itemID))
            local tier = ns.ReagentTier(r.itemID)
            if tier then left = left .. " |cffaaaaaa(tier " .. tier .. ")|r" end
            local right = ns.Money(r.unit) .. " " .. (ns.SOURCE_LABELS[r.source] or r.source)
            if r.weight and r.weight ~= 1 then right = right .. string.format(" |cffaaaaaax%.2g|r", r.weight) end
            local haveColor = r.have >= r.need and "|cff80ff80" or "|cffff6666"
            right = right .. "  " .. haveColor .. "have " .. r.have .. "|r"
            tip:AddDoubleLine(left, right, 1, 1, 1, 1, 1, 1)
        end
    end
    if data.guessed then
        tip:AddLine(" ")
        tip:AddLine("Some reagent prices are guesses. Scan the auction house with Auctionator, or visit a vendor that sells them, for real numbers.", 1, 0.4, 0.4, true)
    end
    tip:AddLine(" ")
    tip:AddLine("Click: show in profession window   Shift-click: link", 0.6, 0.6, 0.6)
    tip:AddLine("Right-click: shopping list for the next 5 points", 0.6, 0.6, 0.6)
    tip:Show()
end

local function getTooltip(row, data)
    local tip = GameTooltip
    local recipe = data.recipe
    tip:SetOwner(row, "ANCHOR_RIGHT")
    local shown = false
    if recipe.teach then shown = pcall(tip.SetItemByID, tip, recipe.teach) end
    if not shown then shown = pcall(tip.SetSpellByID, tip, recipe.spell) end
    if not shown then tip:AddLine(data.name) end
    tip:AddLine(" ")
    tip:AddDoubleLine("Requires skill", tostring(recipe.skill), 1, 0.82, 0, 1, 1, 1)
    if data.perCraft then
        tip:AddDoubleLine("Weighted reagent cost per craft", ns.Money(data.perCraft), 1, 0.82, 0, 1, 1, 1)
    end
    local faction = UnitFactionGroup("player")
    for _, source in ipairs(data.sources) do
        if source == "trainer" then
            tip:AddDoubleLine("Trainer", recipe.cost and recipe.cost > 0 and ns.Money(recipe.cost) or "", 0.5, 1, 0.5, 1, 1, 1)
        elseif source == "vendor" then
            tip:AddLine("Sold by", 0.5, 1, 0.5)
            local shownCount, total = 0, 0
            for _, vendor in ipairs(recipe.vendors or {}) do
                if not vendor.faction or vendor.faction == faction then
                    total = total + 1
                    if shownCount < 8 then
                        shownCount = shownCount + 1
                        local zones = ns.LocationZones({ vendor }, faction)
                        tip:AddDoubleLine("  " .. (ns.NpcName(vendor.npc) or ("NPC " .. vendor.npc)),
                            table.concat(zones, ", "), 1, 1, 1, 0.7, 0.7, 0.7)
                    end
                end
            end
            if total > shownCount then tip:AddLine(string.format("  ...and %d more", total - shownCount), 0.7, 0.7, 0.7) end
        elseif source == "quest" then
            local zones = ns.LocationZones(recipe.quests, faction)
            tip:AddDoubleLine("Quest reward", table.concat(zones, ", "), 0.5, 1, 0.5, 0.7, 0.7, 0.7)
        elseif source == "drop" then
            tip:AddLine("Drops in the world (check the auction house too)", 0.5, 1, 0.5)
        else
            tip:AddLine(ns.SOURCE_NAMES[source] or source, 0.5, 1, 0.5)
        end
    end
    for _, note in ipairs(data.notes or {}) do tip:AddLine(note, 1, 1, 1, true) end
    tip:Show()
end

---------------------------------------------------------------------------
-- rows
---------------------------------------------------------------------------

local function setupRow(row)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 1, 1, 0.08)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(26, 26)
    row.icon:SetPoint("LEFT", 4, 0)

    row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.value:SetPoint("TOPRIGHT", -6, -3)
    row.value:SetJustifyH("RIGHT")
    row.value2 = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.value2:SetPoint("BOTTOMRIGHT", -6, 4)
    row.value2:SetJustifyH("RIGHT")

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, 0)
    row.name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -120, -4)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 0)
    row.sub:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -120, 4)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(false)

    row.heading = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.heading:SetPoint("LEFT", 6, 0)
    row.heading:SetPoint("RIGHT", -6, 0)
    row.heading:SetJustifyH("LEFT")

    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnEnter", function(self)
        local data = self.data
        if not data or data.header then return end
        if data.kind == "craft" then craftTooltip(self, data) else getTooltip(self, data) end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self, button)
        local data = self.data
        if not data or data.header then return end
        if data.kind == "craft" then
            if button == "RightButton" then
                local crafts = data.expected > 0 and math.ceil(5 / data.expected) or 5
                local _, _, reagents, missing = ns.CostRecipe(data.recipe, crafts, nil)
                ns.MakeShoppingList(string.format("%dx %s", crafts, data.name), missing)
            elseif IsModifiedClick("CHATLINK") then
                linkRecipe(data.id)
            else
                openRecipe(data.id)
            end
        elseif IsModifiedClick("CHATLINK") then
            if data.recipe.teach then
                local link = select(2, ns.GetItemInfo(data.recipe.teach))
                if link then insertLink(link) return end
            end
            linkRecipe(data.spell)
        end
    end)
    row.pgReady = true
end

local function initRow(row, data)
    if not row.pgReady then setupRow(row) end
    row.data = data
    if data.header then
        row.icon:Hide(); row.name:Hide(); row.sub:Hide(); row.value:Hide(); row.value2:Hide()
        row.heading:Show()
        row.heading:SetText(data.header)
        row.bg:SetColorTexture(0.25, 0.2, 0.1, 0.6)
        row.hl:Hide()
        return
    end
    row.heading:Hide()
    row.icon:Show(); row.name:Show(); row.sub:Show(); row.value:Show(); row.value2:Show()
    row.hl:Show()
    row.bg:SetColorTexture(1, 1, 1, data.stripe and 0.03 or 0)
    row.icon:SetTexture(data.icon or "Interface\\Icons\\INV_Misc_QuestionMark")

    if data.kind == "craft" then
        local color = ns.DIFF_COLORS[data.diff] or { 1, 1, 1 }
        row.name:SetText(data.name)
        row.name:SetTextColor(color[1], color[2], color[3])
        local parts = {}
        if data.expected > 0 then
            table.insert(parts, (data.measured and "" or "~") .. pct(data.chance) .. " chance")
            if data.craftsPerPoint > 1.05 then table.insert(parts, string.format("%.1f crafts/pt", data.craftsPerPoint)) end
        else
            table.insert(parts, "no skill-ups")
        end
        if data.craftable > 0 then
            table.insert(parts, "|cff80ff80can make " .. data.craftable .. "|r")
        elseif #data.missing > 0 then
            table.insert(parts, "|cffff8080missing " .. #data.missing .. " reagent" .. (#data.missing > 1 and "s" or "") .. "|r")
        end
        row.sub:SetText(table.concat(parts, " · "))
        if data.expected > 0 then
            row.value:SetText(ns.Money(data.costPerPoint) .. (data.guessed and "|cffff6666?|r" or "") .. " /pt")
        else
            row.value:SetText("-")
        end
        row.value2:SetText("per craft " .. ns.Money(data.perCraft))
    else
        row.name:SetText(data.name)
        row.name:SetTextColor(1, 0.82, 0)
        local notes = data.notes and #data.notes > 0 and ("  " .. table.concat(data.notes, " ")) or ""
        row.sub:SetText(data.sourceText .. notes)
        if data.delta <= 0 then
            row.value:SetText("|cff80ff80skill " .. data.skill .. "|r")
        else
            row.value:SetText(string.format("|cffffb84dskill %d (+%d)|r", data.skill, data.delta))
        end
        row.value2:SetText(data.perCraft and ("craft ~" .. ns.Money(data.perCraft)) or "")
    end
end

---------------------------------------------------------------------------
-- rendering
---------------------------------------------------------------------------

local function setData(elements)
    local provider = CreateDataProvider(elements)
    local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
    scrollBox:SetDataProvider(provider, retain)
    f.empty:SetShown(#elements == 0)
end

local function vendorPriceCount()
    local n = 0
    for _ in pairs(ZugDAQ_ProfDB.vendorPrices) do n = n + 1 end
    return n
end

local function renderCrafts(skillLine, live)
    local rows, _, rank, entry = ns.Evaluate(skillLine)
    if not entry then
        f.best:SetText("")
        f.empty:SetText("Open this profession once so its recipes can be read.")
        setData({})
        return
    end
    local best
    for _, row in ipairs(rows) do
        if row.expected > 0 and (not best or row.costPerPoint < best.costPerPoint) then best = row end
    end
    if best then
        local color = ns.DIFF_COLORS[best.diff] or { 1, 1, 1 }
        f.best:SetText(string.format("Cheapest next point: %s  ~%s (%.1f crafts)",
            colorize(best.name, color), ns.Money(best.costPerPoint), best.craftsPerPoint))
    else
        f.best:SetText("Nothing you know still gives skill-ups. Check the Recipes to Get tab.")
    end
    for i, row in ipairs(rows) do
        row.kind = "craft"
        row.stripe = i % 2 == 0
    end
    f.empty:SetText(ns.settings.onlyCraftable and "Nothing craftable from your bags right now."
        or "No recipes to show.")
    setData(rows)
    if not professionsShown() and entry.time then
        local minutes = math.floor((time() - entry.time) / 60)
        f.footerExtra = string.format("recipes read %s ago", minutes < 60 and (minutes .. "m")
            or (math.floor(minutes / 60) .. "h"))
    end
end

local function renderGet(skillLine, live)
    local info = live[skillLine] or ZugDAQ_ProfCharDB.professions[skillLine]
    if not info then
        f.best:SetText("")
        setData({})
        return
    end
    local groups = ns.RecipesToGet(skillLine, info.rank or 0, info.maxRank or 0)
    local elements = {}
    local function addGroup(title, rows)
        if not rows or #rows == 0 then return end
        table.insert(elements, { header = string.format("%s  |cffaaaaaa(%d)|r", title, #rows) })
        for i, row in ipairs(rows) do
            row.kind = "get"
            row.stripe = i % 2 == 0
            table.insert(elements, row)
        end
    end
    addGroup("Train the next rank", groups.rank)
    addGroup("Learn now", groups.now)
    addGroup(string.format("Coming up (next %d points)", ns.settings.farLookahead and 75 or 25), groups.soon)
    local nowCount = groups.now and #groups.now or 0
    f.best:SetText(nowCount > 0 and string.format("%d recipe%s you can learn right now.", nowCount, nowCount > 1 and "s" or "")
        or "Nothing new to learn at your skill. Look at what is coming up.")
    f.empty:SetText(ns.Recipes[skillLine] and "No recipes to get near your skill." or "No recipe data for this profession.")
    setData(elements)
end

local function render()
    if not (f and f:IsVisible()) then return end
    local skillLine = currentSkillLine()
    local _, live = professionChoices()
    f.footerExtra = nil
    local tab = ns.settings.tab == "get" and "get" or "crafts"
    for _, w in ipairs(f.craftWidgets) do w:SetShown(tab == "crafts") end
    for _, w in ipairs(f.getWidgets) do w:SetShown(tab == "get") end
    f.sortButton:SetText(SORTS[1].label)
    for _, sort in ipairs(SORTS) do
        if sort.key == ns.settings.sortKey then f.sortButton:SetText(sort.label) end
    end

    if not skillLine then
        f.profText:SetText("No profession")
        f.best:SetText("")
        f.empty:SetText("Learn a profession, then open it once.")
        setData({})
    else
        local entry = ZugDAQ_ProfCharDB.professions[skillLine]
        local info = live[skillLine] or entry
        local rank, maxRank = info and info.rank or 0, info and info.maxRank or 0
        if entry and entry.rank > rank then rank = entry.rank end
        f.profText:SetText(string.format("%s  |cffffffff%d / %d|r", info and info.name or "?", rank, maxRank))
        if tab == "crafts" then renderCrafts(skillLine, live) else renderGet(skillLine, live) end
    end
    local prices = ns.HasAuctionator() and "|cff80ff80Auctionator prices|r"
        or (root.AppData and root.AppData()) and "|cff80ff80prices from the ZugDAQ app|r"
        or "|cffff6666no Auctionator or app prices: costs are estimates|r"
    f.footer:SetText(string.format("%s · %d vendor prices seen%s", prices, vendorPriceCount(),
        f.footerExtra and (" · " .. f.footerExtra) or ""))
end
ns.Render = render

---------------------------------------------------------------------------
-- the page (main window: Crafting > Skill-ups / Recipes to get)
---------------------------------------------------------------------------

local function makeCheck(parent, label, key, tooltip)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(22, 22)
    local text = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", check, "RIGHT", 1, 0)
    text:SetText(label)
    check.label = text
    check.width = 26 + text:GetStringWidth() + 14
    check:SetChecked(ns.settings[key])
    check:SetScript("OnClick", function(self)
        ns.settings[key] = self:GetChecked() and true or false
        render()
    end)
    check:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(label)
        GameTooltip:AddLine(tooltip, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    check:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return check
end

-- a row of widgets left to right from (x, y)
local function lineUp(widgets, x, y)
    for _, w in ipairs(widgets) do
        w:SetPoint("TOPLEFT", x, y)
        x = x + (w.width or w:GetWidth()) + 6
    end
end

local function build(page)
    f = page
    local W = root.PAGE_WIDTH or 788

    f.profText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.profText:SetPoint("TOPLEFT", 0, -2)

    local profButton = root.Button(f, "Next profession", 120, function()
        local list = professionChoices()
        if #list == 0 then return end
        local current, index = currentSkillLine(), 1
        for i, choice in ipairs(list) do
            if choice.id == current then index = i % #list + 1 end
        end
        selectedSkillLine = list[index].id
        render()
    end)
    profButton:SetPoint("TOPRIGHT", 0, 0)
    f.profButton = profButton

    f.best = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.best:SetPoint("TOPLEFT", 0, -26)
    f.best:SetPoint("TOPRIGHT", 0, -26)
    f.best:SetJustifyH("LEFT")
    f.best:SetWordWrap(false)

    local sort = root.Button(f, SORTS[1].label, 150, function()
        local index = 1
        for i, s in ipairs(SORTS) do
            if s.key == ns.settings.sortKey then index = i % #SORTS + 1 end
        end
        ns.settings.sortKey = SORTS[index].key
        render()
    end)
    f.sortButton = sort
    f.craftWidgets = {
        sort,
        makeCheck(f, "Use bag items", "bagDiscount",
            "Reagents you already own count for less: common ones are nearly free, rare ones keep their full value so they are not burned."),
        makeCheck(f, "Hide gray", "hideTrivial", "Hide recipes that can no longer give skill-ups."),
        makeCheck(f, "Craftable only", "onlyCraftable", "Only show recipes your bags can make right now."),
    }
    lineUp(f.craftWidgets, 0, -44)
    f.getWidgets = {
        makeCheck(f, "Look 75 points ahead", "farLookahead", "Show recipes up to 75 skill points above you instead of 25."),
    }
    lineUp(f.getWidgets, 0, -44)

    local box = CreateFrame("Frame", nil, f, "WowScrollBoxList")
    box:SetPoint("TOPLEFT", 0, -72)
    box:SetPoint("BOTTOMRIGHT", -18, 20)
    local bar = CreateFrame("EventFrame", nil, f, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 6, 0)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 6, 0)
    view = CreateScrollBoxListLinearView()
    view:SetElementInitializer("Button", initRow)
    if view.SetElementExtentCalculator then
        view:SetElementExtentCalculator(function(_, data) return data.header and HEADER_H or ROW_H end)
    else
        view:SetElementExtent(ROW_H)
    end
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
    scrollBox = box

    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    f.empty:SetPoint("CENTER", box, "CENTER")
    f.empty:SetWidth(W - 120)

    f.footer = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.footer:SetPoint("BOTTOMLEFT", 0, 2)
    f.footer:SetPoint("BOTTOMRIGHT", 0, 2)
    f.footer:SetJustifyH("LEFT")
    f.footer:SetWordWrap(false)

    function page:Refresh()
        ns.settings.tab = self.view == "get" and "get" or "crafts"
        render()
    end
end

if root.RegisterPage then root.RegisterPage("skillups", "Skill-ups", build) end

-- /pg, and the old minimap-menu entry: open the guide on the main window
function ns.ToggleFrame()
    if root.ToggleFrame then root.ToggleFrame("skillups") end
end

---------------------------------------------------------------------------
-- keeping it current
---------------------------------------------------------------------------

-- refresh: re-read the open profession (while the game's profession window is open), then redraw
ns.OnRefresh(function()
    if professionsShown() then
        local before = ns.currentSkillLine
        ns.ScanOpenProfession()
        -- switching professions in the game's window clears a pick made with the button
        if before and ns.currentSkillLine ~= before then selectedSkillLine = nil end
    end
    render()
end)

local events = CreateFrame("Frame")
for _, event in ipairs({
    "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "NEW_RECIPE_LEARNED",
    "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "SPELL_DATA_LOAD_RESULT",
}) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, arg1)
    if root.Trace then root.Trace("professions " .. event) end
    if event == "SPELL_DATA_LOAD_RESULT" then
        if ns.SpellRequested(arg1) and f and f:IsVisible() then ns.RequestRefresh() end
        return
    end
    if event == "TRADE_SKILL_SHOW" then selectedSkillLine = nil end
    ns.RequestRefresh()
end)

