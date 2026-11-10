local _, S = ...
S.Channels = {}

local FIXED = {
    { key = "SAY", label = "Say", chatType = "SAY" },
    { key = "YELL", label = "Yell", chatType = "YELL" },
    { key = "GUILD", label = "Guild", chatType = "GUILD" },
    { key = "PARTY", label = "Party", chatType = "PARTY" },
}

function S.Channels.list(joined)
    local out = {}
    for _, c in ipairs(joined or {}) do
        if c.name and not c.disabled then
            out[#out + 1] = { key = "CHANNEL:" .. c.name, label = tostring(c.id) .. ". " .. c.name,
                              chatType = "CHANNEL", channelID = c.id }
        end
    end
    for _, f in ipairs(FIXED) do out[#out + 1] = f end
    return out
end

function S.Channels.canSend(list, key)
    for _, e in ipairs(list) do
        if e.key == key then return true end
    end
    return false, "not in that channel"
end
