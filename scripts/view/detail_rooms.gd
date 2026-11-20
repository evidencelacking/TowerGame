extends RefCounted
## Detailed room drawing (#302) for the batch 1 kinds: lobby, office (every variant and joined suites),
## condo, hotel rooms and housekeeping, in the G Lit look, composed from the mock-up's own pieces
## (detail_scenes.gd on detail_prims.gd) at double density (16 px per column, 64 per floor).
## A room is drawn in mock-up pixels inside the same world rect Classic fills. Its furniture is placed from the
## recipe's activity spots (room_recipes.gd), so people, who stand and sit at those spots, are at the desks and
## in the beds. A lit room has its lamps and screens on; an empty one is pushed toward night blue. Real lighting
## (a darkened world with glows) is not here (#305).

const Prims := preload("res://scripts/view/detail_prims.gd")
const Scenes := preload("res://scripts/view/detail_scenes.gd")
const Shops := preload("res://scripts/view/detail_shops.gd")
const Palette := preload("res://scripts/view/palette.gd")
const RoomRecipes := preload("res://scripts/view/room_recipes.gd")
const SkyLook := preload("res://scripts/view/sky_look.gd")
const VC := preload("res://scripts/view/view_consts.gd")

const KINDS: Array[String] = ["lobby", "office", "condo", "hotel_single", "hotel_twin", "hotel_suite", "housekeeping"]
const SUB := 2  ## Mock-up pixels per world pixel.
const FLOOR_H := Scenes.FLOOR
const BENCH_GAP := 64.0  ## Seats closer than this (mock-up pixels) get a narrow workstation each.
const CURTAINS: Array[String] = ["b86a5a", "5a7aa0", "5a8a6a"]


static func handles(kind: String) -> bool:
	return KINDS.has(kind) or Shops.handles(kind)


## Paints a room or suite of `kind` over rect (world pixels, at least one floor tall; a lobby taller than a
## floor gets columns, tall windows and a mezzanine rail above its bottom floor). hue is the room colour (a
## state tint shows through when it is not the kind's own), lit the in-use look, id picks the variant.
static func draw(canvas: Object, kind: String, rect: Rect2i, hue: Color, lit: bool, upper: bool = false, id: int = 0, suite: bool = false) -> void:
	var p := Palette.get_palette()
	var night := SkyLook.daylight < SkyLook.FULL / 2
	var dim := SkyLook.dim_at(p["dim"], SkyLook.daylight)
	var pen := Prims.new(canvas, Vector2(rect.position), 0.0 if lit else clampf(dim, 0.0, 0.85), night and lit)
	var w := rect.size.x * SUB
	var h := maxi(rect.size.y, VC.CELL_H) * SUB
	var y0 := h - FLOOR_H  # mock-up row where the bottom floor starts
	pen.limit = Rect2i(0, 0, w, h - Scenes.SLAB_H)  # nothing spills into the neighbour or over the slab
	var variant: int = RoomRecipes.SUITE if suite else RoomRecipes.variant_for(kind, id)
	var seats := seat_centres(kind, rect.size.x, upper, variant)
	var pal := _palette(kind, hue)
	match kind:
		"lobby":
			if y0 > 0:
				Scenes.mezzanine(pen, w, y0, night)
			Scenes.lobby(pen, w, y0, seats)
		"office":
			_office(pen, w, y0, seats, lit, night, id, pal)
		"condo":
			_condo(pen, w, y0, seats, lit, night, id, pal)
		"hotel_single", "hotel_twin", "hotel_suite":
			_hotel(pen, kind, w, y0, seats, lit, night, id, pal)
		"housekeeping":
			_housekeeping(pen, w, y0, seats, lit, night, id, pal)
		_:
			Shops.draw(pen, kind, w, y0, seats, lit, night, id, variant, upper, pal)


## Where people stand or sit in a kind's recipe, as the centre of the figure in mock-up pixels from the room's
## left wall, sorted left to right. Furniture is placed from these.
static func seat_centres(kind: String, width_px: int, upper: bool, variant: int) -> Array:
	var out: Array = []
	for spot: Vector2i in RoomRecipes.layout(kind, width_px, upper, variant)["spots"]:
		out.append(float(spot.x * SUB + VC.FIGURE_W))
	out.sort()
	return out


static func _palette_key(kind: String) -> String:
	if kind.begins_with("hotel"):
		return "hotel"
	return "service" if kind == "housekeeping" else kind  # batch 2 kinds have a palette of their own


## The kind's shell colours, shifted toward the room's hue when a state tint (dirty, idle) replaces it.
static func _palette(kind: String, hue: Color) -> Array:
	var base: Array = Scenes.PALETTES[_palette_key(kind)]
	if hue.is_equal_approx(Palette.hue(RoomRecipes.hue_key(kind))):
		return base
	var out: Array = []
	for c: String in base:
		out.append(Color(c).lerp(hue, 0.35).to_html(false))
	return out


static func _overlaps(taken: Array, x0: float, x1: float) -> bool:
	for t: Vector2 in taken:
		if x0 < t.y and x1 > t.x:
			return true
	return false


static func _office(p: Object, w: int, y0: int, seats: Array, lit: bool, night: bool, id: int, pal: Array) -> void:
	var fy := float(y0 + 58)
	var yt := float(y0)
	Scenes.shell_room(p, 0, yt, w, 2, pal)
	var taken: Array = []
	var facing: Array = []  # per seat: 1 desk to the left, -1 to the right, 0 a bench workstation
	for i: int in seats.size():
		var c: float = seats[i]
		var near := 99999.0
		for j: int in seats.size():
			if j != i:
				near = minf(near, absf(float(seats[j]) - c))
		if near < BENCH_GAP:
			facing.append(0)
			taken.append(Vector2(c - 32.0, c + 8.0))
		elif c - 52.0 >= 4.0:
			facing.append(1)
			taken.append(Vector2(c - 52.0, c + 8.0))
		else:
			facing.append(-1)
			taken.append(Vector2(c - 8.0, c + 52.0))
	var curtain := Color(CURTAINS[id % CURTAINS.size()])
	var lx := 48.0
	while lx < w - 24.0:
		Scenes.ceiling_light(p, lx, yt, 36.0, lit, 64.0)
		lx += 96.0
	var wx := 78.0
	var k := 0
	while wx + 38.0 <= w - 8.0:
		Scenes.window(p, wx, yt + 12, 38, 22, Color("e8e2d4"), curtain, id + k + 3, night, (id + k) % 4 == 1)
		wx += 96.0
		k += 1
	var px := 14.0
	k = 0
	while px + 18.0 <= w - 4.0:
		if (id + k) % 3 != 2 or w < 100:
			Scenes.poster(p, px, yt + 14, id + k)
		px += 96.0
		k += 1
	var fx := w - 28.0
	if fx > 40.0 and not _overlaps(taken, fx - 2.0, fx + 26.0):
		Scenes.filing(p, fx, fy)
		taken.append(Vector2(fx - 2.0, fx + 26.0))
	var plants := maxi(1, w / 150)
	var at := 10.0
	var pots: Array = [Color("7a5a8a"), Color("a8683c"), Color("5a7aa0")]
	while plants > 0 and at < w - 12.0:
		if not _overlaps(taken, at - 8.0, at + 8.0):
			Scenes.plant(p, at, fy, 20.0, pots[(id + plants) % pots.size()])
			taken.append(Vector2(at - 8.0, at + 8.0))
			plants -= 1
		at += 18.0
	for i: int in seats.size():
		var c: float = seats[i]
		match int(facing[i]):
			0:
				Scenes.bench_desk(p, c, fy, lit)
			1:
				Scenes.desk(p, c - 52.0, fy, lit)
			_:
				p.flip_around(c)
				Scenes.desk(p, c - 52.0, fy, lit)
				p.flip_off()


## A bedroom at the left, a table with a chair either side where two seats are, a wardrobe and a kitchen.
static func _condo(p: Object, w: int, y0: int, seats: Array, lit: bool, night: bool, id: int, pal: Array) -> void:
	var fy := float(y0 + 58)
	var yt := float(y0)
	Scenes.shell_room(p, 0, yt, w, 1, pal)
	var c0: float = seats[0] if seats.size() > 0 else 30.0
	var c1: float = seats[1] if seats.size() > 1 else c0 + 54.0
	var c2: float = seats[2] if seats.size() > 2 else c1 + 54.0
	var bx := maxf(c0 - 16.0, 6.0)
	var tx := (c1 + c2) * 0.5 - 22.0
	var curtain := Color(CURTAINS[(id + 1) % CURTAINS.size()])
	Scenes.window(p, tx + 4.0, yt + 10, 36, 26, Color("f0e8dc"), curtain, id + 7, night, id % 4 == 1)
	Scenes.picture(p, bx + 20.0, yt + 12, Color("c8606a"), Color("5a7fb4"))
	var quilts: Array = [Color("5a7fb4"), Color("8a6ab0"), Color("5a9a7a")]
	Scenes.bed(p, bx, fy, 56.0, quilts[id % quilts.size()], Color("f4eee2"))
	Scenes.table_set(p, tx, fy)
	var wx := c2 + 24.0
	if wx + 26.0 < w - 90.0:
		Scenes.wardrobe(p, wx, fy)
	var fxx := w - 34.0
	if fxx > c2 + 40.0:
		Scenes.fridge(p, fxx, fy)
		var kw := minf(48.0, fxx - 6.0 - (c2 + 40.0))
		if kw >= 24.0:
			Scenes.counter(p, fxx - 6.0 - kw, fy, kw, id)
	for lx: float in [w * 0.25, w * 0.75]:
		Scenes.ceiling_light(p, lx, yt, 30.0, lit, 70.0)
	if bx + 58.0 + 14.0 < c1 - 10.0:
		Scenes.nightstand(p, bx + 58.0, fy, lit)


## A hotel room: a bed with its nightstand and lamp, then by size a window, a sofa and an armchair.
static func _hotel(p: Object, kind: String, w: int, y0: int, seats: Array, lit: bool, night: bool, id: int, pal: Array) -> void:
	var fy := float(y0 + 58)
	var yt := float(y0)
	Scenes.shell_room(p, 0, yt, w, 1, pal)
	var c0: float = seats[0] if seats.size() > 0 else 24.0
	var bx := maxf(c0 - 16.0, 6.0)
	var length := clampf(float(w) * 0.45, 36.0, 52.0)
	var quilts: Array = [Color("5a7fb4"), Color("c8606a"), Color("5a9a7a"), Color("8a6ab0")]
	var curtain := Color(CURTAINS[id % CURTAINS.size()])
	Scenes.picture(p, bx + 16.0, yt + 12, Color("c8606a"), Color("5a7fb4"))
	var nx := bx + length + 2.0
	match kind:
		"hotel_twin":
			if nx + 16.0 + 24.0 <= w - 2.0:
				Scenes.window(p, nx + 16.0, yt + 10, 24, 22, Color("f0e8dc"), curtain, id + 5, night, id % 4 == 1)
		"hotel_suite":
			var sx := (float(seats[1]) + float(seats[seats.size() - 1])) * 0.5 - 28.0 if seats.size() > 1 else nx + 20.0
			sx = maxf(sx, nx + 18.0)
			Scenes.window(p, sx + 10.0, yt + 10, 36, 26, Color("f0e8dc"), curtain, id + 5, night, id % 4 == 1)
			Scenes.sofa(p, sx, fy, Color("5a8a6a"))
			Scenes.plant(p, w - 12.0, fy, 22.0, Color("7a5a8a"))
		_:
			pass
	Scenes.bed(p, bx, fy, length, quilts[id % quilts.size()], Color("f4eee2"))
	if nx + 14.0 <= w - 2.0:
		Scenes.nightstand(p, nx, fy, lit)
	Scenes.ceiling_light(p, w * 0.5 + 8.0, yt, mini(30, w - 20), lit, 64.0)


## A service room: linen shelves, carts, a washing machine and a clothes rail, with a light between.
static func _housekeeping(p: Object, w: int, y0: int, seats: Array, lit: bool, night: bool, id: int, pal: Array) -> void:
	var fy := float(y0 + 58)
	var yt := float(y0)
	Scenes.shell_room(p, 0, yt, w, 0, pal)
	var lx := 64.0
	while lx < w - 24.0:
		Scenes.ceiling_light(p, lx, yt, 36.0, lit, 64.0)
		lx += 128.0
	Scenes.linen_shelf(p, 6, fy, id)
	Scenes.cart(p, 40, fy)
	if w >= 200:
		Scenes.washer(p, 98, fy)
		Scenes.clothes_rail(p, 136, fy, 56)
		Scenes.cart(p, 200, fy)
	if w >= 240:
		Scenes.linen_shelf(p, w - 34.0, fy, id + 1)
