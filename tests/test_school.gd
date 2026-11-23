extends RefCounted
## Schools (#370): the catalogue row (24 seats, 3 stars, $150,000, 16 wide), children only, weekdays only,
## the 08:15 drop-off and 15:15 pick-up rows, the odd-id school age split with the daycare, the synergy
## on condos, and a fixed-seed day in which children attend. Our own kind: every number is a tunable.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Commerce := preload("res://scripts/sim/commerce.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const Clock := preload("res://scripts/sim/clock.gd")
const Rooms := preload("res://scripts/sim/rooms.gd")
const People := preload("res://scripts/sim/people.gd")
const Synergy := preload("res://scripts/sim/synergy.gd")
const Names := preload("res://scripts/sim/names.gd")

const DAY_TICKS := 2550


static func _tower(with_daycare: bool = false) -> TowerSim:
	var t := TowerSim.new(42, 100000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	t.floors.fill_span(3, 100, 163)
	var kinds: Array[String] = ["school"]
	if with_daycare:
		kinds.append("daycare")
	var x := 100
	for kind: String in kinds:
		var refusal := t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find(kind), 3, x)
		assert(refusal == 0, "%s places, refusal %d" % [kind, refusal])
		x += int(Catalogue.field(kind, "width"))
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 1, 100)
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 2, 104)
	return t


static func _room(t: TowerSim, kind: String) -> int:
	for id in t.rooms.room_ids():
		if t.rooms.kind_of(id) == kind:
			return id
	return -1


## n children counted as inside the tower (on a long trip), each registered as a child. Returns their ids.
static func _children(t: TowerSim, n: int, minutes: int = 600) -> Array[int]:
	var ids: Array[int] = []
	for k in n:
		var id := t.people.add_person(People.NONE, People.NONE, t.rng)
		t.people.start_trip(t.people.index_of(id), minutes)
		t.life._kids.append(id)
		ids.append(id)
	return ids


static func _serve(t: TowerSim, kind: String, day: int, minute: int) -> void:
	t.commerce._serve(kind, Commerce.SCHOOL_WINDOW, 100, t.floors, t.rooms, t.grid, t.people, t.tenancy, t.rng, day, minute, t.life)


static func _odd(ids: Array[int]) -> int:
	var n := 0
	for id: int in ids:
		if id % 2 == 1:
			n += 1
	return n


static func run(check: Callable) -> void:
	# The row: 24 seats, star 3, $150,000, 16 wide.
	var row: Dictionary = Catalogue.row("school")
	check.call(int(row["cost"]) == 150000 and int(row["width"]) == 16 and Catalogue.star("school") == 3, "school: $150,000, 16 wide, unlocks at 3 stars")
	check.call(int(Commerce.PROFILES["school"]["seats"]) == 24 and Commerce.seats_per_meal("school", Commerce.SCHOOL_WINDOW) == 24, "school: 24 seats a visit row")
	check.call(Rooms.PLACEABLE.has("school") and Commerce.is_shop("school") and Names.TITLES.has("school"), "school: placeable, trades like a shop, has titles")
	check.call(Catalogue.cost("daycare") < Catalogue.cost("school") and Catalogue.star("school") > Catalogue.star("daycare"), "school: dearer and a star above the daycare")
	var rows := 0
	for meal: Array in Commerce.MEALS:
		if meal[3] == "school":
			rows += 1
			check.call(meal[1] == 45 and meal[2] == 70 and (meal[0] == 495 or meal[0] == 915), "school: drop-off 08:15 and pick-up 15:15, 45 minute window, 70 percent")
	check.call(rows == 2, "school: two visit rows")
	check.call(int(Commerce.PROFILES["school"]["linger_minutes"]) == 360 and bool(Commerce.PROFILES["school"]["weekdays"]), "school: six hour stay, weekdays only")
	check.call(Catalogue.IDS.find("school") == Catalogue.IDS.size() - 1, "school: appended to the ids, so existing saves keep their numbering")

	# Who: children only; weekdays only; school-age (odd id) children only; 24 seats a row.
	var t := _tower()
	var school := _room(t, "school")
	check.call(school >= 0, "school: placed")
	for k in 6:
		t.people.start_trip(t.people.index_of(t.people.add_person(People.NONE, People.NONE, t.rng)), 600)
	_serve(t, "school", Clock.WD1, Commerce.SCHOOL_DROP_OFF)
	check.call(t.commerce.customers_today(school) == 0, "school: adults are not taken in")
	var kids := _children(t, 60)
	_serve(t, "school", Clock.WE, Commerce.SCHOOL_DROP_OFF)
	check.call(t.commerce.customers_today(school) == 0, "school: closed at the weekend")
	_serve(t, "school", Clock.WD2, Commerce.SCHOOL_DROP_OFF)
	check.call(_odd(kids) >= 24 and t.commerce.customers_today(school) == 24, "school: 60 children (%d of school age) fill its 24 seats (%d)" % [_odd(kids), t.commerce.customers_today(school)])
	_serve(t, "school", Clock.WD2, Commerce.SCHOOL_PICK_UP)
	check.call(t.commerce.customers_today(school) == 48, "school: the pick-up row seats 24 more visits (%d)" % t.commerce.customers_today(school))

	# A few children: only the odd ids come.
	var few := _tower()
	var few_ids := _children(few, 10)
	_serve(few, "school", Clock.WD1, Commerce.SCHOOL_DROP_OFF)
	check.call(few.commerce.customers_today(_room(few, "school")) == _odd(few_ids), "school: only the school-age children of 10 come (%d)" % few.commerce.customers_today(_room(few, "school")))

	# The daycare keeps the even ids while a school stands, and every child without one.
	var d := _tower(true)
	var daycare := _room(d, "daycare")
	var d_kids := _children(d, 20)
	d.commerce._serve("daycare", 60, 100, d.floors, d.rooms, d.grid, d.people, d.tenancy, d.rng, Clock.WD1, 480, d.life)
	check.call(d.commerce.customers_today(daycare) == d_kids.size() - _odd(d_kids), "daycare: with a school it takes only the even ids (%d)" % d.commerce.customers_today(daycare))
	check.call(not Commerce.school_age_split("daycare", 3, false), "daycare: without a school it takes every child")

	# Synergy: +14 condo demand within 10 floors, never past the cap of 20 (a daycare's 10 included).
	var run_condo := [8, 100, 8]
	var near_school := [["school", [12, 100, 16]]]
	check.call(Synergy.demand_percent(run_condo, near_school) == 14, "synergy: a school adds 14 to condo demand within 10 floors")
	check.call(Synergy.demand_percent(run_condo, [["school", [20, 100, 16]]]) == 0, "synergy: a school 12 floors away adds nothing")
	check.call(Synergy.demand_percent(run_condo, near_school + [["daycare", [9, 100, 12]]]) == 20, "synergy: school and daycare stop at the cap of 20")

	# A fixed-seed day: children inside attend, the day settles, and a second run agrees.
	var a := _tower()
	var b := _tower()
	for tower: TowerSim in [a, b]:
		_children(tower, 40, 1300)
		tower.clock.set_to_tick(0)
		for n in DAY_TICKS:
			tower.step()
	var sch := _room(a, "school")
	check.call(a.commerce.customers_last_day(sch) > 0, "school: a seeded day sees children attend (%d visits)" % a.commerce.customers_last_day(sch))
	check.call(a.state_hash() == b.state_hash(), "school: two runs of the seeded day agree")

	# Saves still load, with the school's day kept.
	var copy := TowerSim.new(1, 1)
	check.call(copy.load_state(a.save()) and copy.state_hash() == a.state_hash(), "school: a tower with a school survives save and load")
