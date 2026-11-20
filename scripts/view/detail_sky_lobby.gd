extends RefCounted
## The G Lit look of a sky lobby (#357): the ground lobby's marble, pillars, lamps and sofas on a one-floor
## transfer hall, with a large floor-number sign on the back wall and elevator-bank hints. Every x, y, w, h is
## in mock-up pixels in the room's frame (y from the top of its floor, feet at y + 58). Everything repeats at a
## fixed period from the left wall, so the hall tiles across any width and a slice paints only its share.

const Scenes := preload("res://scripts/view/detail_scenes.gd")

const PALETTE: Array = ["e3e0d6", "6f7f98", "ebe6d8", "bcb6ae", "c9a85c"]  ## Wall, dado, floor, alt tile, trim: the lobby's, cooler.
const PILLAR_STEP := 120.0
const SEAT_STEP := 240.0
const BANK_STEP := 360.0
const SIGN_STEP := 480.0
const STEEL := Color("a9b3c0")
const DIGITS: Array = [0x7e, 0x30, 0x6d, 0x79, 0x33, 0x5b, 0x5f, 0x70, 0x7f, 0x7b]  ## Seven segments a..g from bit 6 down.


## Paints the hall of width w on the floor whose top is y, for sky lobby `floor_number`.
static func draw(p: Object, w: float, y: float, floor_number: int) -> void:
	var fy: float = y + 58.0
	Scenes.shell_room(p, 0, y, w, 1, PALETTE)
	_polish(p, w, y)
	_pillars(p, w, y)
	_lamps(p, w, y)
	_signs(p, w, y, floor_number)
	_banks(p, w, y)
	_seating(p, w, fy)


## Reflections on the floor, so it reads polished: a pale streak every few tiles and a bright edge.
static func _polish(p: Object, w: float, y: float) -> void:
	var run: Vector2i = p.repeats(0.0, 36.0, int(ceil(w / 36.0)), 22.0)
	for i: int in range(run.x, run.y):
		p.R(i * 36 + 6, y + 58, 14, 1, Color("ffffff"))
		p.R(i * 36 + 10, y + 57, 8, 1, Color("f6f1e6"))


static func _pillars(p: Object, w: float, y: float) -> void:
	var run: Vector2i = p.repeats(PILLAR_STEP, PILLAR_STEP, int(w / PILLAR_STEP), 8.0)
	for i: int in range(run.x, run.y):
		var px: float = PILLAR_STEP + i * PILLAR_STEP
		if px > w - 12.0:
			continue
		p.item(px, y + 4, 6, 52, Color("d8c8a4"), 1.0, false)
		p.R(px - 1, y + 4, 8, 3, Color("c9a85c"))
		p.R(px - 1, y + 53, 8, 3, Color("c9a85c"))
		p.R(px + 4, y + 8, 1, 44, Color("f0e4c4"))


static func _lamps(p: Object, w: float, y: float) -> void:
	var run: Vector2i = p.repeats(60.0, 120.0, int(w / 120.0) + 1, 8.0)
	for i: int in range(run.x, run.y):
		var lx: float = 60.0 + i * 120.0
		if lx > w - 8.0:
			continue
		p.R(lx, y + 4, 1, 8, Color("8a7a60"))
		p.ell(lx, y + 15, 5, 5, Color("f4e8c8"))
		p.GR(lx - 3, y + 12, 6, 6, Color("fff2c8"))
		p.glow(lx, y + 15, 80.0, 64.0, Scenes.WARM, 0.4)


## The back-wall plaque with the floor number in big seven-segment digits, one per SIGN_STEP of wall.
static func _signs(p: Object, w: float, y: float, floor_number: int) -> void:
	var text := str(floor_number)
	var plaque_w: float = 18.0 + 16.0 * text.length()
	var centres: Array[float] = []
	if w <= SIGN_STEP:
		centres.append(w * 0.5)
	else:
		var c: float = SIGN_STEP * 0.5
		while c < w - 60.0:  # ends: c grows by SIGN_STEP each pass
			centres.append(c)
			c += SIGN_STEP
	for cx: float in centres:
		if cx + plaque_w * 0.5 < p.x_from() or cx - plaque_w * 0.5 > p.x_to():
			continue
		var x0: float = cx - plaque_w * 0.5
		p.item(x0, y + 10, plaque_w, 30, Color("2a3550"), 2.0)
		p.R(x0 + 2, y + 12, plaque_w - 4, 1, Color("c9a85c"))
		p.R(x0 + 2, y + 37, plaque_w - 4, 1, Color("c9a85c"))
		for i: int in text.length():
			_digit(p, x0 + 10.0 + i * 16.0, y + 16.0, int(text[i]))
		p.glow(cx, y + 25, plaque_w * 0.9, 30.0, Color("ffe0a0"), 0.3)


## One seven-segment digit, 11 wide and 18 tall, in lit brass.
static func _digit(p: Object, x: float, y: float, n: int) -> void:
	var bits: int = DIGITS[n]
	var c := Color("ffd98a")
	if bits & 0x40:
		p.GR(x + 2, y, 7, 2, c)  # a
	if bits & 0x20:
		p.GR(x + 9, y + 2, 2, 7, c)  # b
	if bits & 0x10:
		p.GR(x + 9, y + 10, 2, 7, c)  # c
	if bits & 0x08:
		p.GR(x + 2, y + 16, 7, 2, c)  # d
	if bits & 0x04:
		p.GR(x, y + 10, 2, 7, c)  # e
	if bits & 0x02:
		p.GR(x, y + 2, 2, 7, c)  # f
	if bits & 0x01:
		p.GR(x + 2, y + 8, 7, 2, c)  # g


## A hint of a lift bank: a steel door pair under an up/down indicator, with a call plate beside it.
static func _banks(p: Object, w: float, y: float) -> void:
	var run: Vector2i = p.repeats(40.0, BANK_STEP, int(ceil(w / BANK_STEP)), 80.0)
	for i: int in range(run.x, run.y):
		var bx: float = 40.0 + i * BANK_STEP
		if bx + 75.0 > w:
			continue
		p.item(bx - 3, y + 8, 66, 48, Color("8a7a60"), 2.0)
		p.item(bx, y + 16, 30, 40, STEEL, 0.0, false)
		p.item(bx + 30, y + 16, 30, 40, STEEL.darkened(0.06), 0.0, false)
		p.R(bx + 29, y + 16, 2, 40, Color("4a5260"))
		p.R(bx + 4, y + 20, 1, 32, STEEL.lightened(0.3))
		p.R(bx + 34, y + 20, 1, 32, STEEL.lightened(0.3))
		p.R(bx + 22, y + 11, 16, 4, Color("20242e"))
		p.GR(bx + 25, y + 12, 3, 2, Color("ffb050"))  # indicator: up
		p.GR(bx + 32, y + 12, 3, 2, Color("78d890"))  # and down
		p.item(bx + 66, y + 30, 4, 8, Color("c9a85c"), 1.0, false)
		p.GR(bx + 67, y + 32, 2, 2, Color("ff9a5a"))
		p.glow(bx + 30, y + 14, 40.0, 24.0, Color("ffd8a0"), 0.25)


## Sofa clusters every SEAT_STEP, each with a side table and a plant; more plants at the wall ends.
static func _seating(p: Object, w: float, fy: float) -> void:
	var run: Vector2i = p.repeats(150.0, SEAT_STEP, int(ceil(w / SEAT_STEP)), 150.0)
	for i: int in range(run.x, run.y):
		var sx: float = 150.0 + i * SEAT_STEP
		if sx + 100.0 > w:
			continue
		Scenes.sofa(p, sx, fy, Color("3f6f8c") if i % 2 == 0 else Color("8c5a3f"))
		Scenes.side_table(p, sx + 62.0, fy)
		Scenes.plant(p, sx + 100.0, fy, 32.0, Color("a8683c"))
	if w >= 120.0:
		Scenes.plant(p, 16, fy, 34.0, Color("a8683c"))
	if w >= 220.0:
		Scenes.plant(p, w - 16.0, fy, 30.0, Color("7a5a8a"))
