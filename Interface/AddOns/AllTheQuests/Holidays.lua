local _, ns = ...
local active, ready, checked, previous = {}, false, nil, ''
local aliases = {
    ['Midsummer Fire Festival'] = 'Midsummer',
    ['Feast of Winter Veil'] = 'Winter Veil',
    ['The Feast of Winter Veil'] = 'Winter Veil',
}
local fixed = {
    ['Winter Veil'] = {12, 15, 1, 2},
    ['Midsummer'] = {6, 21, 7, 5},
}
local function now()
    if C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime then return C_DateAndTime.GetCurrentCalendarTime() end
    if date and GetServerTime then
        local t=date('*t',GetServerTime())
        return {year=t.year,month=t.month,monthDay=t.day,hour=t.hour,minute=t.min}
    end
end
local function stamp(t)
    if not t or not t.year or not t.month or not t.monthDay then return nil end
    return (((t.year*12+t.month)*32+t.monthDay)*24+(t.hour or 0))*60+(t.minute or 0)
end
function ns.InHolidayWindow(t,w)
    if not t then return nil end
    local value=((t.month*32+t.monthDay)*24+(t.hour or 0))*60+(t.minute or 0)
    local first=(w[1]*32+w[2])*24*60+(w[5] or 0)*60
    -- Quest-only windows include the entire final date; event schedules have an exact end hour.
    local last=(w[3]*32+w[4])*24*60+(w[6] and w[6]*60 or 24*60)
    if first>last then return value>=first or value<last end
    return value>=first and value<last
end
function ns.UpdateHolidays(force)
    if not force and checked and GetTime()-checked<30 then return false end
    checked=GetTime()
    local t=now()
    active={}
    if ready and t and C_Calendar and C_Calendar.GetMonthInfo and C_Calendar.GetHolidayInfo and C_Calendar.GetNumDayEvents then
        local base=C_Calendar.GetMonthInfo(0)
        if base then
            local offset=(t.year-base.year)*12+t.month-base.month
            for i=1,C_Calendar.GetNumDayEvents(offset,t.monthDay) do
                local event=C_Calendar.GetHolidayInfo(offset,t.monthDay,i)
                if event then
                    local first,last=stamp(event.startTime),stamp(event.endTime)
                    if (not first or stamp(t)>=first) and (not last or stamp(t)<last) then
                        active[aliases[event.name] or event.name]=true
                        if event.texture==235446 or event.texture==235447 or event.texture==235448 then active['Darkmoon Faire']=true end
                    end
                end
            end
        end
    end
    -- Only signal a redraw when an event or a date-window boundary can change.
    local states={}
    for _,name in ipairs(ns.eventNames or {}) do states[#states+1]=name..':'..tostring(ns.EventState(name)) end
    states[#states+1]=t and (t.year..':'..t.month..':'..t.monthDay) or 'unknown-date'
    local signature=table.concat(states,'|')
    local changed=signature~=previous; previous=signature
    return changed
end
function ns.EventState(name)
    local override=ns.eventOverrides and ns.eventOverrides[name]
    if override=='show' then return true,'Manual: show' end
    if override=='hide' then return false,'Manual: hide' end
    if active[name] then return true,'Calendar: active' end
    if fixed[name] then return ns.InHolidayWindow(now(),fixed[name]),'Standard date fallback' end
    -- Variable-date and one-off events cannot safely be inferred from old annual dates.
    return nil,'Unknown: hidden in Auto'
end
function ns.HolidayInactive(id)
    local name=ns.holidays[id]
    if not name then return false end
    local override=ns.eventOverrides and ns.eventOverrides[name]
    if override=='hide' then return true end
    -- A manual Show override is also the escape hatch for changed server quest dates.
    if override=='show' then return false end
    local window=ns.holidayWindows and ns.holidayWindows[id]
    if window and ns.InHolidayWindow(now(),window)~=true then return true end
    return ns.EventState(name)~=true
end
function ns.CalendarReady()
    ready=true
    return ns.UpdateHolidays(true)
end
ns.eventNames={}
do
    local seen={}
    for _,name in pairs(ns.holidays) do if not seen[name] then seen[name]=true; ns.eventNames[#ns.eventNames+1]=name end end
    table.sort(ns.eventNames)
end
function ns.ShowEventOptions(onChange)
    if not ns.eventsWindow then
        local w=CreateFrame('Frame','AllTheQuestsEvents',UIParent,'BasicFrameTemplateWithInset')
        ns.eventsWindow=w; w:SetSize(455,100+#ns.eventNames*30); w:SetPoint('CENTER'); w:SetFrameStrata('DIALOG')
        w.TitleText:SetText("AllTheQuests |cffc9a45c- by Reversal|r - Holiday / event overrides")
        table.insert(UISpecialFrames,'AllTheQuestsEvents')
        local hint=w:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
        hint:SetPoint('TOPLEFT',16,-32); hint:SetWidth(420); hint:SetJustifyH('LEFT')
        hint:SetText('Auto uses calendar or supported dates; unknown events stay hidden. Click to cycle Auto / Show / Hide.')
        w.rows={}
        for i,name in ipairs(ns.eventNames) do
            local b=CreateFrame('Button',nil,w,'UIPanelButtonTemplate')
            b:SetSize(420,25); b:SetPoint('TOPLEFT',16,-72-(i-1)*30)
            b.name=name; w.rows[#w.rows+1]=b
            b:SetScript('OnClick',function()
                local mode=ns.eventOverrides[name]
                ns.eventOverrides[name]=mode==nil and 'show' or mode=='show' and 'hide' or nil
                ns.ShowEventOptions(onChange); onChange()
            end)
        end
    end
    for _,b in ipairs(ns.eventsWindow.rows) do
        local _,reason=ns.EventState(b.name)
        b:SetText(b.name..' - '..reason)
    end
    ns.eventsWindow:Show()
end

