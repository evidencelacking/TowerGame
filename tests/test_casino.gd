extends RefCounted
## The casino (#319): one per tower, open from the evening to the early morning, takings from seeded bets with a
## house edge, a lift for hotels and a harm to the offices and condos near it, and an incident now and then when
## the tower has no security office. Our own design: every number is an unverified tunable.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Commerce := preload("res://scripts/sim/commerce.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const Rooms := preload("res://scripts/sim/rooms.gd")
const Synergy := preload("res://scripts/sim/synergy.gd")
const Clock := preload("res://scripts/sim/clock.gd")
const Names := preload("res://scripts/sim/names.gd")
const Messages := preload("res://scripts/sim/messages.gd")
const SimRng := preload("res://scripts/sim/sim_rng.gd")
const Ghost := preload("res://scripts/view/placement_ghost.gd")
const ToolbarScript := preload("res://scripts/view/toolbar.gd")
const TestNewKinds := preload("res://tests/test_new_kinds.gd")


## Lobby on floors 1-2 (columns 100-163), floor 3 above it with the casino at 120 (40 wide) and stairs from the
## lobby up to floor 3 at 100 and 104, so the casino is reachable.
static func _tower() -> TowerSim:
	var t := TowerSim.new(42, 100000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	t.floors.fill_span(3, 100, 163)
	var refusal := _put(t, "casino", 3, 124)
	assert(refusal == 0, "the casino places, refusal %d" % refusal)
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 1, 100)
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 2, 104)
	return t


static func _put(t: TowerSim, kind: String, floor_number: int, x: int) -> int:
	return t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find(kind), floor_number, x)


static func _serve(t: TowerSim, minute: int, day: int) -> void:
	t.commerce._serve("casino", 240, 100, t.floors, t.rooms, t.grid, t.people, t.tenancy, t.rng, day, minute, t.life)


static func _settle(t: TowerSim) -> void:
	t.commerce._settle(t.floors, t.rooms, t.grid, t.tenancy, t.ledger, t.messages, t.tick, t.rng)


static func _incidents(t: TowerSim) -> int:
	var count := 0
	for i in t.messages.count():
		if t.messages.entry(i)[1] == Messages.CASINO_INCIDENT:
			count += 1
	return count


static func run(check: Callable) -> void:
	var row: Dictionary = Catalogue.row("casino")
	check.call(Catalogue.star("casino") == 4 and int(row["width"]) == 40 and int(row["cost"]) == 1200000 and int(row["staff"]) == 6, "casino: star 4, 40 wide, $1,200,000, 6 staff")
	check.call(Rooms.PLACEABLE.has("casino") and Commerce.is_shop("casino") and Commerce.has_sales("casino"), "casino: placeable and trades like a shop")
	check.call(Names.TITLES.has("casino") and (Names.TITLES["casino"] as Array).size() == 3, "casino: job titles for three age bands")
	check.call(Ghost.ROOM_TEXT.has(Rooms.ONE_CASINO) and Rooms.ONE_CASINO != Rooms.ONE_DECK and Rooms.ONE_CASINO != Rooms.NOT_TOP, "casino: its own refusal and ghost words")
	check.call(ToolbarScript.item_state("casino", 3)["locked"] and not ToolbarScript.item_state("casino", 4)["locked"], "casino: locked before star 4, open at star 4")

	# Opening hours: an evening wave from 20:00 and a late wave from midnight to 05:00, nothing by day.
	var waves: Array[int] = []
	var windows: Array[int] = []
	for meal: Array in Commerce.MEALS:
		if meal[3] == "casino":
			waves.append(meal[0])
			windows.append(meal[1])
	check.call(waves == [1200, 0] and windows == [240, 300], "casino: waves at 20:00 and midnight, open until 05:00 (%s, %s)" % [str(waves), str(windows)])
	check.call(Commerce.city_visitors_for("casino", 5, Clock.WD1) > 0 and Commerce.city_visitors_for("casino", 6, Clock.WE) > Commerce.city_visitors_for("casino", 6, Clock.WD1) and Commerce.city_visitors_for("casino", 3, Clock.WE) == 0, "casino: the city comes after dark, more at the weekend, never by day")

	# One per tower.
	var t := _tower()
	var second := t.rooms.check_place(t.grid, t.floors, "casino", 3, 110)
	check.call(second["reason"] == Rooms.ONE_CASINO, "casino: a second casino is refused (%d)" % second["reason"])
	var casino := TestNewKinds._room(t, "casino")

	# Gamblers: adults who are inside come; the takings are the seeded bets less the wages.
	TestNewKinds._inside(t, 60, 90)
	_serve(t, 1200, Clock.WD1)
	var came := t.commerce.customers_today(casino)
	check.call(came >= 60, "casino: the 60 people inside come, and the city's visitors (%d)" % came)
	var seeded_a := Commerce.casino_takings(200, SimRng.new(7))
	var seeded_b := Commerce.casino_takings(200, SimRng.new(7))
	check.call(seeded_a == seeded_b, "casino: the same seed gives the same night (%d)" % seeded_a)
	check.call(Commerce.casino_takings(0, SimRng.new(7)) == -Commerce.CASINO_WAGE, "casino: an empty night loses the wages")
	var edge := Commerce.casino_takings(5000, SimRng.new(3)) + Commerce.CASINO_WAGE
	check.call(edge > 0 and edge < 5000 * Commerce.CASINO_STAKE, "casino: over a long run the house keeps part of the stakes (%d)" % edge)
	check.call(Commerce.casino_takings(100, null) == 100 * 40 - Commerce.CASINO_WAGE, "casino: the bare expectation is 10 percent of the stakes")
	var balance := t.ledger.balance
	_settle(t)
	check.call(t.ledger.balance != balance, "casino: settlement credits the bets' result")

	# Incidents: with no security office on the tower, some nights go wrong; with one, none do.
	var bare := _tower()
	var guarded := _tower()
	var office := _put(guarded, "security", 3, 108)
	check.call(office == Rooms.OK, "casino: a security office places beside it (%d)" % office)
	for tower: TowerSim in [bare, guarded]:
		for night in 60:
			TestNewKinds._inside(tower, 10, 90)
			_serve(tower, 1200, Clock.WD1)
			_settle(tower)
	check.call(_incidents(bare) > 0 and _incidents(guarded) == 0, "casino: incidents only without security (%d, %d)" % [_incidents(bare), _incidents(guarded)])

	# Neighbours: condos and offices lose mood within 3 floors, hotels gain within 10.
	var sources := Synergy.others_of(t.grid, t.rooms)
	check.call(Synergy.mood_delta("condo", [4, 120, 16], sources) == -5 and Synergy.mood_delta("condo", [30, 120, 16], sources) == 0, "casino: -5 mood for a condo within 3 floors only")
	check.call(Synergy.mood_delta("office", [5, 120, 9], sources) == -3 and Synergy.mood_delta("hotel_twin", [10, 120, 4], sources) == 2, "casino: -3 mood for offices nearby, +2 for hotels within 10 floors")
	var texts: Array[String] = []
	for entry: Dictionary in Synergy.preview("casino", [3, 120, 40], [["condo", [4, 120, 16]], ["hotel_suite", [6, 120, 8]]]):
		texts.append(Synergy.text_of(entry))
	check.call(texts.has("-5 mood on 1 Condo") and texts.has("+2 mood on 1 %s" % Catalogue.display_name("hotel_suite")), "casino: the ghost shows the harm and the lift (%s)" % str(texts))

	# Save and load, and a day replays the same.
	var copy := TowerSim.new(1, 1)
	check.call(copy.load_state(t.save()) and copy.state_hash() == t.state_hash(), "casino: a tower with a casino survives save and load")
	var a := _tower()
	var b := _tower()
	for tower: TowerSim in [a, b]:
		TestNewKinds._inside(tower, 40, 60)
		tower.clock.set_to_tick(0)
		for n in 2550:
			tower.step()
	check.call(a.state_hash() == b.state_hash(), "casino: two runs of a day with a casino agree")
