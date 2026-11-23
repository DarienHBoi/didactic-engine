local _, S = ...
S.Target = {}

-- The whisper name of your target ("Name" or "Name-Realm"), or nil and a reason. env defaults to the game globals.
local function read(env)
    if not env.UnitExists("target") then return nil, "Target a player first." end
    if not env.UnitIsPlayer("target") then return nil, "Your target is not a player." end
    if env.UnitIsUnit("target", "player") then return nil, "That's you." end
    local name, realm = env.UnitName("target")
    local secret = env.issecretvalue
    if secret and (secret(name) or (realm ~= nil and secret(realm))) then return nil, "Can't read your target's name right now." end
    if type(name) ~= "string" or name == "" then return nil, "Can't read your target's name." end
    if env.UnitFactionGroup("target") ~= env.UnitFactionGroup("player") then
        return nil, "Your target is the other faction: whispers won't reach them."
    end
    if type(realm) == "string" and realm ~= "" then return name .. "-" .. realm end
    return name
end

function S.Target.name(env)
    env = env or _G
    if type(env.UnitExists) ~= "function" or type(env.UnitName) ~= "function" then return nil, "Targeting isn't available here." end
    local ok, name, why = pcall(read, env)
    if not ok then return nil, "Can't read your target right now." end
    return name, why
end

-- Button text: "Whisper Zed" for a target, else "Whisper target".
function S.Target.label(name)
    if type(name) ~= "string" or name == "" then return "Whisper target" end
    local short = name:match("^([^%-]+)") or name
    if #short > 10 then short = short:sub(1, 9) .. ".." end
    return "Whisper " .. short
end
