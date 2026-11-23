-- AscendXP gold and loot valuation module, designed for WoW Forever (16001).
-- Independent implementation. Read-only Auctionator API; never requests AH scans.
local addonName, addon = ...
local Money = {}
addon.Money = Money
local floor, max, min = math.floor, math.max, math.min
local format = string.format
local now = time
local lastWallet, suppressUntil, lastPriceRefresh = nil, 0, -1
local lastClosedContext = "normal"
local pauses = {}
local session, sessionStart, changed
local lootFormats, craftFormats = {}, {}
-- A single loot window is treated as a transaction: chat and verified bag
-- increases are two reports of the SAME pickup, never two income events.
local pendingLoot, lateLoot, lootSerial = nil, nil, 0
local bagRescanQueued = false
local diagnostic = {windows=0,chat=0,matched=0,bag=0,items=0,last="None"}

local function IsUsable(v)
    return type(v) == "number" and (not issecretvalue or not issecretvalue(v)) and v >= 0
end
local function Number(v) return IsUsable(v) and v or 0 end
local function SafeMoney()
    if type(GetMoney) ~= "function" then return nil end
    local ok, value = pcall(GetMoney)
    return ok and IsUsable(value) and value or nil
end
local function Refresh()
    if changed then changed() end
end

-- Interprets the *localized* Blizzard loot strings, restricted to own loot.
-- Chat logs from parties, trades and creations are not counted as mob loot.
local function LootPattern(template)
    if type(template) ~= "string" or template == "" then return nil end
    local p = template:gsub("%%(%d+)%$([sd])", "%%%2")
    p = p:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
    return "^" .. p .. "$"
end
local function AddPattern(dest, text)
    local p = LootPattern(text)
    if p then dest[#dest+1] = p end
end
local function BuildPatterns()
    lootFormats, craftFormats = {}, {}
    AddPattern(lootFormats, LOOT_ITEM_SELF_MULTIPLE)
    AddPattern(lootFormats, LOOT_ITEM_PUSHED_SELF_MULTIPLE)
    AddPattern(lootFormats, LOOT_ITEM_SELF)
    AddPattern(lootFormats, LOOT_ITEM_PUSHED_SELF)
    AddPattern(craftFormats, LOOT_ITEM_CREATED_SELF_MULTIPLE)
    AddPattern(craftFormats, LOOT_ITEM_CREATED_SELF)
end
local function LootMatch(message, list)
    for _,pattern in ipairs(list) do
        local link, qty = message:match(pattern)
        if link then return link, tonumber(qty) or 1 end
    end
end
local function SafeItemInfo(itemLink)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if type(get) ~= "function" then return nil end
    local ok, name, _, quality, _, _, _, _, _, _, _, vendorCopper, classID, subclassID, bindType = pcall(get,itemLink)
    if not ok or not name then return nil end
    return {name=name, vendor=Number(vendorCopper), quality=quality,
        classID=classID, subclassID=subclassID, bindType=bindType}
end
local function IsSoulboundOnPickup(bindType)
    local onAcquire = Enum and Enum.ItemBind and Enum.ItemBind.OnAcquire
    return bindType ~= nil and bindType == (onAcquire or 1)
end
local function AuctionPrice(itemLink, itemID)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if type(api) ~= "table" then return nil end
    local getter = api.GetAuctionPriceByItemLink
    if type(getter) == "function" then
        local ok,value=pcall(getter,addonName,itemLink)
        if ok and IsUsable(value) and value > 0 then return value end
    end
    -- Forever Auctionator also exposes item-ID pricing. Use it if link data is absent.
    getter=api.GetAuctionPriceByItemID
    if type(getter) == "function" and itemID then
        local ok,value=pcall(getter,addonName,itemID)
        if ok and IsUsable(value) and value>0 then return value end
    end
    return nil
end
local function ItemName(link)
    return link:match("%[(.-)%]") or ("Item " .. (link:match("item:(%d+)") or "unknown"))
end
local function PriceItem(item)
    local info = SafeItemInfo(item.link)
    local vendor = info and info.vendor or 0
    local bindType = info and info.bindType
    local auction = not IsSoulboundOnPickup(bindType) and AuctionPrice(item.link,item.itemID) or nil
    item.name = info and info.name or item.name or ItemName(item.link)
    item.quality = info and info.quality or item.quality
    item.vendor = vendor
    item.market = auction or 0
    item.known = info ~= nil or auction ~= nil
    -- Value the item at the better gross selling option; don't invent an AH price.
    if auction and auction > vendor then
        item.unit = auction
        item.source = "AH"
    elseif info then
        item.unit = vendor
        item.source = vendor>0 and "VENDOR" or "NO VALUE"
    elseif auction then
        item.unit = auction
        item.source = "AH"
    else
        item.unit = 0
        item.source = "PENDING"
        if item.itemID and C_Item and type(C_Item.RequestLoadItemDataByID)=="function" then
            pcall(C_Item.RequestLoadItemDataByID,item.itemID)
        end
    end
end
local function CapEvents(t,limit)
    if #t > limit then
        local excess = #t-limit
        for _=1,excess do table.remove(t,1) end
    end
end
-- Version 2 repairs merchant purchases being counted as dropped loot in v1.1.0.
-- Reinitializing ONLY the gold session discards old misclassified purchased items;
-- XP and quest session statistics remain untouched.
function Money.NewSession()
    return {version=2, cash=0, spent=0, itemCount=0, drops={}, events={},
        lootLog={}, recent={}, started=now()}
end
function Money.Init(parentSession, onChanged)
    if not parentSession.money or parentSession.money.version ~= 2 then
        parentSession.money=Money.NewSession()
    end
    session=parentSession.money
    session.cash=Number(session.cash)
    session.spent=Number(session.spent)
    session.itemCount=Number(session.itemCount)
    session.drops=session.drops or {}
    session.events=session.events or {}
    -- Upgrade existing characters without resetting their session or loot totals.
    -- Older sessions kept each pickup in the general event history.
    if not session.lootLog then
        session.lootLog={}
        for _,event in ipairs(session.events) do
            if event.kind=="item" and event.link then
                session.lootLog[#session.lootLog+1]={t=event.t,link=event.link,count=event.count}
            end
        end
    end
    session.recent=session.recent or {}
    -- An upgrade can add gold tracking to a pre-existing XP session.
    sessionStart=session.started or parentSession.started or now()
    lastWallet=SafeMoney()
    suppressUntil=0
    lastClosedContext="normal"
    pauses={}
    pendingLoot,lateLoot=nil,nil
    lootSerial=lootSerial+1
    bagRescanQueued=false
    diagnostic={windows=0,chat=0,matched=0,bag=0,items=0,last="None"}
    changed=onChanged or changed
    lastPriceRefresh=-1
    BuildPatterns()
    Money.UpdatePrices(true)
end
function Money.Reset(parentSession)
    parentSession.money=Money.NewSession()
    Money.Init(parentSession, changed)
end
function Money.UpdatePrices(force)
    if not session then return end
    local t = type(GetTime)=="function" and GetTime() or now()
    if not force and lastPriceRefresh>=0 and t-lastPriceRefresh<30 then return end
    lastPriceRefresh=t
    local i=0
    for _,item in pairs(session.drops) do
        PriceItem(item)
        i=i+1
        if i>=600 then break end -- avoid a frame hitch on enormous loot sessions
    end
end
local function RecordItem(link, count)
    if not session then return end
    count=min(10000, max(1, floor(count or 1)))
    local id=tonumber(link:match("item:(%d+)"))
    if not id then return end
    local item=session.drops[link]
    if not item then
        item={link=link,itemID=id,count=0,name=ItemName(link),unit=0,source="PENDING"}
        session.drops[link]=item
        PriceItem(item)
    end
    item.count=item.count+count
    session.itemCount=session.itemCount+count
    local evt={t=now(),kind="item",link=link,count=count}
    session.events[#session.events+1]=evt
    session.lootLog=session.lootLog or {}
    session.lootLog[#session.lootLog+1]={t=evt.t,link=link,count=count}
    CapEvents(session.lootLog,5000)
    session.recent[#session.recent+1]=evt
    CapEvents(session.events,3000)
    CapEvents(session.recent,30)
    diagnostic.items=diagnostic.items+count
    diagnostic.last=ItemName(link).." x"..count
    Refresh()
end
local function RecordCash(copper)
    if not session or copper <= 0 then return end
    session.cash=session.cash+copper
    local evt={t=now(),kind="cash",cash=copper}
    session.events[#session.events+1]=evt
    session.recent[#session.recent+1]=evt
    CapEvents(session.events,3000)
    CapEvents(session.recent,30)
    Refresh()
end
local function RecordExpense(copper)
    if not session or copper <= 0 then return end
    session.spent=session.spent+copper
    local evt={t=now(),kind="expense",cash=copper}
    session.events[#session.events+1]=evt
    session.recent[#session.recent+1]=evt
    CapEvents(session.events,3000)
    CapEvents(session.recent,30)
    Refresh()
end
-- Trade money counts as actual service income. Customer materials do not count
-- as loot: only genuine world loot and explicitly verified fishing catches enter
-- item valuation. Bank/mail transfers remain excluded.
local function IsTransfer(kind)
    return kind=="mail" or kind=="bank" or kind=="guildbank" or
        kind=="accountbank" or kind=="characterbank" or kind=="voidbank"
end
local function CurrentContext()
    local activeShop=false
    for _,kind in pairs(pauses) do
        if kind=="trade" then return "trade" end
        if IsTransfer(kind) then return "transfer" end
        if kind then activeShop=true end
    end
    if activeShop then return "shop" end
    local t=type(GetTime)=="function" and GetTime() or now()
    if t < suppressUntil then return lastClosedContext end
    return "normal"
end
local function WatchWallet()
    local current=SafeMoney()
    if not current then return end
    if lastWallet == nil then lastWallet=current; return end
    local delta=current-lastWallet
    lastWallet=current -- always rebaseline, including transfers
    if delta==0 then return end
    local context=CurrentContext()
    if delta>0 then
        -- A finished trade produces a *real* positive wallet delta. Counting
        -- only that delta (never the offer) avoids cancelled-trade income.
        -- Shop/bank/mail credit is still excluded as before.
        if context=="normal" or context=="trade" then RecordCash(delta) end
    elseif context~="transfer" and context~="trade" then
        -- Payments, repairs and purchases are expenses. Outgoing player-trade
        -- gold is intentionally excluded like the original addon.
        RecordExpense(-delta)
    end
end
local function Pause(key,on,kind)
    -- Flush old wallet changes before switching interaction attribution.
    WatchWallet()
    if on then
        pauses[key]=kind or "shop"
    else
        pauses[key]=nil
        lastClosedContext=kind=="trade" and "trade" or
            (IsTransfer(kind) and "transfer" or "shop")
        local t=type(GetTime)=="function" and GetTime() or now()
        suppressUntil=t+3 -- catches delayed trade money / purchase messages
    end
end

-- LOOT_READY / LOOT_OPENED fire for corpse loot, gathering and fishing.
-- Earlier builds only reconciled fishing, leaving normal mob drops dependent
-- on a locale-sensitive chat format. We now match bag increases against loot
-- window items for ALL loot sources. Inventory changes outside loot windows
-- (trade mats, crafting, merchant, mail, quest rewards) are NEVER loot.
local function BagSnapshot()
    local container=C_Container
    local slots=(container and container.GetContainerNumSlots) or GetContainerNumSlots
    local itemInfo=(container and container.GetContainerItemInfo) or GetContainerItemInfo
    local itemLink=(container and container.GetContainerItemLink) or GetContainerItemLink
    local itemID=(container and container.GetContainerItemID) or GetContainerItemID
    if type(slots)~="function" or type(itemInfo)~="function" then return nil end
    local counts,links={},{}
    local usable=false
    for bag=0,4 do
        local ok,n=pcall(slots,bag)
        if ok and type(n)=="number" and n>=0 then
            usable=true
            for slot=1,min(n,200) do
                local okInfo,a,b,_,_,_,_,g=pcall(itemInfo,bag,slot)
                if okInfo then
                    local id,qty,link
                    if type(a)=="table" then
                        id=a.itemID
                        qty=a.stackCount or a.count or 0
                        link=a.hyperlink
                    else
                        qty=b
                        link=g
                    end
                    if type(link)~="string" and type(itemLink)=="function" then
                        local good,v=pcall(itemLink,bag,slot)
                        if good then link=v end
                    end
                    if not id and type(link)=="string" then id=tonumber(link:match("item:(%d+)")) end
                    if not id and type(itemID)=="function" then
                        local good,v=pcall(itemID,bag,slot)
                        if good and type(v)=="number" then id=v end
                    end
                    if type(id)=="number" and type(qty)=="number" and qty>0 then
                        counts[id]=(counts[id] or 0)+qty
                        if type(link)=="string" then links[id]=link end
                    end
                end
            end
        end
    end
    if not usable then return nil end
    return counts,links
end

local function Clock()
    return type(GetTime)=="function" and GetTime() or now()
end

-- Loot windows sometimes expose links later than LOOT_READY. Re-scan while
-- open; do not reset the before-inventory baseline or existing chat counts.
local function ScanLootSlots(target)
    if type(GetNumLootItems)~="function" or type(GetLootSlotLink)~="function" then return end
    local ok,total=pcall(GetNumLootItems)
    if not ok or type(total)~="number" then return end
    for slot=1,min(total,40) do
        local good,link=pcall(GetLootSlotLink,slot)
        if good and type(link)=="string" then
            local id=tonumber(link:match("item:(%d+)"))
            if id then
                local qty=1
                if type(GetLootSlotInfo)=="function" then
                    local okInfo,_,_,count=pcall(GetLootSlotInfo,slot)
                    if okInfo and type(count)=="number" and count>0 then qty=count end
                end
                target.slots[slot]={id=id,count=qty}
                local previous=target.items[id]
                if not previous then
                    target.items[id]={link=link,count=qty}
                else
                    previous.link=link
                    -- Multiple slots with the same item may exist.
                    local totalQuantity=0
                    for _,entry in pairs(target.slots) do
                        if entry.id==id then totalQuantity=totalQuantity+entry.count end
                    end
                    previous.count=totalQuantity
                end
            end
        end
    end
end

local function ReconcileLoot(target)
    if pendingLoot~=target then return end
    local after,links=BagSnapshot()
    if not after or not target.before then return end
    diagnostic.bag=diagnostic.bag+1
    -- On some client builds loot links aren't ready at LOOT_READY. A bag
    -- increase during an actual loot transaction is still usable evidence.
    for id,total in pairs(after) do
        local gained=max(0,total-(target.before[id] or 0))
        if gained>0 and not target.items[id] then
            target.items[id]={link=(links and links[id]) or ("item:"..id),count=gained}
        end
    end
    for id,item in pairs(target.items) do
        local gained=max(0,(after[id] or 0)-(target.before[id] or 0))
        local observed=min(item.count,gained)
        -- Chat-reported pickups already counted; bag fallback counts only the
        -- remainder and can run repeatedly without duplicate credits.
        local needed=max(0,observed-(target.chat[id] or 0)-(target.credited[id] or 0))
        if needed>0 then
            local link=item.link or (links and links[id]) or ("item:"..id)
            RecordItem(link,needed)
            target.credited[id]=(target.credited[id] or 0)+needed
        end
    end
end

local function FinishLoot(target)
    if pendingLoot~=target then return end
    ReconcileLoot(target)
    -- If bag APIs are not available, a cleared loot slot is independent proof
    -- of a pickup. Never assume that merely opening loot grants its contents.
    if not target.before then
        for id,count in pairs(target.cleared) do
            local item=target.items[id]
            local needed=max(0,count-(target.chat[id] or 0)-(target.credited[id] or 0))
            if item and needed>0 then
                RecordItem(item.link,needed)
                target.credited[id]=(target.credited[id] or 0)+needed
            end
        end
    end
    pendingLoot=nil
    lateLoot={t=Clock(),credited=target.credited}
end

local function BeginLoot(ready)
    -- Separate fast consecutive mob kills instead of treating a later
    -- LOOT_READY as the same loot transaction (especially with auto-loot).
    if pendingLoot and (pendingLoot.closed or
        (ready and Clock()-(pendingLoot.started or 0)>0.3)) then
        FinishLoot(pendingLoot)
    end
    -- An actual LOOT_READY is stronger evidence than a recent shop-close
    -- grace period. Still reject loot while a transaction window is open.
    if next(pauses) then return end
    if not pendingLoot then
        local before=BagSnapshot()
        pendingLoot={items={},slots={},before=before,chat={},credited={},usedCredit={},cleared={},usedSlots={},closed=false,started=Clock()}
        diagnostic.windows=diagnostic.windows+1
        if C_Timer and type(C_Timer.After)=="function" then
            local target=pendingLoot
            C_Timer.After(3.0,function()
                if pendingLoot~=target or target.closed then return end
                local open=false
                if LootFrame and type(LootFrame.IsShown)=="function" then
                    local ok,shown=pcall(LootFrame.IsShown,LootFrame)
                    open=ok and shown
                end
                if not open then FinishLoot(target) end
            end)
        end
    end
    ScanLootSlots(pendingLoot)
end

local function CloseLoot()
    local target=pendingLoot
    if not target then return end
    target.closed=true
    -- First try once inventory has had time to settle. Keep the window alive
    -- briefly for asynchronous item loads and BAG_UPDATE_DELAYED events.
    if C_Timer and type(C_Timer.After)=="function" then
        C_Timer.After(0.3,function() ReconcileLoot(target) end)
        C_Timer.After(2.5,function() FinishLoot(target) end)
    else
        FinishLoot(target)
    end
end

local function LootSlotCleared(index)
    local target=pendingLoot
    if not target or target.usedSlots[index] then return end
    local item=target.slots[index]
    if item then
        target.usedSlots[index]=true
        target.cleared[item.id]=(target.cleared[item.id] or 0)+item.count
    end
end

local function LootBagChanged()
    if not pendingLoot or bagRescanQueued then return end
    bagRescanQueued=true
    if C_Timer and type(C_Timer.After)=="function" then
        local target=pendingLoot
        C_Timer.After(0.15,function()
            bagRescanQueued=false
            if pendingLoot==target then ReconcileLoot(target) end
        end)
    else
        bagRescanQueued=false
        ReconcileLoot(pendingLoot)
    end
end

local function ReceiveLootChat(link,count)
    local id=tonumber(link:match("item:(%d+)"))
    if not id then return end
    local target=pendingLoot
    if target then
        target.chat[id]=(target.chat[id] or 0)+count
        -- A bag callback may precede the chat message. Absorb the already
        -- credited quantity before recording any remainder.
        local available=max(0,(target.credited[id] or 0)-(target.usedCredit[id] or 0))
        local consumed=min(count,available)
        target.usedCredit[id]=(target.usedCredit[id] or 0)+consumed
        count=count-consumed
    elseif lateLoot and Clock()-lateLoot.t<=2 then
        local available=lateLoot.credited[id] or 0
        local consumed=min(count,available)
        lateLoot.credited[id]=available-consumed
        count=count-consumed
    end
    if count>0 then RecordItem(link,count) end
end

local blockedInteractions={}
local function BuildBlockedInteractions()
    local all = Enum and Enum.PlayerInteractionType
    if not all then return end
    local categories={Merchant="shop",MailInfo="mail",Auctioneer="shop",
        Banker="bank",GuildBanker="guildbank",BlackMarketAuctioneer="shop",
        VoidStorageBanker="voidbank",AccountBanker="accountbank",
        CharacterBanker="characterbank",Trade="trade",Transmogrifier="shop",
        ClassTrainer="shop",TaxiNode="shop"}
    for name,category in pairs(categories) do
        if all[name] ~= nil then blockedInteractions[all[name]]=category end
    end
end
local legacyWindows = {
    MERCHANT_SHOW="shop",MERCHANT_CLOSED="shop",
    MAIL_SHOW="mail",MAIL_CLOSED="mail",
    AUCTION_HOUSE_SHOW="shop",AUCTION_HOUSE_CLOSED="shop",
    BANKFRAME_OPENED="bank",BANKFRAME_CLOSED="bank",
    GUILDBANKFRAME_OPENED="guildbank",GUILDBANKFRAME_CLOSED="guildbank",
    TRADE_SHOW="trade",TRADE_CLOSED="trade",
}
function Money.OnEvent(event,...)
    if not session then return end
    if event == "PLAYER_MONEY" then
        WatchWallet()
    elseif event == "CHAT_MSG_LOOT" then
        local message = ...
        if type(message) ~= "string" or not message:find("|Hitem:",1,true) then return end
        -- CHAT_MSG_LOOT also fires for purchased items on Forever. A shop
        -- purchase must NEVER become a farming drop/Auctionator gold value.
        if CurrentContext()~="normal" and not (pendingLoot and not next(pauses)) then return end
        if LootMatch(message,craftFormats) then return end
        local link,count = LootMatch(message,lootFormats)
        diagnostic.chat=diagnostic.chat+1
        if link and link:find("|Hitem:",1,true) then
            diagnostic.matched=diagnostic.matched+1
            ReceiveLootChat(link,count)
        end
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        BeginLoot(event=="LOOT_READY")
    elseif event == "LOOT_SLOT_CLEARED" then
        LootSlotCleared(...)
    elseif event == "LOOT_CLOSED" then
        CloseLoot()
    elseif event == "BAG_UPDATE_DELAYED" then
        LootBagChanged()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        Money.UpdatePrices(true); Refresh()
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        local kind=...
        if blockedInteractions[kind] then
            Pause("interaction:"..tostring(kind),event=="PLAYER_INTERACTION_MANAGER_FRAME_SHOW",blockedInteractions[kind])
        end
    elseif legacyWindows[event] then
        local isOpening=event:find("SHOW",1,true)~=nil or event:find("OPENED",1,true)~=nil
        local kind=legacyWindows[event]
        -- Use stable matching open/close keys rather than event names.
        local windowKey=event:find("MERCHANT",1,true) and "merchant" or
            event:find("MAIL",1,true) and "mail" or
            event:find("AUCTION_HOUSE",1,true) and "auction" or
            event:find("GUILDBANK",1,true) and "guildbank" or
            event:find("BANKFRAME",1,true) and "bank" or "trade"
        Pause(windowKey,isOpening,kind)
    end
end
BuildBlockedInteractions()
local function Comma(v)
    local s=tostring(floor(v+0.5))
    return s:reverse():gsub("(%d%d%d)","%1,"):reverse():gsub("^,","")
end
function Money.Format(copper)
    local neg=type(copper)=="number" and copper<0
    copper=floor(math.abs(tonumber(copper) or 0)+0.5)
    local prefix=neg and "-" or ""
    local g=floor(copper/10000)
    local s=floor((copper%10000)/100)
    local c=copper%100
    if g>0 then return prefix..Comma(g).."g "..s.."s "..c.."c" end
    if s>0 then return prefix..s.."s "..c.."c" end
    return prefix..c.."c"
end
function Money.Compact(copper)
    local neg=type(copper)=="number" and copper<0
    copper=math.abs(tonumber(copper) or 0)
    local prefix=neg and "-" or ""
    if copper>=100000000 then return prefix..format("%.1fkg",copper/10000000) end
    if copper>=10000000 then return prefix..format("%.0fg",copper/10000) end
    if copper>=10000 then return prefix..format("%.1fg",copper/10000) end
    if copper>=100 then return prefix..format("%.1fs",copper/100) end
    return prefix..floor(copper+0.5).."c"
end
function Money.Summary()
    if not session then return {cash=0,spent=0,loot=0,gross=0,net=0,total=0,items=0,unique=0,ahItems=0,vendorItems=0,missing=0} end
    Money.UpdatePrices()
    local summary={cash=session.cash or 0,spent=session.spent or 0,loot=0,total=0,items=session.itemCount or 0,
        unique=0,ahItems=0,vendorItems=0,missing=0}
    for _,item in pairs(session.drops) do
        summary.unique=summary.unique+1
        summary.loot=summary.loot + Number(item.unit)*Number(item.count)
        if item.source=="AH" then summary.ahItems=summary.ahItems+item.count
        elseif item.source=="PENDING" then summary.missing=summary.missing+item.count
        else summary.vendorItems=summary.vendorItems+item.count end
    end
    summary.gross=summary.cash+summary.loot
    summary.net=summary.gross-summary.spent
    summary.total=summary.net
    return summary
end
function Money.Rate(window)
    if not session then return 0,false end
    Money.UpdatePrices()
    local elapsed=max(1,now()-(sessionStart or now()))
    if window==0 then
        local sum=Money.Summary()
        local seconds=max(35,elapsed)
        local hasData=(sum.cash~=0 or sum.loot~=0 or sum.spent~=0 or elapsed>=35)
        return sum.net*3600/seconds,hasData,sum.cash*3600/seconds,sum.loot*3600/seconds,sum.spent*3600/seconds
    end
    local seconds=max(35,min(elapsed,(window or 15)*60))
    local cutoff=now()-(window or 15)*60
    local cash,loot,spent=0,0,0
    for _,event in ipairs(session.events) do
        if event.t and event.t >= cutoff then
            if event.kind=="cash" then cash=cash+Number(event.cash)
            elseif event.kind=="expense" then spent=spent+Number(event.cash)
            elseif event.kind=="item" then
                local item=session.drops[event.link]
                loot=loot+(item and Number(item.unit) or 0)*Number(event.count)
            end
        end
    end
    local hasData=(cash~=0 or loot~=0 or spent~=0) or elapsed>=35
    return (cash+loot-spent)*3600/seconds,hasData,cash*3600/seconds,loot*3600/seconds,spent*3600/seconds
end
function Money.TopItems(limit)
    local result={}
    if not session then return result end
    Money.UpdatePrices()
    for _,item in pairs(session.drops) do result[#result+1]=item end
    table.sort(result,function(a,b)
        local va=Number(a.unit)*Number(a.count)
        local vb=Number(b.unit)*Number(b.count)
        if va~=vb then return va>vb end
        return (a.name or "")<(b.name or "")
    end)
    if limit then for i=#result,limit+1,-1 do result[i]=nil end end
    return result
end
-- Per-pickup ledger. Newest first, paged to avoid creating hundreds of UI rows.
-- Prices are always current estimates from the same data as the main gold counter.
function Money.LootEntries(page, pageSize)
    if not session then return {},0 end
    Money.UpdatePrices()
    local log=session.lootLog or {}
    local total=#log
    pageSize=max(1,min(50,tonumber(pageSize) or 11))
    page=max(1,floor(tonumber(page) or 1))
    local first=total-(page-1)*pageSize
    local last=max(1,first-pageSize+1)
    local result={}
    for i=first,last,-1 do
        local e=log[i]
        if e then
            local item=session.drops[e.link]
            local unit=item and Number(item.unit) or 0
            local count=Number(e.count)
            result[#result+1]={
                t=e.t,link=e.link,count=count,
                name=item and item.name or ItemName(e.link),
                quality=item and item.quality,
                source=item and item.source or "PENDING",
                unit=unit,total=unit*count,
            }
        end
    end
    return result,total
end

function Money.DebugStatus()
    local m=Money.Summary()
    local present=(C_Container and type(C_Container.GetContainerItemInfo)=="function") or
        (type(GetContainerItemInfo)=="function")
    return {
        windows=diagnostic.windows,lootChat=diagnostic.chat,
        parsedChat=diagnostic.matched,bagChecks=diagnostic.bag,
        recorded=diagnostic.items,last=diagnostic.last,
        totalItems=m.items,unpriced=m.missing,
        bagAPI=not not present,pending=pendingLoot~=nil,
    }
end
function Money.HasAuctionator()
    return Auctionator and Auctionator.API and Auctionator.API.v1 ~= nil
end
