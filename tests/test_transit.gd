extends RefCounted
## The metro station (M13, #325): a single basement floor, one per tower, from star 3. Placement and its refusals,
## the link check (a station nobody can reach does nothing), the visitors it sends to shops, the office rent and
## condo price bonus of a connected tower, and that a day with a station replays the same. Our own design: every
## number is an unverified tunable.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Commerce := preload("res://scripts/sim/commerce.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const Rooms := preload("res://scripts/sim/rooms.gd")
const Synergy := preload("res://scripts/sim/synergy.gd")
const Clock := preload("res://scripts/sim/clock.gd")
const TestNewKinds := preload("res://tests/test_new_kinds.gd")
const TestEvaluation := preload("res://tests/test_evaluation.gd")
const Ghost := preload("res://scripts/view/placement_ghost.gd")
const ToolbarScript := preload("res://scripts/view/toolbar.gd")
const TestCondos := preload("res://tests/test_condos.gd")
const TestTenancy := preload("res://tests/test_tenancy.gd")
const Ledger := preload("res://scripts/sim/ledger.gd")

const DAY_TICKS := 2550


## Lobby on floors 1-2 (columns 100-163), a fast food shop on floor 3 reached by stairs. The station is placed
## by the caller.
static func _tower() -> TowerSim:
	var t := TowerSim.new(42, 100000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	t.floors.fill_span(3, 100, 163)
	var refusal := t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("fast_food"), 3, 100)
	assert(refusal == 0, "the shop places, refusal %d" % refusal)
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 1, 100)
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 2, 104)
	return t


static func _station(t: TowerSim, floor_number: int, x: int) -> int:
	return t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("metro"), floor_number, x)


## Stairs from the lobby floor down to B1 where the station sits.
static func _link(t: TowerSim, x: int) -> void:
	var refusal := t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, -1, x)
	assert(refusal == 0, "the stairs down to the station place, refusal %d" % refusal)


static func run(check: Callable) -> void:
	check.call(Catalogue.star("metro") == 3 and Catalogue.cost("metro") == 1000000 and Catalogue.field("metro", "width") == 32 and Catalogue.field("metro", "height") == 1, "metro: star 3, $1,000,000, one basement floor 32 wide")
	check.call(Rooms.PLACEABLE.has("metro") and not Catalogue.field("metro", "removable") and Catalogue.field("metro", "limit") == 1, "metro: placeable, permanent, one per tower")
	check.call(Ghost.ROOM_TEXT.has(Rooms.ONE_STATION), "metro: the ghost has words for a second station")

	# Placement: basements only, one per tower.
	var t := _tower()
	var above := t.rooms.check_place(t.grid, t.floors, "metro", 3, 120)
	check.call(above["reason"] == Rooms.NOT_BASEMENT, "metro: refused above ground (%d)" % above["reason"])
	var first := _station(t, -1, 100)
	check.call(first == Rooms.OK, "metro: the station places on B1 (refusal %d)" % first)
	var second := t.rooms.check_place(t.grid, t.floors, "metro", -1, 140)
	check.call(second["reason"] == Rooms.ONE_STATION, "metro: a second station is refused (%d)" % second["reason"])
	check.call(t.star_facts()["metro"] == 1, "metro: it still counts toward star 5's station requirement")

	# Linked or not: with no way down from the lobby the station does nothing.
	check.call(not t.tenancy.transit_linked(t.floors, t.rooms, t.grid), "metro: a station nobody can reach is not linked")
	check.call(Synergy.others_of(t.grid, t.rooms, false).is_empty() and Synergy.others_of(t.grid, t.rooms, true).size() == 1, "metro: an unlinked station is left out of the synergies")
	_link(t, 100)
	check.call(t.tenancy.transit_linked(t.floors, t.rooms, t.grid), "metro: stairs from the lobby link it")

	# Bonuses, pure: offices rent for 15 percent more, condos sell for 10 percent more; both tower-wide.
	var others := Synergy.others_of(t.grid, t.rooms, true)
	check.call(Synergy.rent_percent(others) == 15 and Synergy.rent_percent([]) == 0, "metro: +15 percent office rent while linked")
	check.call(Synergy.demand_percent([3, 300, 16], others) == 10 and Synergy.demand_percent([60, 10, 16], others) == 10, "metro: +10 percent condo price on any floor")
	check.call(Synergy.demand_percent([3, 300, 16], others + [["daycare", [3, 300, 12]]]) == 20, "metro: it adds to a daycare's lift")
	var preview := Synergy.preview("metro", [-1, 100, 32], [["office", [3, 100, 9]], ["condo", [4, 100, 16]], ["office", [5, 100, 9]]])
	var texts: Array[String] = []
	for entry: Dictionary in preview:
		texts.append(Synergy.text_of(entry))
	check.call(texts.has("+15% rent on 2 Office") and texts.has("+10% sale price on 1 Condo"), "metro: the ghost shows both bonuses (%s)" % str(texts))

	# Rent: an office with workers pays 15 percent more with the bonus.
	var office := TestEvaluation._pair("office")
	var plain := office.rent.collect(office.rooms, office.people, office.ledger, 0, true, 0)
	var richer := office.rent.collect(office.rooms, office.people, office.ledger, 0, true, 15)
	check.call(plain > 0 and richer == plain + plain * 15 / 100, "metro: the rent collected is 15 percent higher with the bonus (%d, %d)" % [plain, richer])

	# Visitors: a linked station sends more people to the shop at lunch than none, and the extra is the table's.
	var period := Commerce.period_of_minute(720)
	var extra := Commerce.metro_visitors_for("fast_food", period, Clock.WD1)
	check.call(extra > 0 and Commerce.metro_visitors_for("gym", period, Clock.WD1) == 0 and Commerce.metro_visitors_for("fast_food", 0, Clock.WD1) == 0, "metro: it feeds fast food at lunch and not a gym (%d)" % extra)
	var counts: Array[int] = []
	for case_name: String in ["none", "unlinked", "linked"]:
		var s := _tower()
		if case_name != "none":
			_station(s, -1, 100)
		if case_name == "linked":
			_link(s, 100)
		var shop := TestNewKinds._room(s, "fast_food")
		s.commerce._serve("fast_food", 60, 0, s.floors, s.rooms, s.grid, s.people, s.tenancy, s.rng, Clock.WD1, 720, s.life)
		counts.append(s.commerce.customers_today(shop))
	var base := Commerce.visitors_for("fast_food", period, Clock.WD1)
	check.call(counts[0] == base and counts[1] == base and counts[2] == mini(base + extra, Commerce.seats_per_meal("fast_food", 60)), "metro: only a linked station adds visitors (%s, base %d, extra %d)" % [str(counts), base, extra])

	# The tower itself: the rent bonus follows a linked station, and a condo sells for 10 percent more in the tick.
	var plain_tower := _tower()
	var linked_tower := _tower()
	_station(plain_tower, -1, 100)
	_station(linked_tower, -1, 100)
	_link(linked_tower, 100)
	check.call(plain_tower.rent_bonus_percent() == 0 and linked_tower.rent_bonus_percent() == 15, "metro: the tower's rent bonus is 15 percent only with a linked station (%d, %d)" % [plain_tower.rent_bonus_percent(), linked_tower.rent_bonus_percent()])
	var prices: Array[int] = []
	for linked: bool in [false, true]:
		var s := TestCondos._tower()
		var station := _station(s, -1, 100)
		assert(station == 0, "the station places beside the condo tower, refusal %d" % station)
		if linked:
			_link(s, 100)
		TestTenancy._link(s)
		TestCondos._at(s, 10 * 60, 0)
		for line: Array in s.ledger.lines:
			if line[2] == Ledger.SALE:
				prices.append(line[1])
	check.call(prices == [Catalogue.cost("condo"), Catalogue.cost("condo") * 110 / 100], "metro: a condo sells for 10 percent more with a linked station (%s)" % str(prices))

	# The star gate: locked in the toolbar and the ghost at 2 stars, open at 3.
	check.call(ToolbarScript.item_state("metro", 2)["locked"] and not ToolbarScript.item_state("metro", 3)["locked"], "metro: locked at star 2, open at star 3")
	var locked_text: String = Ghost.evaluate(plain_tower, "metro", -1, 200, 2)["text"]
	var open_text: String = Ghost.evaluate(plain_tower, "metro", -1, 200, 3)["text"]
	check.call(locked_text != open_text, "metro: the ghost says the star gate at star 2 (%s)" % locked_text)

	# Save and load, and a whole day with a station replays the same.
	var copy := TowerSim.new(1, 1)
	check.call(copy.load_state(t.save()) and copy.state_hash() == t.state_hash(), "metro: a tower with a station survives save and load")
	var a := _tower()
	var b := _tower()
	for tower: TowerSim in [a, b]:
		_station(tower, -1, 100)
		_link(tower, 100)
		TestNewKinds._inside(tower, 30, 60)
		tower.clock.set_to_tick(0)
		for n in DAY_TICKS:
			tower.step()
	check.call(a.state_hash() == b.state_hash(), "metro: two runs of a day with a station agree")
