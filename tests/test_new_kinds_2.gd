extends RefCounted
## New room kinds, batch 2 (M13, #292): nightclub and co-working. Catalogue rows, who visits and when (adults
## only; the club in two waves around midnight, co-working in three morning waves on weekdays), the income
## tiers, the club's noise and its synergy on a condo next door, job titles, and save and load.
## Our own kinds: no reference values.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Commerce := preload("res://scripts/sim/commerce.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const Names := preload("res://scripts/sim/names.gd")
const Clock := preload("res://scripts/sim/clock.gd")
const Rooms := preload("res://scripts/sim/rooms.gd")
const NoiseScript := preload("res://scripts/sim/noise.gd")
const Synergy := preload("res://scripts/sim/synergy.gd")
const TestNewKinds := preload("res://tests/test_new_kinds.gd")
const TestEvaluation := preload("res://tests/test_evaluation.gd")

const KINDS: Array[String] = ["nightclub", "coworking"]


## Lobby on floors 1-2 (columns 100-163) and floor 3 above it: the nightclub at 100, a condo touching it at 124
## and co-working at 140, joined to the lobby by stairs so every room is reachable.
static func _tower() -> TowerSim:
	var t := TowerSim.new(42, 100000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	t.floors.fill_span(3, 100, 163)
	var x := 100
	for kind: String in ["nightclub", "condo", "coworking"]:
		var refusal := t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find(kind), 3, x)
		assert(refusal == 0, "%s places, refusal %d" % [kind, refusal])
		x += int(Catalogue.field(kind, "width"))
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 1, 100)
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 2, 104)
	return t


static func _serve(t: TowerSim, kind: String, day: int, window: int) -> void:
	t.commerce._serve(kind, window, 100, t.floors, t.rooms, t.grid, t.people, t.tenancy, t.rng, day, 600, t.life)


static func run(check: Callable) -> void:
	check.call(Catalogue.IDS.size() == 33 and Catalogue.IDS.find("nightclub") == 31 and Catalogue.IDS.find("coworking") == 32, "kinds 2: nightclub and co-working follow the clinic")
	for kind: String in KINDS:
		var row: Dictionary = Catalogue.row(kind)
		check.call(not row.is_empty() and int(row["staff"]) >= 2 and int(row["cost"]) > 0 and int(row["width"]) >= 8, "%s: has cost, width and staff" % kind)
		check.call(Rooms.PLACEABLE.has(kind), "%s is placeable" % kind)
		check.call(Commerce.is_shop(kind) and Commerce.has_sales(kind), "%s trades like a shop and sells for its own income" % kind)
		check.call(Names.TITLES.has(kind) and (Names.TITLES[kind] as Array).size() == 3, "%s has job titles for three age bands" % kind)
		check.call(Commerce.food_of(kind, 0) != Commerce.food_of(kind, 1), "%s has several services" % kind)
		check.call(Commerce.income_for(kind, 0) < 0 and Commerce.income_for(kind, int(Commerce.PROFILES[kind]["grade_cap"])) > 0, "%s: empty loses money, full earns" % kind)
	check.call(Catalogue.cost("nightclub") > Catalogue.cost("party_hall") and Catalogue.cost("coworking") > Catalogue.cost("office"), "kinds 2: the club costs more than the party hall, co-working more than an office")
	check.call(Catalogue.star("nightclub") == 4 and Catalogue.star("coworking") == 3, "kinds 2: stars 4 and 3")

	# Opening hours: the club's two waves cover 21:00 to 03:00; co-working has three morning waves.
	var club_waves: Array[int] = []
	var cowork_waves: Array[int] = []
	for meal: Array in Commerce.MEALS:
		if meal[3] == "nightclub":
			club_waves.append(meal[0])
			check.call(meal[1] == 180, "nightclub: each wave lasts 3 hours")
		if meal[3] == "coworking":
			cowork_waves.append(meal[0])
	check.call(club_waves == [21 * 60, 0], "nightclub: waves at 21:00 and midnight, open until 03:00 (%s)" % str(club_waves))
	check.call(cowork_waves == [450, 540, 630], "co-working: three waves, 07:30, 09:00 and 10:30 (%s)" % str(cowork_waves))
	check.call(Commerce.seats_per_meal("nightclub", 180) == 120 and Commerce.seats_per_meal("coworking", Commerce.COWORK_WINDOW) == 10, "kinds 2: seats per wave come from seats, window and linger")

	var t := _tower()
	var club := TestNewKinds._room(t, "nightclub")
	var cowork := TestNewKinds._room(t, "coworking")
	check.call(club >= 0 and cowork >= 0, "kinds 2: both are placed")

	# Nightclub: adults only, limited by its places (120 in a wave of 3 hours).
	var adults := TestNewKinds._inside(t, 50, 90)
	_serve(t, "nightclub", Clock.WE, 180)
	check.call(t.commerce.customers_today(club) == 50, "nightclub: 50 adults come at the weekend too (%d)" % t.commerce.customers_today(club))
	check.call(t.commerce.customers_today(cowork) == 0, "nightclub: serves nobody in the other room")
	for k in 20:
		t.life._kids.append(adults[k])
	_serve(t, "nightclub", Clock.WD1, 180)
	check.call(t.commerce.customers_today(club) == 50 + 30, "nightclub: the 20 children are turned away, 30 adults come (%d)" % t.commerce.customers_today(club))

	# Co-working: weekdays only, adults only, ten desks a wave. Of the 50 people 20 are children, so 30 adults.
	_serve(t, "coworking", Clock.WE, Commerce.COWORK_WINDOW)
	check.call(t.commerce.customers_today(cowork) == 0, "co-working: closed at the weekend")
	_serve(t, "coworking", Clock.WD1, Commerce.COWORK_WINDOW)
	check.call(t.commerce.customers_today(cowork) == 10, "co-working: 30 adults fill only the 10 desks of a wave (%d)" % t.commerce.customers_today(cowork))
	_serve(t, "coworking", Clock.WD1, Commerce.COWORK_WINDOW)
	_serve(t, "coworking", Clock.WD1, Commerce.COWORK_WINDOW)
	check.call(t.commerce.customers_today(cowork) == 30, "co-working: three waves fill its 30 desks (%d)" % t.commerce.customers_today(cowork))

	# The club's noise and its synergy reach the condo next door.
	var condo := TestNewKinds._room(t, "condo")
	check.call(NoiseScript.is_source("nightclub") and NoiseScript.noise_at(t.grid, t.rooms, condo) > 0, "nightclub: it makes noise next to a condo")
	var near := Synergy.mood_delta("condo", t.grid.run_of(condo), Synergy.others_of(t.grid, t.rooms))
	check.call(near == -6, "nightclub: the condo's neighbours factor is -6 (%d)" % near)
	var fresh := TowerSim.new(42, 100000000)
	check.call(Synergy.mood_delta("condo", [3, 124, 16], Synergy.others_of(fresh.grid, fresh.rooms)) == 0, "nightclub: no club, no harm")

	# The midnight wave belongs to the next day: the 23:00 settle credits the evening wave, then clears the count.
	var day := _tower()
	var day_club := TestNewKinds._room(day, "nightclub")
	TestNewKinds._inside(day, 40, 90)
	_serve(day, "nightclub", Clock.WD1, 180)
	check.call(day.commerce.customers_today(day_club) == 40, "nightclub: the evening wave serves 40")
	day.commerce._settle(day.floors, day.rooms, day.grid, day.tenancy, day.ledger, day.messages, 0)
	check.call(day.commerce.customers_last_day(day_club) == 40 and day.commerce.customers_today(day_club) == 0, "nightclub: the 23:00 settle credits the evening wave and starts a new day")
	_serve(day, "nightclub", Clock.WD2, 180)
	check.call(day.commerce.customers_today(day_club) == 40 and day.commerce.customers_last_day(day_club) == 40, "nightclub: the midnight wave counts toward the next day, not the one settled")

	# Through the real tick: a day with a nightclub next door lowers a condo resident's mood below the same day without.
	var moods: Array[int] = []
	for with_club: bool in [false, true]:
		var m := TestEvaluation._pair("condo")
		if with_club:
			m.floors.fill_span(3, 100, 170)
			var refusal := m.rooms.place_room(m.grid, m.floors, m.ledger, 0, Catalogue.IDS.find("nightclub"), 3, 140)
			assert(refusal == 0, "the club places beside the condos, refusal %d" % refusal)
		for i in m.people.count():
			m.people.set_mood(i, 100)
		m.clock.set_to_tick(0)
		for n in TestNewKinds.DAY_TICKS:
			m.step()
		moods.append(m.people.mood_of(0))
	check.call(moods[1] < moods[0], "nightclub: after a day the condo resident is less happy than without the club (%s)" % str(moods))

	# Save and load keep the day's counts, and the same state gives the same hash.
	var copy := TowerSim.new(1, 1)
	check.call(copy.load_state(t.save()) and copy.state_hash() == t.state_hash(), "kinds 2: a tower with the new rooms survives save and load")
	check.call(copy.commerce.customers_today(cowork) == 30, "kinds 2: co-working's customers survive save and load")

	# A whole day runs and replays the same.
	var a := _tower()
	var b := _tower()
	for tower: TowerSim in [a, b]:
		TestNewKinds._inside(tower, 30, 40)
		tower.clock.set_to_tick(0)
		for n in TestNewKinds.DAY_TICKS:
			tower.step()
	check.call(a.state_hash() == b.state_hash(), "kinds 2: two runs of a day with the new rooms agree")
