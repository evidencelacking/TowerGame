extends RefCounted
## The furniture and shells of the G Lit look (#302), ported from the mock-up's drawer
## (mockups/detail_drawer.gd): the same palette, proportions, outlines and dithering, parametrised by the room's
## width and the activity spots it must line up with. Every x, y, w, h is in mock-up pixels (half a world
## pixel) in the room's own frame: x from its left wall, y from the top of its floor, feet at y + 58.
## A furniture group that stands at a spot is placed from that spot, so people (drawn elsewhere, at the same
## spots) sit at the desks and sleep in the beds. Pieces are static functions on a DetailPrims `p`.

const SLAB_H: int = 4
const FLOOR: int = 64
const WARM: Color = Color("ffcf8a")
const LEAF: Color = Color("3f8a52")

## Colour set of a room's shell: wall, dado, floor, floor alt, trim (the mock-up's own).
const PALETTES: Dictionary = {
	"office": ["bccdc3", "86a196", "6e7f96", "5f6f86", "a9bab1"],
	"condo": ["dcc0cc", "a8788e", "8f6a4a", "7c5a3e", "e8d8d0"],
	"hotel": ["d8c0b8", "9a6e5c", "a89a88", "988a78", "eee4dc"],
	"service": ["c6d2cc", "86a096", "7a8aa0", "6a7a92", "a8b8b0"],
	"lobby": ["eadfc8", "b99f74", "e8e2d8", "b0aaa8", "c9a85c"],
	"fast_food": ["e8b45a", "b8453c", "d8d0c0", "c0b8a8", "f4ecd8"],
	"restaurant": ["cf6b50", "7a3a2e", "8a5a38", "74482e", "f0dcc0"],
	"retail": ["cfe0c8", "6f9a78", "d8d4c8", "c4c0b4", "f2eee0"],
	"security": ["b8c4d8", "4a5a7a", "5a6070", "4c5262", "8a98b4"],
	"medical": ["eef2f2", "9ac8c8", "dcdcdc", "c8d4d4", "ffffff"],
	"recycling": ["b4c4a0", "5a7a48", "7a7870", "6a6860", "9aaa88"],
	"parking_ramp": ["9a9aa6", "6a6a78", "5a5a64", "50505a", "c8c0a0"],
	"parking_space": ["9a9aa6", "6a6a78", "5a5a64", "50505a", "c8c0a0"],
	"movie_theatre": ["5a2a3c", "3a1a2a", "4a3040", "3c2634", "c9a85c"],
	"party_hall": ["7a4a9a", "4c2a6a", "3a3050", "30283f", "f0c050"],
	"pool": ["bfe4e6", "4a9ab4", "c8d8da", "b4c8cc", "f0f6f6"],
	"metro": ["d4dce0", "4a6a8a", "9a9ca4", "8a8c94", "e8c040"],
	"casino": ["4a1a2c", "2c1020", "6a1a28", "5a1622", "e0b040"],
	"nightclub": ["2a1a4a", "1a1030", "2a2040", "221a36", "e04aa8"],
	"observation_deck": ["c8d4e0", "8a9ab0", "b8b4ac", "a8a49c", "d8dce4"],
	"helipad": ["8a9ab0", "6a7686", "5a6270", "4e5662", "e8c040"],
	"cafe": ["ecd8b8", "a8744a", "b88a58", "9a7048", "f8ecd4"],
	"pizza": ["e0c090", "a83c30", "c8b090", "b8a07c", "f4e4c0"],
	"sushi": ["e4dcc8", "3a3a46", "a8845a", "987450", "c8453c"],
	"fine_dining": ["d8c8a8", "5a2a34", "6a4a38", "5a3c2c", "c9a85c"],
	"bar": ["6a3a28", "3a2018", "5a3a28", "4a2e20", "c9a85c"],
	"grocery": ["e4eccc", "6a9a58", "d4d0c0", "c4c0b0", "f6f4e4"],
	"deli": ["f0dcb0", "b8453c", "d8c8a8", "c8b898", "f8f0d8"],
	"gym": ["c0c8d4", "3a4a64", "4a4a54", "3e3e48", "e8a030"],
	"daycare": ["f8e4a8", "e87a68", "8ac8a0", "7ab890", "f8f4e0"],
	"clinic": ["e8f2f0", "88c0bc", "d8dcdc", "c4cccc", "ffffff"],
	"coworking": ["d4dce0", "6a8a9a", "8a8a90", "7a7a84", "e8b040"],
	"cathedral": ["d8d0c0", "8a7a68", "7a6a5a", "6a5a4c", "c9a85c"],
}


## The mock-up's sky colour at height y, by day or night.
static func sky_col(night: bool, y: float) -> Color:
	var t: float = clampf(y / 312.0, 0.0, 1.0)
	var lo: Color = Color("0b1033") if night else Color("3a92e0")
	var mid: Color = Color("2a2468") if night else Color("a4d6f0")
	var hi: Color = Color("8a4a6c") if night else Color("f6e8bc")
	if t < 0.6:
		return lo.lerp(mid, t / 0.6)
	return mid.lerp(hi, (t - 0.6) / 0.4)


## Back wall, cornice, dado rail, skirting and floor for one room cell (the mock-up's _shell_room).
static func shell_room(p: Object, x: float, y: float, w: float, row: int, pal: Array) -> void:
	var wall := Color(pal[0] as String)
	var dado := Color(pal[1] as String)
	var floor_c := Color(pal[2] as String)
	var floor_alt := Color(pal[3] as String)
	var trim := Color(pal[4] as String)
	p.gradv(x, y, w, 56, wall.lightened(0.07), wall.darkened(0.06))
	var run: Vector2i = p.repeats(x, 12.0, int(ceil(w / 12.0)), 2.0)
	for i: int in range(run.x, run.y):
		p.R(x + i * 12, y + 4, 1, 34, wall.darkened(0.045))
	p.R(x, y, w, 3, trim)
	p.R(x, y + 1, w, 1, trim.lightened(0.25))
	p.R(x, y + 3, w, 1, trim.darkened(0.3))
	p.R(x, y + 38, w, 18, dado)
	p.R(x, y + 38, w, 1, dado.lightened(0.3))
	p.R(x, y + 39, w, 1, dado.darkened(0.25))
	run = p.repeats(x, 16.0, int(ceil(w / 16.0)), 17.0)
	for j: int in range(run.x, run.y):
		p.R(x + j * 16 + 15, y + 40, 1, 14, dado.darkened(0.18))
	p.R(x, y + 54, w, 2, trim.darkened(0.12))
	p.R(x, y + 56, w, 4, floor_c)
	run = p.repeats(x, 12.0, int(ceil(w / 12.0)), 12.0)
	for k: int in range(run.x, run.y):
		p.R(x + k * 12 + (row % 2) * 5, y + 56, 6, 4, floor_alt)
	p.R(x, y + 56, w, 1, floor_c.lightened(0.25))
	p.R(x, y + 3, 1, 53, wall.darkened(0.35))
	p.R(x + w - 1, y + 3, 1, 53, wall.darkened(0.35))


static func skyline(p: Object, x: float, y: float, w: float, h: float, night: bool, seed_v: int) -> void:
	var skyc: Color = Color("2a2a66") if night else Color("93b6d4")
	for k: int in int(w) / 5 + 1:
		var bw: float = minf(5.0, w - float(k * 5))
		if bw <= 0.0:
			continue
		var bh: float = 5.0 + floorf(p.hn(k + seed_v * 7, 5) * h * 0.45)
		var bc: Color = skyc if k % 2 == 0 else skyc.lightened(0.06)
		p.GR(x + k * 5, y + h - bh, bw, bh, bc)
		if night and p.hn(k + seed_v * 7, 6) > 0.5 and bw >= 2.0:
			p.GR(x + k * 5 + 1, y + h - bh + 2, 1, 1, Color("ffd27a"))
	if not night and w >= 12.0 and h >= 10.0:
		p.GR(x + w * 0.5 - 5.0, y + h * 0.3, 10, 2, Color("ffffff"))
		p.GR(x + w * 0.5 - 3.0, y + h * 0.3 - 2.0, 6, 2, Color("ffffff"))


## One pane of a window: sky gradient, hazy skyline, a cloud by day. Never darkened by the room.
static func pane(p: Object, x: float, y: float, w: float, h: float, seed_v: int, night: bool) -> void:
	p.gradv(x, y, w, h, sky_col(night, y + 30.0), sky_col(night, y + h + 30.0), true)
	skyline(p, x, y, w, h, night, seed_v)


## A window: frame, four panes with a muntin cross between them, a glint, a sill and curtains.
static func window(p: Object, x: float, y: float, w: float, h: float, frame: Color, curtain: Color, seed_v: int, night: bool, blind: bool = false) -> void:
	p.item(x - 3, y - 3, w + 6, h + 6, frame, 1.5)
	var hw: float = floorf(w * 0.5)
	var th: float = floorf(h * 0.55)
	pane(p, x, y, hw - 1, th - 1, seed_v, night)
	pane(p, x + hw + 1, y, w - hw - 1, th - 1, seed_v + 1, night)
	pane(p, x, y + th + 1, hw - 1, h - th - 1, seed_v + 2, night)
	pane(p, x + hw + 1, y + th + 1, w - hw - 1, h - th - 1, seed_v + 3, night)
	p.R(x + hw - 1, y, 2, h, frame.darkened(0.12))
	p.R(x, y + th - 1, w, 2, frame.darkened(0.12))
	p.GW(x + 3, y + 1, 4, 10, Color(0.25, 0.25, 0.28))
	p.GW(x + 9, y + 1, 2, 10, Color(0.18, 0.18, 0.2))
	p.item(x - 5, y + h + 2, w + 10, 3, frame.lightened(0.1), 1)
	if p.lit:
		p.glow(x + w * 0.5, y + h * 0.5, w * 0.8, h * 0.9, Color("ffd890"), 0.3)
	if blind:
		for i: int in int(h * 0.4 / 3.0):
			p.R(x, y + i * 3, w, 2, Color("f2e8d0"))
			p.R(x, y + i * 3 + 2, w, 1, Color("c8b898"))
	if curtain.a > 0.0:
		curtain_at(p, x - 9, y - 4, 6, h + 6, curtain)
		curtain_at(p, x + w + 3, y - 4, 6, h + 6, curtain)


static func curtain_at(p: Object, x: float, y: float, w: float, h: float, c: Color) -> void:
	p.item(x, y, w, h, c, 2.0, false)
	for i: int in int(w / 2.0):
		p.R(x + i * 2 + 1, y + 1, 1, h - 2, c.darkened(0.2))


static func ceiling_light(p: Object, cx: float, y: float, w: float, on: bool, radius: float = 70.0) -> void:
	p.item(cx - w * 0.5, y + 3, w, 3, Color("d8d2c8"), 1, false)
	if on:
		p.GR(cx - w * 0.5 + 2, y + 5, w - 4, 2, Color("fff6d8"))
		p.glow(cx, y + 8, radius * 1.3, radius * 1.1, WARM, 0.65)
	else:
		p.R(cx - w * 0.5 + 2, y + 5, w - 4, 2, Color("b8b2a8"))


static func plant(p: Object, x: float, fy: float, h: float, pot: Color) -> void:
	p.shadow(x, fy, 7, 0.5)
	p.item(x - 5, fy - 9, 10, 9, pot, 2)
	p.R(x - 5, fy - 9, 10, 2, pot.darkened(0.25))
	var n: int = 7
	for i: int in n:
		var a: float = -PI * 0.5 + (float(i) - float(n - 1) * 0.5) * 0.42
		var l: float = h * (0.55 + 0.4 * p.hn(i, int(x)))
		var tip: Vector2 = Vector2(x + cos(a) * l * 0.7, fy - 9 + sin(a) * l)
		p.ln(Vector2(x, fy - 9), tip, LEAF.darkened(0.1 * float(i % 3)), 2.0)
		p.ell(tip.x, tip.y, 3, 2, LEAF.lightened(0.12))


## An office desk with its chair, the person's seat at x = dx + 52 (the mock-up's _desk without the person).
static func desk(p: Object, dx: float, fy: float, powered: bool) -> void:
	p.shadow(dx + 30, fy, 32, 0.5)
	p.item(dx + 55, fy - 20, 4, 16, Color("3a4a62"), 2.0)
	p.item(dx + 44, fy - 11, 14, 3, Color("4a5a76"), 1.5)
	p.R(dx + 50, fy - 8, 2, 8, Color("2a2f3c"))
	p.item(dx, fy - 21, 44, 3, Color("c89a62"), 1.0)
	p.item(dx + 2, fy - 18, 4, 18, Color("8a5f3a"), 0.0, false)
	p.item(dx + 34, fy - 18, 8, 18, Color("a87a4c"), 1.0)
	p.R(dx + 36, fy - 12, 4, 1, Color("e8d098"))
	p.item(dx + 6, fy - 34, 14, 11, Color("2a3140"), 1.5)
	screen(p, dx + 7, fy - 33, powered)
	p.R(dx + 11, fy - 23, 4, 2, Color("2a2f3c"))
	p.item(dx + 8, fy - 23, 12, 2, Color("e0dcd2"), 0.5, false)
	p.R(dx + 28, fy - 28, 1, 7, Color("3a3a44"))
	p.item(dx + 25, fy - 31, 7, 4, Color("e8b458"), 1.5, false)
	p.item(dx + 22, fy - 24, 6, 3, Color("f4f0e6"), 0.0, false)


static func screen(p: Object, x: float, y: float, powered: bool) -> void:
	if powered:
		p.GR(x, y, 12, 8, Color("8ad0f0"))
		p.GR(x + 1, y + 2, 8, 1, Color("e8f8ff"))
		p.GR(x + 2, y + 4, 6, 1, Color("5aa4d0"))
		p.glow(x + 6, y + 4, 22.0, 18.0, Color("8ad0f0"), 0.4)
	else:
		p.R(x, y, 12, 8, Color("1a2030"))


## A narrow workstation for a tight row (a bench): a monitor on a short desk and the chair, seat at x = cx.
static func bench_desk(p: Object, cx: float, fy: float, powered: bool) -> void:
	p.shadow(cx - 12, fy, 18, 0.5)
	p.item(cx + 3, fy - 20, 4, 16, Color("3a4a62"), 2.0)
	p.item(cx - 8, fy - 11, 14, 3, Color("4a5a76"), 1.5)
	p.R(cx - 2, fy - 8, 2, 8, Color("2a2f3c"))
	p.item(cx - 30, fy - 21, 26, 3, Color("c89a62"), 1.0)
	p.item(cx - 28, fy - 18, 4, 18, Color("8a5f3a"), 0.0, false)
	p.item(cx - 14, fy - 34, 14, 11, Color("2a3140"), 1.5)
	screen(p, cx - 13, fy - 33, powered)
	p.R(cx - 9, fy - 23, 4, 2, Color("2a2f3c"))
	p.item(cx - 12, fy - 23, 12, 2, Color("e0dcd2"), 0.5, false)


static func filing(p: Object, fx: float, fy: float) -> void:
	p.shadow(fx + 7, fy, 10, 0.5)
	p.item(fx, fy - 26, 14, 26, Color("8a94a4"), 1.5)
	for i: int in 3:
		p.R(fx + 2, fy - 24 + i * 8, 10, 1, Color("5a6272"))
		p.R(fx + 5, fy - 21 + i * 8, 4, 1, Color("d8dce4"))
	p.item(fx + 15, fy - 26, 8, 16, Color("a4d4f0"), 3.0)
	p.item(fx + 14, fy - 10, 10, 10, Color("e8ecf0"), 2.0)


static func poster(p: Object, x: float, y: float, which: int) -> void:
	if which % 2 == 0:
		p.item(x, y + 2, 18, 14, Color("f4f0e6"), 1.0)
		p.R(x + 3, y + 6, 8, 1, Color("c83a30"))
		p.R(x + 3, y + 9, 11, 1, Color("3f7fb0"))
		p.R(x + 3, y + 12, 6, 1, Color("2a2f3c"))
	else:
		p.item(x, y, 18, 18, Color("e8b458"), 1.5)
		p.item(x + 3, y + 3, 12, 12, Color("c8453c"), 1.0, false)
		p.ell(x + 9, y + 9, 3, 3, Color("f6e8c8"))


## A bed with its headboard at bx, length len; the sleeper's head lies at bx + 16.
static func bed(p: Object, bx: float, fy: float, length: float, quilt: Color, sheet: Color) -> void:
	p.shadow(bx + length * 0.5, fy, length * 0.55, 0.55)
	p.item(bx, fy - 26, 5, 26, Color("7a4e32"), 1.5)
	p.item(bx + 4, fy - 12, length - 4, 10, Color("8a5a3c"), 2.0)
	p.item(bx + 4, fy - 17, length - 6, 7, sheet, 3.0)
	p.item(bx + 8, fy - 21, 16, 7, Color("fffaf0"), 3.0)
	p.item(bx + 26, fy - 21, length - 28, 9, quilt, 3.0)
	for i: int in int((length - 34.0) / 7.0):
		p.R(bx + 30 + i * 7, fy - 20, 3, 7, quilt.lightened(0.15))
	p.R(bx + 4, fy - 12, length - 4, 1, Color("c8a070"))


static func nightstand(p: Object, nx: float, fy: float, lamp_on: bool) -> void:
	p.item(nx, fy - 14, 14, 14, Color("a87a4c"), 1.5)
	p.R(nx + 2, fy - 9, 10, 1, Color("5a3a28"))
	p.R(nx + 6, fy - 7, 2, 1, Color("e8d098"))
	p.R(nx + 6, fy - 22, 2, 8, Color("c9a85c"))
	p.item(nx + 2, fy - 28, 10, 7, Color("f4d8a0"), 2.0, false)
	if lamp_on or p.sleeping:
		p.GR(nx + 4, fy - 26, 6, 3, Color("ffe6a8"))
		p.glow(nx + 7, fy - 24, 74.0, 60.0, WARM, 0.6)


static func wardrobe(p: Object, wx: float, fy: float, h: float = 44.0) -> void:
	p.shadow(wx + 16, fy, 20, 0.5)
	p.item(wx, fy - h, 26, h, Color("7a5238"), 2.0)
	p.R(wx + 12, fy - h + 1, 1, h - 2, Color("4a3020"))
	p.R(wx + 9, fy - 24, 2, 5, Color("e8c88a"))
	p.R(wx + 15, fy - 24, 2, 5, Color("e8c88a"))


static func picture(p: Object, x: float, y: float, a: Color, b: Color) -> void:
	p.item(x, y, 24, 16, Color("e8d8c8"), 1.5)
	p.R(x + 4, y + 4, 8, 8, a)
	p.R(x + 14, y + 7, 6, 5, b)


static func sofa(p: Object, sx: float, fy: float, body: Color) -> void:
	p.shadow(sx + 28, fy, 32, 0.5)
	p.item(sx, fy - 17, 56, 17, body, 4.0)
	p.item(sx - 3, fy - 24, 62, 9, body.lightened(0.08), 4.0)
	p.item(sx + 2, fy - 16, 24, 8, body.lightened(0.14), 3.0, false)
	p.item(sx + 30, fy - 16, 24, 8, body.lightened(0.14), 3.0, false)


static func side_table(p: Object, sx: float, fy: float) -> void:
	p.item(sx, fy - 9, 24, 3, Color("a87850"), 1.0)
	p.R(sx + 3, fy - 6, 2, 6, Color("5a3a28"))
	p.R(sx + 19, fy - 6, 2, 6, Color("5a3a28"))
	p.item(sx + 8, fy - 14, 7, 5, Color("f2eadc"), 1.5, false)


## A table with a chair either side: the chairs' backs at tx - 8 and tx + 46.
static func table_set(p: Object, tx: float, fy: float) -> void:
	p.shadow(tx + 22, fy, 26, 0.5)
	p.item(tx, fy - 18, 44, 4, Color("a87850"), 1.0)
	p.R(tx + 4, fy - 14, 3, 14, Color("5a3a28"))
	p.R(tx + 37, fy - 14, 3, 14, Color("5a3a28"))
	for cxx: float in [tx - 8.0, tx + 46.0]:
		p.item(cxx, fy - 18, 4, 18, Color("c8845a"), 1.5, false)
		p.item(cxx - 2, fy - 10, 8, 3, Color("c8845a"), 1.0, false)
	p.item(tx + 14, fy - 24, 6, 6, Color("c8453c"), 2.5, false)
	p.ell(tx + 30, fy - 21, 2.5, 2.5, Color("e8b458"))


static func fridge(p: Object, fx: float, fy: float) -> void:
	p.shadow(fx + 14, fy, 18, 0.5)
	p.item(fx, fy - 50, 28, 50, Color("e8ecf0"), 2.5)
	p.R(fx, fy - 32, 28, 1, Color("9aa4b0"))
	p.R(fx + 22, fy - 46, 2, 10, Color("8a94a4"))
	p.R(fx + 22, fy - 28, 2, 8, Color("8a94a4"))


static func counter(p: Object, kx: float, fy: float, cw: float, seed_v: int) -> void:
	p.shadow(kx + cw * 0.5, fy, cw * 0.55, 0.55)
	p.item(kx, fy - 20, cw, 20, Color("eae4d8"), 1.5)
	p.item(kx - 2, fy - 23, cw + 4, 4, Color("6a6a76"), 1.0)
	for i: int in int(cw / 22.0):
		p.R(kx + 4 + i * 22, fy - 17, 18, 1, Color("c4bcae"))
		p.R(kx + 10 + i * 22, fy - 10, 6, 1, Color("8a8478"))
	p.item(kx + 8, fy - 26, 20, 3, Color("2a2f3c"), 0.5, false)
	var shelf: float = minf(cw - 8.0, 40.0)
	p.item(kx + 4, fy - 46, shelf, 4, Color("8a5f3a"), 1.0)
	for i: int in int(shelf / 10.0):
		p.item(kx + 6 + i * 9, fy - 54, 6, 8, Color("c8a870") if (i + seed_v) % 2 == 0 else Color("a8c8b0"), 1.5, false)


## A linen cart with a stack of towels.
static func cart(p: Object, cx: float, fy: float) -> void:
	p.shadow(cx + 14, fy, 20, 0.5)
	p.item(cx, fy - 22, 28, 18, Color("8a94a4"), 1.5)
	p.item(cx + 2, fy - 20, 24, 14, Color("f4f0e6"), 1.5, false)
	for i: int in 3:
		p.R(cx + 4, fy - 18 + i * 4, 20, 1, Color("c8d0e0"))
	p.R(cx + 3, fy - 4, 2, 4, Color("2a2f3c"))
	p.R(cx + 23, fy - 4, 2, 4, Color("2a2f3c"))
	p.item(cx + 28, fy - 34, 3, 28, Color("8a94a4"), 0.0, false)
	p.item(cx + 28, fy - 34, 8, 3, Color("8a94a4"), 0.0, false)


static func linen_shelf(p: Object, sx: float, fy: float, seed_v: int) -> void:
	p.shadow(sx + 14, fy, 18, 0.5)
	p.item(sx, fy - 48, 28, 48, Color("7a5238"), 2.0)
	var towels: Array = [Color("f4f0e6"), Color("a8c8e0"), Color("e8b0a8")]
	for i: int in 3:
		p.R(sx + 1, fy - 32 + i * 16, 26, 1, Color("4a3020"))
		var tow: Color = towels[(seed_v + i) % 3]
		p.item(sx + 3, fy - 44 + i * 16, 10, 8, tow, 1.0, false)
		p.item(sx + 15, fy - 44 + i * 16, 10, 8, tow.lightened(0.1), 1.0, false)


static func washer(p: Object, wx: float, fy: float) -> void:
	p.shadow(wx + 14, fy, 18, 0.5)
	p.item(wx, fy - 32, 28, 32, Color("e8ecf0"), 2.5)
	p.item(wx + 6, fy - 22, 16, 16, Color("8a94a4"), 6.0)
	p.item(wx + 9, fy - 19, 10, 10, Color("a4d4f0"), 4.0, false)
	p.R(wx + 3, fy - 29, 6, 2, Color("c83a30"))


static func clothes_rail(p: Object, rx: float, fy: float, rw: float) -> void:
	p.R(rx, fy - 48, rw, 2, Color("8a5f3a"))
	p.R(rx, fy - 48, 2, 48, Color("8a5f3a"))
	p.R(rx + rw - 2, fy - 48, 2, 48, Color("8a5f3a"))
	var cols: Array = [Color("e8e2d4"), Color("c8453c"), Color("e0a83a"), Color("a8c8e0"), Color("f4f0e6")]
	for i: int in int((rw - 6.0) / 6.0):
		p.item(rx + 4 + i * 6, fy - 46, 4, 22 - (i % 3) * 2, cols[i % cols.size()], 0.0, false)


## A lobby floor (the mock-up's _room_lobby) over width w: columns every 100, ceiling lamps, a directory board,
## the reception desk centred, a sofa group at every other seat, plants at the ends and a revolving door.
static func lobby(p: Object, w: float, y: float, seats: Array) -> void:
	var fy: float = y + 58.0
	shell_room(p, 0, y, w, 1, PALETTES["lobby"])
	var run: Vector2i = p.repeats(0.0, 8.0, int(w / 8.0), 8.0)
	for i: int in range(run.x, run.y):
		if i % 2 == 0:
			p.R(i * 8, y + 58, 8, 2, Color("9a948f"))
	var px: float = 100.0
	if p.x_from() > 108.0:  # columns every 100: jump to the first one that can touch the slice
		px = 100.0 + floorf((p.x_from() - 108.0) / 100.0) * 100.0
	while px < w - 60.0 and px < p.x_to():
		p.item(px, y + 4, 6, 52, Color("d8c8a4"), 1.0, false)
		p.R(px - 1, y + 4, 8, 3, Color("c9a85c"))
		p.R(px - 1, y + 53, 8, 3, Color("c9a85c"))
		px += 100.0
	var lx: float = 40.0
	if p.x_from() > 148.0:  # lamps every 103
		lx = 40.0 + floorf((p.x_from() - 148.0) / 103.0) * 103.0
	while lx < w - 40.0 and lx < p.x_to() + 100.0:
		p.R(lx, y + 4, 1, 8, Color("8a7a60"))
		p.ell(lx, y + 15, 5, 5, Color("f4e8c8"))
		p.GR(lx - 3, y + 12, 6, 6, Color("fff2c8"))
		p.glow(lx, y + 15, 100.0, 80.0, WARM, 0.65)
		lx += 103.0
	if w >= 200.0:
		p.item(14, y + 12, 22, 28, Color("2e3a52"), 1.5)
		for i: int in 5:
			p.R(17, y + 16 + i * 5, 5.0 + floorf(p.hn(i, 9) * 8.0), 2, Color("e8d8a0"))
	var dx: float = floorf(w * 0.5) - 36.0
	p.shadow(dx + 36, fy, 40, 0.55)
	p.item(dx, fy - 20, 72, 20, Color("8a5a3c"), 2.0)
	p.item(dx - 2, fy - 24, 76, 5, Color("c89a62"), 2.0)
	p.R(dx + 4, fy - 17, 64, 1, Color("c9a85c"))
	for i: int in 5:
		p.item(dx + 6 + i * 12, fy - 15, 9, 11, Color("6a4430"), 1.0, false)
	p.item(dx + 46, fy - 34, 14, 9, Color("3a4052"), 1.0)
	p.GR(dx + 47, fy - 33, 12, 6, Color("78c8e8"))
	p.R(dx + 51, fy - 25, 4, 2, Color("2a2f3c"))
	p.item(dx + 6, fy - 31, 4, 7, Color("c9a85c"), 1.5)
	for c: float in seats:
		if absf(c - w * 0.5) < 90.0 or c < 40.0 or c > w - 70.0:
			continue
		sofa(p, c - 28.0, fy, Color("3f6f8c"))
		side_table(p, c + 38.0, fy)
	if w >= 120.0:
		plant(p, 16, fy, 34.0, Color("a8683c"))
	if w >= 220.0:
		plant(p, w - 66.0, fy, 30.0, Color("7a5a8a"))
	if w >= 300.0:
		door(p, w - 52.0, y)


static func door(p: Object, rx: float, y: float) -> void:
	p.item(rx, y + 6, 40, 52, Color("7a8aa0"), 3.0)
	var gx: float = rx + 3.0
	var gy: float = y + 9.0
	p.gradv(gx, gy, 34, 49, Color("dff2ff"), Color("bfe0f0"), true)
	p.ln(Vector2(gx + 17, gy), Vector2(gx + 17, gy + 49), Color("2a303e"), 2.0)
	p.ln(Vector2(gx + 2, gy + 37), Vector2(gx + 32, gy + 12), Color("2a303e"), 2.0)
	p.R(gx, gy + 43, 34, 6, Color("5a6478"))


## The upper floors of a tall lobby, above y = top: panelled wall, columns, tall windows between them and a
## mezzanine rail along the edge of the floor.
static func mezzanine(p: Object, w: float, top: float, night: bool) -> void:
	var pal: Array = PALETTES["lobby"]
	var wall := Color(pal[0] as String)
	var trim := Color(pal[4] as String)
	p.gradv(0, 0, w, top, wall.lightened(0.07), wall.darkened(0.06))
	var run: Vector2i = p.repeats(0.0, 12.0, int(ceil(w / 12.0)), 2.0)
	for i: int in range(run.x, run.y):
		p.R(i * 12, 4, 1, top - 8, wall.darkened(0.045))
	p.R(0, 0, w, 3, trim)
	p.R(0, 1, w, 1, trim.lightened(0.25))
	p.R(0, 3, w, 1, trim.darkened(0.3))
	var col := Color("e8dcc0")
	var cx: float = 48.0
	if p.x_from() > 160.0:  # columns every 96
		cx = 48.0 + floorf((p.x_from() - 160.0) / 96.0) * 96.0
	while cx < w - 4.0 and cx < p.x_to():
		p.item(cx, 4, 8, top - 4, col, 0.0, false)
		p.item(cx - 2, 4, 12, 4, col.lightened(0.1), 0.0, false)
		p.item(cx - 2, top - 8, 12, 4, col.darkened(0.1), 0.0, false)
		p.R(cx + 3, 10, 1, top - 18, col.darkened(0.2))
		cx += 96.0
	var wh: float = top - 40.0
	if wh >= 12.0:
		var wx: float = 72.0
		if p.x_from() > 104.0:  # windows every 96, 32 wide
			wx = 72.0 + floorf((p.x_from() - 104.0) / 96.0) * 96.0
		while wx < w - 48.0 and wx < p.x_to():
			window(p, wx, 10, 32, wh, Color("e8e2d4"), Color("b86a5a"), int(wx), night)
			wx += 96.0
	var rail := Color("5a4030")
	p.R(0, top - 24, w, 2, rail.lightened(0.15))
	p.R(0, top - 20, w, 1, rail)
	run = p.repeats(0.0, 8.0, int(w / 8.0), 2.0)
	for k: int in range(run.x, run.y):
		p.R(2 + k * 8, top - 22, 1, 18, rail)
	p.item(0, top - 4, w, 3, rail.lightened(0.05), 0.0, false)


## A cubicle partition: a tall fabric panel with a lighter edge.
static func partition(p: Object, x: float, fy: float, h: float = 46.0) -> void:
	p.item(x, fy - h, 4, h, Color("6f86a4"), 0.0)
	p.R(x + 1, fy - h + 3, 1, h - 8, Color("93a8c2"))
	p.R(x - 1, fy - 2, 6, 2, Color("2a2f3c"))


## An office chair seen from the side; dir 1 faces right (back on the left), -1 faces left.
static func chair(p: Object, cx: float, fy: float, dir: int) -> void:
	if dir < 0:
		p.flip_around(cx)
	p.item(cx - 7, fy - 20, 4, 16, Color("3a4a62"), 2.0)
	p.item(cx - 7, fy - 11, 14, 3, Color("4a5a76"), 1.5)
	p.R(cx - 1, fy - 8, 2, 8, Color("2a2f3c"))
	if dir < 0:
		p.flip_off()


## A meeting table with legs, papers, mugs and a laptop; its top spans x0 to x1.
static func meeting_table(p: Object, x0: float, x1: float, fy: float, powered: bool) -> void:
	p.shadow((x0 + x1) * 0.5, fy, (x1 - x0) * 0.5, 0.5)
	p.item(x0 + 4, fy - 21, 5, 21, Color("8a5f3a"), 0.0, false)
	p.item(x1 - 9, fy - 21, 5, 21, Color("8a5f3a"), 0.0, false)
	p.item(x0, fy - 25, x1 - x0, 4, Color("c89a62"), 1.0)
	var x: float = x0 + 12.0
	var k: int = 0
	while x + 14.0 < x1 - 8.0:
		if k % 3 == 1 and powered:
			p.item(x, fy - 36, 12, 9, Color("2a3140"), 1.0)
			screen(p, x + 1, fy - 35, true)
		elif k % 3 == 1:
			p.item(x, fy - 36, 12, 9, Color("2a3140"), 1.0)
			screen(p, x + 1, fy - 35, false)
		else:
			p.item(x, fy - 27, 10, 2, Color("f4f0e6"), 0.0, false)
			p.item(x + 12, fy - 29, 4, 4, Color("e8e2d4"), 1.0, false)
		x += 30.0
		k += 1


## A whiteboard on the wall with a few scribbles.
static func whiteboard(p: Object, x: float, y: float, w: float, h: float) -> void:
	p.item(x, y, w, h, Color("f2f0ea"), 1.0)
	p.R(x + 4, y + 5, w * 0.5, 1, Color("c8606a"))
	p.R(x + 4, y + 10, w * 0.7, 1, Color("5a7fb4"))
	p.R(x + 4, y + 15, w * 0.35, 1, Color("5a7fb4"))
	p.R(x + w - 14, y + 5, 8, 8, Color("e8b458"))
	p.R(x + 4, y + h - 4, w - 8, 1, Color("8a8a94"))


## An executive's desk: a broad dark-wood top on a drawer pedestal, two monitors and a lamp. Left edge at dx.
static func exec_desk(p: Object, dx: float, fy: float, powered: bool) -> void:
	p.shadow(dx + 30, fy, 34, 0.5)
	p.item(dx, fy - 24, 60, 4, Color("7a4a2a"), 1.0)
	p.item(dx + 2, fy - 20, 6, 20, Color("5a3a22"), 0.0, false)
	p.item(dx + 38, fy - 20, 20, 20, Color("6a4228"), 1.0)
	p.R(dx + 41, fy - 14, 14, 1, Color("3a2412"))
	p.R(dx + 46, fy - 12, 4, 1, Color("e8d098"))
	p.item(dx + 6, fy - 37, 14, 11, Color("2a3140"), 1.5)
	screen(p, dx + 7, fy - 36, powered)
	p.item(dx + 22, fy - 37, 14, 11, Color("2a3140"), 1.5)
	screen(p, dx + 23, fy - 36, powered)
	p.item(dx + 44, fy - 31, 7, 4, Color("e8b458"), 1.5, false)


## A high-backed leather chair; dir 1 faces right.
static func exec_chair(p: Object, cx: float, fy: float, dir: int) -> void:
	if dir < 0:
		p.flip_around(cx)
	p.item(cx - 8, fy - 34, 6, 28, Color("5a2a2a"), 2.0)
	p.item(cx - 8, fy - 13, 18, 4, Color("6a3434"), 1.5)
	p.R(cx, fy - 9, 2, 9, Color("2a2f3c"))
	if dir < 0:
		p.flip_off()


## A tall bookcase with rows of coloured books.
static func bookcase(p: Object, x: float, fy: float, w: float = 24.0, h: float = 52.0) -> void:
	p.item(x, fy - h, w, h, Color("7a4a2a"), 1.0)
	var rows: int = int(h / 13.0)
	for r: int in rows:
		var ry: float = fy - h + 3.0 + float(r) * 13.0
		p.R(x + 2, ry + 10, w - 4, 1, Color("4a2a16"))
		var bx: float = x + 3.0
		var k: int = 0
		while bx + 3.0 < x + w - 2.0:
			var cols: Array = [Color("c8606a"), Color("e8b458"), Color("5a7fb4"), Color("f4f0e6"), Color("5a9a7a")]
			p.R(bx, ry + 2.0 + float((k + r) % 3), 3, 8.0 - float((k + r) % 3), cols[(k + r * 2) % cols.size()])
			bx += 4.0
			k += 1


## A low armchair; dir 1 faces right.
static func armchair(p: Object, cx: float, fy: float, dir: int, body: Color) -> void:
	if dir < 0:
		p.flip_around(cx)
	p.shadow(cx, fy, 14, 0.5)
	p.item(cx - 12, fy - 22, 6, 22, body.darkened(0.1), 2.0)
	p.item(cx - 12, fy - 11, 22, 11, body, 2.0)
	p.item(cx + 6, fy - 16, 6, 5, body.lightened(0.1), 1.5)
	if dir < 0:
		p.flip_off()
