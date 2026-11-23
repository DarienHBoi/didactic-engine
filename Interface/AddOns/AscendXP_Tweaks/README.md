# AscendXP Tweaks

Companion for AscendXP (WoW Forever, interface 16001). It moves, scales, aligns, recolours and hides AscendXP's text in groups from outside, so AscendXP updates do not overwrite your choices.

- `/axpt` opens the window. **Unlock text**, then click a highlighted group on the AscendXP bar or panel and drag it. A group is the texts in one column (a label and its value); they move and scale together. Right-click a group to reset it.
- With a group selected: Left / Centre / Right, Scale - / + (0.5x to 3x, per group), Hide / Show, and a colour box (RRGGBB, press Enter). Prev / Next steps through the groups.
- `/axpt group 30` makes bigger groups (texts whose left edges are within 30 pixels), `/axpt group 6` smaller ones; it clears your earlier changes. The default is 14.
- **Snap to top** (also `/axpt top`) holds the bar against the top edge of the screen. AscendXP keeps its bar a little off the edge; this switches that off. Gap -/+ sets the distance below the top edge (negative moves it above, so the art sits flush), and < Bar left / Bar right > move it sideways. One pixel per click, ten with Shift held. While Snap is on, position it with these buttons; turn Snap off to drag the bar again.
- `/axpt info` prints where the bar sits (anchor, scale, top edge, snap state) for troubleshooting.
- `/axpt reset` puts everything back. Settings are saved per account in `AscendXPTweaksDB`.
- If AscendXP changes its layout in a new version, group numbers may shift; use Reset all.
