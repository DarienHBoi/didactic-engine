# Console Port

## [3.3.13](https://github.com/seblindfors/ConsolePort/tree/3.3.13) (2026-10-30)
[Full Changelog](https://github.com/seblindfors/ConsolePort/compare/3.3.12...3.3.13) [Previous Releases](https://github.com/seblindfors/ConsolePort/releases)

- Merge pull request #293 from seblindfors/forever  
    3.3.13: wrapper cleanup  
- Bump version to 3.3.13  
- Drop the CPAPI wrappers whose namespaced API exists on every client  
- Merge pull request #288 from Daemeron/fix/deprecated-socket-info  
    Use the current item socket API instead of the deprecated global  
- Merge pull request #292 from seblindfors/forever  
    3.3.13: settings regroup, action placer, keyboard glyphs, Forever groundwork  
- Merge pull request #287 from seblindfors/forever-impl  
    Forever: gamepad action storage, native UI coexistence, keyboard glyphs  
- Merge pull request #291 from seblindfors/action-placement  
    Paged action placer for spells and items  
- Replace the slot grid popup with a paged action placer in the config  
- Number keyboard bars within their own set  
- Page the gamepad bar onto vehicle, override and temp shapeshift pages  
- Hold the camera stick after a targeting binding is released  
- Let the mouse button bindings lead and mirror the interface click from a plain button  
- Move the modifier settings under Bindings and merge its lists  
- Group and sort stance bars with their own slot set in the config  
- Fit Forever's bag slot textures and key ring to the toolbar size  
- Show modifier glyphs above the keyboard and hints in the suggestion list  
- Guard the Forever paths on other clients, at load and in combat  
- Gate cursor, auras, loot, temp abilities and the game menu behind the native gamepad UI on Forever  
- Size config and slot pickers by bar width for the gamepad slot set  
- Hide the native gamepad bar, strip its keys, and bind Interact, Inspect and targeting on Forever  
- Add the gamepad action storage backend for Forever  
- Use the current item socket API instead of the deprecated global  
    GetSocketItemInfo is a bare global only provided by the on-demand  
    Blizzard\_DeprecatedItemSocketInfo addon as an alias for  
    C\_ItemSocketInfo.GetSocketItemInfo. When that compatibility addon has  
    not loaded, the global is nil and every modified-click on an item  
    button errors with 'attempt to call a nil value', regardless of which  
    button it was.  
    Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>  
