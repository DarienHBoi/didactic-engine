-- Mail transaction engine. A frozen, explicitly confirmed selection is sent
-- one letter at a time; only MAIL_SEND_SUCCESS permits the next letter.
local _, ns = ...
local L = ns.L
local Mail = { items = {}, selected = {}, open = false }
ns.Mail = Mail
local db, recipientKey, job, generation = nil, nil, nil, 0
local scheduledGeneration
local MAX_WAIT, STEP = 10, 0.15

local function Secret(value) return issecretvalue and issecretvalue(value) or false end
local function Now() return GetTime() end
local function Changed() if Mail.onChange then Mail.onChange() end end
local function Status(key, ...)
    Mail.status = select("#", ...) > 0 and string.format(L[key], ...) or L[key]
    Changed()
end
local function Limit() return math.max(1, math.min(12, tonumber(ATTACHMENTS_MAX_SEND) or 12)) end
Mail.Limit = Limit
local function ItemString(link)
    return type(link) == "string" and not Secret(link) and link:match("item:([^|]+)") or nil
end
local function BagInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        return C_Container.GetContainerItemInfo(bag, slot)
    end
    if GetContainerItemInfo then
        local icon,count,locked,quality,_,_,link = GetContainerItemInfo(bag,slot)
        return link and {iconFileID=icon,stackCount=count,isLocked=locked,quality=quality,hyperlink=link} or nil
    end
end
local function GetFacts(bag,slot)
    local info=BagInfo(bag,slot)
    if not info or info.isLocked or Secret(info.hyperlink) or not info.hyperlink then return nil end
    local get=(C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not get then return nil end
    local name,link,quality,_,_,_,_,_,equipLoc,icon,_,classID,subclassID,bindType=get(info.hyperlink)
    if not name or not quality or quality<2 or quality>4 or (classID~=2 and classID~=4)
        or subclassID==5 and classID==4 or not equipLoc or equipLoc=="" then return nil end
    if bindType~=0 and bindType~=2 and bindType~=3 then return nil end
    local bound=info.isBound
    local location
    if ItemLocation and ItemLocation.CreateFromBagAndSlot then location=ItemLocation:CreateFromBagAndSlot(bag,slot) end
    if bound==nil and location and C_Item and C_Item.IsBound then bound=C_Item.IsBound(location) end
    -- Unknown binding is not assumed transferable. This also excludes warbound
    -- and account-only items whose recipient rules vary between clients.
    if Secret(bound) or bound~=false then return nil end
    local guid=location and C_Item and C_Item.GetItemGUID and C_Item.GetItemGUID(location) or nil
    -- GetItemInfo can rewrite link context (e.g. player level). Transaction
    -- identity must use the actual bag link, matching the picked-up item.
    return {bag=bag,slot=slot,link=info.hyperlink,name=name,
        count=info.stackCount or 1,icon=info.iconFileID or icon or 134400,
        quality=quality,guid=guid,key=bag..":"..slot}
end
local function Same(a,b)
    return a and b and ItemString(a.link)==ItemString(b.link) and a.count==b.count
        and (not a.guid or a.guid==b.guid)
end
local function IsCombat() return InCombatLockdown and InCombatLockdown() end
local function CursorEmpty() return not GetCursorInfo or GetCursorInfo()==nil end
local function Attachment(i)
    if GetSendMailItemLink then return GetSendMailItemLink(i) end
end
local function HasAttachment(i)
    if HasSendMailItem then return HasSendMailItem(i) end
    return Attachment(i)~=nil or GetSendMailItem and GetSendMailItem(i)~=nil
end
local function DraftEmpty()
    for i=1,Limit() do if HasAttachment(i) then return false end end
    for _,field in ipairs({"SendMailNameEditBox","SendMailSubjectEditBox","SendMailBodyEditBox"}) do
        local box=_G[field]
        if box and box:GetText()~="" then return false end
    end
    if GetSendMailMoney and GetSendMailMoney()~=0 then return false end
    if GetSendMailCOD and GetSendMailCOD()~=0 then return false end
    if MoneyInputFrame_GetCopper and SendMailMoney and MoneyInputFrame_GetCopper(SendMailMoney)~=0 then return false end
    return true
end
local function Available()
    return Mail.open and not IsCombat() and MailFrame and MailFrame:IsShown()
end
local function APIs()
    return C_Timer and C_Timer.After and SendMail and GetSendMailItem and GetSendMailItemLink and ClickSendMailItemButton
        and SetSendMailMoney and SetSendMailCOD and GetCursorInfo
        and ((C_Container and C_Container.PickupContainerItem) or PickupContainerItem)
        and SendMailNameEditBox and SendMailSubjectEditBox and SendMailBodyEditBox
end

function Mail.Init(saved)
    db=saved
    recipientKey=(UnitName("player") or "").."-"..(GetRealmName() or "")
    if db.mailRecipients==nil then db.mailRecipients={} end
    Mail.recipient=type(db.mailRecipients)=="table" and db.mailRecipients[recipientKey] or ""
    if type(Mail.recipient)~="string" then Mail.recipient="" end
    Mail.RememberCharacter()
end

function Mail.RememberCharacter()
    if not db then return end
    local name,realm=UnitName("player"),GetRealmName()
    if Secret(name) or Secret(realm) or type(name)~="string" or type(realm)~="string" or name=="" or realm=="" then return end
    if db.mailCharacters==nil then db.mailCharacters={} end
    -- Preserve unknown/corrupt saved data rather than replacing it silently.
    if type(db.mailCharacters)~="table" then return end
    local address=name.."-"..realm:gsub("%s","")
    db.mailCharacters[address]=true
    Mail.characterAddress=address
end

function Mail.GetKnownRecipients()
    local names={}
    if db and type(db.mailCharacters)=="table" then
        for address,known in pairs(db.mailCharacters) do
            if known==true and type(address)=="string" and #address<=100
                and address:find(".-.") and not address:find("[%s%c|,;]")
                and string.lower(address)~=string.lower(Mail.characterAddress or "") then
                names[#names+1]=address
            end
        end
    end
    table.sort(names)
    return names
end

function Mail.Scan()
    if job or IsCombat() then return false end
    local previous={}
    for _,e in ipairs(Mail.items) do previous[e.key]=e end
    local items,selected={},{}
    local slots=(C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    if slots then
        for bag=0,NUM_BAG_SLOTS or 4 do
            for slot=1,slots(bag) or 0 do
                local e=GetFacts(bag,slot)
                if e and (not db.qualityFilter or db.qualityFilter[e.quality]~=false) then
                    items[#items+1]=e
                    if Mail.selected[e.key] and Same(previous[e.key],e) then selected[e.key]=true end
                end
            end
        end
    end
    Mail.items,Mail.selected=items,selected
    Mail.plan=nil
    Changed()
    return true
end
function Mail.ToggleItem(key)
    if job then return end
    Mail.selected[key]=not Mail.selected[key] or nil
    Mail.plan=nil;Mail.status=nil
    Changed()
end
function Mail.SelectAll(enabled)
    if job then return end
    Mail.selected={}
    if enabled then for _,e in ipairs(Mail.items) do Mail.selected[e.key]=true end end
    Mail.plan=nil;Mail.status=nil
    Changed()
end
function Mail.SetRecipient(value)
    if job then return end
    Mail.recipient=value or ""
    Mail.plan=nil;Mail.status=nil
    Changed()
end
local function Recipient()
    local name=(Mail.recipient or ""):match("^%s*(.-)%s*$")
    if name=="" or #name>100 or name:find("[%c|,;]") or name:find("%s") then return nil end
    local own=string.lower((UnitName("player") or "").."-"..(GetRealmName() or "")):gsub("%s","")
    local normalized=string.lower(name):gsub("%s","")
    if normalized==string.lower(UnitName("player") or "") or normalized==own then return nil end
    return name
end
function Mail.Prepare()
    if job then return false end
    Mail.plan=nil
    if not Available() then Status("MAIL_NEED_BOX"); return false end
    if not APIs() then Status("MAIL_UNSUPPORTED"); return false end
    if not CursorEmpty() then Status("MAIL_CURSOR"); return false end
    if not DraftEmpty() then Status("MAIL_DRAFT"); return false end
    if C_Mail and C_Mail.IsCommandPending and C_Mail.IsCommandPending() then Status("MAIL_PENDING");return false end
    local name=Recipient()
    if not name then Status("MAIL_BAD_RECIPIENT");return false end
    local items={}
    for _,e in ipairs(Mail.items) do
        if Mail.selected[e.key] then
            if not Same(e,GetFacts(e.bag,e.slot)) then Status("MAIL_STALE");return false end
            items[#items+1]=e
        end
    end
    if #items==0 then Status("MAIL_EMPTY");return false end
    Mail.plan={recipient=name,items=items,letters=math.ceil(#items/Limit()),created=Now()}
    Status("MAIL_CONFIRM",#items,name,Mail.plan.letters)
    return true
end

function Mail.Stop(key)
    generation=generation+1
    job=nil;Mail.busy=false;Mail.plan=nil
    Status(key or "MAIL_STOPPED")
end
local Schedule,Advance
local function RunAdvance()
    local ok,err=pcall(Advance)
    if not ok and job then
        local detail=not Secret(err) and type(err)=="string" and err or "unknown API error"
        Mail.lastError=detail
        Mail.Stop()
        Status("MAIL_API_ERROR",detail)
    end
end
Schedule=function(delay)
    if scheduledGeneration==generation then return end
    local token=generation
    scheduledGeneration=token
    C_Timer.After(delay or STEP,function()
        if token~=generation then return end
        scheduledGeneration=nil
        if not job then return end
        RunAdvance()
    end)
end
local function ValidAttachments()
    for i,e in ipairs(job.attached) do
        if ItemString(Attachment(i))~=ItemString(e.link) then return false end
        local _,_,_,count=GetSendMailItem(i)
        if count~=e.count then return false end
    end
    for i=#job.attached+1,Limit() do if HasAttachment(i) then return false end end
    return true
end
Advance=function()
    if not Available() then Mail.Stop("MAIL_STOPPED");return end
    if Now()>job.deadline then Mail.Stop("MAIL_TIMEOUT");return end
    if job.phase=="sending" then Schedule();return end
    if not CursorEmpty() then Mail.Stop("MAIL_CURSOR");return end
    if job.phase=="next" then
        if not DraftEmpty() then Schedule();return end
        if C_Mail and C_Mail.IsCommandPending and C_Mail.IsCommandPending() then Schedule();return end
        job.phase="attach";job.attached={};job.next=job.index
        if MailFrameTab_OnClick then MailFrameTab_OnClick(nil,2) end
        if SetSendMailShowing then SetSendMailShowing(true) end
        SendMailNameEditBox:SetText(job.recipient)
        SendMailSubjectEditBox:SetText(L.MAIL_SUBJECT)
        SendMailBodyEditBox:SetText("")
        SetSendMailMoney(0);SetSendMailCOD(0)
    end
    if job.phase=="attach" then
        -- Wait for the previous attachment to be visible before picking another.
        if #job.attached>0 and not ValidAttachments() then Schedule();return end
        local e=job.items[job.next]
        if e and #job.attached<Limit() then
            if not Same(e,GetFacts(e.bag,e.slot)) then Mail.Stop("MAIL_STALE");return end
            local pickup=(C_Container and C_Container.PickupContainerItem) or PickupContainerItem
            pickup(e.bag,e.slot)
            local kind,_,link=GetCursorInfo()
            if kind~="item" or ItemString(link)~=ItemString(e.link) then Mail.Stop("MAIL_CURSOR");return end
            ClickSendMailItemButton(#job.attached+1)
            job.attached[#job.attached+1]=e;job.next=job.next+1
            Schedule();return
        end
        if #job.attached==0 then Mail.Stop("MAIL_EMPTY");return end
        if C_Mail and C_Mail.IsCommandPending and C_Mail.IsCommandPending() then Schedule();return end
        if SendMailNameEditBox:GetText()~=job.recipient or SendMailSubjectEditBox:GetText()~=L.MAIL_SUBJECT
            or SendMailBodyEditBox:GetText()~="" then Mail.Stop("MAIL_DRAFT_CHANGED");return end
        if GetSendMailMoney and GetSendMailMoney()~=0 or GetSendMailCOD and GetSendMailCOD()~=0
            or MoneyInputFrame_GetCopper and SendMailMoney and MoneyInputFrame_GetCopper(SendMailMoney)~=0 then
            Mail.Stop("MAIL_DRAFT_CHANGED");return
        end
        job.phase="sending";job.deadline=Now()+MAX_WAIT
        Status("MAIL_PROGRESS",job.sent+1,job.letters,job.recipient)
        -- Set the phase before SendMail: synchronous success/failure is valid too.
        SendMail(job.recipient,L.MAIL_SUBJECT,"")
        if job then Schedule() end
    end
end

function Mail.Confirm()
    if job or not Mail.plan then return false end
    local plan=Mail.plan
    if Now()-plan.created>60 then Mail.plan=nil;Status("MAIL_STALE");return false end
    -- Revalidate the frozen selection and empty draft immediately before starting.
    if not Mail.Prepare() then return false end
    if Mail.plan.recipient~=plan.recipient or #Mail.plan.items~=#plan.items then Mail.plan=nil;Status("MAIL_STALE");return false end
    for i,e in ipairs(plan.items) do
        local current=Mail.plan.items[i]
        if not Same(e,current) or e.bag~=current.bag or e.slot~=current.slot then
            Mail.plan=nil;Status("MAIL_STALE");return false
        end
    end
    generation=generation+1
    job={recipient=plan.recipient,items=plan.items,index=1,next=1,sent=0,letters=plan.letters,
        attached={},phase="next",deadline=Now()+MAX_WAIT}
    Mail.plan=nil;Mail.busy=true
    Changed()
    if type(db.mailRecipients)=="table" then db.mailRecipients[recipientKey]=plan.recipient end
    RunAdvance()
    return true
end
function Mail.OnEvent(event)
    if event=="PLAYER_LOGIN" then Mail.RememberCharacter()
    elseif event=="MAIL_SHOW" then Mail.open=true;Mail.plan=nil;Mail.Scan()
    elseif event=="MAIL_CLOSED" then Mail.open=false;Mail.Stop("MAIL_CLOSED_STATUS");Mail.selected={};if Mail.onClose then Mail.onClose() end
    elseif event=="PLAYER_REGEN_DISABLED" then if job then Mail.Stop("MAIL_STOPPED") end;if Mail.onClose then Mail.onClose() end
    elseif event=="MAIL_FAILED" and job then Mail.Stop("MAIL_FAILED_STATUS")
    elseif event=="MAIL_SEND_SUCCESS" and job and job.phase=="sending" then
        job.sent=job.sent+1;job.index=job.next
        if job.index>#job.items then
            local n=job.sent
            job=nil;Mail.busy=false;Mail.selected={};generation=generation+1
            Mail.Scan();Status("MAIL_DONE",n)
        else
            job.phase="next";job.deadline=Now()+MAX_WAIT
            Schedule(0.4)
        end
    elseif event=="BAG_UPDATE_DELAYED" and Mail.open and not job then Mail.Scan() end
end

local events=CreateFrame("Frame")
for _,event in ipairs({"PLAYER_LOGIN","MAIL_SHOW","MAIL_CLOSED","MAIL_SEND_SUCCESS","MAIL_FAILED","PLAYER_REGEN_DISABLED","BAG_UPDATE_DELAYED"}) do events:RegisterEvent(event) end
events:SetScript("OnEvent",function(_,event) if db then Mail.OnEvent(event) end end)
