extends RefCounted
## New room kinds, batch 1 (M13, #291): gym, daycare and clinic. Catalogue rows, placement, who visits and
## when (a gym: anyone inside; a daycare: children, weekdays only; a clinic: people in a low mood), the
## seats, the daily income tiers, job titles, and save and load. Our own kinds: no reference values.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Commerce := preload("res://scripts/sim/commerce.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const Names := preload("res://scripts/sim/names.gd")
const Clock := preload("res://scripts/sim/clock.gd")
const Rooms := preload("res://scripts/sim/rooms.gd")
const People := preload("res://scripts/sim/people.gd")

const KINDS: Array[String] = ["gym", "daycare", "clinic"]
const DAY_TICKS := 2550


## Lobby on floors 1-2 (columns 100-163) and floor 3 above it with one room of each new kind, joined to the
## lobby by stairs so every room is reachable.
static func _tower() -> TowerSim:
	var t := TowerSim.new(42, 100000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	t.floors.fill_span(3, 100, 163)
	var x := 100
	for kind: String in KINDS:
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


## n people who count as inside the tower (on a trip), with the given mood. Returns their ids.
static func _inside(t: TowerSim, n: int, mood: int) -> Array[int]:
	var ids: Array[int] = []
	for k in n:
		var id := t.people.add_person(People.NONE, People.NONE, t.rng)
		var i := t.people.index_of(id)
		t.people.start_trip(i, 600)
		t.people.set_mood(i, mood)
		ids.append(id)
	return ids


## One 120 minute session of a kind in which everyone eligible tries to come (100 percent).
static func _serve(t: TowerSim, kind: String, day: int) -> void:
	t.commerce._serve(kind, 120, 100, t.floors, t.rooms, t.grid, t.people, t.tenancy, t.rng, day, 600, t.life)


static func run(check: Callable) -> void:
	# Catalogue rows: our own numbers, kept in a sensible order against the existing kinds.
	check.call(Catalogue.IDS.size() == 34 and Catalogue.IDS.find("gym") == 28 and Catalogue.IDS.find("daycare") == 29 and Catalogue.IDS.find("clinic") == 30, "kinds: gym, daycare and clinic follow the cathedral")
	for kind: String in KINDS:
		var row: Dictionary = Catalogue.row(kind)
		check.call(not row.is_empty() and int(row["staff"]) >= 3 and int(row["cost"]) > 0 and int(row["width"]) >= 8, "%s: has cost, width and staff" % kind)
		check.call(Rooms.PLACEABLE.has(kind), "%s is placeable" % kind)
		check.call(Commerce.is_shop(kind) and Commerce.has_sales(kind), "%s trades like a shop and sells for its own income" % kind)
		check.call(Names.TITLES.has(kind) and (Names.TITLES[kind] as Array).size() == 3, "%s has job titles for three age bands" % kind)
		check.call(Commerce.food_of(kind, 0) != Commerce.food_of(kind, 1), "%s has several services" % kind)
		check.call(Commerce.income_for(kind, 0) < 0 and Commerce.income_for(kind, int(Commerce.PROFILES[kind]["grade_cap"])) > 0, "%s: empty loses money, full earns" % kind)
	check.call(Catalogue.cost("daycare") < Catalogue.cost("gym") and Catalogue.cost("gym") < Catalogue.cost("clinic"), "kinds: daycare is cheapest, the clinic the dearest")
	check.call(Catalogue.cost("clinic") < Catalogue.cost("medical"), "kinds: the clinic is cheaper than a medical centre")
	check.call(Catalogue.star("gym") == 2 and Catalogue.star("daycare") == 2 and Catalogue.star("clinic") == 3, "kinds: stars 2, 2 and 3")
	check.call(Commerce.seats_per_meal("gym", 120) == 40 and Commerce.seats_per_meal("daycare", Commerce.DAYCARE_WINDOW) == 12 and Commerce.seats_per_meal("clinic", Commerce.CLINIC_WINDOW) == 36, "kinds: seats per session come from seats, window and linger")

	var t := _tower()
	var gym := _room(t, "gym")
	var daycare := _room(t, "daycare")
	var clinic := _room(t, "clinic")
	check.call(gym >= 0 and daycare >= 0 and clinic >= 0, "kinds: all three are placed")

	# Gym: anyone inside, limited by the machines.
	var adults := _inside(t, 50, 90)
	_serve(t, "gym", Clock.WD1)
	check.call(t.commerce.customers_today(gym) == 40, "gym: 50 people inside fill its 40 places (%d)" % t.commerce.customers_today(gym))
	check.call(t.commerce.customers_today(daycare) == 0 and t.commerce.customers_today(clinic) == 0, "gym: serves nobody in the other rooms")

	# Daycare: children only, weekdays only, twelve places.
	_serve(t, "daycare", Clock.WD1)
	check.call(t.commerce.customers_today(daycare) == 0, "daycare: adults are not taken in")
	for k in 8:
		t.life._kids.append(adults[k])
	_serve(t, "daycare", Clock.WE)
	check.call(t.commerce.customers_today(daycare) == 0, "daycare: closed at the weekend")
	_serve(t, "daycare", Clock.WD2)
	check.call(t.commerce.customers_today(daycare) == 8, "daycare: the 8 children come on a weekday (%d)" % t.commerce.customers_today(daycare))
	for id: int in _inside(t, 8, 90):
		t.life._kids.append(id)
	_serve(t, "daycare", Clock.WD1)
	check.call(t.commerce.customers_today(daycare) == 8 + 12, "daycare: 16 children fill only its 12 places (%d)" % t.commerce.customers_today(daycare))

	# Clinic: only people in a low mood.
	_serve(t, "clinic", Clock.WD1)
	check.call(t.commerce.customers_today(clinic) == 0, "clinic: nobody well comes")
	for k in 5:
		t.people.set_mood(t.people.index_of(adults[10 + k]), Commerce.CLINIC_MOOD_BELOW - 1)
	_serve(t, "clinic", Clock.WE)
	check.call(t.commerce.customers_today(clinic) == 5, "clinic: the 5 unwell visit, weekends too (%d)" % t.commerce.customers_today(clinic))

	# Save and load keep the day's counts, and the same state gives the same hash.
	var copy := TowerSim.new(1, 1)
	check.call(copy.load_state(t.save()) and copy.state_hash() == t.state_hash(), "kinds: a tower with the new rooms survives save and load")
	check.call(copy.commerce.customers_today(gym) == 40, "kinds: the gym's customers survive save and load")

	# A whole day runs and replays the same.
	var a := _tower()
	var b := _tower()
	for tower: TowerSim in [a, b]:
		_inside(tower, 30, 40)
		tower.clock.set_to_tick(0)
		for n in DAY_TICKS:
			tower.step()
	check.call(a.state_hash() == b.state_hash(), "kinds: two runs of a day with the new rooms agree")
