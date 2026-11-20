extends RefCounted
## The outside of the tower in the Detailed look (#306, G Lit): brick facade edges and a roof with a
## parapet, railings, water tanks, vents, antennas and beacons on every exposed run of floor units; a street
## at the ground with a sidewalk, a road, trees, streetlights, parked cars and pedestrians; and two layers of
## city skyline behind the tower that grow taller and denser with the star rating.
## Everything is drawn with draw_rect through DetailPrims in half-pixel steps, so the same code serves any
## canvas item; the facade and roof paint on the static layer, the street and skyline on their own layers
## (exterior_layer.gd). Night turns windows and lamps on as light-emitting rectangles, which the night glow
## pass can add to. Pure drawing: nothing here reads the simulation, and the placement is hashed, never random.

const Pen := preload("res://scripts/view/detail_prims.gd")
const SkyLook := preload("res://scripts/view/sky_look.gd")
const VC := preload("res://scripts/view/view_consts.gd")

const NIGHT_BELOW := 400  ## Daylight under this counts as night: lamps and lit windows come on.
const WARM := Color("ffcf8a")
const BRICK_A := Color("8a7d86")
const BRICK_B := Color("6a5f6c")
const MORTAR := Color("52485a")
const STONE := Color("6a6070")
const RAIL := Color("54505c")
const STREET_FROM := -1800  ## The street and skyline span from here to the tower's width plus the same.
const SLOT := 112  ## World pixels per street slot: each holds one thing.
const CAR_COLORS: Array = [Color("c8453c"), Color("3f7fb0"), Color("e0a83a"), Color("6aa06a"), Color("9a55b0"), Color("c8c2b8")]
## [skin, hair, shirt, trousers]
const LOOKS: Array = [
	[Color("f0c59a"), Color("3a2418"), Color("c8453c"), Color("3d4660")],
	[Color("d9a074"), Color("1c1414"), Color("3f7fb0"), Color("4a3a52")],
	[Color("8a5a3c"), Color("141010"), Color("e0a83a"), Color("2f3a4a")],
	[Color("f4d2b0"), Color("c98a3c"), Color("6aa06a"), Color("5a4a6a")],
]


static func is_night(dl: int) -> bool:
	return dl < NIGHT_BELOW


## How far an unlit thing is pushed toward night blue: none by day, about half by full night.
static func darkness(dl: int) -> float:
	return 0.6 * float(SkyLook.FULL - clampi(dl, 0, SkyLook.FULL)) / float(SkyLook.FULL)


# ---------------------------------------------------------------- facade and roof

## Brick edges down both ends of every run of floor units, and a roof on every stretch with nothing above.
static func shell(canvas: Object, rects: Array[Rect2i], dl: int) -> void:
	var dark := darkness(dl)
	var night := is_night(dl)
	for rect: Rect2i in rects:
		_edges(Pen.new(canvas, Vector2(rect.position), dark, night), rect.size.x * 2, rect.size.y * 2)
	for run: Array in roof_runs(rects):
		var at := Vector2(int(run[0]), int(run[1]))
		_roof(Pen.new(canvas, at, dark, night), int(run[2]) * 2, int(run[0]) / VC.CELL_W, int(run[1]) / VC.CELL_H, int(run[3]))


## The exposed tops: one [x, y, width, rank] (world pixels) per stretch of a floor run with no floor unit
## above it. Rank is 0 on the highest row of the tower and counts down one per row below; it carries the antenna.
static func roof_runs(rects: Array[Rect2i]) -> Array[Array]:
	var built: Dictionary = {}
	for rect: Rect2i in rects:
		var row := rect.position.y / VC.CELL_H
		for c: int in rect.size.x / VC.CELL_W:
			built[row * 10000 + rect.position.x / VC.CELL_W + c] = true
	var out: Array[Array] = []
	var top_row := 1000000
	for rect: Rect2i in rects:
		var row := rect.position.y / VC.CELL_H
		var col0 := rect.position.x / VC.CELL_W
		var columns := rect.size.x / VC.CELL_W
		var start := -1
		for c: int in columns + 1:
			var open := c < columns and not built.has((row - 1) * 10000 + col0 + c)
			if open and start < 0:
				start = c
			elif not open and start >= 0:
				out.append([(col0 + start) * VC.CELL_W, rect.position.y, (c - start) * VC.CELL_W, row])
				top_row = mini(top_row, row)
				start = -1
	for run: Array in out:
		run[3] = int(run[3]) - top_row
	return out


static func _edges(pen: Pen, w: int, h: int) -> void:
	for side: int in 2:
		var x := 0 if side == 0 else w - 6
		pen.gradv(x, 0, 6, h, BRICK_A, BRICK_B)
		for r: int in h / 8:
			pen.R(x, r * 8, 6, 1, MORTAR)
			pen.R(x + (r % 2) * 3 + 1, r * 8, 1, 8, MORTAR)
		pen.R(x + (5 if side == 0 else 0), 0, 1, h, Color("4a4050"))
		pen.R(x + (0 if side == 0 else 5), 0, 1, h, Color("b4a8b0"))


## A roof over `w` half-pixels: cornice, railing, corner lights and, by a hash of where it is, a water tank,
## a rooftop unit or a vent stack; the highest stretches also carry an antenna with a beacon.
static func _roof(pen: Pen, w: int, col: int, row: int, rank: int) -> void:
	var seed_a := Pen.hn(col, row + 3)
	pen.item(-2, -5, w + 4, 5, STONE, 1)
	pen.R(-1, -4, w + 2, 1, STONE.darkened(0.2))
	for x: int in range(2, w - 1, 12):
		pen.R(x, -11, 1, 6, RAIL)
	pen.R(0, -11, w, 1, RAIL.lightened(0.25))
	for corner: int in 2:
		var lx := 1 if corner == 0 else w - 3
		pen.R(lx, -8, 2, 2, Color("e8e2d0"))
		if pen.night:
			pen.GR(lx, -8, 2, 2, WARM)
			pen.pool(lx + 1, -6, 9, 4, WARM, 0.5)
	if w >= 96 and seed_a < 0.34:
		var x := 14 + int(Pen.hn(col, row + 9) * float(w - 62))
		pen.R(x + 3, -13, 2, 8, RAIL)
		pen.R(x + 23, -13, 2, 8, RAIL)
		pen.item(x, -33, 28, 20, Color("8a5a3c"), 3)
		for b: int in 3:
			pen.R(x, -30 + b * 6, 28, 1, Color("5a3a28"))
		pen.item(x - 2, -37, 32, 5, Color("6a4430"), 2)
	elif w >= 64 and seed_a < 0.66:
		var x := 8 + int(Pen.hn(col, row + 9) * float(w - 50))
		pen.item(x, -19, 34, 14, Color("7a8090"), 2)
		for f: int in 5:
			pen.R(x + 4 + f * 6, -15, 3, 8, Color("4a4e5c"))
	elif w >= 32:
		var x := 6 + int(Pen.hn(col, row + 9) * float(w - 20))
		pen.item(x, -17, 8, 12, Color("8a7d86"), 1)
		pen.item(x - 1, -20, 10, 3, Color("6a6070"), 1)
	if rank <= 1 and w >= 24:  # the tallest roofs carry the antenna
		var ax := w / 2 + int(Pen.hn(col, row + 21) * 8.0) - 4
		var tip := -50 - 6 * (1 - rank)
		pen.R(ax, tip, 2, -tip - 5, RAIL)
		pen.ln(Vector2(ax + 1, tip + 12), Vector2(ax - 12, -5), RAIL, 1.0)
		pen.ln(Vector2(ax + 1, tip + 12), Vector2(ax + 14, -5), RAIL, 1.0)
		pen.ln(Vector2(ax + 1, tip + 24), Vector2(ax - 8, -5), RAIL, 1.0)
		pen.ln(Vector2(ax + 1, tip + 24), Vector2(ax + 10, -5), RAIL, 1.0)
		pen.R(ax - 1, tip - 4, 4, 4, Color("c83a30"))
		if pen.night:
			pen.GR(ax - 1, tip - 4, 4, 4, Color("ff3a2a"))
			pen.pool(ax + 1, tip - 2, 9, 9, Color("ff3a2a"), 0.7)


# ---------------------------------------------------------------- street

## The street along the ground, centred on the tower: a sidewalk and a road in the strip under the ground
## line, and trees, streetlights, parked cars and pedestrians in front of floor 1's unbuilt stretches.
## `built` holds the columns of floor 1 that have floor units; nothing is drawn standing over those.
static func street(canvas: Object, dl: int, world_w: int, ground_y: int, built: Dictionary) -> void:
	var pen := Pen.new(canvas, Vector2(0, ground_y), darkness(dl), is_night(dl))
	var x0 := STREET_FROM
	var span := world_w - 2 * STREET_FROM
	pen.R(x0 * 2, 0, span * 2, 12, Color("b8b2ac"))
	pen.R(x0 * 2, 0, span * 2, 1, Color("d8d2c8"))
	pen.R(x0 * 2, 10, span * 2, 2, Color("8f8a8c"))
	for j: int in range(0, span, 24):
		pen.R((x0 + j) * 2, 1, 1, 9, Color("9a9498"))
	pen.R(x0 * 2, 12, span * 2, 28, Color("403c4c"))
	pen.R(x0 * 2, 39, span * 2, 1, Color("2e2b38"))
	for j: int in range(0, span, 96):
		pen.R((x0 + j) * 2, 26, 24, 2, Color("e2c868"))
	for slot: int in span / SLOT:
		var sx := x0 + slot * SLOT
		var x := sx + 24 + int(Pen.hn(slot, 42) * 48.0)
		var kind := int(Pen.hn(slot, 41) * 6.0)
		if kind == 2 or kind == 5:
			_car(pen, x * 2, slot)
		elif not _blocked(built, x - 16, x + 24):
			match kind:
				0:
					_tree(pen, x * 2, slot)
				1:
					_streetlight(pen, x * 2)
				_:
					_walkers(pen, x * 2, slot)


static func _blocked(built: Dictionary, from_x: int, to_x: int) -> bool:
	for c: int in range(floori(float(from_x) / VC.CELL_W), floori(float(to_x) / VC.CELL_W) + 1):
		if built.has(c):
			return true
	return false


static func _tree(pen: Pen, x: int, slot: int) -> void:
	var tall := 4 * int(Pen.hn(slot, 43) * 3.0)
	pen.shadow(x, 9, 14, 0.5)
	pen.item(x - 2, -18 - tall, 4, 26 + tall, Color("6a4a32"), 1)
	var leaf := Color("4a8a4e") if Pen.hn(slot, 44) < 0.6 else Color("5a9a58")
	pen.ell(x, -34 - tall, 15, 12, leaf.darkened(0.2))
	pen.ell(x - 9, -26 - tall, 10, 8, leaf)
	pen.ell(x + 10, -27 - tall, 10, 8, leaf)
	pen.ell(x - 2, -38 - tall, 8, 5, leaf.lightened(0.25))
	pen.R(x - 12, -26 - tall, 3, 2, leaf.lightened(0.35))


static func _streetlight(pen: Pen, x: int) -> void:
	pen.item(x - 1, -46, 3, 54, Color("46404e"), 1)
	pen.item(x - 6, -50, 12, 5, Color("5a5260"), 2)
	if pen.night:
		pen.GR(x - 5, -46, 10, 2, WARM)
		pen.pool(x, 6, 30, 5, WARM, 0.5)
		pen.GW(x - 18, -44, 36, 50, WARM)
	else:
		pen.R(x - 5, -46, 10, 2, Color("e8e2d0"))


static func _car(pen: Pen, x: int, slot: int) -> void:
	var body: Color = CAR_COLORS[slot % CAR_COLORS.size()]
	var cy := 36
	pen.shadow(x + 20, cy + 3, 22, 0.6)
	pen.item(x, cy - 8, 40, 9, body, 3)
	pen.item(x + 9, cy - 15, 20, 8, body.darkened(0.12), 3)
	pen.R(x + 11, cy - 13, 7, 5, Color("a8d4e8"))
	pen.R(x + 20, cy - 13, 7, 5, Color("a8d4e8"))
	for wx: int in [x + 8, x + 31]:
		pen.ell(wx, cy + 1, 4, 4, Color("1e1a22"))
		pen.ell(wx, cy + 1, 1.6, 1.6, Color("b8b4c0"))
	if pen.night:
		pen.GR(x + 38, cy - 6, 3, 3, Color("fff2b0"))
		pen.GR(x - 1, cy - 6, 2, 3, Color("ff4030"))
		pen.pool(x + 52, cy - 3, 20, 4, WARM, 0.45)


static func _walkers(pen: Pen, x: int, slot: int) -> void:
	for n: int in 1 + (slot % 2):
		var look: Array = LOOKS[(slot + n) % LOOKS.size()]
		var px := x + n * 14
		var feet := 8
		pen.shadow(px, feet + 1, 5, 0.45)
		pen.R(px - 3, feet - 10, 2, 10, look[3])
		pen.R(px + 1, feet - 10, 2, 10, look[3])
		pen.item(px - 3, feet - 22, 6, 12, look[2], 1)
		pen.ell(px, feet - 26, 3.5, 3.5, look[0])
		pen.R(px - 3, feet - 30, 6, 2, look[1])


# ---------------------------------------------------------------- skyline

## One layer of the city, from `STREET_FROM` across, standing on the ground line. depth 0 is the far haze,
## depth 1 the nearer, darker row with windows. Each star adds height and fills the gaps between buildings;
## at night the windows light up. Hashed, so it never shimmers.
static func skyline(canvas: Object, p: Dictionary, dl: int, raining: bool, stars: int, depth: int, world_w: int, ground_y: int) -> void:
	var colors := SkyLook.colors(p, dl, raining)
	var horizon: Color = colors["horizon"]
	var top: Color = colors["top"]
	var body := horizon.lerp(top, 0.3 + 0.25 * float(depth))
	var pen := Pen.new(canvas, Vector2(0, ground_y), 0.0, is_night(dl))
	var level := clampi(stars, 1, 5)
	var fill := 0.45 + 0.11 * float(level)
	var x := STREET_FROM + depth * 7
	var i := depth * 1000
	while x < world_w - STREET_FROM:
		var bw := 10 - depth * 2 + int(Pen.hn(i, 11) * 14.0)
		var present := Pen.hn(i, 7) <= fill
		if present:
			var reach := (28.0 + 22.0 * float(level)) * (1.0 - 0.3 * float(depth))
			var bh := int(14.0 + Pen.hn(i, 12) * reach)
			_block(pen, x * 2, bw * 2, bh * 2, body.darkened(0.06 * float(i % 2)), i, depth)
		x += bw + (0 if present else bw / 2)
		i += 1


static func _block(pen: Pen, x: int, w: int, h: int, body: Color, i: int, depth: int) -> void:
	pen.GR(x, -h, w, h, body)
	pen.GR(x, -h, w, 1, body.lightened(0.22))
	pen.GR(x + w - 1, -h + 1, 1, h - 1, body.darkened(0.15))
	if h > 90 and Pen.hn(i, 14) < 0.5:  # a mast on the tall ones
		pen.GR(x + w / 2, -h - 12, 2, 12, body.darkened(0.25))
		if pen.night:
			pen.GR(x + w / 2 - 1, -h - 14, 4, 3, Color("ff3a2a"))
	elif Pen.hn(i, 15) < 0.4:  # a roof box
		pen.GR(x + 3, -h - 5, w / 3, 5, body.darkened(0.12))
	if depth == 0:
		return
	for row: int in range(6, h - 6, 8):
		for col: int in range(3, w - 4, 6):
			var lit := Pen.hn(i * 31 + row * 7 + col, 13)
			if pen.night and lit > 0.55:
				pen.GR(x + col, -h + row, 3, 4, Color("ffd27a"))
			elif not pen.night:
				pen.GR(x + col, -h + row, 3, 4, body.darkened(0.1))
