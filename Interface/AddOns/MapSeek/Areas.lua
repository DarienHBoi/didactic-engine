-- MapSeek: areas on the map. Where an item drops: its spawns gathered into clusters, the one
-- to show picked (a big one, the nearest of them), and its outline worked out to be drawn as
-- the game draws a quest's area (Pins.lua).
local _, ns = ...
local Areas = {}
ns.Areas = Areas

local HBD = ns.MapLib and ns.MapLib("HBD", "GetWorldCoordinatesFromZone") or (LibStub and LibStub("HereBeDragons-2.0", true))
local floor, ceil, sqrt, max, min, abs, huge = math.floor, math.ceil, math.sqrt, math.max, math.min, math.abs, math.huge

local EPS_MIN, EPS_MAX = 40, 300   -- yards: spawns this close (or closer) are one area
local EPS_TIMES = 2.5              -- (how close: this many times the usual gap between spawns)
local NN_RING = 50                 -- yards: the cells the gap's looked for in
local NN_RINGS = 12                -- (that many cells out at most)
local SAMPLE = 400                 -- spawns the usual gap's measured from
local ZONE_MAX = 2500              -- spawns of one zone read at most (every so many, past it)
local BIG_ENOUGH = 0.4             -- an area this much of the best's score: good enough to be picked for being near
local SPREAD_CELL = 40             -- yards: the squares an area's spread is counted in (its score: below)
local HERE_SHARE = 0.15            -- (in your own zone, this much is enough ...
local HERE_MIN = 8                 -- ... with this many spawns at least)
local RADIUS = 0.65                -- the outline: this much of the gap around each spawn
local RADIUS_MIN = 30              -- yards, at least
local GRID_MAX = 70                -- the outline's grid: this many cells across at most
local VERTS_MAX = 120              -- an outline's corners at most

-- a zone's size in yards (a usual zone's, when it isn't known)
local function ZoneSize(ui)
	if HBD and HBD.GetZoneSize then
		local w, h = HBD:GetZoneSize(ui)
		if w and h and w > 0 and h > 0 then return w, h end
	end
	return 4000, 2700
end

local function Key(cx, cy) return cx * 65536 + cy end

-- the usual (median) gap from a spawn to its nearest other, in yards
local function UsualGap(P)
	if #P < 2 then return EPS_MIN end
	local grid = {}
	for i, p in ipairs(P) do
		local k = Key(floor(p.X / NN_RING), floor(p.Y / NN_RING))
		local g = grid[k]
		if not g then g = {} grid[k] = g end
		g[#g + 1] = i
	end
	local gaps = {}
	local step = max(1, floor(#P / SAMPLE))
	for i = 1, #P, step do
		local p = P[i]
		local cx, cy = floor(p.X / NN_RING), floor(p.Y / NN_RING)
		local best = huge
		for ring = 0, NN_RINGS do
			if sqrt(best) <= (ring - 1) * NN_RING then break end
			for dx = -ring, ring do
				for dy = -ring, ring do
					if max(abs(dx), abs(dy)) == ring then
						local g = grid[Key(cx + dx, cy + dy)]
						if g then
							for _, j in ipairs(g) do
								local q = P[j]
								local d = (q.X - p.X) ^ 2 + (q.Y - p.Y) ^ 2
								if d >= 1 and d < best then best = d end   -- (not itself, nor one on its spot)
							end
						end
					end
				end
			end
		end
		gaps[#gaps + 1] = best < huge and sqrt(best) or NN_RING * NN_RINGS
	end
	table.sort(gaps)
	return gaps[ceil(#gaps / 2)]
end

--- the spawns { { ui, x, y (0..100), src, wt? }, ... } gathered into areas, zone by zone:
--- { { ui, pts, eps, w, h, x, y (its middle, 0..100), wt (its spawns' weights) }, ... }
function Areas.Clusters(points)
	local byZone, zones = {}, {}
	for _, p in ipairs(points) do
		local z = byZone[p.ui]
		if not z then z = {} byZone[p.ui] = z zones[#zones + 1] = p.ui end
		z[#z + 1] = p
	end
	local out = {}
	for _, ui in ipairs(zones) do
		local list = byZone[ui]
		local w, h = ZoneSize(ui)
		local P = {}
		local step = #list > ZONE_MAX and #list / ZONE_MAX or 1
		local at = 1
		while at <= #list do
			local p = list[floor(at)]
			P[#P + 1] = { X = p.x / 100 * w, Y = p.y / 100 * h, x = p.x, y = p.y, src = p.src, id = p.id,
				rate = p.rate, wt = (p.wt or 1) * step }
			at = at + step
		end
		local eps = min(EPS_MAX, max(EPS_MIN, UsualGap(P) * EPS_TIMES))
		-- (spawns within eps of each other, and so on along: one area)
		local grid, parent = {}, {}
		local function Find(i)
			while parent[i] ~= i do parent[i] = parent[parent[i]] i = parent[i] end
			return i
		end
		local e2 = eps * eps
		for i, p in ipairs(P) do
			parent[i] = i
			local cx, cy = floor(p.X / eps), floor(p.Y / eps)
			for dx = -1, 1 do
				for dy = -1, 1 do
					local g = grid[Key(cx + dx, cy + dy)]
					if g then
						for _, j in ipairs(g) do
							local q = P[j]
							if (q.X - p.X) ^ 2 + (q.Y - p.Y) ^ 2 <= e2 then
								local a, b = Find(i), Find(j)
								if a ~= b then parent[a] = b end
							end
						end
					end
				end
			end
			local k = Key(cx, cy)
			local g = grid[k]
			if not g then g = {} grid[k] = g end
			g[#g + 1] = i
		end
		local groups = {}
		for i, p in ipairs(P) do
			local r = Find(i)
			local c = groups[r]
			if not c then
				c = { ui = ui, pts = {}, eps = eps, w = w, h = h }
				groups[r] = c
				out[#out + 1] = c
			end
			c.pts[#c.pts + 1] = p
		end
	end
	-- (each area's weight: its spawns, each as often as it drops the item; its score: that over
	-- the square root of the ground it covers (squares with spawns in), so a packed camp beats a
	-- sprawl of a few more, but a whole camp still beats one lone mob; and its middle)
	for _, c in ipairs(out) do
		local sx, sy, wt, cells, nCells = 0, 0, 0, {}, 0
		for _, p in ipairs(c.pts) do
			sx, sy, wt = sx + p.x, sy + p.y, wt + p.wt
			local k = Key(floor(p.X / SPREAD_CELL), floor(p.Y / SPREAD_CELL))
			if not cells[k] then cells[k] = true nCells = nCells + 1 end
		end
		c.x, c.y, c.wt = sx / #c.pts, sy / #c.pts, wt
		c.cells, c.score = nCells, wt / sqrt(nCells)
	end
	return out
end

--- the area to show: of the good ones (BIG_ENOUGH of the best score), the nearest you; the best
--- when you're on another continent (or it's not known where you are)
function Areas.Pick(clusters)
	local biggest = 0
	for _, c in ipairs(clusters) do biggest = max(biggest, c.score) end
	-- (where you are first: your zone's best area, when it's a fair one)
	local here, guard = ns.PlayerMap and ns.PlayerMap(), 0
	while here and guard < 6 do
		local mine
		for _, c in ipairs(clusters) do
			if c.ui == here and #c.pts >= HERE_MIN and c.score >= biggest * HERE_SHARE
				and (not mine or c.score > mine.score) then
				mine = c
			end
		end
		if mine then return mine end
		local info = C_Map and C_Map.GetMapInfo(here)
		here, guard = info and info.parentMapID, guard + 1
	end
	local px, py, pinst
	if HBD and HBD.GetPlayerWorldPosition then px, py, pinst = HBD:GetPlayerWorldPosition() end
	local best, bestD, bestN
	for _, c in ipairs(clusters) do
		local n = c.score
		if n >= biggest * BIG_ENOUGH then
			local d = huge
			if px and HBD.GetWorldCoordinatesFromZone then
				local wx, wy, inst = HBD:GetWorldCoordinatesFromZone(c.x / 100, c.y / 100, c.ui)
				if wx and inst == pinst then d = sqrt((wx - px) ^ 2 + (wy - py) ^ 2) end
			end
			if not best or d < bestD or (d == bestD and n > bestN) then best, bestD, bestN = c, d, n end
		end
	end
	return best
end

local NODES_MIN = 8                -- veins or plants a zone needs to be picked (unless none has that many)
local ZONE_SHARE = 0.15            -- (or this share of the zone with the most, when that's more)

--- the zone to show a herb's plants (or ore's veins) in: the one you're in when it has a fair
--- number of them, else the nearest that does (the one with the most, on another continent).
--- Returns its map, and how many zones have any
function Areas.PickZone(points)
	local count, sx, sy, zones = {}, {}, {}, {}
	for _, p in ipairs(points) do
		local ui = p.ui
		if not count[ui] then count[ui], sx[ui], sy[ui] = 0, 0, 0 zones[#zones + 1] = ui end
		count[ui], sx[ui], sy[ui] = count[ui] + 1, sx[ui] + p.x, sy[ui] + p.y
	end
	local most = 0
	for _, ui in ipairs(zones) do most = max(most, count[ui]) end
	local need = min(most, max(NODES_MIN, most * ZONE_SHARE))
	-- (where you are: your map, or one it's inside, a cave's zone)
	local here, guard = ns.PlayerMap and ns.PlayerMap(), 0
	while here and guard < 6 do
		if count[here] and count[here] >= need then return here, #zones end
		local info = C_Map and C_Map.GetMapInfo(here)
		here, guard = info and info.parentMapID, guard + 1
	end
	local px, py, pinst
	if HBD and HBD.GetPlayerWorldPosition then px, py, pinst = HBD:GetPlayerWorldPosition() end
	local best, bestD, bestN
	for _, ui in ipairs(zones) do
		local n = count[ui]
		if n >= need then
			local d = huge
			if px and HBD.GetWorldCoordinatesFromZone then
				local wx, wy, inst = HBD:GetWorldCoordinatesFromZone(sx[ui] / n / 100, sy[ui] / n / 100, ui)
				if wx and inst == pinst then d = sqrt((wx - px) ^ 2 + (wy - py) ^ 2) end
			end
			if not best or d < bestD or (d == bestD and n > bestN) then best, bestD, bestN = ui, d, n end
		end
	end
	return best, #zones
end

--- the spawn nearest an area's middle (where its marker goes)
function Areas.Middle(c)
	local best, bd
	for _, p in ipairs(c.pts) do
		local d = (p.x - c.x) ^ 2 + (p.y - c.y) ^ 2
		if not bd or d < bd then best, bd = p, d end
	end
	return best
end

--------------------------------------------------------------------------------
-- The outline: a soft blob around the spawns (each one's circle, run together where they
-- meet), traced on a grid (marching squares), its corners thinned, cut into triangles to fill
--------------------------------------------------------------------------------

-- the corners kept of a run of them, Douglas-Peucker: none further than tol off the line kept
local function Thin(pts, tol)
	local n = #pts
	if n < 4 then return pts end
	-- (a loop: split at its first corner and the one furthest from it)
	local far, fd = 1, -1
	for i = 2, n do
		local d = (pts[i][1] - pts[1][1]) ^ 2 + (pts[i][2] - pts[1][2]) ^ 2
		if d > fd then far, fd = i, d end
	end
	local keep = { [1] = true, [far] = true }
	local t2 = tol * tol
	local stack = { { 1, far }, { far, n + 1 } }
	local function At(i) return pts[(i - 1) % n + 1] end
	while #stack > 0 do
		local s = table.remove(stack)
		local a, b = s[1], s[2]
		if b - a > 1 then
			local A, B = At(a), At(b)
			local dx, dy = B[1] - A[1], B[2] - A[2]
			local len2 = dx * dx + dy * dy
			local worst, wd = nil, t2
			for i = a + 1, b - 1 do
				local P = At(i)
				local d
				if len2 == 0 then d = (P[1] - A[1]) ^ 2 + (P[2] - A[2]) ^ 2
				else d = (dx * (A[2] - P[2]) - dy * (A[1] - P[1])) ^ 2 / len2 end
				if d > wd then worst, wd = i, d end
			end
			if worst then
				keep[(worst - 1) % n + 1] = true
				stack[#stack + 1] = { a, worst }
				stack[#stack + 1] = { worst, b }
			end
		end
	end
	local out = {}
	for i = 1, n do if keep[i] then out[#out + 1] = pts[i] end end
	return out
end

local function SignedArea(poly)
	local a, n = 0, #poly
	for i = 1, n do
		local p, q = poly[i], poly[i % n + 1]
		a = a + p[1] * q[2] - q[1] * p[2]
	end
	return a / 2
end

local function InLoop(x, y, poly)
	local inside, n = false, #poly
	local j = n
	for i = 1, n do
		local a, b = poly[i], poly[j]
		if (a[2] > y) ~= (b[2] > y) and x < (b[1] - a[1]) * (y - a[2]) / (b[2] - a[2]) + a[1] then
			inside = not inside
		end
		j = i
	end
	return inside
end

-- a loop of corners cut into triangles (ear clipping): each { a, b, c } as the corners' numbers
local function Triangles(poly, base, out)
	local n = #poly
	if n < 3 then return end
	local sgn = SignedArea(poly) > 0 and 1 or -1
	local function Cross(a, b, c) return (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1]) end
	local idx = {}
	for i = 1, n do idx[i] = i end
	local i, since = 1, 0
	while #idx > 3 do
		local m = #idx
		local pa, pb, pc = (i - 2) % m + 1, (i - 1) % m + 1, i % m + 1
		local ia, ib, ic = idx[pa], idx[pb], idx[pc]
		local a, b, c = poly[ia], poly[ib], poly[ic]
		local ear = sgn * Cross(a, b, c) > 0
		if ear then
			for k = 1, m do
				local v = idx[k]
				if v ~= ia and v ~= ib and v ~= ic then
					local p = poly[v]
					if sgn * Cross(a, b, p) >= 0 and sgn * Cross(b, c, p) >= 0 and sgn * Cross(c, a, p) >= 0 then
						ear = false
						break
					end
				end
			end
		end
		-- (none found all the way round: a corner on a straight line, or a knot; clipped anyway)
		if ear or since > m then
			if sgn * Cross(a, b, c) ~= 0 then out[#out + 1] = { base + ia, base + ib, base + ic } end
			table.remove(idx, pb)
			since = 0
			if pb <= #idx then i = pb else i = 1 end
		else
			i = i % m + 1
			since = since + 1
		end
	end
	out[#out + 1] = { base + idx[1], base + idx[2], base + idx[3] }
end

--- an area's outline, to draw: { ui, verts = { x1, y1, x2, y2, ... } (0..100), loops =
--- { { first, count }, ... }, tris = { { i, j, k }, ... } (verts' numbers) }
function Areas.Outline(c)
	local w, h = c.w, c.h
	local r = max(c.eps * RADIUS, RADIUS_MIN)
	local reach = r * 1.5
	local minX, minY, maxX, maxY = huge, huge, -huge, -huge
	for _, p in ipairs(c.pts) do
		minX, minY = min(minX, p.X), min(minY, p.Y)
		maxX, maxY = max(maxX, p.X), max(maxY, p.Y)
	end
	minX, minY, maxX, maxY = minX - reach - r, minY - reach - r, maxX + reach + r, maxY + reach + r
	local cs = max(r / 2.5, max(maxX - minX, maxY - minY) / GRID_MAX)
	local W, H = ceil((maxX - minX) / cs), ceil((maxY - minY) / cs)
	local cols = W + 1
	-- (each grid corner: 1 on a spawn, falling to 0 at r from it, below past it)
	local f = {}
	for k = 0, cols * (H + 1) - 1 do f[k] = -1 end
	local r2 = r * r
	for _, p in ipairs(c.pts) do
		local i0, i1 = max(0, floor((p.X - reach - minX) / cs)), min(W, ceil((p.X + reach - minX) / cs))
		local j0, j1 = max(0, floor((p.Y - reach - minY) / cs)), min(H, ceil((p.Y + reach - minY) / cs))
		for j = j0, j1 do
			local dy2 = (minY + j * cs - p.Y) ^ 2
			for i = i0, i1 do
				local v = 1 - ((minX + i * cs - p.X) ^ 2 + dy2) / r2
				local k = j * cols + i
				if v > f[k] then f[k] = v end
			end
		end
	end
	-- where the outline crosses each grid edge (h: from corner i,j right; v: from i,j down)
	local pos, links = {}, {}
	local function HE(i, j) return (j * cols + i) * 2 end
	local function VE(i, j) return (j * cols + i) * 2 + 1 end
	local function Cross(id, i, j, horiz)
		if pos[id] then return id end
		local a = f[j * cols + i]
		local b = horiz and f[j * cols + i + 1] or f[(j + 1) * cols + i]
		local t = a / (a - b)
		local x, y = minX + i * cs, minY + j * cs
		if horiz then x = x + t * cs else y = y + t * cs end
		pos[id] = { x, y }
		return id
	end
	local function Link(a, b)
		local la, lb = links[a], links[b]
		if not la then la = {} links[a] = la end
		if not lb then lb = {} links[b] = lb end
		la[#la + 1], lb[#lb + 1] = b, a
	end
	for j = 0, H - 1 do
		for i = 0, W - 1 do
			local va, vb = f[j * cols + i], f[j * cols + i + 1]
			local vc, vd = f[(j + 1) * cols + i + 1], f[(j + 1) * cols + i]
			local A, B, C, D = va > 0, vb > 0, vc > 0, vd > 0
			if not (A == B and B == C and C == D) then
				local top = A ~= B and Cross(HE(i, j), i, j, true)
				local right = B ~= C and Cross(VE(i + 1, j), i + 1, j, false)
				local bottom = D ~= C and Cross(HE(i, j + 1), i, j + 1, true)
				local left = A ~= D and Cross(VE(i, j), i, j, false)
				if top and right and bottom and left then
					-- (a saddle: which two corners are cut off, by the middle)
					local mid = (va + vb + vc + vd) / 4 > 0
					if mid == A then
						Link(top, right) Link(bottom, left)       -- (B and D cut off)
					else
						Link(top, left) Link(right, bottom)       -- (A and C cut off)
					end
				else
					local e = {}
					for _, x in ipairs({ top, right, bottom, left }) do if x then e[#e + 1] = x end end
					if #e == 2 then Link(e[1], e[2]) end
				end
			end
		end
	end
	-- the loops
	local loops, seen = {}, {}
	for id in pairs(pos) do
		if not seen[id] and links[id] then
			local loop, prev, at = {}, nil, id
			while at and not seen[at] do
				seen[at] = true
				loop[#loop + 1] = pos[at]
				local l = links[at]
				local nxt = (l[1] ~= prev) and l[1] or l[2]
				if seen[nxt] then nxt = (l[2] ~= prev and not seen[l[2]]) and l[2] or nil end
				prev, at = at, nxt
			end
			if #loop >= 3 then loops[#loops + 1] = loop end
		end
	end
	-- (thinned, the holes left out: filled), biggest first
	local tol = cs * 0.35
	local outer = {}
	for _, loop in ipairs(loops) do loop.area = abs(SignedArea(loop)) end
	table.sort(loops, function(a, b) return a.area > b.area end)
	for _, loop in ipairs(loops) do
		local hole = false
		for _, o in ipairs(outer) do
			if InLoop(loop[1][1], loop[1][2], o.raw) then hole = true break end
		end
		if not hole then outer[#outer + 1] = { raw = loop } end
	end
	local total = 0
	for _, o in ipairs(outer) do total = total + #o.raw end
	repeat
		local n = 0
		for _, o in ipairs(outer) do
			o.pts = Thin(o.raw, tol)
			n = n + #o.pts
		end
		tol = tol * 1.5
	until n <= VERTS_MAX or tol > cs * 20
	local out = { ui = c.ui, verts = {}, loops = {}, tris = {} }
	for _, o in ipairs(outer) do
		if #o.pts >= 3 then
			local base = #out.verts / 2
			out.loops[#out.loops + 1] = { base + 1, #o.pts }
			for _, p in ipairs(o.pts) do
				out.verts[#out.verts + 1] = p[1] / w * 100
				out.verts[#out.verts + 1] = p[2] / h * 100
			end
			Triangles(o.pts, base, out.tris)
		end
	end
	return out
end

return Areas
