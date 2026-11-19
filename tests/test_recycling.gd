extends RefCounted
## Recycling centres (7.6, #171): two floors, underground only, must touch another centre, fill by
## day, a truck empties them each morning, a full centre is idle, overflow keeps the "needs
## recycling" demand open, no service elevator is needed, and the state saves and loads.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const ClockScript := preload("res://scripts/sim/clock.gd")
const Rec := preload("res://scripts/sim/recycling.gd")
const DemandsScript := preload("res://scripts/sim/demands.gd")


static func _tower() -> TowerSim:
	var t := TowerSim.new(5, 1000000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	t.floors.fill_span(-1, 90, 200)  # B1 under the lobby; basements below rest on it
	return t


static func _put(t: TowerSim, floor_number: int, x: int) -> int:
	return t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("recycling"), floor_number, x)


## Advances a clock to the given hour, letting the module act on every tick on the way. The guard
## only stops a broken clock from looping for ever; a day is under 2,600 ticks.
static func _to_hour(clock: ClockScript, rec: Rec, hour: int, inside: int) -> void:
	var guard := 0
	while clock.hour() != hour and guard < 5000:
		clock.advance()
		rec.tick(clock, inside)
		guard += 1


static func run(check: Callable) -> void:
	check.call(Rooms.PLACEABLE.has("recycling"), "recycling is placeable")
	check.call(Catalogue.star("recycling") == 3 and Catalogue.field("recycling", "height") == 2 and Catalogue.cost("recycling") == 500000, "recycling: 3 stars, two floors, $500,000")

	# Placement.
	var t := _tower()
	var funds := t.ledger.balance
	check.call(_put(t, 5, 100) == Rooms.NOT_UNDERGROUND, "recycling above ground is refused")
	check.call(_put(t, -1, 100) == Rooms.NOT_UNDERGROUND, "recycling on B1 (it needs two basement floors) is refused")
	check.call(t.ledger.balance == funds and t.rooms.room_count() == 0, "refusals cost nothing")
	check.call(_put(t, -3, 100) == Rooms.OK, "the first centre goes anywhere underground (B3 and B2)")
	var first := t.grid.cell_at(-3, 100)
	check.call(t.grid.cell_at(-2, 115) == first + 1 and t.grid.cell_at(-3, 115) == first and t.rooms.room_count() == 1, "it holds both floors and counts as one room")
	check.call(t.rooms.room_of(first + 1) == first and t.rooms.is_tall_upper(first + 1), "the upper half belongs to the room")
	check.call(funds - t.ledger.balance == 500000 + 500 * 2 * 16, "cost: the room plus the missing floor units on both floors")
	check.call(_put(t, -3, 140) == Rooms.NOT_TOUCHING, "a second centre that does not touch is refused")
	check.call(_put(t, -3, 116) == Rooms.OK, "a centre beside the first touches it")
	check.call(_put(t, -5, 100) == Rooms.OK, "a centre below the first touches it")
	check.call(_put(t, -3, 120) == Rooms.OVERLAPS_ROOM, "centres cannot overlap")
	check.call(t.rooms.check_replace(t.grid, t.floors, 1000000000, "recycling", 2, 100)["reason"] == Rooms.TALL_REPLACE, "replace cannot put in a two-floor room")

	# Bulldozing the upper floor removes the whole room.
	t.tick = 20
	t.enqueue(TowerSim.Command.make(21, TowerSim.Command.BULLDOZE, [-2, 105] as Array[int]))
	t.step()
	t.step()
	check.call(t.grid.cell_at(-3, 105) == 0 and t.grid.cell_at(-2, 105) == 0 and t.rooms.room_count() == 2, "bulldozing either floor removes both halves")

	# Capacity tuning: about 9 centres serve 10,000 people over the 16 hours.
	var full_day := 10000 * (Rec.LAST_HOUR - Rec.FIRST_HOUR + 1)
	check.call(9 * Rec.CAPACITY >= full_day and 8 * Rec.CAPACITY < full_day, "about 9 centres serve a full tower")

	# Fill and truck, driven by the clock (it starts at 5:00).
	var s := _tower()
	_put(s, -3, 100)
	var centre := s.grid.cell_at(-3, 100)
	var clock := ClockScript.new()
	var rec := Rec.new(s.rooms)
	_to_hour(clock, rec, 7, 1000)
	check.call(rec.fill_of(centre) == 2000, "rubbish arrives each hour from 6:00 (two hours in, two loads)")
	_to_hour(clock, rec, 10, 1000)
	check.call(rec.fill_of(centre) == 5000, "each hour adds one unit per person inside")
	_to_hour(clock, rec, 22, 1000)
	check.call(rec.fill_of(centre) == 16000 and not rec.short() and not rec.is_idle(centre), "a quiet day fits one centre")
	_to_hour(clock, rec, 6, 1000)
	check.call(rec.fill_of(centre) == 1000, "the truck empties it in the morning (then the new day's first hour fills it)")

	# A busy tower fills the only centre: idle, overflow, demand stays open.
	var busy := Rec.new(s.rooms)
	var c2 := ClockScript.new()
	_to_hour(c2, busy, 12, 8000)
	check.call(busy.is_idle(centre) and busy.fill_of(centre) == Rec.CAPACITY, "a full centre is idle")
	check.call(busy.short(), "rubbish that no centre can take is overflow")
	_to_hour(c2, busy, 14, 8000)
	check.call(busy.fill_of(centre) == Rec.CAPACITY, "an idle centre takes nothing more")
	_to_hour(c2, busy, 6, 8000)
	check.call(busy.short() and busy.fill_of(centre) == 8000, "the truck empties it, but the day before overflowed so the shortage stands")

	# More touching centres cover the same load, and nothing overflows.
	var lone := Rec.new(s.rooms)
	var c4 := ClockScript.new()
	_to_hour(c4, lone, 5, 3000)
	_to_hour(c4, lone, 6, 3000)
	_to_hour(c4, lone, 5, 3000)
	check.call(lone.short(), "one centre cannot take 3,000 people for a day")
	_put(s, -3, 116)
	_put(s, -3, 132)
	var cleared := Rec.new(s.rooms)
	var c3 := ClockScript.new()
	_to_hour(c3, cleared, 6, 3000)
	_to_hour(c3, cleared, 5, 3000)
	check.call(not cleared.short() and cleared.capacity() == 3 * Rec.CAPACITY, "three centres take 3,000 people for a day")

	# Demand: opens with no centre, closes with one, re-opens on overflow.
	var D := DemandsScript
	var all: Array[String] = ["office", "hotel_suite", "security", "medical", "recycling", "parking_space"]
	var bit := 1 << (D.RECYCLING - 1)
	check.call(D.compute(3, {"office": 1}, all) & bit != 0, "no centre: needs recycling")
	check.call(D.compute(3, {"office": 1, "recycling": 1}, all) & bit == 0, "a centre with room clears the demand (no service elevator needed)")
	check.call(D.compute(3, {"office": 1, "recycling": 1, "recycling_short": 1}, all) & bit != 0, "overflowing rubbish re-raises the demand")
	var live := _tower()
	live.stars = 3
	live.floors.fill_span(3, 100, 163)
	live.rooms.place_room(live.grid, live.floors, live.ledger, 0, Catalogue.IDS.find("office"), 3, 100)
	live.promote_stars()
	check.call(live.demands.is_open(D.RECYCLING), "a live tower with an office at 3 stars asks for recycling")
	_put(live, -3, 100)
	live.promote_stars()
	check.call(not live.demands.is_open(D.RECYCLING), "building a centre clears the demand")

	# Save and load.
	live.recycling._fill[live.grid.cell_at(-3, 100)] = 1234
	var copy := TowerSim.new(5)
	check.call(copy.load_state(live.save()) and copy.recycling.state_ints() == live.recycling.state_ints(), "the fill and flags save and load")
	check.call(copy.rooms.room_of(copy.grid.cell_at(-2, 100)) == copy.grid.cell_at(-3, 100), "a loaded centre keeps its upper half")
	check.call(not Rec.valid_ints([0]) and not Rec.valid_ints([30, 0, 0, 0]) and Rec.valid_ints([-1, 0, 0, 0]), "bad recycling saves are refused")
