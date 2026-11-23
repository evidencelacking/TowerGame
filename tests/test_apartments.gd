extends RefCounted
## Rental apartments (#379): the catalogue row, a daily fill while reachable, turnover (more at grade C, none
## at the lowest rent), quarterly rent at each level, the renter mood penalty against a condo, residents in the
## population, a fixed-seed run and save/load. Our own kind: every number is a tunable.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const Rooms := preload("res://scripts/sim/rooms.gd")
const People := preload("res://scripts/sim/people.gd")
const Rent := preload("res://scripts/sim/rent.gd")
const Mood := preload("res://scripts/sim/mood.gd")
const Names := preload("res://scripts/sim/names.gd")
const Grades := preload("res://scripts/sim/grades.gd")
const Apartments := preload("res://scripts/sim/apartments.gd")
const TestRent := preload("res://tests/test_rent.gd")

const DAY_TICKS := 2550


## A tower with a reachable apartment on floor 3 (and a condo beside it when with_condo). linked false leaves out the stairs.
## The first step runs Tower.refresh_reach, so Tenancy.routed knows which rooms the lobby reaches before any check.
static func _tower(linked: bool = true, with_condo: bool = false) -> TowerSim:
	var t := TowerSim.new(42, 100000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	t.floors.fill_span(3, 100, 163)
	var refusal := t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("apartment"), 3, 110)
	assert(refusal == 0, "apartment places")
	if with_condo:
		refusal = t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("condo"), 3, 130)
		assert(refusal == 0, "condo places")
	if linked:
		t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 1, 100)
		t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 2, 104)
	t.step()
	return t


static func _room(t: TowerSim, kind: String) -> int:
	for id in t.rooms.room_ids():
		if t.rooms.kind_of(id) == kind:
			return id
	return -1


static func _move_in(t: TowerSim, room: int, n: int) -> void:
	for k in n:
		t.people.add_person(room, People.NONE, t.rng)


static func _income(t: TowerSim) -> int:
	var total := 0
	for line: Array in t.ledger.lines:
		if line[2] == t.ledger.INCOME:
			total += line[1]
	return total


static func run(check: Callable) -> void:
	# Unlock and cost: $50,000, 12 wide, two residents, star 2, placeable, named, last in the ids.
	var row: Dictionary = Catalogue.row("apartment")
	check.call(int(row["cost"]) == 50000 and int(row["width"]) == 12 and int(row["people"]) == 2, "apartment: $50,000, 12 wide, 2 residents")
	check.call(Catalogue.star("apartment") == 2 and Rooms.PLACEABLE.has("apartment") and Names.TITLES.has("apartment"), "apartment: unlocks at 2 stars, placeable, has titles")
	check.call(Catalogue.IDS.find("apartment") == Catalogue.IDS.size() - 1 and Catalogue.IDS.find("apartment") == Catalogue.IDS.find("conference_center") + 1, "apartment: appended last, so existing saves keep their numbering")
	check.call(row["rent"] == [2000, 3000, 4000, 6000] and Rent.is_rentable("apartment") and Grades.is_graded("apartment"), "apartment: four rent levels around $4,000, graded")
	var built := TowerSim.new(1, 1000000)
	built.floors.build_lobby(built.ledger, 0, 1, 100, 163, 2)
	built.floors.fill_span(3, 100, 163)
	var before := built.ledger.balance
	built.rooms.place_room(built.grid, built.floors, built.ledger, 0, Catalogue.IDS.find("apartment"), 3, 110)
	check.call(before - built.ledger.balance >= 50000, "apartment: building one costs at least $50,000")
	check.call(Catalogue.cost("condo") == 80000 and Catalogue.row("condo")["people"] == 3 and Catalogue.row("condo")["width"] == 16, "condo: cost, residents and width are unchanged")

	# Fill over days: a reachable apartment takes at most one resident a day and is full within 40 days;
	# one the lobby cannot reach stays empty.
	var t := _tower()
	var apt := _room(t, "apartment")
	check.call(t.people.homes_in(apt) == 0, "fill: a new apartment starts empty")
	var most_in_a_day := 0
	var days_to_full := -1
	for day in 40:
		var had := t.people.homes_in(apt)
		t.apartments.daily(t)
		most_in_a_day = maxi(most_in_a_day, t.people.homes_in(apt) - had)
		if days_to_full == -1 and t.people.homes_in(apt) == 2:
			days_to_full = day + 1
	check.call(most_in_a_day == 1, "fill: residents move in one at a time, at most one a day")
	check.call(days_to_full >= 2, "fill: it takes more than one day to fill (%d)" % days_to_full)
	var cut := _tower(false)
	for day in 40:
		cut.apartments.daily(cut)
	check.call(cut.people.homes_in(_room(cut, "apartment")) == 0, "fill: an apartment the lobby cannot reach stays empty")

	# Turnover: people leave over the days and the vacancy refills; the lowest rent keeps everyone; grade C leaves more.
	var churn := _tower()
	var home := _room(churn, "apartment")
	_move_in(churn, home, 2)
	var left := 0
	var refilled := false
	for day in 400:
		var was := churn.people.homes_in(home)
		churn.apartments.daily(churn)
		if churn.people.homes_in(home) < was:
			left += 1
		elif churn.people.homes_in(home) > was and left > 0:
			refilled = true
	check.call(left > 0 and refilled, "turnover: residents leave over 400 days (%d days with a leaver) and the vacancy refills" % left)
	var loyal := _tower()
	var loyal_room := _room(loyal, "apartment")
	loyal.rent.set_rent(loyal.rooms, loyal_room, Rent.LEVEL_LOW)
	_move_in(loyal, loyal_room, 2)
	for day in 400:
		loyal.apartments.daily(loyal)
	check.call(loyal.people.homes_in(loyal_room) == 2, "turnover: at the lowest rent nobody leaves")
	var calm := _departures(false)
	var stressed := _departures(true)
	check.call(calm > 0 and stressed > calm * 2 and Apartments.LEAVE_PERCENT_C > Apartments.LEAVE_PERCENT, "turnover: a grade C apartment loses far more residents (%d against %d)" % [stressed, calm])

	# Quarterly rent at each level; a vacant apartment pays nothing.
	var expected: Array[int] = [2000, 3000, 4000, 6000]
	for level in 4:
		var r := _tower()
		var room := _room(r, "apartment")
		check.call(r.rent.set_rent(r.rooms, room, level) == Rent.OK, "rent: level %d can be set on an apartment" % level)
		_move_in(r, room, 2)
		var before_rent := _income(r)
		TestRent.settle_quarter(r)
		var paid := _income(r) - before_rent
		check.call(paid == expected[level] and r.rent_amount(room) == expected[level], "rent: level %d pays $%d a quarter (%d)" % [level, expected[level], paid])
	var vacant := _tower()
	var vacant_before := _income(vacant)
	TestRent.settle_quarter(vacant)
	check.call(_income(vacant) == vacant_before, "rent: a vacant apartment pays nothing")

	# Mood: an apartment resident sits RENTER_PENALTY under a condo resident in the same conditions.
	var m := _tower(true, true)
	var apt_room := _room(m, "apartment")
	var condo := _room(m, "condo")
	var a := m.people.add_person(apt_room, People.NONE, m.rng)
	var c := m.people.add_person(condo, People.NONE, m.rng)
	var counts := Mood.floor_counts(m.people, m.grid, m.floors)
	var apt_target := m.mood.target(m.rooms, m.grid, m.grades, m.people, counts, m.people.index_of(a))
	var condo_target := m.mood.target(m.rooms, m.grid, m.grades, m.people, counts, m.people.index_of(c))
	check.call(Mood.RENTER_PENALTY == 5 and condo_target - apt_target == Mood.RENTER_PENALTY, "mood: an apartment resident's target is 5 under a condo resident's (%d against %d)" % [apt_target, condo_target])
	var named := false
	for factor: Array in m.mood_factors(m.people.index_of(a)):
		named = named or factor[0] == Mood.REASON_RENTER
	check.call(named and Mood.REASON_NAMES.size() > Mood.REASON_RENTER, "mood: the renter factor is listed and named")

	# Population: residents inside the tower count, in the star rules' population and under "residents".
	var p := _tower()
	var empty_pop := p.population()
	_move_in(p, _room(p, "apartment"), 2)
	check.call(empty_pop == 0 and p.population() == 2 and int(p.population_breakdown()["now"]["residents"]) == 2, "population: two apartment residents count as 2 residents in the tower (%d)" % p.population())

	# A fixed-seed run of three days: residents arrive, rent comes in, and two runs agree; the tower saves and loads.
	var x := _tower()
	var y := _tower()
	for tower: TowerSim in [x, y]:
		tower.clock.set_to_tick(0)
		for n in 3 * DAY_TICKS:
			tower.step()
	check.call(x.people.count() > 0 and _income(x) > 0, "seeded run: residents moved in (%d) and paid rent ($%d)" % [x.people.count(), _income(x)])
	check.call(x.state_hash() == y.state_hash(), "seeded run: two runs of the same seed agree")
	var copy := TowerSim.new(1, 1)
	check.call(copy.load_state(x.save()) and copy.state_hash() == x.state_hash(), "save: a tower with apartments and residents survives save and load")
	var xa := _room(x, "apartment")
	check.call(copy.rooms.kind_of(xa) == "apartment" and copy.people.homes_in(xa) == x.people.homes_in(xa), "save: the apartment and its residents come back")


## Residents lost to 1,000 turnover checks on a full apartment, topped up after each; stressed makes the room grade C.
static func _departures(stressed: bool) -> int:
	var t := _tower()
	var room := _room(t, "apartment")
	_move_in(t, room, 2)
	var lost := 0
	for n in 1000:
		if stressed:
			for i in t.people.count():
				t.people.set_stress(i, People.STRESS_MAX)
				t.grades._tripped[t.people.id_at(i)] = true
		var had := t.people.homes_in(room)
		t.apartments._leave(t, room)
		lost += had - t.people.homes_in(room)
		_move_in(t, room, 2 - t.people.homes_in(room))
	return lost
