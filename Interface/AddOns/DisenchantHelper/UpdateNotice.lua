local addonName, ns = ...
local prefix = "DEHRelease1"

-- Releases only. No network lookup, saved peer data or prerelease promotion.
local function VersionCode(value)
    if issecretvalue and issecretvalue(value) then return end
    if type(value) ~= "string" or #value > 11 then return end
    local a,b,c = value:match("^(%d+)%.(%d+)%.(%d+)$")
    a,b,c = tonumber(a),tonumber(b),tonumber(c)
    if not a or not b or not c or a>999 or b>999 or c>999 then return end
    if value ~= ("%d.%d.%d"):format(a,b,c) then return end
    return a*1000000+b*1000+c
end

local metadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
if not metadata then return end
local ok, version = pcall(metadata, addonName, "Version")
local current = ok and VersionCode(version)
if not current then return end

local register = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
if not register or not send then return end

local highest, ready = current, false
local lastSend, queued = {}, {}
local channels = {"GUILD","PARTY","RAID","INSTANCE_CHAT"}

local function InChannel(channel)
    if channel=="GUILD" then return IsInGuild and IsInGuild() end
    if not IsInGroup then return false end
    if channel=="INSTANCE_CHAT" then
        return LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
    end
    local home=LE_PARTY_CATEGORY_HOME
    local inRaid=IsInRaid and IsInRaid(home)
    if channel=="RAID" then return inRaid end
    return channel=="PARTY" and not inRaid and IsInGroup(home)
end

local function Schedule(channel)
    if not InChannel(channel) or queued[channel] then return end
    local now=GetTime()
    if lastSend[channel] and now-lastSend[channel]<30 then return end
    local ticket={}
    queued[channel]=ticket
    local function Announce()
        if queued[channel]~=ticket then return end
        queued[channel]=nil
        if not InChannel(channel) then return end
        lastSend[channel]=GetTime()
        pcall(send,prefix,version,channel)
    end
    if C_Timer and C_Timer.After then C_Timer.After(1+math.random()*3,Announce)
    else Announce() end
end

local function HandleMessage(tag, text, channel)
    if issecretvalue and (issecretvalue(tag) or issecretvalue(channel)) then return end
    if tag~=prefix or not InChannel(channel) then return end
    local remote=VersionCode(text)
    if not remote then return end
    if remote<current then
        Schedule(channel)
    elseif remote>highest then
        highest=remote
        print(ns.L.UPDATE_NOTICE:format(text,version))
    end
end

local frame=CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent",function(_,event,...)
    if event=="PLAYER_LOGIN" then
        local success,result=pcall(register,prefix)
        ready=success and result~=false
    end
    if not ready then return end
    if event=="CHAT_MSG_ADDON" then HandleMessage(...)
    else
        for _,channel in ipairs(channels) do Schedule(channel) end
    end
end)
