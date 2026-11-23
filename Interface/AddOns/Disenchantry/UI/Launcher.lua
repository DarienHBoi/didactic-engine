-- Minimap launcher routing is separate from its broker registration.
local _, ns = ...
local App = ns.App
local function activate(_, mouse)
    if IsAltKeyDown() then
        App.db.minimap.hide = true
        App.libDBIcon:Hide("Disenchantry")
        local panel = App.settingsFrame
        local sync = panel and panel:IsShown() and panel:GetScript("OnShow")
        if sync then sync(panel) end
        App.Print(App.L.MM_HIDDEN)
        return
    end
    if mouse == "RightButton" then App.ToggleSettingsFrame(); return end
    if mouse ~= "LeftButton" then return end
    if InCombatLockdown() then App.Print(App.L.NOT_IN_COMBAT); return end
    local preference=App.db.minimapOpenMode or "last"
    local compact=preference=="compact" or preference=="last" and App.db.compactMode
    local frame=compact and App.compactFrame or App.mainFrame
    if frame and frame:IsShown() then frame:Hide() else App.SetCompactMode(compact) end
end
local function describe(tip)
    tip:AddLine("Disenchantry")
    for _, key in ipairs({"MM_LEFT", "MM_RIGHT", "MM_DRAG", "MM_ALT_HIDE", "MM_COMPACT_HINT"}) do
        tip:AddLine(App.L[key], 1, 1, 1)
    end
end
function App.CreateMinimapButton()
    if not LibStub then return end
    local broker = LibStub:GetLibrary("LibDataBroker-1.1", true)
    local icons = LibStub:GetLibrary("LibDBIcon-1.0", true)
    if not broker or not icons then return end
    App.libDBIcon = icons
    local launcher = {type="launcher", text="Disenchantry", icon=App.GetSpellTextureSafe(13262) or 136244,
        OnClick=activate, OnTooltipShow=describe}
    icons:Register("Disenchantry", broker:NewDataObject("Disenchantry", launcher), App.db.minimap)
end
