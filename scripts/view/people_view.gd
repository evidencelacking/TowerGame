extends RefCounted
## Where to draw each person and in what colour. Reads the sim only; never writes to it.
## Positions are integers in sim units (floor number, column). Moving people are placed along
## their route by trip progress; resting people stand in their room; people outside are skipped.

const PeopleScript := preload("res://scripts/sim/people.gd")
const RoutesScript := preload("res://scripts/sim/routes.gd")
const TripsScript := preload("res://scripts/sim/trips.gd")

## Colour per stress band: calm black, uneasy pink, angry red.
const BAND_COLORS: Array[Color] = [Color(0.05, 0.05, 0.05), Color(1.0, 0.45, 0.70), Color(0.85, 0.08, 0.08)]
## Marks drawn above the head per band, so the band reads without colour: 0, 1 or 2.
const BAND_MARKS: Array[int] = [0, 1, 2]
const _STAIRS_WEIGHT := TripsScript.WALK_COLUMNS_PER_MINUTE * TripsScript.STAIRS_MINUTES  ## Columns a stairs leg counts as.

## Routes already found, keyed by trip ends; the caller keeps it and it is cleared when the
## floors or rooms change (see tower_renderer.gd).
var route_cache: Dictionary = {}


static func color_of(band: int) -> Color:
	return BAND_COLORS[clampi(band, 0, BAND_COLORS.size() - 1)]


static func marks_of(band: int) -> int:
	return BAND_MARKS[clampi(band, 0, BAND_MARKS.size() - 1)]


## Where a trip is after elapsed of total minutes: [floor, column]. Pure integer maths.
static func along(legs: Array, elapsed: int, total: int) -> Array[int]:
	var weight := 0
	for leg: Dictionary in legs:
		weight += _leg_weight(leg)
	var at := weight * clampi(elapsed, 0, maxi(total, 1)) / maxi(total, 1)
	for leg: Dictionary in legs:
		var w := _leg_weight(leg)
		var from_x: int = leg["from_x"]
		var to_x: int = leg["to_x"]
		if at <= w:
			var x := from_x if w == 0 else from_x + (to_x - from_x) * at / w
			var floor_number: int = leg["floor"]
			if leg["kind"] == RoutesScript.STAIRS and at * 2 > w:
				floor_number = leg["to_floor"]
			return [floor_number, x]
		at -= w
	var last: Dictionary = legs[legs.size() - 1]
	return [last["to_floor"], last["to_x"]]


static func _leg_weight(leg: Dictionary) -> int:
	if leg["kind"] == RoutesScript.WALK:
		return absi((leg["to_x"] as int) - (leg["from_x"] as int))
	return _STAIRS_WEIGHT


## One entry per person drawn: {"floor", "x", "band", "moving"}.
func figures(tower: Object) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var people: PeopleScript = tower.people
	for i in people.count():
		var band := people.stress_band(i)
		if people.trip_state(i) == PeopleScript.TRIP_MOVING:
			var spot := _moving_spot(tower, i)
			if not spot.is_empty():
				out.append({"floor": spot[0], "x": spot[1], "band": band, "moving": true})
			continue
		var room := people.location_of(i)
		var run: Array[int] = tower.grid.run_of(room)
		if run.is_empty():
			continue
		out.append({"floor": run[0], "x": run[1] + people.id_at(i) % maxi(run[2], 1), "band": band, "moving": false})
	return out


func _moving_spot(tower: Object, i: int) -> Array[int]:
	var people: PeopleScript = tower.people
	var span: Array = tower.floors.lobby_span()
	if span.is_empty():
		return []
	var entry: Array[int] = [TripsScript.GROUND_FLOOR, span[0]]
	var from := _spot(tower, people.trip_from(i), entry)
	var to := _spot(tower, people.goal_room(i), entry)
	var key := [from, to]
	if not route_cache.has(key):
		var route: Dictionary = RoutesScript.find(tower.floors, tower.rooms, tower.grid, from[0], from[1], to[0], to[1])
		route_cache[key] = route["legs"] if route["reason"] == RoutesScript.OK else []
	var legs: Array = route_cache[key]
	if legs.is_empty():
		return from
	var total := people.trip_total(i)
	return along(legs, total - people.trip_left(i), total)


static func _spot(tower: Object, room: int, entry: Array[int]) -> Array[int]:
	var run: Array[int] = tower.grid.run_of(room)  # empty for NONE
	if run.is_empty():
		return entry
	return [run[0], run[1]]
