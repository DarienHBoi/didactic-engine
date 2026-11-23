# Missing Buff Warning: compact grouped display (design, approved by the owner 2026-11-15)

Addon: `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\MissingBuffWarning` (owner's own; read its `NEXT-AGENT.md` first).

## Why
Today each missing buff is a big trainer-style panel (icon, gold title, two lines of text). Two missing buffs already cover a large part of the screen. The owner wants the same information much smaller, grouped, scalable and tweakable.

## Decided by the owner
- **Two layouts, switchable in options:**
  - **A. Grouped list:** small box with header "Missing buffs (N)" (click to collapse). Group headers *Self*, *Group*, *Optional*, each collapsible. One line per buff: 16px icon (red edge) + name; group buffs show "3/5" and, nested under it, the names of who is missing it.
  - **B. Icon strip:** a row of small icons with a thin divider between groups; a badge with how many people miss a group buff; hover shows name and who; optional buffs dimmed.
- **Both:** click a line/icon to cast (keep the existing secure cast behaviour), shift-drag to move, scale handle stays.
- **Options panel gets all four areas:**
  - Size and spacing: scale, icon size, row spacing, font size, grow up or down.
  - Look: background on/off + opacity, border on/off, group header colour, red edge on missing icons.
  - Grouping: assign each buff to Self / Group / Optional; collapse state per group remembered; show who in the party is missing a group buff (on/off).
  - When to show: in combat on/off, only in group/raid, fade (or hide) when nothing is missing, lock/unlock.

## Calls I made (owner can overrule)
- Defaults: layout A, Inner Fire = Self, Fortitude/Divine Spirit/Shadow Protection = Group, Shadowform = Optional; scale 1, icon 16px.
- The old big panel stays as a third layout choice ("Big panels") so nothing is lost.
- Party checking is new: it reads party/raid members' auras out of combat only. The addon already knows the game can hide aura names in combat (see its NEXT-AGENT.md); in combat the group section keeps its last known state rather than guessing.

## Done means
- Layout and grouping logic tested first against the existing fake-WoW harness approach (rebuild a harness if the old scratchpad one is gone).
- Settings saved in `MissingBuffWarningDB`, old settings migrate (old scale/position kept).
- Not seen in game until the owner checks; say that.
