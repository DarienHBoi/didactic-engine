# NectarKit (working name)
Launcher drawer plus per-addon and per-module switches. One minimap button, left click opens a panel with one icon per owner-made addon (calls SlashCmdList[KEY]("")) and a settings cog. `/nk` toggles, `/nk options` opens the settings window, `/nk buttons [on|off]` hides/restores the other addons' own minimap buttons (default on), `/nk scale 0.6-1.6`. Settings in `NectarKitDB` (angle, hideButtons, scale, modules).
- Files: Entries.lua (data table: addon, title, key, slash, icon, button frame), Logic.lua (pure, tested), Options.lua (settings window), Main.lua (frames, events, /nk, module API globals).
- Tests: `python nectarkit_tests/run.py` (logic, hider, entries, options, modules, smoke with fake Forever frames: C_AddOns present, no IsAddOnLoaded global). 369 passed at build.
- Reaper (execute timing, /reaper, key REAPER) added 2026-11-21 with modules lines, glow, alert (registered from Reaper/Main.lua). nectarkit_tests 381 passed.
- Left out of Entries: !ChatClickWatch (no slash command), TaxiSpike (throwaway).
- `## Category: Nectar` groups the owner's addons in the game's AddOns list (NectarKit, Taxi, MissingBuffWarning, AddonPresets, LinkBisect, !ErrorLog, AscendXP_Tweaks). Pricewatch and Salesman still need the line (queued). Same key DisenchantBuddy_Forever.toc uses on this client.
- NOT seen in game. New files and toc changes need a full WoW restart (not just /reload). Risks: EllesmereUIMinimap may make the minimap square; real frame names read from source; `C_AddOns.GetAddOnEnableState` argument order (name, character) is assumed, the old global takes (character, name), both handled; EnableAddOn(name) with no character is assumed to apply to this character.

## Options window
Cog in the panel or `/nk options`. Lists NectarKit (locked, always on) then every Entries.lua addon, installed or not (not installed = greyed). The addon checkbox calls C_AddOns.EnableAddOn/DisableAddOn and only takes effect after a reload. "N changes need a reload" counts addons whose state differs from the state at login (toggling back cancels). Module checkboxes sit indented under their addon and apply at once. Addons that register no modules show only the addon switch. The window is not scrollable; it grows with the rows.

## Module API (for Pricewatch, Salesman, ... wired later)
State is `NectarKitDB.modules[addon][key]` (boolean; only written when the owner changes it, so defaults can change later).
- `NectarKit_RegisterModule(addon, key, label, default, onToggle)` returns the current state. `default` is on unless it is exactly `false`. `onToggle(enabled)` runs at login (after NectarKit's PLAYER_LOGIN), on every change, and immediately if registered after login. pcall-guarded; an error prints one chat line and nothing else breaks. Registering the same addon/key again replaces label/default/callback.
- `NectarKit_IsModuleOn(addon, key)` returns the state (false for an unknown module).
- Registration must name an addon that is in Entries.lua, or its modules are not shown in the window (the state still works).

Use: add `## OptionalDeps: NectarKit` to the addon's toc so NectarKit loads first, then call it from the addon's own PLAYER_LOGIN (or at file load). Always guard, because NectarKit may be absent or disabled:
```lua
local function setup()
    if not NectarKit_RegisterModule then return false end  -- NectarKit missing or disabled: keep every feature on
    NectarKit_RegisterModule("Pricewatch", "tooltip", "Item tooltip lines", true, function(on) PW.tooltipOn = on end)
    NectarKit_RegisterModule("Pricewatch", "deals", "Deals panel", true, function(on) PW.dealsOn = on end)
    NectarKit_RegisterModule("Salesman", "adverts", "Adverts", true, function(on) SM.advertsOn = on end)
    return true
end
local f = CreateFrame("Frame"); f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", setup)
-- later, at the point of use: if NectarKit_IsModuleOn and not NectarKit_IsModuleOn("Pricewatch", "tooltip") then return end
```
Loaded before NectarKit (no OptionalDeps)? The function does not exist yet at file load, so leave a record in the global queue instead; it is drained at NectarKit's ADDON_LOADED and again at PLAYER_LOGIN:
```lua
NectarKit_Queue = NectarKit_Queue or {}
table.insert(NectarKit_Queue, { addon = "Pricewatch", key = "tooltip", label = "Item tooltip lines", default = true,
    onToggle = function(on) PW.tooltipOn = on end })
```
- Next: owner checks in game (full restart); wire Pricewatch and Salesman modules and their `## Category: Nectar` line; rename if wanted (folder, toc, NectarKitDB, /nk).
