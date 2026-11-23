-- ForeverCampGuide - Locale.lua
-- Los textos se escriben en español y se traducen al vuelo con ns.T().
-- Las traducciones al inglés están en Locale_Data_enUS.lua (guías) y Locale_UI_enUS.lua (interfaz).
local _, ns = ...

ns.EN = {}

local function DetectLanguage()
    local loc = GetLocale and GetLocale() or "enUS"
    return (loc == "esES" or loc == "esMX") and "es" or "en"
end
ns.LANG = DetectLanguage()

-- Aplica la preferencia guardada ("auto", "es" o "en")
function ns.ApplyLanguage(pref)
    if pref == "es" or pref == "en" then ns.LANG = pref else ns.LANG = DetectLanguage() end
end

-- Traduce un texto (o lo devuelve igual si no hay traducción)
function ns.T(s)
    if s == nil or ns.LANG == "es" then return s end
    local e = ns.EN[s]
    if e then return e end
    if ns.missing and type(s) == "string" then ns.missing[s] = true end
    return s
end

function ns.IsEnglish() return ns.LANG == "en" end

-- Nombre visible de una profesión
function ns.ProfName(prof)
    if not prof then return "" end
    return ns.LANG == "es" and prof.name or prof.names[1]
end
