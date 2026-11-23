local addon, ns = ...
local F = CreateFrame('Frame')
local pins, db, Q, maps, index, geometry, database
local lastX, lastY, lastInstance
local skillsDirty, sortedMap, spatial = true, nil, nil
local pool, used = {}, 0
local rendered, questRows, levelBuckets = {}, {}, {}
local finished, scanRunning, scanStatus = {}, false, "Completion scan pending"
local defaults = {hideHigh=true, hideGrey=false, hideCompleted=true, hideRepeatable=true, hideIneligible=true, hideInactiveEvents=true, immersive=false, world=true}
local function completed(id)
    return (not ns.holidays[id] and finished[id]) or C_QuestLog.IsQuestFlaggedCompleted(id)
end
local repeatableCache = {}
local function isRepeatable(id)
    if repeatableCache[id]==nil then
        local special=Q.Get(id,'specialFlags') or 0
        local flags=Q.Get(id,'questFlags') or 0
        repeatableCache[id]=special%2==1 or math.floor(flags/4096)%2==1
            or math.floor(flags/32768)%2==1 or math.floor(flags/65536)%2==1
    end
    return repeatableCache[id]
end
local eligibility, hiddenQuests, hoverLocations
local previewQuestIDs
local itemSourceText = {
    ['Possible drop source'] = {'Drops from this creature', 'Drop not guaranteed.'},
    ['Possible container source'] = {'Found in this object', 'Contents may vary.'},
    ['Possible vendor source'] = {'Sold by this vendor', 'Stock may vary.'},
    ['Possible item source'] = {'Item source', 'Availability may vary.'},
}
local function updatePinArtwork(pin)
    local hide = false
    if previewQuestIDs then
        for _, id in ipairs(pin.row.quests) do if previewQuestIDs[id] then hide = true; break end end
    end
    pin.icon:SetShown(pin.atqNormal and not hide)
    pin.repeatIcon:SetShown(pin.atqRepeatable and not hide)
end
local function previewChanged(ids)
    previewQuestIDs = ids
    for _, entry in pairs(rendered) do updatePinArtwork(entry.pin) end
end
local function refreshSkills() eligibility:RefreshSkills() end
local function meetsRequirements(id) return eligibility:Allows(id) end
local function allowed(id)
    if hiddenQuests and hiddenQuests:IsHidden(id) then return false end
    if db.hideInactiveEvents and ns.HolidayInactive(id) then return false end
    if db.hideIneligible and not meetsRequirements(id) then return false end
    if db.hideRepeatable and isRepeatable(id) then return false end
    if db.hideCompleted and completed(id) then return false end
    if db.hideHigh or db.hideGrey then
        local playerLevel, questLevel = UnitLevel('player'), Q.Get(id,'questLevel') or 0
        if db.hideHigh and math.max(Q.Get(id,'requiredLevel') or 0,questLevel)>playerLevel then return false end
        if db.hideGrey and questLevel>0 and playerLevel-questLevel>=7 then return false end
    end
    if C_QuestLog.IsOnQuest(id) then return false end
    local _,_,race = UnitRace('player')
    local mask = database.Enum.raceMaskById[race]
    local required = Q.Get(id,'requiredRaces') or 0
    -- Arithmetic supports Forever race bits above bit library's 32-bit range.
    if required>0 and mask and math.floor(required/mask)%2<1 then return false end
    local _,_,class = UnitClass('player')
    required=Q.Get(id,'requiredClasses') or 0
    if required>0 and math.floor(required/2^(class-1))%2<1 then return false end
    return true
end
-- Forever library turn-ins list the pickup object alongside the trainers.
local libraryBookQuests={
    [78124]=true,[78127]=true,[78142]=true,[78143]=true,[78145]=true,[78146]=true,
    [78147]=true,[78148]=true,[78149]=true,[79091]=true,[79092]=true,[79093]=true,
    [79094]=true,[79095]=true,[79096]=true,[79097]=true,[79535]=true,[79947]=true,
    [79948]=true,[79949]=true,[79950]=true,[79951]=true,[79952]=true,[79953]=true,
    [81947]=true,[81949]=true,[81952]=true,[81953]=true,[81954]=true,[81955]=true,
    [81956]=true,[84395]=true,[84396]=true,[84397]=true,[84398]=true,[84399]=true,
    [84400]=true,[84401]=true,[84402]=true,
}
local function acquire(row, parent)
    used=used+1
    local p=pool[used]
    if not p then
        p=CreateFrame('Button',nil,UIParent)
        p:SetSize(20,20)
        p:RegisterForClicks('RightButtonUp')
        p:SetScript('OnClick',function(self,button) hiddenQuests:Click(self,button) end)
        p.icon=p:CreateTexture(nil,'ARTWORK')
        p.icon:SetAllPoints()
        p.repeatIcon=p:CreateTexture(nil,'OVERLAY')
        p.repeatIcon:SetSize(20,20)
        p.repeatIcon:SetTexture('Interface\\GossipFrame\\ActiveQuestIcon')
        p.repeatIcon:SetDesaturated(true)
        p.repeatIcon:SetVertexColor(0.15,0.65,1)
        p:SetScript('OnEnter',function(self)
            GameTooltip:SetOwner(self,'ANCHOR_RIGHT')
            GameTooltip:SetText(self.row.libraryBook and 'Library book pickup' or self.row.name)
            for _,id in ipairs(self.row.quests) do
                if allowed(id) then
                    GameTooltip:AddLine(('[%s] %s%s'):format(Q.Get(id,'questLevel') or '?',Q.Get(id,'name') or ('Quest '..id),(isRepeatable(id) and ' (repeatable)' or '')..(completed(id) and ' (completed)' or '')),1,0.82,0,true)
                    local items=self.row.itemStarts and self.row.itemStarts[id]
                    if items then
                        for itemID in pairs(items) do
                            GameTooltip:AddLine('Quest item: '..(database.Item.Get(itemID,'name') or ('Item '..itemID)),0.7,0.9,1,true)
                        end
                    end
                end
            end
            if self.row.itemStarts then
                local source = itemSourceText[self.row.itemSource] or itemSourceText['Possible item source']
                GameTooltip:AddLine(source[1],0.8,0.8,0.8)
                GameTooltip:AddLine(source[2],0.6,0.6,0.6)
            end
            if hoverLocations:Show(self,self.row.quests) then
                GameTooltip:AddLine('Hover to see all known locations',0.4,0.8,1)
            end
            GameTooltip:AddLine('Ctrl + right-click: hide quest',0.4,0.8,1)
            GameTooltip:Show()
        end)
        p:SetScript('OnLeave',function(self) hoverLocations:Clear(self); GameTooltip:Hide() end)
        pool[used]=p
    end
    p:SetParent(parent); p.row=row
    p.icon:SetDesaturated(false)
    p.icon:SetVertexColor(1,1,1,1)
    p.icon:SetTexCoord(0,1,0,1)
    if row.libraryBook then
        ns.SetLibraryBookIcon(p.icon)
    elseif row.itemStarts then
        if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo('Crosshair_lootall_128') then
            p.icon:SetAtlas('Crosshair_lootall_128',false)
        else
            p.icon:SetTexture('Interface\\Icons\\INV_Misc_Bag_10')
        end
    elseif C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo('QuestNormal') then
        p.icon:SetAtlas('QuestNormal',false)
    else
        p.icon:SetTexture('Interface\\GossipFrame\\AvailableQuestIcon')
    end
    local repeatable, normal = false, false
    for _,id in ipairs(row.quests) do
        if isRepeatable(id) then repeatable=true else normal=true end
    end
    p.atqNormal, p.atqRepeatable = normal or row.itemStarts~=nil or row.libraryBook==true, repeatable
    p.repeatIcon:ClearAllPoints()
    -- Mixed givers retain their normal marker and show a blue ? alongside it.
    p.repeatIcon:SetPoint('CENTER',p,'CENTER',p.atqNormal and 12 or 0,0)
    updatePinArtwork(p)
    p:Show()
    return p
end
local function itemVisibleOnMap(row, viewedMap)
    if not viewedMap then return false end
    if row.map ~= viewedMap and viewedMap ~= 947 then
        local map = geometry.mapData[row.map]
        while map and map.parent ~= viewedMap do map = geometry.mapData[map.parent] end
        if not map then return false end
        local target = geometry.mapData[viewedMap]
        local kind = target and target.mapType
        local types = Enum.UIMapType
        if kind ~= types.Continent and kind ~= types.Zone and kind ~= types.Dungeon and kind ~= types.Micro then
            return false
        end
    end
    local x,y,instance = geometry:GetWorldCoordinatesFromZone(row.x,row.y,row.map)
    if not x then return false end
    return geometry:GetZoneCoordinatesFromWorldInstance(x,y,instance,viewedMap) ~= nil
end
local function refresh()
    if not index or not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    if not db.world then
        hoverLocations:Clear()
        for key,entry in pairs(rendered) do pins:RemoveWorldMapIcon(addon,entry.pin); entry.pin:Hide(); entry.pin.atqInUse=false; rendered[key]=nil end
        return
    end
    local wanted={}
    if skillsDirty then skillsDirty=false; refreshSkills() end
    ns.UpdateHolidays()
    local current=C_Map.GetBestMapForUnit('player')
    local candidates, itemChoices, itemVisibility = {}, {}, {}
    local viewedMap = WorldMapFrame:GetMapID()
    local function itemVisible(row)
        if itemVisibility[row] == nil then itemVisibility[row] = itemVisibleOnMap(row,viewedMap) end
        return itemVisibility[row]
    end
    if not db.immersive then
        local unique={}
        for id,zones in pairs(questRows) do
            if allowed(id) then
                local count=0
                local function addCandidate(row)
                    if not unique[row] then candidates[#candidates+1]=row; unique[row]=true end
                end
                if zones.hasDrop then
                    local best
                    for _,mapID in ipairs(zones.order) do
                        for _,row in ipairs(zones[mapID]) do
                            if row.itemStarts and itemVisible(row) and
                                (not best or (row.map==viewedMap and best.map~=viewedMap)
                                    or ((row.map==viewedMap)==(best.map==viewedMap) and row.key<best.key)) then
                                best=row
                            end
                        end
                    end
                    if best then itemChoices[id]=best; addCandidate(best); count=1 end
                end
                local function take(rows)
                    for _,row in ipairs(rows or {}) do
                        if count>=2 then break end
                        if not (zones.hasDrop and row.itemStarts) then
                            count=count+1
                            addCandidate(row)
                        end
                    end
                end
                take(zones[current])
                if count<2 then
                    for _,mapID in ipairs(zones.order) do
                        if mapID~=current then take(zones[mapID]) end
                        if count>=2 then break end
                    end
                end
            end
        end
    end
    if db.immersive then
        local px,py,instance=geometry:GetPlayerWorldPosition()
        lastX,lastY,lastInstance=px,py,instance
        candidates={}
        if px and py and instance then
            if not spatial then
                spatial={}
                for _,row in ipairs(index) do
                    row.wx,row.wy,row.instance=geometry:GetWorldCoordinatesFromZone(row.x,row.y,row.map)
                    if row.wx and row.wy and row.instance then
                        local key=row.instance..':'..math.floor(row.wx/500)..':'..math.floor(row.wy/500)
                        spatial[key]=spatial[key] or {}
                        local bucket=spatial[key]; bucket[#bucket+1]=row
                    end
                end
            end
            local cx,cy=math.floor(px/500),math.floor(py/500)
            for gx=cx-1,cx+1 do
                for gy=cy-1,cy+1 do
                    local bucket=spatial[instance..':'..gx..':'..gy]
                    if bucket then
                        for _,row in ipairs(bucket) do
                            local dx,dy=row.wx-px,row.wy-py
                            if dx*dx+dy*dy<=500*500 then candidates[#candidates+1]=row end
                        end
                    end
                end
            end
        end
    end
    -- Prefer the player's zone, with stable ordering across reloads/events.
    if true then
    table.sort(candidates,function(a,b)
        if a.map~=b.map then
            if a.map==current then return true end
            if b.map==current then return false end
            return a.map<b.map
        end
        if a.x~=b.x then return a.x<b.x end
        if a.y~=b.y then return a.y<b.y end
        if a.name~=b.name then return a.name<b.name end
        return a.key<b.key
    end)
    if not db.immersive then sortedMap=current end
    end
    local counts, eligibility, locations, itemShown = {}, {}, {}, {}
    for _,row in ipairs(candidates) do
        local selected, seen = {}, {}
        for _,id in ipairs(row.quests) do
            if eligibility[id]==nil then eligibility[id]=allowed(id) and true or false end
            local location=row.map..':'..row.x..':'..row.y
            locations[id]=locations[id] or {}
            local limitedItem = row.itemStarts and questRows[id].hasDrop
            local showItem = not limitedItem or (not itemShown[id] and
                (itemChoices[id]==row or (db.immersive and itemVisible(row))))
            local limit = not db.immersive and itemChoices[id] and not limitedItem and not itemShown[id] and 1 or 2
            if showItem and not seen[id] and eligibility[id] and (counts[id] or 0)<limit and not locations[id][location] then
                selected[#selected+1]=id
                if limitedItem then itemShown[id]=true end
                counts[id]=(counts[id] or 0)+1
                locations[id][location]=true
            end
            seen[id]=true
        end
        if #selected>0 then
            -- Tooltip lists only quests allocated to this pin, including shared givers.
            local shown={map=row.map,x=row.x,y=row.y,name=row.name,quests=selected,itemStarts=row.itemStarts,itemSource=row.itemSource,libraryBook=row.libraryBook}
            table.sort(selected)
            local key=row.key or (row.map..':'..row.x..':'..row.y..':'..row.name)
            local signature=table.concat(selected,',')
            wanted[key]=true
            local old=rendered[key]
            if not old or old.signature~=signature then
                if old then hoverLocations:Clear(old.pin); pins:RemoveWorldMapIcon(addon,old.pin); old.pin:Hide(); old.pin.atqInUse=false end
                -- Reuse a hidden frame rather than allocating on every rebuild.
                local slot
                for i,p in ipairs(pool) do if not p.atqInUse then slot=i; break end end
                used=slot and slot-1 or #pool
                local pin=acquire(shown,UIParent); pin.atqInUse=true
                pins:AddWorldMapIconMap(addon,pin,row.map,row.x,row.y,3)
                rendered[key]={pin=pin,signature=signature}
            end
        end
    end
    for key,entry in pairs(rendered) do
        if not wanted[key] then hoverLocations:Clear(entry.pin); pins:RemoveWorldMapIcon(addon,entry.pin); entry.pin:Hide(); entry.pin.atqInUse=false; rendered[key]=nil end
    end
end
local pending
local function schedule()
    if pending or not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    pending=true
    C_Timer.After(1,function() pending=false; refresh() end)
end
local function updateScanStatus(message)
    scanStatus=message
    if F.options then
        F.options.status:SetText(message)
        F.options.scan:SetEnabled(not scanRunning)
    end
end
local function scanCompleted()
    if scanRunning or not Q then return end
    scanRunning=true
    if not index then scanRunning=false; updateScanStatus('Waiting for quest data...'); return end
    local levels={}
    for level in pairs(levelBuckets) do levels[#levels+1]=level end
    table.sort(levels)
    local li,qi,checked,found=1,1,0,0
    updateScanStatus('Checking completed quests, lowest levels first...')
    local function batch()
        for n=1,150 do
            local bucket=levels[li] and levelBuckets[levels[li]]
            if not bucket then
                scanRunning=false
                updateScanStatus(('Checked %d quests; %d completed.'):format(checked,found))
                schedule(); return
            end
            local id=bucket[qi]
            qi=qi+1
            if qi>#bucket then li=li+1; qi=1 end
            checked=checked+1
            if completed(id) then
                found=found+1
                if not isRepeatable(id) and not ns.holidays[id] then finished[id]=true end
            end
        end
        updateScanStatus(('Checked %d quests (level %d)...'):format(checked,levels[li] or 0))
        C_Timer.After(0.02,batch)
    end
    batch()
end
local coordinateCVars={'worldMapShowPlayerCoords','worldMapShowCursorCoords'}
local function getCoordinateSettings()
    local get=C_CVar and C_CVar.GetCVar or GetCVar
    if not get then return false,false end
    local player,cursor=get(coordinateCVars[1]),get(coordinateCVars[2])
    return player=='1' and cursor=='1',player~=nil and cursor~=nil
end
local function setCoordinateSettings(enabled)
    local set=C_CVar and C_CVar.SetCVar or SetCVar
    if not set then return end
    for _,name in ipairs(coordinateCVars) do set(name,enabled and '1' or '0') end
end
local function optionTooltip(control, title, description)
    control:SetScript('OnEnter',function(self)
        GameTooltip:SetOwner(self,'ANCHOR_RIGHT')
        GameTooltip:SetText(title)
        GameTooltip:AddLine(description,1,1,1,true)
        GameTooltip:Show()
    end)
    control:SetScript('OnLeave',function(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
end
local function options()
    if not F.options then
        local w=CreateFrame('Frame','AllTheQuestsOptions',UIParent,'DefaultPanelTemplate')
        F.options=w
        w:SetSize(404,378)
        w:SetFrameStrata('DIALOG')
        w:SetPoint('CENTER')
        w:SetClampedToScreen(true)
        w:SetMovable(true)
        w:EnableMouse(true)
        w:RegisterForDrag('LeftButton')
        w:SetScript('OnDragStart',w.StartMoving)
        w:SetScript('OnDragStop',w.StopMovingOrSizing)
        w.TitleContainer.TitleText:SetText('All the Quests |cffc9a45c- Settings|r')
        w.CloseButton=CreateFrame('Button',nil,w,'UIPanelCloseButtonDefaultAnchors')
        table.insert(UISpecialFrames,'AllTheQuestsOptions')

        local function label(text, x, y, font)
            local line=w:CreateFontString(nil,'OVERLAY',font)
            line:SetPoint('TOPLEFT',x,y)
            line:SetJustifyH('LEFT')
            line:SetText(text)
            return line
        end
        local function button(text, x, y, onClick, description)
            local control=CreateFrame('Button',nil,w,'UIPanelButtonTemplate')
            control:SetSize(178,24)
            control:SetPoint('TOPLEFT',x,y)
            control:SetText(text)
            control:SetScript('OnClick',onClick)
            optionTooltip(control,text,description)
            return control
        end
        label('Map filters',18,-34,'GameFontNormal')
        local filters = {
            {'hideHigh', 'Hide above my level', 16, 1, 'Hides quests above your character level.'},
            {'hideIneligible', 'Hide ineligible quests', 206, 1, 'Attempts to hide quests whose requirements you do not meet.'},
            {'hideCompleted', 'Hide completed quests', 16, 2, 'Hides quests marked as completed.'},
            {'hideGrey', 'Hide low-level quests', 206, 2, 'Attempts to hide quests that would be gray to you (7 or more levels below you).'},
            {'hideRepeatable', 'Hide repeatable quests', 16, 3, 'Hides quests marked as repeatable.'},
            {'hideInactiveEvents', 'Hide inactive events', 206, 3, 'Attempts to hide quests for holidays and events that are inactive.'},
            {'world', 'Show world map icons', 16, 4, 'Shows quest markers on the world map.'},
            {'immersive', 'Immersive mode (500 yd)', 206, 4, 'Only shows quest markers within 500 yards of your character.'},
            {'showCoordinates', 'Show coordinates', 16, 5, 'Toggles Blizzard’s player and mouse coordinates on the world map.'},
        }
        for _,entry in ipairs(filters) do
            local key, text, x, row, description=unpack(entry)
            local b=CreateFrame('CheckButton',nil,w,'SettingsCheckboxTemplate')
            b:SetSize(24,24)
            b:SetPoint('TOPLEFT',x,-50-(row-1)*28)
            optionTooltip(b,text,description)
            local caption=b:CreateFontString(nil,'OVERLAY','GameFontHighlight')
            caption:SetPoint('LEFT',b,'RIGHT',4,0)
            caption:SetText(text)
            b:SetHitRectInsets(0,-caption:GetStringWidth()-4,0,0)
            if key=='showCoordinates' then
                w.coordinates=b
                b:SetScript('OnClick',function(self)
                    setCoordinateSettings(self:GetChecked())
                    self:SetChecked((getCoordinateSettings()))
                end)
            else
                b:SetChecked(db[key])
                b:SetScript('OnClick',function(self)
                    db[key]=self:GetChecked() and true or false
                    schedule()
                end)
            end
        end

        button('Holiday / event overrides',208,-199,function() ns.ShowEventOptions(schedule) end,'Manually show or hide quests for individual events.')
        w.scan=button('Refresh completed quests',18,-199,scanCompleted,'Checks for completed quests, starting with the lowest levels.')
        w.scan:SetEnabled(not scanRunning)
        w.status=label(scanStatus,18,-231,'GameFontHighlightSmall')
        w.status:SetWidth(368)

        w.hiddenCount=label('',18,-258,'GameFontNormal')
        w.undo=button('Undo last hide',18,-276,function() hiddenQuests:Undo() end,'Restores the last quest you hid manually.')
        w.restore=button('Restore all hidden',208,-276,function() hiddenQuests:RestoreAll() end,'Restores all quests you hid manually.')
        label('Ctrl + right-click a map icon to hide a quest.',18,-309,'GameFontHighlightSmall')
        local source=label(ns.databaseStatus or '',18,-350,'GameFontDisableSmall')
        source:SetWidth(368)

        function w:UpdateHidden()
            local count=hiddenQuests:Count()
            self.hiddenCount:SetText('Hidden quests: '..count)
            self.undo:SetEnabled(hiddenQuests:CanUndo())
            self.restore:SetEnabled(count>0)
        end
    end
    local enabled,supported=getCoordinateSettings()
    F.options.coordinates:SetChecked(enabled)
    F.options.coordinates:SetEnabled(supported)
    F.options:UpdateHidden()
    F.options:Show()
end
local function attachMapSettings()
    if F.mapButton or not WorldMapFrame then return end
    local button=CreateFrame('Button',nil,WorldMapFrame,'UIPanelButtonTemplate')
    button:SetSize(125,22)
    local function positionButton()
        local canvas=WorldMapFrame.GetCanvasContainer and WorldMapFrame:GetCanvasContainer()
        button:ClearAllPoints()
        button:SetPoint('BOTTOMRIGHT',canvas or WorldMapFrame,'BOTTOMRIGHT',-12,12)
    end
    positionButton()
    button:SetFrameLevel(WorldMapFrame:GetFrameLevel()+20)
    button:SetText('AllTheQuests')
    button:SetScript('OnClick',function()
        options()
        F.options:ClearAllPoints()
        local panel=F.options
        local panelScale=panel:GetEffectiveScale()
        local buttonScale=button:GetEffectiveScale()/panelScale
        local screenScale=UIParent:GetEffectiveScale()/panelScale
        local _,screenHeight=GetPhysicalScreenSize()
        local unitsPerPixel=768/(screenHeight*panelScale)
        local anchorRight=button:GetRight()*buttonScale
        local anchorBottom=button:GetBottom()*buttonScale
        local baseRight=math.min(math.max(anchorRight+100,panel:GetWidth()),UIParent:GetWidth()*screenScale)
        local baseBottom=math.min(math.max(anchorBottom+100,0),UIParent:GetHeight()*screenScale-panel:GetHeight())
        panel:SetPoint('BOTTOMRIGHT',button,'BOTTOMRIGHT',
            baseRight-anchorRight-111*unitsPerPixel,baseBottom-anchorBottom-150*unitsPerPixel)
    end)
    WorldMapFrame:HookScript('OnShow',function() positionButton(); schedule() end)
    WorldMapFrame:HookScript('OnHide',function()
        if F.options then F.options:Hide() end
        if hoverLocations then hoverLocations:Clear() end
    end)
    local viewedMap = WorldMapFrame:GetMapID()
    hooksecurefunc(WorldMapFrame,'SetMapID',function(map)
        local mapID=map:GetMapID()
        if mapID==viewedMap then return end
        viewedMap=mapID
        if hoverLocations then hoverLocations:Clear() end
        schedule()
    end)
    F.mapButton=button
end
local function build()
    local groups={}
    local ids=Q.GetAllIds()
    local cursor=1
    local itemSources=ns.CreateItemSources(database)
    local function addSpawns(id,kind,eid,questSeen,itemID,source,libraryBook)
        local added=false
        local entity=kind==1 and database.Npc or database.Object
        for area,coords in pairs(entity.Get(eid,'spawns') or {}) do
            local map=maps[area]
            if map then
                for _,xy in ipairs(coords) do
                    if xy[1] and xy[2] and xy[1]>=0 and xy[1]<=100 and xy[2]>=0 and xy[2]<=100 then
                        local key=(libraryBook and 'book:' or itemID and 'item:' or '')..kind..':'..eid..':'..map..':'..xy[1]..':'..xy[2]
                        local row=groups[key]
                        if not row then
                            row={key=key,map=map,x=xy[1]/100,y=xy[2]/100,name=entity.Get(eid,'name') or 'Quest source',quests={},libraryBook=libraryBook}
                            groups[key]=row
                        end
                        row.quests[#row.quests+1]=id
                        added=true
                        if itemID then
                            if source=='Possible drop source' or source=='Possible container source' then
                                questRows[id].hasDrop=true
                            end
                            row.itemStarts=row.itemStarts or {}
                            row.itemStarts[id]=row.itemStarts[id] or {}
                            row.itemStarts[id][itemID]=true
                            if row.itemSource and row.itemSource~=source then row.itemSource='Possible item source'
                            else row.itemSource=source end
                        end
                        local location=(itemID and 'item:' or '')..map..':'..xy[1]..':'..xy[2]
                        if not questSeen[location] then
                            questSeen[location]=true
                            if not questRows[id][map] then questRows[id][map]={}; table.insert(questRows[id].order,map) end
                            table.insert(questRows[id][map],row)
                        end
                    end
                end
            end
        end
        return added
    end
    local function batch()
        for n=1,100 do
            local id=ids[cursor]; cursor=cursor+1
            if not id then
                index={}; for _,row in pairs(groups) do index[#index+1]=row end
                refresh(); scanCompleted(); return
            end
            if not ns.holidays[id] then
                ns.holidays[id]=ns.holidayCategories[Q.Get(id,'zoneOrSort')]
            end
            local level=math.max(0,Q.Get(id,'requiredLevel') or 0,Q.Get(id,'questLevel') or 0)
            levelBuckets[level]=levelBuckets[level] or {}
            table.insert(levelBuckets[level],id)
            questRows[id]={order={}}
            local questSeen={}
            local starts=Q.Get(id,'startedBy') or {}
            local hasBookPickup=false
            if libraryBookQuests[id] then
                for _,eid in ipairs(starts[2] or {}) do
                    if addSpawns(id,2,eid,questSeen,nil,nil,true) then hasBookPickup=true end
                end
            end
            if not hasBookPickup then
                for kind in ipairs({database.Npc,database.Object}) do
                    for _,eid in ipairs(starts[kind] or {}) do addSpawns(id,kind,eid,questSeen) end
                end
                for _,itemID in ipairs(starts[3] or {}) do
                    for _,source in ipairs(itemSources(itemID)) do
                        addSpawns(id,source.kind,source.id,questSeen,itemID,source.source)
                    end
                end
            end
        end
        C_Timer.After(0,batch)
    end
    batch()
end
F:RegisterEvent('PLAYER_LOGIN')
F:RegisterEvent('ADDON_LOADED')
F:SetScript('OnEvent',function(_,event,arg1)
    if event=='ADDON_LOADED' then
        if Q then attachMapSettings() end
        return
    end
    if event=='CALENDAR_UPDATE_EVENT_LIST' then ns.CalendarReady(); schedule(); return end
    if event~='PLAYER_LOGIN' then
        if event=='QUEST_TURNED_IN' and arg1 and Q and not isRepeatable(arg1) then
            finished[arg1]=true
        end
        if event=='SKILL_LINES_CHANGED' or event=='SPELLS_CHANGED' then skillsDirty=true end
        if event=='PLAYER_ENTERING_WORLD' or event=='ZONE_CHANGED_NEW_AREA' then
            spatial=nil; skillsDirty=true
        end
        schedule(); return
    end
    AllTheQuestsDB=AllTheQuestsDB or {}; db=AllTheQuestsDB; db.mini=nil
    for k,v in pairs(defaults) do if db[k]==nil then db[k]=v end end
    ns.eventOverrides=db.eventOverrides or {}; db.eventOverrides=ns.eventOverrides
    local failure
    database,failure=ns.ResolveDatabase()
    if not database then
        print('|cffff6666AllTheQuests:|r '..tostring(failure))
        SLASH_FOREVERQUESTMAP1='/atq'
        SlashCmdList.FOREVERQUESTMAP=function() print('AllTheQuests: '..tostring(failure)) end
        return
    end
    eligibility=ns.CreateEligibility(database,completed)
    hiddenQuests=ns.CreateHiddenQuests(db,database.Quest,function()
        if hoverLocations then hoverLocations:Clear() end
        schedule()
        if F.options then F.options:UpdateHidden() end
    end,allowed)
    Q=database.Quest; pins=LibStub('HereBeDragons-Pins-2.0'); geometry=LibStub('HereBeDragons-2.0')
    hoverLocations=ns.CreateHoverLocations(pins,questRows,allowed,previewChanged)
    local zones=database.Support.Get('ZoneDB').private
    local function decode(value) return type(value)=='string' and assert(loadstring(value))() or value or {} end
    maps=decode(zones.areaIdToUiMapId)
    local merged={}; for k,v in pairs(maps) do merged[k]=v end
    for k,v in pairs(decode(zones.areaIdToUiMapIdOverride)) do merged[k]=v end
    maps=merged
    SLASH_FOREVERQUESTMAP1='/atq'; SlashCmdList.FOREVERQUESTMAP=options
    for _,e in ipairs({'CALENDAR_UPDATE_EVENT_LIST','SKILL_LINES_CHANGED','SPELLS_CHANGED','UPDATE_FACTION','PLAYER_ENTERING_WORLD','QUEST_LOG_UPDATE','QUEST_TURNED_IN','PLAYER_LEVEL_UP','ZONE_CHANGED_NEW_AREA','ZONE_CHANGED'}) do F:RegisterEvent(e) end
    attachMapSettings()
    if C_Calendar and C_Calendar.OpenCalendar then C_Calendar.OpenCalendar() end
    C_Timer.NewTicker(60,function()
        if not db.world or not WorldMapFrame or not WorldMapFrame:IsShown() then return end
        if ns.UpdateHolidays(true) then schedule() end
    end)
    -- No movement scanning with the map closed; map opening requests a fresh pass.
    C_Timer.NewTicker(3,function()
        if not db.immersive or not db.world or not index or not WorldMapFrame or not WorldMapFrame:IsShown() then return end
        local x,y,instance=geometry:GetPlayerWorldPosition()
        if not x or not y then
            if lastX then schedule() end
        elseif not lastX or not lastY or instance~=lastInstance or (x-lastX)^2+(y-lastY)^2>=10*10 then
            schedule()
        end
    end)
    build()

end)














