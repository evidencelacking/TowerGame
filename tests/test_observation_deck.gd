extends RefCounted
## The observation deck (#318): a landmark on the tower's top floor only. Placement and its refusals, closing
## when the tower grows past it, the visitors and admission it earns, and the reputation it spreads (mood for
## offices, condos and hotels, a lift for restaurants). Our own design: every number is an unverified tunable.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Commerce := preload("res://scripts/sim/commerce.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const Rooms := preload("res://scripts/sim/rooms.gd")
const Synergy := preload("res://scripts/sim/synergy.gd")
const Clock := preload("res://scripts/sim/clock.gd")
const Names := preload("res://scripts/sim/names.gd")
const Ghost := preload("res://scripts/view/placement_ghost.gd")
const ToolbarScript := preload("res://scripts/view/toolbar.gd")
const TestNewKinds := preload("res://tests/test_new_kinds.gd")


## Lobby on floors 1-2 (columns 100-163), floors 3 to 5 built above it, a fast food shop on floor 3 (column 140)
## and flights of stairs from the lobby up to floor 3. The deck and the rest are placed by the caller.
static func _tower() -> TowerSim:
	var t := TowerSim.new(42, 100000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	for floor_number in [3, 4, 5]:
		t.floors.fill_span(floor_number, 100, 163)
	var refusal := _put(t, "fast_food", 3, 140)
	assert(refusal == 0, "the shop places, refusal %d" % refusal)
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 1, 100)
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 2, 104)
	return t


static func _put(t: TowerSim, kind: String, floor_number: int, x: int) -> int:
	return t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find(kind), floor_number, x)


static func _serve(t: TowerSim, minute: int) -> void:
	t.refresh_reach()  # the tick does this before commerce runs; the shop test drives commerce by hand
	t.commerce._serve("observation_deck", 90, 100, t.floors, t.rooms, t.grid, t.people, t.tenancy, t.rng, Clock.WD1, minute, t.life)


static func run(check: Callable) -> void:
	var row: Dictionary = Catalogue.row("observation_deck")
	check.call(Catalogue.star("observation_deck") == 4 and int(row["width"]) == 32 and int(row["height"]) == 1 and int(row["cost"]) == 800000, "deck: star 4, 32 wide, one floor, $800,000")
	check.call(Rooms.PLACEABLE.has("observation_deck") and Commerce.is_shop("observation_deck") and Commerce.has_sales("observation_deck"), "deck: placeable and takes admission like a shop")
	check.call(Names.TITLES.has("observation_deck") and (Names.TITLES["observation_deck"] as Array).size() == 3, "deck: job titles for three age bands")
	check.call(Ghost.ROOM_TEXT.has(Rooms.NOT_TOP) and Ghost.ROOM_TEXT.has(Rooms.ONE_DECK) and String(Ghost.ROOM_TEXT[Rooms.NOT_TOP]).contains("top floor"), "deck: the ghost explains the top-floor rule")
	check.call(ToolbarScript.item_state("observation_deck", 3)["locked"] and not ToolbarScript.item_state("observation_deck", 4)["locked"], "deck: locked before star 4, open at star 4")
	check.call(Rooms.NOT_TOP != Rooms.ONE_STATION and Rooms.ONE_STATION != Rooms.BAD_SCHEDULE and Rooms.ONE_DECK != Rooms.NOT_TOP, "deck: its refusal codes are their own")

	# Placement: only where nothing is above, one per tower.
	var t := _tower()
	check.call(t.rooms.highest_room_floor(t.grid) == 3, "deck: the shop on floor 3 makes it the top (%d)" % t.rooms.highest_room_floor(t.grid))
	var upper := _put(t, "fast_food", 4, 116)
	check.call(upper == Rooms.OK, "deck: a shop on floor 4 places (%d)" % upper)
	var refused := t.rooms.check_place(t.grid, t.floors, "observation_deck", 3, 108)
	check.call(refused["reason"] == Rooms.NOT_TOP, "deck: refused on floor 3 with a room above it (%d)" % refused["reason"])
	var placed := _put(t, "observation_deck", 4, 132)
	check.call(placed == Rooms.OK, "deck: places on the top floor (%d)" % placed)
	var again := t.rooms.check_place(t.grid, t.floors, "observation_deck", 4, 100)
	check.call(again["reason"] == Rooms.ONE_DECK, "deck: a second deck is refused (%d)" % again["reason"])
	var deck := TestNewKinds._room(t, "observation_deck")
	check.call(deck >= 0 and not t.rooms.is_closed_up(t.grid, deck), "deck: open on the top floor")
	var ground := t.rooms.check_place(t.grid, t.floors, "observation_deck", -1, 120)
	check.call(ground["reason"] == Rooms.BELOW_GROUND, "deck: never below ground (%d)" % ground["reason"])

	# Reputation: while open it lifts mood tower-wide and restaurants and hotels near it.
	var sources := Synergy.others_of(t.grid, t.rooms)
	check.call(Synergy.mood_delta("office", [3, 300, 9], sources) == 2 and Synergy.mood_delta("condo", [80, 10, 16], sources) == 2, "deck: +2 mood for offices and condos anywhere")
	check.call(Synergy.mood_delta("hotel_single", [8, 300, 4], sources) == 3 and Synergy.mood_delta("hotel_single", [30, 300, 4], sources) == 0, "deck: +3 mood for hotels within 10 floors only")
	check.call(Synergy.sales_percent("restaurant", [8, 300, 24], sources) == 10 and Synergy.sales_percent("restaurant", [40, 300, 24], sources) == 0, "deck: restaurants within 10 floors sell 10 percent more")
	var texts: Array[String] = []
	for entry: Dictionary in Synergy.preview("observation_deck", [4, 132, 32], [["restaurant", [2, 100, 24]], ["office", [3, 100, 9]]]):
		texts.append(Synergy.text_of(entry))
	check.call(texts.has("+10% sales on 1 Restaurant") and texts.has("+2 mood on 1 Office"), "deck: the ghost shows what it does for its neighbours (%s)" % str(texts))

	# Admission: reachable and open it takes everyone inside who wants to come, and visitors from the city.
	TestNewKinds._inside(t, 40, 90)
	_serve(t, 1110)
	check.call(t.commerce.customers_today(deck) == 0, "deck: with no stairs up to floor 4 nobody can come")
	var stairs := t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 3, 108)
	check.call(stairs == Rooms.OK, "deck: stairs from floor 3 up to floor 4 place (%d)" % stairs)
	_serve(t, 1110)
	var open_count := t.commerce.customers_today(deck)
	check.call(open_count >= 40, "deck: once reachable, the 40 people inside and the visitors come (%d)" % open_count)
	var evening := Commerce.city_visitors_for("observation_deck", Commerce.period_of_minute(1110), Clock.WD1)
	var morning := Commerce.city_visitors_for("observation_deck", Commerce.period_of_minute(540), Clock.WD1)
	var weekend := Commerce.city_visitors_for("observation_deck", Commerce.period_of_minute(1110), Clock.WE)
	check.call(morning > 0 and evening > morning and weekend > evening, "deck: visitors come all day, more at sunset and at the weekend (%d, %d, %d)" % [morning, evening, weekend])
	var waves: Array[int] = []
	var percents: Array[int] = []
	for meal: Array in Commerce.MEALS:
		if meal[3] == "observation_deck":
			waves.append(meal[0])
			percents.append(meal[2])
	check.call(waves.size() == 5 and percents[3] > percents[0] and percents[4] > percents[0], "deck: five waves through the day, busiest at sunset and after dark (%s)" % str(percents))
	check.call(Commerce.income_for("observation_deck", 0) < 0 and Commerce.income_for("observation_deck", 40) > 0, "deck: an empty day loses the wages, a full one earns")

	# The tower grows past it: a room on floor 5 closes it, and it stops being a source or a shop.
	var grown := _put(t, "fast_food", 5, 100)
	check.call(grown == Rooms.OK, "deck: a room places above it (%d)" % grown)
	check.call(t.rooms.is_closed_up(t.grid, deck), "deck: closed once the tower grows past it")
	var closed_sources := 0
	for source: Array in Synergy.others_of(t.grid, t.rooms):
		if source[0] == "observation_deck":
			closed_sources += 1
	check.call(closed_sources == 0 and Synergy.mood_delta("office", [3, 300, 9], Synergy.others_of(t.grid, t.rooms)) == 0, "deck: a closed deck spreads no reputation")
	var before := t.commerce.customers_today(deck)
	_serve(t, 1110)
	check.call(t.commerce.customers_today(deck) == before, "deck: a closed deck takes no visitors")

	# Save and load keep a tower with a deck.
	var copy := TowerSim.new(1, 1)
	check.call(copy.load_state(t.save()) and copy.state_hash() == t.state_hash(), "deck: a tower with a deck survives save and load")

	# A day with a deck replays the same.
	var a := _tower()
	var b := _tower()
	for tower: TowerSim in [a, b]:
		assert(_put(tower, "fast_food", 4, 116) == Rooms.OK and _put(tower, "observation_deck", 4, 132) == Rooms.OK, "the deck tower builds")
		tower.rooms.place_stairs(tower.grid, tower.floors, tower.ledger, 0, 3, 108)
		TestNewKinds._inside(tower, 30, 60)
		tower.clock.set_to_tick(0)
		for n in 2550:
			tower.step()
	check.call(a.state_hash() == b.state_hash(), "deck: two runs of a day with a deck agree")
