-- NectarSellers: shows the seller name on each row of the auction house item buy list
-- (AuctionHouseFrame.ItemBuyFrame.ItemList), tinting sellers that have 2+ listings of the item.
-- Taint rules: nothing is ever written onto a Blizzard frame table; our FontStrings live in weak
-- local tables; we only use ScrollUtil callbacks and HookScript; every Blizzard touch is pcall'd.
local addonName, NS = ...
local L = NS.Logic

local ROW_RIGHT, ROW_W = -192, 130 -- label right-aligned in the empty fill column, just left of the 24px info + 140px Time Left columns
local HEADER_TEXT = "Seller"
local MAX_RESULTS = 1000

local labels = setmetatable({}, { __mode = "k" })  -- row frame -> FontString
local rowSeller = setmetatable({}, { __mode = "k" }) -- row frame -> full seller key, for the tooltip
local hooked = setmetatable({}, { __mode = "k" })   -- row frame -> true once OnEnter is hooked
local cbOwner = {}                                   -- our owner token for ScrollBox callbacks
local cur = { list = nil, ibf = nil, header = nil, counts = {}, dirty = true }

local function say(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Sellers|r: " .. msg) end
end

local function enabled() return not (type(NectarSellersDB) == "table" and NectarSellersDB.enabled == false) end

local function get(t, k)
    if type(t) ~= "table" then return nil end
    local ok, v = pcall(function() return t[k] end)
    if ok then return v end
end

local function myName()
    local ok, n = pcall(UnitName, "player")
    if ok and type(n) == "string" then return n end
end

local function itemKey() return get(cur.ibf, "itemKey") end

local function apiInfo(index)
    local key = itemKey()
    local api = type(C_AuctionHouse) == "table" and C_AuctionHouse.GetItemSearchResultInfo
    if type(index) ~= "number" or key == nil or type(api) ~= "function" then return nil end
    local ok, info = pcall(api, key, index)
    if ok and type(info) == "table" then return info end
end

-- result for a row: by index from the API (authoritative), else the row's own rowData
local function rowInfo(frame, elementData)
    if type(elementData) ~= "number" then
        local fn = get(frame, "GetElementData")
        if type(fn) == "function" then
            local ok, d = pcall(fn, frame)
            if ok then elementData = d end
        end
    end
    local info = apiInfo(elementData)
    if info then return info end
    local rd = get(frame, "rowData")
    if type(rd) == "table" then return rd end
end

local function forEachRow(fn)
    local list = cur.list
    if not list then return end
    local sb = get(list, "ScrollBox")
    local each = get(sb, "ForEachFrame")
    if type(each) == "function" then
        pcall(each, sb, function(frame, elementData) fn(frame, elementData) end)
        return
    end
    local buttons = get(get(list, "ScrollFrame"), "buttons") -- pre-ScrollBox (HybridScrollFrame) lists
    if type(buttons) == "table" then
        for _, b in ipairs(buttons) do pcall(fn, b, nil) end
    end
end

local function recount()
    local me = myName()
    local key = itemKey()
    local api = type(C_AuctionHouse) == "table" and C_AuctionHouse
    local numFn = api and api.GetNumItemSearchResults
    local list = { n = 0 }
    local ok, n = false, nil
    if key ~= nil and type(numFn) == "function" then ok, n = pcall(numFn, key) end
    if ok and type(n) == "number" and n > 0 then
        if n > MAX_RESULTS then n = MAX_RESULTS end
        for i = 1, n do list[i] = apiInfo(i) end
        list.n = n
    else
        forEachRow(function(frame, elementData)
            list.n = list.n + 1; list[list.n] = rowInfo(frame, elementData)
        end)
    end
    cur.counts = L.countBySeller(list, me)
    cur.dirty = false
end

local function onEnter(frame)
    if not enabled() then return end
    local key = rowSeller[frame]
    if not key or not GameTooltip then return end
    local ok, shown = pcall(GameTooltip.IsShown, GameTooltip)
    if not (ok and shown) then return end
    local n = cur.counts[key] or 1
    pcall(GameTooltip.AddLine, GameTooltip,
        string.format("Seller: %s (%d listing%s here)", key, n, n == 1 and "" or "s"), 0.9, 0.9, 0.9)
    pcall(GameTooltip.Show, GameTooltip)
end

local function labelFor(frame)
    local fs = labels[frame]
    if fs then return fs end
    local mk = get(frame, "CreateFontString")
    if type(mk) ~= "function" then return nil end
    local ok
    ok, fs = pcall(mk, frame, nil, "OVERLAY", "GameFontHighlightSmall")
    if not ok or not fs then return nil end
    pcall(fs.SetPoint, fs, "RIGHT", frame, "RIGHT", ROW_RIGHT, 0)
    pcall(fs.SetWidth, fs, ROW_W)
    pcall(fs.SetJustifyH, fs, "RIGHT")
    pcall(fs.SetWordWrap, fs, false)
    labels[frame] = fs
    if not hooked[frame] and type(get(frame, "HookScript")) == "function" then
        hooked[frame] = true
        pcall(frame.HookScript, frame, "OnEnter", onEnter)
    end
    return fs
end

local function updateRow(frame, elementData)
    if not frame then return end
    if not enabled() then
        local fs = labels[frame]
        if fs then pcall(fs.Hide, fs) end
        return
    end
    if cur.dirty then recount() end
    local fs = labelFor(frame)
    if not fs then return end
    local me = myName()
    local info = rowInfo(frame, elementData)
    local text, color = L.sellerText(info, me)
    local key = L.sellerKey(info, me)
    color = color or L.tintFor(key, cur.counts)
    rowSeller[frame] = key
    pcall(fs.SetText, fs, text)
    pcall(fs.SetTextColor, fs, color[1], color[2], color[3])
    pcall(fs.Show, fs)
end

local function refreshAll()
    if not cur.list then return end
    if cur.header then pcall(cur.header.SetShown, cur.header, enabled()) end
    if enabled() and cur.dirty then recount() end
    forEachRow(updateRow)
end

local function onReleased(_, frame)
    rowSeller[frame] = nil
    local fs = labels[frame]
    if fs then pcall(fs.Hide, fs) end
end

local function attach()
    local ibf = get(AuctionHouseFrame, "ItemBuyFrame")
    local list = get(ibf, "ItemList")
    if type(list) ~= "table" then return false end
    if cur.list == list then return true end
    cur.list, cur.ibf, cur.dirty, cur.header = list, ibf, true, nil

    local hc = get(list, "HeaderContainer")
    local parent = type(hc) == "table" and hc or list
    local mk = get(parent, "CreateFontString")
    if type(mk) == "function" then
        local ok, h = pcall(mk, parent, nil, "OVERLAY", "GameFontNormalSmall")
        if ok and h then
            if parent == hc then pcall(h.SetPoint, h, "RIGHT", hc, "RIGHT", ROW_RIGHT, 0)
            else pcall(h.SetPoint, h, "TOPRIGHT", list, "TOPRIGHT", ROW_RIGHT, -6) end
            pcall(h.SetText, h, HEADER_TEXT)
            cur.header = h
        end
    end

    local sb = get(list, "ScrollBox")
    if type(sb) == "table" and type(ScrollUtil) == "table" then
        if type(ScrollUtil.AddInitializedFrameCallback) == "function" then
            -- no iterateExisting: Blizzard calls that pass without the owner argument
            pcall(ScrollUtil.AddInitializedFrameCallback, sb, function(_, frame, elementData)
                updateRow(frame, elementData)
            end, cbOwner, false)
        end
        if type(ScrollUtil.AddReleasedFrameCallback) == "function" then
            pcall(ScrollUtil.AddReleasedFrameCallback, sb, onReleased, cbOwner)
        end
    end
    if type(get(list, "HookScript")) == "function" then
        pcall(list.HookScript, list, "OnShow", function() cur.dirty = true; refreshAll() end)
    end
    refreshAll()
    return true
end

local function later(fn)
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        if pcall(C_Timer.After, 0, fn) then return end
    end
    pcall(fn)
end

local function setEnabled(on)
    if type(NectarSellersDB) ~= "table" then NectarSellersDB = {} end
    NectarSellersDB.enabled = on and true or false
    pcall(refreshAll)
end

local function ahLoaded()
    local fn = (type(C_AddOns) == "table" and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if type(fn) ~= "function" then return false end
    local ok, loaded = pcall(fn, "Blizzard_AuctionHouseUI")
    return ok and loaded and true or false
end

local function registerNectarKit()
    local onToggle = function(on) setEnabled(on) end
    if type(NectarKit_RegisterModule) == "function" then
        pcall(NectarKit_RegisterModule, addonName, "sellers", "AH seller names", true, onToggle)
        return
    end
    NectarKit_Queue = NectarKit_Queue or {}
    table.insert(NectarKit_Queue, { addon = addonName, key = "sellers", label = "AH seller names", default = true,
        onToggle = onToggle })
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
pcall(ev.RegisterEvent, ev, "ITEM_SEARCH_RESULTS_UPDATED")
pcall(ev.RegisterEvent, ev, "ITEM_SEARCH_RESULTS_ADDED")
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            if type(NectarSellersDB) ~= "table" then NectarSellersDB = {} end
            if NectarSellersDB.enabled == nil then NectarSellersDB.enabled = true end
            if ahLoaded() then pcall(attach) end
        elseif arg1 == "Blizzard_AuctionHouseUI" then
            pcall(attach)
        end
    elseif event == "PLAYER_LOGIN" then
        registerNectarKit()
    elseif cur.list then -- item search results changed
        cur.dirty = true
        later(function() pcall(refreshAll) end)
    end
end)

SLASH_NECTARSELLERS1 = "/sellers"
SlashCmdList["NECTARSELLERS"] = function(msg)
    msg = type(msg) == "string" and msg:lower():match("^%s*(%S*)") or ""
    if msg == "on" then setEnabled(true); say("on")
    elseif msg == "off" then setEnabled(false); say("off")
    elseif msg == "" or msg == "status" then
        say((enabled() and "on" or "off") .. (cur.list and ", attached to the auction house" or ", waiting for the auction house"))
    else say("usage: /sellers on | off | status") end
end
