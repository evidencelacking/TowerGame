extends RefCounted
## Furniture for the Detailed batch 2 rooms (#303): dining, shops, services and parking, composed in the same
## G Lit style as detail_scenes.gd (the mock-up's restaurant is the model for the dining pieces). Same frame:
## mock-up pixels, x from the room's left wall, feet at fy, every piece a static function on a DetailPrims `p`.
## Pieces that people stand or sit at are centred on the activity spot they serve (see detail_shops.gd).
## Every loop here runs over a fixed count or a width divided by a positive step.

const Scenes := preload("res://scripts/view/detail_scenes.gd")

const WARM: Color = Color("ffcf8a")
const BOTTLES: Array[String] = ["3f8a52", "c8453c", "e8b458", "5a7fb4"]
const GARMENTS: Array[String] = ["c8453c", "f4f0e6", "e0a83a", "5a7fb4", "3f8a52", "8a6ab0"]
const BLOOMS: Array[String] = ["c8453c", "e8b458", "e87aa8", "f4f0e6", "8a6ab0"]


## A pendant lamp on a wire from the ceiling at y; lit it glows and (at night) pools light below.
static func pendant(p: Object, lx: float, y: float, on: bool, radius: float = 70.0, shade: Color = Color("2a3a54")) -> void:
	p.R(lx, y + 4, 1, 12, Color("2a2230"))
	p.item(lx - 7, y + 16, 14, 6, shade, 3.0)
	if on:
		p.GR(lx - 5, y + 21, 10, 2, Color("fff0c0"))
		p.pool(lx, y + 24 + radius * 0.35, radius * 0.9, radius * 0.55, WARM, 0.55)
	else:
		p.R(lx - 5, y + 21, 10, 2, Color("b8b090"))


## A striped awning (two colours) over a window or shopfront.
static func awning(p: Object, x: float, y: float, w: float, a: Color = Color("b8353a"), b: Color = Color("f4ecdc")) -> void:
	for i: int in int(ceil(w / 7.0)):
		var c := b if i % 2 == 0 else a
		var sw := minf(7.0, w - i * 7.0)
		p.R(x + i * 7, y, sw, 4, c)
		p.R(x + i * 7, y + 4, sw, 1, c.darkened(0.3))


## A cafe chair with its back at bx, facing right (dir 1) or left (-1).
static func chair(p: Object, bx: float, fy: float, dir: int, c: Color = Color("7a4a32")) -> void:
	p.item(bx, fy - 16, 4, 16, c, 1.5, false)
	if dir > 0:
		p.item(bx - 2, fy - 9, 8, 3, c.lightened(0.2), 1.0, false)
	else:
		p.item(bx - 3, fy - 9, 8, 3, c.lightened(0.2), 1.0, false)


## A dining table centred on cx with a chair either side, the seats at cx - 20 and cx + 20 (the mock-up's table).
static func dining_table(p: Object, cx: float, fy: float, on: bool, cloth: Color = Color("f6ecd6"), chairs: Color = Color("7a4a32")) -> void:
	var tx := cx - 14.0
	p.shadow(cx, fy, 22, 0.5)
	p.item(tx + 12, fy - 16, 4, 16, Color("5a3a28"), 0.0, false)
	p.R(tx + 6, fy - 2, 16, 2, Color("3a2a22"))
	p.item(tx - 2, fy - 20, 32, 4, cloth, 1.5)
	for i: int in 8:
		p.R(tx - 1 + i * 4, fy - 16, 2, 5, cloth.darkened(0.08))
	p.item(tx + 12, fy - 26, 4, 6, Color("a8d4e0"), 1.5, false)
	p.item(tx + 2, fy - 22, 7, 2, Color("fffaf0"), 1.0, false)
	p.item(tx + 20, fy - 22, 7, 2, Color("fffaf0"), 1.0, false)
	p.R(tx + 13, fy - 30, 2, 4, Color("fff0c0"))
	if on:
		p.GR(tx + 13, fy - 32, 2, 2, Color("ffd070"))
	chair(p, tx - 10, fy, 1, chairs)
	chair(p, tx + 32, fy, -1, chairs)


## A small round table between two seats at c0 and c1, a cafe chair at each; for a cafe or a fast food floor.
static func small_table(p: Object, c0: float, c1: float, fy: float, top: Color, chairs: Color) -> void:
	var cx := (c0 + c1) * 0.5
	p.shadow(cx, fy, 18, 0.5)
	p.R(cx - 1, fy - 14, 3, 14, Color("4a4a56"))
	p.R(cx - 6, fy - 2, 13, 2, Color("3a3a46"))
	p.item(cx - 12, fy - 18, 24, 4, top, 2.0)
	p.item(cx - 3, fy - 25, 5, 7, Color("e8b458"), 1.5, false)
	chair(p, c0 - 4, fy, 1, chairs)
	chair(p, c1 - 1, fy, -1, chairs)


## A bar stool or high stool centred on cx.
static func stool(p: Object, cx: float, fy: float, top: Color = Color("c8453c")) -> void:
	p.shadow(cx, fy, 8, 0.45)
	p.item(cx - 6, fy - 18, 12, 4, top, 2.0, false)
	p.R(cx - 1, fy - 14, 2, 12, Color("3a3a46"))
	p.R(cx - 5, fy - 2, 10, 2, Color("3a3a46"))
	p.R(cx - 4, fy - 8, 8, 1, Color("5a5a66"))


## A booth: a high-backed bench either side of a table, the seats at cx - 22 and cx + 22.
static func booth(p: Object, cx: float, fy: float, seat: Color, top: Color) -> void:
	p.shadow(cx, fy, 34, 0.5)
	p.item(cx - 34, fy - 28, 7, 28, seat.darkened(0.1), 1.5)
	p.item(cx - 34, fy - 10, 24, 10, seat, 2.0)
	p.item(cx + 27, fy - 28, 7, 28, seat.darkened(0.1), 1.5)
	p.item(cx + 10, fy - 10, 24, 10, seat, 2.0)
	p.item(cx - 12, fy - 19, 24, 3, top, 1.0)
	p.R(cx - 1, fy - 16, 2, 16, Color("4a4a56"))
	p.item(cx - 8, fy - 25, 5, 6, Color("c8453c"), 1.5, false)
	p.item(cx + 3, fy - 24, 5, 5, Color("e8b458"), 1.5, false)


## A queue post with a rope stub either side, centred on cx.
static func queue_post(p: Object, cx: float, fy: float, rope: Color = Color("c8453c")) -> void:
	p.shadow(cx, fy, 6, 0.4)
	p.R(cx - 3, fy - 2, 7, 2, Color("5a5a66"))
	p.item(cx - 1, fy - 20, 3, 18, Color("8a94a4"), 0.0, false)
	p.ell(cx, fy - 21, 3, 2, Color("c9a85c"))
	p.R(cx + 2, fy - 17, 8, 2, rope)
	p.R(cx - 9, fy - 17, 8, 2, rope)


## A food counter with a till, a red band and a menu board over it. x is its left edge, y the room's top.
static func food_counter(p: Object, x: float, y: float, fy: float, w: float, on: bool, accent: Color = Color("c8453c")) -> void:
	p.shadow(x + w * 0.5, fy, w * 0.55, 0.55)
	p.item(x, fy - 24, w, 24, Color("e4dccb"), 2.0)
	p.R(x + 1, fy - 8, w - 2, 3, accent)
	p.R(x + 1, fy - 5, w - 2, 1, Color("c9a85c"))
	p.item(x - 2, fy - 28, w + 4, 5, Color("5a5a66"), 1.5)
	p.item(x + 6, fy - 38, 12, 9, Color("2a2f3c"), 1.0)
	if on:
		p.GR(x + 7, fy - 37, 10, 5, Color("8ad0a0"))
	p.item(x + w - 16, fy - 34, 6, 6, Color("f4ecdc"), 2.0, false)
	menu_board(p, x + 2, y + 6, w - 4, 22, on)


## A menu board: dark panel with lines of text and a red and gold item.
static func menu_board(p: Object, x: float, y: float, w: float, h: float, on: bool) -> void:
	p.item(x, y, w, h, Color("2a2f3c"), 1.5)
	if on:
		p.GW(x, y, w, h, Color("ffd070"))
	for i: int in int((h - 4.0) / 5.0):
		p.R(x + 3, y + 3 + i * 5, 6.0 + floorf(p.hn(i, int(x)) * maxf(w - 22.0, 1.0)), 1, Color("f0e8d0"))
		p.R(x + w - 10, y + 3 + i * 5, 6, 1, Color("e8b458"))
	p.ell(x + w - 7, y + h - 5, 3, 2.5, Color("c8453c"))


## A bar counter with a bottle shelf behind it: front panels, a brass rail and a wood top. x is its left edge.
static func bar(p: Object, x: float, y: float, fy: float, w: float, on: bool) -> void:
	p.item(x + 4, y + 22, w - 8, 4, Color("7a4e32"), 1.0)
	for i: int in int((w - 12.0) / 10.0):
		var c := Color(BOTTLES[i % BOTTLES.size()])
		p.item(x + 8 + i * 10, y + 11, 4, 11, c, 1.5, false)
		p.R(x + 9 + i * 10, y + 8, 2, 3, c.darkened(0.2))
	if on:
		p.GW(x + 4, y + 6, w - 8, 20, Color("ffd070"))
	p.shadow(x + w * 0.5, fy, w * 0.55, 0.55)
	p.item(x, fy - 24, w, 24, Color("5a3524"), 2.0)
	p.item(x - 3, fy - 28, w + 6, 5, Color("c89a62"), 2.0)
	p.R(x + 4, fy - 21, w - 8, 1, Color("c9a85c"))
	for i: int in int((w - 8.0) / 10.0):
		p.R(x + 8 + i * 10, fy - 18, 4, 14, Color("7a4a32"))


## A cafe blackboard menu on the wall.
static func chalkboard(p: Object, cx: float, y: float, w: float, h: float) -> void:
	p.item(cx - w * 0.5, y, w, h, Color("2e3a34"), 1.5)
	p.R(cx - w * 0.5 + 2, y + 2, w - 4, 1, Color("6a5a40"))
	for i: int in int((h - 8.0) / 4.0):
		p.R(cx - w * 0.5 + 4, y + 6 + i * 4, 5.0 + floorf(p.hn(i, int(cx)) * maxf(w - 16.0, 1.0)), 1, Color("e8e2d0"))


# ---------------------------------------------------------------- shops

## A shelving unit of w by h with goods on every shelf (colours from the seed). x is its left edge.
static func shelf_unit(p: Object, x: float, fy: float, w: float, h: float, seed_v: int) -> void:
	p.shadow(x + w * 0.5, fy, w * 0.55, 0.5)
	p.item(x, fy - h, w, h, Color("8a5f3a"), 1.5)
	p.R(x + 1, fy - h + 1, w - 2, h - 2, Color("5a3a28"))
	var rows := maxi(int(h / 14.0), 1)
	var step := (h - 4.0) / rows
	for r: int in rows:
		var sy := fy - h + 2 + r * step
		var gx := x + 3.0
		var k := 0
		while gx + 5.0 < x + w - 2.0:
			var bw := minf(4.0 + floorf(p.hn(k + seed_v * 5, r) * 3.0), x + w - 3.0 - gx)
			var bh := 6.0 + floorf(p.hn(k, r + seed_v) * 5.0)
			var c := Color(GARMENTS[(k + r + seed_v) % GARMENTS.size()])
			p.item(gx, sy + step - 2 - bh, bw, bh, c, 1.0, false)
			gx += bw + 1.0
			k += 1
		p.R(x + 1, sy + step - 2, w - 2, 2, Color("a87a4c"))


## A clothes rack on a stand centred on cx, garments hanging.
static func clothes_rack(p: Object, cx: float, fy: float, w: float, seed_v: int) -> void:
	p.shadow(cx, fy, w * 0.5, 0.45)
	p.R(cx - w * 0.5, fy - 40, w, 2, Color("8a94a4"))
	p.R(cx - w * 0.5, fy - 40, 2, 40, Color("8a94a4"))
	p.R(cx + w * 0.5 - 2, fy - 40, 2, 40, Color("8a94a4"))
	p.R(cx - w * 0.5 - 3, fy - 2, 8, 2, Color("5a5a66"))
	p.R(cx + w * 0.5 - 5, fy - 2, 8, 2, Color("5a5a66"))
	for i: int in int((w - 6.0) / 5.0):
		var c := Color(GARMENTS[(i + seed_v) % GARMENTS.size()])
		var drop := 20.0 + floorf(p.hn(i, seed_v) * 8.0)
		p.item(cx - w * 0.5 + 4 + i * 5, fy - 38, 4, drop, c, 0.0, false)
		p.R(cx - w * 0.5 + 4 + i * 5, fy - 38, 4, 2, c.lightened(0.25))


## A display table centred on cx, goods stacked on it.
static func display_table(p: Object, cx: float, fy: float, w: float, seed_v: int) -> void:
	p.shadow(cx, fy, w * 0.55, 0.5)
	p.item(cx - w * 0.5, fy - 18, w, 4, Color("c89a62"), 1.0)
	p.item(cx - w * 0.5 + 2, fy - 14, 3, 14, Color("8a5f3a"), 0.0, false)
	p.item(cx + w * 0.5 - 5, fy - 14, 3, 14, Color("8a5f3a"), 0.0, false)
	for i: int in int((w - 4.0) / 8.0):
		var c := Color(GARMENTS[(i + seed_v) % GARMENTS.size()])
		p.item(cx - w * 0.5 + 3 + i * 8, fy - 26 + (i % 2) * 2, 6, 8 - (i % 2) * 2, c, 1.0, false)


## A shop till counter with a register, a card reader and bags, left edge x.
static func till(p: Object, x: float, fy: float, w: float, on: bool) -> void:
	p.shadow(x + w * 0.5, fy, w * 0.55, 0.55)
	p.item(x, fy - 22, w, 22, Color("a87a4c"), 1.5)
	p.R(x + 2, fy - 12, w - 4, 1, Color("7a5238"))
	p.item(x - 2, fy - 25, w + 4, 4, Color("e8dcc4"), 1.0)
	p.item(x + 4, fy - 36, 12, 10, Color("3a4052"), 1.5)
	if on:
		p.GR(x + 5, fy - 35, 10, 5, Color("8ad0a0"))
	p.item(x + 18, fy - 30, 5, 5, Color("2a2f3c"), 1.0, false)
	p.item(x + w - 14, fy - 35, 8, 10, Color("c8453c"), 1.5, false)
	p.item(x + w - 8, fy - 33, 6, 8, Color("e0a83a"), 1.5, false)


## A wall of TV screens (electronics), x..x+w at y, lit when on.
static func tv_wall(p: Object, x: float, y: float, w: float, h: float, on: bool, seed_v: int) -> void:
	var n := maxi(1, int(w / 28.0))
	var sw := (w - 2.0) / n
	for i: int in n:
		p.item(x + 1 + i * sw, y, sw - 3, h, Color("1a2030"), 1.5)
		if on:
			p.gradv(x + 3 + i * sw, y + 2, sw - 7, h - 4, Color("5aa4d0"), Color("c8e8f8"), true)
			p.GR(x + 3 + i * sw, y + h * 0.5, (sw - 7) * (0.3 + 0.5 * p.hn(i, seed_v)), 2, Color("ffffff"))
		else:
			p.R(x + 3 + i * sw, y + 2, sw - 7, h - 4, Color("10141c"))


## A flower stand centred on cx: tiered buckets with blooms.
static func flower_stand(p: Object, cx: float, fy: float, w: float, seed_v: int) -> void:
	p.shadow(cx, fy, w * 0.55, 0.5)
	p.item(cx - w * 0.5, fy - 12, w, 12, Color("8a5f3a"), 1.5)
	p.item(cx - w * 0.5 + 2, fy - 26, w - 4, 12, Color("a87a4c"), 1.5)
	for i: int in int((w - 4.0) / 7.0):
		var bx := cx - w * 0.5 + 5 + i * 7
		var c := Color(BLOOMS[(i + seed_v) % BLOOMS.size()])
		p.R(bx, fy - 40 + (i % 2) * 4, 1, 16 - (i % 2) * 4, Color("3f8a52"))
		p.ell(bx, fy - 41 + (i % 2) * 4, 3, 3, c)
		p.R(bx - 2, fy - 12, 5, 3, c.darkened(0.2))


## A shop window: frame, a sky-and-skyline pane and a glint; left edge x, top y.
static func shop_window(p: Object, x: float, y: float, w: float, h: float, night: bool, seed_v: int) -> void:
	p.item(x - 2, y - 2, w + 4, h + 4, Color("e8e2d4"), 1.5)
	Scenes.pane(p, x, y, w, h, seed_v, night)
	p.R(x + w * 0.5, y, 1, h, Color("c8c2b4"))
	p.GW(x + 2, y + 1, 4, h - 2, Color(0.25, 0.25, 0.28))


# ---------------------------------------------------------------- services

## A reception desk: counter with a monitor, a chair at its right; left edge x.
static func service_desk(p: Object, x: float, fy: float, w: float, on: bool) -> void:
	p.shadow(x + w * 0.5, fy, w * 0.5, 0.5)
	p.item(x, fy - 22, w, 22, Color("5a6a86"), 1.5)
	p.item(x - 2, fy - 25, w + 4, 4, Color("d8d4cc"), 1.0)
	p.item(x + 8, fy - 37, 14, 10, Color("2a3140"), 1.5)
	if on:
		p.GR(x + 9, fy - 36, 12, 6, Color("8ad0f0"))
	p.R(x + 13, fy - 28, 4, 3, Color("2a2f3c"))
	p.item(x + w - 20, fy - 31, 10, 6, Color("f4f0e6"), 1.0, false)
	p.item(x + w + 4, fy - 20, 4, 20, Color("3a4a62"), 2.0)
	p.item(x + w - 2, fy - 11, 14, 3, Color("4a5a76"), 1.5)


## A bank of CCTV monitors on the wall: cols by rows, each screen with a live feed when on.
static func monitor_wall(p: Object, x: float, y: float, cols: int, rows: int, on: bool, seed_v: int) -> void:
	for r: int in rows:
		for c: int in cols:
			var mx := x + c * 18
			var my := y + r * 14
			p.item(mx, my, 16, 11, Color("1a2030"), 1.5)
			if on:
				p.GR(mx + 1, my + 1, 14, 9, Color("2a4a3a") if p.hn(c + r * 7, seed_v) > 0.4 else Color("2a3a5a"))
				p.GR(mx + 2 + int(p.hn(c, r) * 8.0), my + 3 + int(p.hn(r, c) * 4.0), 3, 3, Color("9ae8b0"))
			else:
				p.R(mx + 1, my + 1, 14, 9, Color("0e1218"))


## A security gate: two posts with a striped barrier arm between them.
static func gate(p: Object, x0: float, x1: float, fy: float, on: bool) -> void:
	for gx: float in [x0, x1]:
		p.shadow(gx + 2, fy, 7, 0.45)
		p.item(gx - 2, fy - 34, 6, 34, Color("5a6a86"), 1.5)
		p.item(gx - 3, fy - 36, 8, 3, Color("3a4258"), 1.0)
		if on:
			p.GR(gx - 1, fy - 28, 4, 3, Color("ff5030"))
		else:
			p.R(gx - 1, fy - 28, 4, 3, Color("6a2a20"))
	var ax := minf(x0, x1) + 4.0
	var aw := absf(x1 - x0) - 6.0
	for i: int in int(aw / 4.0):
		p.R(ax + i * 4, fy - 26, 4, 3, Color("f4f0e6") if i % 2 == 0 else Color("c8453c"))


## A shield badge on the wall, centred on cx.
static func badge(p: Object, cx: float, y: float) -> void:
	p.item(cx - 9, y, 18, 18, Color("c9a85c"), 4.0)
	p.R(cx - 6, y + 3, 12, 10, Color("2e3a58"))
	p.R(cx - 1, y + 5, 2, 6, Color("f4ecdc"))
	p.R(cx - 3, y + 7, 6, 2, Color("f4ecdc"))


## A red cross on the wall, centred on cx; lit it glows.
static func red_cross(p: Object, cx: float, y: float, s: float, on: bool) -> void:
	p.item(cx - s * 0.5 - 3, y - 3, s + 6, s + 6, Color("f4f0e6"), 2.0)
	var c := Color("e04040") if on else Color("b03030")
	if on:
		p.GR(cx - s * 0.17, y, s * 0.34, s, c)
		p.GR(cx - s * 0.5, y + s * 0.33, s, s * 0.34, c)
	else:
		p.R(cx - s * 0.17, y, s * 0.34, s, c)
		p.R(cx - s * 0.5, y + s * 0.33, s, s * 0.34, c)


## A hospital bed: frame, mattress, pillow; head at the left edge x, 44 long.
static func hospital_bed(p: Object, x: float, fy: float, on: bool) -> void:
	p.shadow(x + 22, fy, 28, 0.5)
	p.item(x, fy - 26, 4, 26, Color("c8ccd8"), 1.0, false)
	p.item(x + 40, fy - 18, 4, 18, Color("c8ccd8"), 1.0, false)
	p.R(x + 3, fy - 4, 3, 4, Color("2a2f3c"))
	p.R(x + 37, fy - 4, 3, 4, Color("2a2f3c"))
	p.item(x + 2, fy - 14, 40, 4, Color("8a94a4"), 1.0)
	p.item(x + 4, fy - 20, 36, 7, Color("f4f6f8"), 3.0)
	p.item(x + 5, fy - 24, 12, 6, Color("ffffff"), 3.0, false)
	p.item(x + 18, fy - 22, 22, 8, Color("9ac8c8"), 2.0, false)
	p.R(x + 4, fy - 13, 36, 1, Color("c8d4d4"))
	if on:
		p.GW(x + 4, fy - 24, 36, 12, Color("c8f0f0"))


## An IV drip stand with a bag, centred on cx.
static func iv_stand(p: Object, cx: float, fy: float) -> void:
	p.shadow(cx, fy, 8, 0.4)
	p.R(cx - 1, fy - 46, 2, 46, Color("a4acb8"))
	p.R(cx - 6, fy - 2, 12, 2, Color("5a5a66"))
	p.R(cx - 5, fy - 46, 10, 2, Color("a4acb8"))
	p.item(cx - 2, fy - 44, 5, 9, Color("a8d4e0"), 2.0, false)
	p.R(cx, fy - 34, 1, 14, Color("d8e8f0"))


## A wall vital-signs monitor.
static func vitals(p: Object, x: float, y: float, on: bool) -> void:
	p.item(x, y, 20, 12, Color("1a2030"), 1.5)
	if on:
		p.GR(x + 1, y + 1, 18, 10, Color("123a2a"))
		for i: int in 8:
			var dy := -3 if i == 3 else (3 if i == 4 else 0)
			p.GR(x + 2 + i * 2, y + 6 + dy, 2, 1, Color("5aff9a"))
	else:
		p.R(x + 1, y + 1, 18, 10, Color("0e1218"))


## A cabinet with a cross: medicine storage; left edge x.
static func med_cabinet(p: Object, x: float, fy: float) -> void:
	p.shadow(x + 12, fy, 16, 0.5)
	p.item(x, fy - 40, 24, 40, Color("e8ecf0"), 2.0)
	p.R(x + 11, fy - 39, 1, 38, Color("b8c0c8"))
	p.R(x + 4, fy - 20, 1, 4, Color("8a94a4"))
	p.R(x + 19, fy - 20, 1, 4, Color("8a94a4"))
	p.R(x + 10, fy - 33, 4, 8, Color("c8453c"))
	p.R(x + 8, fy - 31, 8, 4, Color("c8453c"))


## A waiting chair centred on cx.
static func waiting_chair(p: Object, cx: float, fy: float, c: Color) -> void:
	p.shadow(cx, fy, 10, 0.45)
	p.item(cx - 7, fy - 22, 14, 14, c, 3.0)
	p.item(cx - 8, fy - 10, 16, 4, c.lightened(0.1), 2.0)
	p.R(cx - 6, fy - 6, 2, 6, Color("3a3a46"))
	p.R(cx + 4, fy - 6, 2, 6, Color("3a3a46"))


## A recycling bin with a lid and the arrows mark, left edge x, w wide.
static func recycle_bin(p: Object, x: float, fy: float, w: float, c: Color) -> void:
	p.shadow(x + w * 0.5, fy, w * 0.6, 0.5)
	p.item(x, fy - 26, w, 26, c, 1.5)
	p.item(x - 2, fy - 30, w + 4, 5, c.darkened(0.2), 1.5)
	p.R(x + 2, fy - 3, 3, 3, Color("2a2f3c"))
	p.R(x + w - 5, fy - 3, 3, 3, Color("2a2f3c"))
	var cx := x + w * 0.5
	p.R(cx - 3, fy - 18, 6, 1, Color("f4f0e6"))
	p.R(cx - 3, fy - 18, 1, 6, Color("f4f0e6"))
	p.R(cx + 2, fy - 14, 1, 5, Color("f4f0e6"))
	p.R(cx - 3, fy - 9, 6, 1, Color("f4f0e6"))


## A baler: a steel hopper over a block press with warning stripes; left edge x, w wide.
static func baler(p: Object, x: float, fy: float, w: float, on: bool) -> void:
	p.shadow(x + w * 0.5, fy, w * 0.55, 0.55)
	p.item(x, fy - 44, w, 44, Color("5a6a58"), 2.0)
	p.item(x + 4, fy - 50, w - 8, 8, Color("3a4a38"), 1.5)
	p.item(x + 6, fy - 36, w * 0.45, 20, Color("2a2f3c"), 1.5)
	if on:
		p.GR(x + 8, fy - 34, w * 0.45 - 4, 16, Color("e8a030"))
		p.GW(x, fy - 44, w, 44, Color("ffd070"))
	for i: int in int((w - 10.0) / 6.0):
		p.R(x + 5 + i * 6, fy - 8, 3, 4, Color("e8c030"))
	p.item(x + w - 16, fy - 40, 10, 8, Color("1a2030"), 1.0)
	if on:
		p.GR(x + w - 14, fy - 38, 6, 4, Color("5aff9a"))


## A skip (an open crate of cans and bottles), left edge x.
static func skip(p: Object, x: float, fy: float, w: float, seed_v: int) -> void:
	p.shadow(x + w * 0.5, fy, w * 0.55, 0.5)
	p.item(x, fy - 18, w, 18, Color("4a6a58"), 1.5)
	p.R(x, fy - 18, w, 3, Color("6a8a78"))
	for i: int in int((w - 4.0) / 6.0):
		p.item(x + 3 + i * 6, fy - 24 + (i + seed_v) % 3 * 2, 4, 7, Color(BOTTLES[(i + seed_v) % 4]), 1.5, false)


## A conveyor belt with crates on it, left edge x.
static func conveyor(p: Object, x: float, fy: float, w: float, seed_v: int) -> void:
	p.shadow(x + w * 0.5, fy, w * 0.5, 0.5)
	p.item(x, fy - 14, w, 6, Color("4a505e"), 1.5)
	for i: int in int(w / 8.0):
		p.R(x + 2 + i * 8, fy - 13, 4, 1, Color("8a92a6"))
	for i: int in 2:
		p.R(x + 4 + i * (w - 8.0) * 0.5, fy - 8, 2, 8, Color("3a4052"))
	var k := 0
	var cx := x + 6.0
	while cx + 12.0 < x + w:
		p.item(cx, fy - 25, 12, 10, Color("a87a4c") if (k + seed_v) % 2 == 0 else Color("8a94a4"), 1.5)
		p.R(cx + 2, fy - 21, 8, 1, Color("5a3a28"))
		cx += 22.0
		k += 1


# ---------------------------------------------------------------- parking

## A car side-on, nose to the right when dir is 1, left edge x, 52 long.
static func car(p: Object, x: float, fy: float, body: Color, dir: int, on: bool) -> void:
	var glass := Color("8ac0d8") if on else Color("5a7a90")
	p.shadow(x + 26, fy, 30, 0.6)
	p.item(x, fy - 15, 52, 9, body, 3.0)
	p.item(x + 12 if dir > 0 else x + 14, fy - 24, 26, 10, body.lightened(0.05), 3.0)
	p.R(x + 14 if dir > 0 else x + 16, fy - 22, 10, 7, glass)
	p.R(x + 26 if dir > 0 else x + 28, fy - 22, 10, 7, glass)
	if dir > 0:
		p.R(x + 49, fy - 13, 3, 3, Color("ffe6a8"))
		p.R(x, fy - 13, 2, 3, Color("c83a30"))
	else:
		p.R(x, fy - 13, 3, 3, Color("ffe6a8"))
		p.R(x + 50, fy - 13, 2, 3, Color("c83a30"))
	for wx: float in [x + 8.0, x + 36.0]:
		p.item(wx, fy - 9, 9, 9, Color("2a2f3c"), 4.0, false)
		p.R(wx + 3, fy - 6, 3, 3, Color("a4acb8"))
	p.R(x + 2, fy - 11, 48, 1, body.lightened(0.25))


## A big P sign on the wall, centred on cx.
static func parking_sign(p: Object, cx: float, y: float, on: bool) -> void:
	p.item(cx - 12, y, 24, 24, Color("2a4a9a"), 3.0)
	if on:
		p.GW(cx - 12, y, 24, 24, Color("a0c0ff"))
	p.R(cx - 5, y + 5, 3, 14, Color("f4f0e6"))
	p.R(cx - 5, y + 5, 10, 3, Color("f4f0e6"))
	p.R(cx + 3, y + 5, 3, 9, Color("f4f0e6"))
	p.R(cx - 5, y + 12, 10, 3, Color("f4f0e6"))
