extends RefCounted
## Detailed drawing (#328) of the swimming pool, two floors tall: the lower floor is the pool hall (a tiled
## basin of lit water with lane ropes, a springboard, a lifeguard's tall chair under an umbrella, loungers on the
## deck) and the upper floor the atrium over it (a glass roof, bunting, the high-dive tower, a viewing gallery with
## a rail and benches). Composed in the G Lit look from detail_prims.gd and detail_scenes.gd, in mock-up pixels
## (half a world pixel): x from the room's left wall, y from the top of the floor, feet at y + 58.
## The water is lit from below at night (a glow for the additive layer). The living parts (swimmers, the
## lifeguard, the cannonball and its splash, the closed sign) are not here: room_look.gd draws them as marks over
## this, for Classic and Detailed alike, because they change with the clock. Every loop runs over a fixed count.

const Prims := preload("res://scripts/view/detail_prims.gd")
const Scenes := preload("res://scripts/view/detail_scenes.gd")

const KINDS: Array[String] = ["pool"]
const DECK_L := 44.0  ## Where the basin starts (the springboard's stand is on the deck before it).
const DECK_R := 96.0  ## Width of the deck after the basin (the lifeguard's chair and loungers).
const WATER_TOP := Color("66d8ee")
const WATER_DEEP := Color("2a74b4")
const TILE := Color("e6f2f4")
const STEEL := Color("9aa6b0")
const CORD := Color("2a2230")


static func handles(kind: String) -> bool:
	return KINDS.has(kind)


## Paints one floor of the pool into pen p. w is the room's width, y0 the row its floor starts at (mock-up
## pixels), seats the figure centres, upper the second floor.
static func draw(p: Object, w: int, y0: int, seats: Array, lit: bool, night: bool, id: int, upper: bool, pal: Array) -> void:
	var yt := float(y0)
	var fy := float(y0 + 58)
	var wf := float(w)
	Scenes.shell_room(p, 0, yt, w, id % 2, pal)
	if upper:
		_atrium(p, wf, yt, fy, seats, lit, night)
	else:
		_hall(p, wf, yt, fy, seats, lit, night, id)


# ---------------------------------------------------------------- the pool hall (lower floor)

static func _hall(p: Object, w: float, yt: float, fy: float, seats: Array, lit: bool, night: bool, id: int) -> void:
	var x1 := w - DECK_R
	_basin(p, DECK_L, x1, yt, lit, night, id)
	_springboard(p, yt, fy)
	_lifeguard_chair(p, w - 52.0, yt, fy)
	for c: float in seats:  # a lounger at each spot on the deck
		if c < DECK_L - 4.0 or c > x1 + 8.0:
			_lounger(p, c, fy, id)
	var ring := Color("e8453c")  # a lifebuoy on the wall
	p.ell(w - 20.0, yt + 22.0, 8, 8, TILE)
	p.ell(w - 20.0, yt + 22.0, 8, 8, ring)
	p.ell(w - 20.0, yt + 22.0, 4, 4, Color("e6f2f4"))
	for i: int in 4:
		p.R(w - 29.0 + i * 5, yt + 17 + (i % 2) * 10, 3, 2, TILE)
	Scenes.plant(p, 8.0, fy, 18.0, Color("a8683c"))


## The tiled basin: sides and floor, graded water with ripples, lane ropes and, when lit, light from below.
static func _basin(p: Object, x0: float, x1: float, yt: float, lit: bool, night: bool, id: int) -> void:
	var span := x1 - x0
	p.R(x0 - 4, yt + 30, span + 8, 3, TILE)  # the coping along the edge
	p.R(x0 - 4, yt + 33, 4, 25, TILE.darkened(0.12))
	p.R(x1, yt + 33, 4, 25, TILE.darkened(0.12))
	p.gradv(x0, yt + 33, span, 25, WATER_TOP, WATER_DEEP)
	p.R(x0, yt + 33, span, 4, WATER_TOP.lightened(0.18))  # a lighter surface band
	p.R(x0, yt + 48, span, 10, WATER_DEEP.darkened(0.3))  # darker water lower down
	if lit:
		p.GR(x0, yt + 33, span, 2, Color("b8f4ff"))  # the surface catches the light
	for k: int in 6:  # tile joints on the far wall under the surface
		p.R(x0, yt + 40 + k * 3, span, 1, WATER_DEEP.lightened(0.12 + 0.02 * k))
	for i: int in int(span / 14.0):  # ripples
		var rx := x0 + 4.0 + i * 14.0 + Prims.hn(i, id) * 6.0
		p.R(rx, yt + 36 + (i % 3) * 5, 6, 1, Color("d8fbff"))
	for j: int in 3:  # a couple of bright ripple highlights
		var hx := x0 + span * (0.2 + 0.3 * j) + Prims.hn(j, id + 7) * 8.0
		p.R(hx, yt + 35 + j, 10, 1, Color("f0feff"))
		p.R(hx + 3, yt + 37 + j, 5, 1, Color("b8f4ff"))
	for lane: int in 2:  # lane ropes: red and white floats
		var ly := yt + 41.0 + lane * 8.0
		p.R(x0, ly, span, 1, CORD)
		for f: int in int(span / 8.0):
			p.R(x0 + f * 8, ly - 1, 4, 3, Color("e8453c") if f % 2 == 0 else TILE)
	for m: int in int(span / 48.0) + 1:  # black lane markers on the bed
		p.R(x0 + 12.0 + m * 48.0, yt + 54, 20, 2, WATER_DEEP.darkened(0.45))
	p.R(x0 + 6, yt + 33, 2, 25, STEEL)  # the ladder's rails on the near side
	p.R(x0 + 12, yt + 33, 2, 25, STEEL)
	for r: int in 4:
		p.R(x0 + 6, yt + 38 + r * 5, 8, 1, STEEL.lightened(0.2))
	if lit:
		p.glow(x0 + span * 0.5, yt + 46, span * 0.5, 22.0, Color("70e8ff"), 0.5)
		p.glow(x0 + span * 0.5, yt + 54, span * 0.4, 8.0, Color("40d0ff"), 0.3)  # the bed glows from below
	elif night:
		p.glow(x0 + span * 0.5, yt + 46, span * 0.3, 14.0, Color("70e8ff"), 0.2)


## The low springboard: a post on the left deck and a plank out over the water.
static func _springboard(p: Object, yt: float, fy: float) -> void:
	p.shadow(36.0, fy, 10, 0.4)
	p.item(32, yt + 28, 8, 30, STEEL, 1.0)
	p.R(34, yt + 30, 4, 26, STEEL.darkened(0.2))
	p.item(34, yt + 26, 76, 3, Color("e8d8b8"), 1.0)  # the plank
	p.R(34, yt + 26, 76, 1, Color("fff4d8"))
	for g: int in 8:  # grip strips on the plank
		p.R(38 + g * 9, yt + 27, 5, 1, Color("c0a878"))


## A lifeguard's tall chair under a striped umbrella; the guard herself is a mark (room_look.gd).
static func _lifeguard_chair(p: Object, cx: float, yt: float, fy: float) -> void:
	p.shadow(cx, fy, 16, 0.5)
	p.R(cx - 11, yt + 36, 3, 22, STEEL)
	p.R(cx + 9, yt + 36, 3, 22, STEEL)
	p.R(cx - 9, yt + 46, 20, 2, STEEL.darkened(0.15))  # cross brace
	p.item(cx - 14, yt + 33, 28, 4, Color("e8453c"), 1.5)  # seat
	p.R(cx - 14, yt + 20, 3, 13, Color("e8453c"))  # back
	p.R(cx + 1, yt + 6, 2, 28, Color("8a8a90"))  # umbrella pole
	for s: int in 6:
		p.R(cx - 18 + s * 6, yt + 6, 6, 3, Color("e8453c") if s % 2 == 0 else TILE)
	p.R(cx - 14, yt + 9, 28, 1, Color("c8c8d0"))
	for rung: int in 5:  # the ladder up to the seat
		p.R(cx - 10, yt + 40 + rung * 4, 6, 1, STEEL.lightened(0.25))


static func _lounger(p: Object, c: float, fy: float, id: int) -> void:
	var towels: Array[Color] = [Color("e8453c"), Color("3a8ad8"), Color("e8b83c")]
	var towel := towels[(int(c) / 7 + id) % 3]
	p.shadow(c, fy, 15, 0.4)
	p.item(c - 14, fy - 8, 28, 5, TILE, 1.5)
	p.R(c - 14, fy - 7, 28, 2, towel)  # a towel along it
	p.item(c - 14, fy - 14, 6, 7, TILE.darkened(0.08), 1.0)  # the raised back
	p.R(c - 13, fy - 3, 2, 3, STEEL)
	p.R(c + 11, fy - 3, 2, 3, STEEL)


# ---------------------------------------------------------------- the atrium (upper floor)

static func _atrium(p: Object, w: float, yt: float, fy: float, seats: Array, lit: bool, night: bool) -> void:
	p.R(0, yt + 3, w, 1, CORD)  # a string of bunting
	var colours: Array[Color] = [Color("e8453c"), Color("e8b83c"), Color("3a8ad8"), Color("3f8a52")]
	for i: int in int(w / 16.0):
		var c := colours[i % 4]
		p.R(i * 16 + 4, yt + 4, 8, 3, c)
		p.R(i * 16 + 5, yt + 7, 6, 2, c)
		p.R(i * 16 + 7, yt + 9, 2, 1, c)
	var roof := Color("9ad8f0") if not night else Color("1a2a5a")  # skylights along the ceiling
	for k: int in 4:
		var gx := 36.0 + k * ((w - 72.0) / 4.0)
		p.GR(gx, yt + 12, (w - 72.0) / 4.0 - 8.0, 12, roof)
		p.R(gx - 3, yt + 12, 3, 12, STEEL)
		if lit and night:
			p.glow(gx + 20.0, yt + 30, 40.0, 16.0, Color("70e8ff"), 0.3)
	p.R(36, yt + 24, w - 72.0, 2, STEEL.darkened(0.1))
	_high_dive(p, yt, fy)
	_gallery(p, w, yt, fy, seats, lit)


## The high-dive tower: a mast, a platform with a rail and a ladder, and the board stretching out over the pool.
static func _high_dive(p: Object, yt: float, fy: float) -> void:
	p.shadow(52.0, fy, 14, 0.4)
	p.item(46, yt + 14, 10, 44, STEEL, 1.0)
	for r: int in 9:  # ladder rungs
		p.R(46, yt + 18 + r * 4, 10, 1, STEEL.lightened(0.25))
	p.item(30, yt + 12, 54, 3, Color("e8d8b8"), 1.0)  # the platform and the board
	p.R(30, yt + 12, 54, 1, Color("fff4d8"))
	p.R(30, yt + 4, 1, 8, STEEL)  # the rail's posts and bar
	p.R(30, yt + 4, 20, 1, STEEL)
	p.R(40, yt + 4, 1, 8, STEEL)
	p.R(50, yt + 4, 1, 8, STEEL)
	p.item(60, yt + 16, 10, 8, Color("e8453c"), 1.0)  # a depth sign on the post: "5 m"
	p.R(62, yt + 18, 6, 1, TILE)
	p.R(62, yt + 20, 4, 1, TILE)


## The viewing gallery: a rail along the front with balusters and benches at the spots.
static func _gallery(p: Object, w: float, yt: float, fy: float, seats: Array, lit: bool) -> void:
	var x0 := w - 190.0
	p.R(x0, yt + 38, 188, 3, STEEL.lightened(0.1))  # the rail
	for i: int in 24:
		p.R(x0 + 2 + i * 8, yt + 41, 1, 17, STEEL)
	p.R(x0 - 2, yt + 36, 3, 22, STEEL.darkened(0.15))
	for c: float in seats:
		p.shadow(c, fy, 15, 0.4)
		p.item(c - 14, fy - 10, 28, 4, Color("8a5a38"), 1.5)  # a bench
		p.R(c - 12, fy - 6, 2, 6, Color("5a3a22"))
		p.R(c + 10, fy - 6, 2, 6, Color("5a3a22"))
	var lx := x0 + 20.0  # lamps on the rail
	for k: int in 3:
		p.R(lx + k * 70, yt + 30, 2, 8, STEEL)
		if lit:
			p.GR(lx - 2 + k * 70, yt + 27, 6, 3, Color("fff0c0"))
			p.glow(lx + 1 + k * 70, yt + 30, 22.0, 14.0, Color("ffc880"), 0.35)
			p.glow(lx + 1 + k * 70, yt + 44, 30.0, 18.0, Color("ffb060"), 0.25)  # warm pool on the gallery floor
		else:
			p.R(lx - 2 + k * 70, yt + 27, 6, 3, Color("6a6a74"))
	Scenes.plant(p, w - 12.0, fy, 18.0, Color("a8683c"))
