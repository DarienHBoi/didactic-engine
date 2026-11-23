local _, P = ...
-- Draws P.AHRows on auction house list rows, the hook approach of NectarSellers: nothing is ever written onto a Blizzard frame
-- table; our FontStrings live in weak local tables; only ScrollUtil callbacks and HookScript; every Blizzard touch is pcall'd.
-- Two lists: Browse Auctions results (AuctionHouseFrame.BrowseResultsFrame.ItemList, one row per item key at its lowest price;
-- green/red/grey "DE x" column right after Name) and, only when P.Config.AH_BUY_ROWS is true, the item buy list
-- (ItemBuyFrame.ItemList, per auction, left of NectarSellers' seller label). NectarKit module "ahrows" switches both live.
local R = P.AHRows

local HEADER_TEXT = "Disenchant"
local BUY_RIGHT, BUY_W = -330, 130     -- buy list: left of NectarSellers' seller label (RIGHT -192, width 130)
local BROWSE_FALLBACK, BROWSE_W = -164, 100 -- browse list when the header positions cannot be read: left of Level (50) + Available

local function on() return P.Mod.on("ahrows") end

local function get(t, k)
    if type(t) ~= "table" then return nil end
    local ok, v = pcall(function() return t[k] end)
    if ok then return v end
end

local function m(obj, name, ...)
    local fn = get(obj, name)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, obj, ...)
    if ok then return a, b end
end

local cbOwner = {}
local views = {}

local function newView(kind)
    return { kind = kind, list = nil, owner = nil, header = nil, right = kind == "buy" and BUY_RIGHT or BROWSE_FALLBACK,
        width = kind == "buy" and BUY_W or BROWSE_W, labels = setmetatable({}, { __mode = "k" }),
        rowEval = setmetatable({}, { __mode = "k" }), hooked = setmetatable({}, { __mode = "k" }),
        cache = {}, cacheSig = nil, cacheAt = 0, awaiting = false, pending = false, refreshes = 0, valued = 0 }
end
views.browse = newView("browse")
views.buy = newView("buy")

local function enabled(v)
    if not on() then return false end
    if v.kind == "buy" then return P.Config.AH_BUY_ROWS == true end
    return true
end

-- The browse list's column right after Name (Level, else Available), from the live header frames: the widest header is the Name
-- fill column; our label's right edge goes just left of the next header. Falls back to BROWSE_FALLBACK while frames are unplaced.
local function browseColumn(v)
    local hc = get(v.list, "HeaderContainer")
    local listRight = m(v.list, "GetRight")
    if type(hc) ~= "table" or type(listRight) ~= "number" then return end
    local kids = { m(hc, "GetChildren") }
    local okK, all = pcall(function() return { hc:GetChildren() } end)
    if okK and type(all) == "table" then kids = all end
    local heads = {}
    for _, h in ipairs(kids) do
        local l, w = m(h, "GetLeft"), m(h, "GetWidth")
        if type(l) == "number" and type(w) == "number" and w > 0 then heads[#heads + 1] = { l = l, w = w } end
    end
    if #heads < 2 then return end
    local name = heads[1]
    for _, h in ipairs(heads) do if h.w > name.w then name = h end end
    local nextH
    for _, h in ipairs(heads) do if h.l > name.l and (not nextH or h.l < nextH.l) then nextH = h end end
    if not nextH then return end
    v.right = math.floor(nextH.l - listRight - 6 + 0.5)
    v.width = math.max(60, math.min(BROWSE_W, math.floor(name.w * 0.45)))
end

-- The result a row shows: browse rows carry their summary as element data (else rowData, else an index into GetBrowseResults);
-- buy rows are an index into GetItemSearchResultInfo for the buy frame's key (else rowData).
local function rowInfo(v, frame, elementData)
    if elementData == nil then
        local d = m(frame, "GetElementData")
        if d ~= nil then elementData = d end
    end
    local api = type(C_AuctionHouse) == "table" and C_AuctionHouse or nil
    if v.kind == "browse" then
        if type(elementData) == "table" and type(get(elementData, "itemKey")) == "table" then return elementData end
        local rd = get(frame, "rowData")
        if type(rd) == "table" then return rd end
        if type(elementData) == "number" and api and type(api.GetBrowseResults) == "function" then
            local ok, list = pcall(api.GetBrowseResults)
            if ok and type(list) == "table" then return list[elementData] end
        end
        return nil
    end
    local key = get(v.owner, "itemKey")
    if type(elementData) == "number" and key ~= nil and api and type(api.GetItemSearchResultInfo) == "function" then
        local ok, info = pcall(api.GetItemSearchResultInfo, key, elementData)
        if ok and type(info) == "table" then return info end
    end
    local rd = get(frame, "rowData")
    if type(rd) == "table" then return rd end
end

local function forEachRow(v, fn)
    local sb = get(v.list, "ScrollBox")
    local each = get(sb, "ForEachFrame")
    if type(each) == "function" then
        pcall(each, sb, function(frame, elementData) pcall(fn, frame, elementData) end)
        return
    end
    local buttons = get(get(v.list, "ScrollFrame"), "buttons") -- pre-ScrollBox (HybridScrollFrame) lists
    if type(buttons) == "table" then
        for _, b in ipairs(buttons) do pcall(fn, b, nil) end
    end
end

local function onEnterFor(v)
    return function(frame)
        if not enabled(v) then return end
        local e = v.rowEval[frame]
        if not e or type(GameTooltip) ~= "table" then return end
        local ok, shown = pcall(GameTooltip.IsShown, GameTooltip)
        if not (ok and shown) then return end
        local okD, deps = pcall(R.deps)
        local okL, lines = pcall(R.tipLines, e, okD and deps.nameOf or nil)
        if not okL then return end
        for _, l in ipairs(lines) do pcall(GameTooltip.AddLine, GameTooltip, l[1], l[2][1], l[2][2], l[2][3]) end
        pcall(GameTooltip.Show, GameTooltip)
    end
end

local function place(v, fs, frame)
    pcall(fs.ClearAllPoints, fs)
    pcall(fs.SetPoint, fs, "RIGHT", frame, "RIGHT", v.right, 0)
    pcall(fs.SetWidth, fs, v.width)
end

local function labelFor(v, frame)
    local fs = v.labels[frame]
    if fs then place(v, fs, frame) return fs end
    local mk = get(frame, "CreateFontString")
    if type(mk) ~= "function" then return nil end
    local ok
    ok, fs = pcall(mk, frame, nil, "OVERLAY", "GameFontHighlightSmall")
    if not ok or not fs then return nil end
    place(v, fs, frame)
    pcall(fs.SetJustifyH, fs, "RIGHT")
    pcall(fs.SetWordWrap, fs, false)
    v.labels[frame] = fs
    if not v.hooked[frame] and type(get(frame, "HookScript")) == "function" then
        v.hooked[frame] = true
        pcall(frame.HookScript, frame, "OnEnter", onEnterFor(v))
    end
    return fs
end

local function hideRow(v, frame)
    v.rowEval[frame] = nil
    local fs = v.labels[frame]
    if fs then pcall(fs.Hide, fs) end
end

local function updateRow(v, frame, elementData, deps)
    if not frame then return end
    if not enabled(v) then hideRow(v, frame) return end
    deps = deps or R.deps()
    local info = rowInfo(v, frame, elementData)
    local okE, e, why
    if v.kind == "browse" then
        -- one valuation per item key and price while Min profit and skill stay the same (lag fix 2026-11-21)
        local k = type(info) == "table" and type(info.itemKey) == "table" and
            (tostring(info.itemKey.itemID) .. ":" .. tostring(info.itemKey.itemLevel) .. ":" .. tostring(info.itemKey.itemSuffix)
            .. ":" .. tostring(info.minPrice)) or nil
        local hit = k and v.cache[k]
        if hit ~= nil then okE, e = true, hit or nil
        else
            v.valued = v.valued + 1
            okE, e, why = pcall(R.browse, info, deps)
            if okE and why == "await" then v.awaiting = true
            elseif okE and k then v.cache[k] = e or false end
        end
    else okE, e = pcall(R.evaluate, info, deps, get(get(v.owner, "itemKey"), "itemID")) end
    if not okE or not e then hideRow(v, frame) return end
    local fs = labelFor(v, frame)
    if not fs then return end
    v.rowEval[frame] = e
    local text, color
    if v.kind == "browse" then text, color = R.browseLabel(e) else text, color = R.label(e) end
    pcall(fs.SetText, fs, text)
    pcall(fs.SetTextColor, fs, color[1], color[2], color[3])
    pcall(fs.Show, fs)
end

local function placeHeader(v)
    local h = v.header
    if not h then return end
    local hc = get(v.list, "HeaderContainer")
    pcall(h.ClearAllPoints, h)
    if type(hc) == "table" then pcall(h.SetPoint, h, "RIGHT", hc, "RIGHT", v.right, 0)
    else pcall(h.SetPoint, h, "TOPRIGHT", v.list, "TOPRIGHT", v.right, -6) end
end

local function now() return (type(GetTime) == "function" and GetTime()) or 0 end

local function refresh(v)
    if not v.list then return end
    v.refreshes = v.refreshes + 1
    v.awaiting = false
    if v.kind == "browse" then pcall(browseColumn, v) end
    if v.header then placeHeader(v); pcall(v.header.SetShown, v.header, enabled(v)) end
    local okD, deps = pcall(R.deps)
    if not okD then deps = nil end
    local sig = deps and (tostring(deps.margin and deps.margin.min) .. ":" .. tostring(deps.skill)) or ""
    if sig ~= v.cacheSig or now() - v.cacheAt > 60 then v.cache, v.cacheSig, v.cacheAt = {}, sig, now() end
    forEachRow(v, function(frame, elementData) updateRow(v, frame, elementData, deps) end)
end

local function attachView(v, owner, list)
    if type(list) ~= "table" then return false end
    if v.list == list then return true end
    v.list, v.owner, v.header = list, owner, nil
    local hc = get(list, "HeaderContainer")
    local parent = type(hc) == "table" and hc or list
    local mk = get(parent, "CreateFontString")
    if type(mk) == "function" then
        local ok, h = pcall(mk, parent, nil, "OVERLAY", "GameFontNormalSmall")
        if ok and h then pcall(h.SetText, h, HEADER_TEXT); pcall(h.SetJustifyH, h, "RIGHT"); v.header = h; placeHeader(v) end
    end
    local sb = get(list, "ScrollBox")
    if type(sb) == "table" and type(ScrollUtil) == "table" then
        if type(ScrollUtil.AddInitializedFrameCallback) == "function" then
            -- no iterateExisting: Blizzard calls that pass without the owner argument
            pcall(ScrollUtil.AddInitializedFrameCallback, sb, function(_, frame, elementData)
                pcall(updateRow, v, frame, elementData)
            end, cbOwner, false)
        end
        if type(ScrollUtil.AddReleasedFrameCallback) == "function" then
            pcall(ScrollUtil.AddReleasedFrameCallback, sb, function(_, frame) pcall(hideRow, v, frame) end, cbOwner)
        end
    end
    if type(get(list, "HookScript")) == "function" then
        pcall(list.HookScript, list, "OnShow", function() pcall(refresh, v) end)
    end
    refresh(v)
    return true
end

local function attach()
    local ah = AuctionHouseFrame
    local brf = get(ah, "BrowseResultsFrame")
    attachView(views.browse, brf, get(brf, "ItemList"))
    local ibf = get(ah, "ItemBuyFrame")
    attachView(views.buy, ibf, get(ibf, "ItemList"))
end

local function later(fn)
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        if pcall(C_Timer.After, 0, fn) then return end
    end
    pcall(fn)
end

local function ahLoaded()
    local fn = (type(C_AddOns) == "table" and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if type(fn) ~= "function" then return false end
    local ok, loaded = pcall(fn, "Blizzard_AuctionHouseUI")
    return ok and loaded and true or false
end

-- true unless the client says the list is hidden (no redraw work for item info that arrives while the AH is closed)
local function visible(v)
    if not v.list then return false end
    local fn = get(v.list, "IsVisible")
    if type(fn) ~= "function" then return true end
    local ok, s = pcall(fn, v.list)
    return not ok or s and true or false
end

local function refreshAll() for _, v in pairs(views) do v.cache = {}; pcall(refresh, v) end end

-- At most one refresh per list per 0.25 s, however many events arrive (browse paging, item info storms).
local function schedule(v)
    if v.pending then return end
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        v.pending = true
        if pcall(C_Timer.After, 0.25, function() v.pending = false; pcall(refresh, v) end) then return end
        v.pending = false
    end
    pcall(refresh, v)
end
R.schedule = schedule
R.views, R.refreshAll = views, refreshAll

P.Mod.listen("ahrows", function() refreshAll() end)

local ev = CreateFrame("Frame")
R.frame = ev
for _, e in ipairs({ "ADDON_LOADED", "AUCTION_HOUSE_SHOW", "ITEM_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_ADDED",
    "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "GET_ITEM_INFO_RECEIVED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "Blizzard_AuctionHouseUI" or (arg1 == "Pricewatch" and ahLoaded()) then pcall(attach) end
    elseif event == "AUCTION_HOUSE_SHOW" then
        pcall(attach)
    elseif on() then
        if event == "GET_ITEM_INFO_RECEIVED" then
            -- only a list that showed a row waiting for item info is redrawn
            for _, v in pairs(views) do if v.awaiting and visible(v) then schedule(v) end end
            return
        end
        local v = event:find("BROWSE", 1, true) and views.browse or views.buy
        if visible(v) then schedule(v) end
    end
end)
