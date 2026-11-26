extends RefCounted
## Rooms no stairs, escalator or elevator reaches (#368): Tower.refresh_reach marks them in Rooms.cut_off, and a cut-off
## room earns nothing, books nothing, serves nothing and counts for nothing until a route reaches it. Kinds that
## need no route (parking, recycling) are never marked.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const Rooms := preload("res://scripts/sim/rooms.gd")
const Security := preload("res://scripts/sim/security.gd")
const PoolLife := preload("res://scripts/sim/pool_life.gd")
const Demands := preload("res://scripts/sim/demands.gd")
const Synergy := preload("res://scripts/sim/synergy.gd")
const RoomLook := preload("res://scripts/view/room_look.gd")
const Commerce := preload("res://scripts/sim/commerce.gd")
const Clock := preload("res://scripts/sim/clock.gd")
const TestTransit := preload("res://tests/test_transit.gd")
const TestHotel := preload("res://tests/test_hotel.gd")
const TestCharred := preload("res://tests/test_charred_look.gd")

const SEEDS := 40  ## Seeds tried for the hotel: a bound, and enough that a connected room is booked on at least one.


## Lobby on floors 1-2 (columns 100-163), floor 3 above it holding the given kinds side by side from column 100. No stairs.
static func _tower(kinds: Array[String]) -> TowerSim:
	var t := TowerSim.new(42, 1000000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	t.floors.fill_span(3, 100, 299)
	var x := 100
	for kind in kinds:
		var refusal := t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find(kind), 3, x)
		assert(refusal == 0, "%s places, refusal %d" % [kind, refusal])
		x += int(Catalogue.field(kind, "width"))
	return t


static func _room(t: TowerSim, kind: String) -> int:
	for id in t.rooms.room_ids():
		if t.rooms.kind_of(id) == kind:
			return id
	return -1


static func _link(t: TowerSim) -> void:
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 1, 100)
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 2, 104)


static func run(check: Callable) -> void:
	var kinds: Array[String] = ["security", "housekeeping", "medical", "hotel_suite", "casino", "gym", "office"]
	var t := _tower(kinds)
	check.call(t.rooms.cut_off.is_empty(), "before any tick nothing is marked")
	t.step()
	for kind in kinds:
		check.call(t.rooms.is_cut_off(_room(t, kind)), "%s with no stairs or lift is cut off" % kind)
	check.call(not Rooms.needs_route("parking_space") and not Rooms.needs_route("recycling") and not Rooms.needs_route("stairs") and not Rooms.needs_route("local_car") and Rooms.needs_route("pool"), "parking, recycling and links need no route; a pool does")

	# Security: an unreachable office covers nothing, gives no star and clears no demand.
	var office := _room(t, "security")
	check.call(Security.offices(t.rooms).is_empty() and not Security.covers(t.rooms, t.grid, 3) and not Security.threats_possible(t.rooms), "an unreachable security office covers nothing")
	check.call(int(t.star_facts()["security"]) == 0 and int(t.star_facts()["suites"]) == 0, "unreachable offices and suites count for no star")
	var avail: Array[String] = ["security", "medical"]
	t.demands.update(t.rooms, 3, t.messages, 5, avail)
	check.call(t.demands.is_open(Demands.SECURITY), "an unreachable security office leaves its demand open")

	# Housekeeping stations send no staff; the pool does not count a cut-off station.
	t.clock.set_to_tick(1000)
	t.housekeeping.tick(t.clock, t.floors, t.grid)
	check.call(t.housekeeping.staff_count() == 0 and not PoolLife.has_housekeeping(t.rooms), "an unreachable housekeeping station has no staff and does not shorten the pool's cleaning")

	# The look: a cut-off room shows the red cross.
	check.call(RoomLook.describe(t, office)["cut_off"] == true, "a cut-off room describes as cut off")
	var rec := TestCharred.Recorder.new()
	RoomLook.draw_marks(rec, RoomLook.describe(t, office), Rect2i(0, 0, 128, 32), false)
	check.call(not rec.calls.is_empty(), "a cut-off room draws the red cross")

	# Connecting it clears every mark on the next tick and the services work.
	_link(t)
	t.step()
	check.call(t.rooms.cut_off.is_empty(), "stairs to floor 3 clear every mark")
	check.call(Security.covers(t.rooms, t.grid, 3) and int(t.star_facts()["security"]) == 1 and int(t.star_facts()["suites"]) == 1, "a connected office covers and counts")
	t.clock.set_to_tick(2000)
	t.housekeeping.tick(t.clock, t.floors, t.grid)
	check.call(t.housekeeping.staff_count() > 0 and PoolLife.has_housekeeping(t.rooms), "a connected station hires staff")

	# Bulldozing the stairs cuts the floor off again.
	var stair := _room(t, "stairs")
	check.call(stair > 0, "the stairs exist")
	t.rooms.destroy(t.grid, t.floors, stair)
	t.step()
	check.call(not t.rooms.cut_off.is_empty(), "losing the stairs cuts rooms off again")

	# Hotel: across many seeds an unlinked room is never booked, while a linked one is on some seed.
	var booked_unlinked := 0
	for seed_value in range(1, SEEDS + 1):
		var meta: Array = []
		if TestHotel._evening(seed_value, "hotel_single", false, false, meta) != null:
			booked_unlinked += 1
	check.call(booked_unlinked == 0, "an unreachable hotel room books no guests on any of %d seeds (%d booked)" % [SEEDS, booked_unlinked])
	var linked_meta: Array = []
	check.call(TestHotel._booked("hotel_single", true, false, linked_meta) != null, "a connected hotel room is booked on some seed")

	# Synergy: a cut-off deck gives nothing to the neighbours.
	var dt := _tower(["observation_deck"] as Array[String])
	check.call(Synergy.others_of(dt.grid, dt.rooms).size() == 1, "a deck not yet checked is a source")
	dt.step()
	check.call(Synergy.others_of(dt.grid, dt.rooms).is_empty(), "a cut-off deck is no source of synergy")

	# Retail: a cut-off leased shop pays no rent, and does once connected.
	var rt := _tower(["retail"] as Array[String])
	rt.step()
	var rent := rt.commerce.collect_rent(rt.rooms, rt.rent, rt.ledger, rt.tick, true)
	check.call(rent == 0, "a cut-off leased shop pays no rent (%d)" % rent)
	_link(rt)
	rt.step()
	check.call(rt.commerce.collect_rent(rt.rooms, rt.rent, rt.ledger, rt.tick, true) > 0, "once connected it pays")

	# Metro (#325): a station no stairs reach is marked cut off and earns nothing (no rent bonus, no extra visitors)
	# until a route connects it.
	var period := Commerce.period_of_minute(720)
	var counts: Array[int] = []
	var bonuses: Array[int] = []
	for linked: bool in [false, true]:
		var mt := TestTransit._tower()
		TestTransit._station(mt, -1, 100)
		var station := _room(mt, "metro")
		if linked:
			TestTransit._link(mt, 100)
		mt.step()
		check.call(mt.rooms.is_cut_off(station) == not linked, "a metro station is cut off exactly while no route reaches it (linked %s)" % str(linked))
		bonuses.append(mt.rent_bonus_percent())
		var shop := _room(mt, "fast_food")
		mt.commerce._serve("fast_food", 60, 0, mt.floors, mt.rooms, mt.grid, mt.people, mt.tenancy, mt.rng, Clock.WD1, 720, mt.life)
		counts.append(mt.commerce.customers_today(shop))
	var base := Commerce.visitors_for("fast_food", period, Clock.WD1)
	check.call(bonuses == [0, 15], "a cut-off metro station gives no rent bonus until connected (%s)" % str(bonuses))
	check.call(counts[0] == base and counts[1] > base, "a cut-off metro station sends no visitors until connected (%s, base %d)" % [str(counts), base])
