extends RefCounted
## Detailed drawing (#352) of the venue kinds the earlier batches left in the Classic look: the casino,
## nightclub and observation deck (groups 1 and 2), then the eateries, shops and services. Composed from
## detail_furnish.gd, detail_scenes.gd and detail_prims.gd in the G Lit look, with the same frame as
## detail_shops.gd: every x, y, w, h is in mock-up pixels (half a world pixel) in the room's frame, `seats`
## are the figure centres of the recipe's activity spots (sorted), and a seat nothing stands at gets a piece
## of its own. Each kind has a silhouette of its own and its own lights, kept moderate (the world is dimmed).
## Every loop runs over a fixed count or steps a positive distance toward a limit.

const Furnish := preload("res://scripts/view/detail_furnish.gd")
const Scenes := preload("res://scripts/view/detail_scenes.gd")

const KINDS: Array[String] = ["casino", "nightclub", "observation_deck", "cafe", "pizza", "sushi", "fine_dining", "bar"]
const BRASS := Color("c9a85c")
const FELT := Color("2f7a4a")
const REACH := 16.0


static func handles(kind: String) -> bool:
	return KINDS.has(kind)


## Paints one floor of `kind` into pen p. w is the room's width, y0 the row its floor starts at (mock-up pixels).
static func draw(p: Object, kind: String, w: int, y0: int, seats: Array, lit: bool, night: bool, id: int, pal: Array) -> void:
	var yt := float(y0)
	var fy := float(y0 + 58)
	var wf := float(w)
	Scenes.shell_room(p, 0, yt, w, id % 2, pal)
	var taken: Array = []
	match kind:
		"casino":
			_casino(p, wf, yt, fy, seats, lit, taken)
		"nightclub":
			_nightclub(p, wf, yt, fy, seats, lit, taken)
		"observation_deck":
			_deck(p, wf, yt, fy, seats, lit, night, id, taken)
		"cafe":
			_cafe(p, wf, yt, fy, seats, lit, night, id, taken)
		"pizza":
			_pizza(p, wf, yt, fy, seats, lit, taken)
		"sushi":
			_sushi(p, wf, yt, fy, seats, lit, taken)
		"fine_dining":
			_fine(p, wf, yt, fy, seats, lit, taken)
		"bar":
			_pub(p, wf, yt, fy, seats, lit, taken)
	_cover(p, seats, taken, fy)


static func _note(taken: Array, x0: float, x1: float) -> void:
	taken.append(Vector2(x0, x1))


static func _covered(taken: Array, c: float) -> bool:
	for t: Vector2 in taken:
		if c >= t.x - REACH and c <= t.y + REACH:
			return true
	return false


## Gives every seat no piece stands at a piece of its own.
static func _cover(p: Object, seats: Array, taken: Array, fy: float) -> void:
	for c: float in seats:
		if _covered(taken, c):
			continue
		Furnish.stool(p, c, fy)
		_note(taken, c - 8.0, c + 8.0)


## A neon sign: a dark plate with `n` letter blocks in `c`, lit when the room is.
static func _neon(p: Object, cx: float, y: float, n: int, c: Color, lit: bool) -> void:
	var sw := n * 7.0 + 4.0
	var sx := cx - sw * 0.5
	p.R(sx, y, sw, 14, Color("2a2230"))
	for k: int in n:
		if lit:
			p.GR(sx + 3 + k * 7, y + 3, 4, 8, c)
		else:
			p.R(sx + 3 + k * 7, y + 3, 4, 8, c.darkened(0.5))
	if lit:
		p.glow(cx, y + 7, sw * 0.8, 20.0, c, 0.4)


# ---------------------------------------------------------------- group 1

## The casino: a red carpet with a gold edge, a marquee of bulbs along the top, green-felt tables under hanging
## lamps and a bank of slot machines at the right.
static func _casino(p: Object, w: float, yt: float, fy: float, seats: Array, lit: bool, taken: Array) -> void:
	p.R(0, fy + 1, w, 3, Color("8a1f2c"))
	p.R(0, fy + 1, w, 1, BRASS)
	p.R(0, yt + 4, w, 7, Color("2a1220"))
	var bx := 4.0
	var k := 0
	while bx < w - 4.0:
		var bulb := Color("ffd84a") if k % 2 == 0 else Color("ff5a5a")
		if lit:
			p.GR(bx, yt + 6, 3, 3, bulb)
		else:
			p.R(bx, yt + 6, 3, 3, bulb.darkened(0.5))
		bx += 8.0
		k += 1
	if lit:
		p.glow(w * 0.5, yt + 8, w * 0.45, 14.0, Color("ffd070"), 0.3)
	_neon(p, 52.0, yt + 16, 6, Color("ffd84a"), lit)
	var sx := w - 74.0  # three tall slot machines with lit reels and a lever
	for i: int in 3:
		var mx := sx + i * 24.0
		p.shadow(mx + 9, fy, 12, 0.5)
		p.item(mx, fy - 36, 18, 36, Color("a8353a") if i % 2 == 0 else Color("3a5a9a"), 2.0)
		p.item(mx + 2, fy - 32, 14, 12, Color("1a1a22"), 1.0)
		for r: int in 3:
			if lit:
				p.GR(mx + 3 + r * 4, fy - 30, 3, 8, Color("f4f0e6"))
			else:
				p.R(mx + 3 + r * 4, fy - 30, 3, 8, Color("8a8a94"))
		p.R(mx + 4, fy - 18, 10, 3, BRASS)
		p.R(mx + 18, fy - 28, 2, 12, Color("c8453c"))
		p.ell(mx + 19, fy - 29, 2, 2, Color("c8453c"))
		if lit:
			p.glow(mx + 9, fy - 24, 16.0, 18.0, Color("ffe8a0"), 0.3)
	_note(taken, sx, sx + 72.0)
	for c: float in seats:  # a green-felt table with chips under a hanging lamp
		if c > sx - 12.0:
			continue
		Furnish.pendant(p, c, yt + 8, lit, 64.0, Color("6a1a28"))
		p.shadow(c, fy, 22, 0.5)
		p.item(c - 20, fy - 14, 40, 6, FELT, 3.0)
		p.R(c - 20, fy - 14, 40, 1, FELT.lightened(0.25))
		p.R(c - 17, fy - 8, 3, 8, Color("3a2018"))
		p.R(c + 14, fy - 8, 3, 8, Color("3a2018"))
		p.R(c - 4, fy - 16, 3, 2, Color("e8453c"))
		p.R(c + 1, fy - 16, 3, 2, Color("f4f0e6"))
		p.R(c - 4, fy - 18, 3, 2, Color("3a6aa8"))
		_note(taken, c - 20.0, c + 20.0)


## The nightclub: a stage with a disco ball and coloured spotlights, a tiled dance floor, high tables and a
## neon-lit bar at the right.
static func _nightclub(p: Object, w: float, yt: float, fy: float, seats: Array, lit: bool, taken: Array) -> void:
	var cols: Array[Color] = [Color("ff4aa8"), Color("4ac8ff"), Color("b84aff"), Color("ffd84a")]
	for i: int in int(w / 8.0) + 1:
		var t := cols[i % 4]
		p.R(i * 8, fy + 1, 8, 3, t.darkened(0.25) if lit else t.darkened(0.55))
	p.item(4, fy - 9, 56, 9, Color("2a2034"), 1.0)
	p.R(4, fy - 9, 56, 1, Color("e04aa8"))
	p.item(8, yt + 22, 48, 20, Color("1a1230"), 1.0)
	for k: int in 4:  # spotlight cans along the truss, each throwing a cone of colour
		var lx := 14.0 + k * 13.0
		p.R(lx - 3, yt + 8, 6, 3, Color("3a3a46"))
		if lit:
			p.GW(lx - 5, yt + 11, 10, 34, cols[k])
			p.glow(lx, yt + 36, 12.0, 26.0, cols[k], 0.35)
	p.R(6, yt + 7, 52, 1, Color("5a5a66"))
	p.R(31, yt + 2, 1, 6, Color("5a5a66"))
	p.ell(32, yt + 15, 6, 6, Color("c8d0d8"))
	for r: int in 4:
		for q: int in 4:
			if (r + q) % 2 == 0:
				p.R(27 + q * 3, yt + 11 + r * 3, 2, 2, Color("ffffff"))
	if lit:
		p.glow(32, yt + 18, 36.0, 28.0, Color("e8d8ff"), 0.4)
	_note(taken, 4.0, 60.0)
	var bw := 46.0
	var bx := w - bw - 8.0
	p.item(bx, yt + 22, bw, 4, Color("3a2a44"), 1.0)
	for i: int in 5:
		p.item(bx + 4 + i * 9, yt + 12, 4, 10, Color(Furnish.BOTTLES[i % 4]), 1.5, false)
	p.shadow(bx + bw * 0.5, fy, bw * 0.55, 0.55)
	p.item(bx, fy - 24, bw, 24, Color("2a1c38"), 2.0)
	if lit:
		p.GR(bx, fy - 25, bw, 2, Color("ff4aa8"))
		p.GR(bx + 2, fy - 4, bw - 4, 1, Color("4ac8ff"))
		p.glow(bx + bw * 0.5, fy - 14, bw * 0.8, 22.0, Color("c84aff"), 0.35)
	else:
		p.R(bx, fy - 25, bw, 2, Color("8a2a68"))
	for c: float in seats:  # a high cocktail table with a candle
		if c < 64.0 or c > bx - 4.0:
			continue
		p.shadow(c, fy, 9, 0.45)
		p.R(c - 1, fy - 18, 2, 18, Color("5a5a66"))
		p.R(c - 5, fy - 2, 10, 2, Color("5a5a66"))
		p.item(c - 8, fy - 22, 16, 4, Color("3a2a54"), 2.0)
		if lit:
			p.GR(c - 1, fy - 25, 2, 3, Color("ffd070"))
			p.glow(c, fy - 22, 14.0, 12.0, Color("ffb060"), 0.3)
		_note(taken, c - 10.0, c + 10.0)


## The observation deck: a wall of glass over the skyline, a brass handrail, telescopes on tripods and a bench.
static func _deck(p: Object, w: float, yt: float, fy: float, seats: Array, lit: bool, night: bool, id: int, taken: Array) -> void:
	Scenes.skyline(p, 4, yt + 4, w - 8, 34, night, id)
	var mx := 4.0
	while mx < w - 4.0:  # steel mullions, floor to ceiling
		p.R(mx, yt + 4, 2, 50, Color("8a94a4"))
		p.R(mx, yt + 4, 1, 50, Color("c8d0d8"))
		mx += 36.0
	p.R(4, yt + 38, w - 8, 16, Color("7a8aa0"))
	p.R(4, yt + 38, w - 8, 1, Color("c8d0d8"))
	p.R(0, yt + 46, w, 2, BRASS)
	p.R(0, yt + 46, w, 1, BRASS.lightened(0.3))
	var rx := 6.0
	while rx < w - 4.0:
		p.R(rx, yt + 48, 1, 8, BRASS.darkened(0.25))
		rx += 12.0
	var lx := 40.0
	while lx < w - 24.0:
		Scenes.ceiling_light(p, lx, yt, 28.0, lit, 56.0)
		lx += 96.0
	if night:
		p.glow(w * 0.5, yt + 20, w * 0.4, 26.0, Color("8aa8e8"), 0.18)
	for c: float in seats:  # a telescope on a tripod, aimed out through the glass
		p.shadow(c, fy, 10, 0.45)
		p.ln(Vector2(c, fy - 14), Vector2(c - 6, fy), Color("5a5a66"), 1.0)
		p.ln(Vector2(c, fy - 14), Vector2(c + 6, fy), Color("5a5a66"), 1.0)
		p.ln(Vector2(c, fy - 14), Vector2(c, fy - 1), Color("5a5a66"), 1.0)
		p.item(c - 9, fy - 26, 18, 6, Color("2a3a54"), 2.0)
		p.R(c - 11, fy - 25, 3, 4, BRASS)
		p.R(c + 8, fy - 25, 2, 4, Color("e8e8f0"))
		_note(taken, c - 12.0, c + 12.0)
	var bx := w - 62.0
	p.shadow(bx + 20, fy, 24, 0.45)
	p.item(bx, fy - 12, 40, 5, Color("7a4a32"), 2.0)
	p.item(bx, fy - 20, 40, 6, Color("8a5a38"), 2.0)
	p.R(bx + 2, fy - 7, 2, 7, Color("3a2a22"))
	p.R(bx + 36, fy - 7, 2, 7, Color("3a2a22"))
	_note(taken, bx, bx + 40.0)


# ---------------------------------------------------------------- group 2

## A small round table on one leg with a chair back either side, centred on c.
static func _round_table(p: Object, c: float, fy: float, top: Color, chair: Color, wide: float = 24.0) -> void:
	p.shadow(c, fy, wide * 0.6, 0.45)
	p.R(c - 1, fy - 14, 2, 14, Color("4a4a56"))
	p.R(c - 5, fy - 2, 10, 2, Color("4a4a56"))
	p.item(c - wide * 0.5, fy - 18, wide, 4, top, 2.0)
	p.item(c - wide * 0.5 - 4, fy - 20, 4, 20, chair, 1.5, false)
	p.item(c + wide * 0.5, fy - 20, 4, 20, chair, 1.5, false)


## The cafe: striped awnings over street windows, a chalkboard menu, bistro tables with a flower, and a
## pastry case with an espresso machine at the right.
static func _cafe(p: Object, w: float, yt: float, fy: float, seats: Array, lit: bool, night: bool, id: int, taken: Array) -> void:
	var wx := 14.0
	var k := 0
	while wx + 40.0 <= w - 76.0:
		Scenes.window(p, wx, yt + 12, 40, 24, Color("f6ecd6"), Color(0, 0, 0, 0), id + k * 3 + 11, night)
		Furnish.awning(p, wx - 5, yt + 5, 50.0, Color("3f7a5a"), Color("f4ecdc"))
		wx += 56.0
		k += 1
	var cx := w - 66.0
	p.shadow(cx + 28, fy, 32, 0.5)
	p.item(cx, fy - 22, 56, 22, Color("8a5a38"), 2.0)
	p.item(cx - 2, fy - 25, 60, 4, Color("e8d8b8"), 1.5)
	p.item(cx + 4, fy - 40, 30, 15, Color("a8d8e8"), 2.0, false)  # the glass pastry case
	p.R(cx + 5, fy - 33, 28, 1, Color("c8d0d8"))
	p.R(cx + 8, fy - 31, 6, 5, Color("e8b458"))
	p.R(cx + 18, fy - 31, 6, 5, Color("c8453c"))
	p.R(cx + 27, fy - 31, 5, 5, Color("f4ecdc"))
	p.item(cx + 38, fy - 38, 14, 13, Color("5a5a66"), 1.5)  # the espresso machine
	p.R(cx + 40, fy - 34, 10, 2, Color("c8d0d8"))
	if lit:
		p.GW(cx + 4, fy - 40, 30, 15, Color("ffe8a0"))
		p.glow(cx + 28, fy - 30, 40.0, 26.0, Color("ffd890"), 0.35)
	_note(taken, cx, cx + 56.0)
	Furnish.chalkboard(p, w - 100.0, yt + 8.0, 32.0, 24.0)
	for c: float in seats:
		if c > cx - 10.0:
			continue
		Furnish.pendant(p, c, yt + 2, lit, 60.0, Color("3f7a5a"))
		_round_table(p, c, fy, Color("e8c8a0"), Color("5a8a6a"))
		p.R(c - 1, fy - 24, 2, 4, Color("3f8a52"))  # a flower in a jar
		p.R(c - 2, fy - 26, 4, 2, Color("e87aa8"))
		_note(taken, c - 16.0, c + 16.0)


## The pizzeria: a domed brick oven with a fire in it, red-and-white checked tables, a string of flag bunting.
static func _pizza(p: Object, w: float, yt: float, fy: float, seats: Array, lit: bool, taken: Array) -> void:
	var bx := w - 64.0  # the oven at the right: a brick dome, a mouth, a fire and a flue
	p.shadow(bx + 26, fy, 30, 0.5)
	p.item(bx, fy - 26, 52, 26, Color("a8553a"), 2.0)
	for r: int in 3:
		p.R(bx + 2, fy - 22 + r * 7, 48, 1, Color("7a3a2a"))
	p.ell(bx + 26, fy - 28, 20, 14, Color("b8603e"))
	p.R(bx + 18, fy - 44, 8, 10, Color("5a3a30"))
	p.ell(bx + 26, fy - 14, 11, 9, Color("1a1214"))
	if lit:
		p.GR(bx + 19, fy - 13, 14, 7, Color("ff9a30"))
		p.GR(bx + 23, fy - 16, 6, 4, Color("ffd860"))
		p.glow(bx + 26, fy - 16, 54.0, 32.0, Color("ff8a3a"), 0.45)
	else:
		p.R(bx + 19, fy - 11, 14, 4, Color("4a2a20"))
	p.R(bx - 10, fy - 30, 3, 30, Color("8a6a48"))  # a peel against the wall
	p.R(bx - 12, fy - 36, 7, 6, Color("a88a60"))
	_note(taken, bx - 12.0, bx + 52.0)
	var flags: Array[Color] = [Color("3f8a52"), Color("f4f0e6"), Color("c8453c")]
	var x := 4.0  # bunting in the flag colours along the wall
	var k := 0
	while x < w - 8.0:
		var c := flags[k % 3]
		p.R(x, yt + 8, 8, 1, Color("5a4a3a"))
		p.R(x + 1, yt + 9, 6, 2, c)
		p.R(x + 2, yt + 11, 4, 2, c)
		x += 8.0
		k += 1
	for c: float in seats:
		if c > bx - 14.0:
			continue
		p.shadow(c, fy, 16, 0.45)
		p.R(c - 1, fy - 14, 2, 14, Color("5a3a28"))
		p.R(c - 5, fy - 2, 10, 2, Color("5a3a28"))
		p.item(c - 14, fy - 18, 28, 4, Color("c8453c"), 2.0)
		for q: int in 4:  # the checks of the cloth
			p.R(c - 13 + q * 7, fy - 18, 3, 2, Color("f4f0e6"))
		p.R(c - 5, fy - 21, 10, 3, Color("e8b458"))  # a pizza on the table
		p.R(c - 3, fy - 22, 2, 1, Color("c8453c"))
		p.item(c - 19, fy - 20, 4, 20, Color("7a4a32"), 1.5, false)
		p.item(c + 15, fy - 20, 4, 20, Color("7a4a32"), 1.5, false)
		_note(taken, c - 19.0, c + 19.0)


## The sushi bar: a long counter with a belt of plates, stools in front, red paper lanterns and a noren curtain.
static func _sushi(p: Object, w: float, yt: float, fy: float, seats: Array, lit: bool, taken: Array) -> void:
	var cx0 := 10.0
	var cw := w - 20.0
	p.shadow(cx0 + cw * 0.5, fy, cw * 0.5, 0.5)
	p.item(cx0, fy - 22, cw, 22, Color("6a4228"), 2.0)
	p.item(cx0 - 2, fy - 27, cw + 4, 5, Color("c8a470"), 2.0)  # the pale wood top, with the belt on it
	p.R(cx0 - 2, fy - 27, cw + 4, 1, Color("e0c898"))
	p.R(cx0 + 2, fy - 25, cw - 4, 1, Color("3a3a46"))
	var plates: Array[Color] = [Color("c8453c"), Color("3a6aa8"), Color("e8b458")]
	var px := cx0 + 8.0
	var k := 0
	while px < cx0 + cw - 12.0:  # plates of sushi riding the belt
		p.R(px, fy - 32, 8, 2, plates[k % 3])
		p.R(px + 1, fy - 34, 6, 2, Color("f4f0e6"))
		p.R(px + 2, fy - 35, 4, 1, Color("e87a5a"))
		px += 22.0
		k += 1
	var lx := 24.0
	while lx < w - 20.0:  # red paper lanterns
		p.R(lx, yt + 4, 1, 10, Color("2a2230"))
		p.item(lx - 6, yt + 14, 12, 14, Color("c8353a"), 5.0, false)
		p.R(lx - 4, yt + 18, 8, 1, Color("8a1f2c"))
		if lit:
			p.GW(lx - 6, yt + 14, 12, 14, Color("ffd890"))
			p.glow(lx, yt + 22, 26.0, 22.0, Color("ff9a60"), 0.35)
		lx += 56.0
	var nx := w - 36.0  # the noren curtain over a door
	p.R(nx, yt + 6, 28, 2, Color("3a2a22"))
	for i: int in 4:
		p.R(nx + 1 + i * 7, yt + 8, 6, 14, Color("2a3a6a"))
		p.R(nx + 3 + i * 7, yt + 12, 2, 5, Color("f4f0e6"))
	for c: float in seats:
		Furnish.stool(p, c, fy + 4.0, Color("3a2a22"))
		_note(taken, c - 8.0, c + 8.0)
	_note(taken, cx0, cx0 + cw)


## Fine dining: burgundy drapes, a brass chandelier over each white-clothed table with a candle and glasses, and
## a wine rack at the right.
static func _fine(p: Object, w: float, yt: float, fy: float, seats: Array, lit: bool, taken: Array) -> void:
	var drape := Color("7a1f34")
	var dx := 6.0
	while dx < w - 90.0:  # tall drapes
		for i: int in 3:
			p.R(dx + i * 3, yt + 6, 2, 46, drape if i % 2 == 0 else drape.darkened(0.25))
		p.R(dx, yt + 6, 9, 2, BRASS)
		dx += 60.0
	var rx := w - 70.0  # the wine rack: a grid of bottle ends
	p.item(rx, fy - 54, 56, 54, Color("4a2a1c"), 1.5)
	for r: int in 5:
		for q: int in 6:
			p.ell(rx + 6 + q * 9, fy - 48 + r * 10, 3, 3, Color("2a1220") if (r + q) % 3 != 0 else Color("8a5a38"))
	_note(taken, rx, rx + 56.0)
	for c: float in seats:
		if c > rx - 14.0:
			continue
		p.R(c, yt + 4, 1, 8, BRASS.darkened(0.2))  # the chandelier
		p.item(c - 12, yt + 12, 24, 3, BRASS, 1.5)
		for q: int in 3:
			p.R(c - 10 + q * 10, yt + 9, 1, 3, BRASS)
			if lit:
				p.GR(c - 10 + q * 10, yt + 7, 1, 2, Color("fff0c0"))
		if lit:
			p.glow(c, yt + 20, 48.0, 36.0, Color("ffd890"), 0.45)
		p.shadow(c, fy, 18, 0.5)
		p.R(c - 1, fy - 14, 2, 14, Color("4a4a56"))
		p.item(c - 16, fy - 18, 32, 5, Color("f8f4ea"), 2.0)
		p.R(c - 16, fy - 14, 32, 2, Color("e0d8c4"))
		p.R(c - 1, fy - 24, 2, 6, Color("f4ecdc"))  # the candle
		if lit:
			p.GR(c - 1, fy - 26, 2, 2, Color("ffd060"))
		p.R(c + 6, fy - 24, 2, 6, Color("a8d8e8"))
		p.R(c - 9, fy - 23, 2, 5, Color("a8d8e8"))
		p.item(c - 22, fy - 26, 5, 26, drape.darkened(0.1), 2.0, false)  # high-backed chairs
		p.item(c + 17, fy - 26, 5, 26, drape.darkened(0.1), 2.0, false)
		_note(taken, c - 22.0, c + 22.0)


## The bar: a long wooden counter under a lit bottle shelf, amber lamps, a neon sign and a dartboard.
static func _pub(p: Object, w: float, yt: float, fy: float, seats: Array, lit: bool, taken: Array) -> void:
	var bw := w - 56.0
	var bx := 8.0
	p.item(bx + 4, yt + 20, bw - 8, 4, Color("7a4e32"), 1.0)  # the shelf and its bottles
	var i := 0
	while 10.0 + i * 9.0 < bw - 12.0:
		var c := Color(Furnish.BOTTLES[i % 4])
		p.item(bx + 8 + i * 9, yt + 9, 4, 11, c, 1.5, false)
		p.R(bx + 9 + i * 9, yt + 6, 2, 3, c.darkened(0.2))
		i += 1
	if lit:
		p.GW(bx + 4, yt + 5, bw - 8, 20, Color("ffc060"))
		p.glow(bx + bw * 0.5, yt + 16, bw * 0.5, 20.0, Color("ffb050"), 0.3)
	p.shadow(bx + bw * 0.5, fy, bw * 0.5, 0.55)
	p.item(bx, fy - 24, bw, 24, Color("5a3524"), 2.0)
	p.item(bx - 3, fy - 28, bw + 6, 5, Color("c89a62"), 2.0)
	p.R(bx + 4, fy - 21, bw - 8, 1, BRASS)
	p.R(bx + 4, fy - 5, bw - 8, 1, BRASS)  # the foot rail
	var taps := bx + bw * 0.5 - 12.0  # three beer taps
	for q: int in 3:
		p.R(taps + q * 8, fy - 36, 2, 8, BRASS)
	p.R(taps - 1, fy - 37, 20, 2, Color("8a94a4"))
	_note(taken, bx, bx + bw)
	var sx := w - 44.0  # a dartboard and a neon sign
	p.ell(sx + 14, yt + 22, 9, 9, Color("2a2230"))
	p.ell(sx + 14, yt + 22, 6, 6, Color("c8453c"))
	p.ell(sx + 14, yt + 22, 3, 3, Color("f4f0e6"))
	p.R(sx + 13, yt + 21, 2, 2, Color("3f8a52"))
	_neon(p, sx + 14, yt + 36, 3, Color("ffb040"), lit)
	Furnish.pendant(p, w - 20.0, yt, lit, 56.0, Color("8a5a38"))
	for c: float in seats:
		Furnish.stool(p, c, fy + 4.0, Color("8a3a30"))
		_note(taken, c - 8.0, c + 8.0)
