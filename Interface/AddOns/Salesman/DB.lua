local _, S = ...
S.DB = {}
S.DB.OLD_DEFAULT_TEMPLATE = "SELLING {link} {price} whisper me"
S.DB.DEFAULT_TEMPLATE = "SELLING {link} {stats} {price} whisper me"
S.DB.OLD_DEFAULT_TEMPLATE_BYO = "SELLING {link} {price} (you bring mats: {mats}) whisper me"
S.DB.DEFAULT_TEMPLATE_BYO = "SELLING {link} {stats} {price} (you bring mats: {mats}) whisper me"
S.DB.DEFAULT_TEMPLATE_SKILL = "ENCHANTER {link} whisper me for prices"
S.DB.DEFAULT_TEMPLATE_REPLY = "Hi! {link} is {price} with mats included. Want it?"
S.DB.CACHE_VERSION = 2

function S.DB.init(globalSV, charSV)
    globalSV = globalSV or {}
    charSV = charSV or {}
    if globalSV.margin == nil then globalSV.margin = 20 end
    if globalSV.template == nil then globalSV.template = S.DB.DEFAULT_TEMPLATE end
    if charSV.favourites == nil then charSV.favourites = {} end
    if globalSV.editFirst == nil then globalSV.editFirst = true end
    if globalSV.minimapAngle == nil then globalSV.minimapAngle = 200 end
    if globalSV.minimapHidden == nil then globalSV.minimapHidden = false end
    if globalSV.templateSkill == nil then globalSV.templateSkill = S.DB.DEFAULT_TEMPLATE_SKILL end
    if globalSV.templateBYO == nil then globalSV.templateBYO = S.DB.DEFAULT_TEMPLATE_BYO end
    if charSV.recipes == nil or charSV.cacheVersion ~= S.DB.CACHE_VERSION then
        -- Older caches lack category/profession data (and may hold other professions): rebuild on next scan.
        charSV.recipes = {}
        charSV.cacheVersion = S.DB.CACHE_VERSION
    end
    if charSV.cardMargin == nil then charSV.cardMargin = {} end
    if charSV.collapsed == nil then charSV.collapsed = {} end
    if charSV.sales == nil then charSV.sales = {} end
    if charSV.customers == nil then charSV.customers = {} end
    if globalSV.statsOverride == nil then globalSV.statsOverride = {} end
    globalSV.scale = S.Scale.clamp(globalSV.scale)
    -- Untouched old default wording moves to the one that shows the enchant's stats; custom wording is left alone.
    if globalSV.template == S.DB.OLD_DEFAULT_TEMPLATE then globalSV.template = S.DB.DEFAULT_TEMPLATE end
    if globalSV.templateBYO == S.DB.OLD_DEFAULT_TEMPLATE_BYO then globalSV.templateBYO = S.DB.DEFAULT_TEMPLATE_BYO end
    if globalSV.alerts == nil then globalSV.alerts = true end
    if globalSV.templateReply == nil then globalSV.templateReply = S.DB.DEFAULT_TEMPLATE_REPLY end
    S.DB.global, S.DB.char = globalSV, charSV
end

function S.DB.toggleFavourite(key)
    if key == nil then return false end
    local f = S.DB.char.favourites
    f[key] = not f[key] or nil
    return f[key] == true
end

-- Puts every ad wording back to the shipped default.
function S.DB.resetWording()
    local g = S.DB.global
    g.template = S.DB.DEFAULT_TEMPLATE
    g.templateBYO = S.DB.DEFAULT_TEMPLATE_BYO
    g.templateSkill = S.DB.DEFAULT_TEMPLATE_SKILL
    g.templateReply = S.DB.DEFAULT_TEMPLATE_REPLY
end
