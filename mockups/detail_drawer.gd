extends "res://mockups/detail_prims.gd"
## One tower slice at double density (16 px per column, 64 px per floor): lobby, office, condo,
## restaurant, stairs, escalator, an elevator shaft with a car, and people. Mock-up only.

const W: int = 640
const H: int = 344
const TOP: int = 56
const FH: int = 64
const GROUND: int = 312
const BX0: int = 24
const BX1: int = 616
const STAIR_X: int = 32
const SHAFT_X: int = 112
const ESC_X: int = 160
const ROOM_X: int = 224

const SLAB_C: Color = Color("4b4352")
const INK: Color = Color("2a1f2b")
const WARM: Color = Color("ffcf8a")

## [skin, hair, hair style (0 short, 1 long, 2 bald, 3 bun), shirt, trousers, shoes]
const LOOKS: Array = [
	[Color("f0c59a"), Color("3a2418"), 0, Color("c8453c"), Color("3d4660"), Color("2a1f2b")],
	[Color("d9a074"), Color("1c1414"), 1, Color("3f7fb0"), Color("4a3a52"), Color("3a2a2a")],
	[Color("8a5a3c"), Color("141010"), 0, Color("e0a83a"), Color("2f3a4a"), Color("1c1618")],
	[Color("f4d2b0"), Color("c98a3c"), 1, Color("6aa06a"), Color("5a4a6a"), Color("3a2a2a")],
	[Color("e8b88c"), Color("8a8a90"), 2, Color("eeeae0"), Color("46506a"), Color("2a2a30")],
	[Color("6a4228"), Color("1a1210"), 3, Color("9a55b0"), Color("2a2f3c"), Color("1c1618")],
]

var lights: Array = []  ## [x, y, radius, energy, colour] for the scene to turn into PointLight2D
var occluders: Array = []  ## [x, y, w, h] solid rectangles that stop light


func setup(style_id: int, is_night: bool, layer: int) -> void:
	style = style_id
	night = is_night
	pass_layer = layer
	queue_redraw()


func _ytop(row: int) -> float:
	return float(TOP + row * FH)


func _fy(row: int) -> float:  ## Where feet touch the floor of a row.
	return _ytop(row) + 58.0


func _sky_col(y: float) -> Color:
	var t: float = clampf(y / float(GROUND), 0.0, 1.0)
	var lo: Color = Color("0b1033") if night else Color("3a92e0")
	var mid: Color = Color("2a2468") if night else Color("a4d6f0")
	var hi: Color = Color("8a4a6c") if night else Color("f6e8bc")
	if t < 0.6:
		return lo.lerp(mid, t / 0.6)
	return mid.lerp(hi, (t - 0.6) / 0.4)


func _draw() -> void:
	lights.clear()
	occluders.clear()
	_tex_cache.clear()
	_layer = Layer.BG
	_sky()
	_layer = Layer.WORLD
	_dark = 0.0
	_shell()
	_stairs()
	_shaft()
	_escalator()
	_room_restaurant()
	_room_condo_a()
	_room_condo_b()
	_room_office(224.0, 192.0, 0)
	_room_office(416.0, 192.0, 1)
	_vestibule()
	_room_lobby()
	_slabs()
	_street()
	_roof()


# ---------------------------------------------------------------- sky and outdoors

func _sky() -> void:
	if not _active():
		return
	var top_c: Color = _sky_col(0.0)
	var bot_c: Color = _sky_col(float(GROUND))
	if _smooth():
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(W, 0), Vector2(W, GROUND), Vector2(0, GROUND)]),
			PackedColorArray([top_c, top_c, bot_c, bot_c]))
	else:
		var steps: int = 8
		for i: int in steps:
			var y0: int = i * GROUND / steps
			var y1: int = (i + 1) * GROUND / steps
			var c: Color = top_c.lerp(bot_c, float(i) / float(steps - 1))
			if i > 0:  # a dithered seam between bands
				var prev_c: Color = top_c.lerp(bot_c, float(i - 1) / float(steps - 1))
				for px: int in range(0, W, 2):
					draw_rect(Rect2(px + (y0 / 2) % 2, y0, 1, 1), prev_c)
					draw_rect(Rect2(px + 1 - (y0 / 2) % 2, y0 + 1, 1, 1), prev_c)
			draw_rect(Rect2(0, y0 + (2 if i > 0 else 0), W, y1 - y0 - (2 if i > 0 else 0)), c)
	if night:
		for i: int in 70:
			var sx: float = hn(i, 1) * float(W)
			var sy: float = hn(i, 2) * 180.0
			var br: float = 0.4 + hn(i, 3) * 0.6
			if _smooth():
				draw_circle(Vector2(sx, sy), 0.5 + hn(i, 4) * 0.5, Color(1, 0.96, 0.85, br))
			else:
				draw_rect(Rect2(floorf(sx), floorf(sy), 1, 1), Color(1, 0.96, 0.85, br))
		if _smooth():
			draw_circle(Vector2(560, 26), 19, Color(0.95, 0.93, 0.8, 0.10))
			draw_circle(Vector2(560, 26), 11, Color("f1ecd0"))
			draw_circle(Vector2(564, 23), 9.5, Color("2a2468"))
		else:
			_raw_ell(560, 26, 11, 11, Color("f1ecd0"))
			_raw_ell(564, 23, 9, 9, Color("231f60"))
	else:
		if _smooth():
			draw_circle(Vector2(560, 28), 28, Color(1, 0.95, 0.7, 0.12))
			draw_circle(Vector2(560, 28), 20, Color(1, 0.95, 0.7, 0.2))
			draw_circle(Vector2(560, 28), 12, Color("fff3b0"))
		else:
			_raw_ell(560, 28, 17, 17, Color("e8f0c0"))
			_raw_ell(560, 28, 12, 12, Color("fff0a0"))
			_raw_ell(560, 27, 9, 9, Color("fffadc"))
	_cloud(60, 22, 1.0)
	_cloud(180, 36, 0.7)
	_cloud(410, 18, 0.85)
	_cloud(8, 90, 0.7)
	_cloud(612, 96, 0.6)
	_skyline(0, 222, 24, 90)
	_skyline(616, 222, 24, 90)


func _cloud(x: float, y: float, s: float) -> void:
	var tone: Color = Color("5a5890") if night else Color("ffffff")
	var shade: Color = Color("3c3a74") if night else Color("d4e4f4")
	var a: float = 0.6 if night else 0.95
	var blobs: Array = [[0, 4, 14, 7], [12, 0, 12, 9], [26, 3, 14, 7], [38, 6, 12, 5], [8, 6, 22, 5]]
	for pass_i: int in 2:
		var c: Color = shade if pass_i == 0 else tone
		for b: Array in blobs:
			var cx: float = x + float(b[0]) * s
			var cy: float = y + float(b[1]) * s + (1.5 if pass_i == 0 else 0.0)
			var rx: float = float(b[2]) * s
			var ry: float = float(b[3]) * s
			if _smooth():
				draw_colored_polygon(_ell_pts(cx, cy, rx, ry), Color(c.r, c.g, c.b, a))
			else:
				_raw_ell(cx, cy, rx, ry, c)


func _ell_pts(cx: float, cy: float, rx: float, ry: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 28:
		var a: float = TAU * float(i) / 28.0
		pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	return pts


## A pixel ellipse that ignores layers and room darkness (sky objects).
func _raw_ell(cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	var iy: int = int(ceil(ry))
	for dy: int in range(-iy, iy):
		var t: float = (float(dy) + 0.5) / ry
		if absf(t) >= 1.0:
			continue
		var hw: float = rx * sqrt(1.0 - t * t)
		var x0: float = roundf(cx - hw)
		var x1: float = roundf(cx + hw)
		if x1 > x0:
			draw_rect(Rect2(x0, floorf(cy) + float(dy), x1 - x0, 1.0), c)


func _skyline(x: float, y: float, w: float, h: float) -> void:
	var haze: Color = Color("1a1a48") if night else Color("8fb0cc")
	var haze2: Color = Color("262460") if night else Color("a5c2d8")
	var xx: float = 0.0
	var i: int = int(x) / 6
	while xx < w:
		var bw: float = 8.0 + floorf(hn(i, 11) * 8.0)
		var bh: float = 20.0 + floorf(hn(i, 12) * 56.0)
		draw_rect(Rect2(x + xx, y + h - bh, minf(bw, w - xx), bh), haze if i % 2 == 0 else haze2)
		if night:
			for wy: int in int(bh / 6.0):
				if hn(i * 31 + wy, 13) > 0.65:
					draw_rect(Rect2(x + xx + 2.0, y + h - bh + 3.0 + float(wy) * 6.0, 2, 2), Color("ffd27a"))
		xx += bw
		i += 1


## One pane of a window: sky gradient, hazy skyline, a cloud by day. Never darkened by the room.
func _pane(x: float, y: float, w: float, h: float, seed_v: int) -> void:
	var c1: Color = _sky_col(y + 30.0)
	var c2: Color = _sky_col(y + h + 30.0)
	if _smooth():
		draw_polygon(PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)]),
			PackedColorArray([c1, c1, c2, c2]))
	var skyc: Color = Color("2a2a66") if night else Color("93b6d4")
	for k: int in int(w) / 5 + 1:
		var bw: float = minf(5.0, w - float(k * 5))
		if bw <= 0.0:
			continue
		var bh: float = 5.0 + floorf(hn(k + seed_v * 7, 5) * h * 0.45)
		var bc: Color = skyc if k % 2 == 0 else skyc.lightened(0.06)
		if _smooth():
			draw_rect(Rect2(x + float(k * 5), y + h - bh, bw, bh), bc)
		else:
			# sky rows stop where the building starts, so light adds never overlap
			for py: int in int(h - bh):
				GR(x + float(k * 5), y + float(py), bw, 1, c1.lerp(c2, float(py) / h))
			GR(x + float(k * 5), y + h - bh, bw, bh, bc)
		if night and hn(k + seed_v * 7, 6) > 0.5 and bw >= 2.0:
			GR(x + float(k * 5) + 1.0, y + h - bh + 2.0, 1, 1, Color("ffd27a"))
	if not night and w >= 12.0 and h >= 10.0:
		if _smooth():
			draw_colored_polygon(_ell_pts(x + w * 0.5, y + h * 0.3, minf(7.0, w * 0.4), 2.6), Color(1, 1, 1, 0.85))
		else:
			GR(x + w * 0.5 - 5.0, y + h * 0.3, 10, 2, Color("ffffff"))
			GR(x + w * 0.5 - 3.0, y + h * 0.3 - 2.0, 6, 2, Color("ffffff"))


## A window: frame, four panes with a muntin cross between them, a glint, a sill and curtains.
func _window(x: float, y: float, w: float, h: float, frame: Color, curtain: Color, seed_v: int, blind: bool = false) -> void:
	item(x - 3, y - 3, w + 6, h + 6, frame, 1.5)
	var hw: float = floorf(w * 0.5)
	var th: float = floorf(h * 0.55)
	_pane(x, y, hw - 1, th - 1, seed_v)
	_pane(x + hw + 1, y, w - hw - 1, th - 1, seed_v + 1)
	_pane(x, y + th + 1, hw - 1, h - th - 1, seed_v + 2)
	_pane(x + hw + 1, y + th + 1, w - hw - 1, h - th - 1, seed_v + 3)
	R(x + hw - 1, y, 2, h, frame.darkened(0.12))
	R(x, y + th - 1, w, 2, frame.darkened(0.12))
	GW(x + 3, y + 1, 4, 10, Color(0.25, 0.25, 0.28))
	GW(x + 9, y + 1, 2, 10, Color(0.18, 0.18, 0.2))
	item(x - 5, y + h + 2, w + 10, 3, frame.lightened(0.1), 1)
	if blind:
		for i: int in int(h * 0.4 / 3.0):
			R(x, y + float(i) * 3.0, w, 2, Color("f2e8d0"))
			R(x, y + float(i) * 3.0 + 2.0, w, 1, Color("c8b898"))
	if curtain.a > 0.0:
		_curtain(x - 9, y - 4, 6, h + 6, curtain)
		_curtain(x + w + 3, y - 4, 6, h + 6, curtain)


func _curtain(x: float, y: float, w: float, h: float, c: Color) -> void:
	item(x, y, w, h, c, 2.0, false)
	for i: int in int(w / 2.0):
		R(x + float(i) * 2.0 + 1.0, y + 1, 1, h - 2, c.darkened(0.2))


func _street() -> void:
	var gy: float = float(GROUND)
	item(float(BX0 - 4), gy - 2, float(BX1 - BX0 + 8), 6, Color("5a5260"), 0.0, false)
	gradv(0, gy + 4, W, 10, Color("c8c2ba"), Color("a8a2a0"))
	for i: int in 26:
		R(float(i * 26), gy + 4, 1, 10, Color("8f8a8c"))
	R(0, gy + 14, W, 2, Color("6a6672"))
	gradv(0, gy + 16, W, float(H - GROUND - 16), Color("403c4c"), Color("2e2b38"))
	for i: int in 14:
		R(float(i * 48 + 8), gy + 25, 22, 2, Color("e2c868"))
	for lx: float in [12.0, 628.0]:
		item(lx - 1, gy - 46, 3, 50, Color("46404e"), 1)
		item(lx - 6, gy - 50, 12, 5, Color("5a5260"), 2)
		if night:
			GR(lx - 5, gy - 46, 10, 2, WARM)
			_lamp(lx, gy - 44, 56.0, 1.0, true)
			pool(lx, gy + 8, 30, 5, WARM, 0.5)
		else:
			R(lx - 5, gy - 46, 10, 2, Color("e8e2d0"))
	for bx: float in [4.0, 620.0]:
		item(bx - 3, gy - 9, 14, 13, Color("4a8a4e"), 6.0)
		R(bx + 1, gy - 6, 3, 2, Color("78b86a"))
	var cx: float = 360.0
	var cy: float = gy + 26.0
	shadow(cx + 20, cy + 3, 22, 0.6)
	item(cx, cy - 8, 40, 9, Color("c8453c"), 3)
	item(cx + 9, cy - 15, 20, 8, Color("b83c34"), 3)
	R(cx + 11, cy - 13, 7, 5, Color("a8d4e8"))
	R(cx + 20, cy - 13, 7, 5, Color("a8d4e8"))
	for wx: float in [cx + 8.0, cx + 31.0]:
		ell(wx, cy + 1, 4, 4, Color("1e1a22"))
		ell(wx, cy + 1, 1.6, 1.6, Color("b8b4c0"))
	if night:
		GR(cx + 38, cy - 6, 3, 3, Color("fff2b0"))
		GR(cx - 1, cy - 6, 2, 3, Color("ff4030"))
		_lamp(cx + 52, cy - 4, 34.0, 0.7, true)
		pool(cx + 52, cy - 3, 20, 4, WARM, 0.45)


func _roof() -> void:
	var y: float = float(TOP - 12)
	item(float(BX0 - 4), y, float(BX1 - BX0 + 8), 6, Color("6a6070"), 1)
	item(float(BX0 - 2), y + 6, float(BX1 - BX0 + 4), 6, Color("554c5e"), 1)
	for i: int in 37:
		R(float(BX0 + i * 16), y + 7, 1, 4, Color("3a3340"))
	item(60, y - 22, 28, 22, Color("8a5a3c"), 3)
	for i: int in 3:
		R(60, y - 18 + float(i * 6), 28, 1, Color("5a3a28"))
	item(58, y - 26, 32, 5, Color("6a4430"), 2)
	item(480, y - 14, 34, 14, Color("7a8090"), 2)
	for i: int in 5:
		R(484 + float(i * 6), y - 10, 3, 8, Color("4a4e5c"))
	R(330, y - 52, 2, 52, Color("54505c"))
	ln(Vector2(331, y - 40), Vector2(318, y), Color("54505c"), 1.0)
	ln(Vector2(331, y - 40), Vector2(344, y), Color("54505c"), 1.0)
	ln(Vector2(331, y - 28), Vector2(322, y), Color("54505c"), 1.0)
	ln(Vector2(331, y - 28), Vector2(340, y), Color("54505c"), 1.0)
	if night:
		GR(329, y - 56, 4, 4, Color("ff3a2a"))
		pool(331, y - 54, 9, 9, Color("ff3a2a"), 0.7)
	else:
		R(329, y - 56, 4, 4, Color("c83a30"))


# ---------------------------------------------------------------- shell, slabs, occluders

func _shell() -> void:
	for side: int in 2:
		var x: float = float(BX0) if side == 0 else float(BX1 - 8)
		gradv(x, float(TOP), 8, float(4 * FH), Color("8a7d86"), Color("6a5f6c"))
		for r: int in (4 * FH) / 8:
			var ox: float = 0.0 if r % 2 == 0 else 4.0
			R(x, float(TOP + r * 8), 8, 1, Color("52485a"))
			R(x + ox + 3.0, float(TOP + r * 8), 1, 8, Color("52485a"))
		R(x + (7.0 if side == 0 else 0.0), float(TOP), 1, float(4 * FH), Color("4a4050"))
		R(x + (0.0 if side == 0 else 7.0), float(TOP), 1, float(4 * FH), Color("b4a8b0"))
		occluders.append([x, float(TOP), 8.0, float(4 * FH)])


func _slabs() -> void:
	for r: int in 4:
		var y: float = _ytop(r) + 60.0
		var cuts: Array = [[float(SHAFT_X), float(ESC_X)]]
		if r < 3:  # the flight below opens onto a landing at one end only
			cuts.append([float(STAIR_X), float(STAIR_X + 64)] if r % 2 == 0 else [float(STAIR_X + 16), float(SHAFT_X)])
		if r == 2:
			cuts.append([float(ESC_X + 16), float(ROOM_X)])
		var xs: Array = [float(BX0 + 8)]
		for c: Array in cuts:
			xs.append(float(c[0]))
			xs.append(float(c[1]))
		xs.append(float(BX1 - 8))
		xs.sort()
		var i: int = 0
		while i + 1 < xs.size():  # pairs (start, cut 1 start), (cut 1 end, cut 2 start), ...
			_slab_seg(float(xs[i]), y, float(xs[i + 1]) - float(xs[i]))
			i += 2


func _slab_seg(x: float, y: float, w: float) -> void:
	if w <= 0.0:
		return
	gradv(x, y, w, 4, SLAB_C.lightened(0.12), SLAB_C.darkened(0.2))
	R(x, y, w, 1, SLAB_C.lightened(0.35))
	occluders.append([x, y, w, 4.0])


# ---------------------------------------------------------------- room scaffolding

## Dark at night if the room's lamps are off. G uses real light instead.
func _room_state(lit_night: bool) -> void:
	_dark = 0.0
	if night and not lit_night and not _lighting():
		_dark = 0.85


func _lamp(cx: float, cy: float, radius: float, energy: float, on: bool) -> void:
	if not on:
		return
	if _lighting():
		if pass_layer == Layer.WORLD and night:  # the compatibility renderer lights at most 16 sources per item
			lights.append([cx, cy, radius, energy, WARM])
	elif night:
		pool(cx, cy + radius * 0.35, radius * 0.9, radius * 0.55, WARM, 0.55)


## Back wall, cornice, dado rail, skirting and floor for one room cell.
func _shell_room(x: float, row: int, w: float, wall: Color, dado: Color, floor_c: Color, floor_alt: Color, trim: Color) -> void:
	var y: float = _ytop(row)
	gradv(x, y, w, 56, wall.lightened(0.07), wall.darkened(0.06))
	var i: int = 0
	while float(i * 12) < w:
		R(x + float(i * 12), y + 4, 1, 34, wall.darkened(0.045))
		i += 1
	R(x, y, w, 3, trim)
	R(x, y + 1, w, 1, trim.lightened(0.25))
	R(x, y + 3, w, 1, trim.darkened(0.3))
	R(x, y + 38, w, 18, dado)
	R(x, y + 38, w, 1, dado.lightened(0.3))
	R(x, y + 39, w, 1, dado.darkened(0.25))
	var j: int = 0
	while float(j * 16) < w:
		R(x + float(j * 16) + 15.0, y + 40, 1, 14, dado.darkened(0.18))
		j += 1
	R(x, y + 54, w, 2, trim.darkened(0.12))
	R(x, y + 56, w, 4, floor_c)
	var k: int = 0
	while float(k * 12) < w:
		R(x + float(k * 12) + float(row % 2 * 5), y + 56, 6, 4, floor_alt)
		k += 1
	R(x, y + 56, w, 1, floor_c.lightened(0.25))
	R(x, y + 3, 1, 53, wall.darkened(0.35))
	R(x + w - 1, y + 3, 1, 53, wall.darkened(0.35))
	occluders.append([x - 1.0, y, 2.0, 60.0])
	occluders.append([x + w - 1.0, y, 2.0, 60.0])


## A faint warm wash over a lit room at night (unlit styles only; G has real lights).
func _room_glow(x: float, row: int, w: float, lit: bool) -> void:
	if lit and night and not _lighting():
		wash(x + 1, _ytop(row) + 4, w - 2, 52, WARM, 0.07 if _smooth() else 0.0, true)


func _ceiling_light(cx: float, y: float, w: float, on: bool, radius: float = 70.0) -> void:
	item(cx - w * 0.5, y + 3, w, 3, Color("d8d2c8"), 1, false)
	if on:
		GR(cx - w * 0.5 + 2, y + 5, w - 4, 2, Color("fff6d8"))
	else:
		R(cx - w * 0.5 + 2, y + 5, w - 4, 2, Color("b8b2a8"))
	_lamp(cx, y + 8, radius, 1.0, on)


func _plant(x: float, fy: float, h: float, pot: Color) -> void:
	shadow(x, fy, 7, 0.5)
	item(x - 5, fy - 9, 10, 9, pot, 2)
	R(x - 5, fy - 9, 10, 2, pot.darkened(0.25))
	var leaf: Color = Color("3f8a52")
	var n: int = 7
	for i: int in n:
		var a: float = -PI * 0.5 + (float(i) - float(n - 1) * 0.5) * 0.42
		var l: float = h * (0.55 + 0.4 * hn(i, int(x)))
		var tip: Vector2 = Vector2(x + cos(a) * l * 0.7, fy - 9 + sin(a) * l)
		ln(Vector2(x, fy - 9), tip, leaf.darkened(0.1 * float(i % 3)), 2.0)
		ell(tip.x, tip.y, 3, 2, leaf.lightened(0.12))


# ---------------------------------------------------------------- people

## A person about 12 wide and 32 tall. pose: 0 stand, 1 walk, 2 sit. dir is -1 or 1.
func person(cx: float, fy: float, pose: int, look_i: int, dir: int) -> void:
	var lk: Array = LOOKS[look_i % LOOKS.size()]
	var skin: Color = lk[0]
	var hair: Color = lk[1]
	var hs: int = lk[2]
	var shirt: Color = lk[3]
	var pants: Color = lk[4]
	var shoe: Color = lk[5]
	var d: float = float(dir)
	shadow(cx, fy + 0.5, 6, 0.55)
	var torso_y: float
	if pose == 2:  # seated on a chair, facing dir
		var hip: float = fy - 9.0
		item(cx - 4.0 if dir > 0 else cx - 5.0, hip - 3, 9, 4, pants, 1.5)
		var knee_x: float = cx + d * 5.0
		item(knee_x - 1.5, hip - 3, 3, 11, pants, 1.0)
		item(knee_x - 2.0 + (1.0 if dir > 0 else 0.0), fy - 2, 4, 2, shoe, 0.5, false)
		torso_y = hip - 13.0
		item(cx - 4, torso_y, 8, 12, shirt, 2.5)
		item(cx + d * 2.0 - 1.0, hip - 11, 2, 7, shirt.darkened(0.1), 1.0)
		R(cx + d * 4.0 - 1.0, hip - 5, 2, 2, skin)
	else:
		var sw: float = 1.5 if pose == 1 else 0.0
		item(cx - 4 - sw, fy - 12, 3, 10, pants, 1.0)
		item(cx + 1 + sw, fy - 12, 3, 10, pants, 1.0)
		item(cx - 5 - sw, fy - 3, 5, 3, shoe, 1.0, false)
		item(cx + 0.5 + sw, fy - 3, 5, 3, shoe, 1.0, false)
		torso_y = fy - 24.0
		item(cx - 4, torso_y, 8, 13, shirt, 2.5)
		R(cx - 4, torso_y + 10, 8, 1, pants.darkened(0.1))
		var as_: float = 2.0 if pose == 1 else 0.0
		item(cx - 6.5, torso_y + 1 + as_ * 0.5, 2, 9, shirt.darkened(0.08), 1.0)
		item(cx + 4.5, torso_y + 1 - as_ * 0.5, 2, 9, shirt.darkened(0.08), 1.0)
		R(cx - 6.5, torso_y + 9 + as_ * 0.5, 2, 2, skin)
		R(cx + 4.5, torso_y + 9 - as_ * 0.5, 2, 2, skin)
	_head(cx, torso_y - 4.0, skin, hair, hs, d)


func _head(cx: float, cy: float, skin: Color, hair: Color, hs: int, d: float) -> void:
	R(cx - 1.5, cy + 3, 3, 3, skin.darkened(0.12))
	if hs == 1:  # long hair falls behind the shoulders
		item(cx - 5, cy - 3, 10, 12, hair, 3.0, false)
	ell(cx, cy, 4.0, 4.6, skin)
	match hs:
		0, 1:
			ell(cx, cy - 2.2, 4.4, 3.2, hair)
			R(cx - 4.2, cy - 2, 2, 4, hair)
			R(cx + 2.2, cy - 2, 2, 4, hair)
		2:
			ell(cx, cy - 3.6, 3.0, 1.2, hair)
		3:
			ell(cx, cy - 2.4, 4.3, 3.0, hair)
			ell(cx - d * 3.2, cy - 5.0, 2.2, 2.2, hair)
	var ex: float = cx + d * 1.2
	R(ex - 2.0, cy - 0.5, 1, 1.4, INK)
	R(ex + 1.0, cy - 0.5, 1, 1.4, INK)
	R(ex - 0.5, cy + 2.2, 2, 1, skin.darkened(0.35))


## Someone asleep: head on a pillow facing up, shoulders. The caller draws the blanket.
func sleeper(hx: float, hy: float, look_i: int) -> void:
	var lk: Array = LOOKS[look_i % LOOKS.size()]
	var skin: Color = lk[0]
	item(hx + 3, hy - 3, 9, 8, lk[3], 3.0, false)
	if int(lk[2]) == 1:
		item(hx - 6, hy - 4, 8, 7, lk[1], 3.0, false)
	ell(hx, hy, 4.4, 4.4, skin)
	ell(hx - 1.5, hy - 1.8, 4.2, 3.0, lk[1])
	R(hx - 1.5, hy - 0.3, 2, 1, INK)
	R(hx + 1.5, hy - 0.3, 2, 1, INK)
	R(hx, hy + 2.2, 2, 1, skin.darkened(0.35))


func _zzz(x: float, y: float) -> void:
	var col: Color = Color("e8ecff")
	for i: int in 3:
		var s: float = 3.0 + float(i) * 1.5
		var zx: float = x + float(i) * 7.0
		var zy: float = y - float(i) * 6.0
		if _smooth():
			draw_polyline(PackedVector2Array([Vector2(zx, zy), Vector2(zx + s, zy), Vector2(zx, zy + s), Vector2(zx + s, zy + s)]), col, 0.9, true)
		else:
			GR(zx, zy, s, 1, col)
			GR(zx, zy + s, s, 1, col)
			for k: int in int(s):
				GR(zx + s - float(k), zy + float(k), 1, 1, col)


# ---------------------------------------------------------------- stairs

func _stairs() -> void:
	for r: int in 4:
		var y: float = _ytop(r)
		var fy: float = _fy(r)
		_dark = 0.0
		var right_up: bool = (3 - r) % 2 == 0  # the ground flight climbs right, the next climbs left
		gradv(float(STAIR_X), y, 80, 56, Color("6f7694"), Color("565c78"))
		R(float(STAIR_X), y, 80, 3, Color("8d93ae"))
		R(float(STAIR_X), y + 3, 80, 1, Color("3e4358"))
		for i: int in 5:
			R(float(STAIR_X + 16 + i * 16) - 1, y + 4, 1, 50, Color("5a6080"))
		R(float(STAIR_X), y + 54, 80, 2, Color("3e4358"))
		R(float(STAIR_X), y + 56, 80, 4, Color("8a8498"))
		R(float(STAIR_X), y + 56, 80, 1, Color("aaa4b8"))
		var ox: float = float(STAIR_X) if right_up else float(STAIR_X + 16)
		for i: int in 8:
			var sx: float = ox + float(i * 8) if right_up else ox + float(7 - i) * 8.0
			var top_y: float = fy - float(i + 1) * 8.0
			var body_h: float = minf(fy - top_y - 8.0, 12.0)
			if body_h > 0.0:  # solid underside, stepped
				R(sx, top_y + 8.0, 8, body_h, Color("6a585c"))
				R(sx, top_y + 8.0, 8, 1, Color("52403f"))
			R(sx, top_y + 3, 8, 5, Color("7d6a6c"))
			R(sx, top_y + 3, 8, 1, Color("5a484c"))
			item(sx, top_y, 8, 3, Color("c2b0a4"), 0.5, false)
			R(sx, top_y, 8, 1, Color("e8d8cc"))
		# handrail: 20 px above the tread nose, kept under the ceiling, with posts
		var rail_hi: float = y + 6.0
		var a: Vector2 = Vector2(ox, maxf(fy - 28.0, rail_hi)) if right_up else Vector2(ox + 64.0, maxf(fy - 28.0, rail_hi))
		var b: Vector2 = Vector2(ox + 64.0, maxf(fy - 84.0, rail_hi)) if right_up else Vector2(ox, maxf(fy - 84.0, rail_hi))
		ln(a, b, Color("3a2e2c"), 2.0)
		for i: int in 9:
			var px: float = ox + float(i * 8)
			var nose: float = fy - 8.0 - float(i) * 8.0 if right_up else fy - 8.0 - float(8 - i) * 8.0
			var ry: float = maxf(nose - 20.0, rail_hi)
			if nose - ry > 2.0:
				R(px, ry, 1, nose - ry, Color("484050"))
		var sgx: float = float(SHAFT_X - 14) if right_up else float(STAIR_X + 6)
		R(sgx - 1, y + 6, 12, 7, Color("2a3a30"))
		GR(sgx, y + 7, 10, 5, Color("5ae08a"))
		R(sgx + 3, y + 9, 4, 1, Color("1a3a28"))
	if _lighting() and pass_layer == Layer.WORLD and night:  # two lights cover the four flights
		lights.append([float(STAIR_X + 40), float(TOP + FH), 100.0, 0.9, WARM])
		lights.append([float(STAIR_X + 40), float(TOP + 3 * FH), 100.0, 0.9, WARM])
	person(float(STAIR_X + 60), _fy(3) - 32.0, 1, 4, 1)
	person(float(STAIR_X + 44), _fy(1) - 32.0, 1, 1, 1)


# ---------------------------------------------------------------- elevator shaft

func _shaft() -> void:
	var x: float = float(SHAFT_X)
	_dark = 0.0
	gradv(x, float(TOP), 48, float(4 * FH), Color("1c212c"), Color("2a303e"))
	R(x + 4, float(TOP), 3, float(4 * FH), Color("5a6274"))
	R(x + 4, float(TOP), 1, float(4 * FH), Color("8a92a6"))
	R(x + 41, float(TOP), 3, float(4 * FH), Color("5a6274"))
	R(x + 41, float(TOP), 1, float(4 * FH), Color("8a92a6"))
	for r: int in 4:
		var fy: float = _fy(r)
		item(x + 8, fy - 36, 32, 36, Color("565e70"), 1.0)
		R(x + 24, fy - 35, 1, 35, Color("2a303e"))
		R(x + 8, fy - 36, 32, 1, Color("8a92a6"))
		R(x + 18, fy - 42, 12, 4, Color("1a1e28"))
		var on: bool = r == 1
		GR(x + 19.0 + (0.0 if on else 4.0), fy - 41, 4 if on else 2, 2, Color("ffb840") if on else Color("5a4a2a"))
		R(x, _ytop(r) + 56, 48, 4, Color("3a4052"))
	item(x + 8, float(TOP + 6), 8, 22, Color("6a707e"), 1.0)  # counterweight
	for i: int in 4:
		R(x + 9, float(TOP + 9 + i * 5), 6, 1, Color("4a505e"))
	# the car at the condo floor
	var cy: float = _fy(1) - 38.0
	var cx: float = x + 9.0
	ln(Vector2(x + 18, float(TOP)), Vector2(x + 18, cy - 4), Color("90969e"), 1.0)
	ln(Vector2(x + 30, float(TOP)), Vector2(x + 30, cy - 4), Color("90969e"), 1.0)
	item(cx - 1, cy - 4, 32, 5, Color("606878"), 1.0)
	item(cx, cy, 30, 40, Color("a4acb8"), 1.5)
	R(cx + 2, cy + 2, 26, 36, Color("f0e0b0"))
	R(cx + 2, cy + 24, 26, 1, Color("c8b486"))
	R(cx + 2, cy + 25, 26, 13, Color("d8c490"))
	R(cx + 14, cy + 2, 1, 36, Color("d0bd88"))
	GR(cx + 8, cy + 2, 14, 2, Color("fffbe8"))
	GW(cx + 2, cy + 2, 26, 36, Color(0.3, 0.22, 0.08))
	_lamp(cx + 15, cy + 6, 44.0, 0.9, true)
	person(cx + 9, cy + 37, 0, 3, 1)
	person(cx + 21, cy + 37, 0, 0, -1)
	R(cx + 2, cy + 38, 26, 2, Color("6a6070"))


# ---------------------------------------------------------------- escalator

func _escalator() -> void:
	var x0: float = float(ESC_X)
	var yb: float = _fy(3)
	var yt: float = _fy(2)
	_dark = 0.0
	_shell_room(x0, 3, 64.0, Color("e6dac2"), Color("b8a27c"), Color("d8d0c4"), Color("a8a0a8"), Color("c8ad6a"))
	poly(PackedVector2Array([Vector2(x0, yb + 1), Vector2(x0 + 64, yt + 1), Vector2(x0 + 64, yt + 15), Vector2(x0 + 14, yb + 1)]), Color("424a5e"))
	ln(Vector2(x0, yb), Vector2(x0 + 64, yt), Color("8a94ac"), 2.0)
	for i: int in 16:
		var sx: float = x0 + float(i * 4)
		var sy: float = yb - float(i * 4)
		R(sx, sy - 3, 4, 1, Color("c8ccd8"))
		R(sx, sy - 2, 3, 2, Color("7a8298"))
		R(sx + 3, sy - 2, 1, 2, Color("3a4054"))
	var top_off: float = 24.0
	poly(PackedVector2Array([Vector2(x0 + 2, yb - top_off + 2), Vector2(x0 + 62, yt - top_off + 2), Vector2(x0 + 62, yt - 4), Vector2(x0 + 2, yb - 4)]), Color(0.75, 0.88, 0.95, 0.35))
	ln(Vector2(x0, yb - top_off), Vector2(x0 + 64, yt - top_off), Color("23202a"), 3.0)
	ln(Vector2(x0, yb - top_off - 1), Vector2(x0 + 64, yt - top_off - 1), Color("5a5664"), 1.0)
	for i: int in 5:
		var px: float = x0 + 4.0 + float(i) * 14.0
		var py: float = yb - 4.0 - (px - x0)
		R(px, py - top_off + 4.0, 1, top_off - 6.0, Color("9aa4b8"))
	person(x0 + 26, yb - 25.0, 0, 2, 1)
	R(x0 + 48, yt, 16, 3, Color("8a94ac"))
	for i: int in 8:
		R(x0 + 48 + float(i * 2), yt, 1, 3, Color("3a4054"))


func _vestibule() -> void:
	var x0: float = float(ESC_X)
	_dark = 0.0
	_shell_room(x0, 2, 64.0, Color("c6d2cc"), Color("86a096"), Color("7a8aa0"), Color("6a7a92"), Color("a8b8b0"))
	var fy: float = _fy(2)
	var gx: float = x0 + 12.0
	poly(PackedVector2Array([Vector2(gx, fy - 22), Vector2(gx + 36, fy - 22), Vector2(gx + 36, fy), Vector2(gx, fy)]), Color(0.75, 0.9, 0.95, 0.28))
	ln(Vector2(gx, fy - 22), Vector2(gx + 36, fy - 22), Color("23202a"), 2.0)
	R(gx, fy - 22, 2, 22, Color("8a94ac"))
	R(gx + 34, fy - 22, 2, 22, Color("8a94ac"))
	R(x0 + 4, _ytop(2) + 12, 4, 20, Color("3a4054"))
	R(x0 + 5, _ytop(2) + 14, 2, 8, Color("c83a30"))
	_plant(x0 + 56, fy, 22.0, Color("c8785a"))
	person(x0 + 8, fy, 0, 5, 1)


# ---------------------------------------------------------------- rooms

func _room_lobby() -> void:
	var x: float = float(ROOM_X)
	var w: float = float(BX1 - 8) - x
	var row: int = 3
	_room_state(true)
	_shell_room(x, row, w, Color("eadfc8"), Color("b99f74"), Color("e8e2d8"), Color("b0aaa8"), Color("c9a85c"))
	var fy: float = _fy(row)
	var y: float = _ytop(row)
	for i: int in int(w / 8.0):
		if i % 2 == 0:
			R(x + float(i * 8), y + 58, 8, 2, Color("9a948f"))
	for px: float in [x + 100.0, x + 200.0, x + 300.0]:
		item(px, y + 4, 6, 52, Color("d8c8a4"), 1.0, false)
		R(px - 1, y + 4, 8, 3, Color("c9a85c"))
		R(px - 1, y + 53, 8, 3, Color("c9a85c"))
	for lx: float in [x + 40.0, x + 150.0, x + 250.0, x + 350.0]:
		R(lx, y + 4, 1, 8, Color("8a7a60"))
		ell(lx, y + 15, 5, 5, Color("f4e8c8"))
		GR(lx - 3, y + 12, 6, 6, Color("fff2c8"))
		_lamp(lx, y + 15, 76.0, 1.0, true)
	item(x + 14, y + 12, 22, 28, Color("2e3a52"), 1.5)
	for i: int in 5:
		R(x + 17, y + 16 + float(i * 5), 5.0 + floorf(hn(i, 9) * 8.0), 2, Color("e8d8a0"))
	# front desk with a receptionist
	var dx: float = x + 74.0
	person(dx + 24, fy - 6.0, 0, 5, 1)
	shadow(dx + 36, fy, 40, 0.55)
	item(dx, fy - 20, 72, 20, Color("8a5a3c"), 2.0)
	item(dx - 2, fy - 24, 76, 5, Color("c89a62"), 2.0)
	R(dx + 4, fy - 17, 64, 1, Color("c9a85c"))
	for i: int in 5:
		item(dx + 6 + float(i * 12), fy - 15, 9, 11, Color("6a4430"), 1.0, false)
	item(dx + 46, fy - 34, 14, 9, Color("3a4052"), 1.0)
	GR(dx + 47, fy - 33, 12, 6, Color("78c8e8"))
	R(dx + 51, fy - 25, 4, 2, Color("2a2f3c"))
	item(dx + 6, fy - 31, 4, 7, Color("c9a85c"), 1.5)
	# sofa, side table and a seated visitor
	var sx: float = x + 188.0
	shadow(sx + 28, fy, 32, 0.5)
	item(sx, fy - 17, 56, 17, Color("3f6f8c"), 4.0)
	item(sx - 3, fy - 24, 62, 9, Color("4a82a2"), 4.0)
	item(sx + 2, fy - 16, 24, 8, Color("558cac"), 3.0, false)
	item(sx + 30, fy - 16, 24, 8, Color("558cac"), 3.0, false)
	person(sx + 16, fy - 6.0, 2, 3, 1)
	item(sx + 66, fy - 9, 24, 3, Color("a87850"), 1.0)
	R(sx + 69, fy - 6, 2, 6, Color("5a3a28"))
	R(sx + 85, fy - 6, 2, 6, Color("5a3a28"))
	item(sx + 74, fy - 14, 7, 5, Color("f2eadc"), 1.5, false)
	_plant(x + 16, fy, 34.0, Color("a8683c"))
	_plant(x + 332.0, fy, 30.0, Color("7a5a8a"))
	# revolving door on the right
	var rx: float = float(BX1 - 8) - 46.0
	item(rx, y + 6, 40, 52, Color("7a8aa0"), 3.0)
	_door_glass(rx + 3, y + 9, 34, 49)
	person(rx - 22, fy, 1, 1, 1)
	person(x + 156, fy, 1, 0, 1)
	item(x + 160, fy - 11, 5, 4, Color("6a4430"), 1.0, false)
	person(x + 288, fy, 0, 2, -1)
	_room_glow(x, row, w, true)


func _door_glass(x: float, y: float, w: float, h: float) -> void:
	var c1: Color = Color("dff2ff") if not night else Color("22306a")
	var c2: Color = Color("bfe0f0") if not night else Color("5a3f6a")
	gradv(x, y, w, h, c1, c2, true)
	var cx: float = x + w * 0.5
	ln(Vector2(cx, y), Vector2(cx, y + h), Color("2a303e"), 2.0)
	ln(Vector2(x + 2, y + h - 12), Vector2(x + w - 2, y + 12), Color("2a303e"), 2.0)
	R(x, y + h - 6, w, 6, Color("5a6478"))


func _room_office(x: float, w: float, idx: int) -> void:
	var row: int = 2
	_room_state(idx == 0)
	var y: float = _ytop(row)
	var fy: float = _fy(row)
	_shell_room(x, row, w, Color("bccdc3"), Color("86a196"), Color("6e7f96"), Color("5f6f86"), Color("a9bab1"))
	var lights_on: bool = idx == 0 or not night
	for lx: float in [x + 48.0, x + 144.0]:
		_ceiling_light(lx, y, 36.0, lights_on, 64.0)
	_window(x + 78, y + 12, 38, 22, Color("e8e2d4"), Color("b86a5a") if idx == 0 else Color("5a7aa0"), idx + 3, idx == 1)
	if idx == 0:
		item(x + 14, y + 16, 18, 14, Color("f4f0e6"), 1.0)
		R(x + 17, y + 20, 8, 1, Color("c83a30"))
		R(x + 17, y + 23, 11, 1, Color("3f7fb0"))
		R(x + 17, y + 26, 6, 1, Color("2a2f3c"))
	else:
		item(x + 14, y + 14, 18, 18, Color("e8b458"), 1.5)
		item(x + 17, y + 17, 12, 12, Color("c8453c"), 1.0, false)
		ell(x + 23, y + 23, 3, 3, Color("f6e8c8"))
	for d: int in 2:
		var occupied: bool = (idx == 0 and d == 0) or (idx == 1 and d == 1 and not night)
		_desk(x + 16.0 + float(d) * 84.0, fy, occupied, d + idx * 2, lights_on)
	var fx: float = x + w - 28.0
	shadow(fx + 7, fy, 10, 0.5)
	item(fx, fy - 26, 14, 26, Color("8a94a4"), 1.5)
	for i: int in 3:
		R(fx + 2, fy - 24 + float(i * 8), 10, 1, Color("5a6272"))
		R(fx + 5, fy - 21 + float(i * 8), 4, 1, Color("d8dce4"))
	item(fx + 15, fy - 26, 8, 16, Color("a4d4f0"), 3.0)
	item(fx + 14, fy - 10, 10, 10, Color("e8ecf0"), 2.0)
	_plant(x + 10, fy, 20.0, Color("7a5a8a"))
	_room_glow(x, row, w, idx == 0)


func _desk(dx: float, fy: float, occupied: bool, look_i: int, powered: bool) -> void:
	shadow(dx + 30, fy, 32, 0.5)
	if occupied:
		person(dx + 52, fy, 2, look_i, -1)
	item(dx + 55, fy - 20, 4, 16, Color("3a4a62"), 2.0)
	item(dx + 44, fy - 11, 14, 3, Color("4a5a76"), 1.5)
	R(dx + 50, fy - 8, 2, 8, Color("2a2f3c"))
	item(dx, fy - 21, 44, 3, Color("c89a62"), 1.0)
	item(dx + 2, fy - 18, 4, 18, Color("8a5f3a"), 0.0, false)
	item(dx + 34, fy - 18, 8, 18, Color("a87a4c"), 1.0)
	R(dx + 36, fy - 12, 4, 1, Color("e8d098"))
	item(dx + 6, fy - 34, 14, 11, Color("2a3140"), 1.5)
	if powered:
		GR(dx + 7, fy - 33, 12, 8, Color("8ad0f0"))
		GR(dx + 8, fy - 31, 8, 1, Color("e8f8ff"))
		GR(dx + 9, fy - 29, 6, 1, Color("5aa4d0"))
	else:
		R(dx + 7, fy - 33, 12, 8, Color("1a2030"))
	R(dx + 11, fy - 23, 4, 2, Color("2a2f3c"))
	item(dx + 8, fy - 23, 12, 2, Color("e0dcd2"), 0.5, false)
	R(dx + 28, fy - 28, 1, 7, Color("3a3a44"))
	item(dx + 25, fy - 31, 7, 4, Color("e8b458"), 1.5, false)
	item(dx + 22, fy - 24, 6, 3, Color("f4f0e6"), 0.0, false)


func _room_condo_a() -> void:
	var x: float = 160.0
	var w: float = 224.0
	var row: int = 1
	_room_state(true)
	_shell_room(x, row, w, Color("dcc0cc"), Color("a8788e"), Color("8f6a4a"), Color("7c5a3e"), Color("e8d8d0"))
	var y: float = _ytop(row)
	var fy: float = _fy(row)
	_window(x + 150, y + 10, 40, 26, Color("f0e8dc"), Color("c8606a"), 7)
	item(x + 18, fy - 3, 90, 5, Color("8aa0c8"), 2.0, false)
	for i: int in 9:
		R(x + 22 + float(i * 10), fy - 2, 5, 3, Color("a8b8d8"))
	var bx: float = x + 22.0
	shadow(bx + 36, fy, 42, 0.55)
	item(bx, fy - 26, 5, 26, Color("7a4e32"), 1.5)
	item(bx + 4, fy - 12, 70, 10, Color("8a5a3c"), 2.0)
	item(bx + 4, fy - 17, 68, 7, Color("f4eee2"), 3.0)
	item(bx + 8, fy - 21, 16, 7, Color("fffaf0"), 3.0)
	sleeper(bx + 16, fy - 21.0, 1)
	item(bx + 26, fy - 21, 46, 9, Color("5a7fb4"), 3.0)
	for i: int in 6:
		R(bx + 30 + float(i * 7), fy - 20, 3, 7, Color("7a9ccc"))
	R(bx + 4, fy - 12, 70, 1, Color("c8a070"))
	_zzz(bx + 14, fy - 32)
	var nx: float = bx + 78.0
	item(nx, fy - 14, 14, 14, Color("a87a4c"), 1.5)
	R(nx + 2, fy - 9, 10, 1, Color("5a3a28"))
	R(nx + 6, fy - 7, 2, 1, Color("e8d098"))
	R(nx + 6, fy - 22, 2, 8, Color("c9a85c"))
	item(nx + 2, fy - 28, 10, 7, Color("f4d8a0"), 2.0, false)
	GR(nx + 4, fy - 26, 6, 3, Color("ffe6a8"))
	_lamp(nx + 7, fy - 24, 74.0, 1.0, true)
	var wx: float = x + 124.0
	shadow(wx + 16, fy, 20, 0.5)
	item(wx, fy - 44, 26, 44, Color("7a5238"), 2.0)
	R(wx + 12, fy - 43, 1, 42, Color("4a3020"))
	R(wx + 9, fy - 24, 2, 5, Color("e8c88a"))
	R(wx + 15, fy - 24, 2, 5, Color("e8c88a"))
	item(x + 16, y + 10, 24, 16, Color("e8d8c8"), 1.5)
	R(x + 20, y + 14, 8, 8, Color("c8606a"))
	R(x + 30, y + 17, 6, 5, Color("5a7fb4"))
	var tx: float = x + 196.0
	shadow(tx + 12, fy, 16, 0.5)
	item(tx, fy - 14, 24, 14, Color("5a8a6a"), 3.0)
	item(tx + 16, fy - 28, 6, 14, Color("6a9a7a"), 3.0, false)
	_room_glow(x, row, w, true)


func _room_condo_b() -> void:
	var x: float = 384.0
	var w: float = 224.0
	var row: int = 1
	_room_state(false)
	_shell_room(x, row, w, Color("d8c0b8"), Color("9a6e5c"), Color("a89a88"), Color("988a78"), Color("eee4dc"))
	var y: float = _ytop(row)
	var fy: float = _fy(row)
	_window(x + 24, y + 10, 36, 26, Color("f0e8dc"), Color("5a8a6a"), 9, true)
	var kx: float = x + 90.0
	shadow(kx + 44, fy, 50, 0.55)
	item(kx, fy - 20, 88, 20, Color("eae4d8"), 1.5)
	item(kx - 2, fy - 23, 92, 4, Color("6a6a76"), 1.0)
	for i: int in 4:
		R(kx + 4 + float(i * 22), fy - 17, 18, 1, Color("c4bcae"))
		R(kx + 10 + float(i * 22), fy - 10, 6, 1, Color("8a8478"))
	item(kx + 8, fy - 26, 20, 3, Color("2a2f3c"), 0.5, false)
	item(kx + 8, fy - 46, 40, 4, Color("8a5f3a"), 1.0)
	for i: int in 4:
		item(kx + 10 + float(i * 9), fy - 54, 6, 8, Color("c8a870") if i % 2 == 0 else Color("a8c8b0"), 1.5, false)
	for i: int in 3:
		R(kx + 54 + float(i * 10), y + 10, 1, 10, Color("4a4250"))
		ell(kx + 54 + float(i * 10), y + 24, 4, 4, Color("8a90a0"))
	var fxx: float = x + 188.0
	shadow(fxx + 14, fy, 18, 0.5)
	item(fxx, fy - 50, 28, 50, Color("e8ecf0"), 2.5)
	R(fxx, fy - 32, 28, 1, Color("9aa4b0"))
	R(fxx + 22, fy - 46, 2, 10, Color("8a94a4"))
	R(fxx + 22, fy - 28, 2, 8, Color("8a94a4"))
	var tx: float = x + 40.0
	shadow(tx + 22, fy, 26, 0.5)
	item(tx, fy - 18, 44, 4, Color("a87850"), 1.0)
	R(tx + 4, fy - 14, 3, 14, Color("5a3a28"))
	R(tx + 37, fy - 14, 3, 14, Color("5a3a28"))
	for cxx: float in [tx - 8.0, tx + 46.0]:
		item(cxx, fy - 18, 4, 18, Color("c8845a"), 1.5, false)
		item(cxx - 2, fy - 10, 8, 3, Color("c8845a"), 1.0, false)
	item(tx + 14, fy - 24, 6, 6, Color("c8453c"), 2.5, false)
	ell(tx + 30, fy - 21, 2.5, 2.5, Color("e8b458"))


func _room_restaurant() -> void:
	var x: float = 160.0
	var w: float = 448.0
	var row: int = 0
	_room_state(true)
	_shell_room(x, row, w, Color("cf6b50"), Color("7a3a2e"), Color("8a5a38"), Color("74482e"), Color("f0dcc0"))
	var y: float = _ytop(row)
	var fy: float = _fy(row)
	for wx: float in [x + 20.0, x + 272.0]:
		_window(wx, y + 12, 48, 24, Color("f4ecdc"), Color(0, 0, 0, 0), 11 + int(wx))
		for i: int in 8:
			R(wx - 3 + float(i * 7), y + 4, 7, 4, Color("f4ecdc") if i % 2 == 0 else Color("b8353a"))
	for i: int in int(w / 8.0):
		if i % 2 == 0:
			R(x + float(i * 8), y + 58, 8, 2, Color("5a3a24"))
	for lx: float in [x + 96.0, x + 166.0, x + 236.0]:
		R(lx, y + 4, 1, 12, Color("2a2230"))
		item(lx - 7, y + 16, 14, 6, Color("2a3a54"), 3.0)
		GR(lx - 5, y + 21, 10, 2, Color("fff0c0"))
		_lamp(lx, y + 24, 105.0, 0.85, true)
	item(x + 100, y + 8, 28, 22, Color("2a3a34"), 1.5)
	for i: int in 4:
		R(x + 104, y + 13 + float(i * 4), 8.0 + floorf(hn(i, 21) * 10.0), 1, Color("f0e8d0"))
	# tables first, then diners seated beside them
	for tx: float in [x + 82.0, x + 152.0, x + 222.0]:
		_dining_table(tx, fy)
	person(x + 82.0 - 6.0, fy, 2, 0, 1)
	person(x + 82.0 + 34.0, fy, 2, 3, -1)
	person(x + 222.0 - 6.0, fy, 2, 5, 1)
	person(x + 222.0 + 34.0, fy, 2, 4, -1)
	# the bar with stools and bottles
	var bx: float = x + 340.0
	item(bx + 4, y + 22, 78, 4, Color("7a4e32"), 1.0)
	var bc: Array = [Color("3f8a52"), Color("c8453c"), Color("e8b458"), Color("5a7fb4"), Color("3f8a52"), Color("e8b458")]
	for i: int in 7:
		var c: Color = bc[i % bc.size()]
		item(bx + 8 + float(i * 10), y + 11, 4, 11, c, 1.5, false)
		R(bx + 9 + float(i * 10), y + 8, 2, 3, c.darkened(0.2))
	person(bx + 40, fy - 6.0, 0, 2, -1)
	shadow(bx + 40, fy, 50, 0.55)
	item(bx, fy - 24, 88, 24, Color("5a3524"), 2.0)
	item(bx - 3, fy - 28, 94, 5, Color("c89a62"), 2.0)
	R(bx + 4, fy - 21, 80, 1, Color("c9a85c"))
	for i: int in 8:
		R(bx + 8 + float(i * 10), fy - 18, 4, 14, Color("7a4a32"))
	person(x + 190, fy, 1, 4, 1)
	item(x + 196, fy - 29, 12, 2, Color("c8ccd8"), 0.5, false)
	ell(x + 202, fy - 32, 3, 2.4, Color("f4ecdc"))
	_plant(x + 14, fy, 24.0, Color("a8683c"))
	_plant(x + 430, fy, 22.0, Color("7a5a8a"))
	_room_glow(x, row, w, true)


func _dining_table(tx: float, fy: float) -> void:
	shadow(tx + 14, fy, 22, 0.5)
	item(tx + 12, fy - 16, 4, 16, Color("5a3a28"), 0.0, false)
	R(tx + 6, fy - 2, 16, 2, Color("3a2a22"))
	item(tx - 2, fy - 20, 32, 4, Color("f6ecd6"), 1.5)
	for i: int in 8:
		R(tx - 1 + float(i * 4), fy - 16, 2, 5, Color("e6d8b8"))
	item(tx + 12, fy - 26, 4, 6, Color("a8d4e0"), 1.5, false)
	item(tx + 2, fy - 22, 7, 2, Color("fffaf0"), 1.0, false)
	item(tx + 20, fy - 22, 7, 2, Color("fffaf0"), 1.0, false)
	R(tx + 13, fy - 30, 2, 4, Color("fff0c0"))
	GR(tx + 13, fy - 32, 2, 2, Color("ffd070"))
	for cx: float in [tx - 10.0, tx + 32.0]:
		item(cx, fy - 16, 4, 16, Color("7a4a32"), 1.5, false)
		item(cx - 2.0 if cx < tx else cx - 1.0, fy - 9, 8, 3, Color("a8683c"), 1.0, false)
