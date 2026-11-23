-- AscendXP • purpose-built for World of Warcraft: Forever (interface 16001)
-- Original assets and independent UI. No combat-log inspection or automated play.
local addonName, addon = ...
local Money = addon.Money
local BlizzardBar = addon.BlizzardBar
local Projection = addon.Projection
local AX = CreateFrame("Frame")
local PATH = "Interface\\AddOns\\AscendXP\\Textures\\"
local C_TEAL = "|cff4bdfd7"
local C_GOLD = "|cffe5bd70"
local C_MUTED = "|cff91a8b1"
local C_GREEN = "|cff8bedb6"
local C_RED = "|cffff9a8c"
local MAX_LEVEL = 60
local floor, min, max, ceil, abs = math.floor, math.min, math.max, math.ceil, math.abs
local format, tostring, tonumber = string.format, tostring, tonumber

local defaults = {
    showTracker = true, locked = false, compact = false,
    questOverlay = true, restedOverlay = true, showMinimap = true,
    rateWindow = 15, scale = 1, x = 0, y = 170, minimapAngle = 215,
    showGold = true, hideBlizzardBar = true,
    uiMode = "bar", barScale = 1, barX = 0, barY = -14,
}
local db, ch, snapshot, tracker, barTracker, minimapButton, settingsFrame, questFrame, detailsFrame
local xpFill, restedFill, questFill, panelQuestMark, panelQuestHalo, barBackground, logo, levelFont, percentFont
local barXpFill, barRestedFill, barQuestFill, barQuestMark, barQuestHalo, barBack, barLevelText, barCenterText, barPercentText
local barRateText, barTimeText, barKillText, barQuestText, barGoldText, barGlow, barSpark
local barRateLabel, barTimeLabel, barKillLabel, barQuestLabel, barGoldLabel
local rows = {}, questFooter, footerText, footerBadge, btnCollapse
local goldStrip, goldValue, goldLoot, goldDetailsFrame, lootLedgerFrame, goldHitButton
local lootLedgerPage = 1
local questRows = {}
local quests = { items = {}, count = 0, knownXP = 0, unknown = 0 }
local questPage = 1
local pendingRefresh = false
local lastDraw = 0
local ApplyTracker, UpdateUI, LayoutBarTracker

local function IsNumber(v)
    return type(v) == "number" and (not issecretvalue or not issecretvalue(v))
end
local function SafePlayerXP()
    local level, xp, maximum = UnitLevel("player"), UnitXP("player"), UnitXPMax("player")
    if IsNumber(level) and level >= MAX_LEVEL and not IsNumber(maximum) then maximum=0 end
    if not IsNumber(level) or not IsNumber(xp) or not IsNumber(maximum) then return nil end
    return { level = level, xp = max(0,xp), maximum = max(0,maximum) }
end
local function ReadRestedXP()
    if type(GetXPExhaustion) ~= "function" then return 0 end
    local ok, value = pcall(GetXPExhaustion)
    if ok and IsNumber(value) then return max(0, value) end
    return 0
end
local function DrawSingleTrack(track, restTexture, questTexture, questMark, questHalo, width, height, xp, maximum, restedXP, questXP)
    local visual = Projection.Compute(xp, maximum, restedXP, questXP, width, db.restedOverlay, db.questOverlay)
    restTexture:ClearAllPoints()
    restTexture:SetPoint("LEFT",track,"LEFT",visual.restedStart,0)
    restTexture:SetSize(max(0.1,visual.restedWidth),height)
    restTexture:SetShown(visual.restedWidth > 0.5)
    questTexture:ClearAllPoints()
    questTexture:SetPoint("LEFT",track,"LEFT",visual.questStart,0)
    questTexture:SetSize(max(0.1,visual.questWidth),height)
    questTexture:SetShown(visual.questWidth > 0.5)
    for _, marker in ipairs({questMark,questHalo}) do
        marker:ClearAllPoints()
        marker:SetPoint("CENTER",track,"LEFT",visual.markerX,0)
        marker:SetShown(visual.showMarker)
    end
    return visual
end
local function Now() return time() end
local function Comma(value)
    local s = tostring(floor((tonumber(value) or 0) + 0.5))
    local sign = ""
    if s:sub(1,1) == "-" then sign, s = "-",s:sub(2) end
    return sign .. s:reverse():gsub("(%d%d%d)","%1,"):reverse():gsub("^,","")
end
local function Short(value)
    value = tonumber(value) or 0
    if value >= 1000000 then return format("%.2fm", value/1000000) end
    if value >= 100000 then return format("%.0fk", value/1000) end
    if value >= 10000 then return format("%.1fk", value/1000) end
    return Comma(value)
end
local function TimeLeft(seconds)
    if not seconds or seconds < 0 or seconds > 86400 * 90 then return "Gathering data" end
    if seconds < 60 then return "<1 min" end
    local m = ceil(seconds/60)
    if m < 60 then return m .. " min" end
    local hours = floor(m/60)
    if hours < 48 then return format("%dh %02dm",hours,m%60) end
    return format("%dd %dh",floor(hours/24),hours%24)
end
local function Label(parent,text,size,color,width)
    local t = parent:CreateFontString(nil,"OVERLAY")
    t:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",size or 12,"OUTLINE")
    t:SetTextColor((color or {1,1,1})[1],(color or {1,1,1})[2],(color or {1,1,1})[3])
    t:SetJustifyH("LEFT")
    t:SetJustifyV("MIDDLE")
    if width then t:SetWidth(width) end
    if t.SetMaxLines then t:SetMaxLines(1) end
    if t.SetWordWrap then t:SetWordWrap(false) end
    if text then t:SetText(text) end
    return t
end
local function TextColor(t,c)
    t:SetTextColor(c[1],c[2],c[3],c[4] or 1)
end
local TEAL = {0.32,0.91,0.88}
local GOLD = {0.95,0.75,0.43}
local WHITE = {0.95,0.97,0.97}
local MUTED = {0.51,0.67,0.72}

local function PanelMode() return (db and (db.uiMode == "panel" or db.uiMode == "both")) end
local function BarMode() return (db and (db.uiMode == "bar" or db.uiMode == "both")) end
local function SetMode(mode)
    if mode ~= "panel" and mode ~= "bar" and mode ~= "both" then mode = "bar" end
    db.uiMode = mode
    ApplyTracker()
    if AX and AX.RefreshSettings then AX:RefreshSettings() end
    UpdateUI()
end

local function Button(parent,text,w,h,onclick)
    local b = CreateFrame("Button",nil,parent)
    b:SetSize(w,h)
    b:RegisterForClicks("LeftButtonUp")
    b.base = b:CreateTexture(nil,"BACKGROUND")
    b.base:SetAllPoints()
    b.base:SetColorTexture(0.10,0.19,0.26,0.98)
    b.edge = b:CreateTexture(nil,"BORDER")
    b.edge:SetPoint("TOPLEFT",0,0)
    b.edge:SetPoint("TOPRIGHT",0,0)
    b.edge:SetHeight(1)
    b.edge:SetColorTexture(0.23,0.53,0.55,0.83)
    b.label = Label(b,text,11,WHITE,w-10)
    b.label:SetPoint("CENTER",b,"CENTER",0,0)
    b.label:SetJustifyH("CENTER")
    b:SetScript("OnEnter",function(self)
        self.base:SetColorTexture(0.16,0.30,0.36,1)
    end)
    b:SetScript("OnLeave",function(self)
        if not self.selected then self.base:SetColorTexture(0.10,0.19,0.26,0.98) end
    end)
    b:SetScript("OnClick",onclick)
    return b
end
local function Selected(b,on)
    b.selected = on
    if on then
        b.base:SetColorTexture(0.14,0.37,0.42,1)
        b.edge:SetColorTexture(0.40,0.93,0.85,1)
        TextColor(b.label,TEAL)
    else
        b.base:SetColorTexture(0.10,0.19,0.26,0.98)
        b.edge:SetColorTexture(0.23,0.53,0.55,0.83)
        TextColor(b.label,WHITE)
    end
end
local function IconButton(parent,path,w,h,onclick)
    local b = CreateFrame("Button",nil,parent)
    b:SetSize(w,h)
    local t = b:CreateTexture(nil,"ARTWORK")
    t:SetTexture(PATH..path)
    t:SetAllPoints()
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square","ADD")
    b:SetScript("OnClick",onclick)
    return b
end

local function NewSession()
    ch.session = {
        started = Now(), xp = 0, kills = 0, killXP = 0,
        lastKill = 0, lastMob = "", samples = {}, recentKills = {}, recentKillRecords = {},
        questXP = 0, questCount = 0, money = Money.NewSession(),
    }
end
local function PruneSamples()
    local s = ch.session.samples
    local cutoff = Now()-1900 -- retains recent 30-minute rate + margin
    local first = 1
    while first <= #s and (not s[first].t or s[first].t < cutoff) do first = first + 1 end
    if first > 1 then
        local result = {}
        for i=first,#s do result[#result+1]=s[i] end
        ch.session.samples = result
    end
    -- hard cap on retained, extremely dense XP events
    while #ch.session.samples > 2200 do table.remove(ch.session.samples,1) end
end
local function RecordXP(delta)
    if not ch or not ch.session or delta <= 0 then return end
    local session = ch.session
    session.xp = (session.xp or 0) + delta
    session.samples[#session.samples+1] = {t=Now(),xp=delta}
    PruneSamples()
end
local function HandleXPChange()
    if not ch then return end
    local current = SafePlayerXP()
    if not current then return end
    if not snapshot then snapshot = current; return end
    local earned = 0
    if current.level == snapshot.level then
        if current.xp >= snapshot.xp then earned = current.xp-snapshot.xp
        else
            -- Level-up may be in flight: retain old snapshot until PLAYER_LEVEL_UP.
            return
        end
    elseif current.level > snapshot.level then
        if current.level == snapshot.level+1 then
            earned = max(0,snapshot.maximum-snapshot.xp)+current.xp
        else
            -- Only first old-level remainder and new-level XP are knowable.
            earned = max(0,snapshot.maximum-snapshot.xp)+current.xp
        end
    end
    snapshot = current
    if earned > 0 then RecordXP(earned) end
end
local function Rate()
    if not ch or not ch.session then return 0,false end
    local sess=ch.session
    local seconds = max(1,Now()-(sess.started or Now()))
    if db.rateWindow == 0 then
        if seconds < 35 then return 0,false end
        return (sess.xp or 0)*3600/seconds,true
    end
    local window = db.rateWindow*60
    local xp = 0
    local cutoff = Now()-window
    for _,sample in ipairs(sess.samples) do
        if sample.t >= cutoff then xp = xp+sample.xp end
    end
    if seconds < 35 then return 0,false end
    return xp*3600/max(35,min(seconds,window)),true
end
local function AverageKill()
    local kills = ch and ch.session and ch.session.recentKills or {}
    if not kills or #kills == 0 then return 0 end
    local sum = 0
    for _,value in ipairs(kills) do sum = sum+value end
    return sum/#kills
end
local function Readiness(id)
    if C_QuestLog and C_QuestLog.ReadyForTurnIn then
        local ok,ready = pcall(C_QuestLog.ReadyForTurnIn,id)
        if ok and ready then return true end
    end
    if C_QuestLog and C_QuestLog.IsComplete then
        local ok,complete = pcall(C_QuestLog.IsComplete,id)
        if ok and complete then return true end
    end
    return false
end
local function ScanQuests()
    local results = {items={},knownXP=0,unknown=0,count=0}
    if not C_QuestLog or not C_QuestLog.GetInfo or not C_QuestLog.GetNumQuestLogEntries then
        quests = results; return
    end
    local total = C_QuestLog.GetNumQuestLogEntries() or 0
    for i=1,total do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID and not info.isHidden then
            local id=info.questID
            if Readiness(id) then
                local amount = nil
                if type(GetQuestLogRewardXP) == "function" then
                    local ok,totalXP = pcall(GetQuestLogRewardXP,id)
                    if ok and IsNumber(totalXP) and totalXP > 0 then amount = totalXP end
                end
                results.count=results.count+1
                if amount then results.knownXP=results.knownXP+amount
                else results.unknown=results.unknown+1 end
                results.items[#results.items+1]={id=id,title=info.title or ("Quest #"..id), xp=amount}
            end
        end
    end
    table.sort(results.items,function(a,b)
        if (a.xp ~= nil) ~= (b.xp ~= nil) then return a.xp ~= nil end
        if a.xp and b.xp and a.xp ~= b.xp then return a.xp>b.xp end
        return a.title<b.title
    end)
    quests = results
end
local function ProjectedStatus(current)
    if not current or current.maximum <= 0 then return "MAX" end
    if quests.count == 0 then return "NONE" end
    if current.xp+quests.knownXP >= current.maximum then return "DING" end
    if quests.unknown > 0 then return "MAYBE" end
    return "NO DING"
end

local function LayoutTracker()
    if not tracker then return end
    local compact = db.compact
    local baseHeight = compact and 190 or 270
    tracker:SetSize(360,baseHeight + (db.showGold and 42 or 0))
    local art = compact and (db.showGold and "panel_compact_gold.tga" or "panel_compact.tga")
        or (db.showGold and "panel_full_gold.tga" or "panel_full.tga")
    tracker.art:SetTexture(PATH..art)
    if goldStrip then
        goldStrip:SetShown(db.showGold)
        goldStrip:ClearAllPoints()
        goldStrip:SetPoint("TOPLEFT",tracker,"TOPLEFT",17,-(baseHeight-41+4))
    end
    rows[1].labelA:SetShown(not compact)
    rows[1].labelB:SetShown(not compact)
    rows[1].valueA:SetShown(not compact)
    rows[1].valueB:SetShown(not compact)
    rows[2].labelA:SetShown(not compact)
    rows[2].labelB:SetShown(not compact)
    rows[2].valueA:SetShown(not compact)
    rows[2].valueB:SetShown(not compact)
    local offsets = compact and {102,102,102} or {107,147,187}
    for i,row in ipairs(rows) do
        local y=offsets[i]
        for _,field in ipairs({"labelA","labelB"}) do
            local font=row[field]; font:ClearAllPoints()
            font:SetPoint("TOPLEFT",tracker,"TOPLEFT",field=="labelA" and 19 or 189,-y)
        end
        for _,field in ipairs({"valueA","valueB"}) do
            local font=row[field]; font:ClearAllPoints()
            font:SetPoint("TOPLEFT",tracker,"TOPLEFT",field=="valueA" and 19 or 189,-(y+17))
        end
    end
    questFooter:ClearAllPoints()
    questFooter:SetPoint("BOTTOMLEFT",tracker,"BOTTOMLEFT",17,12)
    if btnCollapse then btnCollapse.icon:SetTexture(PATH..(compact and "chevron_down.tga" or "chevron.tga")) end
end
LayoutBarTracker = function()
    if not barTracker then return end
    barTracker:SetSize(700,58)
    if barBack then
        barBack:ClearAllPoints()
        barBack:SetPoint("TOPLEFT",barTracker,"TOPLEFT",92,-38)
        barBack:SetPoint("TOPRIGHT",barTracker,"TOPRIGHT",-73,-38)
        barBack:SetHeight(14)
    end
end
ApplyTracker = function()
    if tracker then
        tracker:SetScale(db.scale or 1)
        tracker:SetShown((db.showTracker) and PanelMode())
        LayoutTracker()
    end
    if barTracker then
        barTracker:SetScale(db.barScale or db.scale or 1)
        barTracker:SetShown((db.showTracker) and BarMode())
        LayoutBarTracker()
    end
    if minimapButton then minimapButton:SetShown(db.showMinimap) end
    -- Blizzard's bar is suppressed only while AscendXP's XP bar is active.
    if BlizzardBar then BlizzardBar.Apply(db.showTracker and db.hideBlizzardBar and BarMode()) end
end
UpdateUI = function()
    if not ch then return end
    local current = SafePlayerXP()
    if not current then return end
    local remaining = max(0,current.maximum-current.xp)
    local pct = current.maximum > 0 and min(100,current.xp/current.maximum*100) or 100
    local rate,ready = Rate()
    local enough = rate > 0 and ready
    local s=ch.session
    local avg=AverageKill()
    local atMax = current.maximum <= 0 or current.level >= MAX_LEVEL

    if tracker then
        levelFont:SetText("LV " .. current.level)
        percentFont:SetText(format("%.1f%%",pct))
        if current.maximum > 0 then
            xpFill:SetMinMaxValues(0,current.maximum)
            xpFill:SetValue(current.xp)
            xpFill:Show()
        else
            xpFill:SetMinMaxValues(0,1);xpFill:SetValue(1)
        end
        local progressWidth=324
        local fraction=current.maximum>0 and current.xp/current.maximum or 1
        local progress=progressWidth*min(1,max(0,fraction))
        DrawSingleTrack(barBackground, restedFill, questFill, panelQuestMark, panelQuestHalo,
            progressWidth, 12, current.xp, current.maximum, ReadRestedXP(), quests.knownXP)
        rows[1].valueA:SetText(atMax and "MAX LEVEL" or (Comma(current.xp) .. " / " .. Comma(current.maximum)))
        rows[1].valueB:SetText(atMax and "0 XP" or (Comma(remaining).. " XP"))
        rows[2].valueA:SetText(s.lastKill > 0 and ("+"..Comma(s.lastKill).." XP") or "No kill yet")
        rows[2].valueB:SetText(avg > 0 and (Comma(avg).." XP") or "No kills yet")
        rows[3].valueA:SetText(enough and (Short(rate).." XP/h") or "Calculating...")
        rows[3].valueB:SetText(atMax and "MAX LEVEL" or (enough and TimeLeft(remaining/rate*3600) or "Calculating..."))
        if db.showGold and goldStrip then
            local m=Money.Summary()
            local value,hasRate=Money.Rate(db.rateWindow)
            goldValue:SetText(hasRate and Money.Compact(value).."/h" or "Calculating...")
            goldLoot:SetText(Money.Compact(m.loot))
        end
        local xpLabel=quests.unknown>0 and (Short(quests.knownXP).."+ XP") or (Short(quests.knownXP).." XP")
        footerText:SetText(quests.count .. " ready  •  " .. xpLabel)
        local status=ProjectedStatus(current)
        footerBadge:SetText(status)
        if status=="DING" then TextColor(footerBadge,{0.61,0.97,0.69})
        elseif status=="MAYBE" then TextColor(footerBadge,GOLD)
        else TextColor(footerBadge,MUTED) end
    end

    if barTracker then
        if current.maximum > 0 then
            barXpFill:SetMinMaxValues(0,current.maximum)
            barXpFill:SetValue(current.xp)
        else
            barXpFill:SetMinMaxValues(0,1)
            barXpFill:SetValue(1)
        end
        local fraction=current.maximum>0 and current.xp/current.maximum or 1
        local progressWidth=barBack:GetWidth() > 0 and barBack:GetWidth() or 535
        local progress=progressWidth*min(1,max(0,fraction))
        DrawSingleTrack(barBack, barRestedFill, barQuestFill, barQuestMark, barQuestHalo,
            progressWidth, 14, current.xp, current.maximum, ReadRestedXP(), quests.knownXP)
        barLevelText:SetText("LV "..current.level)
        barCenterText:SetText(atMax and "MAX LEVEL" or (Comma(current.xp).." / "..Comma(current.maximum)))
        barPercentText:SetText(format("%.1f%%", pct))
        barRateText:SetText(enough and Short(rate) or "--")
        barTimeText:SetText(atMax and "MAX" or (enough and TimeLeft(remaining/rate*3600) or "--"))
        barKillText:SetText(avg > 0 and Short(avg) or "--")
        if quests.count > 0 then
            barQuestText:SetText(quests.count.."  +"..Short(quests.knownXP)..(quests.unknown>0 and "+" or ""))
            TextColor(barQuestText,ProjectedStatus(current)=="DING" and {0.61,0.97,0.69} or GOLD)
        else
            barQuestText:SetText("0 ready")
            TextColor(barQuestText,MUTED)
        end
        if db.showGold then
            local value,hasRate=Money.Rate(db.rateWindow)
            barGoldText:SetText(hasRate and Money.Compact(value) or "--")
            barGoldLabel:Show()
            barGoldText:Show()
            if goldHitButton then goldHitButton:Show() end
        else
            barGoldText:SetText("")
            barGoldLabel:Hide()
            barGoldText:Hide()
            if goldHitButton then goldHitButton:Hide() end
        end
        if barGlow then
            -- Glow is confined to the filled section; no outer panel/shadow.
            barGlow:ClearAllPoints()
            barGlow:SetPoint("TOPLEFT",barXpFill,"TOPLEFT",0,2)
            barGlow:SetSize(max(0.1, progress),18)
            barGlow:SetShown(progress > 0.5)
            barSpark:ClearAllPoints()
            barSpark:SetPoint("CENTER",barXpFill,"LEFT",progress,0)
            barSpark:SetAlpha(min(0.95,0.40 + pct/100))
            barSpark:SetShown(current.maximum > 0 and pct > 1 and pct < 99.9)
        end
    end

    if questFrame and questFrame:IsShown() and questFrame.Refresh then questFrame:Refresh() end
    if detailsFrame and detailsFrame:IsShown() and detailsFrame.Refresh then detailsFrame:Refresh() end
    if goldDetailsFrame and goldDetailsFrame:IsShown() and goldDetailsFrame.Refresh then goldDetailsFrame:Refresh() end
    if lootLedgerFrame and lootLedgerFrame:IsShown() and lootLedgerFrame.Refresh then lootLedgerFrame:Refresh() end
end

-- Reset stats without changing actual character XP, level, position or ready quests.
function AX:ResetSession()
    if not ch then return end
    NewSession()
    Money.Init(ch.session)
    snapshot = SafePlayerXP() -- establish a fresh baseline for the next XP gain
    UpdateUI()
    print(C_TEAL .. "AscendXP|r: XP, kill history, gold and loot session reset.")
end

-- A confirmation keeps an accidental tracker click from discarding session history.
StaticPopupDialogs["ASCENDXP_RESET_SESSION"] = {
    text = "Reset AscendXP session?\n\nClears XP, kills, earned coin, gold spent, loot values and hourly rates. Your real XP, gold, bags, level and quests are not changed.",
    button1 = "Reset session",
    button2 = "Cancel",
    OnAccept = function() AX:ResetSession() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function TooltipSummary(owner)
    local current=SafePlayerXP()
    if not current then return end
    local rate,ready=Rate()
    local need=max(0,current.maximum-current.xp)
    GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
    GameTooltip:AddLine("AscendXP",0.30,0.92,0.88)
    GameTooltip:AddDoubleLine("Progress",Comma(current.xp).." / "..Comma(current.maximum),1,1,1,1,1,1)
    GameTooltip:AddDoubleLine("To next level",Comma(need).." XP",0.8,0.85,0.9,1,1,1)
    local rested = ReadRestedXP()
    local restedPct = current.maximum > 0 and (rested / current.maximum * 100) or 0
    GameTooltip:AddDoubleLine("Rested bonus",Comma(rested).." XP  ("..format("%.1f%%",restedPct).." of level)",0.53,0.75,1,0.68,0.83,1)
    GameTooltip:AddDoubleLine("Quest turn-ins",Comma(quests.knownXP)..(quests.unknown>0 and "+" or "").." XP",0.95,0.75,0.43,1,0.88,0.65)
    GameTooltip:AddDoubleLine("Current rate",ready and (Comma(rate).." XP/hour") or "Collecting XP",0.8,0.85,0.9,0.6,0.95,0.85)
    GameTooltip:AddDoubleLine("Time to level",(ready and rate>0) and TimeLeft(need/rate*3600) or "—",0.8,0.85,0.9,1,1,1)
    GameTooltip:AddDoubleLine("Last mob",(ch.session.lastMob ~= "" and ch.session.lastMob or "No kill") .. "  +"..Comma(ch.session.lastKill),0.8,0.85,0.9,1,1,1)
    GameTooltip:AddDoubleLine("Session XP",Comma(ch.session.xp or 0),0.8,0.85,0.9,1,1,1)
    if db.showGold then
        local m=Money.Summary()
        local moneyRate,moneyReady=Money.Rate(db.rateWindow)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("GOLD AND LOOT",0.96,0.77,0.43)
        GameTooltip:AddDoubleLine("Estimated gold/hour",moneyReady and (Money.Format(moneyRate).." /h") or "Collecting data",0.8,0.85,0.9,1,1,1)
        GameTooltip:AddDoubleLine("Actual gold earned",Money.Format(m.cash),0.8,0.85,0.9,1,1,1)
        GameTooltip:AddDoubleLine("Gold spent",Money.Format(m.spent),0.8,0.85,0.9,1,0.67,0.59)
        GameTooltip:AddDoubleLine("Loot value",Money.Format(m.loot),0.8,0.85,0.9,1,1,1)
        GameTooltip:AddDoubleLine("Net value",Money.Format(m.net),0.8,0.85,0.9,1,1,1)
    end
    GameTooltip:AddDoubleLine("Ready quests",quests.count.." quests / "..Comma(quests.knownXP)..(quests.unknown>0 and "+" or "").." XP",0.8,0.85,0.9,1,0.85,0.45)
    if quests.unknown>0 then GameTooltip:AddLine(quests.unknown.." reward(s) unavailable from game API; no XP guessed.",0.97,0.74,0.48,true) end
    if current.maximum>0 and current.xp+quests.knownXP>=current.maximum then
        GameTooltip:AddLine("Ready turn-ins GUARANTEE the next level!",0.52,0.97,0.67)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Drag to move • Left-click details • Right-click quests",0.60,0.75,0.83)
    GameTooltip:Show()
end

local function MakeTracker()
    tracker=CreateFrame("Frame","AscendXPTracker",UIParent)
    tracker:SetSize(360,270)
    tracker:SetPoint("CENTER",UIParent,"CENTER",db.x or 0,db.y or 170)
    tracker:SetClampedToScreen(true)
    tracker:SetMovable(true)
    tracker:EnableMouse(true)
    tracker:RegisterForDrag("LeftButton")
    tracker:SetFrameStrata("MEDIUM")
    tracker:SetScript("OnDragStart",function(self) if not db.locked then self:StartMoving() end end)
    tracker:SetScript("OnDragStop",function(self)
        self:StopMovingOrSizing()
        local cx,cy=self:GetCenter()
        local ux,uy=UIParent:GetCenter()
        if cx and cy and ux and uy then db.x=cx-ux; db.y=cy-uy end
    end)
    tracker:SetScript("OnEnter",function(self) TooltipSummary(self) end)
    tracker:SetScript("OnLeave",function() GameTooltip:Hide() end)
    tracker:SetScript("OnMouseUp",function(self,button) if button=="RightButton" then AX:ToggleDetails() end end)
    tracker.art=tracker:CreateTexture(nil,"BACKGROUND")
    tracker.art:SetAllPoints();tracker.art:SetTexture(PATH.."panel_full.tga")
    logo=tracker:CreateTexture(nil,"ARTWORK")
    logo:SetTexture(PATH.."crest.tga")
    logo:SetSize(40,40);logo:SetPoint("TOPLEFT",tracker,"TOPLEFT",13,-9)
    local crestClick=CreateFrame("Button",nil,tracker)
    crestClick:SetSize(40,40);crestClick:SetPoint("TOPLEFT",tracker,"TOPLEFT",13,-9)
    crestClick:SetScript("OnClick",function() AX:ToggleDetails() end)
    crestClick:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self,"ANCHOR_TOP");GameTooltip:SetText("View XP & mob kill history");GameTooltip:Show() end)
    crestClick:SetScript("OnLeave",function() GameTooltip:Hide() end)
    local name=Label(tracker,"ASCEND",16,TEAL,132)
    name:SetPoint("TOPLEFT",54,-13)
    local sub=Label(tracker,"XP INTELLIGENCE",8,GOLD,154)
    sub:SetPoint("TOPLEFT",55,-34)
    levelFont=Label(tracker,"LV 1",11,GOLD,55)
    levelFont:SetJustifyH("RIGHT")
    levelFont:SetPoint("TOPRIGHT",tracker,"TOPRIGHT",-92,-18)
    -- Header layout (360px): level ends x268, reset x272-291, settings x296-318.
    -- The small icon remains present in both full and compact modes.
    local resetButton=IconButton(tracker,"reset.tga",19,19,function()
        StaticPopup_Show("ASCENDXP_RESET_SESSION")
    end)
    resetButton:SetPoint("TOPRIGHT",tracker,"TOPRIGHT",-69,-17)
    resetButton:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:SetText("Reset XP + gold session",0.95,0.75,0.43)
        GameTooltip:AddLine("Clears XP, kills, loot, coin and hourly rates.",0.83,0.92,0.95)
        GameTooltip:AddLine("Your actual XP, gold, bags and quests are safe.",0.55,0.73,0.78)
        GameTooltip:Show()
    end)
    resetButton:SetScript("OnLeave",function() GameTooltip:Hide() end)
    local gear=IconButton(tracker,"gear.tga",22,22,function() AX:ToggleSettings() end)
    gear:SetPoint("TOPRIGHT",tracker,"TOPRIGHT",-42,-16)
    gear:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self,"ANCHOR_TOP");GameTooltip:SetText("AscendXP settings");GameTooltip:Show() end)
    gear:SetScript("OnLeave",function() GameTooltip:Hide() end)
    btnCollapse=CreateFrame("Button",nil,tracker)
    btnCollapse:SetSize(22,22)
    btnCollapse:SetPoint("TOPRIGHT",tracker,"TOPRIGHT",-13,-16)
    btnCollapse.icon=btnCollapse:CreateTexture(nil,"ARTWORK")
    btnCollapse.icon:SetAllPoints()
    btnCollapse.icon:SetTexture(PATH.."chevron.tga")
    btnCollapse:SetScript("OnClick",function() db.compact=not db.compact;ApplyTracker();AX:RefreshSettings() end)
    local prog=Label(tracker,"LEVEL PROGRESS",9,MUTED,180)
    prog:SetPoint("TOPLEFT",tracker,"TOPLEFT",19,-57)
    percentFont=Label(tracker,"0.0%",10,TEAL,86)
    percentFont:SetJustifyH("RIGHT")
    percentFont:SetPoint("TOPRIGHT",tracker,"TOPRIGHT",-19,-55)
    barBackground=tracker:CreateTexture(nil,"BORDER")
    barBackground:SetTexture(PATH.."bar_track.tga")
    barBackground:SetSize(324,12)
    barBackground:SetPoint("TOPLEFT",tracker,"TOPLEFT",18,-77)
    restedFill=tracker:CreateTexture(nil,"ARTWORK",nil,1)
    restedFill:SetTexture(PATH.."bar_rested.tga")
    questFill=tracker:CreateTexture(nil,"ARTWORK",nil,2)
    questFill:SetTexture(PATH.."bar_quest.tga")
    xpFill=CreateFrame("StatusBar",nil,tracker)
    xpFill:SetSize(324,12)
    xpFill:SetPoint("CENTER",barBackground,"CENTER",0,0)
    xpFill:SetStatusBarTexture(PATH.."bar_xp.tga")
    xpFill:SetFrameLevel(tracker:GetFrameLevel()+2)
    -- One shared track; blue rested has priority, and gold quest XP gets a
    -- slim endpoint marker even when it is covered by the rested projection.
    local panelOverlay=CreateFrame("Frame",nil,tracker)
    panelOverlay:SetAllPoints(tracker)
    panelOverlay:SetFrameLevel(xpFill:GetFrameLevel()+1)
    panelOverlay:EnableMouse(false)
    panelQuestHalo=panelOverlay:CreateTexture(nil,"OVERLAY",nil,1)
    panelQuestHalo:SetColorTexture(0.98,0.70,0.23,0.25)
    panelQuestHalo:SetSize(6,17)
    panelQuestMark=panelOverlay:CreateTexture(nil,"OVERLAY",nil,3)
    panelQuestMark:SetColorTexture(1.0,0.83,0.39,0.97)
    panelQuestMark:SetSize(2,14)
    local titles={{"CURRENT XP","TO LEVEL"},{"LAST MOB","AVG / KILL"},{"XP / HOUR","TIME TO LEVEL"}}
    for i=1,3 do
        local row={}
        row.labelA=Label(tracker,titles[i][1],9,MUTED,154)
        row.labelB=Label(tracker,titles[i][2],9,MUTED,153)
        row.valueA=Label(tracker,"—",i==1 and 12 or 14,WHITE,162)
        row.valueB=Label(tracker,"—",14,(i==3 and GOLD or WHITE),153)
        rows[i]=row
    end
    questFooter=CreateFrame("Button",nil,tracker)
    questFooter:SetSize(326,29)
    questFooter:RegisterForClicks("LeftButtonUp")
    local fbg=questFooter:CreateTexture(nil,"BACKGROUND")
    fbg:SetAllPoints();fbg:SetColorTexture(0.15,0.29,0.31,0.91)
    local line=questFooter:CreateTexture(nil,"ARTWORK")
    line:SetPoint("TOPLEFT",1,0);line:SetPoint("TOPRIGHT",-1,0);line:SetHeight(1)
    line:SetColorTexture(0.46,0.76,0.69,0.9)
    local qIcon=questFooter:CreateTexture(nil,"ARTWORK")
    qIcon:SetTexture(PATH.."crest.tga")
    qIcon:SetSize(20,20)
    qIcon:SetPoint("LEFT",questFooter,"LEFT",6,0)
    footerText=Label(questFooter,"0 ready  •  0 XP",11,WHITE,214)
    footerText:SetPoint("LEFT",questFooter,"LEFT",27,0)
    footerBadge=Label(questFooter,"NONE",10,GOLD,76)
    footerBadge:SetJustifyH("RIGHT")
    footerBadge:SetPoint("RIGHT",questFooter,"RIGHT",-12,0)
    questFooter:SetScript("OnClick",function() AX:ToggleQuests() end)
    questFooter:SetScript("OnEnter",function(self)
        fbg:SetColorTexture(0.20,0.42,0.42,0.94)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine("Ready quest turn-ins",0.4,0.9,0.86)
        GameTooltip:AddLine("Click to view completed quests and their XP.",1,1,1)
        GameTooltip:Show()
    end)
    questFooter:SetScript("OnLeave",function() fbg:SetColorTexture(0.15,0.29,0.31,0.91);GameTooltip:Hide() end)

    -- One 34px gold strip, placed between XP metrics and quest turn-ins.
    goldStrip=CreateFrame("Button",nil,tracker)
    goldStrip:SetSize(326,34)
    goldStrip:RegisterForClicks("LeftButtonUp","RightButtonUp")
    local goldArt=goldStrip:CreateTexture(nil,"BACKGROUND")
    goldArt:SetAllPoints();goldArt:SetTexture(PATH.."gold_strip.tga")
    local coin=goldStrip:CreateTexture(nil,"ARTWORK")
    coin:SetTexture(PATH.."gold_coin.tga")
    coin:SetSize(27,27);coin:SetPoint("LEFT",goldStrip,"LEFT",6,0)
    local l=Label(goldStrip,"GOLD / H",9,GOLD,143)
    l:SetPoint("TOPLEFT",goldStrip,"TOPLEFT",40,-3)
    goldValue=Label(goldStrip,"Calculating...",12,WHITE,145)
    goldValue:SetPoint("TOPLEFT",goldStrip,"TOPLEFT",40,-15)
    local r=Label(goldStrip,"LOOT VALUE",9,MUTED,117)
    r:SetJustifyH("RIGHT");r:SetPoint("TOPRIGHT",goldStrip,"TOPRIGHT",-12,-3)
    goldLoot=Label(goldStrip,"0c",12,WHITE,117)
    goldLoot:SetJustifyH("RIGHT");goldLoot:SetPoint("TOPRIGHT",goldStrip,"TOPRIGHT",-12,-15)
    goldStrip:SetScript("OnClick",function(_,button)
        if button=="RightButton" then AX:ToggleLootLedger()
        else AX:ToggleGold() end
    end)
    goldStrip:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine("AscendXP gold and loot",0.97,0.77,0.45)
        local m=Money.Summary()
        local rate,ready,cashHour,lootHour=Money.Rate(db.rateWindow)
        GameTooltip:AddDoubleLine("Estimated NET / hour",ready and Money.Format(rate).." /h" or "Calculating",1,1,1,1,1,1)
        if ready then
            GameTooltip:AddDoubleLine("  Coin per hour",Money.Format(cashHour).." /h",0.7,0.85,0.9,1,1,1)
            GameTooltip:AddDoubleLine("  Loot per hour (est.)",Money.Format(lootHour).." /h",0.7,0.85,0.9,1,1,1)
        end
        GameTooltip:AddDoubleLine("Earned coin",Money.Format(m.cash),0.7,0.85,0.9,1,1,1)
        GameTooltip:AddDoubleLine("Gold spent",Money.Format(m.spent),0.85,0.65,0.62,1,0.72,0.60)
        GameTooltip:AddDoubleLine("Loot value",Money.Format(m.loot),0.7,0.85,0.9,1,1,1)
        GameTooltip:AddDoubleLine("Est. net value",Money.Format(m.net),0.7,0.85,0.9,1,1,1)
        if m.missing>0 then GameTooltip:AddDoubleLine("Unpriced items", tostring(m.missing),1,0.70,0.43,1,1,1) end
        GameTooltip:AddLine("Left-click: gold summary  |  Right-click: loot ledger",0.30,0.92,0.88)
        GameTooltip:Show()
    end)
    goldStrip:SetScript("OnLeave",function() GameTooltip:Hide() end)
    ApplyTracker()
end

local function MakeBarTracker()
    barTracker=CreateFrame("Frame","AscendXPBarTracker",UIParent)
    barTracker:SetSize(700,58)
    if db.barAnchor == "CENTER" then
        barTracker:SetPoint("CENTER",UIParent,"CENTER",db.barX or 0,db.barY or 0)
    else
        barTracker:SetPoint("TOP",UIParent,"TOP",db.barX or 0,db.barY or -14)
    end
    barTracker:SetClampedToScreen(true)
    barTracker:SetMovable(true)
    barTracker:EnableMouse(true)
    barTracker:RegisterForDrag("LeftButton")
    barTracker:SetFrameStrata("MEDIUM")
    barTracker:SetScript("OnDragStart",function(self) if not db.locked then self:StartMoving() end end)
    barTracker:SetScript("OnDragStop",function(self)
        self:StopMovingOrSizing()
        local cx,cy=self:GetCenter()
        local ux,uy=UIParent:GetCenter()
        if cx and cy and ux and uy then
            -- Use a CENTER anchor after dragging so the saved position remains
            -- stable across /reload instead of mixing TOP and CENTER offsets.
            db.barX=cx-ux
            db.barY=cy-uy
            db.barAnchor="CENTER"
            self:ClearAllPoints()
            self:SetPoint("CENTER",UIParent,"CENTER",db.barX,db.barY)
        end
    end)
    -- Floating text and a single colored progress track: no background box.

    local crest=barTracker:CreateTexture(nil,"ARTWORK")
    crest:SetTexture(PATH.."crest.tga")
    crest:SetSize(30,30)
    crest:SetPoint("LEFT",barTracker,"LEFT",10,0)
    local crestButton=CreateFrame("Button",nil,barTracker)
    crestButton:SetAllPoints(crest)
    crestButton:SetScript("OnClick",function() AX:ToggleDetails() end)
    crestButton:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self,"ANCHOR_BOTTOMLEFT"); GameTooltip:SetText("AscendXP details"); GameTooltip:Show() end)
    crestButton:SetScript("OnLeave",function() GameTooltip:Hide() end)

    barLevelText=Label(barTracker,"LV 1",10,GOLD,44)
    barLevelText:SetPoint("LEFT",crest,"RIGHT",7,0)

    -- Five fixed-width fields: labels above readable values, no collisions at
    -- different scales or when XP and gold values grow during a session.
    local function Metric(x, width, title, color)
        local tag=Label(barTracker,title,8,MUTED,width)
        tag:SetPoint("TOPLEFT",barTracker,"TOPLEFT",x,-3)
        local value=Label(barTracker,"--",11,color or WHITE,width)
        value:SetPoint("TOPLEFT",barTracker,"TOPLEFT",x,-17)
        return tag,value
    end
    barRateLabel,barRateText=Metric(94,94,"XP / HOUR",TEAL)
    barTimeLabel,barTimeText=Metric(194,94,"TO LEVEL",WHITE)
    barKillLabel,barKillText=Metric(294,94,"XP / KILL",WHITE)
    barQuestLabel,barQuestText=Metric(394,116,"READY QUESTS",GOLD)
    barGoldLabel,barGoldText=Metric(516,108,"GOLD / HOUR",GOLD)
    goldHitButton=CreateFrame("Button",nil,barTracker)
    goldHitButton:SetSize(112,35)
    goldHitButton:SetPoint("TOPLEFT",barTracker,"TOPLEFT",512,-1)
    goldHitButton:RegisterForClicks("LeftButtonUp","RightButtonUp")
    goldHitButton:SetScript("OnClick",function(_,button)
        if button=="RightButton" then AX:ToggleLootLedger()
        else AX:ToggleGold() end
    end)
    goldHitButton:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine("GOLD / HOUR",0.95,0.75,0.43)
        GameTooltip:AddLine("Left-click: summary",0.92,0.94,0.97)
        GameTooltip:AddLine("Right-click: individual loot pickups",0.30,0.92,0.88)
        GameTooltip:Show()
    end)
    goldHitButton:SetScript("OnLeave",function() GameTooltip:Hide() end)
    if goldHitButton.SetPropagateMouseClicks then goldHitButton:SetPropagateMouseClicks(false) end

    barBack=barTracker:CreateTexture(nil,"BORDER")
    barBack:SetTexture(PATH.."bar_track.tga")
    barBack:SetHeight(14)
    barBack:SetPoint("TOPLEFT",barTracker,"TOPLEFT",92,-38)
    barBack:SetPoint("TOPRIGHT",barTracker,"TOPRIGHT",-73,-38)

    barRestedFill=barTracker:CreateTexture(nil,"ARTWORK",nil,1)
    barRestedFill:SetTexture(PATH.."bar_rested.tga")
    barQuestFill=barTracker:CreateTexture(nil,"ARTWORK",nil,2)
    barQuestFill:SetTexture(PATH.."bar_quest.tga")
    barXpFill=CreateFrame("StatusBar",nil,barTracker)
    barXpFill:SetPoint("TOPLEFT",barTracker,"TOPLEFT",92,-38)
    barXpFill:SetPoint("TOPRIGHT",barTracker,"TOPRIGHT",-73,-38)
    barXpFill:SetHeight(14)
    barXpFill:SetStatusBarTexture(PATH.."bar_xp.tga")
    barXpFill:SetFrameLevel(barTracker:GetFrameLevel()+2)
    -- Keep the bar's numbers and glow above the StatusBar fill.
    local barOverlay=CreateFrame("Frame",nil,barTracker)
    barOverlay:SetAllPoints(barTracker)
    barOverlay:SetFrameLevel(barXpFill:GetFrameLevel()+1)
    barOverlay:EnableMouse(false)
    barGlow=barOverlay:CreateTexture(nil,"OVERLAY")
    barGlow:SetTexture(PATH.."bar_xp.tga")
    barGlow:SetBlendMode("ADD")
    barGlow:SetPoint("TOPLEFT",barXpFill,"TOPLEFT",0,2)
    barGlow:SetSize(1,18)
    barGlow:SetVertexColor(0.34,0.96,0.92,1)
    barSpark=barOverlay:CreateTexture(nil,"OVERLAY")
    barSpark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    barSpark:SetBlendMode("ADD")
    barSpark:SetSize(18,28)
    barSpark:SetPoint("CENTER",barXpFill:GetStatusBarTexture(),"RIGHT",0,0)
    barQuestHalo=barOverlay:CreateTexture(nil,"OVERLAY",nil,1)
    barQuestHalo:SetColorTexture(0.98,0.70,0.23,0.23)
    barQuestHalo:SetSize(6,19)
    barQuestMark=barOverlay:CreateTexture(nil,"OVERLAY",nil,3)
    barQuestMark:SetColorTexture(1.0,0.83,0.39,0.98)
    barQuestMark:SetSize(2,16)

    barCenterText=Label(barOverlay,"0 / 0",11,WHITE,340)
    barCenterText:SetJustifyH("CENTER")
    barCenterText:SetPoint("CENTER",barBack,"CENTER",0,0)
    barPercentText=Label(barOverlay,"0.0%",10,TEAL,56)
    barPercentText:SetJustifyH("RIGHT")
    barPercentText:SetPoint("RIGHT",barBack,"RIGHT",-6,0)
    -- Keep the gold quest endpoint visible, but never paint over XP text.
    if barCenterText.SetDrawLayer then barCenterText:SetDrawLayer("OVERLAY",7) end
    if barPercentText.SetDrawLayer then barPercentText:SetDrawLayer("OVERLAY",7) end

    local resetButton=IconButton(barTracker,"reset.tga",16,16,function() StaticPopup_Show("ASCENDXP_RESET_SESSION") end)
    resetButton:SetPoint("RIGHT",barTracker,"RIGHT",-33,0)
    resetButton:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self,"ANCHOR_BOTTOMRIGHT"); GameTooltip:SetText("Reset session",0.95,0.75,0.43); GameTooltip:Show() end)
    resetButton:SetScript("OnLeave",function() GameTooltip:Hide() end)
    local gear=IconButton(barTracker,"gear.tga",18,18,function() AX:ToggleSettings() end)
    gear:SetPoint("RIGHT",barTracker,"RIGHT",-12,0)
    gear:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self,"ANCHOR_BOTTOMRIGHT"); GameTooltip:SetText("AscendXP settings"); GameTooltip:Show() end)
    gear:SetScript("OnLeave",function() GameTooltip:Hide() end)

    local glowElapsed=0
    barTracker:SetScript("OnUpdate",function(self,elapsed)
        glowElapsed=glowElapsed+elapsed
        if glowElapsed < .06 then return end
        glowElapsed=0
        if barGlow and barGlow:IsShown() then
            barGlow:SetAlpha(0.17+0.11*(1+math.sin(GetTime()*2.5))/2)
        end
    end)
    barTracker:SetScript("OnEnter",function(self) TooltipSummary(self) end)
    barTracker:SetScript("OnLeave",function() GameTooltip:Hide() end)
    barTracker:SetScript("OnMouseUp",function(_,button)
        if button=="RightButton" then AX:ToggleQuests() else AX:ToggleDetails() end
    end)
    LayoutBarTracker()
end

local function MakePopup(id,title,subtitle,width,height)
    local p=CreateFrame("Frame",id,UIParent)
    p:SetSize(width,height)
    p:SetPoint("CENTER",UIParent,"CENTER",0,30)
    p:SetClampedToScreen(true)
    p:SetMovable(true);p:EnableMouse(true);p:RegisterForDrag("LeftButton")
    p:SetFrameStrata("DIALOG")
    p:SetFrameLevel(200)
    p:SetScript("OnDragStart",function(self) self:StartMoving() end)
    p:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)
    local bg=p:CreateTexture(nil,"BACKGROUND")
    bg:SetAllPoints();bg:SetTexture(PATH.."panel_popup.tga")
    local emblem=p:CreateTexture(nil,"ARTWORK")
    emblem:SetTexture(PATH.."crest.tga")
    emblem:SetSize(43,43);emblem:SetPoint("TOPLEFT",p,"TOPLEFT",16,-12)
    -- One header layout for every window, irrespective of popup height.
    local head=Label(p,title,18,TEAL,width-112)
    head:SetPoint("TOPLEFT",p,"TOPLEFT",64,-17)
    local sub=Label(p,subtitle,10,GOLD,width-112)
    sub:SetPoint("TOPLEFT",p,"TOPLEFT",65,-43)
    local separator=p:CreateTexture(nil,"ARTWORK")
    separator:SetPoint("TOPLEFT",p,"TOPLEFT",20,-64)
    separator:SetPoint("TOPRIGHT",p,"TOPRIGHT",-20,-64)
    separator:SetHeight(1)
    separator:SetColorTexture(0.16,0.79,0.77,0.76)
    local x=Button(p,"X",27,27,function() p:Hide() end)
    x:SetPoint("TOPRIGHT",p,"TOPRIGHT",-18,-19)
    if UISpecialFrames then table.insert(UISpecialFrames,id) end
    p:Hide()
    return p
end

function AX:RefreshSettings()
    if settingsFrame and settingsFrame.Refresh then settingsFrame:Refresh() end
end
local function MakeSettings()
    local p=MakePopup("AscendXPSettingsFrame","ASCENDXP  /  SETTINGS","Display and tracking options",480,750)
    settingsFrame=p
    local section=Label(p,"DISPLAY",10,GOLD,160)
    section:SetPoint("TOPLEFT",p,"TOPLEFT",26,-78)
    local toggles={}
    local config={
        {"Show tracker","Keep AscendXP visible.","showTracker"},
        {"Lock position","Prevent accidental dragging of the tracker.","locked"},
        {"Compact panel","Hide some panel stats in box mode.","compact"},
        {"Quest overlay","Gold tail and marker on the XP bar.","questOverlay"},
        {"Rested overlay","Blue rested XP takes priority over quest XP.","restedOverlay"},
        {"Minimap button","Show the movable crest on the minimap.","showMinimap"},
        {"Gold tracking","Show gold / hour data on the tracker.","showGold"},
        {"Hide Blizzard XP bar","Use AscendXP instead of the default XP strip.","hideBlizzardBar"},
    }
    for i,configRow in ipairs(config) do
        local y=103+(i-1)*38
        local txt=Label(p,configRow[1],12,WHITE,314)
        txt:SetPoint("TOPLEFT",p,"TOPLEFT",27,-y)
        local hint=Label(p,configRow[2],10,MUTED,335)
        hint:SetPoint("TOPLEFT",p,"TOPLEFT",27,-(y+18))
        local key=configRow[3]
        local b=Button(p,"ON",66,25,function()
            db[key]=not db[key]
            ApplyTracker()
            AX:RefreshSettings()
            UpdateUI()
        end)
        b:SetPoint("TOPRIGHT",p,"TOPRIGHT",-27,-(y+5))
        toggles[key]=b
    end

    local modeHead=Label(p,"DISPLAY MODE",10,GOLD,220)
    modeHead:SetPoint("TOPLEFT",p,"TOPLEFT",27,-411)
    local modeButtons={}
    for i,entry in ipairs({{"panel","PANEL"},{"bar","BAR"},{"both","BOTH"}}) do
        local mode,label=entry[1],entry[2]
        local b=Button(p,label,134,30,function() SetMode(mode) end)
        b:SetPoint("TOPLEFT",p,"TOPLEFT",27+(i-1)*146,-437)
        modeButtons[#modeButtons+1]={button=b,value=mode}
    end

    local pace=Label(p,"XP / HOUR CALCULATION",10,GOLD,300)
    pace:SetPoint("TOPLEFT",p,"TOPLEFT",27,-484)
    local helper=Label(p,"Recent pace includes idle time. Session starts when you log in.",10,MUTED,426)
    helper:SetPoint("TOPLEFT",p,"TOPLEFT",27,-503)
    local rateButtons={}
    for i,entry in ipairs({{5,"5 MIN"},{15,"15 MIN"},{30,"30 MIN"},{0,"SESSION"}}) do
        local duration,caption=entry[1],entry[2]
        local b=Button(p,caption,99,30,function()
            db.rateWindow=duration
            UpdateUI();AX:RefreshSettings()
        end)
        b:SetPoint("TOPLEFT",p,"TOPLEFT",27+(i-1)*109,-528)
        rateButtons[i]={button=b,value=duration}
    end

    local size=Label(p,"TRACKER SIZE",10,GOLD,260)
    size:SetPoint("TOPLEFT",p,"TOPLEFT",27,-580)
    local smaller=Button(p,"-",36,29,function() 
        if BarMode() and not PanelMode() then db.barScale=max(.70,floor(((db.barScale or 1)-.05)*100+.5)/100)
        else db.scale=max(.70,floor(((db.scale or 1)-.05)*100+.5)/100) end
        ApplyTracker();AX:RefreshSettings() 
    end)
    smaller:SetPoint("TOPLEFT",p,"TOPLEFT",288,-575)
    local scaleLabel=Label(p,"100%",13,WHITE,68)
    scaleLabel:SetJustifyH("CENTER");scaleLabel:SetPoint("TOPLEFT",p,"TOPLEFT",328,-582)
    local bigger=Button(p,"+",36,29,function() 
        if BarMode() and not PanelMode() then db.barScale=min(1.50,floor(((db.barScale or 1)+.05)*100+.5)/100)
        else db.scale=min(1.50,floor(((db.scale or 1)+.05)*100+.5)/100) end
        ApplyTracker();AX:RefreshSettings() 
    end)
    bigger:SetPoint("TOPRIGHT",p,"TOPRIGHT",-27,-575)

    local centerPanel=Button(p,"CENTER PANEL",136,32,function()
        db.x=0;db.y=150
        if tracker then tracker:ClearAllPoints();tracker:SetPoint("CENTER",UIParent,"CENTER",db.x,db.y) end
    end)
    centerPanel:SetPoint("TOPLEFT",p,"TOPLEFT",27,-624)
    local centerBar=Button(p,"CENTER BAR",136,32,function()
        db.barX=0;db.barY=-14;db.barAnchor="TOP"
        if barTracker then barTracker:ClearAllPoints();barTracker:SetPoint("TOP",UIParent,"TOP",db.barX,db.barY) end
    end)
    centerBar:SetPoint("TOPLEFT",p,"TOPLEFT",172,-624)
    local reset=Button(p,"RESET SESSION",145,32,function()
        StaticPopup_Show("ASCENDXP_RESET_SESSION")
    end)
    reset:SetPoint("TOPRIGHT",p,"TOPRIGHT",-27,-624)

    local tip=Label(p,"Tip: /axp bar • /axp panel • /axp both • /axp gold • /axp reset",10,MUTED,415)
    tip:SetPoint("BOTTOMLEFT",p,"BOTTOMLEFT",27,19)
    function p:Refresh()
        for key,b in pairs(toggles) do
            local enabled=db[key]
            b.label:SetText(enabled and "ON" or "OFF")
            Selected(b,enabled)
        end
        for _,item in ipairs(modeButtons) do Selected(item.button,db.uiMode==item.value) end
        for _,item in ipairs(rateButtons) do Selected(item.button,db.rateWindow==item.value) end
        local activeScale = (BarMode() and not PanelMode()) and (db.barScale or 1) or (db.scale or 1)
        scaleLabel:SetText(floor(activeScale*100+.5).."%")
    end
    p:Refresh()
end

local function MakeQuests()
    local p=MakePopup("AscendXPQuestFrame","ASCENDXP  /  READY QUESTS","Completed quests and turn-in XP",490,445)
    questFrame=p
    local total=Label(p,"0 QUESTS READY",12,GOLD,320)
    total:SetPoint("TOPLEFT",p,"TOPLEFT",27,-88)
    local summary=Label(p,"No quests ready.",11,WHITE,420)
    summary:SetPoint("TOPLEFT",p,"TOPLEFT",27,-110)
    local line=p:CreateTexture(nil,"ARTWORK")
    line:SetPoint("TOPLEFT",p,"TOPLEFT",27,-139)
    line:SetSize(435,1)
    line:SetColorTexture(0.34,0.60,0.58,0.6)
    for i=1,8 do
        local y=155+(i-1)*29
        local row={}
        row.text=Label(p,"",11,WHITE,319)
        row.text:SetPoint("TOPLEFT",p,"TOPLEFT",30,-y)
        row.xp=Label(p,"",11,GOLD,108)
        row.xp:SetJustifyH("RIGHT")
        row.xp:SetPoint("TOPRIGHT",p,"TOPRIGHT",-30,-y)
        row.hit=CreateFrame("Frame",nil,p)
        row.hit:SetSize(431,27)
        row.hit:SetPoint("TOPLEFT",p,"TOPLEFT",27,-(y-4))
        row.hit:EnableMouse(true)
        row.hit:SetScript("OnEnter",function(self)
            if row.title then
                GameTooltip:SetOwner(self,"ANCHOR_CURSOR")
                GameTooltip:AddLine(row.title,1,1,1)
                GameTooltip:AddLine(row.value and (Comma(row.value).." quest XP") or "XP reward unavailable",0.95,0.8,0.55)
                GameTooltip:Show()
            end
        end)
        row.hit:SetScript("OnLeave",function() GameTooltip:Hide() end)
        questRows[i]=row
    end
    local prev=Button(p,"< PREV",85,29,function() questPage=max(1,questPage-1);p:Refresh() end)
    prev:SetPoint("BOTTOMLEFT",p,"BOTTOMLEFT",28,24)
    local pageLabel=Label(p,"1 / 1",11,MUTED,115)
    pageLabel:SetJustifyH("CENTER")
    pageLabel:SetPoint("BOTTOM",p,"BOTTOM",0,31)
    local next=Button(p,"NEXT >",85,29,function() questPage=questPage+1;p:Refresh() end)
    next:SetPoint("BOTTOMRIGHT",p,"BOTTOMRIGHT",-28,24)
    function p:Refresh()
        local current=SafePlayerXP()
        local need=current and max(0,current.maximum-current.xp) or 0
        total:SetText(quests.count.." QUEST"..(quests.count==1 and "" or "S").." READY")
        local source=Comma(quests.knownXP)..(quests.unknown>0 and "+" or "").." known XP"
        local status=ProjectedStatus(current)
        if quests.count==0 then summary:SetText("Complete quests to see turn-in XP here.")
        elseif status=="DING" then summary:SetText(C_GREEN..source.."|r  •  Guaranteed level up!")
        elseif status=="MAYBE" then summary:SetText(source.."  •  "..quests.unknown.." unknown reward(s), ding uncertain")
        else summary:SetText(source.."  •  "..Comma(max(0,need-quests.knownXP)).." XP still needed") end
        local pages=max(1,ceil(quests.count/8))
        questPage=max(1,min(questPage,pages))
        pageLabel:SetText(questPage.." / "..pages)
        for i,row in ipairs(questRows) do
            local info=quests.items[(questPage-1)*8+i]
            if info then
                row.title=info.title
                row.value=info.xp
                local displayTitle=info.title
                if #displayTitle>41 then displayTitle=displayTitle:sub(1,38).."..." end
                row.text:SetText(displayTitle)
                row.xp:SetText(info.xp and ("+"..Comma(info.xp)) or "XP unknown")
                row.text:Show();row.xp:Show();row.hit:Show()
            else
                row.title=nil;row.value=nil
                row.text:Hide();row.xp:Hide();row.hit:Hide()
            end
        end
        prev:SetEnabled(questPage>1)
        next:SetEnabled(questPage<pages)
    end
    p:Refresh()
end

local function MakeDetails()
    local p=MakePopup("AscendXPDetailsFrame","ASCENDXP  /  XP HISTORY","Session breakdown and recent kills",490,600)
    detailsFrame=p
    local heading=Label(p,"SESSION OVERVIEW",10,GOLD,280)
    heading:SetPoint("TOPLEFT",p,"TOPLEFT",29,-85)
    local specs={
        {"XP EARNED", "XP / HOUR"},
        {"MOB XP", "MOB KILLS"},
        {"AVG LAST 25", "KILLS TO LEVEL"},
        {"QUEST TURN-INS", "SESSION TIME"},
    }
    local fields={}
    for i,pair in ipairs(specs) do
        local y=109+(i-1)*41
        fields[i]={}
        for k=1,2 do
            local x=k==1 and 29 or 263
            local tag=Label(p,pair[k],9,MUTED,206)
            tag:SetPoint("TOPLEFT",p,"TOPLEFT",x,-y)
            local val=Label(p,"—",14,WHITE,207)
            val:SetPoint("TOPLEFT",p,"TOPLEFT",x,-(y+16))
            fields[i][k]=val
        end
    end
    local divider=p:CreateTexture(nil,"ARTWORK")
    divider:SetColorTexture(0.26,0.60,0.57,0.65)
    divider:SetPoint("TOPLEFT",p,"TOPLEFT",29,-278)
    divider:SetSize(428,1)
    local recentHead=Label(p,"RECENT MOB XP",10,GOLD,270)
    recentHead:SetPoint("TOPLEFT",p,"TOPLEFT",29,-289)
    local records={}
    for i=1,7 do
        local y=316+(i-1)*29
        local l=Label(p,"",11,WHITE,330)
        l:SetPoint("TOPLEFT",p,"TOPLEFT",32,-y)
        local r=Label(p,"",11,TEAL,100)
        r:SetPoint("TOPRIGHT",p,"TOPRIGHT",-32,-y)
        r:SetJustifyH("RIGHT")
        records[i]={left=l,right=r}
    end
    local questButton=Button(p,"VIEW READY QUESTS",204,32,function() p:Hide();AX:ToggleQuests() end)
    questButton:SetPoint("BOTTOMLEFT",p,"BOTTOMLEFT",29,29)
    local closeButton=Button(p,"CLOSE",205,32,function() p:Hide() end)
    closeButton:SetPoint("BOTTOMRIGHT",p,"BOTTOMRIGHT",-29,29)
    function p:Refresh()
        local s=ch.session
        local rate,ready=Rate()
        local cur=SafePlayerXP()
        local remaining=cur and max(0,cur.maximum-cur.xp) or 0
        local avg=AverageKill()
        fields[1][1]:SetText(Comma(s.xp or 0))
        fields[1][2]:SetText(ready and Short(rate).." XP/h" or "Calculating...")
        fields[2][1]:SetText(Comma(s.killXP or 0).." XP")
        fields[2][2]:SetText(Comma(s.kills or 0))
        fields[3][1]:SetText(avg>0 and Comma(avg).." XP" or "No kills yet")
        fields[3][2]:SetText(avg>0 and Comma(ceil(remaining/avg)) or "No kills yet")
        fields[4][1]:SetText(Comma(s.questCount or 0).." / "..Short(s.questXP or 0).." XP")
        fields[4][2]:SetText(TimeLeft(max(0,Now()-(s.started or Now()))))
        local arr=s.recentKillRecords or {}
        for i,row in ipairs(records) do
            local record=arr[#arr-i+1]
            if record then
                local display=record.name or "Unknown creature"
                if #display>40 then display=display:sub(1,37).."..." end
                row.left:SetText(display)
                row.right:SetText("+"..Comma(record.xp))
            else
                row.left:SetText(i==1 and "No qualifying mob kills yet." or "")
                row.right:SetText("")
            end
        end
    end
    p:Refresh()
end

-- Read-only loot valuation drilldown: the main tracker never grows beyond one row.
local function MakeGoldDetails()
    local p=MakePopup("AscendXPGoldFrame","ASCENDXP  /  GOLD","Session earnings and loot",490,529)
    goldDetailsFrame=p
    local head=Label(p,"SESSION ESTIMATES",10,GOLD,240)
    head:SetPoint("TOPLEFT",p,"TOPLEFT",29,-82)
    local specs={{"EST. GOLD / HOUR","NET SESSION VALUE"},{"GOLD EARNED","LOOT VALUE"},{"GOLD SPENT","ITEMS / UNPRICED"}}
    local fields={}
    for i,pair in ipairs(specs) do
        fields[i]={}
        for k=1,2 do
            local x=k==1 and 29 or 264
            local y=106+(i-1)*44
            local label=Label(p,pair[k],9,MUTED,203)
            label:SetPoint("TOPLEFT",p,"TOPLEFT",x,-y)
            local value=Label(p,"—",14,WHITE,204)
            value:SetPoint("TOPLEFT",p,"TOPLEFT",x,-(y+15))
            fields[i][k]=value
        end
    end
    local tip=Label(p,"Right-click GOLD / HOUR for individual pickups.",10,MUTED,436)
    tip:SetPoint("TOPLEFT",p,"TOPLEFT",29,-246)
    local divider=p:CreateTexture(nil,"ARTWORK")
    divider:SetColorTexture(0.25,0.58,0.58,0.75)
    divider:SetPoint("TOPLEFT",p,"TOPLEFT",29,-270)
    divider:SetSize(431,1)
    local title=Label(p,"HIGHEST VALUE LOOT",10,GOLD,275)
    title:SetPoint("TOPLEFT",p,"TOPLEFT",29,-282)
    local history={}
    for i=1,6 do
        local y=311+(i-1)*24
        local left=Label(p,"",11,WHITE,299)
        left:SetPoint("TOPLEFT",p,"TOPLEFT",32,-y)
        local right=Label(p,"",11,GOLD,119)
        right:SetJustifyH("RIGHT")
        right:SetPoint("TOPRIGHT",p,"TOPRIGHT",-32,-y)
        history[i]={left=left,right=right}
    end
    local refresh=Button(p,"REFRESH PRICES",201,31,function() Money.UpdatePrices(true);p:Refresh();UpdateUI() end)
    refresh:SetPoint("BOTTOMLEFT",p,"BOTTOMLEFT",29,24)
    local close=Button(p,"CLOSE",201,31,function() p:Hide() end)
    close:SetPoint("BOTTOMRIGHT",p,"BOTTOMRIGHT",-29,24)
    function p:Refresh()
        local m=Money.Summary()
        local hourly,ok=Money.Rate(db.rateWindow)
        fields[1][1]:SetText(ok and (Money.Compact(hourly).." /h") or "Calculating...")
        fields[1][2]:SetText(Money.Format(m.total))
        fields[2][1]:SetText(Money.Format(m.cash))
        fields[2][2]:SetText(Money.Format(m.loot))
        fields[3][1]:SetText(Money.Format(m.spent))
        fields[3][2]:SetText(Comma(m.items).." / "..Comma(m.missing).." unknown")
        tip:SetText("Right-click GOLD / HOUR for individual pickups.")
        local entries=Money.TopItems(6)
        for i,row in ipairs(history) do
            local item=entries[i]
            if item then
                local name=(item.name or "Unknown item")
                if #name>32 then name=name:sub(1,29).."..." end
                row.left:SetText((item.count or 0).."x "..name.."  ["..(item.source or "?").."]")
                row.right:SetText(Money.Compact((item.unit or 0)*(item.count or 0)))
            else
                row.left:SetText(i==1 and "No items collected this session." or "")
                row.right:SetText("")
            end
        end
    end
    p:Refresh()
end
function AX:ToggleGold()
    if not goldDetailsFrame then return end
    if goldDetailsFrame:IsShown() then goldDetailsFrame:Hide()
    else goldDetailsFrame:Refresh();goldDetailsFrame:Show() end
end

-- Itemized farming receipts, one row per actual loot pickup (not aggregated by item).
-- Keep this separate from the compact gold summary to avoid cluttering the tracker.
local function MakeLootLedger()
    local p=MakePopup("AscendXPLootLedgerFrame","ASCENDXP  /  LOOT LEDGER",
        "Individual pickups and item values",620,620)
    lootLedgerFrame=p
    local totalLoot=Label(p,"LOOT VALUE",10,GOLD,200)
    totalLoot:SetPoint("TOPLEFT",p,"TOPLEFT",30,-86)
    local totalValue=Label(p,"0g",16,WHITE,200)
    totalValue:SetPoint("TOPLEFT",p,"TOPLEFT",30,-103)
    local pickupsTitle=Label(p,"PICKUPS",10,GOLD,200)
    pickupsTitle:SetPoint("TOPLEFT",p,"TOPLEFT",382,-86)
    local pickupCount=Label(p,"0",16,WHITE,200)
    pickupCount:SetPoint("TOPLEFT",p,"TOPLEFT",382,-103)

    local colY=-139
    local columns={{"ITEM",30,272},{"QTY",326,44},{"EACH",388,92},{"TOTAL",494,99}}
    for _,info in ipairs(columns) do
        local t=Label(p,info[1],10,GOLD,info[3])
        t:SetPoint("TOPLEFT",p,"TOPLEFT",info[2],colY)
        if info[1] ~= "ITEM" then t:SetJustifyH("RIGHT") end
    end
    local rule=p:CreateTexture(nil,"ARTWORK")
    rule:SetColorTexture(0.25,0.65,0.66,0.70)
    rule:SetPoint("TOPLEFT",p,"TOPLEFT",28,-158)
    rule:SetPoint("TOPRIGHT",p,"TOPRIGHT",-28,-158)
    rule:SetHeight(1)
    local lines={}
    for i=1,11 do
        local yy=173+(i-1)*33
        local hit=CreateFrame("Button",nil,p)
        hit:SetSize(563,31)
        hit:SetPoint("TOPLEFT",p,"TOPLEFT",28,-(yy-2))
        hit:RegisterForClicks("LeftButtonUp")
        hit.bg=hit:CreateTexture(nil,"BACKGROUND")
        hit.bg:SetAllPoints()
        hit.bg:SetColorTexture(0.12,0.22,0.29,i%2==0 and 0.27 or 0.42)
        local item=Label(hit,"",11,WHITE,273)
        item:SetPoint("LEFT",hit,"LEFT",2,0)
        local qty=Label(hit,"",11,MUTED,43)
        qty:SetPoint("RIGHT",hit,"LEFT",342,0)
        qty:SetJustifyH("RIGHT")
        local each=Label(hit,"",10,WHITE,95)
        each:SetPoint("RIGHT",hit,"LEFT",453,0)
        each:SetJustifyH("RIGHT")
        local total=Label(hit,"",10,GOLD,99)
        total:SetPoint("RIGHT",hit,"RIGHT",-1,0)
        total:SetJustifyH("RIGHT")
        hit:SetScript("OnEnter",function(self)
            self.bg:SetColorTexture(0.14,0.39,0.41,0.50)
            if self.link then
                GameTooltip:SetOwner(self,"ANCHOR_CURSOR")
                if not pcall(GameTooltip.SetHyperlink,GameTooltip,self.link) then
                    GameTooltip:AddLine(self.itemName or "Loot")
                end
                GameTooltip:AddDoubleLine("Each", self.source=="PENDING" and "..." or Money.Format(self.unitPrice or 0),0.6,0.8,0.85,1,1,1)
                if self.source=="AH" then GameTooltip:AddLine("Auction value",0.96,0.78,0.43)
                elseif self.source=="VENDOR" then GameTooltip:AddLine("Vendor value",0.96,0.78,0.43) end
                GameTooltip:Show()
            end
        end)
        hit:SetScript("OnLeave",function(self)
            self.bg:SetColorTexture(0.12,0.22,0.29,i%2==0 and 0.27 or 0.42)
            GameTooltip:Hide()
        end)
        hit:SetScript("OnClick",function(self)
            if self.link and ChatEdit_InsertLink and IsShiftKeyDown and IsShiftKeyDown() then
                ChatEdit_InsertLink(self.link)
            end
        end)
        lines[i]={hit=hit,item=item,qty=qty,each=each,total=total}
    end
    local prev=Button(p,"< PREV",98,30,function()
        lootLedgerPage=max(1,lootLedgerPage-1)
        p:Refresh()
    end)
    prev:SetPoint("BOTTOMLEFT",p,"BOTTOMLEFT",29,24)
    local pageText=Label(p,"1 / 1",11,MUTED,106)
    pageText:SetJustifyH("CENTER")
    pageText:SetPoint("BOTTOM",p,"BOTTOM",0,31)
    local next=Button(p,"NEXT >",98,30,function()
        lootLedgerPage=lootLedgerPage+1
        p:Refresh()
    end)
    next:SetPoint("BOTTOMRIGHT",p,"BOTTOMRIGHT",-29,24)

    function p:Refresh()
        local m=Money.Summary()
        totalValue:SetText(Money.Format(m.loot))
        local _,count=Money.LootEntries(1,1)
        pickupCount:SetText(Comma(count).." pickups  /  "..Comma(m.items).." items")
        local pageCount=max(1,ceil(count/11))
        lootLedgerPage=max(1,min(lootLedgerPage,pageCount))
        local entries=Money.LootEntries(lootLedgerPage,11)
        pageText:SetText(lootLedgerPage.." / "..pageCount)
        prev:SetEnabled(lootLedgerPage>1)
        next:SetEnabled(lootLedgerPage<pageCount)
        for i,line in ipairs(lines) do
            local e=entries[i]
            if e then
                local n=e.name or "Unknown item"
                line.item:SetText(n)
                local q=type(e.quality)=="number" and e.quality or nil
                if q and GetItemQualityColor then
                    local r,g,b=GetItemQualityColor(q)
                    line.item:SetTextColor(r or 1,g or 1,b or 1)
                else
                    TextColor(line.item,WHITE)
                end
                line.qty:SetText(Comma(e.count))
                line.each:SetText(e.source=="PENDING" and "..." or Money.Format(e.unit))
                line.total:SetText(e.source=="PENDING" and "..." or Money.Format(e.total))
                line.hit.link=e.link
                line.hit.itemName=e.name
                line.hit.source=e.source
                line.hit.unitPrice=e.unit
                line.hit:Show()
            else
                line.hit.link=nil
                line.hit:Hide()
            end
        end
    end
    p:Refresh()
end
function AX:ToggleLootLedger()
    if not lootLedgerFrame then return end
    if lootLedgerFrame:IsShown() then lootLedgerFrame:Hide()
    else lootLedgerPage=1;lootLedgerFrame:Refresh();lootLedgerFrame:Show() end
end

local function MinimapPosition()
    if not minimapButton or not Minimap then return end
    local a=math.rad(db.minimapAngle or 215)
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER",Minimap,"CENTER",math.cos(a)*80,math.sin(a)*80)
end
local function MinimapDrag(self)
    local scale=Minimap:GetEffectiveScale()
    local x,y=GetCursorPosition()
    x,y=x/scale,y/scale
    local cx,cy=Minimap:GetCenter()
    if not cx or not cy then return end
    local dx,dy=x-cx,y-cy
    if dx==0 and dy==0 then return end
    -- atan2 is available in WoW Lua; avoid relying on a 2-arg atan implementation.
    local ang
    if math.atan2 then ang=math.atan2(dy,dx)
    elseif dx>0 then ang=math.atan(dy/dx)
    elseif dx<0 then ang=math.atan(dy/dx)+math.pi
    elseif dy>0 then ang=math.pi/2 else ang=-math.pi/2 end
    db.minimapAngle=math.deg(ang)
    MinimapPosition()
end
local function MakeMinimap()
    if not Minimap then return end
    local b=CreateFrame("Button","AscendXPMinimapButton",Minimap)
    minimapButton=b
    b:SetSize(35,35)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(Minimap:GetFrameLevel()+8)
    b:RegisterForClicks("LeftButtonUp","RightButtonUp")
    b:RegisterForDrag("LeftButton")
    local bg=b:CreateTexture(nil,"BACKGROUND")
    bg:SetSize(35,35)
    bg:SetPoint("CENTER")
    bg:SetColorTexture(0.03,0.08,0.12,0.90)
    local mark=b:CreateTexture(nil,"ARTWORK")
    mark:SetTexture(PATH.."crest.tga")
    mark:SetSize(38,38)
    mark:SetPoint("CENTER")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight","ADD")
    b:SetScript("OnClick",function(_,button)
        if button=="RightButton" then db.showTracker=not db.showTracker;ApplyTracker();AX:RefreshSettings()
        else AX:ToggleSettings() end
    end)
    b:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_LEFT")
        GameTooltip:AddLine("AscendXP",0.25,0.90,0.85)
        GameTooltip:AddLine("Left-click: settings",1,1,1)
        GameTooltip:AddLine("Right-click: show/hide tracker",1,1,1)
        GameTooltip:AddLine("Drag: move around minimap",1,1,1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave",function() GameTooltip:Hide() end)
    b:SetScript("OnDragStart",function(self)
        self.dragging=true
        self:SetScript("OnUpdate",MinimapDrag)
    end)
    b:SetScript("OnDragStop",function(self)
        self.dragging=false
        self:SetScript("OnUpdate",nil)
    end)
    MinimapPosition()
end

function AX:ToggleSettings()
    if not settingsFrame then return end
    if settingsFrame:IsShown() then settingsFrame:Hide()
    else settingsFrame:Refresh();settingsFrame:Show() end
end
function AX:ToggleDetails()
    if not detailsFrame then return end
    if detailsFrame:IsShown() then detailsFrame:Hide()
    else detailsFrame:Refresh();detailsFrame:Show() end
end
function AX:ToggleQuests()
    if not questFrame then return end
    if questFrame:IsShown() then questFrame:Hide()
    else ScanQuests();questPage=1;questFrame:Refresh();questFrame:Show() end
end
function AX:RefreshAll()
    if not ch then return end
    ScanQuests();UpdateUI()
end
local function QueueRefresh()
    if pendingRefresh then return end
    pendingRefresh=true
    if C_Timer and C_Timer.After then
        C_Timer.After(.2,function() pendingRefresh=false;AX:RefreshAll() end)
    else pendingRefresh=false;AX:RefreshAll() end
end
local function CaptureKill(message)
    if type(message)~="string" or not ch or not ch.session then return end
    -- Combat XP strings are separate from combat log events on Forever.
    -- Only count a *named creature death*; do not misidentify quest XP as a kill.
    local plain=message:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
    local name=plain:match("^(.-) dies[,%.]") or plain:match("^(.-) is slain[,%.]")
    if not name or name=="" then return end
    if #name > 90 then name = name:sub(1,87).."..." end
    local amount=plain:match("you gain ([%d,%. ]+) experience") or plain:match("you receive ([%d,%. ]+) experience")
    if not amount then return end
    local n=tonumber((amount:gsub("[^%d]","")))
    if not n or n<=0 then return end
    local s=ch.session
    s.lastKill=n
    s.lastMob=name
    s.kills=(s.kills or 0)+1
    s.killXP=(s.killXP or 0)+n
    s.recentKills[#s.recentKills+1]=n
    if #s.recentKills>25 then table.remove(s.recentKills,1) end
    s.recentKillRecords=s.recentKillRecords or {}
    s.recentKillRecords[#s.recentKillRecords+1]={name=name,xp=n}
    if #s.recentKillRecords>20 then table.remove(s.recentKillRecords,1) end
    UpdateUI()
end
local function Init()
    AscendXPSettings=AscendXPSettings or {}
    db=AscendXPSettings
    for k,v in pairs(defaults) do if db[k]==nil then db[k]=v end end
    -- v1.2.2 did not actually fade the native manager when an XP child existed.
    -- Enable the requested replacement once when upgrading from that version.
    if not db.nativeBarFix123 then
        db.hideBlizzardBar = true
        db.nativeBarFix123 = true
    end
    db.rateWindow=(db.rateWindow==5 or db.rateWindow==15 or db.rateWindow==30 or db.rateWindow==0) and db.rateWindow or 15
    db.scale=max(.7,min(1.5,tonumber(db.scale) or 1))
    db.barScale=max(.7,min(1.5,tonumber(db.barScale) or db.scale or 1))
    if db.uiMode ~= "panel" and db.uiMode ~= "bar" and db.uiMode ~= "both" then db.uiMode = "bar" end
    AscendXPCharacter=AscendXPCharacter or {}
    ch=AscendXPCharacter
    if not ch.session or (ch.lastLogout and (Now()-ch.lastLogout)>90) or (ch.session.started and Now()-ch.session.started>86400) then
        NewSession()
    end
    ch.lastLogout=nil
    ch.session.samples=ch.session.samples or {}
    ch.session.recentKills=ch.session.recentKills or {}
    ch.session.recentKillRecords=ch.session.recentKillRecords or {}
    ch.session.lastKill=ch.session.lastKill or 0
    ch.session.lastMob=ch.session.lastMob or ""
    Money.Init(ch.session,function() UpdateUI() end)
    snapshot=SafePlayerXP()
    ScanQuests()
    MakeTracker()
    MakeBarTracker()
    MakeSettings()
    MakeQuests()
    MakeDetails()
    MakeGoldDetails()
    MakeLootLedger()
    MakeMinimap()
    ApplyTracker()
    UpdateUI()
end
AX:RegisterEvent("PLAYER_LOGIN")
AX:RegisterEvent("PLAYER_ENTERING_WORLD")
AX:RegisterEvent("ADDON_LOADED")
AX:RegisterEvent("PLAYER_LOGOUT")
AX:RegisterEvent("PLAYER_XP_UPDATE")
AX:RegisterEvent("UPDATE_EXHAUSTION")
AX:RegisterEvent("PLAYER_LEVEL_UP")
AX:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
AX:RegisterEvent("QUEST_LOG_UPDATE")
AX:RegisterEvent("QUEST_ACCEPTED")
AX:RegisterEvent("QUEST_REMOVED")
AX:RegisterEvent("QUEST_TURNED_IN")
-- Gold is collected via Blizzard's own loot and wallet notifications, with AH prices
-- read passively from Auctionator when available. Never drives the AH UI.
local moneyEvents = {
    PLAYER_MONEY=true, CHAT_MSG_LOOT=true, GET_ITEM_INFO_RECEIVED=true,
    ITEM_DATA_LOAD_RESULT=true, BAG_UPDATE_DELAYED=true,
    LOOT_READY=true, LOOT_OPENED=true, LOOT_CLOSED=true, LOOT_SLOT_CLEARED=true,
    PLAYER_INTERACTION_MANAGER_FRAME_SHOW=true,PLAYER_INTERACTION_MANAGER_FRAME_HIDE=true,
    MERCHANT_SHOW=true,MERCHANT_CLOSED=true,MAIL_SHOW=true,MAIL_CLOSED=true,
    AUCTION_HOUSE_SHOW=true,AUCTION_HOUSE_CLOSED=true,BANKFRAME_OPENED=true,
    BANKFRAME_CLOSED=true,GUILDBANKFRAME_OPENED=true,GUILDBANKFRAME_CLOSED=true,
    TRADE_SHOW=true,TRADE_CLOSED=true,
}
for event in pairs(moneyEvents) do AX:RegisterEvent(event) end
AX:SetScript("OnEvent",function(self,event,...)
    if event=="PLAYER_LOGIN" then Init()
    elseif event=="PLAYER_ENTERING_WORLD" then
        if db then
            ApplyTracker()
            if C_Timer and C_Timer.After then
                C_Timer.After(1.0,function() if db then ApplyTracker() end end)
            end
        end
    elseif event=="PLAYER_LOGOUT" then if ch then ch.lastLogout=Now() end
    elseif moneyEvents[event] then
        Money.OnEvent(event,...)
    elseif event=="PLAYER_XP_UPDATE" then
        HandleXPChange();UpdateUI()
    elseif event=="UPDATE_EXHAUSTION" then
        UpdateUI()
    elseif event=="PLAYER_LEVEL_UP" then
        if C_Timer and C_Timer.After then
            C_Timer.After(.1,function() HandleXPChange();QueueRefresh() end)
        else HandleXPChange();QueueRefresh() end
    elseif event=="CHAT_MSG_COMBAT_XP_GAIN" then CaptureKill(...)
    elseif event=="QUEST_TURNED_IN" then
        local _,questXP=...
        if ch and IsNumber(questXP) and questXP>0 then
            ch.session.questXP=(ch.session.questXP or 0)+questXP
            ch.session.questCount=(ch.session.questCount or 0)+1
        end
        QueueRefresh()
    else QueueRefresh() end
end)
AX:SetScript("OnUpdate",function(self,elapsed)
    lastDraw=lastDraw+elapsed
    if lastDraw>=2.5 then
        lastDraw=0
        if ch then PruneSamples();UpdateUI() end
        if db and BlizzardBar then BlizzardBar.Apply(db.showTracker and db.hideBlizzardBar and BarMode()) end
    end
end)

SLASH_ASCENDXP1="/axp"
SLASH_ASCENDXP2="/ascendxp"
SlashCmdList.ASCENDXP=function(raw)
    local cmd=string.lower((raw or ""):match("^%s*(%S*)") or "")
    if not db then print("AscendXP is still loading.");return end
    if cmd=="" or cmd=="settings" or cmd=="options" then AX:ToggleSettings()
    elseif cmd=="quests" then AX:ToggleQuests()
    elseif cmd=="loot" or cmd=="money" then AX:ToggleGold()
    elseif cmd=="ledger" or cmd=="drops" then AX:ToggleLootLedger()
    elseif cmd=="golddebug" then
        local d=Money.DebugStatus()
        print(C_TEAL.."AscendXP Gold Diagnostics|r: loot windows "..d.windows..", chat parsed "..d.parsedChat.."/"..d.lootChat..", bag checks "..d.bagChecks)
        print(C_TEAL.."AscendXP|r: recorded items "..d.recorded..", session total "..d.totalItems..", unpriced "..d.unpriced..", bag API "..(d.bagAPI and "yes" or "no")..", pending "..(d.pending and "yes" or "no"))
        print(C_TEAL.."AscendXP|r: last pickup "..d.last)
    elseif cmd=="gold" then db.showGold=not db.showGold;ApplyTracker();AX:RefreshSettings();UpdateUI()
    elseif cmd=="blizzbar" then db.hideBlizzardBar=not db.hideBlizzardBar;ApplyTracker();AX:RefreshSettings()
    elseif cmd=="bars" then
        if BlizzardBar then BlizzardBar.Apply(db.showTracker and db.hideBlizzardBar and BarMode()) end
        print(C_TEAL.."AscendXP|r bars: "..(BlizzardBar and BlizzardBar.Debug() or "module unavailable"))
    elseif cmd=="details" then AX:ToggleDetails()
    elseif cmd=="panel" then SetMode("panel")
    elseif cmd=="bar" then SetMode("bar")
    elseif cmd=="both" then SetMode("both")
    elseif cmd=="compact" then db.compact=not db.compact;ApplyTracker();AX:RefreshSettings()
    elseif cmd=="lock" then db.locked=true;AX:RefreshSettings()
    elseif cmd=="unlock" then db.locked=false;AX:RefreshSettings()
    elseif cmd=="show" then db.showTracker=true;ApplyTracker();AX:RefreshSettings()
    elseif cmd=="hide" then db.showTracker=false;ApplyTracker();AX:RefreshSettings()
    elseif cmd=="minimap" then db.showMinimap=not db.showMinimap;ApplyTracker();AX:RefreshSettings()
    elseif cmd=="center" then
        db.x=0;db.y=150; db.barX=0; db.barY=-14; db.barAnchor="TOP"
        if tracker then tracker:ClearAllPoints();tracker:SetPoint("CENTER",UIParent,"CENTER",db.x,db.y) end
        if barTracker then barTracker:ClearAllPoints();barTracker:SetPoint("TOP",UIParent,"TOP",db.barX,db.barY) end
    elseif cmd=="reset" then AX:ResetSession()
    elseif cmd=="help" then
        print(C_TEAL.."AscendXP|r /axp settings, panel, bar, both, details, quests, loot, gold, blizzbar, bars, compact, show, hide, lock, unlock, center, reset, minimap, golddebug")
    else print(C_RED.."AscendXP|r: Unknown option. Type /axp help") end
end
