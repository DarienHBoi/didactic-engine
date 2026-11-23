-- !ChatClickWatch: keeps chat clickable. At login it undoes the chat tab's "Make Uninteractable" (the saved flag and
-- the applied state) on every chat window, and saves the change. Fix-only since 2026-11-22: the earlier recorder hooked
-- every chat window's mouse/script calls and took a stack trace each time, which cost 3.75 ms per frame (/nk perf).
local function fixChat()
    local fixed = {}
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        local ok, saved = pcall(function() return select(10, GetChatWindowInfo(i)) end)
        if (ok and saved) or (cf and cf.isUninteractable) then
            pcall(SetChatWindowUninteractable, i, false)
            if cf and FCF_SetUninteractable then pcall(FCF_SetUninteractable, cf, false) end
            fixed[#fixed + 1] = "ChatFrame" .. i
        end
    end
    return fixed
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event)
    if event ~= "PLAYER_LOGIN" then return end
    C_Timer.After(5, function()
        local fixed = fixChat()
        if #fixed > 0 then
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffChatClickWatch:|r made " .. table.concat(fixed, ", ") .. " clickable again.")
        end
    end)
end)
