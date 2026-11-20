extends RefCounted
## Event and service visuals (10.7): fire and smoke on burning rooms, guards on their way to a fire, the
## rescue craft, the threat search sweeping the floors, and the device once found. Each draws only while
## its sim state is active, and reads the tower without changing it. Motion comes from the sim tick (and
## the guards' own response time), so the same sim moment draws the same. Elevator doors are in
## transport_look.gd (door_open). Canvas is anything with draw_rect, so tests can record the calls.

const SecurityScript := preload("res://scripts/sim/security.gd")
const GridScript := preload("res://scripts/sim/grid.gd")
const Palette := preload("res://scripts/view/palette.gd")
const VC := preload("res://scripts/view/view_consts.gd")

const FIRE_FIELDS := 3  ## Ints per burning room in Fire.state_ints: room, periods burned, guards arrive tick.
const FIRE_HEADER := 5  ## Ints before the burning rooms in Fire.state_ints; the fifth is how many rooms burn.
const GUARDS_SHOWN := 2
const RESCUE_FLIGHT_TICKS := 120  ## The craft is drawn flying in for this long before it arrives.
const SMOKE_PUFFS := 4
const FRAME_TICKS := 4  ## Ticks per flame frame.


## The burning rooms with their state: [{"room", "periods", "arrive"}] read through Fire.state_ints.
static func burning(tower: Object) -> Array[Dictionary]:
	var ints: Array[int] = tower.fire.state_ints()
	var out: Array[Dictionary] = []
	for n in ints[FIRE_HEADER - 1]:
		var at := FIRE_HEADER + n * FIRE_FIELDS
		out.append({"room": ints[at], "periods": ints[at + 1], "arrive": ints[at + 2]})
	return out


## The pixel rects of a room, one per floor it covers (bottom floor first), each one floor tall.
static func room_rects(tower: Object, room: int) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var run: Array[int] = tower.grid.run_of(room)
	if run.is_empty():
		return out
	for floor_number: int in tower.rooms.floors_of(tower.grid, room):
		out.append(Rect2i(run[1] * VC.CELL_W, VC.floor_to_row(floor_number) * VC.CELL_H, run[2] * VC.CELL_W, VC.CELL_H))
	return out


## Fire and smoke in every burning room: flame tongues along the floor that flicker from the tick and grow
## the longer the room burns, a scorch over the room, and puffs of smoke rising past its ceiling.
static func draw_fire(canvas: Object, tower: Object, tick: int) -> void:
	var p := Palette.get_palette()
	for fire: Dictionary in burning(tower):
		var rects := room_rects(tower, fire["room"])
		var age := mini(fire["periods"], 2)
		for r: Rect2i in rects:
			var floor_y := r.end.y - VC.SLAB_H
			canvas.draw_rect(Rect2i(r.position.x, r.position.y, r.size.x, r.size.y - VC.SLAB_H), Color(0.05, 0.02, 0.0, 0.22 + 0.12 * age))
			var height := 8 + 5 * age
			var x := r.position.x + 2
			var n := 0
			while x + 3 <= r.end.x - 1:  # x grows by 5 each pass, so this ends
				var flick := (tick / FRAME_TICKS + n * 3 + (fire["room"] as int)) % 4
				var h := height - flick * 2
				canvas.draw_rect(Rect2i(x, floor_y - h, 3, h), p["red"])
				canvas.draw_rect(Rect2i(x + 1, floor_y - h + 3, 2, maxi(h - 3, 1)), Color("f08030"))
				canvas.draw_rect(Rect2i(x + 1, floor_y - maxi(h / 2, 2), 1, maxi(h / 2, 2)), p["gold"])
				x += 5
				n += 1
		if rects.is_empty():
			continue
		var top: Rect2i = rects[rects.size() - 1]
		for puff in SMOKE_PUFFS:  # drifting up from the ceiling, each on its own phase
			var phase := (tick / 2 + puff * 9 + (fire["room"] as int)) % 36
			var px := top.position.x + 4 + (puff * 11) % maxi(top.size.x - 8, 1) + phase / 12
			var py := top.position.y + 6 - phase
			var shade := 0.35 + 0.02 * float(phase)
			canvas.draw_rect(Rect2i(px, py, 3, 3), Color(shade, shade, shade, 0.75 - float(phase) * 0.015))


## Guards from the answering office to each fire they have not reached yet: two figures climbing the
## emergency stairs, their position from how far through the response time the tick is. A floor no office
## covers (arrive 0) has no guards. Nothing is drawn once the fire is out (the room leaves the burning list).
static func draw_guards(canvas: Object, tower: Object, tick: int) -> void:
	var p := Palette.get_palette()
	var uniform: Color = Palette.hue("security")
	for fire: Dictionary in burning(tower):
		var arrive: int = fire["arrive"]
		var rects := room_rects(tower, fire["room"])
		if arrive <= 0 or rects.is_empty():
			continue
		var target: Rect2i = rects[0]
		var floors: Array[int] = tower.rooms.floors_of(tower.grid, fire["room"])
		var office: int = SecurityScript.responder(tower.rooms, tower.grid, floors[0])
		var office_run: Array[int] = tower.grid.run_of(office)
		if office == 0 or office_run.is_empty():
			continue
		var response := SecurityScript.response_ticks(tower.rooms, tower.grid, floors[0])
		var progress := clampf(1.0 - float(arrive - tick) / float(maxi(response, 1)), 0.0, 1.0)
		var from_x := office_run[1] * VC.CELL_W
		var from_row := VC.floor_to_row(office_run[0])
		var to_row := VC.floor_to_row(floors[0])
		for n in GUARDS_SHOWN:
			var x := roundi(lerpf(from_x, target.position.x + target.size.x / 2.0, progress)) + n * (VC.FIGURE_W + 1)
			var row := lerpf(from_row, to_row, progress)
			var feet := roundi((row + 1.0) * VC.CELL_H) - 3 - ((tick / 2 + n) % 2)  # a step bob
			_guard(canvas, x, feet, uniform, p)


## One guard: a dark cap over a skin face, a uniform body, a white badge.
static func _guard(canvas: Object, x: int, feet: int, uniform: Color, p: Dictionary) -> void:
	var top := feet - VC.FIGURE_H
	canvas.draw_rect(Rect2i(x, top, VC.FIGURE_W, 2), p["ink"])  # cap
	canvas.draw_rect(Rect2i(x + 1, top + 2, VC.FIGURE_W - 2, 3), p["skin"])
	canvas.draw_rect(Rect2i(x, top + 5, VC.FIGURE_W, 6), uniform)
	canvas.draw_rect(Rect2i(x + 1, top + 6, 2, 2), p["white"])  # badge
	canvas.draw_rect(Rect2i(x + 1, feet - 5, 2, 5), uniform.darkened(0.4))
	canvas.draw_rect(Rect2i(x + VC.FIGURE_W - 3, feet - 5, 2, 5), uniform.darkened(0.4))


## The rescue craft: while one is on its way (Fire.rescue_at) and within RESCUE_FLIGHT_TICKS of arriving, a
## helicopter flies in from the left edge to the first burning floor, rotor blurring from the tick.
static func draw_rescue(canvas: Object, tower: Object, tick: int) -> void:
	var arrives: int = tower.fire.rescue_at()
	if arrives <= 0 or arrives - tick > RESCUE_FLIGHT_TICKS:
		return
	var p := Palette.get_palette()
	var rects: Array[Rect2i] = []
	for fire: Dictionary in burning(tower):
		rects = room_rects(tower, fire["room"])
		break
	var target_x := VC.world_rect().size.x / 4.0
	var target_y := VC.world_rect().size.y / 2.0
	if not rects.is_empty():
		target_x = rects[0].position.x - 10
		target_y = rects[0].position.y + 6
	var progress := clampf(1.0 - float(arrives - tick) / RESCUE_FLIGHT_TICKS, 0.0, 1.0)
	var x := roundi(lerpf(0.0, target_x, progress))
	var y := roundi(target_y) + (tick / 3) % 2  # hovers
	var body: Color = p["red"]
	canvas.draw_rect(Rect2i(x, y + 2, 12, 5), body)  # cabin
	canvas.draw_rect(Rect2i(x + 8, y + 3, 3, 3), p["white"])  # window
	canvas.draw_rect(Rect2i(x - 8, y + 3, 8, 1), body)  # tail
	canvas.draw_rect(Rect2i(x - 8, y, 1, 4), body)
	canvas.draw_rect(Rect2i(x + 1, y + 7, 10, 1), p["ink"])  # skids
	var blade := 14 if (tick / 2) % 2 == 0 else 8
	canvas.draw_rect(Rect2i(x + 6 - blade / 2, y, blade, 1), p["ink"])  # rotor
	canvas.draw_rect(Rect2i(x + 6, y + 1, 1, 1), p["ink"])


## The threat search: each security office sweeps the floors in turn (the sim's own order and pace), so the
## floor being searched gets a scanning band with a guard standing in it, the floors already searched a
## faint cleared line; once a sweep reaches the device floor it shows as a flashing red marker.
static func draw_search(canvas: Object, tower: Object, tick: int) -> void:
	if not tower.threat.is_active():
		return
	var ints: Array[int] = tower.threat.state_ints()
	var started: int = ints[5]
	if started <= 0:
		return  # the owner has not answered yet: nothing is searching
	var p := Palette.get_palette()
	var swept := maxi((tick - started) / tower.threat.SEARCH_TICKS, 0)
	var world_w: int = VC.world_rect().size.x
	for office: int in SecurityScript.offices(tower.rooms):
		var run: Array[int] = tower.grid.run_of(office)
		if run.is_empty():
			continue
		var office_index := GridScript.floor_to_index(run[0])
		for rank in mini(swept, 2 * SecurityScript.COVER_FLOORS + 1):
			var cleared := GridScript.index_to_floor(office_index + _gap_of(rank))
			if cleared != 0:
				var row := VC.floor_to_row(cleared) * VC.CELL_H
				canvas.draw_rect(Rect2i(0, row + VC.CELL_H - VC.SLAB_H - 1, world_w, 1), Color(0.35, 0.8, 0.9, 0.35))
		var now := GridScript.index_to_floor(office_index + _gap_of(swept))
		if now == 0 or swept > 2 * SecurityScript.COVER_FLOORS:
			continue
		var now_row := VC.floor_to_row(now) * VC.CELL_H
		var scan_x := (tick * 3) % maxi(world_w, 1)
		canvas.draw_rect(Rect2i(0, now_row + 2, world_w, VC.CELL_H - VC.SLAB_H - 4), Color(0.35, 0.8, 0.9, 0.14))
		canvas.draw_rect(Rect2i(scan_x, now_row + 2, 2, VC.CELL_H - VC.SLAB_H - 4), Color(0.7, 1.0, 1.0, 0.6))
		_guard(canvas, run[1] * VC.CELL_W + 4, now_row + VC.CELL_H - 3, Palette.hue("security"), p)
	if tower.threat.found(tower.grid, tick):
		var device_row := VC.floor_to_row(tower.threat.device_floor()) * VC.CELL_H
		var blink: bool = (tick / 3) % 2 == 0
		canvas.draw_rect(Rect2i(world_w / 2 - 4, device_row + VC.CELL_H - VC.SLAB_H - 9, 9, 7), p["ink"])
		canvas.draw_rect(Rect2i(world_w / 2 - 2, device_row + VC.CELL_H - VC.SLAB_H - 7, 5, 3), p["red"] if blink else p["gold"])


## The floor offset from an office of the nth floor in a sweep: 0, +1, -1, +2, -2 ... (Security.search_rank inverted).
static func _gap_of(rank: int) -> int:
	if rank == 0:
		return 0
	return (rank + 1) / 2 if rank % 2 == 1 else -(rank / 2)
