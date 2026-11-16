extends RefCounted
## Performance work (4.10) must not change the sim. Pins the state hash of a small benchmark
## tower (tools/bench_tower.gd), whose value was taken before the optimisations and must stay the
## same, and checks the shortcuts the route search and tenancy now use against the plain answers.

const TowerSim := preload("res://scripts/sim/tower.gd")
const RoutesScript := preload("res://scripts/sim/routes.gd")
const GridScript := preload("res://scripts/sim/grid.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const Bench := preload("res://tools/bench_tower.gd")

const SMALL_TICKS := 400
const SMALL_HASH := 2032652333440579341  ## Hash of the small tower after SMALL_TICKS ticks, from main without the #108 speed-ups (after #114).


## What a scan of the whole grid for stairs and escalators finds, in scan order: [floor, column, escalator].
static func _scanned_links(t: TowerSim) -> Array:
	var found: Array = []
	var seen: Dictionary = {}
	for floor_number in range(GridScript.FLOOR_MIN, GridScript.FLOOR_MAX + 1):
		if not GridScript.is_valid_floor(floor_number) or RoomsScript.floor_above(floor_number) == 0:
			continue
		for column in GridScript.WIDTH_UNITS:
			var id := t.rooms.link_at(floor_number, column)
			if id == GridScript.EMPTY or seen.has(id) or not RoomsScript.is_stair_kind(t.rooms.kind_of(id)):
				continue
			seen[id] = true
			found.append([floor_number, column, t.rooms.kind_of(id) == "escalator"])
	return found


static func run(check: Callable) -> void:
	var small := Bench.build(42, 24, 3)
	check.call(Bench.office_count(small) == 24 and small.rooms.total_cars() == 24, "the small benchmark tower has 24 offices and 24 cars")
	for _i in SMALL_TICKS:
		small.step()
	check.call(small.people.count() == 144, "the small benchmark tower houses 144 workers")
	check.call(small.state_hash() == SMALL_HASH, "the small benchmark tower reaches the same state hash as before the speed-ups")

	# Stairs and escalators come out of the route search in the order a grid scan finds them.
	var t := Bench.build(42, 6, 2)
	t.floors.fill_span(-1, 0, 399)
	t.floors.fill_span(-2, 0, 399)
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 5, 60)
	t.rooms.place_escalator(t.grid, t.floors, t.ledger, 0, 3, 100)
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 3, 30)
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, -2, 10)
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, -1, 14)
	var scanned := _scanned_links(t)
	check.call(scanned.size() == 5, "five stairs and escalators are placed")
	check.call(RoutesScript._stair_spots(t.rooms, t.grid) == scanned, "route search lists stairs in grid scan order")

	# Worker counts per room match the one-room count.
	var counts := small.people.worker_counts()
	var same := true
	for id in small.rooms.room_ids():
		if int(counts.get(id, 0)) != small.people.workers_in(id):
			same = false
	check.call(same, "worker_counts agrees with workers_in for every room")

	# The waiting keys say what car_waiting_at says, for every stop of every shaft, mid-morning.
	var agree := true
	for _i in 200:
		small.step()
		var keys := small.rooms.waiting_keys()
		for shaft in small.rooms.shaft_ids():
			for stop in small.rooms.stops_of(shaft):
				if small.rooms.car_waiting_at(shaft, stop) != keys.has(shaft * 1000 + stop + 100):
					agree = false
	check.call(agree, "waiting_keys agrees with car_waiting_at")
