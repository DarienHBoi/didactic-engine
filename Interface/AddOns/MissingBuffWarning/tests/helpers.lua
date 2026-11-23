-- shared test helpers: check/eq, boot the addon, set up a priest
local current = "?"
function section(name) current = name end
function check(c, m) report(c and true or false, current .. ": " .. (m or "check")) end
function eq(a, e, m)
    report(a == e, current .. ": " .. (m or "eq") .. " (expected " .. tostring(e) .. ", got " .. tostring(a) .. ")")
end

-- Load the addon like the game: files run with (name, ns), then saved vars, then ADDON_LOADED.
function boot(saved)
    MissingBuffWarningDB = nil
    NS = {}
    for i = 1, #ADDON_FILES do
        local f = assert(loadfile(ADDON_FILES[i]))
        f("MissingBuffWarning", NS)
    end
    MissingBuffWarningDB = saved
    FAKE.fire("ADDON_LOADED", "MissingBuffWarning")
    FAKE.fire("PLAYER_ENTERING_WORLD")
    FAKE.flushTimers()
    return NS
end

function priest()
    FAKE.learn("Inner Fire", 588)
    FAKE.learn("Power Word: Fortitude", 1243)
    FAKE.learn("Divine Spirit", 14752)
    FAKE.learn("Shadow Protection", 976)
    FAKE.learn("Shadowform", 15473)
end

function refresh() NS.Refresh(); FAKE.flushTimers() end

function errorsPrinted()
    local n = 0
    for _, l in ipairs(FAKE.printed) do if l:find("error") then n = n + 1; io.write("  printed: ", l, string.char(10)) end end
    return n
end

function boxVisible()
    local b = MissingBuffWarningFrame
    if not b:IsShown() or b._alpha == 0 then return false end
    if b.bg:IsShown() then return true end
    for _, c in pairs(NS.cells) do if c:IsVisible() then return true end end
    return (b.footer:GetText() or "") ~= ""
end
function cell(id) return NS.cells and NS.cells[id] end
function shown(id) local c = cell(id); return c ~= nil and c:IsVisible() end

function party(list)  -- list of {name, auras...}
    for u in pairs(UNITS) do if u ~= "player" then UNITS[u] = nil; AURAS[u] = nil end end
    for i, p in ipairs(list) do
        local u = "party" .. i
        UNITS[u] = { name = p[1], class = "WARRIOR" }
        AURAS[u] = { unpack(p, 2) }
    end
    INGROUP = #list > 0
end

-- enter combat the way the game does: REGEN_DISABLED fires just before lockdown starts
function enterCombat() FAKE.fire("PLAYER_REGEN_DISABLED"); COMBAT = true; FAKE.flushTimers() end
function leaveCombat() COMBAT = false; FAKE.fire("PLAYER_REGEN_ENABLED"); FAKE.flushTimers() end
