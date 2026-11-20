extends RefCounted
## Detailed drawing (#352) of the venue kinds the earlier batches left in the Classic look: the casino,
## nightclub and observation deck (group 1), then the eateries, shops and services. Composed from
## detail_furnish.gd, detail_scenes.gd and detail_prims.gd in the G Lit look, with the same frame as
## detail_shops.gd: every x, y, w, h is in mock-up pixels (half a world pixel) in the room's frame, `seats`
## are the figure centres of the recipe's activity spots (sorted), and a seat nothing stands at gets a piece
## of its own. Each kind has a silhouette of its own and its own lights, kept moderate (the world is dimmed).
## Every loop runs over a fixed count or steps a positive distance toward a limit.

const Furnish := preload("res://scripts/view/detail_furnish.gd")
const Scenes := preload("res://scripts/view/detail_scenes.gd")

const KINDS: Array[String] = ["casino", "nightclub", "observation_deck"]
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
