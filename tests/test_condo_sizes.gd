extends RefCounted
## Condo sizes (#369): a studio (10 wide, 1 resident, $50,000), the standard condo (unchanged) and a penthouse
## (24 wide, 5 residents, $140,000, only above floor 20). Every place that treats a condo specially treats all three
## alike: sale and refund, grocery complaint, synergy, families, population. Our own design; every number a tunable.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const Rooms := preload("res://scripts/sim/rooms.gd")
const Names := preload("res://scripts/sim/names.gd")
const Grades := preload("res://scripts/sim/grades.gd")
const Rent := preload("res://scripts/sim/rent.gd")
const Complaints := preload("res://scripts/sim/complaints.gd")
const Synergy := preload("res://scripts/sim/synergy.gd")
const TestCondos := preload("res://tests/test_condos.gd")

const DAY_TICKS := 2550
const SIZES: Array[String] = ["studio", "condo", "penthouse"]
## state_hash of old_tower_hash() taken on main before the sizes existed: existing saves must play the same.
const OLD_TOWER_HASH := 2177821214623250566


static func _floor_of(kind: String) -> int:
	return 21 if kind == "penthouse" else 3


## A tower with one home of kind (on floor 3, or 21 for a penthouse), reached from the lobby by a chain of stairs.
static func _tower(kind: String) -> TowerSim:
	var t := TowerSim.new(7, 100000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	var top := _floor_of(kind)
	for f in range(3, top + 1):
		t.floors.fill_span(f, 100, 163)
	var refusal := t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find(kind), top, 110)
	assert(refusal == 0, "%s places" % kind)
	_link(t, top)
	return t


## A local shaft from the lobby to floor top at column 100 with one car, so a home on any floor is reachable.
static func _link(t: TowerSim, top: int) -> void:
	t.rooms.place_shaft(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("local_shaft"), 1, top, 100)
	t.rooms.add_car(t.ledger, 0, 3, t.rooms._shaft_base(t.rooms.link_at(1, 100)), 1)


static func _home(t: TowerSim) -> int:
	return t.rooms.room_ids()[0]


## The scenario the existing-save regression runs: standard condos only, a fixed seed, three days.
static func old_tower_hash() -> int:
	var t := TowerSim.new(42, 100000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	t.floors.fill_span(3, 100, 163)
	t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("condo"), 3, 110)
	t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("condo"), 3, 130)
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 1, 100)
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 2, 104)
	t.clock.set_to_tick(0)
	for n in 3 * DAY_TICKS:
		t.step()
	return t.state_hash()


static func run(check: Callable) -> void:
	# Catalogue: cost, width and residents per size; the condo is exactly what it was; the new kinds come last.
	var want := {"studio": [50000, 10, 1], "condo": [80000, 16, 3], "penthouse": [140000, 24, 5]}
	for kind: String in SIZES:
		var row: Dictionary = Catalogue.row(kind)
		check.call([int(row["cost"]), int(row["width"]), int(row["people"])] == want[kind], "%s: cost, width and residents" % kind)
		check.call(Rooms.PLACEABLE.has(kind) and Names.TITLES.has(kind) and Grades.is_graded(kind) and Catalogue.is_condo(kind), "%s: placeable, titled, graded and a condo size" % kind)
	check.call(Catalogue.IDS.find("condo") == 6 and Catalogue.IDS.find("apartment") == Catalogue.IDS.size() - 3, "ids: the condo keeps id 6 and the apartment stays where it was")
	check.call(Catalogue.IDS.find("studio") == Catalogue.IDS.size() - 2 and Catalogue.IDS.find("penthouse") == Catalogue.IDS.size() - 1, "ids: studio and penthouse are appended last")
	check.call(not Catalogue.is_condo("apartment") and not Catalogue.is_condo("office"), "is_condo: the three sizes only")

	# The penthouse floor rule: floors 3 and 20 refused, floor 21 allowed; studio and condo go low.
	var f := TowerSim.new(1, 100000000)
	f.floors.build_lobby(f.ledger, 0, 1, 100, 131, 2)
	for fl in range(3, 23):
		f.floors.fill_span(fl, 100, 131)
	check.call(f.rooms.check_place(f.grid, f.floors, "penthouse", 3, 100)["reason"] == Rooms.TOO_LOW, "penthouse: refused on floor 3")
	check.call(f.rooms.check_place(f.grid, f.floors, "penthouse", 20, 100)["reason"] == Rooms.TOO_LOW, "penthouse: refused on floor 20")
	check.call(f.rooms.check_place(f.grid, f.floors, "penthouse", 21, 100)["reason"] == Rooms.OK, "penthouse: allowed on floor 21")
	check.call(f.rooms.check_place(f.grid, f.floors, "studio", 3, 100)["reason"] == Rooms.OK and f.rooms.check_place(f.grid, f.floors, "condo", 3, 100)["reason"] == Rooms.OK, "studio and condo: allowed low")

	# Sale and refund per size.
	for kind: String in SIZES:
		var floor_n := _floor_of(kind)
		var price := Catalogue.cost(kind)
		var residents := int(Catalogue.row(kind)["people"])
		var t := _tower(kind)
		var home := _home(t)
		var funds := t.ledger.balance
		TestCondos._at(t, 10 * 60, 0)
		check.call(t.rooms.is_sold(home) and t.people.count() == residents, "%s: sells with exactly %d residents (%d)" % [kind, residents, t.people.count()])
		check.call(t.ledger.balance == funds + price, "%s: the sale credits its own price" % kind)
		check.call(not Rent.is_rentable(kind) and t.rent.set_rent(t.rooms, home, 1) == Rent.CONDO_LOCKED, "%s: rent is locked as for a condo" % kind)
		var before := t.ledger.balance
		check.call(t.rooms.check_bulldoze(t.grid, t.floors, floor_n, 110)["refund"] == price, "%s: bulldoze previews a refund of $%d" % [kind, price])
		t.rooms.bulldoze(t.grid, t.floors, t.ledger, t.tick, floor_n, 110)
		check.call(t.ledger.balance == before - price, "%s: bulldozing a sold home refunds $%d" % [kind, price])
		# The last resident leaving vacates the home and refunds its own price; it can then sell again.
		var v := _tower(kind)
		TestCondos._at(v, 10 * 60, 0)
		var vhome := _home(v)
		var cash := v.ledger.balance
		for i in range(v.people.count() - 1, -1, -1):
			v.people.remove_person(i)
		v.life._vacate_if_empty(v, vhome)
		check.call(not v.rooms.is_sold(vhome) and v.ledger.balance == cash - price, "%s: vacating refunds $%d" % [kind, price])
		TestCondos._at(v, 11 * 60, 0)
		check.call(v.rooms.is_sold(vhome) and v.ledger.balance == cash, "%s: vacate then resell nets zero" % kind)

	# Families: children fill free places up to the size's cap; a studio has none.
	var s := _tower("studio")
	TestCondos._at(s, 10 * 60, 0)
	s.life.child_percent = 100
	s.life.pair_up(0, 0)
	s.life.have_children(s)
	check.call(s.people.count() == 1 and s.life.story_count() == 0, "studio: one resident and never a child")
	var p := _tower("penthouse")
	TestCondos._at(p, 10 * 60, 0)
	p.life.pair_up(0, 1)
	p.life.child_percent = 100
	for n in 6:
		p.life.have_children(p)
	check.call(p.people.count() == 5, "penthouse: a couple and its children stop at 5 residents (%d)" % p.people.count())
	var c := _tower("condo")
	TestCondos._at(c, 10 * 60, 0)
	c.life.pair_up(0, 1)
	c.life.child_percent = 100
	for n in 6:
		c.life.have_children(c)
	check.call(c.people.count() == 3, "condo: a couple stops at 3 residents (%d)" % c.people.count())
	check.call(int(p.population_breakdown()["overall"]["residents"]) == 5, "penthouse: residents count in the population")

	# Grocery complaint: enough homes of any mix and no grocery complain; one fewer does not.
	for mix: Array in [["studio"], ["penthouse"], ["studio", "condo", "penthouse"]]:
		var g := TowerSim.new(3, 100000000)
		g.floors.build_lobby(g.ledger, 0, 1, 100, 163, 2)
		for fl in range(3, 30):
			g.floors.fill_span(fl, 100, 163)
		var n := 0
		var x := 100
		var row_floor := 21
		while n < Complaints.GROCERY_NEEDED_FROM:
			var kind: String = mix[n % mix.size()]
			if x + int(Catalogue.row(kind)["width"]) > 163:
				x = 100
				row_floor += 1
			g.rooms.place_room(g.grid, g.floors, g.ledger, 0, Catalogue.IDS.find(kind), row_floor, x)
			x += int(Catalogue.row(kind)["width"])
			n += 1
		var first: int = g.rooms.room_ids()[0]
		check.call(g.rooms.room_ids().size() == Complaints.GROCERY_NEEDED_FROM and g.complaint_reasons(first).has(Complaints.NO_GROCERY), "grocery: %s homes count towards the complaint" % str(mix))
		var at: Array[int] = g.grid.run_of(first)
		g.rooms.bulldoze(g.grid, g.floors, g.ledger, 0, at[0], at[1])
		check.call(not g.complaint_reasons(g.rooms.room_ids()[0]).has(Complaints.NO_GROCERY), "grocery: one home fewer is below the threshold %s" % str(mix))

	# Synergy: every size takes the condo's mood effects.
	var others: Array = [["daycare", [3, 112, 8]], ["pool", [3, 118, 8]]]
	var condo_mood := Synergy.mood_delta("condo", [3, 100, 16], others)
	check.call(condo_mood != 0 and Synergy.mood_delta("studio", [3, 100, 16], others) == condo_mood and Synergy.mood_delta("penthouse", [3, 100, 16], others) == condo_mood, "synergy: a studio and a penthouse take a condo's mood effects")

	# Existing saves: a tower of standard condos plays out exactly as it did before the sizes existed.
	var hash_now := old_tower_hash()
	check.call(OLD_TOWER_HASH != 0 and hash_now == OLD_TOWER_HASH, "regression: an old tower with standard condos keeps its state_hash (%d)" % hash_now)

	# A fixed-seed run with every size: two runs agree, and the tower saves and loads.
	var runs: Array[TowerSim] = []
	for k in 2:
		var t := TowerSim.new(11, 100000000)
		t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
		for fl in range(3, 22):
			t.floors.fill_span(fl, 100, 163)
		t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("studio"), 3, 110)
		t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("condo"), 3, 124)
		t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("penthouse"), 21, 110)
		_link(t, 21)
		t.clock.set_to_tick(0)
		for n in 3 * DAY_TICKS:
			t.step()
		runs.append(t)
	check.call(runs[0].people.count() == 9 and runs[0].state_hash() == runs[1].state_hash(), "seeded run: all three sizes fill (%d residents) and two runs agree" % runs[0].people.count())
	var copy := TowerSim.new(1, 1)
	check.call(copy.load_state(runs[0].save()) and copy.state_hash() == runs[0].state_hash(), "save: a tower with all three sizes survives save and load")
	var pent: Array = runs[0].rooms.room_ids().filter(func(id: int) -> bool: return runs[0].rooms.kind_of(id) == "penthouse")
	check.call(pent.size() == 1 and copy.rooms.kind_of(pent[0]) == "penthouse" and copy.rooms.is_sold(pent[0]), "save: the penthouse and its sale come back")
