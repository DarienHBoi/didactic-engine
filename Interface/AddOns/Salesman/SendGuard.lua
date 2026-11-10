local _, S = ...
S.SendGuard = {}
S.SendGuard.__index = S.SendGuard

local COOLDOWN, DUPLICATE = 3, 60

function S.SendGuard.new(now)
    return setmetatable({ now = now, lastAny = nil, lastAt = {}, lastText = {} }, S.SendGuard)
end

-- A clock that steps backwards is re-based to now, so the cooldown still blocks and never locks out.
function S.SendGuard:check(key, text)
    local t = self.now()
    if self.lastAny and t < self.lastAny then
        self.lastAny = t
        for k in pairs(self.lastAt) do self.lastAt[k] = t end
    end
    if self.lastAny and t - self.lastAny < COOLDOWN then return "cooldown" end
    local last = self.lastAt[key]
    if last and self.lastText[key] == text and t - last < DUPLICATE then return "confirm" end
    return "ok"
end

function S.SendGuard:record(key, text)
    if key == nil then return end
    local t = self.now()
    self.lastAny = t
    self.lastAt[key] = t
    self.lastText[key] = text
end
