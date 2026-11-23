local _, S = ...
S.Customers = {}
S.Customers.MAX = 100
S.Customers.MAX_MSGS = 60
S.Customers.STATUSES = { "new", "quoted", "waiting", "done" }

local function valid(status)
    for _, s in ipairs(S.Customers.STATUSES) do if s == status then return true end end
    return false
end

local function prune(customers, keepName, keepName2)
    local count = 0
    for _ in pairs(customers) do count = count + 1 end
    while count > S.Customers.MAX do
        local victim
        for name, c in pairs(customers) do
            if name ~= keepName and name ~= keepName2 then
                local better = false
                if not victim then
                    better = true
                else
                    local v = customers[victim]
                    local cDone, vDone = c.status == "done", v.status == "done"
                    if cDone ~= vDone then better = cDone
                    else better = c.last < v.last end
                end
                if better then victim = name end
            end
        end
        if not victim then return end
        customers[victim] = nil
        count = count - 1
    end
end

-- Records one whisper. Returns the customer and whether this was a brand-new incoming customer.
function S.Customers.record(db, name, text, outgoing, now, protect)
    if type(name) ~= "string" or name == "" or type(text) ~= "string" or text == "" then return nil end
    db.customers = db.customers or {}
    local c = db.customers[name]
    local created = c == nil
    -- A whisper you send to a stranger does not make them a customer; they have to answer first.
    if created and outgoing then return nil end
    if created then
        c = { name = name, status = "new", note = "", first = now, last = now, unread = false, msgs = {} }
        db.customers[name] = c
        prune(db.customers, name, protect)
    end
    c.msgs[#c.msgs + 1] = { t = now, out = outgoing and true or false, text = text:sub(1, 255) }
    while #c.msgs > S.Customers.MAX_MSGS do table.remove(c.msgs, 1) end
    c.last = now
    if not outgoing then c.unread = true end
    return c, created and not outgoing
end

function S.Customers.setStatus(db, name, status)
    local c = db.customers and db.customers[name]
    if not c or not valid(status) then return false end
    c.status = status
    return true
end

function S.Customers.setNote(db, name, note)
    local c = db.customers and db.customers[name]
    if not c then return false end
    c.note = tostring(note or ""):sub(1, 200)
    return true
end

function S.Customers.markRead(db, name)
    local c = db.customers and db.customers[name]
    if c then c.unread = false end
end

function S.Customers.unreadCount(db)
    local n = 0
    for _, c in pairs(db.customers or {}) do if c.unread then n = n + 1 end end
    return n
end

-- Newest activity first, ties by name.
function S.Customers.list(db)
    local out = {}
    for _, c in pairs(db.customers or {}) do out[#out + 1] = c end
    table.sort(out, function(a, b)
        if a.last ~= b.last then return a.last > b.last end
        return a.name < b.name
    end)
    return out
end

-- Remembers which enchant and price was quoted; a quote moves a new customer to "quoted".
function S.Customers.setQuote(db, name, key, price)
    local c = db.customers and db.customers[name]
    if not c or type(key) ~= "string" or type(price) ~= "number" then return false end
    c.quote = { key = key, price = price }
    if c.status == "new" then c.status = "quoted" end
    return true
end

-- You whispered someone you sought out (Whisper target): they are a quoted customer straight away. The whisper itself
-- is recorded by CHAT_MSG_WHISPER_INFORM, which needs the customer to exist first.
function S.Customers.pitch(db, name, key, price, now, protect)
    if type(name) ~= "string" or name == "" or type(key) ~= "string" or type(price) ~= "number" then return nil end
    db.customers = db.customers or {}
    local c = db.customers[name]
    if not c then
        c = { name = name, status = "quoted", note = "", first = now, last = now, unread = false, msgs = {} }
        db.customers[name] = c
        prune(db.customers, name, protect)
    end
    c.quote = { key = key, price = price }
    c.status = "quoted"
    c.last = now
    return c
end

-- Marks done. The first time, a quoted price is added to that enchant sales history.
function S.Customers.complete(db, name, now)
    local c = db.customers and db.customers[name]
    if not c then return false end
    local first = c.status ~= "done"
    c.status = "done"
    if first and c.quote then
        db.sales = db.sales or {}
        local list = db.sales[c.quote.key] or {}
        S.Sales.add(list, c.quote.price, now)
        S.Ledger.add(db, name, c.quote.price, c.quote.key, now, "manual")
        db.sales[c.quote.key] = list
        c.quote = nil -- logged once: Done, Waiting, Done must not log it again
        return true
    end
    return false
end

-- Whisper text is untrusted: flatten hyperlinks to their label, drop colour codes, escape every other pipe.
function S.Customers.display(text)
    if type(text) ~= "string" then return "" end
    text = text:gsub("|H[^|]*|h(.-)|h", "%1")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|", "||")
    return text
end

-- Hides the realm part when it is the owner own realm.
function S.Customers.shortName(name, realm)
    if type(name) ~= "string" then return "" end
    if realm and realm ~= "" then
        local base, r = name:match("^(.-)%-([^%-]+)$")
        if base and r:gsub("%s", "") == realm:gsub("%s", "") then return base end
    end
    return name
end
