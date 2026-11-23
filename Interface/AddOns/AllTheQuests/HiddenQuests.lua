local _, ns = ...

function ns.CreateHiddenQuests(settings, quests, changed, allowed)
    if type(settings.hiddenQuests) ~= 'table' then settings.hiddenQuests = {} end
    if type(settings.hideHistory) ~= 'table' then settings.hideHistory = {} end
    local api = {}
    function api:IsHidden(id) return settings.hiddenQuests[id] == true end
    function api:Count()
        local count = 0
        for _, hidden in pairs(settings.hiddenQuests) do if hidden == true then count = count + 1 end end
        return count
    end
    function api:CanUndo()
        for i = #settings.hideHistory, 1, -1 do
            if self:IsHidden(settings.hideHistory[i]) then return true end
        end
        return false
    end
    function api:Hide(id)
        if type(id) ~= 'number' or id <= 0 or id ~= math.floor(id) or self:IsHidden(id) then return end
        settings.hiddenQuests[id] = true
        settings.hideHistory[#settings.hideHistory + 1] = id
        if GameTooltip then GameTooltip:Hide() end
        changed()
    end
    function api:Undo()
        while #settings.hideHistory > 0 do
            local id = table.remove(settings.hideHistory)
            if self:IsHidden(id) then
                settings.hiddenQuests[id] = nil
                changed()
                return id
            end
        end
    end
    function api:RestoreAll()
        settings.hiddenQuests, settings.hideHistory = {}, {}
        changed()
    end
    function api:Click(pin, button)
        if button ~= 'RightButton' or not IsControlKeyDown or not IsControlKeyDown() then return end
        local visible, seen = {}, {}
        for _, id in ipairs(pin.row and pin.row.quests or {}) do
            if not seen[id] and not self:IsHidden(id) and allowed(id) then
                visible[#visible + 1], seen[id] = id, true
            end
        end
        if #visible == 1 then self:Hide(visible[1]); return end
        if #visible == 0 then return end
        if not (MenuUtil and MenuUtil.CreateContextMenu) then
            print('AllTheQuests: the quest selection menu is unavailable in this client.')
            return
        end
        if GameTooltip then GameTooltip:Hide() end
        MenuUtil.CreateContextMenu(pin, function(_, root)
            root:CreateTitle('Hide a quest on this character')
            for _, id in ipairs(visible) do
                local label = ('[%s] %s'):format(quests.Get(id, 'questLevel') or '?', quests.Get(id, 'name') or ('Quest ' .. id))
                root:CreateButton(label, function() self:Hide(id) end)
            end
        end)
    end
    return api
end
