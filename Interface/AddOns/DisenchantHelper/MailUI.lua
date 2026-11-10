local _, ns = ...
local Mail, L = ns.Mail, ns.L
local UI = {}
ns.MailUI = UI
local frame, saved, makeWindow
local hookedSendFrame

function UI.UpdateMailboxButton()
    if not UI.mailboxButton then return end
    if SendMailFrame and SendMailFrame:IsShown() then
        UI.mailboxButton:Hide()
    else
        UI.mailboxButton:Show()
    end
    UI.mailboxButton:SetEnabled(not InCombatLockdown())
end

-- Mail UI may be loaded on demand, after the addon has initialized.
function UI.AttachMailboxButton()
    if not makeWindow or not MailFrame then return end
    if not UI.mailboxButton then
        local button=CreateFrame("Button","DisenchantHelper_MailboxButton",MailFrame,"UIPanelButtonTemplate")
        button:SetSize(160,22)
        button:SetPoint("TOPRIGHT",MailFrame,"TOPRIGHT",-30,-30)
        button:SetText("Disenchant Helper")
        button:SetScript("OnClick",function() UI.Open() end)
        UI.mailboxButton=button
    end
    -- Listen to the actual send pane, including tab switches made by addons.
    if SendMailFrame and hookedSendFrame~=SendMailFrame then
        SendMailFrame:HookScript("OnShow",UI.UpdateMailboxButton)
        SendMailFrame:HookScript("OnHide",UI.UpdateMailboxButton)
        hookedSendFrame=SendMailFrame
    end
    UI.UpdateMailboxButton()
end

local launcherEvents=CreateFrame("Frame")
for _,event in ipairs({"ADDON_LOADED","MAIL_SHOW","PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED"}) do
    launcherEvents:RegisterEvent(event)
end
launcherEvents:SetScript("OnEvent",function() UI.AttachMailboxButton() end)

local function Button(parent,text,width)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
    b:SetSize(width,22);b:SetText(text)
    return b
end
local function Text(parent,text,font)
    local t=parent:CreateFontString(nil,"OVERLAY",font or "GameFontNormalSmall")
    t:SetText(text);t:SetJustifyH("LEFT")
    return t
end
function UI.ToggleRecipients()
    if not frame or Mail.busy then return end
    local menu=frame.recipientMenu
    if menu:IsShown() then menu:Hide();return end
    local names=Mail.GetKnownRecipients()
    for i,address in ipairs(names) do
        local row=menu.rows[i]
        if not row then
            row=Button(menu.child,"",500)
            row:SetPoint("TOPLEFT",0,-(i-1)*24)
            row:SetScript("OnClick",function(self)
                if Mail.busy then return end
                frame.recipient:SetText(self.address)
                frame.recipient:ClearFocus()
                menu:Hide()
                Mail.SetRecipient(self.address)
            end)
            menu.rows[i]=row
        end
        row.address=address;row:SetText(address);row:Show()
    end
    for i=#names+1,#menu.rows do menu.rows[i]:Hide() end
    menu.empty:SetShown(#names==0)
    menu.child:SetHeight(math.max(40,#names*24))
    menu.scroll:SetVerticalScroll(0)
    menu:SetHeight(math.max(60,math.min(6,#names)*24+16))
    menu:Show()
end
function UI.Refresh()
    if not frame then return end
    local busy=Mail.busy
    local count=0
    for _ in pairs(Mail.selected) do count=count+1 end
    frame.summary:SetText(string.format(L.MAIL_SELECTION,count,math.ceil(count/Mail.Limit())))
    frame.status:SetText(Mail.status or L.MAIL_INSTRUCTIONS)
    frame.action:SetText(Mail.plan and L.MAIL_SEND_CONFIRM or L.MAIL_REVIEW)
    frame.action:SetEnabled(not busy and Mail.open and count>0)
    frame.refresh:SetEnabled(not busy)
    frame.all:SetEnabled(not busy);frame.none:SetEnabled(not busy)
    if busy then frame.recipient:Disable() else frame.recipient:Enable() end
    frame.characters:SetEnabled(not busy)
    if busy then frame.recipientMenu:Hide() end
    frame.cancel:SetEnabled(busy or Mail.plan~=nil)
    for i,e in ipairs(Mail.items) do
        local row=frame.rows[i]
        if not row then
            row=CreateFrame("Button",nil,frame.child)
            row:SetSize(500,28)
            row.check=CreateFrame("CheckButton",nil,row,"UICheckButtonTemplate")
            row.check:SetSize(24,24);row.check:SetPoint("LEFT",0,0)
            row.icon=row:CreateTexture(nil,"ARTWORK")
            row.icon:SetSize(20,20);row.icon:SetPoint("LEFT",row.check,"RIGHT",4,0)
            row.label=Text(row,"","GameFontNormal")
            row.label:SetPoint("LEFT",row.icon,"RIGHT",8,0)
            row.label:SetPoint("RIGHT",row,"RIGHT",-8,0);row.label:SetWordWrap(false)
            row:SetScript("OnClick",function(self) Mail.ToggleItem(self.item.key) end)
            row.check:SetScript("OnClick",function(self)
                local r=self:GetParent();Mail.ToggleItem(r.item.key)
                self:SetChecked(Mail.selected[r.item.key]==true)
            end)
            row:SetScript("OnEnter",function(self)
                if self.item then GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetBagItem(self.item.bag,self.item.slot);GameTooltip:Show() end
            end)
            row:SetScript("OnLeave",function() GameTooltip:Hide() end)
            frame.rows[i]=row
        end
        row.item=e;row:SetPoint("TOPLEFT",0,-(i-1)*30)
        row.icon:SetTexture(e.icon)
        row.label:SetText(e.link..(e.count>1 and " x"..e.count or ""))
        row.check:SetChecked(Mail.selected[e.key]==true)
        row.check:SetEnabled(not busy);row:SetEnabled(not busy);row:Show()
    end
    for i=#Mail.items+1,#frame.rows do frame.rows[i].item=nil;frame.rows[i]:Hide() end
    frame.child:SetHeight(math.max(1,#Mail.items*30))
end
local function Create()
    frame=makeWindow("DisenchantHelper_MailFrame",580,520)
    UI.frame=frame
    frame:SetPoint("CENTER",UIParent,"CENTER",180,0)
    frame.title:SetText(L.MAIL_TITLE);frame.rows={}
    local label=Text(frame,L.MAIL_RECIPIENT,"GameFontNormal")
    label:SetPoint("TOPLEFT",18,-44)
    local edit=CreateFrame("EditBox",nil,frame,"InputBoxTemplate")
    edit:SetSize(340,24);edit:SetPoint("TOPLEFT",18,-65);edit:SetAutoFocus(false);edit:SetMaxLetters(100)
    frame.recipient=edit
    edit:SetText(Mail.recipient or "")
    edit:SetScript("OnTextChanged",function(self,userInput)
        if userInput then frame.recipientMenu:Hide();Mail.SetRecipient(self:GetText()) end
    end)
    edit:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    frame.characters=Button(frame,L.MAIL_KNOWN_CHARS,170)
    frame.characters:SetPoint("LEFT",edit,"RIGHT",12,0)
    frame.characters:SetScript("OnClick",UI.ToggleRecipients)
    local menu=CreateFrame("Frame",nil,frame)
    frame.recipientMenu=menu;menu.rows={}
    menu:SetSize(540,160);menu:SetPoint("TOPLEFT",edit,"BOTTOMLEFT",0,-4)
    menu:SetFrameStrata("DIALOG")
    local background=menu:CreateTexture(nil,"BACKGROUND")
    background:SetAllPoints();background:SetColorTexture(0.06,0.06,0.06,0.98)
    menu.scroll=CreateFrame("ScrollFrame",nil,menu,"UIPanelScrollFrameTemplate")
    menu.scroll:SetPoint("TOPLEFT",6,-6);menu.scroll:SetPoint("BOTTOMRIGHT",-28,6)
    menu.child=CreateFrame("Frame",nil,menu.scroll);menu.child:SetSize(500,40)
    menu.scroll:SetScrollChild(menu.child)
    menu.empty=Text(menu.child,L.MAIL_NO_KNOWN_CHARS)
    menu.empty:SetPoint("TOPLEFT",4,-4);menu.empty:SetWidth(490);menu.empty:SetWordWrap(true)
    menu:Hide()
    local instructions=Text(frame,L.MAIL_INSTRUCTIONS)
    instructions:SetPoint("TOPLEFT",18,-100);instructions:SetWidth(540);instructions:SetWordWrap(true)
    frame.summary=Text(frame,"","GameFontNormal")
    frame.summary:SetPoint("TOPLEFT",18,-140)
    local scroll=CreateFrame("ScrollFrame",nil,frame,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",18,-164);scroll:SetPoint("BOTTOMRIGHT",-36,126)
    frame.child=CreateFrame("Frame",nil,scroll);frame.child:SetSize(500,1);scroll:SetScrollChild(frame.child)
    frame.status=Text(frame,"")
    frame.status:SetPoint("BOTTOMLEFT",18,58);frame.status:SetWidth(540);frame.status:SetWordWrap(true)
    frame.all=Button(frame,L.SELECT_ALL,110);frame.all:SetPoint("BOTTOMLEFT",18,94)
    frame.all:SetScript("OnClick",function() Mail.SelectAll(true) end)
    frame.none=Button(frame,L.CLEAR_SELECTION,120);frame.none:SetPoint("LEFT",frame.all,"RIGHT",8,0)
    frame.none:SetScript("OnClick",function() Mail.SelectAll(false) end)
    frame.refresh=Button(frame,L.REFRESH,100);frame.refresh:SetPoint("LEFT",frame.none,"RIGHT",8,0)
    frame.refresh:SetScript("OnClick",function() Mail.Scan() end)
    frame.action=Button(frame,L.MAIL_REVIEW,190);frame.action:SetPoint("BOTTOMRIGHT",-18,18)
    frame.action:SetScript("OnClick",function()
        edit:ClearFocus()
        if Mail.plan then Mail.Confirm() else Mail.Prepare() end
        UI.Refresh()
    end)
    frame.cancel=Button(frame,L.MAIL_CANCEL,140);frame.cancel:SetPoint("RIGHT",frame.action,"LEFT",-8,0)
    frame.cancel:SetScript("OnClick",function() Mail.Stop() end)
    frame:HookScript("OnHide",function() menu:Hide();if Mail.busy then Mail.Stop() end;Mail.plan=nil end)
    frame:Hide()
end
function UI.Init(db,windowFactory)
    saved,makeWindow=db,windowFactory
    Mail.Init(saved)
    Mail.onChange=UI.Refresh
    Mail.onClose=function() if frame then frame:Hide() end end
    UI.AttachMailboxButton()
end
function UI.Open()
    if not Mail.open or InCombatLockdown() then
        DEFAULT_CHAT_FRAME:AddMessage("Disenchant Helper: "..L.MAIL_NEED_BOX)
        return
    end
    if not frame then Create() end
    if not frame:IsShown() then Mail.Scan();frame:Show() end
    UI.Refresh()
end
function UI.Toggle()
    if frame and frame:IsShown() then frame:Hide() else UI.Open() end
end
