extends RefCounted
## Detailed drawing (#303) of the batch 2 rooms with people in them: food (fast food, restaurant), shops, and
## services (security, medical, recycling), plus parking. Composed from detail_furnish.gd in the G Lit look,
## after the mock-up's restaurant. Like batch 1 (detail_rooms.gd) the furniture is placed from the recipe's
## activity spots, which arrive here as `seats` (the centre of each figure in mock-up pixels, sorted), so
## diners sit at tables, shoppers stand at racks and patients lie in beds. Each kind has its variants (#275),
## following the recipe's variant numbers; RoomRecipes.SUITE (-1) is a joined suite. A seat nothing else
## covers gets a piece of its own, so nobody stands in empty air.
## Every x, y, w, h is in mock-up pixels (half a world pixel) in the room's frame. Every loop runs over a
## fixed count or steps a positive distance toward a limit.

const Furnish := preload("res://scripts/view/detail_furnish.gd")
const Scenes := preload("res://scripts/view/detail_scenes.gd")

const KINDS: Array[String] = ["fast_food", "restaurant", "retail", "security", "medical", "recycling", "parking_ramp", "parking_space"]
const PAIR_MIN := 37.0  ## Seats this far apart (mock-up pixels) sit at one table or bed.
const PAIR_MAX := 47.0
const NARROW := 76.0  ## A piece no wider than this counts as standing at the seats beside it.
const REACH := 16.0
const SUITE := -1  ## RoomRecipes.SUITE.
const CARS: Array[String] = ["c8453c", "5a7fb4", "e8b458", "3f8a52", "8a94a4", "8a6ab0"]
const BINS: Array[String] = ["3a6aa8", "3f8a52", "d0a030", "a8453c"]


static func handles(kind: String) -> bool:
	return KINDS.has(kind)


## Paints one floor of `kind` into pen p. w is the room's width, y0 the row its floor starts at (all mock-up
## pixels), seats the figure centres, variant the recipe's variant (SUITE for a joined suite).
static func draw(p: Object, kind: String, w: int, y0: int, seats: Array, lit: bool, night: bool, id: int, variant: int, upper: bool, pal: Array) -> void:
	var yt := float(y0)
	var fy := float(y0 + 58)
	var wf := float(w)
	Scenes.shell_room(p, 0, yt, w, id % 2, pal)
	var taken: Array = []  # [x0, x1] of the narrow pieces placed, to see which seats stand at one
	match kind:
		"fast_food":
			_fast_food(p, wf, yt, fy, seats, lit, night, id, variant, taken)
		"restaurant":
			_restaurant(p, wf, yt, fy, seats, lit, night, id, variant, taken)
		"retail":
			_retail(p, wf, yt, fy, seats, lit, night, id, variant, taken)
		"security":
			_security(p, wf, yt, fy, lit, id, taken)
		"medical":
			_medical(p, wf, yt, fy, seats, lit, taken)
		"recycling":
			_recycling(p, wf, yt, fy, seats, lit, id, upper, taken)
		"parking_ramp":
			_ramp(p, wf, yt, fy, lit)
		"parking_space":
			_space(p, wf, yt, fy, lit, id)
	_cover(p, seats, taken, fy, kind)


## Seats grouped left to right: [[c0, c1], ...] for neighbours a table apart, and the lone ones [c].
static func groups(seats: Array) -> Array:
	var out: Array = []
	var i := 0
	while i < seats.size():
		var c: float = seats[i]
		var gap := 0.0
		if i + 1 < seats.size():
			gap = float(seats[i + 1]) - c
		if gap >= PAIR_MIN and gap <= PAIR_MAX:
			out.append([c, float(seats[i + 1])])
			i += 2
		else:
			out.append([c])
			i += 1
	return out


## Notes that a piece spans x0..x1 (so seats beside it are covered), when it is narrow enough to be a piece.
static func _note(taken: Array, x0: float, x1: float) -> void:
	if x1 - x0 <= NARROW:
		taken.append(Vector2(x0, x1))


static func _covered(taken: Array, c: float) -> bool:
	for t: Vector2 in taken:
		if c >= t.x - REACH and c <= t.y + REACH:
			return true
	return false


## Gives every seat no piece stands at a piece of its own.
static func _cover(p: Object, seats: Array, taken: Array, fy: float, kind: String) -> void:
	for c: float in seats:
		if _covered(taken, c):
			continue
		match kind:
			"fast_food", "restaurant":
				Furnish.stool(p, c, fy)
			"retail":
				Furnish.display_table(p, c, fy, 32.0, int(c))
			"medical":
				Furnish.waiting_chair(p, c, fy, Color("5a9aa8"))
			_:
				Furnish.queue_post(p, c, fy, Color("5a7fb4"))
		taken.append(Vector2(c - 16.0, c + 16.0))


## Windows every `step` from x while one of `wide` fits before the limit, each with a striped awning when asked.
static func _windows(p: Object, x: float, limit: float, step: float, yt: float, wide: float, night: bool, id: int, awn: bool, frame: Color) -> void:
	var wx := x
	var k := 0
	while wx + wide <= limit:
		Scenes.window(p, wx, yt + 12, wide, 24, frame, Color(0, 0, 0, 0), id + k * 3 + 11, night)
		if awn:
			Furnish.awning(p, wx - 5, yt + 5, wide + 10)
		wx += step
		k += 1


static func _lights(p: Object, w: float, yt: float, lit: bool, step: float) -> void:
	var lx := step * 0.5
	while lx < w - 24.0:
		Scenes.ceiling_light(p, lx, yt, 36.0, lit, 64.0)
		lx += step


# ---------------------------------------------------------------- food

static func _fast_food(p: Object, w: float, yt: float, fy: float, seats: Array, lit: bool, night: bool, id: int, variant: int, taken: Array) -> void:
	var red := Color("c8453c")
	_lights(p, w, yt, lit, 96.0)
	match variant:
		2:  # a kiosk: a window along the wall over a ledge with stools, a serving kiosk at the right
			var ledge := Color("c89a62")
			p.item(8, yt + 8, w - 16, 28, Color("2a3a54"), 1.5)
			p.gradv(10, yt + 10, w - 20, 24, Scenes.sky_col(night, yt + 30.0), Scenes.sky_col(night, yt + 60.0), true)
			Scenes.skyline(p, 10, yt + 10, w - 20, 24, night, id)
			p.item(6, fy - 22, w - 12, 4, ledge, 1.0)
			p.R(8, fy - 18, 2, 18, ledge.darkened(0.3))
			p.R(w - 10, fy - 18, 2, 18, ledge.darkened(0.3))
			Furnish.food_counter(p, w - 52.0, yt, fy, 44.0, lit, red)
			for c: float in seats:
				Furnish.stool(p, c, fy, red)
				_note(taken, c - 8.0, c + 8.0)
		3:  # a hatch: a shuttered opening with an awning and a counter, a queue in front
			p.item(12, yt + 14, 52, 28, Color("2a2f3c"), 1.5)
			if lit:
				p.GR(14, yt + 16, 48, 22, Color("f4d890"))
			else:
				p.R(14, yt + 16, 48, 22, Color("6a6458"))
			for i: int in 6:
				p.R(14, yt + 16 + i * 4, 48, 1, Color("d8b868") if lit else Color("5a5448"))
			Furnish.awning(p, 8, yt + 6, 60, red, Color("f4ecdc"))
			p.item(6, fy - 24, 64, 24, Color("e4dccb"), 2.0)
			p.R(8, fy - 8, 60, 3, red)
			p.item(4, fy - 28, 68, 5, Color("5a5a66"), 1.5)
			Furnish.menu_board(p, w - 60.0, yt + 12, 48.0, 24.0, lit)
			for c: float in seats:
				Furnish.queue_post(p, c, fy)
				_note(taken, c - 10.0, c + 10.0)
		_:
			var booths := variant == 1 or variant == SUITE
			if variant == SUITE:
				Furnish.food_counter(p, 8.0, yt, fy, 48.0, lit, red)
				Furnish.food_counter(p, w - 56.0, yt, fy, 48.0, lit, red)
			else:
				Furnish.food_counter(p, w - 72.0, yt, fy, 60.0, lit, red)
				_windows(p, 30.0, w - 112.0, 96.0, yt, 34.0, night, id, true, Color("f0e8d4"))
			for g: Array in groups(seats):
				if g.size() == 2:
					var c0: float = g[0]
					var c1: float = g[1]
					var mid := (c0 + c1) * 0.5
					if booths:
						Furnish.booth(p, mid, fy, red, Color("e8dcc4"))
					else:
						Furnish.small_table(p, c0, c1, fy, Color("f4ecdc"), Color("d8683c"))
						Furnish.pendant(p, mid, yt, lit, 60.0, red)
					_note(taken, c0 - 14.0, c1 + 14.0)
				else:
					var c: float = g[0]
					Furnish.queue_post(p, c, fy)
					_note(taken, c - 10.0, c + 10.0)
	p.R(0, fy + 2, w, 2, Color("8a3a30"))


static func _restaurant(p: Object, w: float, yt: float, fy: float, seats: Array, lit: bool, night: bool, id: int, variant: int, taken: Array) -> void:
	var cloth := Color("f6ecd6")
	for i: int in int(w / 8.0):  # a dado of dark boards along the foot of the wall
		if i % 2 == 0:
			p.R(i * 8, yt + 58, 8, 2, Color("5a3a24"))
	match variant:
		1:  # a diner: a long counter with stools
			Furnish.bar(p, 16.0, yt, fy, w - 32.0, lit)
			for c: float in seats:
				Furnish.stool(p, c, fy)
				_note(taken, c - 8.0, c + 8.0)
		3:  # a bar: a long bar in the middle, stools along it
			var bw := minf(w - 40.0, 180.0)
			Furnish.bar(p, (w - bw) * 0.5, yt, fy, bw, lit)
			for c: float in seats:
				Furnish.stool(p, c, fy)
				_note(taken, c - 8.0, c + 8.0)
			Furnish.pendant(p, w * 0.5 - 60.0, yt, lit, 90.0)
			Furnish.pendant(p, w * 0.5 + 60.0, yt, lit, 90.0)
		_:
			var cafe := variant == 2
			if cafe:
				_windows(p, 24.0, w - 24.0, 100.0, yt, 36.0, night, id, true, cloth)
				Furnish.chalkboard(p, w * 0.5, yt + 8.0, 40.0, 28.0)
			else:
				_windows(p, 20.0, w - 128.0, 120.0, yt, 48.0, night, id, true, cloth)
				Furnish.chalkboard(p, 114.0, yt + 8.0, 28.0, 22.0)  # the menu, between the windows
				Furnish.bar(p, w - 100.0, yt, fy, 88.0, lit)
				Scenes.plant(p, w - 8.0, fy, 22.0, Color("7a5a8a"))
			for g: Array in groups(seats):
				if g.size() == 2:
					var c0: float = g[0]
					var c1: float = g[1]
					var mid := (c0 + c1) * 0.5
					if cafe:
						Furnish.small_table(p, c0, c1, fy, Color("e8c8a0"), Color("5a8a6a"))
					else:
						Furnish.dining_table(p, mid, fy, lit, cloth)
						Furnish.pendant(p, mid, yt, lit, 105.0)
					_note(taken, c0 - 14.0, c1 + 14.0)
				else:
					var c: float = g[0]
					Furnish.stool(p, c, fy)
					_note(taken, c - 8.0, c + 8.0)
			Scenes.plant(p, 12.0, fy, 24.0, Color("a8683c"))


# ---------------------------------------------------------------- shops

static func _retail(p: Object, w: float, yt: float, fy: float, seats: Array, lit: bool, night: bool, id: int, variant: int, taken: Array) -> void:
	var lx := 40.0
	while lx < w - 20.0:
		Scenes.ceiling_light(p, lx, yt, 30.0, lit, 60.0)
		lx += 80.0
	match variant:
		1:  # clothes: a shop window at the right, a rail at every seat
			Furnish.shop_window(p, w - 28.0, yt + 14.0, 20.0, 40.0, night, id)
			for c: float in seats:
				Furnish.clothes_rack(p, c, fy, 36.0, id + int(c))
				_note(taken, c - 18.0, c + 18.0)
		2:  # electronics: a wall of screens, display counters, a till
			Furnish.tv_wall(p, 8.0, yt + 8.0, w - 60.0, 18.0, lit, id)
			Furnish.tv_wall(p, 8.0, yt + 28.0, w - 60.0, 18.0, lit, id + 3)
			Furnish.till(p, w - 48.0, fy, 40.0, lit)
			for c: float in seats:
				Furnish.display_table(p, c, fy, 32.0, id + int(c))
				_note(taken, c - 16.0, c + 16.0)
		3:  # a florist: flower stands, a counter at the right, a plant
			Furnish.till(p, w - 36.0, fy, 28.0, lit)
			Scenes.plant(p, w - 50.0, fy, 28.0, Color("a8683c"))
			for c: float in seats:
				Furnish.flower_stand(p, c, fy, 36.0, id + int(c))
				_note(taken, c - 18.0, c + 18.0)
		SUITE:  # a department store: aisles of shelving, a shop window at the end
			Furnish.shop_window(p, w - 28.0, yt + 14.0, 20.0, 40.0, night, id)
			for c: float in seats:
				Furnish.shelf_unit(p, c - 52.0, fy, 44.0, 54.0, id + int(c))
				_note(taken, c - 52.0, c - 8.0)
		_:  # the corner shop: shelves, a display table and a till
			Furnish.shelf_unit(p, 8.0, fy, 60.0, 42.0, id)
			_note(taken, 8.0, 68.0)
			Furnish.display_table(p, 96.0, fy, 32.0, id + 2)
			_note(taken, 80.0, 112.0)
			Furnish.till(p, w - 68.0, fy, 60.0, lit)
			_note(taken, w - 68.0, w - 8.0)
	var stripe := Color("b8353a") if variant == 0 else Color("3a6a8a")
	Furnish.awning(p, 4.0, yt + 4.0, w - 8.0, stripe, Color("f4ecdc"))


# ---------------------------------------------------------------- services

static func _security(p: Object, w: float, yt: float, fy: float, lit: bool, id: int, taken: Array) -> void:
	_lights(p, w, yt, lit, 96.0)
	Furnish.monitor_wall(p, 12.0, yt + 10.0, 5, 2, lit, id)
	Furnish.badge(p, w * 0.5, yt + 8.0)
	Furnish.service_desk(p, 8.0, fy, 96.0, lit)
	_note(taken, 8.0, 104.0)
	Furnish.gate(p, w - 76.0, w - 20.0, fy, lit)
	_note(taken, w - 78.0, w - 16.0)


static func _medical(p: Object, w: float, yt: float, fy: float, seats: Array, lit: bool, taken: Array) -> void:
	_lights(p, w, yt, lit, 80.0)
	Furnish.red_cross(p, 30.0, yt + 12.0, 24.0, lit)
	Furnish.med_cabinet(p, w - 32.0, fy)
	_note(taken, w - 32.0, w - 8.0)
	for g: Array in groups(seats):
		if g.size() == 2:
			var c0: float = g[0]
			var c1: float = g[1]
			Furnish.vitals(p, c0 - 6.0, yt + 14.0, lit)
			Furnish.hospital_bed(p, c0 - 24.0, fy, lit)
			Furnish.iv_stand(p, c1 - 14.0, fy)
			_note(taken, c0 - 24.0, c1)
		else:
			var c: float = g[0]
			Furnish.waiting_chair(p, c, fy, Color("5a9aa8"))
			_note(taken, c - 8.0, c + 8.0)


static func _recycling(p: Object, w: float, yt: float, fy: float, seats: Array, lit: bool, id: int, upper: bool, taken: Array) -> void:
	_lights(p, w, yt, lit, 96.0)
	if upper:  # the sorting floor: a conveyor the length of the room, crates, a control window
		Furnish.conveyor(p, 8.0, fy, w - 80.0, id)
		Furnish.skip(p, w - 64.0, fy, 52.0, id)
		p.item(w - 56.0, yt + 12.0, 44.0, 20.0, Color("2a3a30"), 1.5)
		if lit:
			p.GR(w - 54.0, yt + 14.0, 40.0, 14.0, Color("8ad0a0"))
		else:
			p.R(w - 54.0, yt + 14.0, 40.0, 14.0, Color("1a2a20"))
		return
	Furnish.baler(p, w - 64.0, fy, 56.0, lit)
	_note(taken, w - 64.0, w - 8.0)
	for i: int in seats.size():
		var c: float = seats[i]
		Furnish.recycle_bin(p, c - 34.0, fy, 26.0, Color(BINS[(i + id) % BINS.size()]))
		_note(taken, c - 34.0, c - 8.0)
	p.R(8, yt + 14, 24, 3, Color("e8c030"))
	p.R(8, yt + 20, 24, 3, Color("e8c030"))


# ---------------------------------------------------------------- parking

static func _ramp(p: Object, w: float, yt: float, fy: float, lit: bool) -> void:
	Furnish.parking_sign(p, 22.0, yt + 10.0, lit)
	var n := int(w / 4.0)
	for i: int in n:
		var top := fy - 4.0 - float(i) * 44.0 / float(maxi(n - 1, 1))
		p.R(i * 4, top, 4, fy - top, Color("3a3a46"))
		p.R(i * 4, top, 4, 2, Color("e8c030") if i % 2 == 0 else Color("2a2a34"))
	p.R(0, fy - 4.0, w, 4, Color("4a4a56"))
	Scenes.ceiling_light(p, w * 0.5, yt, 28.0, lit, 50.0)


static func _space(p: Object, w: float, yt: float, fy: float, lit: bool, id: int) -> void:
	Scenes.ceiling_light(p, w * 0.5, yt, 32.0, lit, 56.0)
	p.R(0, fy - 16.0, 2, 16, Color("e8e2c0"))
	p.R(w - 2.0, fy - 16.0, 2, 16, Color("e8e2c0"))
	var body := Color(CARS[id % CARS.size()])
	Furnish.car(p, (w - 52.0) * 0.5, fy, body, 1 if id % 2 == 0 else -1, lit)
	p.item(w * 0.5 - 10.0, fy - 3.0, 20, 3, Color("8a8a96"), 0.0, false)
