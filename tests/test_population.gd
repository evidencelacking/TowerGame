extends RefCounted
## Population tests (3.8): people in the tower now, mid-trip included; the HUD text matches.

const TowerSim := preload("res://scripts/sim/tower.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const People := preload("res://scripts/sim/people.gd")
const Hud := preload("res://scripts/view/hud.gd")
const TestTenancy := preload("res://tests/test_tenancy.gd")
const TestOfficeDay := preload("res://tests/test_office_day.gd")


## Reachable office (6 workers) and reachable condo (3 residents) on floor 3.
static func _tower() -> TowerSim:
	var t := TestTenancy._tower()
	t.floors.fill_span(3, 132, 150)
	t.rooms.place_room(t.grid, t.floors, t.ledger, 0, CatalogueScript.IDS.find("condo"), 3, 120)
	TestTenancy._link(t)
	return t


## Jumps to the minute of day 0 and steps long enough for trips to finish.
static func _at(t: TowerSim, minute: int, ticks: int = 40) -> void:
	t.clock.set_to_tick(TestOfficeDay._tick_at(minute, 0))
	for i in ticks:
		t.step()


static func run(check: Callable) -> void:
	var t := _tower()
	_at(t, 10 * 60, 10)  # sells the condo and moves the workers in
	check.call(t.people.count() == 9, "population test tower has 9 people")
	check.call(t.population() == t.people.in_tower_count(), "Tower.population is the people count in the tower")

	_at(t, 6 * 60)
	check.call(t.population() == 3, "6:00: only the 3 residents are in the tower")
	_at(t, 10 * 60)
	check.call(t.population() == 6, "mid-morning: the 6 workers are in, residents are away")
	_at(t, 16 * 60 + 30)
	check.call(t.population() == 6, "before 17:00 the 6 workers are still in")
	_at(t, 18 * 60 + 30)
	check.call(t.population() <= 3, "the count drops after workers leave at 17:00")
	_at(t, 22 * 60)
	check.call(t.population() == 3, "22:00: the 3 residents are home")

	# Mid-trip people count; idle outside does not.
	var m := TowerSim.new(1, 100000000)
	m.people.add_person(People.NONE, People.NONE, m.rng)
	check.call(m.population() == 0, "a person idle outside is not counted")
	m.people.start_trip(0, 5)
	check.call(m.population() == 1, "a person mid-trip counts")
	m.people.finish_trip(0)
	check.call(m.population() == 0, "arriving or leaving at NONE stops counting")

	# HUD text equals the sim value.
	check.call(Hud.format_population(t.population()) == "Pop %d" % t.population(), "the HUD text shows the sim value")
