local addon, ns = ...

function ns.SetLibraryBookIcon(icon)
    local atlas='Campaign-QuestLog-LoreBook-Back'
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        icon:SetAtlas(atlas,false)
    else
        icon:SetTexture('Interface\\Icons\\INV_Misc_Book_09')
    end
end

function ns.CreateHoverLocations(pins, questRows, allowed, previewChanged)
    local api = {}
    local owner, generation, active = nil, 0, 0
    local pool = {}
    function api:Clear(pin)
        if pin and pin ~= owner then return end
        generation, owner = generation + 1, nil
        for i = 1, active do
            pins:RemoveWorldMapIcon(addon, pool[i])
            pool[i]:Hide()
        end
        active = 0
        if previewChanged then previewChanged(nil) end
    end
    local function acquire(row)
        active = active + 1
        local pin = pool[active]
        if not pin then
            pin = CreateFrame('Frame', nil, UIParent)
            pin:SetSize(18, 18)
            -- Preview markers cannot steal hover or clicks from the original icon.
            pin:EnableMouse(false)
            local icon = pin:CreateTexture(nil, 'ARTWORK')
            icon:SetAllPoints()
            pin.icon = icon
            pool[active] = pin
        end
        if row.libraryBook then
            ns.SetLibraryBookIcon(pin.icon)
        elseif row.itemStarts then
            if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo('Crosshair_lootall_128') then
                pin.icon:SetAtlas('Crosshair_lootall_128', false)
            else
                pin.icon:SetTexture('Interface\\Icons\\INV_Misc_Bag_10')
            end
        elseif C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo('QuestNormal') then
            pin.icon:SetAtlas('QuestNormal', false)
        else
            pin.icon:SetTexture('Interface\\GossipFrame\\AvailableQuestIcon')
        end
        pin.icon:SetDesaturated(true)
        pin.icon:SetVertexColor(0.2, 0.65, 1, 1)
        return pin
    end
    function api:Show(pin, quests)
        self:Clear()
        local selected, selectedIDs = {}, {}
        for _, id in ipairs(quests) do
            local zones, count = questRows[id], 0
            if zones and allowed(id) and not selectedIDs[id] then
                for _, map in ipairs(zones.order) do
                    count = count + #zones[map]
                    if count > 1 then break end
                end
                if count > 1 then
                    selected[#selected + 1] = id
                    selectedIDs[id] = true
                end
            end
        end
        if #selected == 0 then return false end
        owner = pin
        if previewChanged then previewChanged(selectedIDs) end
        local token, seen = generation, {}
        local questIndex, mapIndex, rowIndex = 1, 1, 1
        local function nextRow()
            while selected[questIndex] do
                local zones = questRows[selected[questIndex]]
                local map = zones.order[mapIndex]
                if not map then
                    questIndex, mapIndex, rowIndex = questIndex + 1, 1, 1
                else
                    local row = zones[map][rowIndex]
                    if row then rowIndex = rowIndex + 1; return row end
                    mapIndex, rowIndex = mapIndex + 1, 1
                end
            end
        end
        local function batch()
            if generation ~= token then return end
            if not WorldMapFrame or not WorldMapFrame:IsShown() then self:Clear(); return end
            for i = 1, 50 do
                local row = nextRow()
                if not row then return end
                local key = row.map .. ':' .. row.x .. ':' .. row.y
                if not seen[key] then
                    seen[key] = true
                    local marker = acquire(row)
                    pins:AddWorldMapIconMap(addon, marker, row.map, row.x, row.y, 3)
                end
            end
            C_Timer.After(0, batch)
        end
        batch()
        return true
    end
    return api
end
