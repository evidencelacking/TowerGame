extends RefCounted
## Parking (7.7, #172): a ramp column under the ground lobby, spaces chained to it, broken chains
## marked and not counted, demand from the larger of offices and suites, and suites using only
## working spaces.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const DemandsScript := preload("res://scripts/sim/demands.gd")


static func _tower() -> TowerSim:
	var t := TowerSim.new(5, 1000000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	return t


static func _put(t: TowerSim, kind: String, floor_number: int, x: int) -> int:
	return t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find(kind), floor_number, x)


static func _cut(t: TowerSim, floor_number: int, x: int) -> int:
	return t.rooms.bulldoze(t.grid, t.floors, t.ledger, 0, floor_number, x)


static func run(check: Callable) -> void:
	check.call(Rooms.PLACEABLE.has("parking_ramp") and Rooms.PLACEABLE.has("parking_space"), "ramps and spaces are placeable")
	check.call(Catalogue.cost("parking_ramp") == 50000 and Catalogue.cost("parking_space") == 3000 and Catalogue.star("parking_space") == 3, "ramp $50,000, space $3,000, both from 3 stars")

	# Ramps: first on B1 under the lobby, then one column directly below.
	var t := _tower()
	check.call(_put(t, "parking_ramp", 3, 110) == Rooms.NOT_BASEMENT, "parking above ground is refused")
	check.call(_put(t, "parking_ramp", -2, 110) == Rooms.RAMP_NOT_UNDER_LOBBY, "the first ramp must be on B1")
	check.call(_put(t, "parking_ramp", -1, 250) == Rooms.RAMP_NOT_UNDER_LOBBY, "the first ramp must be under the ground lobby")
	check.call(t.rooms.room_count() == 0, "refused ramps place nothing")
	check.call(_put(t, "parking_ramp", -1, 110) == Rooms.OK, "the first ramp goes on B1 under the lobby")
	check.call(_put(t, "parking_ramp", -3, 110) == Rooms.RAMP_NOT_BELOW_RAMP, "a ramp must sit directly below a ramp")
	check.call(_put(t, "parking_ramp", -2, 130) == Rooms.RAMP_COLUMN, "later ramps share the column of the first")
	check.call(_put(t, "parking_ramp", -2, 110) == Rooms.OK and _put(t, "parking_ramp", -3, 110) == Rooms.OK, "the next ramps go directly below, one column")

	# Spaces chain to the ramp or to a working space.
	check.call(_put(t, "parking_space", -1, 130) == Rooms.NOT_CHAINED, "a space that touches nothing is refused")
	check.call(_put(t, "parking_space", -1, 114) == Rooms.OK, "a space beside the ramp is chained")
	check.call(_put(t, "parking_space", -1, 118) == Rooms.OK and _put(t, "parking_space", -1, 122) == Rooms.OK, "spaces chain onto spaces")
	check.call(_put(t, "parking_space", -2, 114) == Rooms.OK, "a space on another floor chains to the ramp beside it")
	check.call(Parking.working_spaces(t.rooms, t.grid) == 4 and Parking.broken_ids(t.rooms, t.grid).is_empty(), "four working spaces and nothing broken")

	# Cutting a link breaks what lies beyond it; building it again revives them.
	var middle := t.grid.cell_at(-1, 118)
	_cut(t, -1, 118)
	check.call(Parking.working_spaces(t.rooms, t.grid) == 2, "cutting a space leaves the ones before it working")
	check.call(_put(t, "parking_space", -1, 126) == Rooms.NOT_CHAINED, "a space beyond the gap does not touch the chain")
	var far_cut := _tower()
	_put(far_cut, "parking_ramp", -1, 110)
	_put(far_cut, "parking_space", -1, 114)
	_put(far_cut, "parking_space", -1, 118)
	_put(far_cut, "parking_space", -1, 122)
	var far := far_cut.grid.cell_at(-1, 122)
	_cut(far_cut, -1, 118)
	var expected: Array[int] = [far]
	check.call(Parking.broken_ids(far_cut.rooms, far_cut.grid) == expected, "the space beyond the cut is marked broken")
	check.call(Parking.working_spaces(far_cut.rooms, far_cut.grid) == 1, "a broken space does not count")
	check.call(_put(far_cut, "parking_space", -1, 118) == Rooms.OK and Parking.working_spaces(far_cut.rooms, far_cut.grid) == 3, "restoring the link revives the spaces beyond")
	_cut(far_cut, -1, 110)
	check.call(Parking.working_spaces(far_cut.rooms, far_cut.grid) == 0 and Parking.broken_ids(far_cut.rooms, far_cut.grid).size() == 3, "cutting the top ramp breaks the whole chain")
	check.call(middle > 0, "fixture: the cut space existed")

	# Demand: one working space per office, and per suite; the larger of the two.
	var D := DemandsScript
	var all: Array[String] = ["office", "hotel_suite", "security", "medical", "recycling", "parking_space"]
	var bit := 1 << (D.PARKING - 1)
	check.call(D.compute(3, {"office": 3, "parking_working": 2}, all) & bit != 0, "fewer working spaces than offices: parking is needed")
	check.call(D.compute(3, {"office": 3, "parking_working": 3}, all) & bit == 0, "a space per office clears the demand")
	check.call(D.compute(3, {"office": 3, "hotel_suite": 5, "parking_working": 4}, all) & bit != 0, "five suites need five spaces (the peak, not 3 + 5)")
	check.call(D.compute(3, {"office": 3, "hotel_suite": 5, "parking_working": 5}, all) & bit == 0, "offices and suites share spaces: five serve both")
	check.call(D.compute(3, {"office": 4, "parking_space": 4}, all) & bit == 0, "with no working count given, placed spaces count")
	check.call(Parking.needed(3, 5) == 5 and Parking.needed(7, 2) == 7, "the need is the larger of offices and suites")

	# On a live tower the demand counts only working spaces.
	var live := _tower()
	live.stars = 3
	live.floors.fill_span(3, 100, 163)
	live.rooms.place_room(live.grid, live.floors, live.ledger, 0, Catalogue.IDS.find("office"), 3, 100)
	live.promote_stars()
	check.call(live.demands.is_open(D.PARKING), "an office at 3 stars needs parking")
	_put(live, "parking_ramp", -1, 110)
	_put(live, "parking_space", -1, 114)
	live.promote_stars()
	check.call(not live.demands.is_open(D.PARKING), "a working space for the office clears it")
	_cut(live, -1, 110)
	live.promote_stars()
	check.call(live.demands.is_open(D.PARKING), "cutting the ramp leaves the space broken and the demand returns")
