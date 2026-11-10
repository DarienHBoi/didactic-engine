# Animated Blizzard Portraits 1.2.24

- Minor Lua source readability cleanup and release-version updates. Existing gameplay behavior and settings are unchanged.

# Animated Blizzard Portraits 1.2.23

- Added Cataclysm Classic 4.4.2 interface 40402 to every shipped TOC. Cataclysm gameplay has not been verified.
- Minor Lua source readability cleanup. Compiled Lua 5.1 bytecode was verified unchanged before release-version metadata was bumped.

# Animated Blizzard Portraits 1.2.22

- Added Cataclysm Classic 4.4.2 interface 40402 to every shipped TOC. This is a manifest update; Cataclysm gameplay has not been verified.

# Animated Blizzard Portraits 1.2.21

- Re-release for Mists of Pandaria Classic (5.5.4) and Wrath of the Lich King Classic (3.4.5): both interface numbers (50504 and 30405) are listed in the TOCs. No code changes.

# Animated Blizzard Portraits 1.2.20

- Added support for game patch 12.1.7: the TOC now lists retail interface 120107 (120105 for 12.1.5 is kept), so the addon is not marked out of date.

# Animated Blizzard Portraits 1.2.13

- Lower target/focus name and level by two pixels.
- Fix Name Highlight controls by targeting Retail ReputationColor explicitly. Transparent hides the native band; Default returns control to Blizzard; Class Color/Custom use neutral addon-owned artwork with correct alpha.
- Avoid eager recursive frame/bar lookup and proximity-based background guessing. Add safe handling for forbidden widgets and secret getter values in audited discovery paths.
- Correct Retail color-picker alpha inversion and Gradient-to-Solid transitions that retained the old gradient.
- Preserve fresh-install/reset defaults without incorrectly running legacy border-order migrations; retain migrations for genuine older databases.
- Fall back to native class resources when custom values are restricted. Use reversible alpha without native show-handlers or forced visibility.
- Remove diagnostic writes to native lockColor. Preserve all fixes from 1.2.9 through 1.2.12.

Verification: expanded component tests cover names/highlights, five unit prefixes' visual parameters, database/profile/queue behavior, model fallback/retries, modern/legacy picker semantics, class resource definitions and pip styling, lazy lookup/client detection, bar/effect transitions and shared UI callbacks. Earlier regressions pass. Lua/XML/manifest/ZIP equality checks run before packaging. Current published 1.2.8 remains identical to the audited baseline.

Gameplay testing is required. Reload outside combat and check Name Highlight modes, text placement, bar transitions, profiles and dungeon/combat target switching. True circular model clipping remains unresolved; the current custom border render path is Square-only. See docs/Animated Blizzard Portraits audit.md in the Workshop for coverage, limitations and the in-game checklist. This is not a claim that every setting has been verified in WoW.

SavedVariables are not modified by deployment. No CurseForge upload performed.

---

# Animated Blizzard Portraits 1.2.12

- Remove OnShow handlers from Retail PvP/prestige, role, corner and rested-glow textures. Blizzard can pass secret values into native texture SetShown calls; a registered script handler blocks those calls even if its callback only schedules deferred work.
- Apply hide-icon preferences with reversible alpha suppression from the existing 0.25-second addon refresh. No native texture Show/Hide/SetShown methods are replaced, and no secret shown-state or role values are inspected to recompute visibility.
- Turning Hide Emblem off no longer forces every native emblem texture visible. Blizzard retains control over native shown states, preventing inappropriate emblems on NPCs.
- Retain the earlier secret-string guard, transparency fallback and separate target/focus header. No SavedVariables changed.

Verification: the 1.2.11 startup hooks reproduce Texture:SetShown(): Cannot be called with secrets due to existing script handlers in the focused API mock. Fixed startup passes secret visibility updates on target/focus PvP and prestige textures; hide/restore preserves native shown state and previous alpha. Role/corner/status polling and Classic isolation checked. Earlier header, fallback and reported-error tests pass. Lua/XML/manifest and ZIP/source checks performed. Current published 1.2.8 download still matches the audited original.

Gameplay validation required: /reload OUTSIDE COMBAT to discard previously attached handlers, then switch between dungeon NPCs during combat and watch for new CheckFaction/Texture:SetShown errors. Test Hide Emblem and Hide Player Icons on/off and normal PvP/role/resting transitions. Other addons can independently attach conflicting scripts, so absence of new errors still needs live confirmation. Circular model clipping remains unresolved and is not changed by this patch.

Not uploaded to CurseForge.

---

# Animated Blizzard Portraits 1.2.11

- Put Retail target/focus name and level on a separate row above the live health bar, avoiding the overlap with Blizzard's Dead/Unconscious labels when using custom fills and transparent frame artwork.
- Preserve Blizzard's status label visibility and text. No secret health values are inspected.
- Defer initial layout changes during combat; relative anchors follow the health bar without reading screen coordinates. Leave Classic and unrelated unit frames unchanged.
- Retain the 1.2.9 secret-value guard and 1.2.10 transparent fallback behavior. No saved settings are changed.

Checks: target/focus header placement, combat deferral, unchanged status visibility, other-client/third-party widget isolation, previous fallback and secret-value regression tests, Lua/XML syntax, TOC references, ZIP/source equality. Current published 1.2.8 was checked on the live page and its downloaded ZIP checksum still matches the audited original.

In-game validation pending: /reload outside combat, target Bribed Captain (or another unconscious/dead dungeon target), and verify the name is above the health bar while status remains inside it. Check normal live targets, Focus, switching targets, combat and frame movement. Circular clipping of the 3D portrait is not fixed by this header patch; the existing Circle option masks the background, while the 3D model is clipped to a rectangle. The large green rectangle in the submitted screenshot is the Frame Stack debug highlight (/fstack), not an addon backdrop.

Not uploaded to CurseForge.

---

# Animated Blizzard Portraits 1.2.10

- Stop restoring Retail's default portrait/bar artwork when an enemy's animated model is unavailable. The static portrait fallback now keeps native chrome suppressed just like the animated portrait, so transparent borders do not become opaque outlines in dungeons.
- Preserve the original static portrait, selected health/resource fill settings, earlier secret-texture checks, and existing Classic fallback behavior.
- No SavedVariables or user preferences are changed.

Verified: regression test reproduces unwanted native chrome in the imported original and checks the fix in circle/square modes, static portrait visibility, gradient preference preservation and Classic behavior. Earlier reported-error regressions, Lua/XML syntax, manifest references and ZIP/source equality checked. Compared current published 1.2.8 files with original import again before packaging.

Gameplay testing required: /reload, target the same dungeon enemy with Transparent selected for portrait background/border and HP/resource borders. Check unwanted outlines stay gone when switching between static and animated portraits. The overlapping Unconscious status text is a separate unresolved layout observation; this patch does not change it. Screenshot alone does not establish the origin of every visible overlay.

Not uploaded to CurseForge.

---

# AnimatedBlizzPortrait 1.2.9

- Check texture names, atlas names and texture IDs for secret values before inspecting or converting them.

Verification: focused Lua regression mocks reproduce the original report and pass with the fix. Lua syntax, manifest and ZIP checks are run by the Workshop packaging tool.

In-game testing required: During combat, switch targets and test player, target, focus, party and pet portraits. Confirm no secret-string errors and that portraits and classic flash suppression still work.

Not uploaded or deployed.

---

# Animated Blizzard Portraits 1.2.7

- Added `/abp version` to report the installed addon version and game build in one line for support.
- The command accepts uppercase letters and surrounding spaces.
- Aligned all included client and module manifests to 1.2.7.
- Existing settings and normal commands are preserved.

Validation: all 1 packaged Lua files compile under Lua 5.1; version reporting checked with modern, legacy and unavailable metadata APIs; normal-command fall-through checked; manifest references verified.

In-game visual testing has not been performed for this maintenance patch.
