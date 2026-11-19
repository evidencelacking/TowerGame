extends Node2D
## One floor slice drawn by code at native resolution (8 px per column, 24 px per floor).
## Mock-up only: not part of the game, and it reads nothing from the simulation.

const COL: int = 8
const FLOOR_H: int = 24
const SLAB: int = 2
const NATIVE_W: int = 448
const NATIVE_H: int = 144
const BUILD_X: int = 32
const SKY_H: int = 24

enum Kind { LOBBY, OFFICE, HOTEL, FOOD }

## [floor, first column, last column, kind, lit by day, lit by night]
const ROOMS: Array = [
	[0, 10, 47, Kind.LOBBY, true, true],
	[1, 10, 21, Kind.OFFICE, true, false],
	[1, 22, 33, Kind.OFFICE, true, false],
	[1, 34, 47, Kind.OFFICE, true, true],
	[2, 10, 18, Kind.HOTEL, false, true],
	[2, 19, 27, Kind.HOTEL, true, true],
	[2, 28, 37, Kind.HOTEL, false, false],
	[2, 38, 47, Kind.HOTEL, false, true],
	[3, 10, 28, Kind.FOOD, true, true],
	[3, 29, 47, Kind.FOOD, true, false],
]

var style_id: int = 0
var night: bool = false
var _s: Dictionary = {}


func setup(style: int, is_night: bool) -> void:
	style_id = style
	night = is_night
	_s = _style(style)
	queue_redraw()


static func _style(id: int) -> Dictionary:
	match id:
		0:  # A: warm, saturated, chunky outlines
			return {
				"sky_day": [Color("5cb8f0"), Color("f8e4a8")],
				"sky_night": [Color("1a1440"), Color("68305c")],
				"wall": Color("3a2216"), "slab": Color("22120c"), "outline": Color("160a06"),
				"hues": [Color("e8b458"), Color("58a0e0"), Color("e0648c"), Color("f08030")],
				"dim_day": 0.45, "dim_night": 0.8, "furn": 0.38, "mode": 0,
				"shaft": Color("2a1a12"), "car": Color("e4c43c"), "ground": Color("4a8a30"),
				"earth": Color("5a3a22"),
				"people": [Color("d03030"), Color("3050c8"), Color("30a040"), Color("f0f0f0"), Color("8a38a8")],
				"skin": Color("f0c090"), "lamp": Color("fff0a0"), "wall_w": 1,
			}
		1:  # B: muted architectural, thin lines, cool night
			return {
				"sky_day": [Color("b4c6d4"), Color("e0e6ea")],
				"sky_night": [Color("0a1222"), Color("1e3048")],
				"wall": Color("1e242c"), "slab": Color("303a46"), "outline": Color("7a8c9e"),
				"hues": [Color("b4a88e"), Color("86a0b2"), Color("a898a8"), Color("c09e76")],
				"dim_day": 0.5, "dim_night": 0.82, "furn": 0.3, "mode": 1,
				"shaft": Color("161c22"), "car": Color("9aaab6"), "ground": Color("6a7882"),
				"earth": Color("2c343c"),
				"people": [Color("5a6a7a"), Color("8a7a6a"), Color("6a8a8a"), Color("a0a0a8"), Color("7a6a8a")],
				"skin": Color("d8c0a8"), "lamp": Color("f4e8c0"), "wall_w": 1,
			}
		3:  # D: A's warm colours with B's thin lines (owner pick, #240)
			return {
				"sky_day": [Color("5cb8f0"), Color("f8e4a8")],
				"sky_night": [Color("1a1440"), Color("68305c")],
				"wall": Color("3a2216"), "slab": Color("22120c"), "outline": Color("160a06"),
				"hues": [Color("e8b458"), Color("58a0e0"), Color("e0648c"), Color("f08030")],
				"dim_day": 0.45, "dim_night": 0.8, "furn": 0.38, "mode": 1,
				"shaft": Color("2a1a12"), "car": Color("e4c43c"), "ground": Color("4a8a30"),
				"earth": Color("5a3a22"),
				"people": [Color("d03030"), Color("3050c8"), Color("30a040"), Color("f0f0f0"), Color("8a38a8")],
				"skin": Color("f0c090"), "lamp": Color("fff0a0"), "wall_w": 1,
			}
		_:  # C: bold flat modern, high contrast
			return {
				"sky_day": [Color("38a0ff"), Color("38a0ff")],
				"sky_night": [Color("0c0c2c"), Color("0c0c2c")],
				"wall": Color("000000"), "slab": Color("000000"), "outline": Color("000000"),
				"hues": [Color("ffd000"), Color("2850ff"), Color("ff2a88"), Color("ff5a00")],
				"dim_day": 0.7, "dim_night": 0.82, "furn": 0.92, "mode": 2,
				"shaft": Color("101010"), "car": Color("ffffff"), "ground": Color("00c060"),
				"earth": Color("101010"),
				"people": [Color("ffffff"), Color("000000"), Color("ffe000"), Color("ff2a88"), Color("00e0ff")],
				"skin": Color("ffffff"), "lamp": Color("ffffff"), "wall_w": 2,
			}


func _draw() -> void:
	if _s.is_empty():
		return
	_draw_sky()
	_draw_ground()
	_draw_stairs()
	_draw_shaft()
	for room: Array in ROOMS:
		_draw_room(room)
	_draw_slabs()
	_draw_people()


func _r(x: int, y: int, w: int, h: int, c: Color) -> void:
	draw_rect(Rect2(x, y, w, h), c)


## A filled box in the style's furniture look: outlined (A), line only (B) or flat (C).
func _box(x: int, y: int, w: int, h: int, c: Color) -> void:
	var mode: int = _s["mode"]
	if mode == 0:
		_r(x - 1, y - 1, w + 2, h + 2, _s["outline"])
		_r(x, y, w, h, c)
	elif mode == 1:
		_frame(x, y, w, h, c)
	else:
		_r(x, y, w, h, c)


func _frame(x: int, y: int, w: int, h: int, c: Color) -> void:
	_r(x, y, w, 1, c)
	_r(x, y + h - 1, w, 1, c)
	_r(x, y, 1, h, c)
	_r(x + w - 1, y, 1, h, c)


func _floor_top(f: int) -> int:
	return SKY_H + (3 - f) * FLOOR_H


func _window_col() -> Color:
	var pair: Array = _s["sky_night"] if night else _s["sky_day"]
	return pair[1] if night else pair[0]


func _draw_sky() -> void:
	var pair: Array = _s["sky_night"] if night else _s["sky_day"]
	var top: Color = pair[0]
	var bot: Color = pair[1]
	var bands: int = 12
	var h: int = SKY_H + 4 * FLOOR_H
	for i: int in bands:
		var t: float = float(i) / float(bands - 1)
		_r(0, i * h / bands, NATIVE_W, h / bands + 1, top.lerp(bot, t))
	if night:
		for i: int in 28:
			var sx: int = (i * 97 + 13) % NATIVE_W
			var sy: int = (i * 53 + 7) % 60
			_r(sx, sy, 1, 1, Color(1, 1, 1, 0.5 + 0.25 * float(i % 3)))
		_r(420, 6, 7, 7, Color("fff0b0") if style_id == 0 or style_id == 3 else Color("e8ecff"))
		if style_id == 1:
			_r(423, 6, 4, 7, top)
	else:
		_r(414, 5, 9, 9, Color("f4f0e0") if style_id == 1 else Color("fff4a0"))
		_r(8, 10, 24, 5, Color(1, 1, 1, 0.85))
		_r(14, 7, 12, 4, Color(1, 1, 1, 0.85))
		_r(BUILD_X + 330, 12, 20, 4, Color(1, 1, 1, 0.8))


func _draw_ground() -> void:
	var gy: int = SKY_H + 4 * FLOOR_H
	_r(0, gy, NATIVE_W, 3, _s["ground"])
	_r(0, gy + 3, NATIVE_W, NATIVE_H - gy - 3, _s["earth"])


func _draw_stairs() -> void:
	var wall: Color = _s["wall"]
	var hue: Color = Color("6a5a4a")
	if style_id == 1:
		hue = Color("5a6672")
	elif style_id == 2:
		hue = Color("ffffff")
	if night and style_id != 2:
		hue = hue.darkened(0.3)
	var rail: Color = Color("7a8c9e") if style_id == 1 else _s["outline"]
	for f: int in 4:
		var top: int = _floor_top(f)
		_r(BUILD_X, top, 7 * COL, FLOOR_H - SLAB, wall.lightened(0.04))
		var yb: int = top + FLOOR_H - SLAB
		var asc_right: bool = f % 2 == 0
		for i: int in 11:
			var k: int = i if asc_right else 10 - i
			var sx: int = BUILD_X + 6 + k * 4
			_r(sx, yb - (i + 1) * 2, 4, (i + 1) * 2, hue)
			_r(sx, yb - (i + 1) * 2 - 3, 4, 1, rail)


func _draw_shaft() -> void:
	var x0: int = BUILD_X + 7 * COL
	var w: int = 3 * COL
	_r(x0, SKY_H, w, 4 * FLOOR_H, _s["shaft"])
	_r(x0 + w / 2, SKY_H, 1, 4 * FLOOR_H, _s["wall"].lightened(0.25))
	var door_c: Color = Color("5a5048")
	if style_id == 1:
		door_c = Color("46525e")
	elif style_id == 2:
		door_c = Color("ffffff")
	for f: int in 4:
		var yb: int = _floor_top(f) + FLOOR_H - SLAB
		_r(x0 + 2, yb - 16, 1, 16, door_c)
		_r(x0 + w - 3, yb - 16, 1, 16, door_c)
	var cf: int = 2 if night else 1
	var cy: int = _floor_top(cf) + FLOOR_H - SLAB - 19
	var car: Color = _s["car"]
	_box(x0 + 3, cy, w - 6, 19, car.darkened(0.55) if style_id != 2 else Color("202020"))
	_r(x0 + 4, cy + 1, w - 8, 17, car.lightened(0.1) if style_id != 2 else Color("ffffff"))
	_r(x0 + w / 2, cy + 1, 1, 17, car.darkened(0.3))


func _draw_slabs() -> void:
	var ww: int = _s["wall_w"]
	for f: int in 4:
		_r(BUILD_X, _floor_top(f) + FLOOR_H - SLAB, 48 * COL, SLAB, _s["slab"])
	_r(BUILD_X, SKY_H - SLAB, 48 * COL, SLAB, _s["slab"])
	_r(BUILD_X - ww, SKY_H - SLAB, ww, 4 * FLOOR_H + SLAB, _s["wall"])
	_r(BUILD_X + 48 * COL, SKY_H - SLAB, ww, 4 * FLOOR_H + SLAB, _s["wall"])
	if _s["mode"] == 1:
		var line: Color = Color("6a7a8c") if style_id == 1 else _s["wall"].lightened(0.3)
		for f: int in 4:
			_r(BUILD_X, _floor_top(f) + FLOOR_H - SLAB, 48 * COL, 1, line)


func _draw_room(room: Array) -> void:
	var f: int = room[0]
	var x0: int = BUILD_X + int(room[1]) * COL
	var w: int = (int(room[2]) - int(room[1]) + 1) * COL
	var kind: int = room[3]
	var lit: bool = room[5] if night else room[4]
	var y0: int = _floor_top(f)
	var h: int = FLOOR_H - SLAB
	var yb: int = y0 + h
	var hue: Color = _s["hues"][kind]
	var base: Color = hue
	if not lit:
		base = hue.darkened(_s["dim_night"] if night else _s["dim_day"])
	_r(x0, y0, w, h, base)
	_r(x0, yb - 2, w, 2, base.darkened(0.25))
	if lit and style_id != 2:
		_r(x0, y0, w, 3, base.lightened(0.18))
	_r(x0, y0, _s["wall_w"], h, _s["wall"])
	if _s["mode"] == 1:
		_frame(x0 + 1, y0, w - 1, h, _s["outline"].darkened(0.3))
	var furn: Color = base.lightened(0.18)
	if lit:
		furn = base.darkened(0.45 if _s["mode"] == 1 else _s["furn"])
	elif style_id == 2:
		furn = base.lightened(0.3)
	var accent: Color = base.lightened(0.4)
	match kind:
		Kind.LOBBY:
			_furn_lobby(x0, y0, w, yb, furn, accent, lit)
		Kind.OFFICE:
			_furn_office(x0, y0, w, yb, furn, lit)
		Kind.HOTEL:
			_furn_hotel(x0, y0, w, yb, furn, accent, lit)
		_:
			_furn_food(x0, y0, w, yb, furn, accent, lit)


func _lamp_col(lit: bool) -> Color:
	return _s["lamp"] if lit else Color("30303a")


func _furn_lobby(x0: int, y0: int, w: int, yb: int, furn: Color, accent: Color, lit: bool) -> void:
	var cx: int = x0 + w / 2 - 16
	_box(cx, yb - 7, 32, 7, furn)
	_box(cx, yb - 9, 32, 2, accent)
	_box(x0 + 10, yb - 4, 5, 4, furn)
	_box(x0 + 8, yb - 11, 9, 7, Color("6a8a70") if style_id == 1 else Color("3c9a48"))
	_box(x0 + w - 18, yb - 16, 10, 16, furn)
	_box(x0 + w - 150, y0 + 3, 60, 3, accent)
	_box(x0 + w / 2 - 4, y0 + 8, 8, 1, _lamp_col(lit))
	_box(x0 + 40, yb - 14, 8, 12, _window_col())
	_box(x0 + w - 60, yb - 14, 8, 12, _window_col())


func _furn_office(x0: int, y0: int, w: int, yb: int, furn: Color, lit: bool) -> void:
	var dx: int = x0 + 6
	while dx + 10 < x0 + w:
		_box(dx, yb - 8, 10, 2, furn)
		_box(dx + 1, yb - 6, 1, 4, furn)
		_box(dx + 8, yb - 6, 1, 4, furn)
		_box(dx + 3, yb - 12, 4, 3, _lamp_col(lit))
		_box(dx + 11, yb - 4, 3, 4, furn)
		dx += 20
	_box(x0 + w / 2 - 5, y0 + 4, 10, 1, _lamp_col(lit))


func _furn_hotel(x0: int, y0: int, w: int, yb: int, furn: Color, accent: Color, lit: bool) -> void:
	_box(x0 + 5, yb - 5, 22, 4, furn)
	_box(x0 + 5, yb - 9, 2, 8, furn)
	_box(x0 + 8, yb - 7, 5, 2, Color("f0f0f0") if lit else Color("707078"))
	_box(x0 + w - 12, yb - 5, 5, 5, furn)
	_box(x0 + w - 11, yb - 9, 3, 3, _lamp_col(lit))
	_box(x0 + 32, y0 + 4, 9, 8, _window_col())
	if w > 72:
		_box(x0 + 52, yb - 12, 6, 12, accent)


func _furn_food(x0: int, y0: int, w: int, yb: int, furn: Color, accent: Color, lit: bool) -> void:
	var tx: int = x0 + 12
	while tx + 12 < x0 + w - 30:
		_box(tx, yb - 7, 8, 1, furn)
		_box(tx + 3, yb - 6, 2, 6, furn)
		_box(tx - 3, yb - 4, 2, 4, furn)
		_box(tx + 9, yb - 4, 2, 4, furn)
		_r(tx + 3, y0 + 3, 1, 5, _s["outline"])
		_box(tx + 1, y0 + 8, 5, 2, _lamp_col(lit))
		tx += 26
	_box(x0 + w - 34, yb - 8, 28, 8, furn)
	_box(x0 + w - 34, yb - 10, 28, 2, accent)
	_box(x0 + w - 30, y0 + 4, 20, 4, accent)


func _fig(x: int, feet: int, i: int) -> void:
	var cols: Array = _s["people"]
	var shirt: Color = cols[i % cols.size()]
	if style_id == 2:
		_r(x - 1, feet - 8, 5, 8, Color("000000"))
	_r(x, feet - 7, 3, 2, _s["skin"])
	_r(x, feet - 5, 3, 4, shirt)
	_r(x, feet - 1, 1, 1, _s["outline"])
	_r(x + 2, feet - 1, 1, 1, _s["outline"])


func _lit(f: int, c: int) -> bool:
	for room: Array in ROOMS:
		if room[0] == f and c >= int(room[1]) and c <= int(room[2]):
			return room[5] if night else room[4]
	return false


func _draw_people() -> void:
	var yb0: int = _floor_top(0) + FLOOR_H - SLAB
	var yb1: int = _floor_top(1) + FLOOR_H - SLAB
	var yb2: int = _floor_top(2) + FLOOR_H - SLAB
	var yb3: int = _floor_top(3) + FLOOR_H - SLAB
	for i: int in 7:
		_fig(BUILD_X + 96 + i * 37 + (i % 2) * 5, yb0 - 1 + (i % 2), i)
	for i: int in 3:
		if _lit(1, 12 + i * 12):
			_fig(BUILD_X + (12 + i * 12) * COL + 11, yb1 - 1, i)
	if _lit(1, 40):
		_fig(BUILD_X + 40 * COL + 31, yb1 - 1, 2)
	if _lit(2, 22):
		_fig(BUILD_X + 22 * COL + 30, yb2 - 1, 1)
	if _lit(2, 40):
		_fig(BUILD_X + 40 * COL + 38, yb2 - 1, 3)
	if _lit(2, 12):
		_fig(BUILD_X + 12 * COL + 40, yb2 - 1, 4)
	if _lit(3, 12):
		for i: int in 5:
			_fig(BUILD_X + 12 * COL + 14 + i * 26, yb3 - 1, i + 1)
	if _lit(3, 40):
		_fig(BUILD_X + 40 * COL + 6, yb3 - 1, 0)
		_fig(BUILD_X + 36 * COL + 10, yb3 - 1, 2)
	_fig(BUILD_X + 26, yb1 - 12, 3)
	var cx: int = BUILD_X + 7 * COL + 5
	var cy: int = _floor_top(2 if night else 1) + FLOOR_H - SLAB - 1
	_fig(cx, cy, 0)
	_fig(cx + 6, cy, 2)
	_fig(cx + 12, cy, 4)
