extends Node2D
## One floor slice drawn by code at native resolution (8 px per column; floor height is per scene, 24 by default).
## Mock-up only: not part of the game, and it reads nothing from the simulation.

const COL: int = 8
const SLAB: int = 2
const NATIVE_W: int = 448
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
var fh: int = 24
var detail: int = 0
var night: bool = false
var _s: Dictionary = {}


## Native height of a scene: sky strip, four floors, ground strip.
static func native_h(floor_h: int) -> int:
	return SKY_H + 4 * floor_h + 24


## detail 0 is the original 24 px drawing; detail 1 uses the extra floor height for furniture.
func setup(style: int, is_night: bool, floor_h: int = 24, detail_level: int = 0) -> void:
	style_id = style
	night = is_night
	fh = floor_h
	detail = detail_level
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
	if detail > 0:
		_d_stairs()
		_d_shaft()
	else:
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
	return SKY_H + (3 - f) * fh


func _window_col() -> Color:
	var pair: Array = _s["sky_night"] if night else _s["sky_day"]
	return pair[1] if night else pair[0]


func _draw_sky() -> void:
	var pair: Array = _s["sky_night"] if night else _s["sky_day"]
	var top: Color = pair[0]
	var bot: Color = pair[1]
	var bands: int = 12
	var h: int = SKY_H + 4 * fh
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
	var gy: int = SKY_H + 4 * fh
	_r(0, gy, NATIVE_W, 3, _s["ground"])
	_r(0, gy + 3, NATIVE_W, native_h(fh) - gy - 3, _s["earth"])


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
		_r(BUILD_X, top, 7 * COL, fh - SLAB, wall.lightened(0.04))
		var yb: int = top + fh - SLAB
		var asc_right: bool = f % 2 == 0
		for i: int in 11:
			var k: int = i if asc_right else 10 - i
			var sx: int = BUILD_X + 6 + k * 4
			_r(sx, yb - (i + 1) * 2, 4, (i + 1) * 2, hue)
			_r(sx, yb - (i + 1) * 2 - 3, 4, 1, rail)


func _draw_shaft() -> void:
	var x0: int = BUILD_X + 7 * COL
	var w: int = 3 * COL
	_r(x0, SKY_H, w, 4 * fh, _s["shaft"])
	_r(x0 + w / 2, SKY_H, 1, 4 * fh, _s["wall"].lightened(0.25))
	var door_c: Color = Color("5a5048")
	if style_id == 1:
		door_c = Color("46525e")
	elif style_id == 2:
		door_c = Color("ffffff")
	for f: int in 4:
		var yb: int = _floor_top(f) + fh - SLAB
		_r(x0 + 2, yb - 16, 1, 16, door_c)
		_r(x0 + w - 3, yb - 16, 1, 16, door_c)
	var cf: int = 2 if night else 1
	var cy: int = _floor_top(cf) + fh - SLAB - 19
	var car: Color = _s["car"]
	_box(x0 + 3, cy, w - 6, 19, car.darkened(0.55) if style_id != 2 else Color("202020"))
	_r(x0 + 4, cy + 1, w - 8, 17, car.lightened(0.1) if style_id != 2 else Color("ffffff"))
	_r(x0 + w / 2, cy + 1, 1, 17, car.darkened(0.3))


func _draw_slabs() -> void:
	var ww: int = _s["wall_w"]
	for f: int in 4:
		_r(BUILD_X, _floor_top(f) + fh - SLAB, 48 * COL, SLAB, _s["slab"])
	_r(BUILD_X, SKY_H - SLAB, 48 * COL, SLAB, _s["slab"])
	_r(BUILD_X - ww, SKY_H - SLAB, ww, 4 * fh + SLAB, _s["wall"])
	_r(BUILD_X + 48 * COL, SKY_H - SLAB, ww, 4 * fh + SLAB, _s["wall"])
	if _s["mode"] == 1:
		var line: Color = Color("6a7a8c") if style_id == 1 else _s["wall"].lightened(0.3)
		for f: int in 4:
			_r(BUILD_X, _floor_top(f) + fh - SLAB, 48 * COL, 1, line)


func _draw_room(room: Array) -> void:
	var f: int = room[0]
	var x0: int = BUILD_X + int(room[1]) * COL
	var w: int = (int(room[2]) - int(room[1]) + 1) * COL
	var kind: int = room[3]
	var lit: bool = room[5] if night else room[4]
	var y0: int = _floor_top(f)
	var h: int = fh - SLAB
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
	if detail > 0:
		_d_room(kind, x0, y0, w, yb, furn, accent, lit)
		return
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
	if detail > 0:
		_d_fig(x, feet + 1, shirt)
		return
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
	var yb0: int = _floor_top(0) + fh - SLAB
	var yb1: int = _floor_top(1) + fh - SLAB
	var yb2: int = _floor_top(2) + fh - SLAB
	var yb3: int = _floor_top(3) + fh - SLAB
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
	if detail > 0:
		_fig(_d_step_x(1, 4) + 1, yb1 - _d_step_h(4), 3)
	else:
		_fig(BUILD_X + 26, yb1 - 12, 3)
	var cx: int = BUILD_X + 7 * COL + 5
	var cy: int = _floor_top(2 if night else 1) + fh - SLAB - 1
	_fig(cx, cy, 0)
	_fig(cx + 6, cy, 2)
	_fig(cx + 12, cy, 4)


# ---- Detail level 1: furniture that uses the extra floor height. Everything stands on the floor
# line (yb) and ceiling items hang from the ceiling (y0), so extra height is headroom only.

func _d_room(kind: int, x0: int, y0: int, w: int, yb: int, furn: Color, accent: Color, lit: bool) -> void:
	match kind:
		Kind.LOBBY:
			_d_lobby(x0, y0, w, yb, furn, accent, lit)
		Kind.OFFICE:
			_d_office(x0, y0, w, yb, furn, lit)
		Kind.HOTEL:
			_d_hotel(x0, y0, w, yb, furn, accent, lit)
		_:
			_d_food(x0, y0, w, yb, furn, accent, lit)


func _d_window(x: int, y: int, w: int, h: int, furn: Color) -> void:
	_r(x, y, w, h, _window_col())
	_frame(x, y, w, h, furn)
	_r(x + w / 2, y, 1, h, furn)
	_r(x, y + h / 2, w, 1, furn)


func _d_office(x0: int, y0: int, w: int, yb: int, furn: Color, lit: bool) -> void:
	var lamp: Color = _lamp_col(lit)
	var dx: int = x0 + 8
	var n: int = 0
	while dx + 28 < x0 + w:
		_r(dx, yb - 10, 20, 1, furn)  # desk top and legs
		_r(dx + 1, yb - 9, 1, 9, furn)
		_r(dx + 18, yb - 9, 1, 9, furn)
		_r(dx + 2, yb - 8, 9, 1, furn)  # drawer rail
		_frame(dx + 11, yb - 16, 8, 6, furn)  # monitor, screen and stand
		_r(dx + 12, yb - 15, 6, 4, lamp)
		_r(dx + 14, yb - 11, 2, 1, furn)
		_r(dx + 24, yb - 13, 1, 7, furn)  # chair back, seat, stem, base
		_r(dx + 22, yb - 6, 4, 1, furn)
		_r(dx + 24, yb - 5, 1, 4, furn)
		_r(dx + 22, yb - 1, 5, 1, furn)
		_r(dx + 3, y0 + 4, 14, 1, lamp)  # ceiling light
		_r(dx + 9, y0 + 3, 1, 1, furn)
		if n % 2 == 0:
			_d_window(dx + 2, yb - 27, 8, 10, furn)
		n += 1
		dx += 32
	_d_clock(x0 + w / 2 - 3, yb - 26, furn, lit)
	var fx: int = x0 + w - 13  # filing cabinet
	_frame(fx, yb - 14, 8, 14, furn)
	_r(fx, yb - 9, 8, 1, furn)
	_r(fx + 3, yb - 12, 2, 1, furn)
	_r(fx + 3, yb - 7, 2, 1, furn)
	_r(fx + 3, yb - 3, 2, 1, furn)


func _d_clock(x: int, y: int, furn: Color, lit: bool) -> void:
	_r(x, y, 7, 7, Color("f4ecd8") if lit else Color("707078"))
	_frame(x, y, 7, 7, furn)
	_r(x + 3, y + 1, 1, 3, furn)
	_r(x + 3, y + 3, 2, 1, furn)


func _d_hotel(x0: int, y0: int, w: int, yb: int, furn: Color, accent: Color, lit: bool) -> void:
	var lamp: Color = _lamp_col(lit)
	_r(x0 + 4, yb - 14, 2, 14, furn)  # headboard
	_frame(x0 + 5, yb - 7, 25, 4, furn)  # mattress
	_r(x0 + 6, yb - 6, 23, 2, Color("f0e0d0") if lit else Color("584840"))
	_r(x0 + 28, yb - 10, 2, 7, furn)  # footboard
	_r(x0 + 5, yb - 3, 1, 3, furn)
	_r(x0 + 29, yb - 3, 1, 3, furn)
	_frame(x0 + 7, yb - 10, 8, 3, furn)  # pillow
	_r(x0 + 8, yb - 9, 6, 1, Color("f0f0f0") if lit else Color("707078"))
	_r(x0 + 17, yb - 7, 11, 1, furn)  # blanket fold
	_frame(x0 + 33, yb - 6, 7, 6, furn)  # nightstand and lamp
	_r(x0 + 33, yb - 4, 7, 1, furn)
	_r(x0 + 36, yb - 10, 1, 4, furn)
	_r(x0 + 34, yb - 13, 5, 3, lamp)
	_frame(x0 + 34, yb - 13, 5, 3, furn)
	_frame(x0 + 10, yb - 25, 11, 7, furn)  # picture above the bed
	_r(x0 + 12, yb - 23, 7, 3, accent)
	_d_window(x0 + 43, yb - 24, 10, 11, furn)
	var wx: int = x0 + w - 17  # wardrobe
	_frame(wx, yb - 23, 12, 22, furn)
	_r(wx + 6, yb - 22, 1, 20, furn)
	_r(wx + 4, yb - 13, 1, 3, furn)
	_r(wx + 8, yb - 13, 1, 3, furn)
	_r(wx + 1, yb - 1, 1, 1, furn)
	_r(wx + 10, yb - 1, 1, 1, furn)
	_r(x0 + 14, y0 + 4, 8, 1, lamp)  # ceiling light


func _d_food(x0: int, y0: int, w: int, yb: int, furn: Color, accent: Color, lit: bool) -> void:
	var lamp: Color = _lamp_col(lit)
	var tx: int = x0 + 14
	while tx + 20 < x0 + w - 44:
		_r(tx, yb - 10, 14, 1, furn)  # table top, pedestal, foot
		_r(tx + 6, yb - 9, 2, 8, furn)
		_r(tx + 3, yb - 1, 8, 1, furn)
		_r(tx + 5, yb - 11, 4, 1, accent)  # dish
		_r(tx - 6, yb - 13, 1, 7, furn)  # left chair
		_r(tx - 6, yb - 6, 4, 1, furn)
		_r(tx - 6, yb - 5, 1, 5, furn)
		_r(tx - 3, yb - 5, 1, 5, furn)
		_r(tx + 19, yb - 13, 1, 7, furn)  # right chair
		_r(tx + 16, yb - 6, 4, 1, furn)
		_r(tx + 16, yb - 5, 1, 5, furn)
		_r(tx + 19, yb - 5, 1, 5, furn)
		_r(tx + 7, y0 + 4, 1, 7, furn)  # hanging lamp
		_r(tx + 3, y0 + 11, 9, 2, lamp)
		_frame(tx + 3, y0 + 11, 9, 2, furn)
		tx += 34
	var cx: int = x0 + w - 36  # counter with stools and a menu board
	_frame(cx, yb - 11, 30, 11, furn)
	_r(cx - 1, yb - 12, 32, 1, furn)
	_r(cx + 4, yb - 15, 5, 3, furn)  # till
	_r(cx + 14, yb - 14, 2, 2, accent)
	for sx: int in [cx - 8, cx - 16]:
		_r(sx, yb - 8, 5, 1, furn)
		_r(sx + 2, yb - 7, 1, 7, furn)
		_r(sx, yb - 1, 5, 1, furn)
	_r(cx + 2, y0 + 5, 26, 10, accent.darkened(0.1) if lit else furn.lightened(0.05))  # menu board
	_frame(cx + 2, y0 + 5, 26, 10, furn)
	for i: int in 3:
		_r(cx + 5, y0 + 8 + i * 3, 12 + (i % 2) * 5, 1, furn)
		_r(cx + 22, y0 + 8 + i * 3, 3, 1, furn)


func _d_lobby(x0: int, y0: int, w: int, yb: int, furn: Color, accent: Color, lit: bool) -> void:
	var lamp: Color = _lamp_col(lit)
	var green: Color = Color("3c9a48") if lit else Color("2c6a38")
	var cx: int = x0 + w / 2 - 22  # reception desk
	_frame(cx, yb - 12, 44, 12, furn)
	_r(cx - 1, yb - 13, 46, 1, furn)
	_r(cx + 4, yb - 8, 12, 1, furn)
	_r(cx + 28, yb - 17, 6, 4, furn)  # terminal
	_r(cx + 29, yb - 16, 4, 2, lamp)
	_frame(x0 + w / 2 - 36, y0 + 5, 72, 8, furn)  # signage band
	_r(x0 + w / 2 - 35, y0 + 6, 70, 6, accent)
	for i: int in 8:
		_r(x0 + w / 2 - 28 + i * 7, y0 + 8, 4, 2, furn)
	for px: int in [x0 + 14, x0 + w - 24]:  # plants
		_frame(px, yb - 6, 8, 6, furn)
		_r(px + 3, yb - 13, 1, 7, green)
		_r(px + 1, yb - 15, 6, 1, green)
		_r(px - 1, yb - 12, 3, 1, green)
		_r(px + 6, yb - 11, 3, 1, green)
		_r(px + 2, yb - 17, 4, 1, green)
	var sx: int = x0 + 54  # sofa
	_frame(sx, yb - 6, 26, 5, furn)
	_r(sx, yb - 12, 3, 12, furn)
	_r(sx + 23, yb - 9, 3, 9, furn)
	_r(sx + 3, yb - 10, 20, 1, furn)
	_d_window(x0 + 108, yb - 25, 12, 11, furn)
	_d_window(x0 + w - 70, yb - 25, 12, 11, furn)
	for lx: int in [x0 + 70, x0 + w / 2 - 2, x0 + w - 90]:  # ceiling lights
		_r(lx, y0 + 4, 8, 1, lamp)


func _d_fig(x: int, feet: int, shirt: Color) -> void:
	_r(x, feet - 9, 4, 3, _s["skin"])  # head, hair, body, legs
	_r(x, feet - 9, 4, 1, _s["outline"].lightened(0.15))
	_r(x, feet - 6, 4, 4, shirt)
	_r(x, feet - 2, 1, 2, _s["outline"])
	_r(x + 3, feet - 2, 1, 2, _s["outline"])


func _d_step_h(i: int) -> int:
	return (i + 1) * (fh - SLAB) / 10


func _d_step_x(f: int, i: int) -> int:
	var k: int = i if f % 2 == 0 else 9 - i
	return BUILD_X + 3 + k * 5


func _d_stairs() -> void:
	var wall: Color = _s["wall"]
	var hue: Color = Color("6a5a4a")
	if night:
		hue = hue.darkened(0.3)
	var rail: Color = _s["wall"].lightened(0.5)
	var tread: Color = hue.lightened(0.15)
	for f: int in 4:
		var top: int = _floor_top(f)
		_r(BUILD_X, top, 7 * COL, fh - SLAB, wall.lightened(0.04))
		var yb: int = top + fh - SLAB
		for i: int in 10:
			var sx: int = _d_step_x(f, i)
			var sh: int = _d_step_h(i)
			_r(sx, yb - sh, 5, sh, hue)
			_r(sx, yb - sh, 5, 1, tread)
		var ry0: int = top + 1  # the rail never rises above the ceiling
		for i: int in 10:  # handrail, one 5 px run per step, posts every third step
			_r(_d_step_x(f, i), maxi(yb - _d_step_h(i) - 9, ry0), 5, 1, rail)
		for i: int in 9:  # join each run to the next so the rail is one slope
			var up: int = _d_step_h(i + 1) - _d_step_h(i)
			var jx: int = _d_step_x(f, i + 1) - 1 if f % 2 == 0 else _d_step_x(f, i)
			var jy: int = maxi(yb - _d_step_h(i + 1) - 9, ry0)
			_r(jx, jy, 1, mini(up + 1, yb - _d_step_h(i) - 9 - jy + 1), rail)
		for i: int in [0, 3, 6, 9]:
			var py: int = maxi(yb - _d_step_h(i) - 9, ry0)
			_r(_d_step_x(f, i) + 2, py, 1, yb - _d_step_h(i) - py, rail)


func _d_shaft() -> void:
	var x0: int = BUILD_X + 7 * COL
	var w: int = 3 * COL
	_r(x0, SKY_H, w, 4 * fh, _s["shaft"])
	_r(x0 + w / 2, SKY_H, 1, 4 * fh, _s["wall"].lightened(0.25))
	var door_c: Color = Color("5a5048")
	var cf: int = 2 if night else 1
	for f: int in 4:
		var yb: int = _floor_top(f) + fh - SLAB
		_frame(x0 + 3, yb - 18, 18, 18, door_c)
		_r(x0 + w / 2, yb - 18, 1, 18, door_c)
		for p: int in 4:  # indicator above the door: one pip per floor, lit at the car
			var on: bool = (3 - p) == cf
			_r(x0 + 6 + p * 4, yb - 22, 2, 2, Color("ff5030") if on else door_c)
	var cy: int = _floor_top(cf) + fh - SLAB - 19
	var car: Color = _s["car"]
	_frame(x0 + 3, cy, 18, 19, car.darkened(0.55))
	_r(x0 + 4, cy + 1, 16, 18, car.lightened(0.1))
	_r(x0 + w / 2, cy + 1, 1, 18, car.darkened(0.3))
	_r(x0 + 4, cy + 9, 16, 1, car.darkened(0.3))
