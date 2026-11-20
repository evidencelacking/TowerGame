extends RefCounted
## The restaurant family (#323, our own design): cafe, pizza, sushi, fine dining and bar. Catalogue rows, their hours
## and audiences (sushi, fine dining and the bar are for adults; fine dining also takes a share of the hotel guests),
## the income tiers, the variety bonus on their sales, the bar's noise and its effect on a condo next door.
## No reference values, so the numbers are the tunables posted on the issue.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Commerce := preload("res://scripts/sim/commerce.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const Names := preload("res://scripts/sim/names.gd")
const Clock := preload("res://scripts/sim/clock.gd")
const Rooms := preload("res://scripts/sim/rooms.gd")
const Synergy := preload("res://scripts/sim/synergy.gd")
const NoiseScript := preload("res://scripts/sim/noise.gd")
const TestNewKinds := preload("res://tests/test_new_kinds.gd")

const KINDS: Array[String] = ["cafe", "pizza", "sushi", "fine_dining", "bar"]


## Lobby on floors 1-2 (columns 100-299) and floor 3 above it holding the given kinds side by side from column 100,
## joined to the lobby by stairs.
static func _tower(kinds: Array[String]) -> TowerSim:
	var t := TowerSim.new(42, 100000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 299, 2)
	t.floors.fill_span(3, 100, 299)
	var x := 100
	for kind: String in kinds:
		var refusal := t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find(kind), 3, x)
		assert(refusal == 0, "%s places, refusal %d" % [kind, refusal])
		x += int(Catalogue.field(kind, "width"))
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 1, 100)
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 2, 104)
	return t


static func _serve(t: TowerSim, kind: String, window: int) -> void:
	t.commerce._serve(kind, window, 100, t.floors, t.rooms, t.grid, t.people, t.tenancy, t.rng, Clock.WD1, 600, t.life)


static func _waves(kind: String) -> Array[int]:
	var found: Array[int] = []
	for meal: Array in Commerce.MEALS:
		if meal[3] == kind:
			found.append(meal[0])
	return found


static func run(check: Callable) -> void:
	for kind: String in KINDS:
		var row: Dictionary = Catalogue.row(kind)
		check.call(not row.is_empty() and int(row["staff"]) >= 2 and int(row["cost"]) > 0 and int(row["width"]) >= 8, "%s: has cost, width and staff" % kind)
		check.call(Rooms.PLACEABLE.has(kind), "%s is placeable" % kind)
		check.call(Commerce.is_shop(kind) and Commerce.has_sales(kind), "%s trades like a shop and sells for its own income" % kind)
		check.call(Names.TITLES.has(kind) and (Names.TITLES[kind] as Array).size() == 3, "%s has job titles for three age bands" % kind)
		check.call(Commerce.food_of(kind, 0) != Commerce.food_of(kind, 1), "%s has several dishes" % kind)
		check.call(Commerce.income_for(kind, 0) < 0 and Commerce.income_for(kind, int(Commerce.PROFILES[kind]["grade_cap"])) > 0, "%s: empty loses money, full earns" % kind)
		check.call(not _waves(kind).is_empty(), "%s has opening hours" % kind)
	check.call(Catalogue.star("cafe") == 2 and Catalogue.star("pizza") == 2 and Catalogue.star("sushi") == 3 and Catalogue.star("bar") == 3 and Catalogue.star("fine_dining") == 4, "dining: stars 2, 2, 3, 3 and 4")
	check.call(Catalogue.cost("fine_dining") > Catalogue.cost("sushi") and Catalogue.cost("sushi") > Catalogue.cost("pizza") and Catalogue.cost("pizza") > Catalogue.cost("cafe"), "dining: fine dining costs more than sushi, pizza and the cafe, in that order")
	check.call(Commerce.income_for("fine_dining", 40) > Commerce.income_for("sushi", 45) and Commerce.income_for("sushi", 45) > Commerce.income_for("pizza", 55), "dining: a full fine dining room out-earns a full sushi bar, which out-earns pizza")

	# Hours.
	check.call(_waves("cafe") == [450, 630], "cafe: mornings only, 07:30 and 10:30 (%s)" % str(_waves("cafe")))
	check.call(_waves("pizza") == [720, 1080], "pizza: noon and 18:00 (%s)" % str(_waves("pizza")))
	check.call(_waves("sushi") == [720, 1140], "sushi: noon and 19:00 (%s)" % str(_waves("sushi")))
	check.call(_waves("fine_dining") == [1140], "fine dining: dinner only (%s)" % str(_waves("fine_dining")))
	check.call(_waves("bar") == [1080, 1260], "bar: 18:00 and 21:00 (%s)" % str(_waves("bar")))
	check.call(Commerce.seats_per_meal("fine_dining", Commerce.FINE_WINDOW) == 40 and Commerce.seats_per_meal("bar", Commerce.BAR_WINDOW) == 90, "dining: seats per wave come from places, window and stay")
	check.call(Commerce.city_visitors_for("fine_dining", 5, Clock.WE) > Commerce.city_visitors_for("fine_dining", 5, Clock.WD1) and Commerce.city_visitors_for("fine_dining", 3, Clock.WD1) == 0, "fine dining: city VIPs come on weekend evenings more than weekday ones, and not at midday")
	check.call(Commerce.visitors_for("cafe", 5, Clock.WD1) == 0 and Commerce.visitors_for("bar", 5, Clock.WD1) == 0, "dining: only fine dining draws city visitors")

	# Audiences: 40 inside, 15 of them children. The cafe and pizza take everyone, sushi, fine dining and the bar adults.
	var t := _tower(KINDS)
	var rooms: Dictionary = {}
	for kind: String in KINDS:
		rooms[kind] = TestNewKinds._room(t, kind)
		check.call(int(rooms[kind]) >= 0, "%s is placed" % kind)
	var inside := TestNewKinds._inside(t, 40, 90)
	for k in 15:
		t.life._kids.append(inside[k])
	_serve(t, "cafe", Commerce.CAFE_MORNING_WINDOW)
	check.call(t.commerce.customers_today(rooms["cafe"]) == 40, "cafe: takes everyone, the 90 minute wave seats 40 or more (%d)" % t.commerce.customers_today(rooms["cafe"]))
	_serve(t, "pizza", Commerce.PIZZA_LUNCH_WINDOW)
	check.call(t.commerce.customers_today(rooms["pizza"]) == 40, "pizza: families too, all 40 come (%d)" % t.commerce.customers_today(rooms["pizza"]))
	_serve(t, "sushi", Commerce.PIZZA_LUNCH_WINDOW)
	check.call(t.commerce.customers_today(rooms["sushi"]) == 25, "sushi: the 15 children are turned away, 25 adults come (%d)" % t.commerce.customers_today(rooms["sushi"]))
	_serve(t, "bar", Commerce.BAR_WINDOW)
	check.call(t.commerce.customers_today(rooms["bar"]) == 25, "bar: adults only (%d)" % t.commerce.customers_today(rooms["bar"]))
	_serve(t, "fine_dining", Commerce.FINE_WINDOW)
	check.call(t.commerce.customers_today(rooms["fine_dining"]) == 25, "fine dining: 25 adults dine, the children do not, and no VIPs at 10:00 (%d)" % t.commerce.customers_today(rooms["fine_dining"]))

	# Hotel guests: fine dining takes a share of them, not all (the restaurant takes every guest).
	check.call(Commerce.FINE_GUEST_PERCENT < Commerce.GUEST_PERCENT and Commerce.FINE_GUEST_PERCENT > 0, "fine dining: only a share of hotel guests dine there")
	check.call(Commerce._guest_percent("fine_dining") == Commerce.FINE_GUEST_PERCENT and Commerce._guest_percent("restaurant") == Commerce.GUEST_PERCENT and Commerce._guest_percent("casino") == Commerce.CASINO_GUEST_PERCENT, "dining: each kind has its own guest share")

	# Variety: each distinct kind of the family beyond the first adds 4 percent, capped at 16; the old kinds do not count.
	var none: Array[String] = []
	var cafes: Array[String] = ["cafe", "cafe", "cafe"]
	var two: Array[String] = ["cafe", "pizza"]
	var three: Array[String] = ["cafe", "pizza", "sushi"]
	var old_kinds: Array[String] = ["fast_food", "restaurant", "cafe"]
	check.call(Commerce.dining_mix_percent(_tower(none).rooms) == 0, "mix: no family kinds, no bonus")
	check.call(Commerce.dining_mix_percent(_tower(cafes).rooms) == 0, "mix: cafes and nothing else earn no bonus, however many")
	check.call(Commerce.dining_mix_percent(_tower(two).rooms) == 4, "mix: two kinds add 4 percent")
	check.call(Commerce.dining_mix_percent(_tower(three).rooms) == 8, "mix: three kinds add 8 percent")
	check.call(Commerce.dining_mix_percent(t.rooms) == 16, "mix: all five kinds reach the 16 percent cap")
	check.call(Commerce.dining_mix_percent(_tower(old_kinds).rooms) == 0, "mix: fast food and the restaurant are not part of the family")

	# The bar: loud and a poor neighbour for a condo within two floors (-3 mood); a cafe is a quiet one.
	var with_bar: Array[String] = ["bar", "condo"]
	var with_cafe: Array[String] = ["cafe", "condo"]
	var pub := _tower(with_bar)
	var condo := TestNewKinds._room(pub, "condo")
	check.call(NoiseScript.is_source("bar") and NoiseScript.noise_at(pub.grid, pub.rooms, condo) > 0, "bar: makes noise next to a condo")
	var near := Synergy.mood_delta("condo", pub.grid.run_of(condo), Synergy.others_of(pub.grid, pub.rooms))
	check.call(near == -3, "bar: a condo next door loses 3 mood (%d)" % near)
	var quiet := _tower(with_cafe)
	var quiet_delta := Synergy.mood_delta("condo", quiet.grid.run_of(TestNewKinds._room(quiet, "condo")), Synergy.others_of(quiet.grid, quiet.rooms))
	check.call(quiet_delta == 0, "cafe: a quiet neighbour, no mood change (%d)" % quiet_delta)

	# The settled day records the count and keeps the saved state valid.
	t.commerce._settle(t.floors, t.rooms, t.grid, t.tenancy, t.ledger, t.messages, 0)
	check.call(t.commerce.customers_last_day(rooms["pizza"]) == 40 and t.commerce.customers_today(rooms["pizza"]) == 0, "dining: settling records the day and starts a new count")
	check.call(Commerce.valid_ints(t.commerce.state_ints()), "dining: the saved state still validates")
