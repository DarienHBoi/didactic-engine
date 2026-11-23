# Holiday data sources

The quest/event associations in HolidayData.lua are derived from CMaNGOS
ClassicDB 1.12.1 z2815, distributed under GPLv3. The addon includes numeric
associations only. Quest text, NPC data, and translated names from the database
are not copied into this holiday mapping.

- [ClassicDB source snapshot](https://github.com/cmangos/classic-db/tree/28ef6259c782928b08a8dc9cacf6bc02e64f2b29)
- [ClassicDB license](https://github.com/cmangos/classic-db/blob/28ef6259c782928b08a8dc9cacf6bc02e64f2b29/LICENSE.md)
- Source file: Full_DB/ClassicDB_1_12_1_z2815.sql.gz
- SHA-256: 4f92db520868ab4e566726f68b5b2e380ae781209beaf22237b4f7f04600d0c0

The table uses game_event_quest associations and quest givers whose known spawns
are exclusive to a supported event, joined through the creature and gameobject
spawn and quest-relation tables. Direct associations take priority. Supported
quest categories are checked against the selected quest database at
runtime. ClassicDB is a Classic snapshot, so coverage of newer event quests
and Forever-specific changes is limited.

Winter Veil and Midsummer fallback dates use Blizzard's published dates.
The Christmas gift window uses Blizzard's December 25–January 2 announcement.
New Year celebration quests identified in ClassicDB use December 31–January 1.
Calendar timing takes priority for event activation.

- [Winter Veil schedule](https://worldofwarcraft.blizzard.com/en-us/news/24249604/the-festive-feast-of-winter-veil-is-now-live)
- [Winter Veil gift dates](https://worldofwarcraft.blizzard.com/en-us/news/20407402/the-feast-of-winter-veil-gifts-are-now-present)
- [Midsummer schedule](https://news.blizzard.com/en-us/article/24107643/ignite-your-summer-with-the-midsummer-fire-festival)

Automatic name matching uses English calendar names. Darkmoon Faire also
matches calendar textures. For unrecognized or unavailable calendar data, use
the per-character event overrides. The holiday mapping contains no Questie
translation table. The addon also includes an adapted QuestieDB fallback;
its original licensing notices and provenance are in EmbeddedQuestDatabase.
