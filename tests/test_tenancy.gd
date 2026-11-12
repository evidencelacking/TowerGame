extends RefCounted
## Office tenancy tests (3.2): 6 workers move in when the office is reachable from the lobby,
## on weekdays before 13:00 only.

const TowerSim := preload("res://scripts/sim/tower.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const Tenancy := preload("res://scripts/sim/tenancy.gd")
const People := preload("res://scripts/sim/people.gd")
const Clock := preload("res://scripts/sim/clock.gd")

const MORNING_TICK := 700  ## Weekday, mid morning.
const AFTERNOON_TICK := 1500  ## Weekday, 14:00.
const WEEKEND_TICK := 5200  ## Day 3 of the quarter, the weekend.


## Lobby on floors 1-2 over columns 100-131, a floor 3 above it, one office on floor 3.
static func _tower() -> TowerSim:
	var t := TowerSim.new(7, 100000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 131, 2)
	t.floors.fill_span(3, 100, 131)
	t.rooms.place_room(t.grid, t.floors, t.ledger, 0, CatalogueScript.IDS.find("office"), 3, 110)
	return t


static func _office(t: TowerSim) -> int:
	return t.rooms.room_ids()[0]


## Stairs from floor 1 up to floor 3.
static func _link(t: TowerSim) -> void:
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 1, 100)
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 2, 104)


## Sets the clock to start_tick, then steps enough ticks for new sim minutes to pass.
static func _run_at(t: TowerSim, start_tick: int, ticks: int = 10) -> void:
	t.clock.set_to_tick(start_tick)
	for i in ticks:
		t.step()


static func run(check: Callable) -> void:
	var t := _tower()
	var office := _office(t)
	check.call(t.rooms.kind_of(office) == "office", "tenancy test office is placed")

	_run_at(t, MORNING_TICK)
	check.call(t.people.count() == 0, "an unreachable office stays empty")

	_link(t)
	_run_at(t, MORNING_TICK)
	check.call(t.people.workers_in(office) == 6 and t.people.count() == 6, "linking it with stairs fills it with exactly 6")
	check.call(t.people.home_of(0) == People.NONE and t.people.work_of(0) == office, "workers live outside and work in the office")

	_run_at(t, MORNING_TICK + 50, 100)
	check.call(t.people.workers_in(office) == 6, "never more than 6 per office")

	var late := _tower()
	_link(late)
	_run_at(late, AFTERNOON_TICK)
	check.call(late.clock.minute_of_day() >= Tenancy.LEASE_END and late.people.count() == 0, "no leasing after 13:00")

	var weekend := _tower()
	_link(weekend)
	_run_at(weekend, WEEKEND_TICK)
	check.call(weekend.clock.day_of_week() == Clock.WE and weekend.people.count() == 0, "no leasing on a weekend day")

	_run_at(weekend, MORNING_TICK)
	check.call(weekend.people.workers_in(_office(weekend)) == 6, "it fills at the next eligible weekday morning")
