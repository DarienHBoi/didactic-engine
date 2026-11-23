# Changelog

## 0.56.1

- Titan Panel and AllTheThings are no longer reported as incompatible.
- Group icons in messages from the last session now show in the right size and color.

## 0.56.0

- The Combat Log tab can be hidden from its right-click menu. It comes back from the + or in the options (History and tabs).
- The shadow around the chat is smaller.

## 0.55.0

- New whisper tabs can start with a sound of your choice: "New whispers" at the top of the tab list in the Alerts options.
- When the chat is faded, it lights up as soon as the mouse is over it.
- Friend and guild marks before names now sit level with the text.

## 0.54.1

- Fixed a Lua error some players could get while using the chat.

## 0.54.0

- Audio alerts now ring for a tab's new messages even when they're on screen, unless you're using the chat. If you already had one on, you'll hear it more often.
- Moving the mouse over the chat brings back messages that had faded.

## 0.53.0

- Locking or unlocking the chat now shows a small padlock.
- The chat can now stay always visible when you're not using it: "Chat when idle" in the options is faded, hidden or always visible, and the eye on the side bar switches between them.
- The names of the other tabs no longer fade before the rest of the chat when the mouse leaves while you type.

## 0.52.2

- Empty lines no longer leave blank space in the chat.

## 0.52.1

- Lines that arrive with no text no longer show a time on their own.

## 0.52.0

- Ready for the launch of WoW Forever.
- Tabs can ring with sounds your other addons share through SharedMedia (sound packs, boss mods): they're listed in each tab's sound menu, under SharedMedia.
- Everchat's sounds are shared too, so your other addons can use them.

## 0.51.0

- Lock the chat so it can't be moved or resized by accident: Shift-click its header, use "Lock Window" in a tab's menu or the box in Appearance. Holding Shift still moves it.
- When the chat is too short for every side bar button, the less used ones go into a "more" button.
- Names of your own now work on every channel, Trade (Local) and Services included.
- The social button always stays at the top of the side bar.
- Visual polish in the header and the window's corners.

## 0.50.0

- A new Channels page in the options: give any channel a name of your own, like [T] for Trade, choose whether the guild's and the group's labels show as icons, and change each channel's color. An arrow puts a channel back the way the game shows it.
- Raids have their own icon, three figures with the crown on the leader.
- A guild without a crest shows a green banner in place of [Guild].
- The typing field shows the same channel names as the chat.
- Lines brought back after a reload follow the channel colors you change.

## 0.49.0

- New option in Appearance: hide the chat while it isn't in use. New messages still show for the time you choose, and the mouse or Enter brings it back.
- An eye on the side bar turns it on and off.
- The chat no longer moves back to its Edit Mode place when you level up.

## 0.48.1

- When the tabs don't fit, the last one's name fades out softly at the end of the header.
- Recipes linked in chat show the icon of what they make.
- Better performance.

## 0.48.0

- The open tab has a lighter frame: one thin line of the theme's metal, light at the top and fading down its sides into the line under the header, where it curves out softly. Its block melts from the header into the messages, so at any background opacity the tab reads as one piece with the chat. It used to sit in three rings around a dark, nearly solid block.
- The header is a little lower, closer to the size of the game's own tabs, and a tab only takes clicks over the header.
- The line under the header runs whole from side to side. The lines over the typing field and under the combat log's filters are gone.
- The typing field is black at half, see-through like the rest of the chat, with a softer edge. It used to draw solid black.
- Tabs light up and fade back gently as the mouse passes over them.
- The minimal style lies flat: the header and the footer look like the messages, the side bar's buttons stand on their own, there's no shadow around the chat, and the field shows its edge only while you type. A tab under the mouse lights its stretch of the line.
- Copy chat, copying a line or an address, copying tabs and the dialog about other chat addons share the options window's look.

## 0.47.0

- The font list in Appearance also offers the fonts other addons share through SharedMedia, such as the SharedMedia pack, ElvUI or Details, each shown in its own font. They don't carry the extra symbols of Everchat's fonts, and some lack accented or Cyrillic letters.
- If the addon that brings your chosen font is turned off, the chat uses Roboto Condensed until it's back, then returns to your font.
- Everchat's five fonts are shared the same way, so addons that use SharedMedia list them as "Roboto Condensed (Everchat)" and so on.
- While you type, the whole field shows above any window open over the chat, as the game's own box does. Only the text and its "Say:" used to.

## 0.46.0

- Themes, in Appearance > Window: gold as before, silver or bronze. They apply at once, and the arrows beside the list step through them.
- A minimal style for any of them: no metal frame on the open tab, whose stretch of the line under the header lights up instead.
- A theme dresses the open tab's frame, the lines, the tab names and every button on the header and the side bar, the game's own buttons included. The background's color and opacity still follow each tab's menu, and the options window keeps the game's gold.
- The scroll bar's thin line keeps its transparency after the bar widens under the mouse. It used to turn solid.

## 0.45.1

- An item's, spell's or quest's icon now moves to the next row together with its name, instead of staying behind at the end of a row.
- Hovering an icon shows the same tooltip as its name, and a click on it opens it.
- The dark frames around item and spell icons are gone. With some fonts the game draws the text after an icon a little wider than it measures, so the frames drifted away from their icons.
- The race and class portraits sit a little closer together.

## 0.45.0

- The guild's crest is drawn whole over the line. Its emblem now sits right on the shield, centered with the text, and at the chat's usual size it comes from the game's own small art, so every emblem stays readable.
- In lines that also show a crest, a portrait, a group icon or a heart, the dark frame around item, spell and skill icons sat a couple of pixels low. It now sits right on the icon.
- Everything players can link shows in your client's language: recipes, profession windows, achievements and currencies join quests, items and spells.
- /everchat plain shows the chat as the game writes it, in the game's font, for before-and-after pictures. Type it again to go back.
- English texts call the guild's coat of arms its crest.

## 0.44.1

- Surnames are read correctly. Forever's game gives the first name and the surname apart, and Everchat used only the first name to keep each character's data (saved chat, tab order, the chat's size and place, alerts and sounds), so two characters with the same first name shared it. Each character's data moves to its full name the next time it logs in; nothing needs to be set again.
- Mentions match your full name in any case, and your first name alone only with its capital, as intended.
- At rest the chat is never more see-through than the background opacity set in the tab's menu, as the game's own chat does: a solid chat now stays solid.
- The dialog about other chat addons also detects Better Forever Chat, and names each addon as the addon list does (Glass Forever, for example).
- Saved chat older than a day is removed for every character at login, not only for the one logging in, so the saved file doesn't grow with each alt.

## 0.44.0

- Race and class icons before players' names: round portraits from the game's own art. Each has its own box in Appearance > Icons and marks, off by default.
- Quests, items and spells other players link show their name in your client's language, as their tooltips already did. It can be turned off in Messages.
- The options window sounds like the game's: checkboxes, page tabs, buttons and windows click as they do in the game's settings, and the "+" menu like the game's menus.
- Dropdowns in the options are the game's own settings control: the arrows on each side change the choice without opening the list. In a tab's sound, the arrows play each sound as they go.
- Option tooltips are at the game's size, and the surname's lists its three choices.
- The font size is one row for every tab, right under the font. A tab can still have its own size from its right-click menu.

## 0.43.1

- An icon and the name after it move to the next row together, so a quest's "!" is no longer left alone at the end of a row.
- A link written right after a word gets a space before its icon.
- Fixed: the gold line under the tabs didn't follow the chat when it was resized or opened on a screen with another resolution, so it stopped short or ran past the chat's edge.

## 0.43.0

- A new Appearance page in the options: the chat's font, its outline, line spacing, the time, icons and marks, and each tab's font size (the same setting as the tab's right-click menu), with a row to set every tab at once.
- Four more fonts: Fira Sans Condensed, Open Sans Condensed, Noto Sans SemiCondensed and Atkinson Hyperlegible Next, each name shown in its own font. Arial Narrow, the game's own, is still there.
- Every font now shows the symbols players use: stars, hearts, suits, arrows, boxes, Braille art and more, which used to show as "?".
- Line spacing (compact, normal or wide) and a font outline (none, thin or thick) for reading the chat over bright ground.
- Messages > Languages: untick Chinese, Korean or Russian to hide those messages in public channels, say and yell.
- Logins, logouts and channel notices show in grey, so the conversation stands out.
- Quest links get the "!" of the characters who give quests, so an orange quest no longer passes for a legendary item.
- Web addresses without "www" become links too, like discord.gg/... in a guild's message of the day.
- Mentions also highlight your other characters' names.
- /everchat cpu shows how much of each frame Everchat takes.
- Every option says what it does at a glance.

## 0.42.0

- Someone's "inv" in a whisper or in guild chat becomes a gold [inv] link: click it to invite them. Only the short form people type to ask, not "invite" in a sentence or an "inv" in quotes. It can be turned off in the options.
- Web addresses are gold and in brackets, like the game's links, instead of light blue (the color of spell links and nearly that of a party leader's lines). Hovering one says a click copies it.
- Icons before spell links and recipes, and before the skill in "Your skill in Maces has increased" lines. Every icon has a thin dark frame that rounds its corners, and sits centered on the text.
- The chat's font sets words and letters a little closer, nearer the game's own chat font, and kerns pairs like "Te" and "Vo".
- Icons follow a font size change at once.
- Less work in busy chats: coats of arms, leader crowns and icons are measured once per message instead of on every redraw.
- Fixed: a whisper tab's audio alert couldn't be turned off.

## 0.41.0

- Every tab can ring with its own sound. The options' Alerts page has one table with each tab's visual alert, audio alert and sound. A tab starts with the sound of what it shows: the singing bowl for the guild, a clink of glass for whispers, the kalimba for General. The table follows your tabs while it's open.
- Any tab can ring, for any new message, not only guild, group, raid, whispers and Trade. Still at most once a minute until you open it.
- Thirty sounds in four groups, each with a speaker to hear it without choosing it: themed ones (a hunting horn, a call to arms, dice for loot rolls), nods to Azeroth (a murloc, "Ding!", a fish biting, level 60, a skill-up), one per class (Thunder Clap, Holy Light, Frost Nova and the rest) and instruments (a dulcimer, a vibraphone, a marimba).
- A bell on the side bar mutes all of Everchat's sounds and brings them back. While muted it's struck through in red, like the game's own muted buttons. The same switch is in the options.
- Surnames can show in full, as an initial ("Zephyrous B.") or not at all.
- Item icons show before item links everywhere in the chat, not only in Trade.
- The open tab stays open into the messages at rest too, and the tab list button stays bright at rest while a hidden tab has unread messages.
- The options window has a title bar and the game's close button in Everchat's colors. Alerts are worded as the game words them in every language.
- Fixed: a tab could ring for a message you were already reading in the tab on show.

## 0.40.0

- The chat rests like the game's own. With the mouse away, the tabs fade as the game's do (the open one to 40%, the others to 20%), and so do the "+", the grips and the text box. The header, footer and side bar blend into one plain dark panel, without their gold lines and shadow. The messages stay fully visible, and everything comes back under the mouse or while you type.
- A tab with unread messages keeps its name readable at rest, next to its dot.
- The combat log's filters fade with its tab, as in the game.
- The guild's default sound is now the singing bowl. The hall bell is still in the list.

## 0.39.0

- Everchat's options open in a window of their own, in the chat's style, from the gear on the side bar, /everchat or the addon compartment. It's laid out like the game's settings: names on the left, the game's checkboxes, dropdowns and buttons. Options > AddOns > Everchat has a button to open it.
- Sounds for new messages by kind: a hall bell for the guild, a toast for the group, war drums for the raid, a celesta for whispers and a shop's door bell for Trade, replacing the old "blip-blip". Each one can be changed or turned off in the options, among these and four instruments. They play on the master channel, so they still sound with sound effects muted.
- A tab's right-click menu starts with an Alerts section: the unread dot and the sound, now just on or off (the message decides which sound plays). Sound is on by default only in whisper tabs. The options window has every tab's switches in one table.
- In public channels, guild members show your guild's coat of arms before their name, or a green banner of the same shape if the guild has no tabard designed. The friend's heart and the banner are shaded like the game's own icons.
- Hovering a guildmate's name shows your guild's name next to their rank.
- Tabs open at the bottom again, like the game's, instead of on the first unread message.
- Everchat's options button on the side bar sits right above the game's channels button.
- Tooltips and hints are worded like the game's own.

## 0.38.0

- The grips have their own look: six gold studs where you drag to move the chat, three gold grooves in the corner that resizes it.
- A thinner "+" with straight ends.
- The scroll bar is a hairline at rest and widens smoothly when the mouse comes near; its arrows and the jump-to-bottom button line up with it, and the bar reaches the bottom.
- Less work per message and per frame: name mentions, unread dots, search, times, the guild roster and the coat of arms do only what's needed, so busy channels cost less.

## 0.37.0

- Search the chat: the magnifier on the side bar opens a find field at the top of the tab, and the tab shows only the lines with what you type, the matches in gold. It stays open with its text when you switch tabs; Esc closes it.
- The scroll bar is drawn in the game's colors: slim, a little wider under the mouse, with gold arrows. While new messages arrive below what you're reading, its bottom arrow glows with a heartbeat (its tooltip says how many).
- Opening a tab with more new messages than fit starts at the first of them.
- Friends get a heart and guild members a tabard before their names in public channels (option).
- Hovering a player's name shows their class, race and level, their guild when the game knows it, and for friends and guildmates their note, zone and rank.
- Option to keep Everchat's sounds quiet in combat and inside instances.
- Lines brought back after a reload remember who wrote them, so their marks and name tooltips work too.
- The header looks more like the game's own: the open tab sits in a frame of gold metal, the "+" and the tab list button are gold icons that glow under the mouse, and the grips that move and resize the chat are gold.
- The group leader's crown sits on the head of the party/raid icon, and the leader's name lines up with everyone else's.
- Everchat's tooltips are smaller (a line's time, the tabs, the "+", the side buttons), and the "+" says what it does.
- Fixed: the gold lines along the header and above the edit box looked broken while the chat was faded.

## 0.36.0

- New logo and in-game icon: a speech bubble whose infinity sign keeps an eye on your unread messages.
- The chat panel follows the game's own background setting (right-click a tab > Background): its opacity, from the usual look down to a see-through chat, and its color, as a dark tint so the text stays readable.
- A sound when someone mentions you (option, on by default), and an optional sound alert per tab for new messages (right-click the tab): a soft "blip-blip" of Everchat's own, on the first unread message and then at most once a minute until you open the tab.
- Hovering an item, spell or achievement link shows its tooltip.
- Click a line's time to copy that line; hovering the time shows its full date and says so.
- Copy your tabs from another character (Options > History and tabs). Only adds what's missing; nothing is removed.
- The options are split into pages: the main one for what shows in the chat, then Alerts, Side buttons, and History and tabs.
- Option to use the game's own font instead of Roboto Condensed.
- Chat history keeps 1,500 lines per tab (was 500).
- Web links in public channels (Trade, General...) are no longer clickable: there they're mostly spam.
- When the tabs don't fit, the mouse wheel over the "+" and the tab list button scrolls the tabs instead of turning the main action bar's page.
- The Combat Log tab no longer offers alert or sound switches (it never gets chat messages).

## 0.35.2

- Copy chat uses the short channel names you see ("[2. Trade]"), while still labelling every line with its channel.

## 0.35.1

- The first time your tabs don't fit, a tip in the game's style shows they scroll with the mouse wheel (shown once).

## 0.35.0

- The chat's buttons (social, chat menu, channels and voice) stand on a slim rail beside the panel, in its style, and are drawn pixel-perfect at any resolution and interface scale.
- Optional side buttons on that rail: copy chat, clear chat and roll 1-100 at the top, Everchat's options at the bottom by the chat menu; copy and options on by default (Options > Side buttons).
- Whisper tabs no longer show the game's own light along the bottom under the unread dot; whispers always light the dot, even in tabs with alerts off.
- Item links written back to back in Trade no longer get their icons stuck to the previous name.
- The copy chat window uses the chat's font and size.

## 0.34.0

- Copy chat: "Copy chat" in a tab's right-click menu opens its text in a window, ready for Ctrl+C.
- Mentions: when someone writes your name (your full name, or your first name with its capital), it shows in gold and the tab lights up, even if its alerts are off (option, on by default).
- Item icons in Trade: linked items show their icon before the name (option, on by default).
- Messages with Cyrillic names or text use the same font as the rest of the chat.
- Everchat's own icon in the game's addon list.
- Repeated ads: in numbered channels like Trade, the same message from the same player shows at most once every 5 minutes (option, on by default).

## 0.33.2

- Resetting the chat windows from the game's menu now leaves the text at the size Everchat picks for your screen, instead of the game's default.
- The default text size leans to the smaller size on screens right at the limit (1440p with a 0.64 interface scale now gets 14, not 16).

## 0.33.1

- The combat log's filter bar shows again (it was hidden inside the tab bar), without its black band and with the header's gold line under it.
- A tab with an unread dot centers its name and the dot together, so the dot no longer crowds the next tab.
- Fixed a tab's name ending up slightly off (up and to the left) after clicking it while it had an unread dot.
- In a tab that shows a single channel (like Trade), its lines drop the channel label, as guild lines already do in a guild tab.
- Group chat icons: party, raid and instance lines show an icon in the chat's color instead of "[Party]", "[Raid]" or "[Instance]", with a crown for the leader and a warning sign for raid warnings (option, on by default).
- The tab header stands out a little more from the messages (a lighter tone and a clearer gold line), so messages scrolling under it no longer look cut off against nothing.

## 0.33.0

First public release.

- Chat panel restyled to fit Forever's interface:
  - rounded card on a soft shadow;
  - tab header;
  - footer with a typing field that takes the channel's color.
- Tab strip:
  - drag to reorder, General and the combat log included;
  - smooth scrolling with the mouse wheel;
  - overflow list;
  - tooltips that explain both.
- "+" menu for new tabs: Guild, Group, Whispers, Trade, Loot, or any name. Presets whose tab is already open aren't listed.
- Unread dot in the messages' color beside the tab's name, with a halo that breathes twice when it appears and once every 12 seconds. While unread tabs are scrolled out of view the tab list button shows the dot too, and its list marks which tabs are unread. Per-tab switch in the tab menu (off by default for General and the combat log).
- Resize grip on every window. The size and place are saved per character, so new characters keep Edit Mode's layout.
- The free space at the right of the tab bar moves the docked chat when dragged, like a window's title bar; some of it is always kept free, marked by a faint six-dot grip (not in combat).
- The "+" and the tab list button sit together after the tabs and share one look: a rounded square under the mouse, no gold.
- Chat history across reloads and logins, which can be turned off (`/everchat history`) and deleted (`/everchat history clear`).
- Every message starts with its time, in grey, in the game clock's format (24-hour or AM/PM).
- Web addresses in chat are links: clicking one opens a small window with it selected; Ctrl+C copies it ("Copied" confirms) and Close closes the window.
- Short channel names: "[1. General]" instead of "[1. General - Elwynn Forest]" (can be turned off).
- Guild coat of arms instead of the guild label.
- Roboto Condensed with Blizzard's CJK and Cyrillic fonts, and a default size chosen for the screen.
- The edit box follows each window's font size.
- Changing an option (time, short channel names, coat of arms) updates the lines already in the chat, both ways.
- Options page in the game's settings (Options > AddOns > Everchat, also `/everchat` and the minimap addon compartment): timestamps, short channel names, guild coat of arms, chat history (with a button to delete it) and a reset for the chat's size and position. Every option explains in its tooltip what it does.
- Translated into Spanish, French, German, Portuguese, Italian and Russian (`Locales/`, English as the source).
- Detects other chat addons (Prat, Chattynator, Glass, ElvUI's chat, and any addon that replaced part of the chat's secure code) and offers to keep only one.
