# MapSeek

**Search the world map for anyone and anything, and see it light up.**

Need a repair? The nearest innkeeper? Who sells Simple Flour, or the book that takes First Aid past 150? Open the map, type it in, and every match appears on the map and minimap, with the nearest one marked and a waypoint one click away.

MapSeek is built for **WoW Forever** and searches the data from [QuestieDB](https://www.curseforge.com/wow/addons/questie). Questie itself is optional.

---

## What you can find

| Search for | Try typing |
|---|---|
| **Services** | `repair` · `inn` · `flight` · `bank` · `auction` · `stable` · `vendor` · `battlemaster` |
| **Trainers** | `trainer` · `mage trainer` · `alchemy trainer` · `fishing trainer` · weapon skills: `staff trainer` · `polearm trainer` · `2h sword trainer` |
| **Items for sale** | `simple flour` · `fishing pole` · `heavy shot` · `rough arrow` |
| **Items no vendor sells** | `copper ore` · `peacebloom` (every vein or plant in a zone) · `linen cloth` · `silk cloth` · `gnoll paw` (where it drops, drawn as an area) |
| **Skill books** | `first aid book` · `cooking book` · `fishing book` · `skill books` |
| **Farming together, or by zone** | `copper and tin farm` (one loop, with the split) · `hillsbrad farm` · `hillsbrad ore farm` (every loop that zone has) |
| **Riding** | `where to train riding` · `mount training` · `learn to ride` · `riding`: your faction's riding trainers (`mount` finds the mount sellers) |
| **Training past a cap** | `how do i train past 225 first aid` · `tailoring 150` · `train cooking` (past the cap you have now): the trainers, book or quest that take it further |
| **Quests** | `quests` (the quests for your level to pick up in your zone, and the zones with more) · `quests in the barrens` · `all quests` (grey ones too) · a quest's name: `lazy peons` · `theldurin the lost` (who gives it) · `turn in the lost pilot` (who it's handed in to) · `deadmines quests` · `krol'dok quests` (who starts a dungeon's quests you could still take) |
| **Reputation** | `timbermaw rep` (quartermaster, turn-ins, and where to farm what they ask for) · `rep farms` (every faction's turn-ins you can do now) |
| **Objects** | `mailbox` · `forge` · `anvil` · `campfire` · `meeting stone` |
| **NPCs** | Any name or title: `Innkeeper Allison` · `weaponsmith` |
| **Places** | Any zone, city, town or dungeon: `elwynn forest` · `stormwind` · `goldshire` · `skywatcher plateau` · `deadmines` · `sm` · `stv` · `epl` (the map goes there) |
| **Your group** | `party` · `raid` · a groupmate's name (or right-click their frame: **Find on Map**) |
| **Anything, in a place** | `herb trainer org` · `org herb trainer` · `innkeeper in the crossroads` |

- **Suggestions as you type**, from NPC names, titles, items vendors sell and quest names.
- **Forgiving spelling:** `fishng trainr` still finds fishing trainers.
- **Smart trainer results:** a plain `trainer` search shows your class's trainers, and only your own professions once both are picked.
- **Where to farm it:** an item no vendor sells shows where it drops or is gathered, not a page of near-misses.

---

## Features

### Results you can act on
- Matches **pulse on the map**, then stay as steady icons. Matches in your zone go on the **minimap** too.
- The map **moves to the results**, and the **nearest match** is ringed in green.
- **Click any marker** for a waypoint (TomTom when installed).
- **Rich tooltips:** distance, the nearest flight master when you're far away, what a vendor sells (with item icons), and a quest giver's quests.
- **Vendor cards:** right-click a vendor to pin a card of everything they sell. Hover any item for its full tooltip; Shift-click to link it.
- NPCs who walk around show their **patrol path**.

### Where to farm it
- Search an item no vendor sells. **Ore and herbs** get a marker on every vein or plant in a zone (yours first).
- **Things mobs drop**, like cloth, get the zone's best farming spots **drawn on the map** the way the game draws a quest's area, ranked by drop rate and how packed the mobs are. The best spot is purple.
- The spots show on the **minimap** too, round or square.
- **Click a spot** on the map to pin it: it stays on the map and minimap after you close the map, until you clear it.

### One-click searches
- **Quick buttons** on the map's top bar: Repair, Inn and Trainer to start, with many more to choose from. Five on the bar, the rest under **More**, all drag-to-reorder.
- A quick button's markers **stay for 30 seconds** after you close the map, so you can head straight there.
- **Right-click** a quick button to **pin** it on the map and minimap until you're done, have the minimap button find it, change its icon or take it off the bar.

### Favourites and pins
- Your quick searches and the searches you **star** are one list of favourites (up to 20), starting with Repair, Innkeeper, Trainer, Vendor, Flight master and Mailbox.
- **Pin** one to keep it on the map and minimap, even after logging out. With none in your zone, its nearest results wait on the edge of the minimap, pointing the way.
- Turn any favourite into a **button on the bar**, with an icon you pick.
- Pick the favourite a click on the **minimap button** finds (Repair, say), or keep it opening the search.

### Made to fit in
- A clean search bar across the top of the map that stays out of the way until you need it. Or put it along the bottom, or drag it anywhere on the map.
- A **settings panel** with Favourites, Search and Options tabs.
- Optional **zone-only** searching that still tells you what's in other zones.
- A **repair reminder** when your gear drops to 20%.
- **EllesmereUI support:** MapSeek's windows take on your EllesmereUI theme.
- **In your language:** English, Deutsch, Español, Français, Italiano, Português, Русский, 한국어 and 中文.
- Light on memory. It reads QuestieDB's data a little at a time after login, to keep loading smooth.

---

## Getting started
1. Install **MapSeek** and **QuestieDB** (Questie itself is optional).
2. Click the **MapSeek button** on the minimap, or open the world map and click the **spyglass** at the top right. The quick buttons sit beside it.
3. Type what you're looking for, or click a quick button.

## Requirements

| Addon | |
|---|---|
| **QuestieDB** (Forever build) | Required |
| **Questie** | Optional: its colours and settings are followed where they apply |
| **TomTom** | Optional: waypoints go to TomTom |
| **OpenMap** | Optional: markers also show on its map |
| **EllesmereUI** | Optional: MapSeek matches your theme |

## Commands

| Command | |
|---|---|
| `/seek <text>` | Open the map and search |
| `/seek clear` | Remove the markers |
| `/seek config` | Open the settings |
| `/seek flash <sec>` | How long markers pulse (default 6) |
| `/seek keep on\|off` | Keep markers after the pulse |
| `/seek minimap on\|off` | Show matches in your zone on the minimap |
| `/seek faction on\|off` | Include NPCs only friendly to the other faction |
| `/seek close all\|list` | Whether closing the map clears the markers too |
| `/seek button on\|off` | Show or hide the minimap button |

`/mapseek` works the same as `/seek`.

---

MapSeek is an independent project and isn't affiliated with Questie. It reads QuestieDB's data while you play and doesn't include any of Questie's code. Copyright (c) 2026 Corey Caruana. All rights reserved: please don't copy, modify or reupload MapSeek. See [LICENSE](LICENSE). Routes ride over a travel network built from the game's own terrain.
