-- ForeverCampGuide - Tracker.lua
-- Panel pequeño que aparece junto a la ventana de profesión con el paso actual.
local _, ns = ...
local L = ns.T
local W = ns.W
local T = {}
ns.Tracker = T

local GOLD, WHITE, GREY, GREEN, ORANGE = W.GOLD, W.WHITE, W.GREY, W.GREEN, W.ORANGE
local frame, text, nextText, openBtn
local openProf

local function Create()
    frame = CreateFrame("Frame", "ForeverCampGuideTracker", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetSize(300, 120)
    frame:SetFrameStrata("HIGH")
    if frame.SetBackdrop then
        frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        frame:SetBackdropColor(0, 0, 0, 0.85)
        frame:SetBackdropBorderColor(1, 0.82, 0, 0.8)
    end
    text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", 10, -10)
    text:SetWidth(280)
    text:SetJustifyH("LEFT"); text:SetJustifyV("TOP")
    nextText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    nextText:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -6)
    nextText:SetWidth(280)
    nextText:SetJustifyH("LEFT"); nextText:SetJustifyV("TOP")
    openBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    openBtn:SetSize(120, 20)
    openBtn:SetText(L("Abrir la guía"))
    openBtn:SetScript("OnClick", function() if openProf then ns.ShowPage(openProf.key, "guide") end end)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame:Hide()
end

local function CurrentProfession()
    local name
    if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
        local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        name = ok and info and info.professionName
    end
    if not name and GetTradeSkillLine then name = GetTradeSkillLine() end
    if (not name or name == "UNKNOWN") and GetCraftDisplaySkillLine then name = GetCraftDisplaySkillLine() end
    return ns.ProfFromName(name)
end

local function Anchor()
    local host = (ProfessionsFrame and ProfessionsFrame:IsShown() and ProfessionsFrame)
        or (TradeSkillFrame and TradeSkillFrame:IsShown() and TradeSkillFrame)
        or (CraftFrame and CraftFrame:IsShown() and CraftFrame)
    frame:ClearAllPoints()
    if host then frame:SetPoint("TOPLEFT", host, "TOPRIGHT", 4, 0)
    else frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 80) end
end

local function MatsLine(s, left, n)
    local parts = {}
    for _, m in ipairs(ns.ScaleMats(s, left, n)) do
        local have = ns.GetItemCount(m[1])
        local col = (have >= m[2] and GREEN) or (have > 0 and ORANGE) or WHITE
        parts[#parts + 1] = W.Icon(ns.GetItemIcon(m[1]), 14) .. " " .. col .. have .. "/" .. m[2] .. "|r " .. ns.GetItemName(m[1], "...")
    end
    return table.concat(parts, "\n")
end

local function StepLine(s, left)
    if s.spell then
        local count = ""
        if left and s.n and left < s.n then count = (L("%d de %d: ")):format(left, s.n)
        elseif s.n then count = s.n .. "x " end
        return WHITE .. count .. ns.GetSpellName(s.spell, s.name) .. "|r  " .. ns.P.KnownIcon(s.spell)
    end
    return WHITE .. L(s.short or s.text or "") .. "|r"
end

function T.Refresh()
    if not frame then return end
    if not (openProf and ns.db and ns.db.settings.tracker and ns.guides[openProf.key]) then frame:Hide(); return end
    local skill, max = ns.GetProfessionSkill(openProf)
    local lines = { GOLD .. "Camp Guide - " .. ns.ProfName(openProf) .. "|r  " .. WHITE .. (skill or "?") .. "/" .. (max or "?") .. "|r" }
    local cap = ns.CapWarning(skill, max)
    if cap then lines[#lines + 1] = ORANGE .. cap .. "|r" end
    local e, idx = ns.CurrentStep(openProf.key, skill)
    if e then
        local s = e.step
        local left, total = ns.StepRemaining(s, skill)
        lines[#lines + 1] = GOLD .. L("Ahora [") .. s.r .. "]:|r " .. StepLine(s, left)
        local m = MatsLine(s.mats, left, total)
        if m ~= "" then lines[#lines + 1] = m end
        if s.alt and #s.alt > 0 then
            lines[#lines + 1] = GREY .. (s.pick and L("o una de las otras ") .. #s.alt .. L(" opciones") or L("Hay alternativa en la guía")) .. "|r"
        end
        local nx = ns.NextStepAfter(openProf.key, idx)
        nextText:SetText(nx and (GREY .. L("Después [") .. nx.step.r .. "]: " .. (nx.step.spell and ns.GetSpellName(nx.step.spell, nx.step.name) or L(nx.step.short or nx.step.text or "")) .. "|r") or "")
    else
        lines[#lines + 1] = GREEN .. (skill and L("¡Guía completada!") or L("Aún no conoces esta profesión.")) .. "|r"
        nextText:SetText("")
    end
    text:SetText(table.concat(lines, "\n"))
    openBtn:ClearAllPoints()
    openBtn:SetPoint("TOPLEFT", nextText, "BOTTOMLEFT", 0, -6)
    frame:SetHeight(10 + text:GetStringHeight() + 6 + nextText:GetStringHeight() + 6 + 20 + 12)
    Anchor()
    frame:Show()
end

function T.OnProfessionOpen()
    if not frame then Create() end
    openProf = CurrentProfession()
    T.Refresh()
end

function T.OnProfessionClose()
    openProf = nil
    if frame then frame:Hide() end
end
