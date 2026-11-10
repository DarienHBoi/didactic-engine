local _,ns=...
local U=ns.UI
function U.RegisterSettings()
 if U.settingsCategory or not ns.enabled or not ns.db then return end
 -- Registration is retried on ADDON_LOADED if the native Settings UI loads later.
 if not Settings or not Settings.RegisterVerticalLayoutCategory or not Settings.RegisterProxySetting
  or not Settings.CreateCheckbox or not Settings.RegisterAddOnCategory then return end
 local category=Settings.RegisterVerticalLayoutCategory("GearWise")
 if Settings.CreateDropdown and Settings.CreateControlTextContainer then
  local language=Settings.RegisterProxySetting(category,"GearWiseLanguage",Settings.VarType.String,ns.L("Sprache"),"auto",
   function() return ns.db.settings.language or "auto" end,ns.Locale.Set)
  Settings.CreateDropdown(category,language,function()
   local choices=Settings.CreateControlTextContainer()
   for _,entry in ipairs(ns.Locale.choices) do choices:Add(entry.id,ns.L(entry.name)) end
   return choices:GetData()
  end,ns.L("Sprache für GearWise. Nach Änderung /reload ausführen. Namen, Chatlinks und originale Tooltips bleiben in der Spielsprache."))
 end
 local function checkbox(key,title,default,hint,changed)
  local variable="GearWise"..key:gsub("^%l",string.upper)
  local setting=Settings.RegisterProxySetting(category,variable,Settings.VarType.Boolean,title,default,
   function() local value=ns.db.settings[key];if value==nil then return default end;return value end,
   function(value) ns.db.settings[key]=not not value;if changed then changed() end end)
  Settings.CreateCheckbox(category,setting,hint..ns.L("\n\nGilt für alle Charaktere und wird sofort übernommen."))
 end
 checkbox("chatLinkQuantity",ns.L("Menge beim Verlinken im Chat anzeigen"),true,
  ns.L("Shift + Linksklick auf Material oder einen Warenkorbeintrag.\n\nAktiviert: 8 × [Großer glänzender Splitter]\nDeaktiviert: [Großer glänzender Splitter]"))
 checkbox("showMinimap",ns.L("Minimap-Symbol anzeigen"),true,
  ns.L("Linksklick öffnet den Planer, Rechtsklick die Einkaufsliste. Die Optionen bleiben über /gw options erreichbar."),U.RefreshMinimap)
 checkbox("showIndicators",ns.L("Hinweise an Ausrüstungsplätzen anzeigen"),true,
  ns.L("Zeigt die anklickbaren GearWise-Siegel im Charakterfenster."),U.RefreshIndicators)
 checkbox("onlyUpgradeIndicators",ns.L("Nur Hinweise für bessere Verzauberungen anzeigen"),false,
  ns.L("Zeigt nur Slots mit einer aktuell nutzbaren, höher bewerteten Verbesserung für deine gewählte Skillung. Unklare Vergleiche werden ausgeblendet."),U.RefreshIndicators)
 checkbox("showRecipeHints",ns.L("GearWise-Hinweise im Berufefenster anzeigen"),true,
  ns.L("Ergänzt bekannte Verzauberungsrezepte um passende Skillungen und konkrete Boni."),function() if ns.RecipeHints then ns.RecipeHints.Refresh() end end)
 checkbox("showCartContributions",ns.L("Warenkorb: Materialbeiträge je Rezept anzeigen"),true,
  ns.L("Zeigt beim Überfahren eines Materials die Beiträge der einzelnen Rezepte."),U.RefreshCart)
 checkbox("autoPriceImport",ns.L("Auctionator-Preise automatisch übernehmen"),true,
  ns.L("Aus: GearWise behält die übernommenen Preise. Manuell laden über „Preise importieren“ oben in der Einkaufsliste oder im Schnellzugriff."),U.RefreshPrices)
 checkbox("showPriceAge",ns.L("Alter der gespeicherten AH-Preise anzeigen"),true,
  ns.L("Zeigt beim Überfahren eines Materials das von Auctionator gemeldete Preisalter."),U.Refresh)
 if Settings.CreateDropdown and Settings.CreateControlTextContainer then
  local setting=Settings.RegisterProxySetting(category,"GearWiseRecommendationSort",Settings.VarType.String,
   ns.L("Empfehlungen sortieren (dieser Charakter)"),"relevance",function() return U.SortMode() end,U.ChooseSort)
  Settings.CreateDropdown(category,setting,function()
   local options=Settings.CreateControlTextContainer()
   options:Add("relevance",ns.L("Relevanz"));options:Add("cheapest",ns.L("Günstigste zuerst"))
   options:Add("expensive",ns.L("Teuerste zuerst"));options:Add("all",ns.L("Alle · nach Name"))
   return options:GetData()
  end,ns.L("Entspricht der Sortierung im Empfehlungsfenster. Unvollständige Preise stehen bei Preissortierung zuletzt."))
 end
 if Settings.RegisterCanvasLayoutSubcategory then U.RegisterSettingsShortcuts(category) end
 Settings.RegisterAddOnCategory(category)
 U.settingsCategory=category
end
function U.OpenSettings()
 U.RegisterSettings()
 if U.settingsCategory and Settings and Settings.OpenToCategory then
  Settings.OpenToCategory(U.settingsCategory:GetID())
  if SettingsPanel then
   if not U.settingsWindowHooked then
    SettingsPanel:HookScript("OnHide",ns.Shopping.WindowHidden)
    U.settingsWindowHooked=true
   end
   ns.Shopping.WindowShown(SettingsPanel)
  end
 else
  ns.Print(ns.L("Die Spieloptionen sind noch nicht verfügbar."))
 end
end

function U.RegisterSettingsShortcuts(category)
 local panel=CreateFrame("Frame",nil,UIParent);panel:Hide()
 panel:HookScript("OnShow",ns.Shopping.WindowShown)
 panel:HookScript("OnHide",ns.Shopping.WindowHidden)
 local title=panel:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
 ns.Theme.Font(title);title:SetPoint("TOPLEFT",20,-20);title:SetText(ns.L("GearWise · Schnellzugriff"))
 local hint=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
 ns.Theme.Font(hint);hint:SetPoint("TOPLEFT",20,-55);hint:SetText(ns.L("Öffne GearWise auch bei ausgeblendetem Minimap-Symbol."))
 panel.buttons={}
 for i,action in ipairs({{ns.L("Planer & Rezepte öffnen"),U.OpenPlanner},{ns.L("Einkaufsliste öffnen"),U.OpenCart},{ns.L("Empfehlungen öffnen"),U.Open},{ns.L("Preise importieren"),U.ImportPrices}}) do
  local open=action[2]
  local button=CreateFrame("Button",nil,panel,"BackdropTemplate");button:SetSize(290,32);button:SetPoint("TOPLEFT",20,-85-(i-1)*46)
  local text=button:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");text:SetPoint("CENTER");button:SetFontString(text);button:SetText(action[1])
  ns.Theme.Button(button)
  button:SetScript("OnEnter",function(self) ns.Theme.Button(self,true) end)
  button:SetScript("OnLeave",function(self) ns.Theme.Button(self) end)
  button:SetScript("OnClick",function() if SettingsPanel then SettingsPanel:Hide() end;open() end)
  panel.buttons[i]=button
 end
 U.settingsShortcuts=panel
 U.settingsShortcutsCategory=Settings.RegisterCanvasLayoutSubcategory(category,panel,ns.L("Schnellzugriff"))
end
