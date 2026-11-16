extends RefCounted
## The benchmark tower (4.10): lobby and 10 more floors the full width, 8 local shafts with 8 cars
## each, and 340 offices (about 2,040 workers once they move in). Built through the sim's own
## placement calls, with a fixed seed, so every run starts identically.

const TowerSim := preload("res://scripts/sim/tower.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")

const TOP := 12
const SHAFT_XS: Array[int] = [20, 70, 120, 170, 220, 270, 320, 370]
const OFFICES := 340
const START_TICK := 580  ## About 8:48 on a weekday: the first arrivals come at 9:00, a few ticks on.


## The tower, with the clock at START_TICK, just before the morning arrivals. Each floor holds at most about 40
## offices, so 340 need floors 3 to 11; the loops end because x only ever grows and floors are finite.
static func build(seed_value: int, offices: int = OFFICES, shafts: int = SHAFT_XS.size()) -> TowerSim:
	var t := TowerSim.new(seed_value, 2000000000)
	t.stars = 5
	t.floors.build_lobby(t.ledger, 0, 1, 0, 399, 2)
	for f in range(3, TOP + 1):
		t.floors.fill_span(f, 0, 399)
	var shaft_kind := CatalogueScript.IDS.find("local_shaft")
	for x in SHAFT_XS.slice(0, shafts):
		t.rooms.place_shaft(t.grid, t.floors, t.ledger, 0, shaft_kind, 1, TOP, x)
	for id in t.rooms.shaft_ids():
		for car in 8:
			t.rooms.add_car(t.ledger, 0, 5, id, 1)
	var office := CatalogueScript.IDS.find("office")
	var width: int = CatalogueScript.field("office", "width")
	var placed := 0
	for f in range(3, TOP + 1):
		var x := 0
		while x + width <= 400 and placed < offices:
			if t.rooms.place_room(t.grid, t.floors, t.ledger, 0, office, f, x) == 0:
				placed += 1
				x += width
			else:
				x += 1
	t.clock.set_to_tick(START_TICK)
	return t


## How many offices the tower holds (the benchmark fails if the build came up short).
static func office_count(t: TowerSim) -> int:
	var n := 0
	for id in t.rooms.room_ids():
		if t.rooms.kind_of(id) == "office":
			n += 1
	return n
