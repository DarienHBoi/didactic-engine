local _,ns=...
-- German source keys remain stable; translated display text never becomes a data ID.
local Q={packs={},code="deDE",ready=false,tracked={}}
ns.Locale=Q
Q.choices={
 {id="auto",name="Automatisch (Spielsprache)"},
 {id="deDE",name="Deutsch"},{id="enUS",name="English"},
 {id="frFR",name="Français"},{id="esES",name="Español"},{id="ruRU",name="Русский"},
}
function Q.Client() return GetLocale and GetLocale() or "deDE" end
function Q.MatchesClient()
 local client=Q.Client()
 if client=="enGB" then client="enUS" elseif client=="esMX" then client="esES" end
 return client==Q.code
end
function Q.Resolve(value)
 if not value or value=="auto" then value=Q.Client() end
 if value=="enGB" then value="enUS" elseif value=="esMX" then value="esES" end
 if value=="deDE" or Q.packs[value] then return value end
 return "enUS"
end
function ns.L(key)
 if key==nil or not Q.ready or Q.code=="deDE" then return key end
 local pack=Q.packs[Q.code] or {}
 return pack[key] or (Q.packs.enUS and Q.packs.enUS[key]) or key
end
-- Register only display tables. Keep original keys so initialization also works
-- when SavedVariables become available after the addon files have been loaded.
function Q.Track(t)
 for key,value in pairs(t) do
  if type(value)=="table" then Q.Track(value)
  elseif key~="german" and type(value)=="string" and Q.packs.enUS[value] then
   Q.tracked[#Q.tracked+1]={owner=t,key=key,source=value}
  end
 end
end
function Q.Initialize()
 Q.code=Q.Resolve(ns.db and ns.db.settings.language)
 Q.ready=true
 for _,entry in ipairs(Q.tracked) do entry.owner[entry.key]=ns.L(entry.source) end
end
function Q.Set(value)
 local valid=false;for _,entry in ipairs(Q.choices) do if entry.id==value then valid=true;break end end
 if not valid or not ns.db then return false end
 ns.db.settings.language=value
 if ns.Theme and ns.Theme.RefreshLanguages then ns.Theme.RefreshLanguages() end
 ns.Print(ns.L("Sprache gespeichert. Bitte /reload ausführen."))
 return true
end
function Q.Decimal(value)
 if Q.code=="enUS" then return value end
 return (value:gsub("%.",","))
end
-- Lua 5.1 string.lower only handles ASCII. Fold Latin accents and Cyrillic
-- explicitly so names from supported clients remain searchable in either case.
local upper={"Ä","Ö","Ü","À","Á","Â","Ã","Å","Æ","Ç","È","É","Ê","Ë","Ì","Í","Î","Ï","Ñ","Ò","Ó","Ô","Õ","Ø","Ù","Ú","Û","Ý","Œ","Ÿ","А","Б","В","Г","Д","Е","Ё","Ж","З","И","Й","К","Л","М","Н","О","П","Р","С","Т","У","Ф","Х","Ц","Ч","Ш","Щ","Ъ","Ы","Ь","Э","Ю","Я"}
local lower={"ä","ö","ü","à","á","â","ã","å","æ","ç","è","é","ê","ë","ì","í","î","ï","ñ","ò","ó","ô","õ","ø","ù","ú","û","ý","œ","ÿ","а","б","в","г","д","е","ё","ж","з","и","й","к","л","м","н","о","п","р","с","т","у","ф","х","ц","ч","ш","щ","ъ","ы","ь","э","ю","я"}
local caseMap={};for i,char in ipairs(upper) do caseMap[char]=lower[i] end
function Q.Fold(value)
 value=(value or ""):gsub("[A-Z]",string.lower)
 return (value:gsub("[\194-\244][\128-\191]+",caseMap))
end
-- Exact stat labels for typed permanent-enchantment tooltip lines. Unknown
-- sentences stay unscored; no translated proc is treated as a permanent stat.
function Q.StatAliases()
 local result={}
 local keys={strength="Stärke",agility="Beweglichkeit",stamina="Ausdauer",intellect="Intelligenz",spirit="Willenskraft",armor="Rüstung",defense="Verteidigung",attack="Angriffskraft",spell="Zaubermacht",healing="Heilung",damage="Waffenschaden",haste="Tempo",threat="Bedrohung",crit="kritische Trefferchance",herbalism="Kräuterkunde",mining="Bergbau",skinning="Kürschnerei",fishing="Angeln",all="Alle Werte"}
 for key,label in pairs(keys) do
  result[Q.Fold(label)]=key
  for _,pack in pairs(Q.packs) do if pack[label] then result[Q.Fold(pack[label])]=key end end
 end
 local extra={
  ["силе"]="strength",["ловкости"]="agility",["выносливости"]="stamina",["интеллекту"]="intellect",["духу"]="spirit",["броне"]="armor",["защите"]="defense",["силе атаки"]="attack",["силе заклинаний"]="spell",
  ["dégâts des sorts"]="spell",["daño con hechizos"]="spell",["урон заклинаний"]="spell",["bonus de soins"]="healing",["bonus de sanación"]="healing",["бонус исцеления"]="healing",
  ["à toutes les caractéristiques"]="all",["ко всем характеристикам"]="all",["к характеристикам"]="all",
 }
 for name,key in pairs(extra) do result[name]=key end
 local globals={strength="ITEM_MOD_STRENGTH_SHORT",agility="ITEM_MOD_AGILITY_SHORT",stamina="ITEM_MOD_STAMINA_SHORT",intellect="ITEM_MOD_INTELLECT_SHORT",spirit="ITEM_MOD_SPIRIT_SHORT",armor="RESISTANCE0_NAME",attack="ITEM_MOD_ATTACK_POWER_SHORT",spell="ITEM_MOD_SPELL_POWER_SHORT",healing="ITEM_MOD_SPELL_HEALING_DONE_SHORT"}
 for key,name in pairs(globals) do if type(_G[name])=="string" then result[Q.Fold(_G[name])]=key end end
 return result
end
