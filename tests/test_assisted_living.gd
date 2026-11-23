extends RefCounted
## Assisted living (#378): the catalogue row, a seniors-only fill, low turnover, steady rent, the care rule (a clinic or
## medical center within 5 floors, else -15 mood and a complaint), noise counting double, the retiree stay path, and
## that a tower without the new kind plays exactly as before. Our own kind: every number is a tunable.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const Rooms := preload("res://scripts/sim/rooms.gd")
const People := preload("res://scripts/sim/people.gd")
const Rent := preload("res://scripts/sim/rent.gd")
const Mood := preload("res://scripts/sim/mood.gd")
const Names := preload("res://scripts/sim/names.gd")
const Grades := preload("res://scripts/sim/grades.gd")
const NoiseScript := preload("res://scripts/sim/noise.gd")
const Synergy := preload("res://scripts/sim/synergy.gd")
const Complaints := preload("res://scripts/sim/complaints.gd")
const Apartments := preload("res://scripts/sim/apartments.gd")
const Toolbar := preload("res://scripts/view/toolbar.gd")
const TestRent := preload("res://tests/test_rent.gd")
const TestApartments := preload("res://tests/test_apartments.gd")

const DAY_TICKS := 2550
## state_hash of old_tower_hash() taken on main before assisted living existed (condo, apartment, clinic, medical).
const OLD_TOWER_HASH := 5666907917047703273


static func _place(t: TowerSim, kind: String, floor_number: int, x: int) -> int:
	return t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find(kind), floor_number, x)


## A tower with an assisted-living room on floor 3 at x 110, reached by stairs; extra rooms are [kind, floor, x] triples.
static func _tower(extra: Array = [], linked: bool = true) -> TowerSim:
	var t := TowerSim.new(42, 100000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	for f in range(3, 12):
		t.floors.fill_span(f, 100, 163)
	assert(_place(t, "assisted", 3, 110) == 0, "assisted places")
	for e: Array in extra:
		assert(_place(t, e[0], e[1], e[2]) == 0, "%s places" % e[0])
	if linked:  # a local shaft from the lobby to floor 11 with one car reaches every floor the tests use
		t.rooms.place_shaft(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("local_shaft"), 1, 11, 100)
		t.rooms.add_car(t.ledger, 0, 3, t.rooms._shaft_base(t.rooms.link_at(1, 100)), 1)
	t.step()
	return t


static func _room(t: TowerSim, kind: String) -> int:
	for id in t.rooms.room_ids():
		if t.rooms.kind_of(id) == kind:
			return id
	return -1


static func _income(t: TowerSim) -> int:
	var total := 0
	for line: Array in t.ledger.lines:
		if line[2] == t.ledger.INCOME:
			total += line[1]
	return total


static func _target(t: TowerSim, who: int) -> int:
	var counts := Mood.floor_counts(t.people, t.grid, t.floors)
	return t.mood.target(t.rooms, t.grid, t.grades, t.people, counts, t.people.index_of(who))


static func _has_factor(t: TowerSim, who: int, reason: int) -> bool:
	var counts := Mood.floor_counts(t.people, t.grid, t.floors)
	for factor: Array in t.mood.factors(t.rooms, t.grid, t.grades, t.people, counts, t.people.index_of(who)):
		if factor[0] == reason:
			return true
	return false


## Residents lost to 1,000 turnover checks on a full room of kind, topped up after each.
static func _departures(kind: String) -> int:
	var t := _tower() if kind == "assisted" else TestApartments._tower()
	var room := _room(t, kind)
	var size: int = t.rooms.people_in(room)
	for k in size:
		t.people.add_person(room, People.NONE, t.rng)
	var lost := 0
	for n in 1000:
		var had := t.people.homes_in(room)
		t.apartments._leave(t, room)
		lost += had - t.people.homes_in(room)
		for k in size - t.people.homes_in(room):
			t.people.add_person(room, People.NONE, t.rng)
	return lost


## The scenario the old-tower regression runs: no assisted living, but the rooms its rules read (condo, apartment,
## clinic, medical center), a fixed seed, three days.
static func old_tower_hash() -> int:
	var t := TowerSim.new(42, 100000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	t.floors.fill_span(3, 100, 163)
	t.floors.fill_span(4, 100, 163)
	_place(t, "condo", 3, 110)
	_place(t, "apartment", 3, 130)
	_place(t, "clinic", 3, 145)
	_place(t, "medical", 4, 110)
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 1, 100)
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 2, 104)
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 3, 100)
	t.clock.set_to_tick(0)
	for n in 3 * DAY_TICKS:
		t.step()
	return t.state_hash()


static func run(check: Callable) -> void:
	# Catalogue: $70,000, 14 wide, 4 residents, appended last, placeable, named, graded, on the toolbar.
	var row: Dictionary = Catalogue.row("assisted")
	check.call(int(row["cost"]) == 70000 and int(row["width"]) == 14 and int(row["people"]) == 4, "assisted: $70,000, 14 wide, four residents")
	check.call(row["rent"] == [2000, 2500, 3000, 4000] and Rent.is_rentable("assisted") and Grades.is_graded("assisted"), "assisted: four rent levels, the third $3,000, graded")
	check.call(Rooms.PLACEABLE.has("assisted") and Names.TITLES.has("assisted") and Catalogue.is_rental("assisted") and not Catalogue.is_condo("assisted"), "assisted: placeable, titled, a rented home and not a condo")
	check.call(Catalogue.IDS.find("assisted") == Catalogue.IDS.size() - 5 and Catalogue.IDS.find("penthouse") == Catalogue.IDS.size() - 6, "assisted: appended last, so existing saves keep their numbering")
	var in_toolbar := false
	for category: Array in Toolbar.CATEGORIES:
		in_toolbar = in_toolbar or (category[1] as Array).has("assisted")
	check.call(in_toolbar and Toolbar.item_state("assisted", 5)["enabled"], "assisted: on the toolbar and buildable")

	# An old tower, without the new kind, plays exactly as it did on main.
	var hash_now := old_tower_hash()
	check.call(hash_now == OLD_TOWER_HASH, "regression: a tower without assisted living keeps its state_hash (%d)" % hash_now)

	# Fill: residents arrive over days, only seniors, up to four; an unreached room stays empty.
	var f := _tower()
	var home := _room(f, "assisted")
	var seen := 0
	for day in 60:
		f.apartments.daily(f)
		seen = maxi(seen, f.people.homes_in(home))
	var seniors := true
	for i in f.people.count():
		seniors = seniors and Names.age_band(f.names.name_seed, f.people.id_at(i)) == Names.BAND_SENIOR
	check.call(seen == 4 and f.people.homes_in(home) <= 4 and seniors, "fill: four residents move in over the days and every one is a senior (%d)" % seen)
	var cut := _tower([], false)
	for day in 30:
		cut.apartments.daily(cut)
	check.call(cut.people.homes_in(_room(cut, "assisted")) == 0, "fill: a room the lobby cannot reach stays empty")

	# Turnover is low: far fewer leave than from an apartment, and nobody leaves at the lowest rent.
	var calm := _departures("assisted")
	var flat := _departures("apartment")
	check.call(Apartments.ASSISTED_LEAVE_PERCENT < Apartments.LEAVE_PERCENT and calm * Catalogue.row("apartment")["people"] < flat * Catalogue.row("assisted")["people"], "turnover: assisted living loses fewer residents for its size (%d of four against %d of two for an apartment)" % [calm, flat])
	var loyal := _tower()
	var loyal_room := _room(loyal, "assisted")
	loyal.rent.set_rent(loyal.rooms, loyal_room, Rent.LEVEL_LOW)
	for k in 4:
		Apartments.add_senior(loyal, loyal_room)
	for day in 300:
		loyal.apartments.daily(loyal)
	check.call(loyal.people.homes_in(loyal_room) == 4, "turnover: at the lowest rent nobody leaves")

	# Rent: $3,000 a quarter at the default level; a vacant room pays nothing.
	var r := _tower()
	var rr := _room(r, "assisted")
	for k in 4:
		Apartments.add_senior(r, rr)
	var before := _income(r)
	TestRent.settle_quarter(r)
	check.call(_income(r) - before == 3000 and r.rent_amount(rr) == 3000, "rent: the default level pays $3,000 a quarter (%d)" % (_income(r) - before))
	var v := _tower()
	var v_before := _income(v)
	TestRent.settle_quarter(v)
	check.call(_income(v) == v_before, "rent: a vacant room pays nothing")

	# Care: a clinic or medical center within 5 floors keeps mood; none (or too far) costs 15 and is a complaint.
	check.call(Synergy.has_care([3, 110, 14], [["clinic", [8, 110, 12]]]) and not Synergy.has_care([3, 110, 14], [["clinic", [9, 110, 12]]]), "care: a clinic five floors away counts and six does not")
	check.call(Synergy.has_care([3, 110, 14], [["medical", [3, 130, 16]]]) and not Synergy.has_care([3, 110, 14], [["office", [3, 130, 16]]]), "care: a medical center counts, an office does not")
	var bare := _tower()
	var ba: int = Apartments.add_senior(bare, _room(bare, "assisted"))
	var bare_target := _target(bare, ba)
	check.call(_has_factor(bare, ba, Mood.REASON_CARE) and Mood.CARE_PENALTY == 15 and Mood.REASON_NAMES.size() > Mood.REASON_CARE, "care: without a clinic the residents lose 15 mood, named in the mood list")
	check.call(bare.complaint_reasons(_room(bare, "assisted")).has(Complaints.NO_CARE) and Complaints.label(Complaints.NO_CARE) != "", "care: without a clinic the room has a complaint")
	for kind: String in ["clinic", "medical"]:
		var near := _tower([[kind, 5, 130]])
		var na: int = Apartments.add_senior(near, _room(near, "assisted"))
		check.call(not _has_factor(near, na, Mood.REASON_CARE) and not near.complaint_reasons(_room(near, "assisted")).has(Complaints.NO_CARE), "care: a %s two floors up clears the penalty and the complaint" % kind)
		check.call(_target(near, na) >= bare_target + Mood.CARE_PENALTY, "care: mood is at least 15 higher with a %s (%d against %d)" % [kind, _target(near, na), bare_target])
	var far := _tower([["clinic", 10, 130]])
	check.call(far.complaint_reasons(_room(far, "assisted")).has(Complaints.NO_CARE), "care: a clinic seven floors up is too far")
	var condo := _tower([["condo", 3, 130]])
	var cc: int = condo.people.add_person(_room(condo, "condo"), People.NONE, condo.rng)
	check.call(not _has_factor(condo, cc, Mood.REASON_CARE), "care: only assisted living has the rule")

	# Noise counts double, capped at the maximum.
	var loud: Array = [["office", [3, 124, 12]]]
	var quiet_level := NoiseScript.level_among("condo", [3, 110, 14], loud)
	check.call(quiet_level > 0 and NoiseScript.level_among("assisted", [3, 110, 14], loud) == mini(quiet_level * 2, NoiseScript.MAX_LEVEL), "noise: assisted living feels an office beside it twice as much (%d)" % quiet_level)
	check.call(NoiseScript.is_sensitive("assisted") and NoiseScript.level_among("assisted", [3, 110, 14], [["nightclub", [3, 124, 12]], ["party_hall", [3, 98, 12]]]) == NoiseScript.MAX_LEVEL, "noise: assisted living is noise sensitive and capped")

	# Retiree stay path: with no condo to take them, a retiring senior takes a place in assisted living.
	var s := _tower([["office", 3, 130]])
	s.life.retire_per_100000 = 100000
	s.life.retire_stay_percent = 100
	var office := _room(s, "office")
	var guard := 0
	while Names.age_band(s.names.name_seed, s.people.next_id()) != Names.BAND_SENIOR and guard < 64:
		s.people.skip_id()
		guard += 1
	s.people.add_person(People.NONE, office, s.rng)
	var workers_before := s.people.workers_in(office)
	s.life.retire(s)
	check.call(s.people.homes_in(_room(s, "assisted")) >= 1 and s.people.workers_in(office) == workers_before, "retire: retirees with no condo place stay on in assisted living (%d) and the office is refilled" % s.people.homes_in(_room(s, "assisted")))

	# A fixed-seed run: two runs agree, residents arrive, and the tower saves and loads.
	var x := _tower([["clinic", 4, 110]])
	var y := _tower([["clinic", 4, 110]])
	for tower: TowerSim in [x, y]:
		tower.clock.set_to_tick(0)
		for n in 3 * DAY_TICKS:
			tower.step()
	check.call(x.people.count() > 0 and x.state_hash() == y.state_hash(), "seeded run: residents arrive and two runs of the same seed agree (%d)" % x.people.count())
	var copy := TowerSim.new(1, 1)
	var xa := _room(x, "assisted")
	check.call(copy.load_state(x.save()) and copy.state_hash() == x.state_hash() and copy.people.homes_in(xa) == x.people.homes_in(xa), "save: assisted living and its residents survive save and load")
