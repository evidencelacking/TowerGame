extends RefCounted
## Where to draw each person and in what colour. Reads the sim only; never writes to it.
## Each figure has an integer floor and column. Moving ones also carry a fractional column ("fx")
## and row ("frow") so stairs and escalator legs can be drawn as a smooth diagonal; resting people
## stand in their room; people outside are skipped.

const PeopleScript := preload("res://scripts/sim/people.gd")
const RoutesScript := preload("res://scripts/sim/routes.gd")
const TripsScript := preload("res://scripts/sim/trips.gd")
const HotelScript := preload("res://scripts/sim/hotel.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const VC := preload("res://scripts/view/view_consts.gd")
const ActivityLook := preload("res://scripts/view/activity_look.gd")
const RoomRecipes := preload("res://scripts/view/room_recipes.gd")
const Suites := preload("res://scripts/view/suites.gd")

## Colour per stress band: calm black, uneasy pink, angry red.
const BAND_COLORS: Array[Color] = [Color(0.05, 0.05, 0.05), Color(1.0, 0.45, 0.70), Color(0.85, 0.08, 0.08)]
## Marks drawn above the head per band, so the band reads without colour: 0, 1 or 2.
const BAND_MARKS: Array[int] = [0, 1, 2]
const _STAIRS_WEIGHT := TripsScript.WALK_COLUMNS_PER_MINUTE * TripsScript.STAIRS_MINUTES  ## Columns a stairs leg counts as.

## Poses a figure can have; the renderer picks the sprite frames from them.
const POSE_WALK := 0
const POSE_STAIRS := 1
const POSE_ESCALATOR := 2

## Routes already found, keyed by trip ends; the caller keeps it and it is cleared when the
## floors or rooms change (see tower_renderer.gd).
var route_cache: Dictionary = {}


static func color_of(band: int) -> Color:
	return BAND_COLORS[clampi(band, 0, BAND_COLORS.size() - 1)]


static func marks_of(band: int) -> int:
	return BAND_MARKS[clampi(band, 0, BAND_MARKS.size() - 1)]


## Where a trip is after elapsed of total minutes: [floor, column], whole numbers. The floor on a
## stairs or escalator leg is the nearer one; see along_f for the smooth version.
static func along(legs: Array, elapsed: int, total: int) -> Array[int]:
	var at := along_f(legs, elapsed, total)
	return [at["floor"], roundi(at["fx"])]


## Where a trip is after elapsed of total minutes, smoothly (the view may use floats):
## {"floor" (nearest floor), "fx" (column, fractional), "frow" (row, fractional, so height moves
## continuously between floors), "pose"}. A stairs or escalator leg crosses its link's width while
## it climbs one floor, so the figure moves along the drawn tread: up goes left to right, down
## right to left.
static func along_f(legs: Array, elapsed: int, total: int) -> Dictionary:
	var weight := 0
	for leg: Dictionary in legs:
		weight += _leg_weight(leg)
	var at := float(weight) * clampi(elapsed, 0, maxi(total, 1)) / maxi(total, 1)
	var done := 0.0
	for n in legs.size():
		var w := _leg_weight(legs[n])
		if at <= done + w or n == legs.size() - 1:
			var f := 0.0 if w == 0 else clampf((at - done) / w, 0.0, 1.0)
			return _leg_spot(legs[n], f)
		done += w
	return {}


static func _leg_spot(leg: Dictionary, f: float) -> Dictionary:
	var floor_number: int = leg["floor"]
	var from_row := VC.floor_to_row(floor_number)
	var kind: int = leg["kind"]
	var from_x: int = leg["from_x"]
	var to_x: int = leg["to_x"]
	if kind == RoutesScript.STAIRS or kind == RoutesScript.ESCALATOR:
		var to_row := VC.floor_to_row(leg["to_floor"])
		var across := f if to_row < from_row else 1.0 - f  # climbing runs left to right
		return {
			"floor": leg["to_floor"] if f > 0.5 else floor_number,
			"fx": from_x + across * (link_columns(kind) - 1),
			"frow": from_row + (to_row - from_row) * f,
			"pose": POSE_STAIRS if kind == RoutesScript.STAIRS else POSE_ESCALATOR,
		}
	return {"floor": floor_number, "fx": from_x + (to_x - from_x) * f, "frow": float(from_row), "pose": POSE_WALK}


## Columns the drawn link of a leg kind spans (its catalogue width).
static func link_columns(kind: int) -> int:
	return CatalogueScript.field("stairs" if kind == RoutesScript.STAIRS else "escalator", "width")


static func _leg_weight(leg: Dictionary) -> int:
	if leg["kind"] == RoutesScript.WALK:
		return absi((leg["to_x"] as int) - (leg["from_x"] as int))
	return _STAIRS_WEIGHT


## One entry per person drawn: {"id", "floor", "x", "fx", "frow", "pose", "band", "moving"}. A resting
## person also has "act" (an ActivityLook activity) and "px", "pfeet": where the pose is drawn, in native
## pixels, on a recipe spot of the room.
func figures(tower: Object) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var people: PeopleScript = tower.people
	var pending: Array[Array] = []  # resting people, placed once every room's use is known
	var minute: int = tower.clock.minute_of_day()
	for i in people.count():
		var band := people.stress_band(i)
		if people.trip_state(i) == PeopleScript.TRIP_RIDING:
			continue  # queued at a shaft or riding: elevator_view draws the queue and the car's load
		if people.trip_state(i) == PeopleScript.TRIP_MOVING:
			var spot := _moving_spot(tower, i)
			if not spot.is_empty():
				out.append({"id": people.id_at(i), "floor": spot["floor"], "x": roundi(spot["fx"]), "fx": spot["fx"], "frow": spot["frow"],
					"pose": spot["pose"], "band": band, "moving": true})
			continue
		var room := people.location_of(i)
		var run: Array[int] = tower.grid.run_of(room)
		if run.is_empty():
			continue
		var column: int = run[1] + people.id_at(i) % maxi(run[2], 1)
		var kind: String = tower.rooms.kind_of(room)
		var staying: bool = tower.hotel.is_hotel(room) and tower.hotel.state_of(room) == HotelScript.STAYING
		var act := ActivityLook.classify(kind, people.work_of(i) == room, people.goal_of(i), staying, minute, people.trip_state(i) == PeopleScript.TRIP_REQUESTED)
		pending.append([out.size(), run, people.id_at(i), kind, act, band, column, room])
		out.append({})  # filled in below, once the suites are known
	_place_resting(out, pending)
	out.append_array(_cleaners(tower))
	return out


## Places the resting figures: each takes the next spot of its room, or of its suite when neighbouring
## rooms of one kind are all in use and draw as one (#276). pending holds [index in out, run, id, kind, act,
## band, column, room] per resting person; the suites come from the same rule the renderer draws by.
static func _place_resting(out: Array[Dictionary], pending: Array[Array]) -> void:
	var rooms: Dictionary = {}  # room id -> its entry for Suites.groups
	for item: Array in pending:
		var run: Array[int] = item[1]
		var room: int = item[7]
		var entry: Dictionary = rooms.get(room, {"key": VC.floor_to_row(run[0]), "x": run[1] * VC.CELL_W, "w": run[2] * VC.CELL_W, "kind": item[3], "in_use": false, "room": room})
		entry["in_use"] = entry["in_use"] or item[4] != ActivityLook.SLEEPING
		rooms[room] = entry
	var entries: Array = rooms.values()
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["key"] < b["key"] or (a["key"] == b["key"] and a["x"] < b["x"]))
	var suite_of: Dictionary = {}  # room id -> [left px, width px, first room of the suite]
	for group: Array[int] in Suites.groups(entries):
		var bounds := Suites.span(entries, group)
		for index: int in group:
			suite_of[(entries[index] as Dictionary)["room"]] = [bounds[0], bounds[1], (entries[group[0]] as Dictionary)["room"]]
	var turns: Dictionary = {}  # room (or a suite's first room) -> people placed there so far
	for item: Array in pending:
		var room: int = item[7]
		var suite: Array = suite_of.get(room, [])
		var seat: int = suite[2] if not suite.is_empty() else room
		var turn: int = turns.get(seat, 0)
		turns[seat] = turn + 1
		out[item[0]] = _resting(item[1], item[2], item[3], item[4], turn, item[5], item[6], room, suite)


## A resting figure of a run [floor, column, width, ...] doing `act`, placed on a spot of its room.
static func _resting(run: Array[int], id: int, kind: String, act: int, turn: int, band: int, column: int, room: int = 0, suite: Array = []) -> Dictionary:
	var width_px: int = run[2] * VC.CELL_W
	var origin: int = run[1] * VC.CELL_W
	var variant := RoomRecipes.variant_for(kind, room)
	if not suite.is_empty():  # one space across the joined rooms: its width, its left edge, its recipe
		origin = suite[0]
		width_px = suite[1]
		variant = RoomRecipes.SUITE
	var at := ActivityLook.place(act, ActivityLook.spot_for(kind, width_px, id, turn, act, variant), width_px)
	var row_top := VC.floor_to_row(run[0]) * VC.CELL_H
	return {"id": id, "floor": run[0], "x": column, "fx": float(column), "frow": float(VC.floor_to_row(run[0])),
		"pose": POSE_WALK, "band": band, "moving": false, "act": act, "px": origin + at.x, "pfeet": row_top + at.y}


## A housekeeper in each dirty hotel room one has claimed (on the way to it or cleaning it; the sim keeps
## no finer state to show). Their id is the room's id, a stand-in for a staff id.
func _cleaners(tower: Object) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for room: int in tower.rooms.room_ids():
		if not tower.hotel.is_hotel(room) or not tower.hotel.is_dirty(room) or not tower.housekeeping.is_claimed(room):
			continue
		var run: Array[int] = tower.grid.run_of(room)
		if run.is_empty():
			continue
		var cleaner := _resting(run, room, tower.rooms.kind_of(room), ActivityLook.CLEANING, 1, 0, run[1], room)
		cleaner["staff"] = true  # not a person: the id is the room's, so a click must not open a person window
		out.append(cleaner)
	return out


func _moving_spot(tower: Object, i: int) -> Dictionary:
	var people: PeopleScript = tower.people
	var span: Array = tower.floors.lobby_span()
	if span.is_empty():
		return {}
	var entry: Array[int] = [TripsScript.GROUND_FLOOR, span[0]]
	var from := _spot(tower, people.trip_from(i), entry)
	var to := _spot(tower, people.goal_room(i), entry)
	var key := [from, to]
	if not route_cache.has(key):
		var route: Dictionary = RoutesScript.find(tower.floors, tower.rooms, tower.grid, from[0], from[1], to[0], to[1])
		route_cache[key] = route["legs"] if route["reason"] == RoutesScript.OK else []
	var legs: Array = route_cache[key]
	if legs.is_empty():
		return _still(from)
	var leg := people.trip_leg(i)
	legs = TripsScript.segment(legs, leg)
	if legs.is_empty():
		return _still(from)
	var total := people.trip_total(i)
	return along_f(legs, total - people.trip_left(i), total)


static func _still(spot: Array[int]) -> Dictionary:
	return {"floor": spot[0], "fx": float(spot[1]), "frow": float(VC.floor_to_row(spot[0])), "pose": POSE_WALK}


static func _spot(tower: Object, room: int, entry: Array[int]) -> Array[int]:
	var run: Array[int] = tower.grid.run_of(room)  # empty for NONE
	if run.is_empty():
		return entry
	return [run[0], run[1]]
