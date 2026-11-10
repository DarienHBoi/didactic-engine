-- Optional item previews outside DEH. Only visible Blizzard item tooltips are
-- touched, never scan tooltips; helper-owned tooltips keep their own rendering.
local _, ns = ...
local External = {}
ns.ExternalTooltips = External
local saved, installed
local marked = setmetatable({}, {__mode="k"})

local function Secret(value)
    return issecretvalue and issecretvalue(value) or false
end
local function HelperOwned(tooltip)
    local owner=tooltip.GetOwner and tooltip:GetOwner()
    for _=1,20 do
        if not owner then return false end
        local name=owner.GetName and owner:GetName()
        if not Secret(name) and type(name)=="string" and name:find("^DisenchantHelper") then return true end
        owner=owner.GetParent and owner:GetParent()
    end
    return true -- malformed/cyclic ownership: do not touch it
end
local function Append(tooltip)
    if not saved or saved.externalItemTooltips~=true then return end
    if tooltip~=GameTooltip and tooltip~=ItemRefTooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if HelperOwned(tooltip) or not tooltip.GetItem then return end
    local _,link=tooltip:GetItem()
    if Secret(link) or type(link)~="string" or not link:find("item:") or marked[tooltip]==link then return end
    local get=(C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not get then return end
    local name,_,quality,level,_,_,_,_,equipLoc,_,_,classID,subclassID=get(link)
    for _,value in pairs({name,quality,level,equipLoc,classID,subclassID}) do
        if Secret(value) then return end
    end
    if not name or type(quality)~="number" or quality<2 or quality>4
        or classID~=2 and classID~=4 or classID==4 and subclassID==5
        or not equipLoc or equipLoc=="" then return end
    local detailed=(C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
    if detailed then level=detailed(link) or level end
    if Secret(level) or type(level)~="number" or level<=0 then return end
    local estimate=ns.Prediction.Estimate({link=link,quality=quality,itemLevel=level})
    -- Avoid adding an empty block to every bag/AH tooltip before data exists.
    if not estimate or #estimate.mats==0 then return end
    marked[tooltip]=link -- before rendering, to prevent reentrant callbacks
    for _,line in ipairs(ns.Prediction.BuildLines(estimate)) do
        if line.right then
            tooltip:AddDoubleLine(line.text,line.right,line.r,line.g,line.b,1,1,1)
        else
            tooltip:AddLine(line.text,line.r,line.g,line.b,true)
        end
    end
end
function External.OnItem(tooltip)
    -- Protected/uncached tooltip data should never interrupt Blizzard's UI.
    pcall(Append,tooltip)
end
function External.Init(db)
    saved=db
    if installed then return end
    local modern=TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
    for _,tooltip in pairs({GameTooltip,ItemRefTooltip}) do
        if tooltip.HookScript then
            pcall(tooltip.HookScript,tooltip,"OnTooltipCleared",function(self) marked[self]=nil end)
        end
    end
    if modern then
        local ok=pcall(TooltipDataProcessor.AddTooltipPostCall,Enum.TooltipDataType.Item,External.OnItem)
        if ok then installed=true;External.mode="modern";return end
    end
    local hooked=false
    for _,tooltip in pairs({GameTooltip,ItemRefTooltip}) do
        if tooltip.HookScript then
            local ok=pcall(tooltip.HookScript,tooltip,"OnTooltipSetItem",function(self)
                External.OnItem(self)
                if marked[self] then self:Show() end
            end)
            hooked=ok or hooked
        end
    end
    installed=hooked
    External.mode=hooked and "legacy" or "unavailable"
end
