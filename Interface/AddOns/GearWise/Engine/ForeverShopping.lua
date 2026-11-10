local _, ns = ...
local S, A = ns.Shopping, ns.API
local function api()
    return type(Auctionator) == "table" and type(Auctionator.API) == "table" and Auctionator.API.v1
end
local function now()
    return GetServerTime and GetServerTime() or time and time() or 0
end
local function priceStore()
    if not ns.db then return nil end
    ns.db.priceSnapshots=ns.db.priceSnapshots or {}
    -- Keep saved prices separate between auction-house economies.
    local key=(GetRealmName() or "")..":"..(UnitFactionGroup and UnitFactionGroup("player") or "")
    local store=ns.db.priceSnapshots[key]
    if not store then store={};ns.db.priceSnapshots[key]=store end
    return store
end
local function readPrice(source,id)
    local ok,price=pcall(source.GetAuctionPriceByItemID,ns.name,id)
    if not ok then return nil,nil,false end
    if type(price)~="number" or price<=0 then return nil,nil,true end
    local age
    if type(source.GetAuctionAgeByItemID)=="function" then
        local ageOK,days=pcall(source.GetAuctionAgeByItemID,ns.name,id)
        if ageOK and type(days)=="number" and days>=0 then age=days end
    end
    return price,age,true
end
function S.Price(id)
    local store=priceStore()
    local saved=store and store[id]
    if not saved then return nil end
    local age=saved.age
    if age then age=age+math.floor(math.max(0,now()-saved.at)/86400) end
    return saved.price,age
end
-- Import in small batches so opening any window can finish drawing first.
function S.ImportPrices(done,automatic)
    if S.priceImportJob then
        if done then table.insert(S.priceImportJob.callbacks,done) end
        if not automatic then S.priceImportJob.manualRequested=true end
        return true
    end
    local source=api()
    if not source or type(source.GetAuctionPriceByItemID)~="function" then
        local message=ns.L("Preise: Auctionator-Preisabfrage nicht verfügbar.")
        if done then done(false,message) end
        return false,message
    end
    local job={source=source,seen={},ids={},incoming={},callbacks={},collecting=true,index=1,count=0,manualRequested=not automatic}
    if done then job.callbacks[1]=done end
    S.priceImportJob=job
    local function finish(ok,message)
        S.priceImportJob=nil
        if ok and job.manualRequested then
            S.sessionPriceImportFinished=true
            S.sessionPriceImportStarted=false
            S.sessionPriceImportGeneration=(S.sessionPriceImportGeneration or 0)+1
        end
        for _,callback in ipairs(job.callbacks) do callback(ok,message) end
    end
    local function add(material)
        if material.id and not job.seen[material.id] then
            job.seen[material.id]=true
            job.ids[#job.ids+1]=material.id
        end
    end
    local function step()
        if job.cancelled then return end
        local work=0
        while work<12 do
            if job.collecting then
                local key,option=next(ns.byID,job.cursor)
                job.cursor=key
                if key then
                    for _,material in ipairs(S.Requirements(option,"materials")) do add(material) end
                    for _,material in ipairs(S.Requirements(option,"item")) do add(material) end
                    work=work+1
                else job.collecting=false end
            else
                local id=job.ids[job.index]
                if not id then
                    if job.count==0 then
                        finish(false,ns.L("Keine Preise in Auctionator gefunden. Gespeicherte Preise bleiben erhalten."))
                        return
                    end
                    local store=priceStore()
                    if not store then
                        finish(false,ns.L("Preisübernahme fehlgeschlagen. Gespeicherte Preise bleiben erhalten."))
                        return
                    end
                    -- Missing quotes never erase older known prices.
                    for itemID,value in pairs(job.incoming) do store[itemID]=value end
                    store.updatedAt=now()
                    finish(true,string.format(ns.L("Auctionator-Preise übernommen: %d von %d Waren."),job.count,#job.ids))
                    return
                end
                local price,age,ok=readPrice(source,id)
                if not ok then
                    finish(false,ns.L("Preisübernahme fehlgeschlagen. Gespeicherte Preise bleiben erhalten."))
                    return
                end
                if price then job.incoming[id]={price=price,age=age,at=now()};job.count=job.count+1 end
                job.index=job.index+1
                work=work+1
            end
        end
        C_Timer.After(0,step)
    end
    C_Timer.After(0,step)
    return true
end
-- Session state is kept outside SavedVariables. A closed, incomplete import is retried.
local function hasOpenPriceWindow()
    for frame in pairs(S.openPriceWindows or {}) do
        if frame:IsShown() then return true end
        S.openPriceWindows[frame]=nil
    end
    return false
end
function S.QueueSessionPriceImport()
    if S.sessionPriceImportFinished or S.sessionPriceImportStarted or not ns.db
        or ns.db.settings.autoPriceImport==false then return end
    S.sessionPriceImportStarted=true
    S.sessionPriceImportGeneration=(S.sessionPriceImportGeneration or 0)+1
    local generation=S.sessionPriceImportGeneration
    C_Timer.After(0.1,function()
        if generation~=S.sessionPriceImportGeneration or not ns.enabled then return end
        if not hasOpenPriceWindow() then S.CancelSessionPriceImport();return end
        S.ImportPrices(function(ok)
            S.sessionPriceImportFinished=true
            S.sessionPriceImportStarted=false
            if not ok then return end
            ns.ScheduleRefresh()
            if ns.UI.RefreshCart then ns.UI.RefreshCart() end
        end,true)
    end)
end
function S.CancelSessionPriceImport()
    if not S.sessionPriceImportStarted or S.sessionPriceImportFinished then return end
    local job=S.priceImportJob
    if job and job.manualRequested then return end
    if job then job.cancelled=true;S.priceImportJob=nil end
    S.sessionPriceImportStarted=false
    S.sessionPriceImportGeneration=(S.sessionPriceImportGeneration or 0)+1
end
function S.WindowShown(frame)
    S.openPriceWindows=S.openPriceWindows or setmetatable({}, {__mode="k"})
    S.openPriceWindows[frame]=true
    S.QueueSessionPriceImport()
end
function S.WindowHidden(frame)
    if S.openPriceWindows then S.openPriceWindows[frame]=nil end
    -- A window switch may hide one frame and show another in the same update.
    C_Timer.After(0,function()
        if not hasOpenPriceWindow() then S.CancelSessionPriceImport() end
    end)
end
function S.PriceImportText()
    local store=priceStore()
    local stamp=store and store.updatedAt
    if not stamp then return ns.L("Preisstand: noch nicht übernommen") end
    local formatDate=date or (os and os.date)
    return ns.L("Preisstand übernommen: ")..(formatDate and formatDate("%d.%m.%Y %H:%M",stamp) or tostring(stamp))
end
function S.Requirements(option, mode)
    if mode == "item" then
        if option.itemID and option.tradable ~= false then return {{id=option.itemID, count=1}} end
        return {}
    end
    if option.materialsVerified == false then return {} end
    return option.materials or {}
end
function S.Estimate(requirements)
    local total, missing, oldest = 0, 0, 0
    for _, material in ipairs(requirements) do
        local price, age = S.Price(material.id)
        if price then total = total + price*material.count else missing = missing+1 end
        if type(age) == "number" then oldest = math.max(oldest, age) end
    end
    return {total=total, missing=missing, complete=missing==0 and #requirements>0, age=oldest}
end
function S.PriceStatus(requirements)
    if #requirements==0 then return "" end
    local estimate=S.Estimate(requirements)
    if estimate.complete then return "" end
    if ns.db and ns.db.settings.autoPriceImport==false then return ns.L("Manuelle Preisübernahme: fehlende Preise über „Preise importieren“ laden.") end
    if type(Auctionator)~="table" then return ns.L("Preise: Auctionator ist nicht geladen.") end
    local source=api()
    if not source or type(source.GetAuctionPriceByItemID)~="function" then return ns.L("Preise: Auctionator-Preisabfrage nicht verfügbar.") end
    return ns.L("Auctionator liefert für ")..estimate.missing..ns.L(" von ")..#requirements..ns.L(" Waren noch keinen Preis.")
end
function S.MaterialsNote(option)
    if option.kind=="reward" then
        return option.availability=="available" and ns.L(option.acquisition) or ns.L("Belohnung · Bezugsquelle noch offen")
    end
    if option.materialsVerified==false then return ns.L("Reagenzien noch nicht bestätigt") end
    return ns.L("Materialdaten fehlen")
end
function S.PriceText(cost)
    if cost.complete then return ns.Money(cost.total) end
    if cost.total > 0 then return ns.L("ab ")..ns.Money(cost.total)..ns.L(" (unvollständig)") end
    return ns.L("Preis unbekannt")
end
local function quantity(choice)
    return math.max(1,math.min(99,math.floor(tonumber(choice.quantity) or 1)))
end
local function cartSlot(key,choice)
    return choice.slot or tonumber(key)
end
function S.Find(slot,option,mode)
    if not option then return nil end
    for key,choice in pairs(ns.char.cart) do
        if cartSlot(key,choice)==slot and choice.id==option.id and choice.mode==mode then return key,choice end
    end
end
function S.Replacement(slot,option,mode,preferred)
    local keys={}
    for key,choice in pairs(ns.char.cart) do
        if cartSlot(key,choice)==slot then keys[#keys+1]=key end
    end
    table.sort(keys)
    local key=preferred and ns.char.cart[preferred] and cartSlot(preferred,ns.char.cart[preferred])==slot and preferred
        or ns.char.cart[tostring(slot)] and tostring(slot) or keys[1]
    local choice=key and ns.char.cart[key]
    if choice and (not option or choice.id~=option.id or choice.mode~=mode) then return key,choice end
end
-- Append retains other recipes for this equipment slot. Repeated recipes gain one.
function S.Append(slot,option,mode)
    if not option or #S.Requirements(option,mode)==0 then return false,ns.L("Keine verifizierten Einkaufsmaterialien hinterlegt.") end
    local key,previous=S.Find(slot,option,mode)
    if previous then
        local count=quantity(previous)
        if count>=99 then return false,ns.L("Maximal 99 pro Eintrag. Anzahl im Warenkorb ändern.") end
        previous.quantity=count+1
    else
        key=tostring(slot);local index=0
        while ns.char.cart[key] do index=index+1;key=tostring(slot)..":"..index end
        ns.char.cart[key]={slot=slot,id=option.id,mode=mode,quantity=1}
    end
    S.CartChanged()
    return true,ns.L("Einkaufsliste: Anzahl dieses Eintrags auf ")..quantity(ns.char.cart[key])..ns.L(" gesetzt.")
end
-- Explicit replacement; legacy numeric slot keys remain readable.
function S.Add(slot,option,mode,key)
    if not option or #S.Requirements(option,mode)==0 then return false,ns.L("Keine verifizierten Einkaufsmaterialien hinterlegt.") end
    key=key or tostring(slot)
    local previous=ns.char.cart[key]
    local same=previous and previous.id==option.id
    local count=same and quantity(previous) or 1
    if same and previous.mode==mode then count=count+1 end
    local otherKey,other=S.Find(slot,option,mode)
    if other and otherKey~=key then count=count+quantity(other) end
    if count>99 then return false,ns.L("Maximal 99 pro Eintrag. Anzahl im Warenkorb ändern.") end
    if other and otherKey~=key then
        other.quantity=count;ns.char.cart[key]=nil
    else ns.char.cart[key]={slot=slot,id=option.id,mode=mode,quantity=count} end
    S.CartChanged()
    return true,ns.L("Einkaufsliste: Anzahl dieses Eintrags auf ")..count..ns.L(" gesetzt.")
end
function S.AddLabel(slot,option,mode)
    return S.Find(slot,option,mode) and ns.L("Hinzufügen (+1)") or ns.L("Auf Einkaufsliste")
end
function S.SetQuantity(slot, value)
    local choice=ns.char.cart[tostring(slot)]
    if not choice or type(value)~="number" then return false end
    choice.quantity=quantity({quantity=value});S.CartChanged();return true
end
function S.Aggregate(cart, lookup, countFn)
    local byID, entries = {}, {}
    for slot, choice in pairs(cart) do
        local option = lookup[choice.id]
        if option then
            local entry={key=slot,slot=cartSlot(slot,choice), option=option, mode=choice.mode, quantity=quantity(choice), requirements={}}
            entries[#entries+1]=entry
            local own={}
            for _,material in ipairs(S.Requirements(option, choice.mode)) do
                own[material.id]=(own[material.id] or 0)+material.count*entry.quantity
            end
            for id,count in pairs(own) do
                entry.requirements[#entry.requirements+1]={id=id,count=count}
                local total=byID[id] or {id=id,count=0,contributors={}}
                total.count=total.count+count
                total.contributors[#total.contributors+1]={key=entry.key,slot=entry.slot,option=option,quantity=entry.quantity,count=count}
                byID[id]=total
            end
            table.sort(entry.requirements,function(a,b) return a.id<b.id end)
        end
    end
    local requirements = {}
    for id,material in pairs(byID) do
        material.owned=countFn and countFn(id) or 0
        material.missing=math.max(0,material.count-material.owned)
        table.sort(material.contributors,function(a,b) return a.slot==b.slot and a.key<b.key or a.slot<b.slot end)
        requirements[#requirements+1]=material
    end
    table.sort(requirements, function(a,b) return a.id < b.id end)
    table.sort(entries, function(a,b) return a.slot==b.slot and a.key<b.key or a.slot<b.slot end)
    return requirements, entries
end
-- Compare whole-cart shortages before/after removal, sharing bag stock only once.
function S.RemovalImpact(requirements,entry)
    local removed,after,saved={},{},{}
    for _,m in ipairs(entry.requirements) do removed[m.id]=(removed[m.id] or 0)+m.count end
    for _,m in ipairs(requirements) do
        local owned=m.owned or A.Count(m.id)
        local before=math.max(0,m.count-owned)
        local remaining=math.max(0,m.count-(removed[m.id] or 0)-owned)
        if remaining>0 then after[#after+1]={id=m.id,count=remaining} end
        if before>remaining then saved[#saved+1]={id=m.id,count=before-remaining} end
    end
    local afterCost,savings=S.Estimate(after),S.Estimate(saved)
    if #after==0 then afterCost.complete=true end
    if #saved==0 then savings.complete=true end
    return {after=after, saved=saved, afterCost=afterCost, savings=savings}
end
function S.GetCart()
    local requirements,entries=S.Aggregate(ns.char.cart,ns.byID,A.Count)
    local adjustments=ns.char.cartAdjustments or {};ns.char.cartAdjustments=adjustments
    local present={}
    for _,m in ipairs(requirements) do
        local key=tostring(m.id);present[key]=true
        m.baseMissing=m.missing
        m.adjustment=tonumber(adjustments[key]) or 0
        m.purchaseCount=math.max(0,m.baseMissing+m.adjustment)
        m.missing=m.purchaseCount
    end
    -- A removed recipe must not leave invisible purchases behind.
    for key in pairs(adjustments) do if not present[key] then adjustments[key]=nil end end
    return requirements,entries
end
function S.SetResourceQuantity(id,value)
    if type(value)~="number" or value~=value or value==math.huge or value==-math.huge then return false end
    for _,m in ipairs(S.GetCart()) do
        if m.id==id then
            value=math.max(0,math.min(999999,math.floor(value)))
            local delta=value-m.baseMissing
            ns.char.cartAdjustments[tostring(id)]=delta~=0 and delta or nil
            S.CartChanged();return true
        end
    end
    return false
end
function S.ResetResourceQuantity(id)
    ns.char.cartAdjustments=ns.char.cartAdjustments or {}
    ns.char.cartAdjustments[tostring(id)]=nil;S.CartChanged()
end
function S.Missing(requirements)
    local merged,purchases={},{}
    for _,m in ipairs(requirements) do
        merged[m.id]=(merged[m.id] or 0)+m.count
        if m.purchaseCount~=nil then purchases[m.id]=(purchases[m.id] or 0)+m.purchaseCount end
    end
    local result={}
    for id,count in pairs(merged) do
        local needed=purchases[id] or math.max(0,count-A.Count(id))
        if needed>0 then result[#result+1]={id=id,count=needed,missing=needed} end
    end
    table.sort(result,function(a,b) return a.id<b.id end)
    return result
end
function S.CanExport()
    local source=api()
    return source and type(source.CreateShoppingList)=='function' and type(source.ConvertToSearchString)=='function' or false
end
function S.OpenAuctionatorShopping()
    -- These are Auctionator's internal identifiers, independent of its display language.
    local tab=AuctionatorTabs_Shopping
    if not tab or type(tab.Click)~='function' then return false end
    local ok=pcall(tab.Click,tab)
    if not ok then return false end
    local containers=AuctionatorShoppingFrame and AuctionatorShoppingFrame.ContainerTabs
    local views=Auctionator and Auctionator.Constants and Auctionator.Constants.ShoppingListViews
    if containers and type(containers.SetView)=='function' and views and views.Lists then
        ok=pcall(containers.SetView,containers,views.Lists)
    end
    return ok
end
function S.ExportRequirements(requirements)
    local source = api()
    if not source or type(source.CreateShoppingList) ~= "function" or type(source.ConvertToSearchString) ~= "function" then
        return false, ns.L("Auctionator-Einkaufslisten-API nicht verfügbar."), "api"
    end
    local terms, waiting = {}, false
    for _, material in ipairs(requirements) do
        if material.missing > 0 then
            local name = A.ItemInfo(material.id)
            if not name then
                A.RequestItem(material.id)
                waiting = true
            else
                local ok, term = pcall(source.ConvertToSearchString, ns.name,
                    {searchString=name, isExact=true, quantity=material.missing})
                if not ok or type(term) ~= "string" then return false, ns.L("Auctionator konnte den Suchbegriff nicht erstellen.") end
                terms[#terms+1] = term
            end
        end
    end
    if waiting then return false, ns.L("Gegenstandsnamen werden geladen."), "items" end
    if #terms == 0 then return false, ns.L("Keine fehlenden Materialien auf der Einkaufsliste.") end
    local listName = "GearWise Forever - "..(UnitName("player") or "Player")
    -- The shopping frame subscribes to list imports only while visible.
    local opened=not S.IsAuctionOpen() or S.OpenAuctionatorShopping()
    local ok, err = pcall(source.CreateShoppingList, ns.name, listName, terms)
    if not ok or err==false then return false, ns.L("Auctionator-Import fehlgeschlagen: ")..tostring(err) end
    local message=ns.L("Exportiert: ")..listName.." ("..#terms..ns.L(" Suchbegriffe).")
    if not opened then message=message..' '..ns.L('Liste übertragen. Den Einkaufsbereich in Auctionator bitte manuell öffnen.') end
    return true,message
end


function S.IsAuctionOpen()
    return S.auctionOpen or (AuctionHouseFrame and AuctionHouseFrame:IsShown())
        or (AuctionFrame and AuctionFrame:IsShown()) or false
end
function S.Export()
    if not S.IsAuctionOpen() then return false,ns.L("Bitte zuerst das Auktionshaus und Auctionator öffnen.") end
    local requirements=S.GetCart()
    local adjustmentSnapshot={}
    for key,value in pairs(ns.char.cartAdjustments) do adjustmentSnapshot[key]=value end
    local snapshot={}
    for slot,choice in pairs(ns.char.cart) do
        local option=ns.byID[choice.id]
        if option and #S.Requirements(option,choice.mode)>0 then
            snapshot[slot]={choice=choice,id=choice.id,mode=choice.mode,quantity=quantity(choice)}
        end
    end
    local ok,message=S.ExportRequirements(requirements)
    if not ok then return false,message..ns.L(" Deine Einkaufsliste bleibt erhalten.") end
    -- Preserve the draft if resource quantities changed during an API callback.
    for key,value in pairs(ns.char.cartAdjustments) do
        if adjustmentSnapshot[key]~=value then return true,message..ns.L(" Deine Einkaufsliste bleibt erhalten.") end
    end
    for key,value in pairs(adjustmentSnapshot) do
        if ns.char.cartAdjustments[key]~=value then return true,message..ns.L(" Deine Einkaufsliste bleibt erhalten.") end
    end
    -- Clear only successfully handed-over choices; keep any changes made during API callbacks.
    for slot,saved in pairs(snapshot) do
        local current=ns.char.cart[slot]
        if current==saved.choice and current.id==saved.id and current.mode==saved.mode and quantity(current)==saved.quantity then
            ns.char.cart[slot]=nil
        end
    end
    S.transferStatus=ns.L("An Auctionator übergeben und aus der Einkaufsliste entfernt.")
    return true,message..ns.L(" Übertragene Einträge wurden aus GearWise entfernt.")
end
function S.Remove(slot)
    ns.char.cart[tostring(slot)] = nil
    S.CartChanged()
end
function S.CartChanged()
    S.transferStatus = nil
    if ns.UI.RefreshCart then ns.UI.RefreshCart() end
end
function S.QueueAuctionCart()
    local visit=S.auctionVisit
    -- Wait until every AUCTION_HOUSE_SHOW handler has initialized its UI.
    C_Timer.After(0,function()
        if visit~=S.auctionVisit or not S.auctionOpen or S.cartOpenedThisVisit
            or not ns.enabled or not ns.char or not api() then return end
        local _,entries=S.GetCart()
        if #entries==0 then return end
        S.cartOpenedThisVisit=true
        if ns.UI.cartWindow and ns.UI.cartWindow:IsShown() then ns.UI.RefreshCart()
        else ns.UI.OpenCart() end
    end)
end
function S.OnEvent(event,addon)
    if event=='AUCTION_HOUSE_SHOW' then
        if not S.auctionOpen then
            S.auctionVisit=(S.auctionVisit or 0)+1;S.cartOpenedThisVisit=false
        end
        S.auctionOpen=true;S.QueueAuctionCart()
    elseif event=='AUCTION_HOUSE_CLOSED' or event=='PLAYER_LEAVING_WORLD' then
        S.auctionOpen=false;S.auctionVisit=(S.auctionVisit or 0)+1;S.cartOpenedThisVisit=false
    elseif event=='ADDON_LOADED' and addon=='Auctionator' and S.auctionOpen then
        S.QueueAuctionCart()
    end
end
