-- Towns and other named areas inside zones, with where they are on their zone's map: the
-- areas with a piece of map art of their own (WorldMapOverlay), the centre of that piece.
-- Generated from WoW Forever's tables (build 1.60.1.70862: WorldMapOverlay, AreaTable,
-- UiMapXMapArt, UiMap, via wago.tools) by tools/make_towns.py; regenerate rather than edit.
-- One string, a line per area ("name|uiMapID|x|y", x and y 0..1000), read on first use:
-- a fraction of the memory of a table per area

local _, ns = ...

ns.TOWNS = [[
Drygulch Ravine|1411|524|247
Echo Isles|1411|654|846
Kolkar Crag|1411|489|793
Orgrimmar|1411|469|52
Razor Hill|1411|546|427
Razormane Grounds|1411|412|434
Sen'jin Village|1411|561|730
Skull Rock|1411|536|120
Thunder Ridge|1411|407|243
Tiragarde Keep|1411|576|561
Valley of Trials|1411|444|670
Bael'dun Digsite|1412|326|507
Bloodhoof Village|1412|470|624
Brambleblade Ravine|1412|614|808
Palemane Rock|1412|341|685
Ravaged Caravan|1412|520|526
Red Cloud Mesa|1412|467|829
Red Rocks|1412|578|316
Skywatcher Plateau|1412|369|168
The Golden Plains|1412|495|398
The Rolling Plains|1412|604|681
The Venture Co. Mine|1412|592|521
Thunder Bluff|1412|394|362
Thunderhorn Water Well|1412|444|500
Wildmane Water Well|1412|426|243
Windfury Ridge|1412|506|205
Winterhoof Water Well|1412|519|689
Agama'gor|1413|432|483
Bael Modan|1413|477|838
Blackthorn Ridge|1413|417|790
Boulder Lode Mine|1413|619|67
Bramblescar|1413|506|584
Camp Taurajo|1413|457|610
Dreadmist Peak|1413|484|183
Far Watch Post|1413|611|213
Field of Giants|1413|462|707
Grol'dom Farm|1413|556|191
Honor's Stand|1413|374|284
Lushwater Oasis|1413|467|389
Northwatch Hold|1413|611|554
Raptor Grounds|1413|559|513
Ratchet|1413|626|374
Razorfen Downs|1413|489|917
Razorfen Kraul|1413|409|883
The Crossroads|1413|516|284
The Dry Hills|1413|397|146
The Forgotten Pools|1413|454|236
The Merchant Coast|1413|636|453
The Mor'shan Rampart|1413|479|67
The Sludge Fen|1413|554|75
The Stagnant Oasis|1413|556|427
Thorn Hill|1413|569|284
Chillwind Point|1416|821|666
Corrahn's Dagger|1416|482|838
Crushridge Hold|1416|484|419
Dalaran|1416|152|659
Dandred's Fold|1416|404|172
Gallows' Corner|1416|501|588
Gavin's Naze|1416|307|857
Growless Cave|1416|397|692
Lordamere Internment Camp|1416|205|850
Misty Shore|1416|282|378
Ravenholdt Manor|1416|821|666
Ruins of Alterac|1416|399|535
Slaughter Hollow|1416|484|419
Sofera's Naze|1416|584|689
Strahnbrad|1416|634|453
The Headland|1416|389|902
The Uplands|1416|564|273
Boulder'gor|1417|377|415
Boulderfist Hall|1417|541|737
Circle of East Binding|1417|636|341
Circle of Inner Binding|1417|367|618
Circle of Outer Binding|1417|526|528
Circle of West Binding|1417|222|254
Dabyrie's Farmstead|1417|551|397
Faldir's Cove|1417|309|797
Go'Shek Farm|1417|614|565
Hammerfall|1417|751|367
Northfold Manor|1417|317|314
Refuge Pointe|1417|459|472
Stromgarde Keep|1417|227|621
Thandol Span|1417|459|831
Thoradin's Wall|1417|177|378
Witherbark Village|1417|666|670
Agmond's End|1418|472|741
Angor Fortress|1418|429|333
Apocryphan's Rest|1418|157|618
Camp Boff|1418|614|726
Camp Cagg|1418|132|816
Camp Kosh|1418|661|225
Dustwind Gulch|1418|626|460
Hammertoe's Digsite|1418|566|363
Kargath|1418|87|475
Lethlor Ravine|1418|783|509
Mirage Flats|1418|307|752
The Dustbowl|1418|304|516
The Maker's Terrace|1418|492|165
Valley of Fangs|1418|464|569
Altar of Storms|1419|397|318
Dreadmaul Hold|1419|432|142
Dreadmaul Post|1419|504|442
Garrison Armory|1419|559|138
Nethergarde Keep|1419|644|183
Rise of the Defiler|1419|487|299
Serpent's Coil|1419|629|333
The Dark Portal|1419|584|565
The Tainted Scar|1419|379|625
Agamand Mills|1420|452|364
Balnir Farmstead|1420|728|617
Brightwater Lake|1420|683|421
Brill|1420|596|552
Cold Hearth Manor|1420|537|600
Crusader Outpost|1420|779|514
Deathknell|1420|344|639
Garren's Haunt|1420|578|382
Nightmare Vale|1420|473|663
Ruins of Lordaeron|1420|622|732
Scarlet Watch Post|1420|778|329
Solliden Farmstead|1420|360|495
Stillwater Pond|1420|480|513
Terrace of Repose|1420|872|379
The Bulwark|1420|836|696
Venomweb Vale|1420|872|485
Whispering Forest|1420|171|614
Whispering Gardens|1420|872|379
Ambermill|1421|634|629
Beren's Peril|1421|589|722
Deep Elem Mine|1421|561|483
Fenris Isle|1421|719|288
Malden's Orchard|1421|566|105
North Tide's Hollow|1421|404|284
Olsen's Farthing|1421|469|539
Pyrewood Village|1421|449|737
Shadowfang Keep|1421|442|662
The Dead Field|1421|464|217
The Decrepit Ferry|1421|554|363
The Greymane Wall|1421|464|861
The Sepulcher|1421|447|408
The Shining Strand|1421|541|228
The Skittering Dark|1421|374|157
Caer Darrow|1422|689|752
Dalson's Tears|1422|464|528
Darrowmere Lake|1422|684|737
Felstone Field|1422|374|558
Gahrron's Withering|1422|629|573
Hearthglen|1422|472|180
Northridge Lumber Camp|1422|474|363
Ruins of Andorhal|1422|437|692
Sorrow Hill|1422|516|793
The Weeping Cave|1422|651|423
The Writhing Haunt|1422|534|655
Blackwood Lake|1423|519|498
Corin's Crossing|1423|596|704
Crown Guard Tower|1423|387|756
Darrowshire|1423|399|898
Eastwall Tower|1423|679|498
Lake Mereldar|1423|626|801
Light's Hope Chapel|1423|821|584
New Avalon|1423|838|651
Northdale|1423|706|318
Northpass Tower|1423|579|284
Pestilent Scar|1423|741|625
Plaguewood|1423|364|337
Quel'Lithien Lodge|1423|529|165
Stratholme|1423|312|153
Terrordale|1423|177|322
The Fungal Vale|1423|404|520
The Infectis Scar|1423|526|666
The Marris Stead|1423|267|734
The Noxious Glade|1423|843|415
The Undercroft|1423|284|846
Thondroril River|1423|77|603
Tyr's Hand|1423|848|831
Zul'Mashar|1423|731|146
Azurelode Mine|1424|262|573
Darrow Hill|1424|509|337
Dun Garok|1424|721|715
Durnholde Keep|1424|768|408
Eastern Strand|1424|619|745
Hillsbrad Fields|1424|349|449
Nethander Stead|1424|639|554
Purgation Isle|1424|172|797
Southpoint Tower|1424|155|460
Southshore|1424|497|554
Tarren Mill|1424|611|258
Western Strand|1424|357|681
Aerie Peak|1425|147|505
Agol'watha|1425|497|371
Hiri'watha|1425|282|618
Jintha'Alor|1425|624|696
Plaguemist Ravine|1425|227|382
Quel'Danil Lodge|1425|314|430
Seradane|1425|641|254
Shadra'Alor|1425|347|715
Shaol'watha|1425|701|505
Skulk Rock|1425|591|430
The Altar of Zul|1425|487|662
The Creeping Ruin|1425|501|535
The Overlook Cliffs|1425|793|689
Valorwind Lake|1425|402|584
Amberstill Ranch|1426|634|505
Anvilmar|1426|264|752
Brewnall Village|1426|304|460
Chill Breeze Valley|1426|359|531
Coldridge Pass|1426|349|681
Coldridge Valley|1426|264|752
Frostmane Hold|1426|282|516
Gates of Ironforge|1426|556|436
Gnomeregan|1426|242|382
Gol'Bolar Quarry|1426|686|576
Helm's Bed Lake|1426|768|543
Iceflow Lake|1426|349|385
Ironforge|1426|556|436
Kharanos|1426|513|632
Misty Pine Refuge|1426|574|427
North Gate Outpost|1426|828|378
Shimmer Ridge|1426|409|400
South Gate Outpost|1426|853|509
The Grizzled Den|1426|409|580
The Tundrid Hills|1426|599|573
Blackchar Cave|1427|230|734
Dustfire Valley|1427|674|292
Firewatch Ridge|1427|279|337
Grimesilt Dig Site|1427|649|588
Tanner Camp|1427|694|763
The Cauldron|1427|462|494
The Sea of Cinders|1427|449|842
Blackrock Mountain|1428|299|318
Blackrock Pass|1428|751|685
Blackrock Stronghold|1428|437|352
Draco'dar|1428|279|655
Dreadmaul Rock|1428|813|415
Morgan's Vigil|1428|886|647
Ruins of Thaurissan|1428|651|344
Terror Wing Path|1428|886|359
The Pillar of Ash|1428|501|565
Brackwell Pumpkin Patch|1429|674|793
Crystal Lake|1429|526|640
Eastvale Logging Camp|1429|836|662
Fargodeep Mine|1429|384|842
Forest's Edge|1429|250|816
Goldshire|1429|412|647
Jerod's Landing|1429|536|831
Northshire Valley|1429|511|423
Ridgepoint Tower|1429|851|805
Stone Cairn Lake|1429|751|498
Stormwind City|1429|242|356
Stormwind Mountains|1429|242|356
Tower of Azora|1429|676|666
Valley of Heroes|1429|242|356
Deadman's Crossing|1430|452|359
Karazhan|1430|427|689
The Vice|1430|586|647
Addle's Stead|1431|217|692
Brightwood Grove|1431|626|408
Darkshire|1431|771|449
Manor Mistmantle|1431|744|337
Raven Hill|1431|207|561
Raven Hill Cemetery|1431|202|419
The Darkened Bank|1431|546|213
The Hushed Bank|1431|100|445
The Rotting Orchard|1431|641|730
The Yorgen Farmstead|1431|492|734
Tranquil Gardens Cemetery|1431|801|700
Twilight Grove|1431|477|404
Vul'Gol Ogre Mound|1431|362|734
Grizzlepaw Ridge|1432|452|689
Ironband's Excavation Site|1432|694|655
Mo'grosh Stronghold|1432|709|251
North Gate Pass|1432|225|153
Silver Stream Mine|1432|344|217
Stonesplinter Valley|1432|349|778
Stonewrought Dam|1432|479|127
The Farstrider Lodge|1432|831|629
The Loch|1432|501|423
Thelsamar|1432|349|460
Valley of Kings|1432|205|737
Alther's Mill|1433|479|427
Galardell Valley|1433|711|420
Lake Everstill|1433|420|598
Lakeridge Highway|1433|373|769
Lakeshire|1433|214|453
Redridge Canyons|1433|234|287
Render's Camp|1433|341|147
Render's Rock|1433|341|147
Render's Valley|1433|704|791
Rethban Caverns|1433|234|287
Stonewatch|1433|623|569
Stonewatch Falls|1433|732|672
Stonewatch Tower|1433|623|569
Three Corners|1433|119|733
Tower of Ilgalar|1433|711|420
Bal'lal Ruins|1434|294|198
Balia'mah Ruins|1434|417|311
Bloodsail Compound|1434|269|535
Booty Bay|1434|262|741
Crystalvein Mine|1434|409|505
Grom'gol Base Camp|1434|317|273
Gurubashi Arena|1434|294|442
Jaguero Isle|1434|389|823
Kal'ai Ruins|1434|344|210
Kurzen's Compound|1434|454|94
Lake Nazferiti|1434|404|187
Mistvale Valley|1434|337|644
Mizjah Ruins|1434|369|296
Mosh'Ogg Ogre Mound|1434|494|299
Nek'mani Wellspring|1434|257|625
Nesingwary's Expedition|1434|342|131
Rebel Camp|1434|374|56
Ruins of Aboraz|1434|397|591
Ruins of Jubuwal|1434|357|516
Ruins of Zul'Kunda|1434|259|124
Ruins of Zul'Mamwe|1434|467|423
The Vile Reef|1434|242|277
Venture Co. Base Camp|1434|442|198
Wild Shore|1434|324|793
Ziata'jai Ruins|1434|407|412
Zul'Gurub|1434|599|187
Zuuldaia Ruins|1434|212|150
Fallow Sanctuary|1435|651|225
Itharius's Cave|1435|150|629
Misty Reed Strand|1435|883|528
Misty Valley|1435|132|359
Pool of Tears|1435|711|528
Sorrowmurk|1435|838|464
Splinterspear Junction|1435|245|524
Stagalbog|1435|704|790
Stonard|1435|477|550
The Harborage|1435|277|359
The Shifting Mire|1435|439|348
Alexston Farmstead|1436|382|524
Demont's Place|1436|312|696
Furlbrow's Pumpkin Farm|1436|509|213
Gold Coast Quarry|1436|314|415
Jangolode Mine|1436|447|243
Moonbrook|1436|442|655
Saldean's Farm|1436|554|326
Sentinel Hill|1436|559|498
The Dagger Hills|1436|469|790
The Dead Acre|1436|624|614
The Dust Plains|1436|634|726
The Jansen Stead|1436|566|176
The Molsen Farm|1436|449|363
Westfall Lighthouse|1436|319|861
Angerfang Encampment|1437|474|483
Black Channel Marsh|1437|200|490
Bluegill Marsh|1437|192|363
Direforge Hill|1437|606|326
Dun Modr|1437|494|168
Grim Batol|1437|801|632
Ironbeard's Tomb|1437|447|311
Menethil Harbor|1437|102|569
Mosshide Fen|1437|619|546
Raptor Ridge|1437|721|382
Saltspray Glen|1437|342|243
Sundown Marsh|1437|232|284
The Green Belt|1437|536|367
Thelgen Rock|1437|564|689
Whelgar's Excavation Site|1437|359|490
Ban'ethil Hollow|1438|464|573
Darnassus|1438|274|576
Dolanaar|1438|551|569
Gnarlpine Hold|1438|439|749
Lake Al'Ameth|1438|576|711
Pools of Arlithrien|1438|404|636
Rut'theran Village|1438|556|909
Shadowglen|1438|596|400
Starbreeze Village|1438|656|576
The Oracle Glade|1438|379|363
Tradesmen's Terrace|1438|274|576
Warrior's Terrace|1438|274|576
Wellspring Lake|1438|469|356
Ameth'Aran|1439|427|576
Auberdine|1439|392|438
Bashal'Aran|1439|449|363
Cliffspring River|1439|536|333
Grove of the Ancients|1439|429|771
Remtravel's Excavation|1439|349|853
Ruins of Mathystra|1439|586|165
The Master's Glaive|1439|414|887
Tower of Althalaxx|1439|564|262
Astranaar|1440|372|516
Bough Shadow|1440|938|363
Fallen Sky Lake|1440|691|820
Felfire Hill|1440|831|775
Fire Scar Shrine|1440|267|636
Iris Lake|1440|464|468
Lake Falathim|1440|205|404
Maestra's Post|1440|292|258
Mystral Lake|1440|494|734
Night Run|1440|716|591
Raynewood Retreat|1440|609|516
Satyrnaar|1440|818|483
The Howling Vale|1440|561|371
The Ruins of Stardust|1440|334|674
The Shrine of Aessina|1440|222|528
The Zoram Strand|1440|130|221
Thistlefur Village|1440|369|367
Warsong Lumber Camp|1440|911|591
Camp E'thok|1441|162|176
Darkcloud Pinnacle|1441|349|363
Freewind Post|1441|462|528
Highperch|1441|135|341
Splithoof Crag|1441|479|412
The Great Lift|1441|322|225
The Screeching Canyon|1441|307|475
The Shimmering Flats|1441|783|730
Windbreak Canyon|1441|624|550
Boulderslide Ravine|1442|649|928
Camp Aparaje|1442|773|924
Grimtotem Post|1442|756|868
Malaka'jin|1442|729|947
Mirkfallon Lake|1442|492|408
Sishir Canyon|1442|544|749
Stonetalon Peak|1442|372|135
Sun Rock Retreat|1442|464|584
The Charred Vale|1442|319|670
Webwinder Path|1442|604|685
Windshear Crag|1442|699|505
Ethel Rethor|1443|409|307
Gelkis Village|1443|384|891
Kodo Graveyard|1443|506|580
Kolkar Village|1443|744|487
Kormek's Hut|1443|644|404
Magram Village|1443|711|730
Mannoroc Coven|1443|534|793
Nijel's Point|1443|649|94
Ranazjar Isle|1443|289|82
Sargeron|1443|758|228
Shadowbreak Ravine|1443|803|793
Shadowprey Village|1443|254|704
Tethris Aran|1443|544|124
Thunder Axe Fortress|1443|544|281
Valley of Spears|1443|332|520
Camp Mojache|1444|753|423
Dire Maul|1444|589|419
Dream Bough|1444|514|101
Feral Scar Vale|1444|544|569
Frayfeather Highlands|1444|536|711
Gordunni Outpost|1444|773|311
Grimtotem Compound|1444|679|404
Isle of Dread|1444|297|790
Lower Wilds|1444|861|430
Oneiros|1444|546|168
Ruins of Isildien|1444|614|670
Ruins of Ravenwind|1444|397|109
Sardor Isle|1444|302|501
The Forgotten Coast|1444|464|621
The Twin Colossals|1444|472|254
The Writhing Deep|1444|729|610
Alcaz Island|1445|756|176
Beezil's Wreck|1445|444|487
Bloodfen Burrow|1445|369|614
Bluefen|1445|369|228
Brackenwall Village|1445|369|228
Darkmist Cavern|1445|369|228
Dreadmurk Shore|1445|539|228
Dustwallow Bay|1445|539|228
North Point Tower|1445|539|228
Sentry Point|1445|681|513
Stonemaul Ruins|1445|369|614
The Den of Flame|1445|369|614
The Dragonmurk|1445|369|614
The Quagmire|1445|444|487
Theramore Isle|1445|681|513
Tidefury Cove|1445|485|619
Witch Hill|1445|539|228
Wyrmbog|1445|526|752
Abyssal Sands|1446|457|427
Broken Pillar|1446|531|457
Caverns of Time|1446|641|494
Dunemaul Compound|1446|419|561
Eastmoon Ruins|1446|467|651
Gadgetzan|1446|511|273
Land's End Beach|1446|549|917
Lost Rigger Cove|1446|716|472
Noonshade Ruins|1446|599|247
Sandsorrow Watch|1446|399|284
Southbreak Shore|1446|624|595
Southmoon Ruins|1446|402|715
Steamwheedle Port|1446|669|213
The Gaping Chasm|1446|544|707
The Noxious Lair|1446|347|457
Thistleshrub Valley|1446|307|625
Valley of the Watchers|1446|369|805
Waterspring Field|1446|596|378
Zalashji's Den|1446|669|333
Zul'Farrak|1446|374|127
Bay of Storms|1447|589|546
Bitter Reaches|1447|766|195
Forlorn Ridge|1447|294|715
Haldarr Encampment|1447|207|603
Jagged Reef|1447|639|112
Lake Mennar|1447|432|801
Legashi Encampment|1447|579|180
Ravencrest Monument|1447|706|850
Ruins of Eldarath|1447|367|543
Shadowsong Shrine|1447|175|749
Southridge Beach|1447|584|719
Temple of Arkkoran|1447|766|412
Thalassian Base Camp|1447|609|288
The Ruined Reaches|1447|581|917
The Shattered Strand|1447|457|460
Timbermaw Hold|1447|377|374
Tower of Eldara|1447|883|303
Ursolan|1447|469|284
Valormok|1447|215|505
Bloodvenom Falls|1448|424|487
Deadwood Village|1448|492|913
Emerald Sanctuary|1448|516|797
Felpaw Village|1448|634|109
Irontree Woods|1448|501|236
Jadefire Glen|1448|412|827
Jadefire Run|1448|412|180
Jaedenar|1448|364|599
Morlos'Aran|1448|576|879
Ruins of Constellas|1448|379|692
Shatter Scar Vale|1448|422|352
Talonbranch Glade|1448|621|243
Fire Plume Ridge|1449|504|498
Golakka Hot Springs|1449|302|501
Ironstone Plateau|1449|724|348
Lakkari Tar Pits|1449|506|206
Terror Run|1449|372|741
The Marshlands|1449|696|632
The Slithering Scar|1449|516|801
Lake Elune'ara|1450|531|516
Moonglade|1450|531|516
Nighthaven|1450|531|516
Shrine of Remulos|1450|531|516
Hive'Ashi|1451|449|243
Hive'Regal|1451|571|805
Hive'Zora|1451|247|584
Southwind Village|1451|624|531
The Crystal Vale|1451|232|176
The Scarab Wall|1451|289|951
Twilight Base Camp|1451|502|485
Darkwhisper Gorge|1452|579|831
Everlook|1452|609|378
Frostfire Hot Springs|1452|334|367
Frostsaber Rock|1452|494|127
Frostwhisper Gorge|1452|619|685
Ice Thistle Hills|1452|681|457
Lake Kel'Theril|1452|531|434
Mazthoril|1452|584|580
Owl Wing Thicket|1452|654|618
Starfall Village|1452|497|284
The Hidden Grove|1452|646|172
Timbermaw Post|1452|402|434
Winterfall Village|1452|684|367
Dun Baldar|1459|419|206
Dun Baldar Pass|1459|476|494
Frostwolf Keep|1459|519|782
Iceblood Garrison|1459|504|638
Rock of Durotan|1459|454|350
Cradle of Tranquility|2482|338|423
Dae'gun|2482|544|373
Elderwild|2482|139|499
Felblood Scar|2482|462|768
Malorne's Retreat|2482|288|706
Mourning's Rest|2482|242|527
Shrine of Aviana|2482|506|591
Summit of Eternity|2482|784|352
Tainted Foothills|2482|706|730
East Pylon Watchtower|2521|700|671
Fairweather Stables|2521|540|812
Falaath Village|2521|499|549
Gustberry Lowlands|2521|600|666
Overlook Standing Stones|2521|481|691
Rohashi Spires|2521|711|496
Ruins of Ban'aethal|2521|580|283
Shadowgale Forest|2521|603|388
Shen'dar Highlands|2521|430|561
Shen'dar Village|2521|445|446
Shrine of Akir|2521|623|503
Thendal Grove|2521|411|296
Thendal Standing Stones|2521|488|186
Thendal Village|2521|458|203
Valanaar|2521|627|787
Valanaar Skydocks|2521|627|787
West Pylon Watchtower|2521|406|640
Windfield Orchard|2521|468|820
Windsong Lake|2521|518|473
Windsong Standing Stones|2521|458|388
Bolder'ok|2548|657|164
Bristle Hills|2548|273|626
Elbrim's Farm|2548|523|455
Farholde Keep|2548|648|829
Krol'dok Stronghold|2548|444|265
Meadowsbrook|2548|448|810
Powderfuse Port|2548|765|518
Rog'mar|2548|587|460
Sunnyglade|2548|461|513
Terral's Watch|2548|600|643
Turner's Logging Camp|2548|381|610
Twilight's Shroud|2548|275|439
Wheeler's Grange|2548|542|776
Windstead|2548|762|342
Bristleback Retreat|2652|749|311
Evenshade's Overlook|2652|307|492
Forlorn Gardens|2652|727|731
Magram Front|2652|622|553
Outcast Hideaway|2652|296|771
Shen'dralas|2652|501|635
Valley of Bones|2652|390|257
]]
