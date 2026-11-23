# Forever Camp Guide 2.5

In-game profession and camping guide for WoW Forever, based on wow-professions.com/forever (beta guides).
English and Spanish. The language follows your game client automatically; you can change it in Settings.

## What's new in 2.5 (2026-11-14)
- New Miscellaneous page: mini guides with map points for the Cozy Sleeping Bag and the Night Watchman's Torch (`/fcg misc`).
- Profession detection works with whatever name your client uses (fixes Tailoring on Spanish clients); `/fcg debug` for bug reports.

## What's new in 2.4 (2026-11-05)
- Quantities now follow your current skill: if you are halfway through a range, the guide shows only the crafts and materials you still need (also in the header and the panel next to the profession window).
- New "What you still need" list in the Shopping tab, calculated from your skill and selected routes.
- New guides for Mining, Herbalism and Skinning.
- Blacksmithing, Leatherworking and Tailoring updated with the website's new routes, including Artisan (225-300).

## What's new in 2.3 (2026-10-22)
- Built-in coordinates for 305 guide NPCs: click any trainer or vendor to see them on the map, or click [x, y] to set a waypoint.

## What's new in 2.2 (data from 2026-10-14)
- New **Merchant's Favor** page: camps and vendors, Waylaid Crate bundles with live bag counts,
  Craftsman's Writs, the receipt trick, and ~120 vendor recipes with level, skill, cost, reputation
  and known/unknown status (also shown in each profession's Recipes tab).
- Camping: materials for every camp item, blueprint drops (boss and dungeon), campfire kit materials,
  crafting stations, and whether you know each camp recipe.
- New routes for Blacksmithing, Enchanting (essence or dust route), Leatherworking, Tailoring and
  First Aid; Alchemy 165-300 updated; Engineering, Cooking and Fishing notes and vendors updated.
- Fishing + Cooking checklist now offers several starting zones per faction.

## English

**Install:** unzip and copy the `ForeverCampGuide` folder into WoW Forever's `Interface\AddOns`, then `/reload`.
If it shows as "out of date", enable "Load out of date AddOns" or set the `## Interface:` line in the `.toc`
to the number returned by `/dump select(4, GetBuildInfo())`.

**What it does**
- 1-300 leveling guides (Alchemy, Blacksmithing, Enchanting, Engineering, Leatherworking, Tailoring, Cooking,
  First Aid, Fishing, Mining, Herbalism, Skinning) with your current step highlighted, known/unknown recipes, live material counts,
  alternative routes, recipe vendors and rank-cap warnings.
- Trainers by capital city and starting zone, a shopping list, a recipes overview and each profession's camp items.
- Map viewer using the game's own zone maps, with built-in coordinates for every guide NPC. Waypoints work with TomTom.
- A panel next to the profession window with what to craft now, plus a Fishing + Cooking checklist.

**Commands:** `/fcg` · `/fcg <profession>` (e.g. `/fcg alch`) · `/fcg map` · `/fcg options` · `/fcg tracker` · `/fcg minimap`

**Translations:** interface texts are in `Locale_UI_enUS.lua`, guide texts in `Locale_Data_enUS.lua`.
Any text without a translation falls back to Spanish.

## Español

**Novedades 2.5 (2026-11-14):** nuevo apartado Misceláneos con mini guías y puntos en el mapa para el Saco de dormir acogedor y la Antorcha del Guardia de la Noche (`/fcg varios`); la detección de profesiones ya no depende del nombre exacto que use el juego (arregla Sastrería en clientes en español) y `/fcg debug` para informar de errores.

**Novedades 2.4 (2026-11-05):** las cantidades se descuentan según tu habilidad (si vas por la mitad de un tramo, solo ves lo que te queda), nueva lista «Lo que aún te falta» en Compras, guías nuevas de Minería, Herboristería y Desuello, y rutas nuevas (con Artesano) en Herrería, Peletería y Sastrería.

**Novedades 2.3 (2026-10-22):** coordenadas de 305 PNJ incluidas: haz clic en cualquier instructor o vendedor para verlo en el mapa.

**Novedades 2.2 (datos del 2026-10-14):** nueva página de Favor del mercader (cajas, encargos, reputación y ~120 recetas de vendedor), materiales y planos de cada objeto de campamento, rutas nuevas en Herrería, Encantamiento, Peletería, Sastrería y Primeros auxilios, y varias zonas de inicio en Pesca + Cocina.


Guía interactiva de profesiones y campamento para WoW Forever, con los datos de
wow-professions.com/forever (guías de la beta).

## Instalación
1. Descomprime el zip y copia la carpeta `ForeverCampGuide` en `Interface\AddOns` de WoW Forever.
2. Reinicia el juego o escribe `/reload`.
3. Si sale como "obsoleto", activa "Cargar addons obsoletos" o pon en la línea `## Interface:`
   del `.toc` el número que devuelve `/dump select(4, GetBuildInfo())`.

## Qué incluye
Cada profesión con guía (Alquimia, Herrería, Encantamiento, Ingeniería, Peletería, Sastrería,
Cocina, Primeros auxilios, Pesca, Minería, Herboristería y Desuello) tiene estas pestañas:
- **Subir 1-300**: todos los pasos de la web, con el paso actual marcado según tu habilidad,
  si conoces cada receta, los materiales con lo que llevas en bolsas y banco, alternativas,
  rutas a elegir (se recuerdan), vendedores de recetas y avisos de tope de rango.
- **Instructores**: capitales, zonas de inicio (resalta tu raza) y dónde subir de rango.
- **Compras**: lista de la compra con recuento en vivo.
- **Recetas**: cuáles de la guía conoces y cuáles no, más las tablas extra (subasta, Annora...).
- **Campamento**: los objetos de campamento de esa profesión.
Además: páginas de campamento, fogatas, primer campamento (con misiones completadas),
novedades de Forever, la guía combinada **Pesca + Cocina** como lista de tareas, y opciones.

## Mapas
- Al hacer clic en un PNJ se abre un visor con la **imagen de la zona sacada del propio juego**,
  tu posición y los PNJ conocidos. Botones para poner un marcador (y en TomTom si lo tienes)
  o abrir el mapa del mundo.
- El addon incluye las **coordenadas de 305 PNJ** (instructores, vendedores y PNJ de misión),
  tomadas de las páginas de PNJ de wow-professions.com. Haz clic en [x, y] para poner un marcador.
  Si quieres corregir alguna, haz Ctrl+clic en el mapa o pulsa «Estoy junto a él».
- Las capturas de pantalla de la web no se pueden mostrar: el juego no carga imágenes de internet.

## Recetas conocidas
Abre una vez la ventana de cada profesión: el addon lee tus recetas y las guarda por personaje.
Mientras está abierta, aparece un panel al lado con el paso actual y sus materiales.

## Comandos
`/fcg` · `/fcg <profesión>` (ej. `/fcg alq`) · `/fcg mapa` · `/fcg opciones` · `/fcg tracker` · `/fcg minimap`

## Notas
- Los tramos altos están marcados como "sin probar" porque la beta tiene límite de nivel.
- Herboristería, Minería y Desuello no tienen guía de Forever en la web: solo muestran el campamento.
- Para actualizar datos, edita los archivos de `Guides/` (el formato está explicado en `Alchemy.lua`).
