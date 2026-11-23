--------------------------------------------------------------------------------
-- Translations. ns.L["English text"] is the text in the client's language: the English is the
-- key, and what shows when there's no translation. Only the client's own language's file loads
-- (the toc's AllowLoadTextLocale), and fills ns.L in.
--------------------------------------------------------------------------------

local _, ns = ...
ns.L = setmetatable({}, { __index = function(_, k) return k end })
