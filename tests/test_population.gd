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
	run_breakdown(check)
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


## Current vs overall population and the grouped breakdown (#383).
static func run_breakdown(check: Callable) -> void:
	var t := _tower()
	_at(t, 10 * 60, 10)
	_at(t, 10 * 60)
	var b := t.population_breakdown()
	check.call(int(b["now_total"]) == t.population(), "breakdown: the now total is Tower.population (what the stars use)")
	check.call(int(b["now"]["workers"]) == 6 and int(b["now"]["residents"]) == 0, "breakdown: mid-morning 6 workers in, residents out")
	check.call(int(b["overall"]["workers"]) == 6 and int(b["overall"]["residents"]) == 3, "breakdown: overall counts 6 workers and 3 residents")
	check.call(int(b["overall_total"]) == 9 and int(b["overall_total"]) >= int(b["now_total"]), "breakdown: overall is everyone, at least those in now")
	_at(t, 6 * 60)
	b = t.population_breakdown()
	check.call(int(b["now"]["residents"]) == 3 and int(b["overall_total"]) == 9, "breakdown: 6:00 residents in now, overall unchanged")

	# Hotel guests and outside visitors.
	var g := TowerSim.new(1, 100000000)
	g.people.add_person(People.NONE, People.NONE, g.rng)
	b = g.population_breakdown()
	check.call(int(b["overall"]["residents"]) == 1 and int(b["now_total"]) == 0, "breakdown: a person outside counts overall, not now")
	g.commerce.load_ints(_with_visitors_today(g.commerce.state_ints(), 25))
	check.call(g.commerce.visitors_today() == 25 and int(g.population_breakdown()["overall"]["visitors"]) == 25, "breakdown: visitors served today count overall")
	check.call(int(g.population_breakdown()["overall_total"]) == 26, "breakdown: overall total adds visitors to people")
	check.call(g.commerce.state_ints()[g.commerce.state_ints().size() - 1] == 25, "breakdown: the visitors-today counter is saved")

	var tip := Hud.population_tooltip(t.population_breakdown())
	check.call(tip.contains("now") and tip.contains("Overall per day: 9") and tip.contains("visitors"), "the tooltip lists both numbers by group")
	check.call(Hud.format_population(3, 9) == "Pop 3 (9/day)", "the HUD label shows both numbers")


static func _with_visitors_today(ints: Array[int], n: int) -> Array[int]:
	var out := ints.duplicate()
	out[out.size() - 1] = n
	return out
