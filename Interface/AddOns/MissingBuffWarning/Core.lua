local ADDON, ns = ...

----------------------------------------------------------------------
-- Data: built-in class buffs. `auras` = aura names that count as "up"
-- (group versions included). `spell` is used to look up the icon and to
-- check that your character actually knows the spell. `group` = default
-- display group: SELF (only you), GROUP (you and your party), OPTIONAL.
----------------------------------------------------------------------
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
ns.QUESTION = QUESTION

ns.BUILTIN = {
    PRIEST = {
        { key = "INNERFIRE",  label = "Inner Fire",            spell = "Inner Fire", group = "SELF",
          auras = { "Inner Fire" }, icon = "Interface\\Icons\\Spell_Holy_InnerFire", default = true },
        { key = "FORTITUDE",  label = "Power Word: Fortitude", spell = "Power Word: Fortitude", group = "GROUP",
          auras = { "Power Word: Fortitude", "Prayer of Fortitude" },
          icon = "Interface\\Icons\\Spell_Holy_WordFortitude", default = true },
        { key = "SPIRIT",     label = "Divine Spirit",         spell = "Divine Spirit", group = "GROUP",
          auras = { "Divine Spirit", "Prayer of Spirit" },
          icon = "Interface\\Icons\\Spell_Holy_DivineSpirit", default = false },
        { key = "SHADOWPROT", label = "Shadow Protection",     spell = "Shadow Protection", group = "GROUP",
          auras = { "Shadow Protection", "Prayer of Shadow Protection" },
          icon = "Interface\\Icons\\Spell_Shadow_AntiShadow", default = false },
        { key = "SHADOWFORM", label = "Shadowform",            spell = "Shadowform", group = "OPTIONAL",
          auras = { "Shadowform" }, icon = "Interface\\Icons\\Spell_Shadow_Shadowform", default = false },
    },
}

ns.GROUPS = { "SELF", "GROUP", "OPTIONAL" }
ns.GROUP_NAMES = { SELF = "Self", GROUP = "Group", OPTIONAL = "Optional" }

----------------------------------------------------------------------
-- Saved variables (version 2 = compact display). Old settings migrate:
-- scale, position, lock, chosen buffs and minimap button are kept.
----------------------------------------------------------------------
local DEFAULTS = {
    scale = 1, locked = true,
    layout = "list",             -- "list" (A), "strip" (B), "panels" (old big panels)
    iconSize = 16, spacing = 2, fontSize = 12, growUp = false,
    showBg = true, bgAlpha = 0.6, showBorder = true, headerColor = "gold", redEdge = true,
    showWho = true,
    showInCombat = true, onlyInGroup = false, whenNone = "hide",
}
ns.DEFAULTS = DEFAULTS

function ns.InitDB()
    MissingBuffWarningDB = MissingBuffWarningDB or {}
    local db = MissingBuffWarningDB
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    db.classes = db.classes or {}
    db.collapsed = db.collapsed or {}
    if (db.version or 1) < 2 then
        db.probe = nil       -- leftovers of earlier debugging builds
        db.diag = nil
        db.version = 2
    end
    ns.db = db
end

function ns.ClassConfig(class)
    local c = ns.db.classes[class]
    if not c then
        c = {}
        ns.db.classes[class] = c
    end
    c.enabled = c.enabled or {}
    c.manual = c.manual or {}
    c.groups = c.groups or {}
    return c
end

function ns.IsBuiltinEnabled(class, entry)
    local v = ns.ClassConfig(class).enabled[entry.key]
    if v == nil then return entry.default end
    return v
end

function ns.PlayerClass()
    local _, class = UnitClass("player")
    return class
end

function ns.ManualKey(label) return "M:" .. string.lower(label) end

----------------------------------------------------------------------
-- Pure logic (no UI) - easy to test
----------------------------------------------------------------------
-- Returns name, iconID, spellID for a known spell (name or id), else nil.
function ns.ResolveSpell(nameOrId)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, nameOrId)
        if ok and info then return info.name, info.iconID, info.spellID end
    end
    return nil
end

-- Passive spells (racial passives etc.) cannot be cast, so they get no click button.
function ns.IsPassive(spellID)
    if not spellID then return false end
    if C_Spell and C_Spell.IsSpellPassive then
        local ok, r = pcall(C_Spell.IsSpellPassive, spellID)
        if ok then return r and true or false end
    end
    if IsPassiveSpell then
        local ok, r = pcall(IsPassiveSpell, spellID)
        if ok then return r and true or false end
    end
    return false
end

-- Build the list of buffs to watch for this class.
function ns.BuildTracked(class, resolve)
    local out, seen = {}, {}
    local cfg = ns.ClassConfig(class)
    for _, e in ipairs(ns.BUILTIN[class] or {}) do
        if ns.IsBuiltinEnabled(class, e) then
            local name, icon = resolve(e.spell)
            -- only watch spells this character has learned
            if name then
                seen[string.lower(e.label)] = true
                out[#out + 1] = { key = e.key, label = e.label, auras = e.auras, icon = icon or e.icon,
                                  castable = true, group = cfg.groups[e.key] or e.group or "SELF" }
            end
        end
    end
    for _, m in ipairs(cfg.manual) do
        if m.enabled ~= false then
            local name, icon, sid = resolve(tonumber(m.input) or m.input)
            -- "Name(Rank 1)" / "Name (Racial Passive)": the buff itself is just "Name"
            local plain = (string.gsub(m.input, "%s*%b()", ""))
            if not name and plain ~= "" and plain ~= m.input then name, icon, sid = resolve(plain) end
            local passive = name ~= nil and ns.IsPassive(sid)
            local label = name or m.input
            -- same spell added twice (by name and by ID, or also built in): warn once
            if not seen[string.lower(label)] then
                seen[string.lower(label)] = true
                local auras = { label }
                if m.input ~= label then auras[#auras + 1] = m.input end
                if plain ~= "" and plain ~= label and plain ~= m.input then auras[#auras + 1] = plain end
                local key = ns.ManualKey(label)
                out[#out + 1] = { key = key, label = label, auras = auras, icon = icon or QUESTION,
                                  castable = (name ~= nil) and not passive,   -- known, non-passive only
                                  passive = passive, group = cfg.groups[key] or "SELF" }
            end
        end
    end
    return out
end

local function hasAny(t, have)
    for _, a in ipairs(t.auras) do
        if have[a] then return true end
    end
    return false
end

-- tracked: list from BuildTracked; have: set of aura names currently up.
function ns.FindMissing(tracked, have)
    local missing = {}
    for _, t in ipairs(tracked) do
        if not hasAny(t, have) then missing[#missing + 1] = t end
    end
    return missing
end

-- Set of a unit's helpful aura names. Second result true = the game hid names (combat
-- rules) or refused the read, so the answer can't be trusted. nil = no aura API.
function ns.ReadUnitBuffs(unit)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    local have, secret, total, hidden = {}, false, 0, 0
    for i = 1, 100 do
        -- The call itself can throw "Auras cannot be accessed when secret while tainted"
        -- (boss encounters). Treat that like hidden names.
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
        if not ok then
            return have, true, total, hidden + 1
        end
        if not a then break end
        total = total + 1
        local n = a.name
        if n and issecretvalue and issecretvalue(n) then
            secret = true            -- the game is hiding this aura's name (combat rules)
            hidden = hidden + 1
        elseif n then
            have[n] = true
        end
    end
    return have, secret, total, hidden
end

function ns.ReadPlayerBuffs() return ns.ReadUnitBuffs("player") end

-- Party/raid members other than you, as unit tokens.
local function groupUnits()
    local out = {}
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do
            local u = "raid" .. i
            if UnitExists(u) and not UnitIsUnit(u, "player") then out[#out + 1] = u end
        end
    elseif IsInGroup and IsInGroup() then
        for i = 1, 4 do
            local u = "party" .. i
            if UnitExists(u) then out[#out + 1] = u end
        end
    end
    return out
end

-- Who in the group is missing each GROUP buff. Out of combat only; in combat (or when the
-- game hides a member's aura names) the last known state is kept rather than guessed.
-- Result: party[key] = { total, have, who = { {name, unit}, ... } } (total includes you).
ns.party = {}
local memberCache = {}     -- unit .. "\0" .. name -> last trusted aura set
function ns.ScanParty(tracked)
    if InCombatLockdown() then return ns.party end
    local units = groupUnits()
    local sets = {}
    local mine = ns.ReadUnitBuffs("player") or {}
    local seenNow = {}
    for _, u in ipairs(units) do
        if UnitIsConnected(u) and not UnitIsDeadOrGhost(u) then
            local name = UnitName(u) or u
            local id = u .. "\0" .. name
            local have, secret = ns.ReadUnitBuffs(u)
            if have and not secret then memberCache[id] = have end
            seenNow[id] = true
            if memberCache[id] then sets[#sets + 1] = { unit = u, name = name, have = memberCache[id] } end
        end
    end
    for id in pairs(memberCache) do if not seenNow[id] then memberCache[id] = nil end end
    local out = {}
    for _, t in ipairs(tracked) do
        if t.group == "GROUP" and #units > 0 then
            local r = { total = 1, have = hasAny(t, mine) and 1 or 0, who = {} }
            for _, m in ipairs(sets) do
                r.total = r.total + 1
                if hasAny(t, m.have) then r.have = r.have + 1
                else r.who[#r.who + 1] = { name = m.name, unit = m.unit } end
            end
            out[t.key] = r
        end
    end
    ns.party = out
    return out
end

-- What the display shows: groups in fixed order, each with its missing items.
-- A GROUP buff is listed when you miss it, or (show-who on) anyone in the party does.
function ns.BuildView(tracked, have, party)
    local byGroup, count = {}, 0
    local showWho = ns.db.showWho
    for _, t in ipairs(tracked) do
        local playerMissing = not hasAny(t, have)
        local p = (showWho and t.group == "GROUP" and party) and party[t.key] or nil
        local who = p and p.who or {}
        if playerMissing or #who > 0 then
            local it = { key = t.key, label = t.label, icon = t.icon, group = t.group, castable = t.castable,
                         passive = t.passive, playerMissing = playerMissing, who = who }
            if p then
                it.total = p.total
                it.have = p.have
            end
            byGroup[t.group] = byGroup[t.group] or {}
            table.insert(byGroup[t.group], it)
            count = count + 1
        end
    end
    local view = { count = count, groups = {} }
    for _, g in ipairs(ns.GROUPS) do
        if byGroup[g] then
            view.groups[#view.groups + 1] = { id = g, name = ns.GROUP_NAMES[g], items = byGroup[g] }
        end
    end
    return view
end

-- "show", "fade" or "hide" for the whole display.
function ns.Visibility(view)
    local db = ns.db
    if not db.locked then return "show" end      -- unlocked: layout preview
    if UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then return "hide" end
    if (InCombatLockdown() or ns.enteringCombat) and not db.showInCombat then return "hide" end
    if db.onlyInGroup and not (IsInGroup and IsInGroup()) then return "hide" end
    if view.count == 0 then return db.whenNone == "fade" and "fade" or "hide" end
    return "show"
end

-- Preview while unlocked: every tracked buff shown as missing, so size/position can be set.
local function previewView(tracked)
    local view = ns.BuildView(tracked, {}, nil)
    if view.count == 0 then
        view = { count = 1, groups = { { id = "SELF", name = "Self", items = {
            { key = "EXAMPLE", label = "Example Buff", icon = QUESTION, group = "SELF", who = {},
              playerMissing = true } } } } }
    end
    return view
end

----------------------------------------------------------------------
-- Refresh
----------------------------------------------------------------------
local function refreshReal()
    if not (ns.db and ns.Render) then return end
    local class = ns.PlayerClass()
    local tracked = ns.BuildTracked(class, ns.ResolveSpell)
    local view
    if not ns.db.locked then
        view = previewView(tracked)
    else
        local have, secret = ns.ReadPlayerBuffs()
        if not have then return end
        -- if the game hides some buff names right now we can't tell: keep what is on screen
        if secret then return end
        local party = ns.party
        if ns.db.showWho and not InCombatLockdown() then party = ns.ScanParty(tracked) end
        view = ns.BuildView(tracked, have, party)
    end
    ns.lastView = view
    ns.Render(view, ns.Visibility(view))
end

-- Errors are printed once to chat instead of failing silently (script errors are often hidden).
local lastErr
function ns.Refresh()
    local ok, err = pcall(refreshReal)
    if not ok and err ~= lastErr then
        lastErr = err
        print("|cffff4444MissingBuffWarning error:|r " .. tostring(err))
    end
    return ok
end

-- /mbw test: show sample warnings for a few seconds, whatever buffs you have
function ns.TestFlash()
    local ok, err = pcall(function()
        ns.Render(previewView(ns.BuildTracked(ns.PlayerClass(), ns.ResolveSpell)), "show")
    end)
    if ok then
        print("|cffffd200MBW|r test warning shown for 8 seconds.")
        C_Timer.After(8, ns.Refresh)
    else
        print("|cffff4444MissingBuffWarning error:|r " .. tostring(err))
    end
end

local pending
function ns.QueueRefresh()
    if pending then return end
    pending = true
    C_Timer.After(0.25, function() pending = false; ns.Refresh() end)
end

----------------------------------------------------------------------
-- Events and slash commands
----------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        self:UnregisterEvent("ADDON_LOADED")
        ns.InitDB()
        ns.BuildDisplay()
        ns.ApplyPosition()
        ns.SetLocked(ns.db.locked)
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        self:RegisterEvent("PLAYER_DEAD")
        self:RegisterEvent("PLAYER_ALIVE")
        self:RegisterEvent("PLAYER_UNGHOST")
        self:RegisterEvent("SPELLS_CHANGED")
        self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        self:RegisterEvent("GROUP_ROSTER_UPDATE")
        self:RegisterUnitEvent("UNIT_AURA", "player")
        -- safety net: re-check once a second so the warning can never get stuck hidden
        -- (this also re-reads the party's buffs, out of combat only)
        local elapsed = 0
        self:SetScript("OnUpdate", function(_, dt)
            elapsed = elapsed + dt
            if elapsed >= 1 then elapsed = 0; ns.Refresh() end
        end)
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- last moment before combat lockdown: lay out now, so nothing secure must change in combat
        ns.enteringCombat = true
        ns.Refresh()
        ns.enteringCombat = false
    else
        ns.QueueRefresh()
    end
end)

SLASH_MISSINGBUFFWARNING1 = "/mbw"
SLASH_MISSINGBUFFWARNING2 = "/missingbuff"
SlashCmdList["MISSINGBUFFWARNING"] = function(msg)
    msg = string.lower(strtrim and strtrim(msg or "") or (msg or ""))
    if msg == "unlock" then
        ns.SetLocked(false)
    elseif msg == "lock" then
        ns.SetLocked(true)
    elseif msg == "reset" then
        ns.ResetLayout()
    elseif msg == "test" then
        ns.TestFlash()
    elseif msg == "list" or msg == "strip" or msg == "panels" then
        ns.SetOption("layout", msg)
        print("|cffffd200MBW|r layout: " .. msg)
    elseif msg == "linkdebug" then
        ns.linkDebug = not ns.linkDebug
        print("|cffffd200MBW|r linkdebug " .. (ns.linkDebug and "ON" or "OFF")
            .. ". Hooks installed: " .. (#(ns.linkHooks or {}) > 0 and table.concat(ns.linkHooks, ", ") or "NONE")
            .. ". Click the Add box, then shift-click a spell.")
    elseif msg == "debug" then
        local dbgLines = {}
        local function dprint(t) print(t); dbgLines[#dbgLines + 1] = t end
        local class = ns.PlayerClass()
        dprint("|cffffd200MBW debug|r class=" .. tostring(class) .. " scale=" .. string.format("%.2f", ns.db.scale)
            .. " layout=" .. tostring(ns.db.layout))
        for _, e in ipairs(ns.BUILTIN[class] or {}) do
            local name, _, id = ns.ResolveSpell(e.spell)
            dprint(("  %s: enabled=%s known=%s spellID=%s"):format(
                e.label, tostring(ns.IsBuiltinEnabled(class, e)), tostring(name ~= nil), tostring(id)))
        end
        for _, t in ipairs(ns.BuildTracked(class, ns.ResolveSpell)) do
            dprint(("  tracked: %s group=%s castable=%s auras=%s"):format(t.label, t.group, tostring(t.castable),
                table.concat(t.auras, " / ")))
        end
        dprint(("  cast buttons: castOnKeyPress=%s createError=%s"):format(
            tostring(GetCVar and GetCVar("ActionButtonUseKeyDown")), tostring(ns.castError)))
        local shownCells = 0
        for id, c in pairs(ns.cells or {}) do
            if c:IsVisible() then
                shownCells = shownCells + 1
                if c.cast then
                    dprint(("    %s: button spell=%s unit=%s mouse=%s"):format(id,
                        tostring(c.cast:GetAttribute("spell")), tostring(c.cast:GetAttribute("unit")),
                        tostring(c.cast:IsMouseEnabled())))
                end
            end
        end
        for key, p in pairs(ns.party or {}) do
            local names = {}
            for _, w in ipairs(p.who) do names[#names + 1] = w.name end
            dprint(("  party %s: %d/%d missing=%s"):format(key, p.have, p.total, table.concat(names, ", ")))
        end
        local have, secret, total, hidden = ns.ReadPlayerBuffs()
        dprint(("  inCombat=%s auras read=%s names hidden by the game=%s -> display %s"):format(
            tostring(UnitAffectingCombat("player")), tostring(total), tostring(hidden),
            secret and "left unchanged (can't tell)" or "updated normally"))
        local names = {}
        for n in pairs(have or {}) do names[#names + 1] = n end
        table.sort(names)
        dprint(("  state: onTaxi=%s deadOrGhost=%s locked=%s inGroup=%s shownParts=%d"):format(
            tostring(UnitOnTaxi("player")), tostring(UnitIsDeadOrGhost("player")), tostring(ns.db.locked),
            tostring(IsInGroup and IsInGroup()), shownCells))
        dprint("  your buffs: " .. (have and table.concat(names, ", ") or "aura API unavailable"))
        ns.db.lastDebug = dbgLines  -- saved on /reload so it can be read from the settings file

    elseif ns.ToggleOptions then
        ns.ToggleOptions()
    end
end
