-- Bind on Forever Guide: sell your gray items when you open a vendor (opt-in: settings.sellGrays; the RestedXP
-- audit, Oct 18). Blizzard's own "sell all junk" (C_MerchantFrame.SellAllJunkItems), so everything sold can be bought
-- back from the vendor's Buyback tab as usual. Never with a modifier key held.
local _, ns = ...

ns.On('MERCHANT_SHOW', function()
  if not (ns.settings and ns.settings.sellGrays) then return end
  if IsShiftKeyDown and (IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown()) then return end
  local mf = C_MerchantFrame
  if not (mf and mf.SellAllJunkItems and mf.GetNumJunkItems) then return end
  local n = ns.clean(mf.GetNumJunkItems()) or 0
  if n <= 0 then return end
  local ok = pcall(mf.SellAllJunkItems)
  if ok then ns.say(ns.count('soldGrays', n)) end
end)
