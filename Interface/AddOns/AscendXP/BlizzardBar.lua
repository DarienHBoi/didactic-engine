-- AscendXP v1.2.3 | WoW Forever 1.60.1
-- Fade Blizzard's entire status-tracking display, INCLUDING its background.
-- Do not call Hide(), reparent, alter edit-mode layout or modify other addons.
-- Blizz often animates the manager's alpha back to 1 after /reload.
local _, addon = ...
local BlizzardBar = {}
addon.BlizzardBar = BlizzardBar

local enabled = false
local originals = {} -- frame -> { alpha, mouse }
local targets = {}
local lastReport = "not initialized"
local pulse = 0

local function Valid(frame)
    return frame and type(frame.SetAlpha) == "function" and type(frame.GetAlpha) == "function"
end
local function Read(frame, method)
    if not frame or type(frame[method]) ~= "function" then return nil end
    local ok, result = pcall(frame[method], frame)
    if ok then return result end
end
local function Set(frame, method, value)
    if frame and type(frame[method]) == "function" then
        return pcall(frame[method], frame, value)
    end
end
local function Add(out, frame, tag)
    if Valid(frame) and not out[frame] then out[frame] = tag end
end
local function Find()
    local out = {}
    -- IMPORTANT: these are not fallback targets. The native segmented XP bar
    -- belongs to these frames even if a separate experience child is found.
    Add(out, _G.StatusTrackingBarManager, "Blizzard manager")
    Add(out, _G.MainStatusTrackingBarContainer, "Main XP container")
    Add(out, _G.SecondaryStatusTrackingBarContainer, "Secondary status container")
    -- Classic and transition-client fallbacks. These aren't a reason to skip
    -- the manager above, which was the v1.2.2 bug.
    Add(out, _G.MainMenuExpBar, "Legacy XP")
    Add(out, _G.MainMenuBarXPText, "Legacy XP text")
    Add(out, _G.MainMenuBarMaxLevelBar, "Legacy level bar")
    return out
end
local function InEditMode()
    local frame = _G.EditModeManagerFrame
    return frame and Read(frame, "IsShown") == true
end
local function Capture(frame)
    if originals[frame] then return end
    local a = Read(frame, "GetAlpha")
    if type(a) ~= "number" then return end
    local mouse = Read(frame, "IsMouseEnabled")
    originals[frame] = {alpha = a, mouse = mouse}
end
local function Restore(frame)
    local prior = originals[frame]
    if not prior then return end
    Set(frame,"SetAlpha",prior.alpha)
    if type(prior.mouse) == "boolean" then
        Set(frame,"EnableMouse",prior.mouse)
    end
end
local function RestoreAll()
    for frame in pairs(originals) do
        Restore(frame)
        originals[frame] = nil
    end
    targets = {}
end
local function Enforce()
    if not enabled then return end
    local editing = InEditMode()
    local fresh = Find()
    -- Never reset a frame's alpha every tick. The original is captured once.
    for frame in pairs(fresh) do
        Capture(frame)
        if originals[frame] then
            if editing then
                Restore(frame) -- retain Edit Mode access without tainting layout
            else
                local alpha = Read(frame, "GetAlpha")
                if type(alpha) == "number" and alpha > 0 then
                    Set(frame,"SetAlpha",0)
                end
                if Read(frame,"IsMouseEnabled") == true then
                    Set(frame,"EnableMouse",false)
                end
            end
        end
    end
    -- Frames can be replaced by Blizzard on an Edit Mode transition.
    for frame in pairs(originals) do
        if not fresh[frame] then
            Restore(frame)
            originals[frame] = nil
        end
    end
    targets = fresh
end
function BlizzardBar.Apply(hide)
    local desired = not not hide
    if not desired then
        if enabled then RestoreAll() end
        enabled = false
        lastReport = "off (Blizzard status bars restored)"
        return
    end
    enabled = true
    Enforce()
end
function BlizzardBar.Debug()
    if not enabled then return lastReport end
    local lines = {}
    for frame, label in pairs(targets) do
        local alpha = Read(frame,"GetAlpha")
        local shown = Read(frame,"IsShown")
        lines[#lines+1] = label .. " alpha=" .. tostring(alpha) .. " shown=" .. tostring(shown)
    end
    table.sort(lines)
    if #lines == 0 then return "ON, no native bar frames found yet" end
    return "ON; " .. table.concat(lines, "; ")
end

-- The native status manager can animate alpha back to 1 *between* XP updates.
-- Small, bounded rechecks keep it hidden without Show/Hide hooks or protected
-- Edit Mode writes. Once a frame is already alpha=0, no extra mutation occurs.
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, elapsed)
    if not enabled then return end
    pulse = pulse + elapsed
    if pulse >= 0.15 then
        pulse = 0
        Enforce()
    end
end)
