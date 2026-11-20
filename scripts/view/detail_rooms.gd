extends RefCounted
## Detailed room drawing (#302) for the batch 1 kinds: lobby, office (every variant and joined suites),
## condo, hotel rooms and housekeeping, in the G Lit look: a papered wall with a cornice, a dado and a tiled
## floor, windows with frames and sills, and 3-tone furniture.
## The furniture is the recipe's own shapes (room_recipes.gd) doubled onto a sub-pixel grid (16 px per
## column, 64 px per floor), so the activity spots, which are the same recipe's, line up with it: people
## stand at the desks and sleep in the beds exactly as in Classic. How a shape is drawn follows its role:
## a window is framed and glazed, a ceiling lamp is a fixture, a lamp shape a screen or a lit bulb, a big
## furniture shape a 3-tone object with an outline and a thin one a bar. Lit means someone is in the room;
## an empty room is pushed toward night blue. Lighting itself is not here (#305).

const Pen := preload("res://scripts/view/detail_pen.gd")
const Palette := preload("res://scripts/view/palette.gd")
const RoomRecipes := preload("res://scripts/view/room_recipes.gd")
const SkyLook := preload("res://scripts/view/sky_look.gd")
const VC := preload("res://scripts/view/view_consts.gd")

const KINDS: Array[String] = ["lobby", "office", "condo", "hotel_single", "hotel_twin", "hotel_suite", "housekeeping"]
const SUB := 2  ## Sub-pixels per native pixel.
const FLOOR_H := VC.CELL_H * SUB  ## 64: one floor in sub-pixels.
const SLAB_H := VC.SLAB_H * SUB
const CREAM := Color("f4f0e6")
const WOOD := Color("b0814f")
const BEZEL := Color("3a4052")
const SCREEN := Color("8ad0f0")
const CEILING := Color("d8d2c8")
const LEAF := Color("3f8a52")


static func handles(kind: String) -> bool:
	return KINDS.has(kind)


## Paints a room or suite of `kind` over rect (world pixels, at least one floor tall; the lobby is taller and
## gets the recipe on its bottom floor and plain wall above). hue is the room colour, lit the in-use look.
static func draw(canvas: Object, kind: String, rect: Rect2i, hue: Color, lit: bool, upper: bool = false, id: int = 0, suite: bool = false) -> void:
	var p := Palette.get_palette()
	var dim := SkyLook.dim_at(p["dim"], SkyLook.daylight)
	var pen := Pen.new(canvas, Vector2(rect.position), 0.0 if lit else clampf(dim, 0.0, 0.85))
	var w := rect.size.x * SUB
	var h := maxi(rect.size.y, VC.CELL_H) * SUB
	var top := h - FLOOR_H  # sub-pixel row where the bottom floor starts
	pen.limit = Rect2i(0, 0, w, h - SLAB_H)  # nothing spills into the neighbour or over the slab
	_shell(pen, w, h, top, hue)
	if kind == "lobby" and top > 0:
		_mezzanine(pen, w, top, h, p, lit)
	var variant: int = RoomRecipes.SUITE if suite else RoomRecipes.variant_for(kind, id)
	var shapes: Array = RoomRecipes.layout(kind, rect.size.x, upper, variant)["shapes"]
	var colors := _colors(p, hue)
	var windows: Array[Rect2i] = []
	for i: int in shapes.size():
		var shape: Array = shapes[i]
		var gate: String = shape[5]
		if gate != "" and (gate == "use") != lit:
			continue
		var r := Rect2i((shape[0] as int) * SUB, top + (shape[1] as int) * SUB, (shape[2] as int) * SUB, (shape[3] as int) * SUB)
		var role: String = shape[4]
		if role == "window":
			_window(pen, r, p, lit)
			windows.append(r)
		elif role == "lamp":
			_lamp(pen, r, p, lit)
		elif role == "furn":
			_furniture(pen, shapes, i, r, windows, colors["furn"])
		else:
			_solid(pen, r, colors[role] if colors.has(role) else hue)
	if lit:
		_glow(pen, shapes, top)
	if kind != "lobby" or top == 0:
		_props(pen, shapes, top, w, id, hue, lit)


## Role -> colour (the recipe roles other than window and lamp, which have their own drawing).
static func _colors(p: Dictionary, hue: Color) -> Dictionary:
	return {
		"furn": WOOD.lerp(hue, 0.12), "accent": hue.lightened(0.2), "ink": Pen.INK, "white": CREAM,
		"red": p["red"], "gold": (p["gold"] as Color).darkened(0.08), "green": LEAF, "wood": (p["wood"] as Color).lightened(0.12), "car": hue,
	}


## The back wall, cornice, dado, skirting and tiled floor, filling the room above its slab. top is the
## sub-pixel row of the bottom floor; h the room's full height in sub-pixels.
static func _shell(pen: Object, w: int, h: int, top: int, hue: Color) -> void:
	var wall := hue.lerp(Color("f2ead8"), 0.62)
	var dado := hue.lerp(Color("3a2a28"), 0.28)
	var trim := hue.lerp(Color("ffffff"), 0.75)
	var floor_c := Color("7a6a60").lerp(hue, 0.22)
	pen.R(0, 0, w, h - SLAB_H, wall)
	for x: int in range(0, w, 24):  # wallpaper stripes on the bottom floor
		pen.R(x, top + 4, 1, 34, wall.darkened(0.045))
	pen.R(0, top + 4, w, 18, wall.lightened(0.05))  # a lighter upper wall, dithered into the lower
	pen.dither_band(0, top + 22, w, wall.lightened(0.05))
	pen.R(0, 4, w, 2, wall.darkened(0.1))  # shade under the cornice, dithered down into the wall
	pen.dither_band(0, 6, w, wall.darkened(0.1))
	pen.R(0, top + 34, w, 1, wall.darkened(0.06))
	pen.dither_band(0, top + 36, w, wall.darkened(0.08))
	pen.R(0, 0, w, 4, trim)  # cornice at the top of the rect
	pen.R(0, 3, w, 1, trim.darkened(0.25))
	pen.R(0, 1, w, 1, trim.lightened(0.25))
	pen.R(0, top + 38, w, 18, dado)
	pen.R(0, top + 38, w, 1, dado.lightened(0.3))
	pen.R(0, top + 39, w, 1, dado.darkened(0.25))
	for x: int in range(15, w, 16):  # panel joints in the dado
		pen.R(x, top + 40, 1, 12, dado.darkened(0.18))
	pen.R(0, top + 52, w, 4, trim.darkened(0.12))  # skirting
	pen.R(0, top + 52, w, 1, trim.lightened(0.2))
	pen.R(0, top + 55, w, 1, trim.darkened(0.4))
	pen.R(0, top + 56, w, 4, floor_c)
	for x: int in range(0, w, 12):  # floor tiles
		pen.R(x, top + 56, 6, 4, floor_c.darkened(0.1))
	pen.R(0, top + 56, w, 1, floor_c.lightened(0.25))
	pen.R(0, 4, 2, h - SLAB_H - 4, Pen.INK.lightened(0.05))  # the room's left wall


## A window: a cream frame, glazing of dithered sky with a muntin cross, and a sill.
static func _window(pen: Object, r: Rect2i, p: Dictionary, lit: bool) -> void:
	var sky: Color = SkyLook.window_color(p, lit, SkyLook.daylight, SkyLook.rain)
	var frame_c := Color("e8e2d4")
	pen.item(r.position.x - 2, r.position.y - 2, r.size.x + 4, r.size.y + 4, frame_c)
	var high: Color = SkyLook.colors(p, SkyLook.daylight, SkyLook.rain)["top"]
	if lit and SkyLook.daylight < SkyLook.FULL / 2:
		high = high.lerp(p["lamp"], 1.0 - float(SkyLook.daylight) / (SkyLook.FULL / 2.0))
	var split := r.size.y / 2
	pen.E(r.position.x, r.position.y, r.size.x, split, high)  # the sky: its top colour above, its horizon below, dithered between
	pen.E(r.position.x, r.position.y + split, r.size.x, r.size.y - split, sky)
	for dx: int in range(0, r.size.x, 4):
		pen.E(r.position.x + dx, r.position.y + split - 1, mini(2, r.size.x - dx), 1, sky)
		pen.E(r.position.x + dx + 2, r.position.y + split, mini(2, maxi(r.size.x - dx - 2, 0)), 1, high)
	var cloud := sky.lerp(Color("ffffff"), 0.35) if SkyLook.daylight > SkyLook.FULL / 2 else sky.lightened(0.1)
	pen.E(r.position.x + 2, r.position.y + r.size.y * 3 / 5, maxi(r.size.x / 2 - 2, 2), 2, cloud)
	_skyline(pen, r)
	pen.R(r.position.x + r.size.x / 2 - 1, r.position.y, 2, r.size.y, frame_c.darkened(0.12))
	if r.size.x >= 10:
		var curtain: Color = (p["red"] as Color).lerp(Color("c8a0a0"), 0.3)
		pen.R(r.position.x - 2, r.position.y - 1, 3, r.size.y + 2, curtain)
		pen.R(r.end.x - 1, r.position.y - 1, 3, r.size.y + 2, curtain)
		pen.R(r.position.x - 2, r.position.y - 1, 1, r.size.y + 2, curtain.darkened(0.25))
		pen.R(r.end.x + 1, r.position.y - 1, 1, r.size.y + 2, curtain.darkened(0.25))
	pen.R(r.position.x, r.position.y + r.size.y / 2 - 1, r.size.x, 2, frame_c.darkened(0.12))
	pen.item(r.position.x - 4, r.end.y + 2, r.size.x + 8, 3, frame_c.lightened(0.05), false)


## A lamp shape by its size: a ceiling fixture (a thin strip near the ceiling), a screen (a panel) or a bulb.
static func _lamp(pen: Object, r: Rect2i, p: Dictionary, lit: bool) -> void:
	var near_ceiling := r.position.y < 8 * SUB and r.size.y <= 3 * SUB
	if near_ceiling and r.size.x >= 6 * SUB:
		pen.R(r.position.x, r.position.y + 2 * SUB, r.size.x, 3, CEILING)
		if lit:
			pen.E(r.position.x + 2, r.position.y + 2 * SUB + 1, r.size.x - 4, 2, Color("fff6d8"))
		else:
			pen.R(r.position.x + 2, r.position.y + 2 * SUB + 1, r.size.x - 4, 2, Color("b8b2a8"))
	elif r.size.x >= 6 * SUB and r.size.y >= 4 * SUB:
		if lit:
			pen.E(r.position.x, r.position.y, r.size.x, r.size.y, SCREEN)
			pen.E(r.position.x + 2, r.position.y + 2, r.size.x - 4, 1, Color("e8f8ff"))
			pen.E(r.position.x + 2, r.position.y + 5, r.size.x * 2 / 3, 1, Color("5aa4d0"))
		else:
			pen.R(r.position.x, r.position.y, r.size.x, r.size.y, Color("1a2030"))
	elif lit:
		pen.E(r.position.x, r.position.y, r.size.x, r.size.y, p["lamp"])
	else:
		pen.R(r.position.x, r.position.y, r.size.x, r.size.y, p["lamp_off"])


## Furniture: nothing when it is a window's frame or muntin, a hollow frame over a shape of the same size
## (a picture frame, a clock rim), a dark bezel when it holds a screen, a bar when thin, else a 3-tone object.
static func _furniture(pen: Object, shapes: Array, index: int, r: Rect2i, windows: Array[Rect2i], color: Color) -> void:
	for win: Rect2i in windows:
		if win.encloses(r):
			return
	if r.size.x >= 4 * SUB and r.size.y >= 3 * SUB and r.end.y % FLOOR_H >= 54:
		pen.E(r.position.x, r.end.y, r.size.x, 2, Color(0, 0, 0, 0.16))  # a soft shadow on the floor
	var shape: Array = shapes[index]
	for j: int in index:
		var before: Array = shapes[j]
		if before[4] != "furn" and before[0] == shape[0] and before[1] == shape[1] and before[2] == shape[2] and before[3] == shape[3]:
			pen.frame(r.position.x, r.position.y, r.size.x, r.size.y, color.darkened(0.2), 2)
			return
	if mini(r.size.x, r.size.y) <= SUB:
		pen.R(r.position.x, r.position.y, r.size.x, r.size.y, color.darkened(0.2))
		return
	pen.item(r.position.x, r.position.y, r.size.x, r.size.y, BEZEL if _holds_screen(shapes, index) else color)


## Whether a later lamp shape sits strictly inside shape `index` (a monitor's bezel).
static func _holds_screen(shapes: Array, index: int) -> bool:
	var shape: Array = shapes[index]
	for j: int in range(index + 1, shapes.size()):
		var later: Array = shapes[j]
		if later[4] != "lamp":
			continue
		var inside: bool = (later[0] as int) >= (shape[0] as int) and (later[1] as int) >= (shape[1] as int) \
			and (later[0] as int) + (later[2] as int) <= (shape[0] as int) + (shape[2] as int) \
			and (later[1] as int) + (later[3] as int) <= (shape[1] as int) + (shape[3] as int)
		if inside and not (later[2] == shape[2] and later[3] == shape[3]):
			return true
	return false


## Any other solid: a bar when thin, else a 3-tone block without an outline.
static func _solid(pen: Object, r: Rect2i, color: Color) -> void:
	if mini(r.size.x, r.size.y) <= SUB:
		pen.R(r.position.x, r.position.y, r.size.x, r.size.y, color)
	else:
		pen.item(r.position.x, r.position.y, r.size.x, r.size.y, color, false)


## A city behind the glass: buildings of stepped heights in the lower third, with lit windows at night.
static func _skyline(pen: Object, r: Rect2i) -> void:
	var night := SkyLook.daylight < SkyLook.FULL / 2
	var base := Color("2a3258") if night else Color("8aa0b8")
	var x := 0
	var k := 0
	while x < r.size.x - 1:
		var bw := 4 + (_h(r.position.x + x, k) % 3) * 2
		bw = mini(bw, r.size.x - x)
		var bh := 4 + (_h(r.position.x + x, k + 7) % 4) * 2
		bh = mini(bh, r.size.y - 2)
		pen.E(r.position.x + x, r.end.y - bh, bw, bh, base.lerp(Color("ffffff"), 0.06 * (k % 3)))
		if night:
			for wy: int in range(r.end.y - bh + 1, r.end.y - 1, 3):
				for wx: int in range(r.position.x + x + 1, r.position.x + x + bw - 1, 2):
					if _h(wx, wy) % 3 == 0:
						pen.E(wx, wy, 1, 1, Color("ffd878"))
		x += bw
		k += 1


## Integer hash of two ints; deterministic, for picking props and building heights.
static func _h(a: int, b: int) -> int:
	return ((a + 1) * 73856093 ^ (b + 1) * 19349663 ^ 0x5bd1e995) & 0x7fffffff


## A warm halo under each ceiling lamp in a lit room at night, as translucent lighter pixels (real light is #305).
static func _glow(pen: Object, shapes: Array, top: int) -> void:
	var strength := clampf(1.0 - float(SkyLook.daylight) / (SkyLook.FULL / 2.0), 0.0, 1.0)
	if strength <= 0.0:
		return
	for shape: Array in shapes:
		if shape[4] != "lamp" or (shape[1] as int) >= 8 or (shape[3] as int) > 3 or (shape[2] as int) < 6:
			continue
		var cx := ((shape[0] as int) + (shape[2] as int) / 2) * SUB
		var wx := (shape[2] as int) * SUB
		for i: int in 4:
			var rx := wx / 2 + 10 + i * 8
			pen.E(cx - rx, top + 10, rx * 2, 14 + i * 12, Color(1.0, 0.86, 0.55, 0.045 * strength * (4 - i) / 2.0))


## Props that vary a room by its id: a plant, a picture, a floor lamp, put where nothing else stands.
static func _props(pen: Object, shapes: Array, top: int, w: int, id: int, hue: Color, lit: bool) -> void:
	var taken: Array[Vector2i] = []
	for shape: Array in shapes:
		var role: String = shape[4]
		var x0 := (shape[0] as int) * SUB
		var x1 := x0 + (shape[2] as int) * SUB
		if role == "window":
			taken.append(Vector2i(x0 - 4, x1 + 4))
		elif role != "lamp" and (shape[1] as int) + (shape[3] as int) >= 20 and (shape[3] as int) >= 3:
			taken.append(Vector2i(x0 - 2, x1 + 2))
	var sel := _h(id, 11)
	for slot: int in 3:
		var want := (sel >> (slot * 3)) & 7
		if want > 4:
			continue
		var pw := 12 if slot == 0 else 10
		var x := 8 + _h(id, 20 + slot) % maxi(w - pw - 16, 1)
		if _blocked(taken, x, pw):
			continue
		taken.append(Vector2i(x - 2, x + pw + 2))
		if slot == 0:
			_plant(pen, x, top, hue, want % 2 == 0)
		elif slot == 1:
			_picture(pen, x, top, hue, want)
		else:
			_floor_lamp(pen, x, top, lit)


static func _blocked(taken: Array[Vector2i], x: int, pw: int) -> bool:
	for t: Vector2i in taken:
		if x < t.y and x + pw > t.x:
			return true
	return false


static func _plant(pen: Object, x: int, top: int, hue: Color, tall: bool) -> void:
	var pot := Color("a5603f").lerp(hue, 0.1)
	pen.item(x + 3, top + 49, 6, 7, pot)
	var h := 14 if tall else 9
	pen.R(x + 6, top + 49 - h, 1, h, LEAF.darkened(0.3))
	pen.R(x + 1, top + 49 - h + 2, 5, 3, LEAF)
	pen.R(x + 6, top + 49 - h, 5, 3, LEAF.lightened(0.15))
	pen.R(x + 3, top + 49 - h / 2, 4, 2, LEAF.darkened(0.12))
	pen.R(x + 7, top + 49 - h / 2 + 1, 4, 2, LEAF)


static func _picture(pen: Object, x: int, top: int, hue: Color, kind: int) -> void:
	var pic := hue.lerp(Color("c06070"), 0.5) if kind % 2 == 0 else hue.lerp(Color("4a7aa0"), 0.6)
	pen.item(x, top + 12, 10, 8, WOOD, true)
	pen.R(x + 2, top + 14, 6, 4, pic)
	pen.R(x + 2, top + 17, 6, 1, pic.darkened(0.25))


static func _floor_lamp(pen: Object, x: int, top: int, lit: bool) -> void:
	pen.R(x + 4, top + 28, 1, 26, WOOD.darkened(0.3))
	pen.R(x + 2, top + 54, 5, 2, WOOD.darkened(0.2))
	if lit:
		pen.E(x + 2, top + 22, 5, 6, Color("ffe8a8"))
		pen.E(x, top + 20, 9, 12, Color(1.0, 0.85, 0.5, 0.12))
	else:
		pen.R(x + 2, top + 22, 5, 6, Color("d8d0b8"))


## The lobby's upper floor: columns, tall windows between them, and a mezzanine rail along its floor.
static func _mezzanine(pen: Object, w: int, top: int, h: int, p: Dictionary, lit: bool) -> void:
	var step := 96
	var col := Color("e8dcc0")
	for cx: int in range(step / 2, w - 4, step):
		pen.item(cx, 4, 8, h - SLAB_H - 4, col, false)
		pen.item(cx - 2, 4, 12, 4, col.lightened(0.1), false)  # capital
		pen.item(cx - 2, h - SLAB_H - 6, 12, 4, col.darkened(0.1), false)  # base
		pen.R(cx + 3, 10, 1, h - SLAB_H - 18, col.darkened(0.2))  # fluting
	var wh := top - 34
	if wh >= 10:
		for cx: int in range(step / 2 + 16, w - 40, step):
			_window(pen, Rect2i(cx, 12, 40, wh), p, lit)
	var rail := Color("5a4030")
	pen.R(0, top - 22, w, 2, rail.lightened(0.15))  # handrail
	pen.R(0, top - 18, w, 1, rail)
	for x: int in range(2, w, 8):
		pen.R(x, top - 20, 1, 18, rail)  # balusters
	pen.item(0, top - 2, w, 3, rail.lightened(0.05), false)  # the mezzanine edge
