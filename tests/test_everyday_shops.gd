extends RefCounted
## Everyday shops (#322, our own design): grocery and deli. Catalogue rows, who shops and when (the grocery serves
## residents only, the deli everyone), the income tiers, the no-grocery complaint, the mood synergy and the settled
## day. No reference values, so the numbers are the tunables posted on the issue.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Commerce := preload("res://scripts/sim/commerce.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const Names := preload("res://scripts/sim/names.gd")
const Clock := preload("res://scripts/sim/clock.gd")
const Rooms := preload("res://scripts/sim/rooms.gd")
const People := preload("res://scripts/sim/people.gd")
const Grades := preload("res://scripts/sim/grades.gd")
const Synergy := preload("res://scripts/sim/synergy.gd")
const Complaints := preload("res://scripts/sim/complaints.gd")
const TestNewKinds := preload("res://tests/test_new_kinds.gd")

const KINDS: Array[String] = ["grocery", "deli"]


## Lobby on floors 1-2 (columns 100-299) and floor 3 above it: a grocery (if asked) at 100, a deli, then the condos,
## joined to the lobby by stairs.
static func _tower(condos: int, with_grocery: bool) -> TowerSim:
	var t := TowerSim.new(42, 100000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 299, 2)
	t.floors.fill_span(3, 100, 299)
	var x := 100
	var kinds: Array[String] = []
	if with_grocery:
		kinds.append("grocery")
	kinds.append("deli")
	for k in condos:
		kinds.append("condo")
	for kind: String in kinds:
		var refusal := t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find(kind), 3, x)
		assert(refusal == 0, "%s places, refusal %d" % [kind, refusal])
		x += int(Catalogue.field(kind, "width"))
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 1, 100)
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 2, 104)
	return t


## n people inside the tower, each living in the given room (or nowhere for NONE).
static func _inside_at(t: TowerSim, n: int, home: int) -> void:
	for k in n:
		var id := t.people.add_person(home, People.NONE, t.rng)
		t.people.start_trip(t.people.index_of(id), 600)


static func _serve(t: TowerSim, kind: String, window: int) -> void:
	t.commerce._serve(kind, window, 100, t.floors, t.rooms, t.grid, t.people, t.tenancy, t.rng, Clock.WD1, 600, t.life)


static func run(check: Callable) -> void:
	check.call(Catalogue.IDS.find("grocery") >= 0 and Catalogue.IDS.find("deli") == Catalogue.IDS.find("grocery") + 1, "everyday: grocery and deli are in the catalogue")
	for kind: String in KINDS:
		var row: Dictionary = Catalogue.row(kind)
		check.call(not row.is_empty() and int(row["staff"]) >= 1 and int(row["cost"]) > 0 and int(row["width"]) >= 8, "%s: has cost, width and staff" % kind)
		check.call(Rooms.PLACEABLE.has(kind), "%s is placeable" % kind)
		check.call(Commerce.is_shop(kind) and Commerce.has_sales(kind), "%s trades like a shop and sells for its own income" % kind)
		check.call(Names.TITLES.has(kind) and (Names.TITLES[kind] as Array).size() == 3, "%s has job titles for three age bands" % kind)
		check.call(Commerce.food_of(kind, 0) != Commerce.food_of(kind, 1), "%s has several goods" % kind)
		check.call(Commerce.income_for(kind, 0) < 0 and Commerce.income_for(kind, int(Commerce.PROFILES[kind]["grade_cap"])) > 0, "%s: empty loses money, full earns" % kind)
	check.call(Catalogue.star("grocery") == 2 and Catalogue.star("deli") == 1, "everyday: the grocery is a star-2 kind, the deli star 1")
	check.call(Catalogue.field("grocery", "width") > Catalogue.field("deli", "width") and Catalogue.cost("grocery") > Catalogue.cost("deli"), "everyday: the grocery is wider and dearer than the deli")
	check.call(Commerce.income_for("grocery", 0) == -3000 and Commerce.income_for("deli", 0) == -1000, "everyday: an empty day loses the wages of 3 and 1 staff at $1,000")

	# Hours: the deli is open early and late, the grocery morning and after work.
	var deli_waves: Array[int] = []
	var grocery_waves: Array[int] = []
	var grocery_inside_day := true
	for meal: Array in Commerce.MEALS:
		if meal[3] == "deli":
			deli_waves.append(meal[0])
		if meal[3] == "grocery":
			grocery_waves.append(meal[0])
			grocery_inside_day = grocery_inside_day and meal[0] >= 360 and meal[0] + meal[1] <= 1320
	check.call(deli_waves == [390, 630, 900, 1320], "deli: waves at 06:30, 10:30, 15:00 and 22:00 (%s)" % str(deli_waves))
	check.call(grocery_waves == [480, 1050], "grocery: waves at 08:00 and 17:30 (%s)" % str(grocery_waves))
	check.call(grocery_inside_day, "grocery: closed overnight")
	check.call(Commerce.visitors_for("grocery", 5, Clock.WD1) == 0 and Commerce.visitors_for("deli", 5, Clock.WD1) == 0, "everyday: no outside visitors (these shops are for the tower's own people)")

	# Residents only: of 40 people, 25 live in a condo and 15 live nowhere; only the 25 shop at the grocery.
	var t := _tower(2, true)
	var grocery := TestNewKinds._room(t, "grocery")
	var deli := TestNewKinds._room(t, "deli")
	var condo := TestNewKinds._room(t, "condo")
	check.call(grocery >= 0 and deli >= 0 and condo >= 0, "everyday: grocery, deli and condo are placed")
	_inside_at(t, 25, condo)
	_inside_at(t, 15, People.NONE)
	_serve(t, "grocery", Commerce.GROCERY_EVENING_WINDOW)
	check.call(t.commerce.customers_today(grocery) == 25, "grocery: the 25 residents shop, the 15 others do not (%d)" % t.commerce.customers_today(grocery))
	_serve(t, "deli", Commerce.DELI_LATE_WINDOW)
	check.call(t.commerce.customers_today(deli) == 40, "deli: all 40 people stop by, residents and workers alike (%d)" % t.commerce.customers_today(deli))
	check.call(t.commerce.customers_today(grocery) == 25, "deli: serves only the deli")
	check.call(Commerce.seats_per_meal("grocery", Commerce.GROCERY_MORNING_WINDOW) == 120 and Commerce.seats_per_meal("deli", Commerce.DELI_BREAK_WINDOW) == 30, "everyday: seats per wave come from places, window and stay")

	# The complaint: ten condos and no grocery complains; a grocery clears it; nine condos are too few.
	var big := _tower(10, false)
	check.call(big.complaint_reasons(TestNewKinds._room(big, "condo")).has(Complaints.NO_GROCERY), "complaints: ten condos and no grocery is a complaint")
	check.call(Complaints.label(Complaints.NO_GROCERY) != "", "complaints: the missing grocery has words")
	var fed := _tower(10, true)
	check.call(not fed.complaint_reasons(TestNewKinds._room(fed, "condo")).has(Complaints.NO_GROCERY), "complaints: a grocery in the tower clears it")
	var small := _tower(9, false)
	check.call(not small.complaint_reasons(TestNewKinds._room(small, "condo")).has(Complaints.NO_GROCERY), "complaints: nine condos are too few to want one")
	check.call(not big.complaint_reasons(TestNewKinds._room(big, "deli")).has(Complaints.NO_GROCERY), "complaints: only condos complain")

	# The synergy: a grocery within six floors lifts a condo's mood by 3; none, no change.
	var near := Synergy.mood_delta("condo", t.grid.run_of(condo), Synergy.others_of(t.grid, t.rooms))
	check.call(near == 3, "grocery: a condo next to it gains 3 mood (%d)" % near)
	var bare := _tower(2, false)
	var bare_delta := Synergy.mood_delta("condo", bare.grid.run_of(TestNewKinds._room(bare, "condo")), Synergy.others_of(bare.grid, bare.rooms))
	check.call(bare_delta == 0, "grocery: no grocery, no lift (%d)" % bare_delta)

	# The settled day: 25 customers is a B (A needs 30), and a new day starts from zero.
	t.commerce._settle(t.floors, t.rooms, t.grid, t.tenancy, t.ledger, t.messages, 0)
	check.call(t.commerce.customers_last_day(grocery) == 25 and t.commerce.grade(t.rooms, grocery) == Grades.GRADE_B, "grocery: 25 customers settle as a B")
	check.call(t.commerce.customers_last_day(deli) == 40 and t.commerce.grade(t.rooms, deli) == Grades.GRADE_A, "deli: 40 customers settle as an A")
	check.call(t.commerce.customers_today(grocery) == 0, "everyday: a settled day starts a new count")
	check.call(Commerce.valid_ints(t.commerce.state_ints()), "everyday: the saved state still validates")
