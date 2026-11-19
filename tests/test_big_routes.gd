extends RefCounted
## Routes across a 100-floor tower (8.3): at most one transfer, only at lobbies; a trip needing two
## is unreachable (no path, stress, a warning); stress follows travel time.

const TowerSim := preload("res://scripts/sim/tower.gd")
const RoutesScript := preload("res://scripts/sim/routes.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")
const TripsScript := preload("res://scripts/sim/trips.gd")
const MessagesScript := preload("res://scripts/sim/messages.gd")
const TestShafts := preload("res://tests/test_shafts.gd")
const TestOfficeDay := preload("res://tests/test_office_day.gd")


## Floors 1 to 100 over columns 100 to 131, the ground lobby on floor 1 and sky lobbies on every
## sky floor, all as wide as the ground lobby.
static func _tower() -> TowerSim:
	var t := TowerSim.new(1, 1000000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 131, 1)
	for f in range(2, 101):
		t.floors.fill_span(f, 100, 131)
	for f: int in [15, 30, 45, 60, 75, 90]:
		t.floors.build_lobby(t.ledger, 0, f, 100, 131, 1, t.grid)
	t.stars = 3
	return t


static func _shaft(t: TowerSim, kind: String, bottom: int, top: int, x: int) -> void:
	t.rooms.place_shaft(t.grid, t.floors, t.ledger, 0, CatalogueScript.IDS.find(kind), bottom, top, x)


static func _rides(route: Dictionary) -> int:
	var rides := 0
	for leg: Dictionary in route["legs"]:
		if leg["kind"] == RoutesScript.ELEVATOR:
			rides += 1
	return rides


static func run(check: Callable) -> void:
	# Floor 5 to floor 95 with one transfer: four flights down to the ground lobby, the express to
	# the floor-90 sky lobby, then a local shaft up to 95.
	var t := _tower()
	for f in range(1, 5):
		t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, f, 100 if f % 2 == 1 else 104)
	_shaft(t, "express_shaft", 1, 90, 110)
	_shaft(t, "local_shaft", 90, 100, 120)
	var started := Time.get_ticks_usec()
	var r := RoutesScript.find(t.floors, t.rooms, t.grid, 5, 104, 95, 120)
	var micros := Time.get_ticks_usec() - started
	check.call(r["reason"] == RoutesScript.OK and _rides(r) == 2, "floor 5 to floor 95 takes exactly one transfer (two rides)")
	check.call(micros < 250000, "a route search across 100 floors stays cheap (%d us)" % micros)
	var lobby_ok := false
	for leg: Dictionary in r["legs"]:
		if leg["kind"] == RoutesScript.ELEVATOR and leg["to_floor"] == 90:
			lobby_ok = true
	check.call(lobby_ok, "the transfer is at the floor-90 sky lobby")

	# Two transfers: local 5 to 15, local 15 to 30, local 30 to 40 (three rides) is unreachable.
	var u := _tower()
	_shaft(u, "local_shaft", 1, 15, 120)
	_shaft(u, "local_shaft", 15, 30, 124)
	_shaft(u, "local_shaft", 30, 40, 128)
	var two := RoutesScript.find(u.floors, u.rooms, u.grid, 5, 120, 38, 128)
	check.call(two["reason"] == RoutesScript.TOO_MANY_TRANSFERS and two["legs"].is_empty(), "a trip needing two transfers has no path")
	var one := RoutesScript.find(u.floors, u.rooms, u.grid, 5, 120, 25, 124)
	check.call(one["reason"] == RoutesScript.OK and _rides(one) == 2, "the same shafts give a one-transfer trip")
	# A transfer off a lobby floor is refused too: shafts meeting at floor 20 (no sky lobby there).
	var v := _tower()
	_shaft(v, "local_shaft", 1, 20, 120)
	_shaft(v, "local_shaft", 20, 40, 124)
	check.call(RoutesScript.find(v.floors, v.rooms, v.grid, 3, 120, 35, 124)["reason"] == RoutesScript.TOO_MANY_TRANSFERS, "transfers happen only at lobbies")

	# Escalator first, then a waiting car, then stairs: an escalator beats a waiting car at the transfer.
	var e := _tower()
	_shaft(e, "local_shaft", 1, 15, 120)
	_shaft(e, "local_shaft", 15, 30, 124)
	e.rooms.place_escalator(e.grid, e.floors, e.ledger, 0, 15, 104)
	var esc := RoutesScript.find(e.floors, e.rooms, e.grid, 15, 126, 16, 106)
	var kinds: Array[int] = []
	for leg: Dictionary in esc["legs"]:
		kinds.append(leg["kind"])
	check.call(esc["reason"] == RoutesScript.OK and kinds.has(RoutesScript.ESCALATOR) and not kinds.has(RoutesScript.ELEVATOR), "an escalator is preferred to riding a car")

	# People: an office on floor 38 behind three rides. Workers cannot reach it: they give up, take
	# stress, and the log warns once.
	var w := _tower()
	_shaft(w, "local_shaft", 1, 15, 120)
	_shaft(w, "local_shaft", 15, 30, 124)
	_shaft(w, "local_shaft", 30, 40, 128)
	w.rooms.place_room(w.grid, w.floors, w.ledger, 0, CatalogueScript.IDS.find("office"), 38, 100)
	var office: int = w.rooms.room_ids()[-1]
	for _k in 3:  # tenants would not move in (the office is unreachable), so the workers are added by hand
		w.people.add_person(-1, office, w.rng)
	w.rng.state = 3
	w.clock.set_to_tick(TestOfficeDay._tick_at(PeopleScript.ARRIVE - 5, 0))
	var peak := 0
	var moved := 0
	for _n in 600:
		w.step()
		for i in w.people.count():
			peak = maxi(peak, w.people.stress_of(i))
			if w.people.trip_state(i) == PeopleScript.TRIP_MOVING or w.people.trip_state(i) == PeopleScript.TRIP_RIDING:
				moved += 1
	var warned := 0
	for i in w.messages.count():
		if w.messages.entry(i)[1] == MessagesScript.TRIP_UNREACHABLE:
			warned += 1
	check.call(w.people.count() == 3 and peak >= TripsScript.STRESS_NO_ROUTE, "workers who cannot reach the office take stress (%d people, peak %d)" % [w.people.count(), peak])
	check.call(warned == 1, "the unreachable trips are warned about once (%d)" % warned)
	check.call(moved == 0, "nobody set off for the unreachable office")

	# Stress follows travel time: 3 per minute, angry above 120 (41 minutes), uneasy at 40.
	var per := TripsScript.STRESS_PER_TRAVEL_MINUTE
	check.call(PeopleScript.band_of(per * 40) == PeopleScript.BAND_UNEASY and PeopleScript.band_of(per * 41) == PeopleScript.BAND_ANGRY, "travel stress turns angry above 120")
	check.call(PeopleScript.STRESS_MAX == 300, "stress runs 0 to 300")
