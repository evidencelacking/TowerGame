extends RefCounted
## Stress and trip tests (3.6): bands, clamping, travel and waiting stress, recovery, giving up.

const TowerSim := preload("res://scripts/sim/tower.gd")
const TestTenancy := preload("res://tests/test_tenancy.gd")
const TestOfficeDay := preload("res://tests/test_office_day.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const People := preload("res://scripts/sim/people.gd")
const Trips := preload("res://scripts/sim/trips.gd")


## Steps until person 0's trip is idle at the goal after having moved; returns the ticks used (-1 on timeout).
static func _until_arrived(t: TowerSim, room: int) -> int:
	var n := 0
	while n < 4000:
		t.step()
		n += 1
		if t.people.location_of(0) == room and t.people.trip_state(0) == People.TRIP_IDLE:
			return n
	return -1


## Steps up to a day of ticks until the person has just finished a trip into room; returns their stress then.
static func _arrival_stress(t: TowerSim, room: int) -> int:
	var was_moving := false
	for n in 4000:
		t.step()
		if t.people.trip_state(0) == People.TRIP_MOVING:
			was_moving = true
		elif was_moving:
			return t.people.stress_of(0) if t.people.location_of(0) == room else -1
	return -1


## Two offices on floor 3, no stairs: a person living in one and working in the other walks the floor.
static func _tower_two_offices() -> TowerSim:
	var t := TowerSim.new(7, 100000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 131, 2)
	t.floors.fill_span(3, 100, 131)
	var kind := CatalogueScript.IDS.find("office")
	t.rooms.place_room(t.grid, t.floors, t.ledger, 0, kind, 3, 102)
	t.rooms.place_room(t.grid, t.floors, t.ledger, 0, kind, 3, 118)
	return t


static func run(check: Callable) -> void:
	# Bands.
	check.call(People.band_of(79) == People.BAND_CALM, "79 is calm")
	check.call(People.band_of(80) == People.BAND_UNEASY, "80 is uneasy")
	check.call(People.band_of(120) == People.BAND_UNEASY, "120 is uneasy")
	check.call(People.band_of(121) == People.BAND_ANGRY, "121 is angry")
	check.call(People.band_of(0) == People.BAND_CALM and People.band_of(People.STRESS_MAX) == People.BAND_ANGRY, "the ends of the range are calm and angry")

	# Clamping.
	var t := TestTenancy._tower()
	TestTenancy._link(t)
	TestTenancy._run_at(t, TestTenancy.MORNING_TICK)
	var office := TestTenancy._office(t)
	t.people.set_stress(0, 290)
	t.people.add_stress(0, 50)
	check.call(t.people.stress_of(0) == People.STRESS_MAX, "stress clamps at 300")
	t.people.set_stress(0, 5)
	t.people.add_stress(0, -50)
	check.call(t.people.stress_of(0) == 0, "stress clamps at 0")
	t.people.set_stress(0, 80)
	check.call(t.people.stress_band(0) == People.BAND_UNEASY, "a person's band follows their stress")

	# Workers get from the lobby to the office on a weekday morning, stress rising with the route.
	var w := TestOfficeDay._filled()
	var office_w := TestTenancy._office(w)
	TestOfficeDay._at(w, People.ARRIVE - 60)
	for n in 4000:
		w.step()
		if w.people.location_of(0) == People.NONE and w.people.trip_state(0) == People.TRIP_IDLE:
			break
	check.call(w.people.location_of(0) == People.NONE, "workers start the morning outside the tower")
	TestOfficeDay._at(w, People.ARRIVE + People.ARRIVAL_SPREAD + 1)
	var stairs_stress := _arrival_stress(w, office_w)
	check.call(stairs_stress > 0 and w.people.location_of(0) == office_w, "workers reach the office after the trip")
	check.call(stairs_stress < People.UNEASY_FROM, "an ordinary stairs commute stays calm")

	var f := _tower_two_offices()
	var ids := f.rooms.room_ids()
	check.call(ids.size() == 2, "the same-floor test offices are placed")
	f.people.add_person(ids[0], ids[1], f.rng)
	TestOfficeDay._at(f, People.ARRIVE + People.ARRIVAL_SPREAD + 1)
	var walk_stress := _arrival_stress(f, ids[1])
	check.call(walk_stress > 0 and f.people.location_of(0) == ids[1], "a same-floor walk reaches the other office")
	check.call(stairs_stress > walk_stress, "a stairs trip builds more stress than a same-floor walk")

	# Recovery while idle.
	w.people.set_stress(0, 50)
	var minute := w.clock.minute_of_day()
	var guard := 0
	while w.clock.minute_of_day() == minute and guard < 100:
		w.step()
		guard += 1
	check.call(w.people.trip_state(0) == People.TRIP_IDLE and w.people.stress_of(0) == 50 - Trips.STRESS_RECOVERY_PER_MINUTE, "an idle person recovers each minute")
	w.people.set_stress(0, 0)
	for n in 100:
		w.step()
	check.call(w.people.stress_of(0) == 0, "recovery never goes below 0")

	# No route: give up in place with the penalty.
	var stranded := TestTenancy._tower()
	stranded.people.add_person(People.NONE, TestTenancy._office(stranded), stranded.rng)  # no stairs: unreachable
	TestOfficeDay._at(stranded, People.ARRIVE - 30)
	for n in 4000:
		stranded.step()
		if stranded.people.stress_of(0) > 0:
			break
	check.call(stranded.people.trip_state(0) == People.TRIP_IDLE and stranded.people.location_of(0) == TestTenancy._office(stranded) and stranded.people.goal_room(0) == People.NONE, "with no route the person gives up and stays where they are")
	check.call(stranded.people.stress_of(0) >= Trips.STRESS_NO_ROUTE, "giving up costs stress")

	# Save round trip of the new fields, mid-trip.
	var h := TestOfficeDay._filled()
	TestOfficeDay._at(h, People.LEAVE + 1)
	for n in 4000:
		h.step()
		if h.people.trip_state(0) == People.TRIP_MOVING:
			break
	check.call(h.people.trip_state(0) == People.TRIP_MOVING and h.people.trip_left(0) > 0 and h.people.trip_total(0) >= h.people.trip_left(0), "a person can be saved mid-trip")
	var u := TowerSim.new(7, 100000000)
	check.call(u.load_state(h.save()) and u.people.state_ints() == h.people.state_ints() and u.people.trip_left(0) == h.people.trip_left(0), "trip fields survive a save")

	# Determinism over a day.
	check.call(TestOfficeDay._day_ints(5) == TestOfficeDay._day_ints(5), "same seed, same stress and trips over a day")
