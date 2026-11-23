extends RefCounted
## Detailed drawing (#352) of the venue kinds the earlier batches left in the Classic look: the casino,
## nightclub and observation deck (all four groups: venues, eateries, shops and services). Composed from
## detail_furnish.gd, detail_scenes.gd and detail_prims.gd in the G Lit look, with the same frame as
## detail_shops.gd: every x, y, w, h is in mock-up pixels (half a world pixel) in the room's frame, `seats`
## are the figure centres of the recipe's activity spots (sorted), and a seat nothing stands at gets a piece
## of its own. Each kind has a silhouette of its own and its own lights, kept moderate (the world is dimmed).
## Every loop runs over a fixed count or steps a positive distance toward a limit.

const Furnish := preload("res://scripts/view/detail_furnish.gd")
const Scenes := preload("res://scripts/view/detail_scenes.gd")

const KINDS: Array[String] = ["casino", "nightclub", "observation_deck", "helipad", "cafe", "pizza", "sushi", "fine_dining", "bar", "grocery", "deli", "gym", "daycare", "school", "clinic", "coworking"]
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
		"helipad":
			_pad(p, wf, yt, fy, lit, night, id, taken)
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
		"grocery":
			_grocery(p, wf, yt, fy, seats, lit, id, taken)
		"deli":
			_deli(p, wf, yt, fy, seats, lit, taken)
		"gym":
			_gym(p, wf, yt, fy, seats, lit, taken)
		"daycare":
			_daycare(p, wf, yt, fy, seats, lit, taken)
		"school":
			_school(p, wf, yt, fy, seats, lit, taken)
		"clinic":
			_clinic(p, wf, yt, fy, seats, lit, taken)
		"coworking":
			_cowork(p, wf, yt, fy, seats, lit, taken)
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


## The helicopter pad (#409): open sky over the skyline, a steel landing platform with a painted H, and a
## beacon on a mast that is lit at night. Drawn over the shell so the roof reads as open air.
static func _pad(p: Object, w: float, yt: float, fy: float, lit: bool, night: bool, id: int, taken: Array) -> void:
	p.gradv(4, yt + 4, w - 8, 36, Scenes.sky_col(night, yt + 4.0), Scenes.sky_col(night, yt + 40.0))
	Scenes.skyline(p, 4, yt + 4, w - 8, 34, night, id)
	var cx := w * 0.5
	var pw := minf(w - 40.0, 150.0)
	p.R(cx - pw * 0.5, fy - 6, pw, 6, Color("5a6270"))  # the platform
	p.R(cx - pw * 0.5, fy - 6, pw, 1, Color("c8d0d8"))
	p.R(cx - pw * 0.5, fy - 1, pw, 1, Color("3a424e"))
	var rim := cx - pw * 0.5
	while rim < cx + pw * 0.5 - 2.0:  # a rim of yellow dashes; rim steps 10 toward the limit
		p.R(rim, fy - 5, 4, 1, Color("e8c040"))
		rim += 10.0
	p.R(cx - 11, fy - 22, 3, 17, Color("f4f0e6"))  # the H: two legs and a bar
	p.R(cx + 8, fy - 22, 3, 17, Color("f4f0e6"))
	p.R(cx - 8, fy - 15, 16, 3, Color("f4f0e6"))
	var mx := cx + pw * 0.5 + 6.0  # the beacon on a mast at the platform's edge
	p.R(mx, fy - 30, 2, 30, Color("8a94a4"))
	p.R(mx - 2, fy - 34, 6, 5, Color("c8453c"))
	if lit or night:
		p.GR(mx - 1, fy - 33, 4, 3, Color("ff6a5a"))
		p.glow(mx + 1, fy - 31, 18.0, 16.0, Color("ff5040"), 0.45)
	_note(taken, cx - pw * 0.5, mx + 4.0)


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


# ---------------------------------------------------------------- group 3

## The grocery: tall aisle shelving stocked in bands at each seat, a produce crate at its foot, hanging aisle
## signs, and a checkout lane with a belt at the right.
static func _grocery(p: Object, w: float, yt: float, fy: float, seats: Array, lit: bool, id: int, taken: Array) -> void:
	var lx := 40.0
	while lx < w - 20.0:
		Scenes.ceiling_light(p, lx, yt, 32.0, lit, 60.0)
		lx += 80.0
	var kx := w - 70.0  # the checkout: a belt, a till and a basket stack
	p.shadow(kx + 28, fy, 32, 0.5)
	p.item(kx, fy - 18, 44, 18, Color("5a6a7a"), 2.0)
	p.R(kx + 2, fy - 18, 40, 2, Color("2a2a32"))
	p.R(kx + 6, fy - 20, 8, 2, Color("e8b458"))
	p.R(kx + 22, fy - 20, 6, 2, Color("c8453c"))
	Furnish.till(p, kx + 44.0, fy, 22.0, lit)
	p.item(kx + 2, fy - 30, 12, 4, Color("c8453c"), 1.0)
	p.item(kx + 3, fy - 26, 12, 4, Color("e0a83a"), 1.0)
	_note(taken, kx, kx + 66.0)
	var fruit: Array[Color] = [Color("3f8a52"), Color("c8453c"), Color("e0a83a"), Color("e87a3a")]
	for c: float in seats:
		if c > kx - 14.0:
			continue
		Furnish.shelf_unit(p, c - 22.0, fy, 44.0, 54.0, id + int(c))
		for q: int in 4:  # a crate of produce at the foot of the shelves
			p.item(c - 20 + q * 10, fy - 7, 9, 7, Color("8a5a38"), 1.0)
			p.R(c - 19 + q * 10, fy - 10, 7, 3, fruit[(q + int(c)) % 4])
		p.R(c - 12, yt + 6, 24, 1, Color("2a2230"))  # an aisle sign
		p.R(c - 12, yt + 7, 24, 5, Color("3f8a52"))
		p.R(c - 8, yt + 8, 16, 1, Color("f4f0e6"))
		_note(taken, c - 22.0, c + 22.0)
	p.R(0, yt + 38, w, 1, Color("3f8a52"))


## The deli: one long counter with a glass case of meats and cheeses, sausages hanging on hooks, a menu board
## and stools along the front.
static func _deli(p: Object, w: float, yt: float, fy: float, seats: Array, lit: bool, taken: Array) -> void:
	for i: int in int(w / 8.0) + 1:  # a tiled floor
		p.R(i * 8, fy + 1, 4, 3, Color("f4f0e6") if i % 2 == 0 else Color("b8453c"))
	Furnish.menu_board(p, 8.0, yt + 6.0, 56.0, 28.0, lit)
	var hx := 76.0
	while hx < w - 20.0:  # a rail of hanging sausages
		p.R(hx, yt + 8, 24, 1, Color("5a5a66"))
		for q: int in 4:
			p.R(hx + 2 + q * 6, yt + 9, 1, 3, Color("5a5a66"))
			p.item(hx + 1 + q * 6, yt + 12, 3, 12, Color("a8453c") if q % 2 == 0 else Color("8a5a38"), 1.5, false)
		hx += 40.0
	var cx0 := 8.0
	var cw := w - 16.0
	p.shadow(cx0 + cw * 0.5, fy, cw * 0.5, 0.5)
	p.item(cx0, fy - 22, cw, 22, Color("e4dccb"), 2.0)
	p.R(cx0, fy - 8, cw, 2, Color("b8453c"))
	p.item(cx0, fy - 38, cw, 14, Color("a8d8e8"), 2.0, false)  # the glass case
	var foods: Array[Color] = [Color("c8453c"), Color("e8b458"), Color("f0d8b0"), Color("8a4a3a")]
	var mx := cx0 + 4.0
	var k := 0
	while mx + 10.0 < cx0 + cw:
		p.R(mx, fy - 33, 10, 6, foods[k % 4])
		p.R(mx + 1, fy - 34, 8, 1, foods[k % 4].lightened(0.25))
		mx += 14.0
		k += 1
	p.R(cx0, fy - 24, cw, 1, Color("c8d0d8"))
	if lit:
		p.GW(cx0, fy - 38, cw, 14, Color("ffe8a0"))
		p.glow(cx0 + cw * 0.5, fy - 30, cw * 0.4, 22.0, Color("ffe0a0"), 0.3)
	_note(taken, cx0, cx0 + cw)
	for c: float in seats:
		Furnish.stool(p, c, fy + 4.0, Color("b8453c"))
		_note(taken, c - 8.0, c + 8.0)


# ---------------------------------------------------------------- group 4

## The gym: a rubber floor, a mirror wall, a treadmill at each seat and a rack of dumbbells and a bench at the right.
static func _gym(p: Object, w: float, yt: float, fy: float, seats: Array, lit: bool, taken: Array) -> void:
	p.R(0, fy + 1, w, 3, Color("2e2e36"))
	p.item(6, yt + 12, w - 12.0, 28, Color("a8c8d8"), 1.0)  # the mirror wall, with glints
	var gx := 12.0
	while gx < w - 20.0:
		p.R(gx, yt + 14, 2, 24, Color("d8ecf4"))
		p.R(gx + 6, yt + 18, 1, 16, Color("d8ecf4"))
		gx += 34.0
	p.R(6, yt + 4, w - 12.0, 5, Color("e8a030"))  # a banner band
	for q: int in int((w - 20.0) / 24.0):
		p.R(10 + q * 24, yt + 6, 12, 1, Color("2a2a32"))
	var rx := w - 66.0
	p.shadow(rx + 24, fy, 28, 0.5)
	p.item(rx, fy - 20, 44, 4, Color("5a5a66"), 1.0)  # a rack, two tiers of dumbbells
	p.R(rx + 2, fy - 16, 2, 16, Color("3a3a46"))
	p.R(rx + 40, fy - 16, 2, 16, Color("3a3a46"))
	p.item(rx, fy - 10, 44, 3, Color("5a5a66"), 1.0)
	for q: int in 6:
		p.item(rx + 4 + q * 7, fy - 25, 5, 5, Color("2a2a32"), 1.0)
		p.item(rx + 4 + q * 7, fy - 15, 5, 5, Color("c8453c") if q % 2 == 1 else Color("3a6aa8"), 1.0)
	p.item(rx + 46, fy - 8, 18, 4, Color("3a3a46"), 1.5)  # a bench with a barbell over it
	p.R(rx + 46, fy - 22, 22, 2, Color("8a94a4"))
	p.item(rx + 44, fy - 25, 3, 8, Color("2a2a32"), 1.0)
	p.item(rx + 66, fy - 25, 3, 8, Color("2a2a32"), 1.0)
	_note(taken, rx, rx + 70.0)
	for c: float in seats:
		if c > rx - 12.0:
			continue
		p.shadow(c, fy, 18, 0.5)
		p.item(c - 18, fy - 6, 32, 6, Color("3a3a46"), 1.5)  # the deck and belt
		p.R(c - 16, fy - 4, 28, 1, Color("6a6a76"))
		p.item(c - 18, fy - 34, 3, 28, Color("5a5a66"), 1.0, false)  # the upright and console
		p.item(c - 22, fy - 38, 14, 7, Color("2a2a32"), 1.5)
		if lit:
			p.GR(c - 20, fy - 36, 10, 3, Color("5ae08a"))
		else:
			p.R(c - 20, fy - 36, 10, 3, Color("3a4a42"))
		p.R(c - 14, fy - 28, 14, 2, Color("8a94a4"))
		_note(taken, c - 22.0, c + 14.0)
	if lit:
		p.glow(w * 0.5, yt + 26, w * 0.4, 20.0, Color("d8f0ff"), 0.2)


## The daycare: a rainbow band on the wall, a play mat of coloured squares, small tables with kid chairs and a
## block on each, a cubby shelf at the right and mobiles of toys.
static func _daycare(p: Object, w: float, yt: float, fy: float, seats: Array, lit: bool, taken: Array) -> void:
	var rainbow: Array[Color] = [Color("e87a68"), Color("f0b84a"), Color("8ac870"), Color("5ab0d8"), Color("a88ad8")]
	for q: int in 5:
		p.R(0, yt + 6 + q * 2, w, 2, rainbow[q])
	for i: int in int(w / 10.0) + 1:  # the play mat
		p.R(i * 10, fy + 1, 10, 3, rainbow[i % 5].lightened(0.15))
	p.ell(36, yt + 28, 9, 9, Color("fff0a0"))  # a painted sun
	for q: int in 8:
		var ang := q * 0.785
		p.R(36.0 + cos(ang) * 13.0, yt + 28.0 + sin(ang) * 13.0, 2, 2, Color("f0b84a"))
	var cx := w - 52.0  # a cubby shelf with bins
	p.item(cx, fy - 40, 44, 40, Color("c89a62"), 1.5)
	for r: int in 2:
		for q: int in 3:
			p.item(cx + 3 + q * 14, fy - 37 + r * 18, 12, 15, Color("8a5a38"), 1.0)
			p.R(cx + 5 + q * 14, fy - 35 + r * 18, 8, 5, rainbow[(q + r * 3) % 5])
	_note(taken, cx, cx + 44.0)
	var mx := 80.0  # mobiles of toys
	while mx < cx - 20.0:
		p.R(mx, yt + 20, 1, 4, Color("5a5a66"))
		p.R(mx - 8, yt + 24, 16, 1, Color("5a5a66"))
		p.R(mx - 8, yt + 25, 3, 6, rainbow[int(mx) % 5])
		p.R(mx + 5, yt + 25, 3, 6, rainbow[(int(mx) + 2) % 5])
		mx += 70.0
	if lit:
		p.glow(w * 0.5, yt + 26, w * 0.4, 22.0, Color("fff0c8"), 0.25)
	for c: float in seats:
		if c > cx - 12.0:
			continue
		var tone := int(c / 8.0)
		p.shadow(c, fy, 16, 0.45)
		p.item(c - 14, fy - 14, 28, 4, rainbow[tone % 5], 2.0)  # a low table
		p.R(c - 12, fy - 10, 3, 10, Color("8a5a38"))
		p.R(c + 9, fy - 10, 3, 10, Color("8a5a38"))
		p.item(c - 18, fy - 12, 4, 12, rainbow[(tone + 2) % 5], 1.5, false)  # kid chairs
		p.item(c + 14, fy - 12, 4, 12, rainbow[(tone + 3) % 5], 1.5, false)
		p.item(c - 4, fy - 20, 6, 6, Color("e0a83a"), 1.0)  # an alphabet block
		p.R(c - 2, fy - 18, 2, 2, Color("2a2230"))
		_note(taken, c - 18.0, c + 18.0)


## The school: a green chalkboard with a ruled chalk line and a clock on the wall, a globe at the right,
## and a wooden desk with a chair and an open book at each seat.
static func _school(p: Object, w: float, yt: float, fy: float, seats: Array, lit: bool, taken: Array) -> void:
	p.item(24, yt + 8, 90, 34, Color("8a5a38"), 2.0)  # the board frame
	p.R(27, yt + 11, 84, 28, Color("2e5a46"))
	p.R(33, yt + 19, 52, 1, Color("e8e8dc"))
	p.R(33, yt + 27, 38, 1, Color("e8e8dc"))
	p.R(88, yt + 33, 8, 2, Color("f0f0e4"))  # chalk on the ledge
	p.ell(w * 0.5, yt + 18, 7, 7, Color("f4f0e0"))  # a wall clock
	p.R(w * 0.5, yt + 12, 1, 6, Color("2a2230"))
	p.R(w * 0.5, yt + 18, 4, 1, Color("2a2230"))
	var gx := w - 44.0  # a globe on a stand
	p.R(gx + 10, fy - 14, 3, 14, Color("5a3a28"))
	p.ell(gx + 11, fy - 22, 9, 9, Color("4a8ac8"))
	p.R(gx + 6, fy - 25, 5, 3, Color("6ab060"))
	_note(taken, gx - 2.0, gx + 26.0)
	if lit:
		p.glow(w * 0.5, yt + 26, w * 0.4, 22.0, Color("fff4d0"), 0.22)
	for c: float in seats:
		if c > gx - 16.0:
			continue
		p.shadow(c, fy, 14, 0.4)
		p.item(c - 12, fy - 13, 24, 3, Color("c89a62"), 1.5)  # a desk top
		p.R(c - 10, fy - 10, 2, 10, Color("8a5a38"))
		p.R(c + 8, fy - 10, 2, 10, Color("8a5a38"))
		p.R(c - 5, fy - 16, 10, 3, Color("f4f0e0"))  # an open book
		p.R(c, fy - 16, 1, 3, Color("8a5a38"))
		p.item(c - 18, fy - 12, 4, 12, Color("a84e3a"), 1.5, false)  # a chair
		_note(taken, c - 18.0, c + 14.0)


## The clinic: a reception desk under a red cross, waiting chairs at each seat, an eye chart and an exam bed
## behind a curtain at the right.
static func _clinic(p: Object, w: float, yt: float, fy: float, seats: Array, lit: bool, taken: Array) -> void:
	var lx := 40.0
	while lx < w - 20.0:
		Scenes.ceiling_light(p, lx, yt, 30.0, lit, 56.0)
		lx += 90.0
	var bx := w - 76.0
	p.item(bx - 4, yt + 8, 4, 46, Color("a8d0d0"), 1.0)  # the curtain rail, its drape and the bed
	for q: int in 6:
		p.R(bx + q * 2, yt + 8, 2, 20, Color("a8d8d0") if q % 2 == 0 else Color("88c0b8"))
	Furnish.hospital_bed(p, bx + 14.0, fy, lit)
	Furnish.iv_stand(p, bx + 58.0, fy)
	_note(taken, bx, bx + 66.0)
	Furnish.red_cross(p, 40.0, yt + 10.0, 14.0, lit)
	p.item(70, yt + 10, 14, 20, Color("f4f0e6"), 1.0)  # an eye chart
	for q: int in 5:
		p.R(73, yt + 13 + q * 3, 8 - q, 1, Color("2a2a32"))
	Furnish.service_desk(p, 6.0, fy, 56.0, lit)
	_note(taken, 6.0, 62.0)
	for c: float in seats:
		if c < 64.0 or c > bx - 10.0:
			continue
		Furnish.waiting_chair(p, c, fy, Color("5a9aa8"))
		p.item(c + 12, fy - 12, 8, 3, Color("f4f0e6"), 1.0)  # a magazine on a side table
		p.R(c + 15, fy - 9, 2, 9, Color("8a94a4"))
		_note(taken, c - 10.0, c + 20.0)


## The coworking space: hot desks with a monitor and laptop at each seat, glass partitions, warm pendants and a
## coffee corner with a plant at the right.
static func _cowork(p: Object, w: float, yt: float, fy: float, seats: Array, lit: bool, taken: Array) -> void:
	var cx := w - 64.0  # the coffee corner: a counter, a machine and a plant
	p.shadow(cx + 24, fy, 28, 0.5)
	p.item(cx, fy - 22, 48, 22, Color("7a5a3a"), 2.0)
	p.item(cx - 2, fy - 25, 52, 4, Color("e8e0d0"), 1.5)
	p.item(cx + 6, fy - 40, 14, 15, Color("3a3a46"), 1.5)
	p.R(cx + 9, fy - 36, 8, 2, Color("e8453c") if lit else Color("6a3a3a"))
	p.item(cx + 28, fy - 32, 8, 7, Color("f4f0e6"), 1.5)
	Scenes.plant(p, cx + 56.0, fy, 30.0, Color("a8683c"))
	if lit:
		p.glow(cx + 14, fy - 30, 28.0, 20.0, Color("ffd890"), 0.3)
	_note(taken, cx, cx + 62.0)
	p.item(6, yt + 12, 34, 22, Color("e8b040"), 1.0)  # a mural on the wall
	p.R(10, yt + 18, 12, 10, Color("3a6aa8"))
	p.ell(30, yt + 24, 5, 5, Color("c8453c"))
	for c: float in seats:
		if c > cx - 12.0:
			continue
		Furnish.pendant(p, c, yt + 2, lit, 58.0, Color("8a6a3a"))
		p.shadow(c, fy, 22, 0.5)
		p.item(c - 22, fy - 16, 44, 4, Color("d8c8a8"), 1.5)  # the desk
		p.R(c - 20, fy - 12, 3, 12, Color("5a5a66"))
		p.R(c + 17, fy - 12, 3, 12, Color("5a5a66"))
		p.item(c - 4, fy - 30, 14, 10, Color("2a2f3c"), 1.5)  # the monitor and its stand
		p.R(c + 1, fy - 20, 4, 4, Color("5a5a66"))
		if lit:
			p.GR(c - 2, fy - 28, 10, 6, Color("8ad0e8"))
		else:
			p.R(c - 2, fy - 28, 10, 6, Color("3a4a58"))
		p.item(c - 18, fy - 19, 10, 3, Color("8a94a4"), 1.0)  # a laptop
		p.item(c - 22, fy - 28, 3, 28, Color("a8d8e8"), 0.0, false)  # a glass partition
		_note(taken, c - 22.0, c + 22.0)
