--------------------------------------------------------------------------------
-- MapSeek's own map arithmetic and marker placing: where a point of a zone's map is in the
-- world (yards), where a point of the world is on a map, where you are; and putting a frame at
-- a point of the world map or the minimap and keeping it there.
--
-- It was a shared library's job (HereBeDragons, Questie's copy). Shared, it was only as sound as
-- whichever copy another addon had loaded, and gone the day Questie kept its copy to itself. Here
-- it leans on nothing but the game's own map functions.
--
-- The names and the arguments are the library's, so the rest of MapSeek calls this as it called
-- that: ns.Map for the arithmetic, ns.MapPins for the placing. World coordinates are the
-- library's too: x is the game's Y (it grows to the west), y the game's X (to the north).
--
-- "/seek maplib questie" goes back to Questie's copy, where there is one (and "/seek maplib own"
-- to this): for telling which is at fault, should a marker sit wrong.
--------------------------------------------------------------------------------

local _, ns = ...

local sqrt, abs, floor, max, min = math.sqrt, math.abs, math.floor, math.max, math.min

local Map, Pins = {}, {}

--------------------------------------------------------------------------------
-- A map's place in the world: how wide and tall it is (yards), its left and top edges, and the
-- world it's of (the game's "instance": 0 the Eastern Kingdoms, 1 Kalimdor). Asked of the game
-- once a map: where its top left corner and its middle are
--------------------------------------------------------------------------------

local mapData = {}   -- [uiMapID] = { width, height, left, top, instance = } or false

local function MapData(ui)
	local d = mapData[ui]
	if d ~= nil then return d or nil end
	d = false
	if type(ui) == "number" and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
		local ok1, inst, corner = pcall(C_Map.GetWorldPosFromMapPos, ui, CreateVector2D(0, 0))
		local ok2, _, middle = pcall(C_Map.GetWorldPosFromMapPos, ui, CreateVector2D(0.5, 0.5))
		if ok1 and ok2 and corner and middle and corner.GetXY and middle.GetXY then
			-- (the game's X runs north, its Y west: a map's top is its greatest X, its left its greatest Y)
			local top, left = corner:GetXY()
			local midX, midY = middle:GetXY()
			if top and left and midX and midY then
				local height, width = (top - midX) * 2, (left - midY) * 2
				if width ~= 0 and height ~= 0 then
					d = { width, height, left, top, instance = inst }
				end
			end
		end
	end
	mapData[ui] = d
	return d or nil
end

--- how wide and tall a map is, in yards; 0, 0 when the game can't say
function Map:GetZoneSize(ui)
	local d = MapData(ui)
	if not d then return 0, 0 end
	return d[1], d[2]
end

--- a point of a map (0..1) in the world: x, y (yards) and the world it's of; nil when the game
--- can't place that map
function Map:GetWorldCoordinatesFromZone(x, y, ui)
	local d = MapData(ui)
	if not (d and x and y) then return nil, nil, nil end
	return d[3] - d[1] * x, d[4] - d[2] * y, d.instance
end

-- a world, on a map the game can't place itself (the map of all Azeroth): by one of that map's
-- own maps that's of the world asked for (a continent's), and where the game says that one
-- sits on it
local onParent = {}   -- [host] = { [instance] = { child map, minX, maxX, minY, maxY } or false }
local function ByChild(host, instance)
	local of = onParent[host]
	if not of then of = {} onParent[host] = of end
	local c = of[instance]
	if c ~= nil then return c or nil end
	c = false
	if C_Map.GetMapChildrenInfo and C_Map.GetMapRectOnMap then
		local ok, kids = pcall(C_Map.GetMapChildrenInfo, host)
		for _, k in ipairs(ok and kids or {}) do
			local d = MapData(k.mapID)
			if d and d.instance == instance then
				local ok2, x0, x1, y0, y1 = pcall(C_Map.GetMapRectOnMap, k.mapID, host)
				if ok2 and x0 and x1 and y0 and y1 and x1 ~= x0 and y1 ~= y0 then
					c = { k.mapID, x0, x1, y0, y1 }
					break
				end
			end
		end
	end
	of[instance] = c
	return c or nil
end

--- a point of a world on a map: x, y (0..1), or nil when it's of another world, or off the map
--- (past its edges too, with allowOutOfBounds)
function Map:GetZoneCoordinatesFromWorldInstance(x, y, instance, ui, allowOutOfBounds)
	if not (x and y and ui) then return nil, nil end
	local d = MapData(ui)
	local zx, zy
	if d then
		if instance ~= nil and d.instance ~= instance then return nil, nil end
		zx, zy = (d[3] - x) / d[1], (d[4] - y) / d[2]
	else
		local c = instance ~= nil and ByChild(ui, instance)
		local cd = c and MapData(c[1])
		if not cd then return nil, nil end
		local cx, cy = (cd[3] - x) / cd[1], (cd[4] - y) / cd[2]
		zx, zy = c[2] + (c[3] - c[2]) * cx, c[4] + (c[5] - c[4]) * cy
	end
	if not allowOutOfBounds and (zx < 0 or zx > 1 or zy < 0 or zy > 1) then return nil, nil end
	return zx, zy
end

--- the same, of whatever world the map is of
function Map:GetZoneCoordinatesFromWorld(x, y, ui, allowOutOfBounds)
	local d = MapData(ui)
	if not (d and x and y) then return nil, nil end
	local zx, zy = (d[3] - x) / d[1], (d[4] - y) / d[2]
	if not allowOutOfBounds and (zx < 0 or zx > 1 or zy < 0 or zy > 1) then return nil, nil end
	return zx, zy
end

--- yards between two points of a world, and how far west and north the second is of the first;
--- nil when either's missing
function Map:GetWorldDistance(_, oX, oY, dX, dY)
	if not (oX and oY and dX and dY) then return nil, nil, nil end
	local deltaX, deltaY = dX - oX, dY - oY
	return sqrt(deltaX * deltaX + deltaY * deltaY), deltaX, deltaY
end

-- the world you're in, as the maps have it: the world your zone's map is of. (The game's own
-- word for it differs on a copy of a continent it keeps for a phase of a story; the maps', and
-- the places on them, don't.) Looked up twice a second, not every frame
local hereAt, hereInst, hereRaw = -1, nil, nil
local function WorldOfYou(raw)
	local now = GetTime()
	if now - hereAt < 0.5 and raw == hereRaw then return hereInst end
	hereAt, hereRaw, hereInst = now, raw, raw
	local ui = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	for _ = 1, 6 do
		if not ui then break end
		local d = MapData(ui)
		if d then hereInst = d.instance break end
		local info = C_Map.GetMapInfo(ui)
		ui = info and info.parentMapID
		if not ui or ui == 0 then break end
	end
	return hereInst
end

--- where you are in the world: x, y (yards) and the world; nil where the game won't say (in a
--- dungeon)
function Map:GetPlayerWorldPosition()
	local gx, gy, _, raw = UnitPosition("player")
	if not (gx and gy) then return nil, nil, nil end
	return gy, gx, WorldOfYou(raw)
end

--------------------------------------------------------------------------------
-- The minimap's view: yards from its middle to its edge, and whether it turns with you
--------------------------------------------------------------------------------

Pins.Minimap = Minimap

-- (how wide the minimap's view is at each zoom, out of doors and in: the game's own, long known)
local VIEW = {
	indoor = { [0] = 300, 240, 180, 120, 80, 50 },
	outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 },
}
local indoors, rotating = false, false

-- in or out of doors: the game keeps a zoom for each and says which it's using only by which of
-- the two its zoom now matches. They may be the same: then one's nudged to tell, and put back
-- (nudge: whether that's allowed. Never on the minimap's own zoom event: a nudge is two zooms,
-- each firing that event, and sensing again on each of those fed on itself, thousands of times
-- a frame from login, and the game down to 20 fps. On that event, only read; the two the same,
-- what was sensed on the last change of zone stands)
local function SenseIndoors(nudge)
	local mm = Pins.Minimap
	if not (mm and mm.GetZoom and GetCVar) then return end
	local zoom = mm:GetZoom()
	local out, inn = tonumber(GetCVar("minimapZoom")), tonumber(GetCVar("minimapInsideZoom"))
	if out == nil or inn == nil then indoors = IsIndoors and IsIndoors() or false return end
	if out == inn then
		if nudge and mm.SetZoom then
			mm:SetZoom(zoom < 2 and zoom + 1 or zoom - 1)
			out = tonumber(GetCVar("minimapZoom"))
			indoors = out ~= mm:GetZoom()
			mm:SetZoom(zoom)
		end
	else
		indoors = out ~= zoom
	end
end

function Pins:GetMinimapView()
	local radius
	if C_Minimap and C_Minimap.GetViewRadius then
		radius = C_Minimap.GetViewRadius()
	else
		local mm = Pins.Minimap
		local size = VIEW[indoors and "indoor" or "outdoor"][mm and mm.GetZoom and mm:GetZoom() or 0]
		radius = size and size / 2
	end
	return radius, rotating
end

--------------------------------------------------------------------------------
-- Frames kept at a point of the world map. Each is a child of the map's canvas (what pans and
-- zooms), set at its point of it; shown on its own zone's map and the maps that zone is part of
-- (its continent's), and on OpenMap's stitched map, wherever the point comes on it
--------------------------------------------------------------------------------

local world = {}        -- [ref] = { [frame] = { ui, x, y } }
local worldDirty = true
local worldKey, worldScale
local worldLook, worldStill = nil, 0

-- whether map `host` is map `ui`, or one it's part of (its continent's; not the map of all Azeroth)
local function Holds(host, ui)
	local id = ui
	for _ = 1, 8 do
		if id == host then return true end
		local info = id and C_Map.GetMapInfo(id)
		id = info and info.parentMapID
		if not id or id == 0 then return false end
		-- (the map of the world, or of all the worlds: a marker isn't shown that far out)
		local up = C_Map.GetMapInfo(id)
		if not up or up.mapType == nil or up.mapType < 2 then return false end
	end
	return false
end

-- a point of a zone's map on the map showing: x, y (0..1), or nil where it isn't shown
local function OnShown(host, stitched, ui, x, y)
	if stitched then
		local api = OpenMapAPI
		local u, v = api.WorldFromMap(ui, x, y)
		if not u then return end
		return api.MapFromWorld(host, u, v)
	end
	if not Holds(host, ui) then return end
	local wx, wy, inst = Map:GetWorldCoordinatesFromZone(x, y, ui)
	if not wx then return end
	return Map:GetZoneCoordinatesFromWorldInstance(wx, wy, inst, host, false)
end

-- whether a point of the map underneath (x, y as OnShown gives them) is somewhere the map shows.
-- The game's own map shows its own rectangle and no more. OpenMap's stitched map shows the land
-- around the map underneath too, as far as you've zoomed out, so a point well past its edges is
-- still in sight: zoomed in on Thunder Bluff, the map underneath is the city's, and a marker
-- outside the city was hidden though the view showed where it stood. (A bound all the same:
-- far beyond any view, nothing need be laid out)
local STITCH_REACH = 60   -- widths of the map underneath, either way
local function InView(stitched, x, y)
	if not (x and y) then return false end
	if stitched then return x >= -STITCH_REACH and x <= 1 + STITCH_REACH and y >= -STITCH_REACH and y <= 1 + STITCH_REACH end
	return x >= 0 and x <= 1 and y >= 0 and y <= 1
end

local function PlaceWorld(scaleNow)
	local frame = WorldMapFrame
	local view = frame and frame.ScrollContainer
	local canvas = view and view.Child
	if not (canvas and frame:IsShown()) then return end
	local host = frame:GetMapID()
	local api = OpenMapAPI
	local stitched = api and api.IsStitched and api.IsStitched() and api.WorldFromMap and api.MapFromWorld and true or false
	local w, h, scale = canvas:GetWidth(), canvas:GetHeight(), scaleNow or canvas:GetScale()
	-- (not the zoom: a point of the canvas stays that point of it however it's zoomed, so a zoom
	-- moves nothing here, and a marker pulsing over its point isn't nudged at every step of one.
	-- Only one that's a marker itself is sized again for it, below)
	local key = ("%s:%s:%.0f:%.0f"):format(tostring(host), tostring(stitched), w, h)
	-- (laid out again a moment after the map's stopped moving, and again a little later: OpenMap
	-- goes from one map to the next part way through a zoom, and a marker laid out from that
	-- moment can come out off the map and be hidden, with nothing changing after to show it again)
	local look = ("%s:%.4f"):format(key, scale)
	if look ~= worldLook then worldLook, worldStill = look, 0
	else
		worldStill = worldStill + 1
		if worldStill == 4 or worldStill == 16 then worldDirty = true end
	end
	if key == worldKey and not worldDirty then
		if scale ~= worldScale then
			worldScale = scale
			for _, set in pairs(world) do
				for f, at in pairs(set) do
					if not f.marker and at.sx then
						local own = 1 / max(scale, 0.01)
						f:SetScale(own)
						f:ClearAllPoints()
						f:SetPoint("CENTER", canvas, "TOPLEFT", at.sx * w / own, -at.sy * h / own)
					end
				end
			end
		end
		return
	end
	worldKey, worldDirty, worldScale = key, false, scale
	for _, set in pairs(world) do
		for f, at in pairs(set) do
			local sx, sy
			if host and w > 0 then sx, sy = OnShown(host, stitched, at[1], at[2], at[3]) end
			if InView(stitched, sx, sy) then
				if f:GetParent() ~= canvas then f:SetParent(canvas) end
				-- (one that's a marker itself, not an unseen point a marker's held to: its own
				-- size whatever the map's zoom)
				local own = 1
				if not f.marker then
					own = 1 / max(scale, 0.01)
					if f:GetScale() ~= own then f:SetScale(own) end
				end
				at.sx, at.sy = sx, sy
				f:ClearAllPoints()
				f:SetPoint("CENTER", canvas, "TOPLEFT", sx * w / own, -sy * h / own)
				f:Show()
			else
				at.sx, at.sy = nil, nil
				if f:IsShown() then f:Hide() end
			end
		end
	end
end

--- a frame at a point (0..1) of a zone's map, on the world map
function Pins:AddWorldMapIconMap(ref, frame, ui, x, y)
	if not (ref and frame and ui and x and y) then return end
	local set = world[ref]
	if not set then set = {} world[ref] = set end
	set[frame] = { ui, x, y }
	worldDirty = true
end

function Pins:RemoveWorldMapIcon(ref, frame)
	local set = world[ref]
	if set and set[frame] then
		set[frame] = nil
		frame:Hide()
	end
end

function Pins:RemoveAllWorldMapIcons(ref)
	for f in pairs(world[ref] or {}) do f:Hide() end
	world[ref] = nil
end

--------------------------------------------------------------------------------
-- Paths on the world map: the way an NPC walks (QuestieDB's own data: for each zone it's in,
-- its patrols, each a run of points of that zone's map, 0..100). Thin lines on the map's canvas,
-- under the markers, drawn again when the map shown, its size or its zoom changes. (Questie
-- drew these, on its own pins; MapSeek's markers aren't those any more)
--------------------------------------------------------------------------------

local paths = {}        -- { { ui, points }, ... }
local pathF, pathKey
local pathPool = {}
local pathDirty = false
-- (as Questie draws them, so they read the same: amber for one who's friendly to you or to
-- no one in particular, red for one who's hostile; 3 wide. Questie there, and its own colours
-- or width changed in its options: those)
local PATH_COLOUR, PATH_HOSTILE = { 1, 0.72, 0, 0.5 }, { 1, 0.2, 0, 0.7 }
local PATH_LIT = { 0.93, 0.46, 0.13, 0.8 }   -- (the one whose marker, or whose own line, the mouse is on: Questie's orange for it)
local PATH_PX, PATH_MAX = 3, 3000
local PATH_REACH = 7    -- pixels of the screen from a path's line: the mouse is on it
local pathLit           -- whose paths are lit: by its marker, or by the mouse on one of its lines
local pathLitBy         -- "marker" or "line"
local pathSegs = {}     -- the lines as drawn: { ax, ay, bx, by, owner } (canvas units)
local pathSeen, pathBase, pathStill, pathMoving = nil, nil, 0, false
local PATH_SETTLE = 3   -- looks (a twentieth of a second each) the map must be still for before they're drawn
-- (a hover lights a path or puts it out by colouring the lines already drawn, nothing else: drawn
-- again whole for it, mid-zoom, they could come out anywhere, or under the map, and stay so)
local pathLineOf = {}   -- [line number] = the path it's part of
local pathDrawn = { n = 0, scale = 1, recolour = false, log = {} }
-- (/seek paths: what happened to them lately, each with its time, the last 40)
function pathDrawn.Note(fmt, ...)
	local log = pathDrawn.log
	log[#log + 1] = ("%.2f  " .. fmt):format(GetTime(), ...)
	if #log > 40 then table.remove(log, 1) end
end
local PATH_AGAIN = 14   -- and drawn once more at this many (OpenMap can still be finishing a change of map)

local function PathStyle(hostile, lit)
	local col, px, fade = lit and PATH_LIT or hostile and PATH_HOSTILE or PATH_COLOUR, PATH_PX, 1
	local Q = _G.Questie
	local prof = Q and type(Q.db) == "table" and type(Q.db.profile) == "table" and Q.db.profile
	if prof then
		local theirs = hostile and prof.waypointHostileColor or prof.waypointColor
		-- (Questie's own choice of whether a path lights up, and in what colour)
		if lit and prof.waypointHighlight == false then lit = false col = hostile and PATH_HOSTILE or PATH_COLOUR end
		if lit then theirs = prof.waypointHighlightColor end
		if type(theirs) == "table" and type(theirs[1]) == "number" and type(theirs[2]) == "number" and type(theirs[3]) == "number" then col = theirs end
		if type(prof.waypointWidth) == "number" and prof.waypointWidth > 0 then px = prof.waypointWidth end
		if type(prof.waypointOpacity) == "number" then fade = prof.waypointOpacity end
	end
	return col[1], col[2], col[3], min(1, (col[4] or 1) * fade), px
end

local function DrawPaths(scaleNow)
	local frame = WorldMapFrame
	local view = frame and frame.ScrollContainer
	local canvas = view and view.Child
	if not canvas then return end
	if #paths == 0 then
		if pathF and pathF:IsShown() then pathF:Hide() end
		pathKey = nil
		return
	end
	if not frame:IsShown() then return end
	if not pathF then
		pathF = CreateFrame("Frame", nil, canvas)
		pathF:SetAllPoints(canvas)
		pathF:EnableMouse(false)
	end
	local host = frame:GetMapID()
	local api = OpenMapAPI
	local stitched = api and api.IsStitched and api.IsStitched() and api.WorldFromMap and api.MapFromWorld and true or false
	local w, h, scale = canvas:GetWidth(), canvas:GetHeight(), scaleNow or canvas:GetScale()
	-- (the map on the move: zooming, or going from one map to another, OpenMap's stitched one
	-- among them. For those few frames its size, zoom and which map it is don't all belong
	-- together, and lines worked out from them land anywhere, the middle of the map as likely
	-- as not. So nothing's drawn until it has been the same for a moment)
	-- (kept over the map's art every look, not only when drawn: OpenMap's stitched map is pieces
	-- on this same canvas, and the ones it makes as you zoom come in at levels of their own. Under
	-- one, a path's lines are there but unseen, until something put it back on top)
	local level = ns.Pins and ns.Pins.UnderLevel and ns.Pins.UnderLevel() or 1
	local art = stitched and api.ArtTopLevel and api.ArtTopLevel()
	if type(art) == "number" and art >= level then level = art + 1 end
	if pathF:GetFrameLevel() ~= level then
		pathDrawn.Note("level %d -> %d (art top %s)", pathF:GetFrameLevel(), level, tostring(art))
		pathF:SetFrameLevel(level)
	end
	-- (seen or not, as the game has it: noted when it changes)
	local seen = pathF.IsVisible and pathF.GetEffectiveAlpha and pathF:IsVisible() and pathF:GetEffectiveAlpha() > 0.05
	if pathF.GetEffectiveAlpha and seen ~= pathDrawn.seen then
		pathDrawn.seen = seen
		pathDrawn.Note("%s (layer %s, alpha %.2f, canvas alpha %.2f)", seen and "SEEN" or "NOT SEEN",
			pathF:IsShown() and "shown" or "hidden", pathF:GetEffectiveAlpha(), canvas:GetEffectiveAlpha())
	end
	local base = ("%s:%s:%.0f:%.0f"):format(tostring(host), tostring(stitched), w, h)
	local now = ("%s:%.4f"):format(base, scale)
	if now ~= pathSeen then
		pathSeen, pathStill = now, 0
		-- (another map, or the map another size: what's drawn is of the old one. OpenMap's map
		-- going from one zone's to the next as you zoom: drawn for the new one at once, as OpenMap
		-- puts the new map and its view in place together, so they agree by the time it's looked
		-- at. Blizzard's own map: taken off till it's still, as its size, zoom and map can be
		-- out of step for a frame or two, and lines worked out then land anywhere. Only zoomed:
		-- the lines are part of the canvas and zoom with it, right where they are; left up, and
		-- drawn afresh, their width put right, once it stops)
		local switched = base ~= pathBase
		if switched then
			pathDrawn.Note("map %s, %.0fx%.0f, stitched %s (was %s)%s", tostring(host), w, h,
				tostring(stitched), tostring(pathBase), stitched and ": drawn for it now" or ": hidden till it's still")
			pathBase = base
			if not stitched and pathF:IsShown() then pathF:Hide() end
		elseif not pathMoving then
			pathDrawn.Note("zoom %.3f", scale)
		end
		pathMoving = true
		if not (switched and stitched) then return end
		pathDirty = true
	else
		pathStill = pathStill + 1
		if pathMoving then
			if pathStill < PATH_SETTLE then return end
			pathMoving, pathDirty = false, true
		elseif pathStill == PATH_AGAIN then
			pathDirty = true
		end
	end
	local key = ("%s:%d"):format(now, #paths)
	if key == pathKey and not pathDirty then return end
	local why = pathStill == 0 and "new map" or pathStill == PATH_SETTLE and "still" or pathStill == PATH_AGAIN and "again" or "changed"
	pathKey, pathDirty = key, false
	local n = 0
	pathDrawn.scale, pathDrawn.recolour = scale, false
	if host and w > 0 and pathF.CreateLine then
		for k = #pathSegs, 1, -1 do pathSegs[k] = nil end
		for _, p in ipairs(paths) do
			local lit = pathLit ~= nil and p[4] == pathLit
			local r, g, b, a, px = PathStyle(p[3], lit)
			-- (a lit one a little wider, and over the others)
			local thick = (px + (lit and 1 or 0)) / max(scale, 0.01)
			local ax, ay
			for _, pt in ipairs(p[2]) do
				local bx, by
				if type(pt) == "table" and type(pt[1]) == "number" and type(pt[2]) == "number" then
					bx, by = OnShown(host, stitched, p[1], pt[1] / 100, pt[2] / 100)
				end
				if ax and bx and n < PATH_MAX then
					n = n + 1
					local l = pathPool[n]
					if not l then
						l = pathF:CreateLine(nil, "ARTWORK")
						pathPool[n] = l
					end
					pathLineOf[n] = p
					l:SetColorTexture(r, g, b, a)
					l:SetDrawLayer("ARTWORK", lit and 2 or 1)
					l:SetThickness(thick)
					if p[4] ~= nil then pathSegs[#pathSegs + 1] = { ax * w, ay * h, bx * w, by * h, p[4] } end
					l:SetStartPoint("TOPLEFT", pathF, ax * w, -ay * h)
					l:SetEndPoint("TOPLEFT", pathF, bx * w, -by * h)
					l:Show()
				end
				ax, ay = bx, by
			end
		end
	end
	for i = n + 1, #pathPool do pathPool[i]:Hide() pathLineOf[i] = nil end
	pathDrawn.n = n
	pathF:SetShown(n > 0)
	-- (how many start inside the map's view, as drawn: none, and they've been put somewhere else)
	local view = frame.ScrollContainer
	local inSight = 0
	if view.GetLeft and canvas.GetLeft and canvas.GetEffectiveScale and view:GetLeft() and canvas:GetLeft()
		and (n == 0 or pathPool[1].GetStartPoint) then
		local cs, vs = canvas:GetEffectiveScale(), view:GetEffectiveScale()
		local vl, vr, vt, vb = view:GetLeft() * vs, view:GetRight() * vs, view:GetTop() * vs, view:GetBottom() * vs
		local cl, ct = canvas:GetLeft() * cs, canvas:GetTop() * cs
		for i = 1, n do
			local _, _, ox, oy = pathPool[i]:GetStartPoint()
			if ox then
				local sx, sy = cl + ox * cs, ct + oy * cs
				if sx >= vl and sx <= vr and sy <= vt and sy >= vb then inSight = inSight + 1 end
			end
		end
	end
	pathDrawn.Note("drawn (%s): %d lines, %d in sight; map %s zoom %.3f", why, n, inSight, tostring(host), scale)
end

-- the lines as drawn, coloured again for which is lit now
local function RecolourPaths()
	if not pathDrawn.recolour then return end
	pathDrawn.recolour = false
	for i = 1, pathDrawn.n do
		local p, l = pathLineOf[i], pathPool[i]
		if p and l then
			local lit = pathLit ~= nil and p[4] == pathLit
			local r, g, b, a, px = PathStyle(p[3], lit)
			l:SetColorTexture(r, g, b, a)
			l:SetDrawLayer("ARTWORK", lit and 2 or 1)
			l:SetThickness((px + (lit and 1 or 0)) / max(pathDrawn.scale, 0.01))
		end
	end
end

-- the mouse on one of the lines: that NPC's paths lit (unless a marker's lighting some just now)
local function PathHover()
	if pathLitBy == "marker" or #pathSegs == 0 or pathMoving then return end
	local view = WorldMapFrame and WorldMapFrame.ScrollContainer
	local canvas = view and view.Child
	local over
	if canvas and WorldMapFrame:IsShown() and view.GetNormalizedCursorPosition
		and (not view.IsMouseOver or view:IsMouseOver()) then
		local ok, cx, cy = pcall(view.GetNormalizedCursorPosition, view)
		if ok and cx and cy and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then
			local w, h = canvas:GetWidth(), canvas:GetHeight()
			local mx, my = cx * w, cy * h
			local reach = PATH_REACH / max(canvas:GetScale(), 0.01)
			local best = reach * reach
			for _, s in ipairs(pathSegs) do
				local dx, dy = s[3] - s[1], s[4] - s[2]
				local l2 = dx * dx + dy * dy
				local t = l2 > 0 and max(0, min(1, ((mx - s[1]) * dx + (my - s[2]) * dy) / l2)) or 0
				local d2 = (mx - s[1] - t * dx) ^ 2 + (my - s[2] - t * dy) ^ 2
				if d2 <= best then best, over = d2, s[5] end
			end
		end
	end
	if over ~= pathLit then
		pathLit, pathLitBy = over, over ~= nil and "line" or nil
		pathDrawn.recolour = true
	end
end

--- an NPC's paths on the world map, kept until Clear: ns.MapPaths.Add(zone's map, its points,
--- whether it's hostile to you, whose they are). Light(whose): that one's lit, while the mouse
--- is on its marker; Light(nil): none, by a marker
ns.MapPaths = {
	-- /seek paths: how the paths' layer stands, for telling why one isn't seen
	Debug = function()
		local canvas = WorldMapFrame and WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
		local api = OpenMapAPI
		local art = api and api.ArtTopLevel and api.ArtTopLevel()
		local shownLines, alpha = 0, nil
		for i = 1, pathDrawn.n do
			local l = pathPool[i]
			if l and l:IsShown() then shownLines = shownLines + 1 alpha = alpha or select(4, l:GetVertexColor()) end
		end
		ns.Print("recent:")
		for _, line in ipairs(pathDrawn.log) do print("  " .. line) end
		ns.Print(("now %.2f: paths %d, lines drawn %d (%d shown); layer %s, level %s, alpha %s; canvas level %s; OpenMap art top %s; stitched %s; moving %s (still %d); lit %s by %s"):format(
			GetTime(), #paths, pathDrawn.n, shownLines, pathF and (pathF:IsShown() and "shown" or "hidden") or "none",
			pathF and pathF:GetFrameLevel() or "-", pathF and ("%.2f"):format(pathF:GetEffectiveAlpha()) or "-",
			canvas and canvas:GetFrameLevel() or "-", tostring(art),
			tostring(api and api.IsStitched and api.IsStitched() or false), tostring(pathMoving), pathStill,
			tostring(pathLit), tostring(pathLitBy)))
		-- where the lines are against where they'd be drawn now, and how many of them are in sight
		local view = WorldMapFrame and WorldMapFrame.ScrollContainer
		if not (canvas and view and pathF and pathDrawn.n > 0) then return end
		local host = WorldMapFrame:GetMapID()
		local stitched = api and api.IsStitched and api.IsStitched() and api.WorldFromMap and api.MapFromWorld and true or false
		local w, h = canvas:GetWidth(), canvas:GetHeight()
		local first = paths[1] and paths[1][2] and paths[1][2][1]
		local nx, ny
		if first then nx, ny = OnShown(host, stitched, paths[1][1], first[1] / 100, first[2] / 100) end
		local seg = pathSegs[1]
		local _, _, dx, dy = pathPool[1]:GetStartPoint()
		local cs, vs = canvas:GetEffectiveScale(), view:GetEffectiveScale()
		local vl, vr, vt, vb = view:GetLeft() * vs, view:GetRight() * vs, view:GetTop() * vs, view:GetBottom() * vs
		local cl, ct = canvas:GetLeft() * cs, canvas:GetTop() * cs
		local inSight = 0
		for i = 1, pathDrawn.n do
			local _, _, ox, oy = pathPool[i]:GetStartPoint()
			if ox then
				local sx, sy = cl + ox * cs, ct + oy * cs
				if sx >= vl and sx <= vr and sy <= vt and sy >= vb then inSight = inSight + 1 end
			end
		end
		ns.Print(("map %s %.0fx%.0f scale %.3f; first point drawn at %s, %s (now it'd be %s, %s); drawn for %s; %d of %d lines start in sight"):format(
			tostring(host), w, h, canvas:GetScale(),
			dx and ("%.0f"):format(dx) or "?", dy and ("%.0f"):format(dy) or "?",
			nx and ("%.0f"):format(nx * w) or "-", ny and ("%.0f"):format(-ny * h) or "-",
			tostring(pathKey), inSight, pathDrawn.n))
	end,
	Light = function(owner)
		if owner == nil then
			if pathLitBy ~= "marker" then return end
			pathLit, pathLitBy = nil, nil
		else
			if pathLit == owner and pathLitBy == "marker" then return end
			pathLit, pathLitBy = owner, "marker"
		end
		pathDrawn.recolour = true
	end,
	Add = function(ui, points, hostile, owner)
		if type(ui) ~= "number" or type(points) ~= "table" or #points < 2 then return end
		paths[#paths + 1] = { ui, points, hostile and true or false, owner }
		pathDirty = true
	end,
	Clear = function()
		if #paths > 0 then paths = {} pathDirty = true end
		pathLit, pathLitBy = nil, nil
		for k = #pathSegs, 1, -1 do pathSegs[k] = nil end
	end,
}

--------------------------------------------------------------------------------
-- Frames kept at a point of the minimap, as you move and turn and it zooms. One beyond its edge
-- is hidden, or (floatOnEdge) held at the edge, the way to it
--------------------------------------------------------------------------------

local mini = {}         -- [ref] = { [frame] = { wx, wy, instance, edge } }
local miniCount = 0
local miniDirty = true
local lastX, lastY, lastF, lastR, lastW

local EDGE = 0.92       -- of the way to the minimap's edge: where one held at the edge sits

local function PlaceMini()
	local mm = Pins.Minimap
	if miniCount == 0 or not mm then return end
	local px, py, pinst = Map:GetPlayerWorldPosition()
	local radius, turns = Pins:GetMinimapView()
	local facing = turns and GetPlayerFacing and GetPlayerFacing() or 0
	local hw, hh = mm:GetWidth() / 2, mm:GetHeight() / 2
	if not (px and radius and radius > 0) or (turns and not facing) then
		-- (nowhere the game will say you are: none of them shown)
		if lastX ~= false then
			for _, set in pairs(mini) do for f in pairs(set) do f:Hide() end end
			lastX = false
		end
		return
	end
	if px == lastX and py == lastY and facing == lastF and radius == lastR and hw == lastW and not miniDirty then return end
	lastX, lastY, lastF, lastR, lastW, miniDirty = px, py, facing, radius, hw, false
	local s, c = 0, 1
	if turns then s, c = math.sin(facing), math.cos(facing) end
	local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
	for _, set in pairs(mini) do
		for f, at in pairs(set) do
			if at[3] ~= pinst then
				if f:IsShown() then f:Hide() end
			else
				-- (yards west and north of you, turned with the minimap, in its halves)
				local dx, dy = px - at[1], py - at[2]
				if turns then dx, dy = dx * c - dy * s, dx * s + dy * c end
				local ux, uy = dx / radius, -dy / radius
				local far
				if square then far = max(abs(ux), abs(uy)) else far = sqrt(ux * ux + uy * uy) end
				local shown = true
				if far > EDGE then
					if at[4] then
						ux, uy = ux / far * EDGE, uy / far * EDGE
					else
						shown = false
					end
				end
				f.minimapEdge = far > EDGE or nil
				if shown then
					if f:GetParent() ~= mm then f:SetParent(mm) end
					f:ClearAllPoints()
					f:SetPoint("CENTER", mm, "CENTER", ux * hw, uy * hh)
					if not f:IsShown() then f:Show() end
				elseif f:IsShown() then
					f:Hide()
				end
			end
		end
	end
end

--- a frame at a point (0..1) of a zone's map, on the minimap. floatOnEdge: held at the minimap's
--- edge when the point's beyond it
function Pins:AddMinimapIconMap(ref, frame, ui, x, y, _, floatOnEdge)
	if not (ref and frame and ui and x and y) then return end
	local wx, wy, inst = Map:GetWorldCoordinatesFromZone(x, y, ui)
	if not wx then return end
	local set = mini[ref]
	if not set then set = {} mini[ref] = set end
	if not set[frame] then miniCount = miniCount + 1 end
	set[frame] = { wx, wy, inst, floatOnEdge and true or false }
	miniDirty = true
end

function Pins:RemoveMinimapIcon(ref, frame)
	local set = mini[ref]
	if set and set[frame] then
		set[frame] = nil
		miniCount = miniCount - 1
		frame:Hide()
	end
end

function Pins:RemoveAllMinimapIcons(ref)
	for f in pairs(mini[ref] or {}) do
		miniCount = miniCount - 1
		f:Hide()
	end
	mini[ref] = nil
end

--- whether a frame put on the minimap is held at its edge just now (its point beyond it)
function Pins:IsMinimapIconOnEdge(frame) return frame and frame.minimapEdge or false end

--------------------------------------------------------------------------------
-- Kept up: the world map's while it's open, when its map, size or zoom changes; the minimap's
-- as you move
--------------------------------------------------------------------------------

-- the map underneath changing, in the frame it changes: everything of ours on the canvas is
-- laid out for the old map, and shown on the new one for that frame it's wrong, the paths most
-- of all. (OpenMap's stitched map goes from a zone's map to the continent's as you zoom out: a
-- path drawn for the zone, 0..1 of it, came out across the whole continent, eight times its size,
-- in the middle of the map, for a frame, then sprang back as the next look drew it again.) So
-- taken off here, as the switch happens, and laid out again, and shown, at the next look
-- (how wide a map is on OpenMap's stitched world)
local function WorldSpan(api, host)
	local u0 = api.WorldFromMap(host, 0, 0)
	local u1 = api.WorldFromMap(host, 1, 0)
	if u0 and u1 and u1 ~= u0 then return abs(u1 - u0) end
end

local function MapSwitched()
	pathDirty, worldDirty = true, true
	-- OpenMap's stitched map: drawn for the new map here and now, so there's no frame without.
	-- Where things go on it doesn't depend on the zoom, only on which map's underneath, and
	-- that's known. Their size does, and the canvas's zoom at this moment is the game's own
	-- default for the new map, OpenMap's coming the moment this returns. But OpenMap keeps the
	-- view's yards to the pixel over a switch, so the zoom it will set is the old one by the
	-- two maps' widths in the world
	local api = OpenMapAPI
	local frame = WorldMapFrame
	local stitched = api and api.IsStitched and api.IsStitched() and api.WorldFromMap and api.MapFromWorld
	local was, host = pathDrawn.seenHost, frame and frame:GetMapID()
	if stitched and was and host and was ~= host and pathDrawn.seenScale then
		local a, b = WorldSpan(api, was), WorldSpan(api, host)
		if a and b then
			local scale = pathDrawn.seenScale * b / a
			if pathDrawn.Note then pathDrawn.Note("switch %s -> %s: drawn at once, zoom %.3f expected", tostring(was), tostring(host), scale) end
			if next(world) then PlaceWorld(scale) end
			DrawPaths(scale)
			return
		end
	end
	-- (the game's own map, or no way of telling: taken off for the frame, back at the next look)
	if pathF and pathF:IsShown() then pathF:Hide() end
	if next(world) then
		for _, set in pairs(world) do
			for f in pairs(set) do if f:IsShown() then f:Hide() end end
		end
	end
	if pathDrawn.Note then pathDrawn.Note("switch: taken off for the frame") end
end
if WorldMapFrame and WorldMapFrame.OnMapChanged and hooksecurefunc then
	hooksecurefunc(WorldMapFrame, "OnMapChanged", MapSwitched)
end

local watch = CreateFrame("Frame")
local sinceMini, sinceWorld = 0, 0
watch:SetScript("OnUpdate", function(_, elapsed)
	sinceMini = sinceMini + elapsed
	if sinceMini >= 0.03 then
		sinceMini = 0
		PlaceMini()
	end
	sinceWorld = sinceWorld + elapsed
	if sinceWorld >= 0.05 then
		sinceWorld = 0
		if next(world) then PlaceWorld() end
		PathHover()
		DrawPaths()
		RecolourPaths()
		local frame = WorldMapFrame
		local canvas = frame and frame.ScrollContainer and frame.ScrollContainer.Child
		if canvas and frame:IsShown() then pathDrawn.seenHost, pathDrawn.seenScale = frame:GetMapID(), canvas:GetScale() end
	end
end)
watch:RegisterEvent("PLAYER_ENTERING_WORLD")
watch:RegisterEvent("MINIMAP_UPDATE_ZOOM")
watch:RegisterEvent("ZONE_CHANGED_INDOORS")
watch:RegisterEvent("ZONE_CHANGED")
watch:RegisterEvent("ZONE_CHANGED_NEW_AREA")
watch:RegisterEvent("CVAR_UPDATE")
watch:SetScript("OnEvent", function(_, event, name)
	if event == "CVAR_UPDATE" then
		if name ~= "rotateMinimap" and name ~= "ROTATE_MINIMAP" then return end
	elseif event == "MINIMAP_UPDATE_ZOOM" then
		SenseIndoors(false)
	else
		SenseIndoors(true)
		hereAt = -1
	end
	rotating = GetCVar and GetCVar("rotateMinimap") == "1" or false
	miniDirty, worldDirty = true, true
end)

--------------------------------------------------------------------------------
-- Which is used: this, or Questie's copy of the library ("/seek maplib questie"). What the rest
-- of MapSeek holds is one of these two stand-ins; each call goes to whichever is chosen
--------------------------------------------------------------------------------

local function Other(module, probe)
	local loader = _G.QuestieLoader
	if loader and loader.ImportModule then
		local ok, mod = pcall(loader.ImportModule, loader, module)
		if ok and type(mod) == "table" and type(mod[probe]) == "function" then return mod end
	end
	if LibStub then
		local name = module == "HBDPins" and "-Pins-2.0" or "-2.0"
		local lib = LibStub("HereBeDragonsQuestie" .. name, true) or LibStub("HereBeDragons" .. name, true)
		if lib and type(lib[probe]) == "function" then return lib end
	end
end

local function StandIn(own, module, probe)
	local wraps = {}
	return setmetatable({}, { __index = function(_, k)
		local src = own
		if ns.mapLibOther then src = Other(module, probe) or own end
		local v = src[k]
		if type(v) ~= "function" then return v end
		-- (called with the stand-in for itself: handed on with what it stands for)
		local of = wraps[src]
		if not of then of = {} wraps[src] = of end
		local w = of[k]
		if not w then
			w = function(_, ...) return v(src, ...) end
			of[k] = w
		end
		return w
	end })
end

ns.Map = StandIn(Map, "HBD", "GetWorldCoordinatesFromZone")
ns.MapPins = StandIn(Pins, "HBDPins", "AddWorldMapIconMap")

--- whether Questie's copy (or another addon's) is there to go back to
function ns.MapLibHasOther()
	return Other("HBD", "GetWorldCoordinatesFromZone") ~= nil and Other("HBDPins", "AddWorldMapIconMap") ~= nil
end

-- (for testing it outside the game)
ns.MapOwn, ns.MapPinsOwn = Map, Pins
