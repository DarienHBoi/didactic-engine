# Changelog

## 2.5.0 (2026-11-14)

### New: Miscellaneous
- New **Miscellaneous** page (side menu under *More*, or `/fcg misc`) with mini guides for useful items that don't belong to a profession. Every point can be opened on the map or set as a waypoint.
- **Cozy Sleeping Bag:** what it does (rested area anywhere, up to +3% experience for 2 hours), the full quest chain for your faction with travel tips and the two jumping puzzles, and the six locations (Westfall, The Barrens, two in Stonetalon Mountains, Loch Modan and Thoradin's Wall). Steps are ticked off as you complete each quest, and the next one is highlighted.
- **Night Watchman's Torch:** how the "An Unfortunate End" quest works, the nine places in Duskwood where the dead Night Watch Guard can appear, a targeting macro, and the torch's limits.
- Data for this page comes from method.gg and conquestcapped.com.

### Fixes
- **Profession detection no longer depends on the exact name the game uses.** Reported on Spanish clients, where Tailoring could not be seen. The addon now also recognizes professions by the names your own client reports, by skill line ID, without accents or capitals ("Sastrería" = "sastreria"), and when the name carries a prefix or suffix. This applies to every profession and every client language.
- `/fcg <profession>` now works without accents (`/fcg sastreria`, `/fcg herreria`, `/fcg mineria`...).
- New `/fcg debug` command: prints the client language, the profession names the game reports and the last page error, to make bug reports easier.

## 2.4.0 (2026-11-05)

Data refreshed from wow-professions.com/forever on November 5, 2026.

### Quantities follow your skill
- **Fixed:** the guide no longer asks for the full amount when you are already partway through a range. If a step says 45x Bolt of Woolen Cloth for 55-80 and you are at 70, it now shows **18x** ("18 of 45 left") and the materials for those 18 only (54 Wool Cloth instead of 135).
- The status line shows how many points and roughly how many crafts are left in the current range.
- Completed ranges show their materials as a plain list, without asking you for them.
- Alternatives and "also make" steps are scaled the same way.
- The header ("Current step") and the panel next to the profession window use the remaining amount too.
- New **What you still need** list at the top of the Shopping tab: every material left until 300, calculated from your current skill, the routes you selected and the main option of each range. Intermediate items the guide makes you craft (bolts, leather, bars, grinding stones...) are subtracted automatically.
- The amounts are an estimate: yellow and green recipes don't always give a point.

### New guides
- **Mining:** trainers (including the new Junior trainers and Zephras Isle), Mining Pick vendors, Find Minerals, skill bonuses, a choice between **smelting to 105** with bought ore or **mining** from 1, and zones for every range up to 300 (optional Iron and Gold smelting).
- **Herbalism:** trainers, Find Herbs, skill bonuses (including Goldthorn Tea) and zones for every range up to 300.
- **Skinning:** trainers, Skinning Knife, the skill-per-mob-level rule and the best mobs for every range up to 300.
- Skyborne players: how to learn each gathering profession from the Harvesting Windstones quest reward.

### Leveling guides
- **Blacksmithing:** Golden Scale Bracers at 175-185 (keep your Heavy Grinding Stones), Mithril Scale Pants at 185-215 with a Steel Breastplate + Steel Plate Helm alternative, and the new **Artisan route (215-300)**: Heavy Mithril Breastplate, Dense Sharpening Stone, Heavy Mithril Boots and the four Imperial Plate quests from Derotain Mudsipper in Gadgetzan, with fallbacks if the quests still need 265. New 150-225 and 225-300 shopping lists.
- **Leatherworking:** Small Leather Ammo Pouch at 30-55, Medium Armor Kit alternative at 80, Dark Leather Pants at 100-115, and the new **Artisan route (225-300)**: Nightscape Boots, Wicked Leather Gauntlets (Werg Thickblade / Leonard Porter) and Runic Leather Headband (Jase Farlane), with three alternatives at 285. New 225-300 shopping list.
- **Tailoring:** simpler route without the beta alternatives (54 Bolts of Silk at 100-120, Gloves of Meditation at 120-140, 23 Bolts of Mageweave at 140-150), and the new **Artisan part**: Runecloth Belt (225-240) and Runecloth Gloves (240-265, pattern from Qia in Winterspring), plus the two world-drop candidates for 265-300. New 225-265 shopping list.

### NPC locations
- 63 new NPCs with built-in coordinates (368 in total), including every gathering trainer, the Mining Pick vendors, Qia, Werg Thickblade, Leonard Porter, Jase Farlane and Derotain Mudsipper.
- New zones on the map: Eastern Plaguelands, Blasted Lands, Searing Gorge and Burning Steppes.

### Interface
- Gathering guides hide the tabs they don't use (Recipes for Herbalism and Skinning; Shopping for Herbalism and Skinning).
- Long zone steps show a short summary in the header and in the profession window panel.
- All new content is available in English and Spanish.

## 2.3.0 (2026-10-22)

### NPC locations
- **Built-in coordinates for 305 NPCs**: every trainer, vendor and quest NPC in the guides now has its exact position, taken from the wow-professions.com NPC pages. You no longer need to visit an NPC before seeing them on the map.
- Clicking an NPC name now opens their zone map with a highlighted star and the NPC's name on it.
- The **[x, y]** coordinates are shown next to every NPC; click them to set a waypoint (TomTom supported).
- The **World map** button now also places a waypoint on the selected NPC.
- Zephras Isle NPCs are placed on the island's own map.
- Annora (Artisan Enchanting) is flagged as being inside Uldaman, since dungeon NPCs can't be shown on a zone map.
- Locations you set yourself (Ctrl-click on the map or "I'm next to it") still take priority, and "Forget location" returns to the website's coordinates.
- Automatic location learning now only applies to NPCs without built-in coordinates, so it no longer spams the chat.

### Merchant's Favor
- Added the Engineering, Leatherworking and Tailoring recipe vendors at both camps (Fizzlefuse, Pawani, Jim'bek / Fritz Fizzle, Daniel Stitchsong, Mivin Shadowweave).
- Added the pet and mount vendors (Gishah, Okamache / Tamelyn Aldridge, Huey Sunnydale).

### Fixes
- Rin'wosho the Trader and Magnus Frostwake (Alchemy vendor recipes) now appear on the map.

## 2.2.0 (2026-10-14)

Data refreshed from wow-professions.com/forever on October 14, 2026.

### New: Merchant's Favor
- New **Merchant's Favor** page (side menu under *More*, or `/fcg favor`).
- Shows your current Merchant's Favor when the client exposes the currency.
- Lists both supply camps and their vendors, with map links:
  - **Horde:** Durotar Supply and Logistics, outside the west gate of the Crossroads.
  - **Alliance:** Azeroth Commerce Authority, at Three Corners in Redridge Mountains.
- **Waylaid Crates:** every crate type and tier (Apprentice, Journeyman, Expert, Artisan) with its bundle options and favor reward. Bundles you can already fill from your bags are shown in green.
- **Reputation:** Craftsman's Writs (75 / 125 / 200 reputation, once per day each), the Shipping Label quest, and the Forged Delivery Receipt trick (50 reputation per empty crate from Friendly).
- **123 vendor recipes** for Alchemy (29), Blacksmithing (61), Cooking (6) and Enchanting (27), each with required level, skill, favor cost, reputation and known/unknown status.
- Each profession's **Recipes** tab now also lists its Merchant's Favor recipes.
- Tooltips now identify Waylaid Crates and their favor reward.

### Camping
- Every camp item now shows its **materials** with live bag counts and whether you already know the recipe.
- Tier 2 items show their **Blueprint** and the boss and dungeon that drop it (for example, the Anvil Blueprint drops from Gilnid in The Deadmines).
- Campfire kits now show their materials and Blueprints (the Journeyman kit Blueprint drops from Lord Serpentis in Wailing Caverns).
- New **Blueprints and crafting stations** section on the *How camping works* page.
- Updated effects: Reagent Bot (class reagents and profession supplies), Repair Bot (repairs for the whole camp), Camp Chair (+2% crit), Molten Foundry (needed for Smelt Heavy Thorium).
- Tooltips now identify camp Blueprints.

### Leveling guides
- **Alchemy:** 165-225 is now Mana Potion followed by Nature Protection Potion. 290-300 is marked as undecided by the guide, with Major Frenzy Potion as an option. New vendor recipe list (Rin'wosho, Magnus Frostwake). Updated shopping lists.
- **Blacksmithing:** new route up to 225 (Heavy Grinding Stones, Bronze Shortswords, Solid Grinding Stones, Mithril Scale Pants, Steel Plate Helms). New shopping lists split into 1-150 and 150-225.
- **Enchanting:** choose between a **Lesser Magic Essence** route and a **Strange Dust** route from 20 to 150 (the choice is remembered). Expert range now uses Minor Mana Oil and Lesser Wizard Oil, with formula vendors. Updated shopping lists.
- **Engineering:** updated shopping list, Mulgore trainer warning, new specialization note, Mithril Tube note, and the Thorium Tube schematic is now bind on pickup.
- **Leatherworking:** new route up to 225, with a choice between the Cured Heavy Hide route and the Heavy Leather route at 130. Nightscape Pants (210-225) must be learned from an Artisan trainer. New shopping list.
- **Tailoring:** new route up to 225, with beta alternatives at 100-125 (shoulders) and 140-150 (Gloves of Meditation). New shopping lists.
- **First Aid:** 75-225 now uses bandages only (Heavy Linen, Wool, Heavy Wool, Silk, Heavy Silk, Mageweave). Updated shopping lists and manual notes.
- **Cooking:** Soothing Turtle Bisque now tracks the Horde quest (7321) as well as the Alliance one. Gikkix's location updated to Steamwheedle Port.
- **Fishing:** many more pole and lure vendors for both factions. Zephras Isle added as a 1-75 zone. The Expert book is also sold on the Auction House.
- **Fishing + Cooking:** the 1-75 section now offers several starting zones per faction (Mulgore, Durotar, Tirisfal Glades, Elwynn Forest, Dun Morogh, Teldrassil and Zephras Isle). Adds Nightcrawler steps and a beta warning not to buy Alterac Swiss yet. Checklist progress starts fresh for this version.

### Interface
- Recipe icons now come from the game client when available.
- Material tooltips now read "material used in:" and list every profession and camp item that uses it.
- New `/fcg favor` command (`/fcg merchant` also works).
- All new content is available in English and Spanish.

### Not yet published by the website
- Merchant's Favor recipe tables for Engineering, Leatherworking and Tailoring.
- Part of the Enchanting Merchant's Favor table (the page is cut off).
- Tier 3 and Expert Campfire Kit Blueprint sources.
- Artisan (225-300) routes for Blacksmithing, Leatherworking and Tailoring.

## 2.1.0
- Full English translation. The language follows your game client and can be changed in Settings.
- English command aliases (`/fcg map`, `/fcg options`, `/fcg help`).

## 2.0.1
- New addon logo, shown in the addon list, on the minimap button and in the main window.

## 2.0.0
- 1-300 leveling guides for nine professions, with current step, known recipes, live material counts and route choices.
- Trainers, shopping lists, recipe overviews and camp items per profession.
- Built-in map viewer with automatic NPC location learning and waypoints (TomTom supported).
- Panel next to the profession window and a Fishing + Cooking checklist.

## 1.0.0
- First release: in-game guide to the WoW Forever camping system.
