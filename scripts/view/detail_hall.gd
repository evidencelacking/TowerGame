extends RefCounted
## Detailed drawing (#303) of the batch 3 rooms, the halls where people gather: the movie theatre (a lit
## screen with curtains, velvet seats, a projection booth on the upper floor), the party hall (stage, disco
## ball, bunting, cocktail tables), the metro station (a train at the platform, benches, a destination board)
## and the cathedral (stained glass, a rose window, pews, an altar). Composed from detail_furnish.gd and
## detail_scenes.gd in the G Lit look. As in detail_shops.gd the furniture is placed from the recipe's
## activity spots, which arrive here as `seats` (the centre of each figure in mock-up pixels, sorted), so
## people sit in the seats and pews, stand at the mics and the platform benches. A seat nothing covers
## gets a piece of its own.
## Every x, y, w, h is in mock-up pixels (half a world pixel) in the room's frame. Every loop runs over a
## fixed count or steps a positive distance toward a limit.

const Furnish := preload("res://scripts/view/detail_furnish.gd")
const Prims := preload("res://scripts/view/detail_prims.gd")
const Scenes := preload("res://scripts/view/detail_scenes.gd")

const KINDS: Array[String] = ["movie_theatre", "party_hall", "metro", "cathedral"]
const GLASS: Array[String] = ["c8453c", "3a6aa8", "e0a83a", "3f8a52", "8a5ab0"]
const VELVET := Color("a8323c")
const BRASS := Color("c9a85c")


static func handles(kind: String) -> bool:
	return KINDS.has(kind)


## Paints one floor of `kind` into pen p. w is the room's width, y0 the row its floor starts at (all mock-up
## pixels), seats the figure centres, upper the second floor of a two-floor room.
static func draw(p: Object, kind: String, w: int, y0: int, seats: Array, lit: bool, night: bool, id: int, upper: bool, pal: Array) -> void:
	var yt := float(y0)
	var fy := float(y0 + 58)
	var wf := float(w)
	Scenes.shell_room(p, 0, yt, w, id % 2, pal)
	var taken: Array = []  # [x0, x1] of the pieces placed, to see which seats stand at one
	match kind:
		"movie_theatre":
			_cinema(p, wf, yt, fy, seats, lit, upper, taken)
		"party_hall":
			_party(p, wf, yt, fy, seats, lit, taken)
		"metro":
			_metro(p, wf, yt, fy, seats, lit, upper, taken)
		"cathedral":
			_cathedral(p, wf, yt, fy, seats, lit, night, id, taken)
	_cover(p, seats, taken, fy)


static func _note(taken: Array, x0: float, x1: float) -> void:
	taken.append(Vector2(x0, x1))


static func _covered(taken: Array, c: float) -> bool:
	for t: Vector2 in taken:
		if c >= t.x - 8.0 and c <= t.y + 8.0:
			return true
	return false


## Gives every seat no piece stands at a piece of its own.
static func _cover(p: Object, seats: Array, taken: Array, fy: float) -> void:
	for c: float in seats:
		if _covered(taken, c):
			continue
		Furnish.waiting_chair(p, c, fy, Color("5a7fb4"))
		_note(taken, c - 8.0, c + 8.0)


# ---------------------------------------------------------------- movie theatre

static func _cinema(p: Object, w: float, yt: float, fy: float, seats: Array, lit: bool, upper: bool, taken: Array) -> void:
	var sx := w - 76.0  # the screen end of the hall, after the recipe: curtains, screen and a low stage
	var drape := Color("8a1f2c")
	p.item(sx, yt + 6, 60, 48, Color("2a1a22"), 1.0)
	p.gradv(sx + 14, yt + 10, 32, 38, Color("5a2a3c"), Color("2a1a30"))
	if lit:  # the film: a sky, a hill and a sun, light of its own
		p.GR(sx + 14, yt + 10, 32, 24, Color("8ac8f0"))
		p.GR(sx + 14, yt + 34, 32, 14, Color("5aa060"))
		p.GR(sx + 36, yt + 15, 6, 6, Color("fff0a0"))
		p.glow(sx + 30, yt + 30, 70.0, 50.0, Color("a8d8ff"), 0.4)
	else:
		p.R(sx + 14, yt + 10, 32, 38, Color("3a3644"))
		p.R(sx + 16, yt + 12, 6, 30, Color("4a4658"))
	for i: int in 3:  # the curtains, in folds
		p.R(sx + 2 + i * 4, yt + 6, 3, 48, drape if i % 2 == 0 else drape.darkened(0.2))
		p.R(sx + 46 + i * 4, yt + 6, 3, 48, drape if i % 2 == 0 else drape.darkened(0.2))
	p.R(sx, yt + 6, 60, 4, drape.darkened(0.3))
	p.R(sx, yt + 6, 60, 1, BRASS)
	p.item(sx - 4, fy - 6, 68, 6, Color("4a3040"), 1.0)
	p.R(sx - 4, fy - 6, 68, 1, BRASS)
	var lx := 46.0
	while lx < sx - 24.0:  # wall lights down the hall
		Scenes.ceiling_light(p, lx, yt, 20.0, lit, 50.0)
		lx += 72.0
	if upper:
		_booth(p, sx, yt, fy, lit)
		var rx := 72.0
		p.R(rx, yt + 42, sx - 12.0 - rx, 2, BRASS)  # the balcony rail
		var post := rx
		while post < sx - 12.0:
			p.R(post, yt + 42, 2, 16, BRASS.darkened(0.2))
			post += 24.0
	else:
		_popcorn(p, 4.0, yt, fy, lit)
		p.item(46, yt + 8, 18, 6, Color("1a3a28"), 1.0)  # the exit sign
		p.GR(48, yt + 10, 14, 2, Color("5ae08a"))
	for c: float in seats:
		p.shadow(c, fy, 10, 0.5)
		p.item(c - 8, fy - 30, 12, 22, VELVET.darkened(0.1), 2.0)  # the seat back, on the far side from the film
		p.R(c - 7, fy - 29, 10, 2, VELVET.lightened(0.2))
		p.item(c - 8, fy - 12, 18, 6, VELVET, 2.0)
		p.R(c + 8, fy - 18, 2, 12, Color("3a2a30"))
		p.R(c - 6, fy - 6, 2, 6, Color("2a2230"))
		_note(taken, c - 9.0, c + 10.0)


## The projection booth of the upper floor: a lit box on the back wall that throws its beam at the screen.
static func _booth(p: Object, sx: float, yt: float, fy: float, lit: bool) -> void:
	p.item(8, yt + 16, 32, 28, Color("3a3644"), 1.5)
	p.R(10, yt + 18, 28, 2, Color("5a5668"))
	p.item(12, yt + 24, 12, 8, Color("1a1a22"), 1.0)
	if lit:
		p.GR(36, yt + 26, 3, 4, Color("fff6d8"))
		p.ln(Vector2(40, yt + 28), Vector2(sx + 14, yt + 20), Color(1.0, 1.0, 0.9, 0.14), 6.0)
		p.ln(Vector2(40, yt + 28), Vector2(sx + 14, yt + 44), Color(1.0, 1.0, 0.9, 0.1), 6.0)
	else:
		p.R(36, yt + 26, 3, 4, Color("5a5668"))
	p.item(10, fy - 14, 28, 14, Color("4a4658"), 1.5)  # the film cases
	p.R(12, fy - 12, 24, 2, Color("c8453c"))


static func _popcorn(p: Object, x: float, yt: float, fy: float, lit: bool) -> void:
	p.shadow(x + 18, fy, 22, 0.5)
	p.item(x, fy - 24, 36, 24, Color("a8323c"), 1.5)
	p.R(x + 2, fy - 20, 32, 2, Color("f4ecdc"))
	p.item(x + 2, fy - 44, 32, 20, Color("e8dcc0"), 1.5)
	if lit:
		p.GW(x + 4, yt + 18, 28, 14, Color("ffd070"))
	p.R(x + 6, fy - 42, 4, 12, Color("c8453c"))
	p.R(x + 14, fy - 42, 4, 12, Color("f4ecdc"))
	p.R(x + 22, fy - 42, 4, 12, Color("c8453c"))
	Furnish.awning(p, x - 2, fy - 50, 40.0)


# ---------------------------------------------------------------- party hall

static func _party(p: Object, w: float, yt: float, fy: float, seats: Array, lit: bool, taken: Array) -> void:
	var gaudy: Array[Color] = [Color("c8453c"), Color("e8b458"), Color("3f8a52")]
	p.R(4, yt + 6, w - 8.0, 1, Color("2a2230"))  # bunting along the top
	var bx := 8.0
	var k := 0
	while bx + 8.0 <= w - 8.0:
		var c := gaudy[k % 3]
		p.R(bx, yt + 7, 8, 3, c)
		p.R(bx + 1, yt + 10, 6, 2, c)
		p.R(bx + 2, yt + 12, 4, 1, c)
		bx += 24.0
		k += 1
	# the stage: a platform, a magenta curtain, speakers
	var st := w - 104.0
	p.gradv(st + 4, yt + 14, 88, 34, Color("d05a9a"), Color("902a6a"))
	for i: int in 11:
		p.R(st + 4 + i * 8, yt + 14, 1, 34, Color("702050"))
	p.R(st + 4, yt + 14, 88, 3, BRASS)
	p.item(st, yt + 48, 92, 10, Color("5a3a4a"), 1.5)
	p.R(st, yt + 48, 92, 2, Color("8a5a6a"))
	for sp: float in [st - 12.0, st + 90.0]:
		p.item(sp, yt + 28, 14, 30, Color("2a2230"), 1.5)
		p.ell(sp + 7, yt + 38, 4, 4, Color("4a4658"))
		p.ell(sp + 7, yt + 50, 5, 5, Color("4a4658"))
		p.R(sp + 6, yt + 49, 2, 2, Color("8a8aa0"))
	if lit:
		p.GR(st + 8, yt + 20, 4, 2, Color("fff0c0"))
		p.GR(st + 80, yt + 20, 4, 2, Color("fff0c0"))
		p.glow(st + 46, yt + 34, 70.0, 40.0, Color("ff90d0"), 0.35)
	var mid := w * 0.5
	p.R(mid, yt + 10, 1, 8, Color("2a2230"))  # the disco ball, on its cord, over a lit dance floor
	p.ell(mid, yt + 24, 7, 7, Color("c8ccd8"))
	for i: int in 6:
		p.R(mid - 5.0 + Prims.hn(i, 31) * 9.0, yt + 19 + i, 2, 2, Color("ffffff"))
	if lit:
		p.GR(mid - 3, yt + 20, 2, 2, Color("fff0a0"))
		p.glow(mid, yt + 44, 60.0, 34.0, Color("c090ff"), 0.4)
	var tiles: Array[Color] = [Color("e04a8a"), Color("4a8ae0"), Color("e0c040"), Color("4ae08a")]
	for i: int in 5:
		var tc := tiles[i % tiles.size()]
		p.R(mid - 22 + i * 8, fy - 4, 8, 4, tc if lit else tc.darkened(0.4))
	_note(taken, mid - 22.0, mid + 18.0)
	var table_seats: Array = []
	for c: float in seats:
		if c >= st - 4.0 and c <= st + 100.0:  # the performers: a mic stand each
			p.R(c - 1, yt + 28, 2, 20, Color("2a2230"))
			p.item(c - 2, yt + 25, 5, 4, Color("8a8aa0"), 1.0, false)
			_note(taken, c - 6.0, c + 6.0)
		elif absf(c - mid) > 8.0:
			table_seats.append(c)
	var i := 0
	while i < table_seats.size():
		var c: float = table_seats[i]
		var mate := -1.0
		if i + 1 < table_seats.size() and float(table_seats[i + 1]) - c <= 44.0:
			mate = table_seats[i + 1]
		if mate >= 0.0:
			var m := (c + mate) * 0.5
			p.shadow(m, fy, 14, 0.5)
			p.R(m - 1, fy - 20, 2, 18, Color("3a2a22"))
			p.R(m - 6, fy - 2, 12, 2, Color("3a2a22"))
			p.item(m - 11, fy - 24, 22, 4, Color("f4e8f0"), 1.5)
			p.item(m - 4, fy - 30, 3, 6, Color("a8d4e0"), 1.0, false)
			p.item(m + 2, fy - 29, 3, 5, Color("e87aa8"), 1.0, false)
			var balloons: Array[Color] = [Color("c8453c"), Color("e8b458"), Color("5a7fb4")]
			for j: int in 3:  # a bunch of balloons tied to the table
				p.R(m + 8, fy - 54 + j * 6, 1, 6, Color("2a2230"))
				p.ell(m + 5 + j * 5, fy - 60 + (j % 2) * 5, 4, 5, balloons[j])
			Furnish.stool(p, c, fy, Color("e04a8a"))
			Furnish.stool(p, mate, fy, Color("e04a8a"))
			_note(taken, c - 8.0, mate + 8.0)
			i += 2
		else:
			Furnish.stool(p, c, fy, Color("e04a8a"))
			_note(taken, c - 8.0, c + 8.0)
			i += 1
	Scenes.plant(p, 14.0, fy, 24.0, Color("a8683c"))


# ---------------------------------------------------------------- metro

static func _metro(p: Object, w: float, yt: float, fy: float, seats: Array, lit: bool, upper: bool, taken: Array) -> void:
	for i: int in int(w / 8.0):  # white tiling up the wall
		if i % 2 == 0:
			p.R(i * 8, yt + 4, 1, 34, Color("c0c8cc"))
	var mid := w * 0.5
	p.item(mid - 32, yt + 4, 64, 12, Color("1a1e28"), 1.5)  # the destination board
	if lit:
		p.GR(mid - 30, yt + 6, 60, 8, Color("2a4a30"))
		for i: int in 5:
			p.GR(mid - 26 + i * 10, yt + 8, 6, 2, Color("5ae08a"))
			p.GR(mid - 26 + i * 10, yt + 11, 4, 1, Color("e8b458"))
		p.glow(mid, yt + 18, 50.0, 20.0, Color("a8ffc0"), 0.35)
	else:
		p.R(mid - 30, yt + 6, 60, 8, Color("2a3a30"))
	p.ell(24, yt + 10, 8, 8, Color("3a6aa8"))  # the station's roundel
	p.R(20, yt + 7, 2, 6, Color("f4f0e6"))
	p.R(22, yt + 7, 2, 2, Color("f4f0e6"))
	p.R(24, yt + 9, 2, 2, Color("f4f0e6"))
	p.R(26, yt + 7, 2, 6, Color("f4f0e6"))
	if not upper:
		p.item(10, yt + 18, w - 20.0, 36, Color("dfe4ea"), 2.0)  # the train at the platform
		p.R(12, yt + 40, w - 24.0, 4, Color("3a6aa8"))
		p.R(12, yt + 44, w - 24.0, 1, Color("e8c040"))
		var wx := 24.0
		while wx + 20.0 <= w - 24.0:
			p.item(wx, yt + 24, 20, 14, Color("2a3a54"), 1.5)
			if lit:
				p.GR(wx + 2, yt + 26, 16, 10, Color("ffe8b0"))
			else:
				p.R(wx + 2, yt + 26, 16, 10, Color("4a5a78"))
			wx += 40.0
		var dx := 44.0
		while dx + 8.0 <= w - 24.0:  # the doors, between the windows
			p.R(dx, yt + 22, 1, 30, Color("8a94a4"))
			dx += 40.0
		var gx := 28.0
		while gx + 10.0 <= w - 24.0:  # the bogies under the car
			p.R(gx, yt + 52, 10, 4, Color("2a2230"))
			gx += 48.0
	for i: int in int(w / 12.0):  # the yellow safety line along the platform edge
		p.R(i * 12, yt + 57, 8, 1, Color("e8c040"))
	for c: float in seats:
		if upper:  # a standing ledge on legs
			p.item(c - 14, fy - 24, 28, 3, Color("6a7a8a"), 1.0)
			p.R(c - 13, fy - 21, 2, 21, Color("3a4252"))
			p.R(c + 11, fy - 21, 2, 21, Color("3a4252"))
			_note(taken, c - 15.0, c + 15.0)
		else:
			p.shadow(c, fy, 18, 0.5)
			p.item(c - 16, fy - 14, 32, 4, Color("8a94a4"), 1.5)
			p.item(c - 16, fy - 26, 32, 4, Color("6a7a8a"), 1.0)
			p.R(c - 14, fy - 10, 2, 10, Color("3a4252"))
			p.R(c + 12, fy - 10, 2, 10, Color("3a4252"))
			_note(taken, c - 17.0, c + 17.0)
	if upper:
		var px := 0.0
		while px < w - 8.0:  # pillars
			p.item(px, yt + 4, 8, 54, Color("b8c0c8"), 1.0)
			px += 128.0
		var ax := 60.0
		while ax + 40.0 < w - 20.0:  # lit advertising panels
			p.item(ax, yt + 16, 40, 24, Color("1a1e28"), 1.5)
			if lit:
				p.GR(ax + 2, yt + 18, 36, 20, Color("d05a9a"))
			else:
				p.R(ax + 2, yt + 18, 36, 20, Color("7a3a5a"))
			p.R(ax + 6, yt + 24, 28, 2, Color("f4f0e6"))
			ax += 192.0


# ---------------------------------------------------------------- cathedral

static func _cathedral(p: Object, w: float, yt: float, fy: float, seats: Array, lit: bool, night: bool, id: int, taken: Array) -> void:
	var mid := w * 0.5
	var wx := 24.0
	var k := 0
	while wx + 20.0 <= w - 96.0:  # tall lancet windows down the nave
		if absf(wx + 10.0 - mid) > 28.0:
			_lancet(p, wx, yt, lit, night, id + k)
		wx += 48.0
		k += 1
	_rose(p, mid, yt, lit, night, id)
	p.R(0, fy - 2, w, 2, Color("8a2430"))  # a red runner down the nave
	p.R(0, fy - 2, w, 1, BRASS)
	for c: float in seats:
		if c > w - 90.0:  # the priest, at the altar
			continue
		p.shadow(c, fy, 12, 0.45)
		p.item(c - 12, fy - 44, 4, 44, Color("6a4428"), 1.5)  # the pew back
		p.item(c - 12, fy - 14, 22, 4, Color("7a5230"), 1.5)
		p.R(c - 12, fy - 14, 22, 1, Color("a07848"))
		p.R(c + 6, fy - 10, 2, 10, Color("4a3020"))
		_note(taken, c - 13.0, c + 11.0)
	var ax := w - 60.0  # the altar, a gold cross over it, candles either side
	p.shadow(ax + 18, fy, 22, 0.55)
	p.item(ax, fy - 20, 36, 20, Color("a8a090"), 1.5)
	p.item(ax - 2, fy - 24, 40, 5, Color("f4f0e6"), 1.0)
	p.R(ax + 4, fy - 14, 28, 2, BRASS)
	p.item(ax + 16, yt + 12, 4, 32, BRASS, 1.0)
	p.item(ax + 8, yt + 20, 20, 4, BRASS, 1.0)
	for cx: float in [ax - 4.0, ax + 38.0]:
		p.item(cx, fy - 40, 2, 16, Color("f4ecdc"), 0.5, false)
		p.R(cx - 1, fy - 26, 4, 2, BRASS)
		if lit:
			p.GR(cx, fy - 43, 2, 3, Color("ffd070"))
			p.glow(cx + 1, fy - 40, 24.0, 20.0, Color("ffd070"), 0.5)
	_note(taken, ax, ax + 36.0)
	var pend := 56.0
	while pend < w - 110.0:
		Furnish.pendant(p, pend, yt, lit, 80.0, BRASS.darkened(0.3))
		pend += 120.0


## A tall pointed window of stained glass: coloured panes in lead, a lit glow at night when the hall is lit.
static func _lancet(p: Object, x: float, yt: float, lit: bool, night: bool, seed_v: int) -> void:
	p.item(x - 2, yt + 6, 24, 38, Color("8a7a68"), 1.5)
	p.ell(x + 10, yt + 8, 11, 7, Color("8a7a68"))
	p.ell(x + 10, yt + 9, 9, 6, Color(GLASS[seed_v % GLASS.size()]))
	for j: int in 5:
		for i: int in 2:
			var c := Color(GLASS[int(Prims.hn(seed_v + j, i + 3) * GLASS.size()) % GLASS.size()])
			p.R(x + float(i * 10), yt + 12 + j * 6, 9, 5, c)
	p.R(x + 9, yt + 4, 1, 38, Color("3a3028"))
	if lit and night:
		p.glow(x + 10, yt + 26, 22.0, 24.0, Color("e0a8ff"), 0.35)


## The round rose window over the nave: glass petals around a hub, in a stone ring.
static func _rose(p: Object, cx: float, yt: float, lit: bool, night: bool, seed_v: int) -> void:
	p.ell(cx, yt + 20, 17, 15, Color("8a7a68"))
	p.ell(cx, yt + 20, 14, 12, Color("3a3028"))
	for i: int in 8:
		var a := float(i) * TAU / 8.0
		var c := Color(GLASS[(i + seed_v) % GLASS.size()])
		p.ell(cx + cos(a) * 8.0, yt + 20 + sin(a) * 7.0, 4, 3.5, c)
	p.ell(cx, yt + 20, 4, 4, BRASS)
	if lit and night:
		p.glow(cx, yt + 22, 36.0, 30.0, Color("ffc8a0"), 0.35)
