# Changelog

## 1.4.0

### Data
- **MapSeek runs on QuestieDB alone.** Questie itself is optional. Everything MapSeek searches comes from QuestieDB; with Questie installed too, its colours and settings are still followed where they apply.
- **MapSeek places its own markers.** The world map and minimap markers, and the patrol paths, are placed by MapSeek's own code rather than a library borrowed from Questie, so a change in Questie can't take them away again. `/seek maplib questie` goes back to Questie's library for a session, for comparing.

### Search
- **A quest item's markers say what quest it's for, and how you're doing with it.** Hovering where a quest item drops (or is gathered) names the quests that need it, and the one it starts, with the game's own count from your log ("Boar Tusk: 3/8"), or that the quest's done and waiting to be handed in. Right-click the marker to show that quest, as searching for it does: the step you're on and where to go for it.
- **Right-click a quest giver's marker to show its quest** the same way: from "deadmines quests", "quests in the barrens", a class's or a profession's quests, or a hand-in's marker. One with several quests opens a menu to pick from.
- **Forever's own dungeons have quest searches too.** "krol'dok quests", "drowned city quests", "alcaz prison quests", "blackmaw hold quests" and "shaper's terrace quests" mark who starts each of that dungeon's quests you could still take, as "deadmines quests" does. QuestieDB files most of these quests under no zone yet, so MapSeek keeps their lists itself; the Shaper's Terrace's are read from the data. Manor Mistmantle has no quests in the data.

### Map
- **Patrol paths are drawn again**, in Questie's colours: amber for an NPC that's friendly or neutral, red for one hostile to you. Hovering a marker or a path lights that NPC's path orange.
- The route line is drawn in the pink that guide addons use, so it reads the same as theirs.
- On OpenMap's stitched map, markers and paths stay put while you zoom and as the map underneath changes: no blink, no path flashing across the middle of the map, and a marker outside the map underneath (a quest marker while you're zoomed in on Thunder Bluff) is no longer hidden.
- The beacon that pulses on a new search, and the "Cancel search" reminder, animate smoothly.

### Routes
- **Zephras Isle has a travel network**, read from Forever's own map files like the continents', so routes on the isle follow its ground and bridges instead of a straight line.
- **Flight paths are only used once MapSeek knows you have them.** A new character isn't sent to fly between cities it has never seen. Open any flight master's map once on a continent and MapSeek learns which paths you have there; until then it tells you so, once, and routes without flights.
- **The Scarlet Enclave from Tirisfal** goes over the Bulwark and along the road through the Plaguelands. Routes no longer cross land the map files have but the game doesn't let you onto (the empty country north of the Plaguelands).
- **The Valley of Trials is walled.** Routes to and from the Horde's starting valley go through its mouth to the east, not over its mountains. A route from the Crossroads used to ford the river and climb straight into it.
- **Sun Rock Retreat** connects to the Charred Vale and Nijel's Point by its south-west road, as in the game. A route from Sun Rock to Nijel's Point is 2 minutes quicker.
- **Moonglade has ways out.** The roads out of Nighthaven's basin, along the lake to the Timbermaw tunnel and up to the pass into Winterspring, were only descents in the data: a route from Moonglade to anywhere didn't exist, and Everlook to Nighthaven went round through Felwood. Both roads are ridden both ways now.
- **Loch Modan's north and east are reached.** The roads up from the loch's shores to Dun Algaz and the Stonewrought Dam, and the east shore's road to Farstrider Lodge, were descents only in the data: from Thelsamar there was no route to the loch's north or east, nor through Dun Algaz to the Wetlands.
- **Hearthglen** is reached by the road north from Andorhal (2½ minutes); routes used to go round through the Eastern Plaguelands, nearly 11 minutes.
- **Silverpine to Alterac along Lordamere's north shore**, from the Dead Field to Dandred's Fold, in 3 minutes; routes went round by the Sepulcher, nearly 7. The shore is on the way through too: from the Sepulcher to Dandred's Fold is 5 minutes, not 7½.
- **The Sepulcher's road north** is ridden out of the town. Routes out of the Sepulcher wandered west and south before turning north (the Sepulcher to Brill was 5½ minutes; it's under 4).
- **Mulgore's ways out are its real ones**: east to the Barrens, north to Stonetalon, and west into Desolace by the pass west of Thunder Bluff. The data had its west and south rims leaking into Desolace, Shen'dralas and Feralas, so routes dropped off the rim (and a low-level character was sent Desolace → Mulgore → Feralas to stay on safe ground).
- **Zephras Isle is reached from Mulgore.** The skycutter's dock on Skywatch Plateau could be left but not come to on the way, so there was no route to the isle from anywhere in Mulgore unless you stood at the dock. Thunder Bluff to the isle is 10 minutes.
- **A lift is no longer taken as a shortcut.** A route west from Thunder Bluff's foot used to say "take the lift into Thunder Bluff" and step off its top onto the ground beyond: the lift stands among the ground's nodes, and was a tie with riding round.
- **West Feralas reaches the east.** From the Forgotten Coast and Feathermoon's ferry landing there was no way up onto Dire Maul's plateau in the data but round through Shen'dralas and Mulgore: the Forgotten Coast to Camp Mojache was 15 minutes; it's under 5.
- **Boats, zeppelins, skycutters and the tram are timed from the game's own schedules**: each leg counts its ride and the average wait for it (a boat's round trip varies from 4 to 8 minutes), where every boat used to count 4 minutes and every zeppelin 3½. Staying aboard the Bravery past Southshore is a leg of its own. Docks and towers sit where the ships actually stop (Southshore's pier, Rut'theran's, Auberdine's Stormwind pier, Zephras Isle's two docks, Powderfuse Port).
- **Searing Gorge to the Badlands through the Kargath pass.** There was no way between the two zones in the data: Thorium Point to Kargath went through Blackrock Mountain and the Riverglades, 11 minutes; it's 3.
- **Crown Guard Tower** joins the Plaguelands' road; routes to and from it used to drop into the Hinterlands and come back.
- **A start in a pocket of the ground** the data never reached (Malaka'jin, Jadefire Glen) now gets a way out to the nearest of the network, as a destination in one always did. There was no route from such places at all.
- **Camp Kosh** is reached up its own road from the Badlands; routes used to go round through Loch Modan.
- **Azshara's road** from Valormok west to Ashenvale is ridden over its bridge, as in the game; routes used to go round by Azshara's south-west corner, two minutes longer.
- Where the terrain data is wrong about what can be walked, MapSeek now carries corrections set by hand: a wall nothing crosses, a cut way, a link the data missed, or a one-way way opened both ways. Each is checked against the game's own ground and a second model of it.
- Towns found by a flight point's name are placed correctly.

### Fixed
- **The game's frame rate fell to about 20** with MapSeek loaded, for players whose minimap zoom indoors and outdoors were set the same. MapSeek's way of telling indoors from outdoors nudged the minimap zoom, which fired the minimap's zoom event, which nudged it again, without end.
- Markers hid and paths glitched while zooming the map with OpenMap.
- Searches without Questie felt slower than with it; the data MapSeek reads for them is now kept between searches.

### Commands
- `/seek time <search>` times a search. `/seek paths` reports on the patrol paths drawn. `/seek maplib own|questie` picks whose code places the markers.

## 1.3.0

### Farm List
- **A list of things to farm, planned as one trip.** `/seek list` opens it. Add items with how many you want of each; MapSeek picks a farm for each and puts them in an order that keeps the riding short.
- Things that share a zone are farmed together: copper and tin in one zone are one stop, not two.
- It takes the same short names the search does: "copper" for Copper Ore, "linen" for Linen Cloth.
- Stops to empty your bags, at a bank or a mailbox, are put in where they're needed. You can turn them off.
- `/seek list start` and `/seek list stop` farm the list shown, or stop.
- A farm's route now starts at the first spot of its loop the way there reaches, not at one it has to ride through the loop to get to.

### Search
- **Coordinates.** Type `59.3, 44.6` (or `59 44`) for a marker at that spot on the zone map that's open, or the zone you're in. Name a zone with them for somewhere else: `barrens 59 44`, `59.3 44.6 the barrens`.
- Towns that are flight points are found by name, such as Splintertree Post.
- **Flight searches show every flight point.** "flight path", "flight master" and the flight button now also mark the game's own flight points where the data has no flight master standing, such as Rog'Mar in the Riverglades.
- **A reminder that a search is still on.** While a search's markers are on the map, a small "Cancel search" tab sits under the search button, which is an X while a search is on. It points at the button to click to take them off.

### Routes
- **A hill is climbed on the side it can be.** A route used to end in a straight line to where you're going, and somewhere near you was just "ride straight there", even when that line ran into a slope too steep to walk up. MapSeek now knows, square by square, where the ground lets you through, and draws the way round to the side you can get up. The limit was measured in the game, on foot: slopes up to about 50 degrees can be walked, steeper ones can't.
- The step you're on is drawn in white, from where you are, on the world map and the minimap. The rest of the route keeps its colours.
- From Razor Hill, routes north follow the road.
- **Fixed:** routes and farming loops weren't drawn on the minimap at all when another addon had loaded its own copy of the map library MapSeek shares with Questie (RXPGuides does).
- A new option, "Show routes on the minimap", turns those lines off or on.

### Farming lists
- A list of farms ("ore farm", "herb farm", "cloth farm", "leather farm", "quest item farm") is now worked out a little each frame, with a bar showing how far it's got. It used to stop the game for a second or more.
- Much less memory is used while a list is worked out, and what's used is given back within a few seconds.

### Questie
- **A Questie tab in the options**, with two buttons: "Keep Questie out of the way" turns off Questie's tracker, its objective icons and its chat lines, leaving its data for MapSeek; "Questie's own defaults" puts them back. `/seek questie quiet` and `/seek questie default` do the same.
- When MapSeek and Questie are both newly installed, Questie starts out quiet. If you already had Questie, nothing of yours is changed.

### EllesmereUI
- With EllesmereUI installed, the route panel, the Farm List, the pinned-spot bar and the minimap button's menu take its look.

### Fixed
- **"Questie's map library isn't available."** After Questie's latest update, searches showed this and nothing else unless another addon happened to bring its own copy of the map library. MapSeek now takes it from Questie the way Questie now offers it.

### Known
- The new texts in this version are in English in every language for now.

## 1.2.0

### Farming loops
- Search "copper farm", "peacebloom farm", "mithril route" or "khadgar's whisker farming" for farming loops. The drop-down offers up to five, each with how many spawn points it passes and about how long a lap takes. The zone you're in comes first if it has enough, then your faction's zones and neutral zones, with the most veins or plants a minute first. The other faction's zones are left out, unless "Include the other faction's NPCs" is on or nowhere else has any.
- **Mob farms.** "linen cloth farm", "runecloth farm", "wool cloth farming" or "large fang farm" offer loops from camp to camp of the mobs that drop it, in the zones where a lap gets the most drops a minute. Each camp counts by its mobs' chances to drop it, using Questie's drop chances. Each lap counts killing time as well as riding, about 12 seconds a mob. Mobs friendly to either faction, elites, and mobs more than 3 levels above you are left out. Each hop between camps follows the travel network, round cliffs and walls. Each mob's marker shows its chance to drop the item, with the item's own icon. The drop-down shows about how many drops a lap gives and how long it takes.
- "Poor Copper Vein" and the like count with their vein: "copper farm" includes Durotar's Poor Copper Veins.
- Hover a loop in the drop-down, or move to it with the arrow keys, to see it on the map: its zone, every vein or plant of it marked, and the loop drawn in green. Click it or press Enter to ride the one you're looking at. The first is picked when the list opens.
- If the loop you pick is far away, MapSeek first takes you there by the quickest route, with flights, boats, zeppelins and your hearthstone, the same as clicking a marker. The loop is drawn in green on the map from the start, so you can see where you're headed. You join the loop at the spot nearest you, and the X on the route panel stops it all, on the way or on the loop.
- On the minimap, the loop and the way there are drawn as lines, with no markers, so the game's own herb and mineral tracking stays in sight. On the world map and in the drop-down, the markers show the herb's or ore's own icon, such as Peacebloom's for Peacebloom or Copper Ore's for a Copper Vein.
- Every vein or plant of it in that zone is marked, the loop is drawn on the map in green, and the arrow points at the next spot. Past the last spot it starts again, lap after lap, until you stop it with `/seek stop` or the X on the map's route panel. A reload or a log out picks it up where it was.
- The loops are worked out from where the veins and plants spawn in WoW Forever and from the continents' own terrain, read from the game's files. Each spot sits on a real spawn. Each hop follows ground that can be ridden, round cliffs, walls and mountains, and swims only near the shore. Spots no way reaches, such as those up a cliff or behind a wall, are left out. Each loop is trimmed to the thickest part of the zone, about 9 minutes a lap on a 60% mount. The terrain doesn't know about buildings, fences or invisible walls, so a hop through a town or camp may still need a small detour. Islands of WoW Forever's own, which have no terrain data, get straight-line loops as before.
- `/seek stop` also stops a route you're following.

### Search
- **Profession specialisations.** "goblin engineering", "gnomish engineering", "dragonscale", "elemental leatherworking", "tribal leatherworking", "shadoweave tailoring", "armorsmithing", "weaponsmithing", and "swordsmith", "hammersmith" or "axesmith" find the trainers who teach them, your faction's only, with what they teach on the marker. A bare "weaponsmith" or "armorsmith" still finds the sellers; add "trainer" for the teacher.
- **Quiet help in the search box.** The grey words in the empty box now suggest a search to try, a different one each time the map opens ("Search, or try "first aid 225""). It changes again whenever you leave the box empty.
- "hillsbrad copper tin farm" or "copper and tin farm in hillsbrad" gives that zone's combined loop alone.
- **Farming learns new spots.** Mine a vein or pick a herb where MapSeek knew of none within 30 yards, and it's kept: a line in chat says so, and the spot is in that zone's farming loops and on the map from then on. It's saved with your settings, for all your characters. A kind of vein or herb the data doesn't have at all is kept too, and can be farmed by its name.
- A farming loop's veins and herbs stay on the map and minimap when the map closes, for as long as you're farming; they go when you stop. On the minimap they're hollow rings, so the game's own tracking dot shows through the middle of one.
- **Experimental: a farming marker hides only where the game's own dot shows** (Options, or `/seek dots`; off to begin with). With Find Minerals or Find Herbs on, MapSeek asks the minimap, each second, what it shows at each of its farming markers within the tracking's reach, and hides the marker only where a vein or herb of that name really is. It doesn't look in a fight. The game doesn't answer this on every build: until it has, markers hide when you're near, as with the option off.
- **Where to learn to make something.** `where to learn heavy silk bandage`, `learn mageweave bandage`, `recipe for ...`: its recipe is found (a manual, pattern, plans and the like) and searched for, so you see who sells it, what drops it or which quest gives it. A first aid bandage no manual teaches goes to the trainers who teach it, and says the skill it asks: `where to learn heavy mageweave bandages` (or `heavy mageweave bandage training`) goes to the Trauma Surgeon.
- **Farming loops rebuilt.** Where a zone has more veins or herbs than a lap has time for, the loop is now the part of the zone where they're thickest, or the whole zone thinned out, whichever passes more a minute; before, a loop that needed one long hop was cut down to six spots. A lone spot that costs a long ride out and back is left out. Durotar's copper loop goes from 21 veins a lap to 59.
- **Skinning farms.** `rugged leather farm`, `thick leather farm` and the like: a loop of the camps of the beasts it's skinned from, as for cloth and other drops. `leather farm` (or `skinning farm`) lists them all, each leather, hide and scale with its best loop and zone.
- **Waylaid Crates.** `waylaid crate farm` (or `waylaid crates`) lists the four tiers, Apprentice to Artisan, each with a loop of the camps of the mobs that drop its crates. Name a tier (`waylaid expert crates`) for a row per crate, a kind (`waylaid ore crate farm`) for that kind in each tier, or both (`expert ore crate farm`) for that crate's loops zone by zone. How often crates drop isn't in the data, so these say so rather than promise a count.
- **Rare drops have farms.** An item its mobs seldom drop (`essence of water farm`, `syndicate emblem farm`) used to find nothing; now it gets a loop, marked a rare drop.
- **Things picked up off the ground have farms.** An item no mob drops but something on the ground gives (a quest's moss, a chest's) gets a loop of where those stand: `ladys tear moss farm`.
- **Fixed:** a farm of something with a small word in its name (`essence of water`, `heart of the wild`) found nothing.
- **What a farm might make.** With TradeSkillMaster installed (or Auctionator, or Auctioneer), each farming loop's row shows what an hour of it might make at auction, as a range (`8g-14g/h`), and its tooltip says so in full. It's a guess: today's lowest buyout and market price, by how much the data says a lap brings (a third of a vein's or herb's spots taken as having one; ten laps an hour at most). Nothing is shown for an item with no price, or one whose drop chance isn't known. `/seek prices off` hides it.
- **Quest items to sell.** `quest item farm` (or `hand in farm`, `turn in farm`) lists the things quests ask for that anyone can sell, the ones people buy for a quick hand-in: murloc eyes, feathers, shards, charms and the like, not a quest's own items (those only drop for whoever's on it), nor cloth, leather, ore and bars, which have lists of their own. Each row is its best loop; the tooltip names a quest that wants it. With a price addon they're ranked by what an hour might make; without, by how many quests want them.
- **A list's row opens that thing's loops.** In `cloth farm`, `leather farm`, `ore farm`, `herb farm`, `waylaid crate farm` and `quest item farm`, picking a row (a click, or Enter) shows that thing's loops zone by zone, to pick one from, rather than riding off round the one on the row.
- **A farm's row is its item.** Shift-click a farming loop's row to link its item in chat; its name takes the item's colour.
- **Item links in the search box.** Shift-click an item, in a bag or in chat, while the search box has the cursor, and its link goes in the box as it would in chat's: `[Copper Ore]`. It's searched for by its name; add `farm` for its farm. A farm you search for by an item's name shows the link too (`[Heavy Scorpid Scale] farm`), and hovering the box shows the item's tooltip.
- **FojjiCore's arrow names the step.** With FojjiCore, a route's or a farming loop's waypoint carries the step's words, so its arrow window says where it's pointing (`Durotar: spot 3 of 24`) rather than `Map Pin`.
- **The route's panel comes out of the map.** A button beside its X pops the route (or a farming loop's next spots) out into a window of its own: it stays up with the map closed, goes where you drag it and is remembered there. The same button puts it back on the map.
- **The drop-down grows to fit.** A farm's row, with its zone, its lap and what it might make, was cut short; the list is now as wide as its longest row needs.
- **A flight master right by you is used, even one you don't have.** A route flies from a flight master within a short ride of where you stand when that's the quicker, picking its flight path up on the way, whether or not flight paths are being picked up along routes. It used to send you to the nearest one you already had.
- **A mob farm shows its areas.** Farming something mobs drop (`long elegant feather farm`, cloth, leather) marked every single mob, a marker each. It now draws the camps as areas, one marker at the middle of each naming what drops it there, as a search for the thing does.
- **Fixed:** routes rode straight over the mountains between the Blasted Lands and Stranglethorn Vale, which the game doesn't let you cross. They go round by Deadwind Pass and Duskwood.
- **Fixed:** the way to Zul'Gurub went the long way round under the mountains; it goes by Lake Nazferiti and up the stairs to the gate, and back the same way.
- **Fixed:** Thunder Bluff's lifts were marked on the wrong side of the bluff, and the way from Thunder Bluff to Desolace looped north of the pass; it goes straight through it.
- **Lockpicking.** `lockpicking` (or `lock picking`, `footlockers`, `level lockpicking`) lists the boxes a rogue practises on, zone by zone, the lowest skill first: practice lockboxes, the strongboxes off Ratchet, and battered, waterlogged, dented, mossy and scarlet footlockers. Each row says the Lockpicking it asks and how many boxes; it's red when it asks more than you have, or the zone is above your level. On a character that isn't a rogue the list still shows, every row marked rogues only. The skill numbers are Classic's and may differ here.
- **Cloth, ore and herb lists.** `cloth farm`, `ore farm` (or `mining farm`) and `herb farm` list each cloth, ore or herb with its best loop and zone, in the order you'd learn them.
- **Farms for higher levels are shown too, with a warning.** Every farm and list now shows the loops for your level first, then those for higher levels so you can plan ahead, marked in red with the level (`level 45+ mobs: too high for you`, or the zone's level for ore and herbs).
- **Blackmaw Hold** is in the search (Azshara). Any dungeon can also be searched with "entrance" after its name, in full or in part: `blackmaw entrance`, `deadmines entrance`.
- A route to a spot inside a walled town, or on ground the travel network couldn't reach, is planned to the nearest ground it can reach, instead of no route at all.
- Less memory: searching another farm lets the last one's loops go, they're let go a minute after the map closes too, and working one out uses about a third of what it did.
- **Farming markers on the minimap too.** A farming loop's veins and herbs now show on the minimap as well as the map. While Find Minerals or Find Herbs is on, the ones within its reach are hidden on the minimap, so the only dot you see close up is the game's own: a real node.
- **Farming two or three things together.** "copper and tin farm" (or "copper, tin & iron farm") makes one loop a zone through all of them, and each row says the split by spawns: "Hillsbrad Foothills: 30% Copper Vein, 70% Tin Vein". Each spot keeps its own icon on the map. A zone with only one of them isn't offered.
- **A zone's farms.** "hillsbrad farm" lists every vein and herb with enough spawns there for a loop, the most spawns a minute's riding passes first. "hillsbrad ore farm" or "hillsbrad herb farm" keeps to one profession. Pick a row to ride that loop.
- **Riding trainers.** "where to train riding", "mount training", "learn to ride" or just "riding" mark your faction's riding trainers, the gnomes' Mechanostrider Pilot included. "riding" alone used to list riding mounts and an enchanting formula.
- **Training past a cap.** "how do i train past 225 first aid", "tailoring 150" or "fishing past 225" mark what takes that skill further, and the status line says what to do. Past 75, 150 and 225 that's the trainers who teach the next rank. For first aid, cooking and fishing, Expert (past 150) is a book, and its vendors are marked. Artisan (past 225) is a quest, so its giver is marked along with the trainer in your capital who sends you there ("Horde Trauma", then "Triage"). With no number ("train cooking"), it goes past the cap you have now.
- **Trainers by rank.** "artisan tailoring", "expert leatherworker trainer" or "journeyman alchemist" find the trainers who teach up to that rank or higher, the rank asked first.
- **Class quests.** "class quests" marks the class quests you can pick up now. "warlock quests" marks where each of a class's quest lines starts. "bear form quest", "voidwalker quest", "defensive stance quest", "taming the beast" or "earth totem quest" mark where that quest line starts, for your faction.
- **Quartermasters.** "argent dawn quartermaster", "timbermaw rep" or "zandalar rewards" mark the faction's vendors, with their wares on the marker's card.
- **Reputation turn-ins.** "timbermaw rep" or "zandalar rep" also marks who takes the faction's repeatable turn-ins that you could hand in now, with what to bring on the marker ("Feathers for Grazle: bring Deadwood Headdress Feather"). A turn-in that needs your standing to be in a certain range shows only while it is, and one that opens after another quest marks that quest first ("Timbermaw Ally: do it first, to open Feathers for Grazle"). The things to bring are listed in the drop-down: pick one to see where it drops, or its "Farm" line for a farming loop. "rep farms" marks every faction's turn-ins you could do now and lists the factions to pick from. Darkmoon Faire turn-ins are left out, and turn-ins whose giver is inside a dungeon (the Thorium Brotherhood's, in Blackrock Depths) can't be marked.
- **Rare mobs.** "rares" marks the rare mobs around your level, each with its level and whether it's elite, at every spot it can spawn. "rares in feralas" marks all of a zone's.
- **Graveyards.** "graveyard" or "spirit healer" marks every spirit healer. While you're dead, the one the game will send you to when you release is marked "Where you'll come back when you release" and highlighted, straight from the game. While you're alive, the nearest spirit healer in the zone you're in is highlighted as the most likely one. The server picks from the graveyards linked to your zone, so it's usually that one but not always.
- **Dungeon quests.** "deadmines quests", "brd quests" or "quests for scholo" mark who starts each of that dungeon's quests you could still take: your faction's, your class's, and not ones you've done. Each one shows its level. Of a line of quests, only the first you haven't done is shown.
- **Attunements and keys.** "mc attunement", "onyxia attunement", "bwl attunement", "naxx attunement", "ubrs key", "brd key" or "scholo key" mark where that quest line starts, or the next step you haven't done. "attunements" marks them all. Onyxia's line is your faction's own.
- **Food, water and ammo.** "water", "food", "arrows", "bullets" or "ammo" mark the vendors of the best you can use at your level, not every vendor of any kind. "food" covers each kind of food (bread, meat, cheese, fruit, fish, mushrooms), and "ammo" what your ranged weapon shoots.
- **Quests for your level.** "quests" or "quests here" marks who starts the quests you could pick up now in the zone you're in: your faction's and class's, not done or already on, with the quests before them done, and not grey. Each shows its level in the game's colour for how hard it is. The status line names the zones with the most others for your level, to go on to. "quests in the barrens" does it for another zone, and "all quests" keeps the grey ones. Holiday quests, repeatable turn-ins and books are left out. It no longer needs Questie itself, only QuestieDB.
- **Quests you're on.** Search a quest by name while it's in your quest log and MapSeek shows where to go for it now, not who gave it to you: where the mobs to kill are, where the items you need drop, the things to use or loot, and the place to find. Objectives you've already finished are left out. Once it's all done, the marker is who you hand it in to. A quest with nothing on the map, such as a talk or an escort, also shows where you hand it in.
- **Quest lines with one name.** When several quests in a line share a name ("Arugal's Folly"), searching it marks who starts the step you're up to, not the first. If you've done them all, MapSeek says so.
- **The whole quest line.** Search a quest that's part of a line and the drop-down lists every step, from the first to the last, each with its level. Steps you've done are grey with a tick. The one you're on or up to is gold, and is marked "on it" or "next". Hover a step to see it on the map, or click it to show it and keep the list open to try another. A step you're on shows where to go for it. Any other step shows who starts it, even one you've done, so you can help a friend to the start of the line. A long line shows the 12 steps around where you are. Where a line branches, it follows the quest with the same name first, and leaves class quests as side lines.
- Item searches no longer leave out neutral (yellow) mobs. WoW Forever's data marks them as friendly to both factions, so "duskbat wing" found nothing. Mob farms count them too.
- Dungeons listed more than once in WoW Forever's data (Dire Maul's wings, Scholomance, Stratholme) are now always read the same way.

### Travel time on markers
- A marker's card now says how long it takes to get there, "About 4 min away", by the quickest way: riding, flights, boats and your hearthstone. It's shown while the world map is open and you're not in a city, for markers more than 100 yards away.

### Nearest by the way there
- The nearest match (its green ring, the nearest button, the status line's "nearest") is now the quickest to get to, not the closest as the crow flies. Of the few closest, MapSeek plans the way to each, riding, flights, boats and your hearthstone, and picks the soonest reached: the one across a river or up a cliff loses to one a little farther on your side. It's worked out while the map is open, again only once you've moved, and in a few milliseconds. In a city it's still the closest, as the routes don't walk a city's streets.

### A look before you pick
- Hover any row of the drop-down (a suggestion, a spelling fix, a place, a recent search, a favourite), or move to it with the arrow keys, and after a moment its markers show and the map glides to the nearest. A place's row takes the map there. Click it or press Enter to pick the one you're looking at. Close the list without picking and the map goes back to what's in the search box. Nothing you only look at goes into your recent searches.

### The search button
- While a search is on the map, the search button shows a red X over its scope. Click it to clear the search. The button then goes back to the scope, which opens and closes the search box as before.

### Fixes
- The most common ore veins and herbs (Copper, Tin, Silver, Gold, Iron, Mithril and Thorium, Peacebloom, Silverleaf, Earthroot, Mageroyal, Briarthorn, Bruiseweed and others) are found again. Questie empties their spawns for its own map, so they were missing from farming loops and from searches like "copper ore". MapSeek now reads them from QuestieDB's stored data.
- A route plans itself again from where you are when you leave it: more than about 350 yards from the step you're on for a few seconds, for example after taking another flight or riding a different way. It doesn't do this while you're on a flight or a boat, or casting your hearthstone.
- Routes no longer cross mountains or borders that can't be crossed. Tirisfal Glades has no ground way into Alterac Mountains. Silverpine Forest reaches Alterac Mountains only near the Sepulcher. Searing Gorge can be entered on foot only through Blackrock Mountain, since the cave from Loch Modan needs a key, so routes into and out of the gorge go through Blackrock Mountain or fly.
- Routes now know what stands on the ground, not only its shape. The network is rebuilt from the game's own collision models: buildings, walls, fences, rocks and tree trunks block, and bridges, docks, stairs and ramps can be walked. Before, a route could pass through a wall or a building.
- A marker joins the route network at the point that can actually reach it over the ground. Before, it joined the nearest point on the map, which could be across a cliff, a wall or a gorge.
- Steep ground is stricter going down. A slope too steep to walk down counts as a fall. A fall that would hurt is taken only when it's 30 yards or less with no second drop under it, or into deep water, and the route step says so: "a drop of about 20 yards on the way".
- Ground that can't be reached on foot (a mesa's top, a walled yard) is treated as such. Freewind Post is reached by its lift, and Darnassus from Rut'theran Village by the portal.
- The Greymane Wall's gate counts as shut.
- Routes and farming loops go round the other faction's towns. A town is where that faction's innkeepers, flight masters, vendors and trainers stand together. A farming loop leaves out the veins and herbs inside one, and a route passes through one only when you start there or are headed there.
- A route or farming step whose way passes near a town of the other faction says so: "careful: passes Southshore".
- A farming loop that met a town of the other faction keeps its own way over the terrain up to the town, goes round the town's edge on dry ground (a river is swum, the sea isn't), and picks the side that doesn't run over the rest of the lap. Before, that hop could ride half the zone away and back, across the loop.
- Where going round a town is a long ride with nothing to gather, the lap is cut there and the half that passes more a minute is kept, when that's clearly more than the whole lap passes.
- Fixed an error in a fight ("attempt to compare ... a secret number value"): the game keeps your speed secret in combat, and the mount-speed check now leaves it be.
- A spot you ride past without coming near enough no longer leaves the arrow pointing back at it. Once you're beyond it on the way to the next one (or nearer the next one than the spot itself is) for two seconds, the route moves on. This covers a farming loop's spots and a ride followed by another ride; a flight master, a dock or a lift still has to be reached.
- Fixed: a farming loop counted a new lap every half second while you stood at its last spot, filling the chat with "Lap 51 of Tin Vein ...".
- Routes inside a city stay inside it. Flying in to Orgrimmar to reach the Valley of Spirits no longer walks out of the gate into Durotar and back in, and the same goes for Stormwind and the other cities. Routes to Thunder Bluff go up its lift, not to the ground under the mesa.
- After stopping for a flight path on the way, the route goes on from that flight master instead of doubling back to where the ride began.
- Routes no longer send you to flight paths the game has retired, such as "zzOLDPowderfuse Port", when picking up flight paths on the way.

## 1.1.0

### Routes
- Set a map pin (Ctrl-click the map, or click a map pin link in chat) somewhere far and MapSeek plans the quickest way there too.
- Click a marker (or the nearest button) somewhere far and MapSeek plans the quickest way there: riding, the flight paths you know, the boats, zeppelins, Deeprun Tram, Dalaran's skycutter and Stormwind's portal, and your hearthstone when it's ready.
- The steps show on the map ("1. Go to the flight master: Tarren Mill  2. Fly to ... 3. Take the boat to Menethil Harbor"), each with about how long it takes. An arrow (TomTom's, when installed) points at the step you're on, and moves on to the next as you get there. The X stops it.
- The route is drawn on the world map from where you are: riding a solid gold line, flights dashed blue, boats and zeppelins dashed teal, a numbered dot at each step. Done steps drop off it, and it follows you as you go.
- Lifts, bridges, tunnels and gates between zones are steps of their own: "Take the lift into Undercity" (or Thunder Bluff, or the Great Lift into Thousand Needles), "Cross the bridge into Arathi Highlands" (Thandol Span), "Go through the tunnel into Wetlands" (Dun Algaz), "Go through the gate into Ashenvale" (Mor'shan).
- Routes go by your level: riding through a zone well above you counts for more, so a route goes round it, or flies or sails over it. One that has to ride through says so on the step ("careful: level 43-50").
- **Pick up flight paths on the way**, a box at the foot of the route: the flight masters near the route whose flight paths you don't have yet become stops of their own ("Pick up the flight path: Tarren Mill"), for quicker travel later: the ones in the zones you ride through that going by adds little riding to (the Crossroads, Camp Taurajo, Gadgetzan on the way to Zul'Farrak). Ticking or clearing it plans the route again, and it's kept for next time.
- Swims: a route can swim across a lake when that's quicker than going round (Lordamere Lake, from Silverpine by Fenris Isle to the Alterac shore by Dalaran), "Swim to Alterac Mountains". Swimming counts at swimming speed, so it's only taken when it's really quicker.
- A route survives a reload or logging out: it picks up at the step you were on.
- A route planned before your flight paths on a continent were known is checked at the flight master: a flight you can't take from there gets the route planned again, from there, with only the flight paths you have.
- At the flight master, the flight path to take pulses purple on the flight map, its own icon glowing, with "Fly here" just over it.
- The flight paths a character knows are learned when you open a flight master's map. Before you've opened one on a continent, the ones standing where you've explored count (you've been there, so you very likely have it). How long each flight takes, and how fast your mount is, are learned as you go.
- Riding and swimming follow the ground: a travel network over each continent's terrain, built from the game's own map files (`tools/terrain`), finds the real quickest way: round a mountain, through a pass, across a lake or along a shore when swimming is quicker, down into a crater where the ground allows. Slopes too steep to climb and drops too far to survive aren't taken. The way is drawn on the map as it will be ridden.
- Lifts, gates, tunnels and ramps the terrain alone can't tell (the Great Lift, Timbermaw Hold, Dun Algaz, Blackrock Mountain, the crater ramp out of Un'Goro) are listed, and join the network on both sides of the mountain.
- A ride through a zone is one step, "Go into Duskwood"; a swim its own, "Swim to Menethil Harbor"; a lift or tunnel its own.
- The line drawn ends where the way reaches the goal, not past it and back (Zul'Gurub's entrance: at the foot of the stairs, not a loop inside the gate), and starts from where the way passes you.

### Fixes
- The count under the search ("2 found, 2 spots") sits under the search box when it's open, not under the quick buttons; under the suggestions while they're up.

### Looks
- One look throughout: the suggestions, the More menu, the minimap's quick searches and the bar's buttons are flat dark panels with a thin gold edge, as the search strip is.
- The count under the search sits in a dark pill of its own, its numbers gold and its parts set off with dots ("12 found · 12 spots · nearest 340 yd"); the same for an item's "sold by 2 vendors · gathered from 32 spots...".
- While Questie's data is read the first time, that pill fills gold across as it goes, in place of the bare percentage.
- Each row of the list carries an icon for what it is: a bag for an item, a speech bubble for an NPC, a map for a place, a key for a dungeon, a ! for a quest, a watch for a recent search, a star for a favourite, a tick for a spelling fix. The rows are a little taller.

### Fonts
- A font setting (Options, "Font"): the game's own, or any font an addon shares through LibSharedMedia (Numen or Expressway from FojjiCore, EllesmereUI's, and so on). Every MapSeek text changes at once, sizes kept: the search box, the list, the status, the settings, the labels on the map and the route steps.

### The minimap button
- A click on it opens a column of your quick searches, up to 6 of your favourites (the Minimap column of the settings' Favourites tab picks them; your bar's buttons to start with). A click on one finds it on the minimap without opening the map (the nearest few outside your zone on its edge, pointing the way); a click on it again clears it. Shift-click still opens the map with the search box; right-click the settings.
- Which way they open is a setting (Options, "Its quick searches open"): a row to the left (the default) or right, or a column down or up.
- The single "minimap button finds this" search is gone, replaced by the column.

### Search
- `pole arm trainer`, `cross bow trainer`, `2 handed sword trainer` and `1 hand mace trainer` work, as the one-word spellings do.
- Dungeons: `dungeon` (or `dungeons`, `instances`) marks every dungeon's entrance, its levels in its tooltip (Forever's own new dungeons too). `dungeons for my level` only the ones for you (within two levels); `dungeon in westfall`, a zone's. `raids` (or `raid entrance`) the raids; `raid` alone is still your group.
- Bags by kind: `reagent bag` (or `regent bag`, `profession bag`) shows every gathering and crafting bag: herb, mining, skinning and enchanting bags and the reagent bags. `herb bag` (`herbing bag`), `mining bag`, `skinning bag`, `enchanting bag` and `soul bag` show that kind. A bag a vendor sells shows its vendors; one a profession makes, who sells its pattern.
- `boat`, `zeppelin`, `tram`, `skycutter`, `dock` and `transport` mark Forever's docks and towers, each named for where it goes ("Boat to Ratchet"); your faction's only.
- `auction house`, `flight path`, `taxi`, `hearthstone` and `mail` work as `auction`, `flight`, `innkeeper` and `mailbox` do.
- `mail box` is `mailbox`; `marshalmcbride` run together still says Marshal McBride is Alliance.
- `boat to ratchet`, `zeppelin to orgrimmar`, `ship to booty bay`: the ones that go there (or "No boat goes to Ratchet").
- `two handed axe`, `2h axe`, `1h mace` on their own find the weapon masters who teach it (a bare `sword` still finds the sellers).
- An item a profession makes that no vendor sells or mob drops (`mechanical squirrel box`, `arcanite bar`) finds who sells its schematic, pattern, plans or recipe.
- `fishing rod` is `fishing pole`. And a search of a few words that finds nothing as a whole offers it without one of them ("Did you mean"): `heavy rod` offers `rod`, `guild bank` offers `bank`, `pet food` offers `food`.
- `class trainer` and `profession trainer` are `trainer`; `battleground` is `battlemaster`; `soul shard bag` is `soul bag`; `mage portal` is `portal trainer`.
- `where is the inn`, `nearest repair`, `find me a mailbox`, `how do I get to Ratchet`: the filler's ignored when the whole finds nothing.
- Questions too: `is there a herb trainer in org?`, `who sells linen cloth`, `what drops silk cloth`, `where does linen cloth drop`, `can I buy a fishing pole in Orgrimmar`, `any mailbox near the crossroads`, `where do I learn fishing` (its trainers), `who teaches polearms`. The question mark doesn't matter.
- `mount` (or `mount vendor`) finds the mount sellers by their titles (Kodo Mounts, Horse Breeder, Saber Handler, Mechanostrider Merchant); `ammo` the bowyers and gunsmiths.
- Part of an unsold item's name finds it: `boar meat` is Chunk of Boar Meat, and shows where it drops.
- An NPC of the other faction, searched by name, says so: "Marshal McBride is Alliance. Turn on ..." rather than nothing found.
- Where an item's got, by kind, all at once: the vendors who sell it, the veins or plants it's gathered from (a marker each), and the mobs' areas, each marker saying which ("Gathered: Copper Ore", "Dropped: Copper Ore (most here)"), and the count under the search listing them: "Copper Ore: gathered from 118 spots in Silverpine Forest; dropped by mobs in 4 places in Silverpine Forest (and 15 other zones)".
- An ore or herb's mobs show only when how often they drop it is known: `heavy stone` no longer sends you after panthers.
- The suggestions offer items no vendor sells too (drops, quest rewards): typing `angler` lists Nat Pagle's Extreme Angler FC-5000, not just the quest.
- Quest items: an item a quest needs says so on its markers ("Quest item for: Gold Dust Exchange"), and an item a quest giver hands you (`marshal mcbride's documents`) marks that giver, "A Threat Within (gives Marshal McBride's Documents)".
- An item a quest rewards finds the quest's giver: `nat pagle's extreme angler fc-5000` marks Nat Pagle, "Nat Pagle, Angler Extreme (rewards Nat Pagle's Extreme Angler FC-5000)" in his tooltip. Items no vendor sells only; the drop sources, when it has those too, show as well.
- An item's drop sources are kept once read, so the search on Enter after typing it is instant.
- Memory: a continent's travel network (a couple of MB) is let go a minute after the map closes when no route is on, as the suggestions' vocabulary is; read again in a few ms when wanted.
- Spaces don't matter any more, in either direction: a name typed run together or split where it isn't finds the same as typed right.
  - Items: `simpleflour`, `heavybrownbag`, `fishingpole`, `peace bloom` (its plants too), `mage weave cloth`, `linencloth`, `copperore`.
  - NPCs: `marshalmcbride`, `marshal mc bride`. Quests: `lazypeons`, `lostpilot`.
  - Places: `org rimmar`, `storm wind`, `iron forge`, `ashen vale`, `stone talon` go straight there.
  - Trainers and the rest: `firstaid trainer`, `black smithing trainer`, `leather working trainer`, `en chanting trainer`, `mail box`, `camp fire`, `meetingstone`.
  - The suggestions as you type too: `peace bl` suggests Peacebloom, `simpleflo` Simple Flour.

## 1.0.5

### Where an item is found
Search an item no vendor sells and the map shows where to get it, instead of "No vendor sells".
- **Ore and herbs** (`copper ore`, `peacebloom`, `black lotus`): a marker, with the item's icon, on every vein or plant in one zone: yours when it has a fair number, else the nearest that does. A herb a vendor also sells (`peacebloom`, `silverleaf`) shows its plants beside the vendors, and the map goes to the plants.
- **Things mobs drop** (`linen cloth`, `silk cloth`, `mageweave cloth`, `gnoll paw`): areas drawn on the map, filled and outlined the way the game draws a quest's area, instead of a marker on every mob.
  - Every good spot in the zone (up to 6), each with its own marker. Your own zone first when it has a fair spot, else the nearest zone that does.
  - The best spot is purple, the rest gold. A spot counts by how often its mobs drop the item (Wowhead's drop rates) and how packed they are, so a tight camp beats a sprawl of a few more.
  - Mobs that seldom drop it, and mobs friendly to you, are left out; so is chests' random loot.
  - Hover a spot's marker for what drops it there, how often, and the other zones it drops in.
- The areas are drawn on the minimap too, turning with it, cut at its edge, round or square (EllesmereUI's square minimap included).
- They stay while the map's open and go when it closes, whatever "Keep markers after the pulse" and "Closing the map clears the markers" are set to.

### Pin a spot
- Hover an area on the world map (it lights up) and click it to pin it. It stays on the map and minimap after the map closes, and after a reload, with the item's icon on the minimap's edge pointing the way when it's further off.
- A **Pinned** bar on the map names it: click it to see its zone, or its X to unpin.

### Handing in quests
- `turn in the lost pilot`, `hand in lazy peons`, `where do i turn in sarkoth` or `kobold camp cleanup turn in` show who takes the quest. Hover them for the quest's name.

### Places
- Zones by the short names players use: `stv` (Stranglethorn Vale), `epl`, `wpl`, `hf`/`hills`, `tn`/`1k needles`, `dwm`, `stm`, `sg`, `bl`, `sos`, `rr`, `lm`, `ef`, `wf`, `wl`, `dwp`, `spf`, `tg`, `hl`, `steppes`. They work inside a search too: `repair stv`, `innkeeper in stv`.
- `bs` and `lw` mean blacksmithing and leatherworking: `bs trainer`, `lw trainer if`.

### Licence
- MapSeek is now All Rights Reserved: please don't copy, modify or reupload it. Versions up to 1.0.4 were MIT, and copies of those stay MIT.

## 1.0.4

### Quests by name
- Search a quest's name to see who gives it: `lazy peons` finds Foreman Thazz'ril, `theldurin the lost` Gerrig Bonegrip in Ironforge (or Zaruk, for the Horde). Hover the marker for "Starts the quest:" and its name.
- A slip or two in the name still finds it (`moktharadins enchantment` is Mok'thardin's Enchantment), and so does part of it when nothing else matches (`lost pilot`).
- Start with `quest` to look at quests only: `quest the lost` shows everyone who gives a quest with "the lost" in its name.
- A quest that starts from an item shows what drops the item.
- Only your faction's quests, unless "Include the other faction's NPCs" is on. A quest only the other faction can take says so, rather than nothing found.
- Quest names show in the suggestions as you type, after the rest.

### Weapon trainers
- Search a weapon with "trainer" (or "training", "skill") to find the weapon masters who teach it: `staff trainer`, `polearm trainer`, `2h sword trainer`, `two handed axe training`, `gun skill`, `fist weapon trainer`. Hover one for every weapon it teaches.
- `weapon trainer` and `weapon master` find all of your faction's weapon masters (no longer Nixi Fireclaw, a drink vendor, or Quartermaster Hicks, a weaponsmith).
- A weapon on its own (`staff`, `bow`) is still a search for the vendors who sell them.

### Favourites and quick buttons, one list
- Your quick buttons are favourites now: one list of the quick searches and the searches you starred, each with **Bar** and **Pin** boxes. Everything you'd starred or put on the bar is kept. A new install starts with Repair, Innkeeper, Trainer, Vendor, Flight master and Mailbox.
- **+ Add a quick search** under the list stars any of the others (Banker, Your group, Meeting stone ...).
- Up to 20 favourites, from 8.
- A starred search's button icon is picked from a menu of them all (click its icon in the Favourites tab).
- The list that opens in the empty search box leaves out the favourites already on the bar. The star at the end of the box still lists them all.

### The bar
- Right-click a quick button for a menu: pin it (or unpin it), have the minimap button find it, change its icon (a starred search's) or take it off the bar.
- Put the search bar where you like (Search tab, "Search bar"): **Top** (over the breadcrumbs, as before), **Bottom** (along the bottom of the map) or **Custom**. Click **Move it**, drag the bar (the search box comes with it) anywhere on the map, then right-click it or click **Done**. It stays put when the map is resized.
- Off the top bar, the breadcrumbs stay free to use. Low on the map, the suggestions, the count, More and the settings open upwards.

### Minimap button
- What a click on it finds is a drop-down in Options ("Minimap button click"), with your favourites first; or right-click a button on the bar and pick **The minimap button finds this**.

### Settings, tidied
- Three tabs: **Favourites** (your bar's order on top, then every favourite), **Search** (where the search bar sits, what a search looks through, recent searches) and **Options** (markers, the minimap button, the repair reminder).
- The grid of quick buttons to pick from is gone: **+ Add a quick search** and the **Bar** box do the same job in one place.

### Nothing found
- Press Enter on a search that finds nothing and what you typed blinks red for 2 seconds, then turns back, still in the box to change or clear. Under it, the list says why: "Nothing found for ...", "No vendor sells ...".

### Spelling
- Apostrophes are optional everywhere: `mokthardin` finds Far Seer Mok'thardin, `onyxias` suggests Onyxia's Lair, `hunters` Hunter's Boomstick.
- "Did you mean" only offers a fix that finds something. If the closest spelling finds nothing, it tries the next closest, and offers none when nothing would be found.
- Plurals come out right: `supplys` is supplies (not supply), `studdies` studies (not studded).
- A misspelled or plural item that no vendor sells says so: `mithril cassing`, `mithril casings` and `mageweave clth` say "No vendor sells" Mithril Casing and Mageweave Cloth.
- Words from quest names and from items no vendor sells count as real words, so `studies` isn't "fixed" into something else.
- A short search that's nothing like any place (`zzzz`) no longer offers a list of places, and a place's name (`plaguelands`) isn't taken over by quests with it in their names.

## 1.0.3

### Dungeons
- WoW Forever's own dungeons can be searched: The Drowned City (`drowned`), Krol'dok Stronghold (`kroldok`), Alcaz Island Prison (`alcaz prison`), The Shaper's Terrace and Manor Mistmantle, alongside Demon Fall Canyon, The Tainted Scar, Karazhan Crypts, The Hall of Thanes and the rest. Where the game itself lists a zone's dungeon entrances, MapSeek uses those too, so new ones turn up as Forever adds them.

### Minimap button
- Pick what a click on it does (Options, "Minimap button click"): open the search, as before, or find one of the quick buttons' searches straight away (Repair, Vendor, Innkeeper, your group ...) or one of your favourites. Click again to close the map. Shift-click always opens the search.

### Your group
- Search `party`, `raid` or `group` to see where everyone in your group is, each with their class's icon. Hover one for their level, class, where they are and how far. Their markers follow them as they move.
- Or search someone in your group by their whole name (`Bobbert`; `bob` stays a search for Bob McNaught and the like).
- Anyone in a dungeon or offline, who can't be put on the map, is listed under the count.
- Right-click someone's party or raid frame (or them as your target) and pick **Find on Map**.
- A **Your group** quick button, to put on the bar from the settings.

### Places, spelled any way
- A place's name with a slip in more than one word still goes there: `drown ciuty` (The Drowned City), `scarlet monastary`, `razor fen kraul`, `molten cor`. So does the start of each word (`drown city`, `hall of thane`), and a name split or run together where it isn't (`krol dok`, `un goro`, `dead mines`).
- Most of a zone's, city's or dungeon's name goes there, even when it's also in other names: `stranglethorn` is Stranglethorn Vale, not the vendors of Stranglethorn Seed; `blackfathom`, `shadowfang`, `deadmine`, `stockades`, `westfal`, `elwyn`, `thunder bluf` the same. Someone's own name still finds them (`mistmantle` finds Stalvan Mistmantle), and `darkmoon` still finds the Darkmoon Faire's people.
- "Did you mean": a search that could be more than one place lists them under the search box to pick from. `razorfen` offers Razorfen Kraul and Razorfen Downs, `plaguelands` Western and Eastern Plaguelands, `blackrock` Blackrock Spire and Blackrock Depths. When the search found NPCs or items too, they're on the map as usual and the places are offered beside them. Pick one with the mouse, or with the arrow keys and Enter, as with the suggestions.
- Dungeons from later expansions that Forever doesn't have (Scarlet Halls, Blackrock Caverns, the Caverns of Time dungeons and the like) are no longer offered as places.

### Languages
- MapSeek speaks your game's language: German, French, Spanish (Spain and Latin America), Italian, Portuguese (Brazil), Russian, Korean and Chinese (Simplified and Traditional), as well as English. Its search box, status line, tooltips, settings and messages are translated; what you type to search is unchanged.

## 1.0.2

### Places
- Search for a zone, city, continent or dungeon by name (`elwynn forest`, `stormwind`, `deadmines`) and the map goes there, breadcrumb and all. Places show in the suggestions as you type; press Enter or pick one to go. A start of a name that finds nothing else goes there too (`elwynn`).
- With OpenMap, the map zooms out to show where you are and where you're going, then zooms in to the place.
- Dungeons, raids and battlegrounds by name (`deadmines`, `blackrock spire`, `wailing caverns`): a marker on each entrance (from Questie's data), the nearest ringed, and the map goes there. Click an entrance for a waypoint.
- Dungeons go by their short names too: `rfc`, `wc`, `dm` (the Deadmines), `sfk`, `bfd`, `stocks`, `gnomer`, `rfk`, `sm`, `rfd`, `ulda`, `zf`, `mara`, `st`, `brd`, `lbrs`/`ubrs`, `dme`/`dmw`/`dmn` (Dire Maul), `strat`, `scholo`, `mc`, `ony`, `bwl`, `zg`, `aq20`, `aq40`, `naxx`, `av`, `wsg`, `ab`, `kara`. Typing one puts the dungeon first in the suggestions.
- With OpenMap, going a long way always zooms out and back in. A place shown further out than where you are (Razorfen Kraul's Barrens from Scarlet Monastery) used to pan straight across instead.
- With OpenMap, every search does the same: the map zooms out and in to the nearest result (on Enter, a pick, a quick button; not while you're still typing).
- Towns and other named areas inside zones too, over 600 of them (`skywatcher plateau`, `goldshire`, `crossroads`): the map goes to the zone and a marker shows the spot. Click the marker for a waypoint. With OpenMap the map zooms in on the town itself. In the suggestions, a town's zone shows beside it.
- Search inside a place by naming it at the start or end: `herb trainer org`, `org herb trainer`, `innkeeper in the crossroads`, `repair goldshire`. The status line says where it looked. If nothing there matches, it searches the whole thing as usual (`booty bay bruiser` still finds the Booty Bay Bruisers).
- Short names for the cities and a few towns: `org`, `sw`, `if`, `tb`, `uc`, `darn`, `xroads`, `bb`.
- Misspelled places go to the place: `orgrimar`, `stormwnd`, `elwyn forest`. The spelling fix no longer "fixes" MapSeek's own words (`inn` stayed `inn`, not `ink`), or a place named alongside a typo (`herb trainr org` finds Orgrimmar's herbalism trainer).
- Places can be typed run together: `diremaul`, `zulfarrak`, `thunderbluff`, `elwynnforest`.
- `reagent vendor` finds every NPC whose title mentions reagents (Reagent Vendor, Reagent Merchant, Reagent Supplies, Reagents & Poisons ...), not only the ones titled exactly "Reagent Vendor". It's forgiving of spelling: `regents vendor`, `reagents`, `reagent merchant` all work.
- "The" is optional both ways: `crossroads` finds The Crossroads, and `the lower wilds` finds Lower Wilds (as the game names it).

### Look
- Dungeon entrances show the game's own dungeon icon; cooking fires show a campfire.

### Memory
- About 40% less memory while the map's closed (around 7 MB, from about 12): NPCs with no place in the world (over a quarter of them, which could never be shown) aren't kept, a vendor's wares are worked out when you look at them rather than kept for every vendor, and the suggestions' word list is let go a minute after the map closes (it's built again, in a moment, the next time you type).

### Search bar
- The search box is open whenever the map opens, over the breadcrumbs. Click the search button to hide it and use the breadcrumbs. Turn this off in Options ("Open the search with the map") to have the search open only from the search button, as before.
- With the search open with the map, the X in the search box only clears it (the markers and what's typed) and leaves it open.
- The minimap button's first click always puts you in the search box; a second click closes the map.

## 1.0.1

### Search bar
- The search bar stays open after you press Enter. It now stays open until you close the map, click its X, or click the search button again. Clicking away or pressing Esc no longer closes it (Esc still leaves the box and closes the drop-down list).
- With EllesmereUI, the typing cursor stays right after the last letter typed, instead of drifting away from it as you type. The search box keeps the game's own font for what you type.

### Minimap button
- A MapSeek button on the minimap. Click it to open the map with the search box ready to type in (click again to close the map); right-click for the settings; drag it around the minimap.
- Turn it off in Options, or with `/seek button on|off`.

### Recent searches
- Each recent search has an X to remove it.
- A new setting picks how many recent searches show (Options, under Recent searches). It starts at 3, up to 10.

### Cooking fires
- Searching `fire` or `campfire` now finds every kind of fire you can cook at: bonfires, cozy, blazing and dwarven fires, fire pits and stoves, not only campfires. `bonfire` and `stove` work as searches too. Burnt-out campfires are left out.

### Bags
- Bag, pouch, pack, satchel and sack mean the same in a search: `herb bag` finds the Herb Pouch, `mining bag` the Apprentice's Mining Pack, `skinning bag` the Apprentice's Skinning Satchel.
- The bag itself comes before a pattern or recipe for one (`herb bag` no longer goes straight to Silithus for Pattern: Cenarion Herb Bag).

### Pinned searches on the minimap
- A pinned search's nearest 3 results outside your zone now show on the edge of the minimap, pointing the way, so the minimap isn't empty when none are in the zone you're in.
- Markers in your zone also show on the minimap while you're in a cave or building with a map of its own.

### Look
- MapSeek's name in the addon list and memory monitors takes the logo's colours: Map in white, Seek in gold.

## 1.0.0

First release.

### Search
- A search box across the top of the world map: NPCs by name or title, services (repair, inn, flight, bank, auction, stable, trainer, vendor, battlemaster, tabard, charter), trainers by class or profession, items vendors sell, skill books, quests you can pick up, and objects (mailbox, forge, anvil, campfire, meeting stone).
- Suggestions as you type, and spelling fixes for searches that find nothing.

### On the map
- Pulsing markers on the map and minimap, the map moving to the results, a ripple on sparse results, and a green ring on the nearest one.
- Tooltips with distance, the nearest flight master, what a vendor sells (with item icons) and a quest giver's quests.
- Right-click a vendor for a card of everything it sells, with the game's item tooltips.
- Click a marker or the footprints button for a waypoint (TomTom when installed).

### The bar
- Quick buttons (5 on the bar, more under More), drag to reorder.
- A quick button's markers stay 30 seconds after the map closes (settable).
- Right-click a quick button to pin it, with an X to unpin.

### Favourites
- Star up to 8 searches, pin one to keep it on the map and minimap after the map closes, and put favourites on the bar as buttons.

### Settings
- Bar, Favourites and Options tabs; zone-only searching that says what's elsewhere; a repair reminder.
- EllesmereUI theme for MapSeek's windows when EllesmereUI is installed.
