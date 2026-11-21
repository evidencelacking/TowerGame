extends RefCounted
## The swimming pool (#328 step 2): a two-floor room above ground, swimmers from the tower and the street with an
## entry price, a lifeguard, a daily cleaning that housekeeping shortens, a deterministic cannonball, and a lift for
## the condos and hotels near it. Also the step-1 gaps: a full place_room above ground and highest_room_floor counting
## the upper floor. Our own design: every number is an unverified tunable.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Commerce := preload("res://scripts/sim/commerce.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const Rooms := preload("res://scripts/sim/rooms.gd")
const PoolLife := preload("res://scripts/sim/pool_life.gd")
const Synergy := preload("res://scripts/sim/synergy.gd")
const Clock := preload("res://scripts/sim/clock.gd")
const Names := preload("res://scripts/sim/names.gd")
const RoomLook := preload("res://scripts/view/room_look.gd")
const ToolbarScript := preload("res://scripts/view/toolbar.gd")
const TestNewKinds := preload("res://tests/test_new_kinds.gd")

const POOL_X := 120
const LUNCH := 720
const EVENING := 1050


## Lobby on floors 1-2 (columns 100-163), floor 3 over it, stairs from the lobby to floor 3 so a pool there is reachable.
static func _tower() -> TowerSim:
	var t := TowerSim.new(42, 100000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	t.floors.fill_span(3, 100, 163)
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 1, 100)
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 2, 104)
	return t


static func _put(t: TowerSim, kind: String, floor_number: int, x: int) -> int:
	return t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find(kind), floor_number, x)


static func _serve(t: TowerSim, window: int, percent: int, minute: int, day: int) -> void:
	t.commerce._serve("pool", window, percent, t.floors, t.rooms, t.grid, t.people, t.tenancy, t.rng, day, minute, t.life)


## How many ticks in the first `ticks` have a cannonball starting for a room.
static func _jumps(room: int, ticks: int) -> int:
	var count := 0
	for tick in ticks:
		if PoolLife.cannonball_age(room, tick) == 0:
			count += 1
	return count


## The cannonball ages of a room over the first `ticks` ticks, in order.
static func _ages(room: int, ticks: int) -> Array[int]:
	var ages: Array[int] = []
	for tick in ticks:
		ages.append(PoolLife.cannonball_age(room, tick))
	return ages


static func run(check: Callable) -> void:
	# The catalogue row and the placement above ground (step 1's gap: a full place_room).
	var row: Dictionary = Catalogue.row("pool")
	check.call(int(row["width"]) == 24 and int(row["height"]) == 2 and int(row["staff"]) == 4 and Catalogue.star("pool") == 3 and Catalogue.cost("pool") == 700000, "pool: 24 wide, two floors, 4 staff, star 3, $700,000")
	check.call(Rooms.TALL_KINDS.has("pool") and Rooms.PLACEABLE.has("pool") and Catalogue.IDS.has("pool"), "pool: a tall, placeable kind in the catalogue")
	var t := _tower()
	var before := t.ledger.balance
	var refusal := _put(t, "pool", 3, POOL_X)
	check.call(refusal == Rooms.OK, "pool: place_room puts it on floor 3 (%d)" % refusal)
	var pool := TestNewKinds._room(t, "pool")
	check.call(pool > 0 and t.grid.cell_at(3, POOL_X) == pool and t.grid.cell_at(4, POOL_X) == pool + 1 and t.grid.cell_at(4, POOL_X + 23) == pool + 1, "pool: it holds floor 3 and the upper floor 4 over its whole width")
	check.call(t.rooms.room_of(pool + 1) == pool and t.rooms.is_tall_upper(pool + 1) and not t.rooms.is_tall_upper(pool), "pool: the upper floor belongs to the pool")
	check.call(t.floors.has_floor(4, POOL_X) and t.floors.has_floor(4, POOL_X + 23) and not t.floors.has_floor(4, POOL_X - 1), "pool: the upper floor's 24 units are built")
	check.call(before - t.ledger.balance == Catalogue.cost("pool") + 24 * Catalogue.FLOOR_COST_PER_UNIT, "pool: it costs its price and the 24 floor units of the upper floor (%d)" % (before - t.ledger.balance))
	check.call(t.rooms.highest_room_floor(t.grid) == 4, "pool: the upper floor counts for the highest room floor (%d)" % t.rooms.highest_room_floor(t.grid))
	check.call(_put(t, "pool", 3, POOL_X + 12) == Rooms.OVERLAPS_ROOM, "pool: a second pool over the first is refused")
	check.call(_put(t, "pool", 1, 140) == Rooms.LOBBY_FLOOR and _put(t, "pool", -3, 100) == Rooms.BELOW_GROUND, "pool: not on the lobby floor, not underground")
	check.call(t.rooms.check_replace(t.grid, t.floors, 100000000, "pool", 3, POOL_X)["reason"] == Rooms.TALL_REPLACE, "pool: a tall room cannot be put in by replace")
	check.call(t.rooms.bulldoze(t.grid, t.floors, t.ledger, 0, 4, POOL_X + 3) == Rooms.OK and not t.grid.has_occupant(pool) and not t.grid.has_occupant(pool + 1) and t.rooms.highest_room_floor(t.grid) == 0, "pool: bulldozing it from the upper floor takes both floors")

	# Who comes, and when: the three waves, entry money, the guest share, the street's visitors.
	t = _tower()
	_put(t, "pool", 3, POOL_X)
	pool = TestNewKinds._room(t, "pool")
	var waves: Array[int] = []
	for meal: Array in Commerce.MEALS:
		if meal[3] == "pool":
			waves.append(meal[0])
	check.call(waves == [390, 720, 1050], "pool: waves at 06:30, 12:00 and 17:30 (%s)" % str(waves))
	check.call(Commerce.is_shop("pool") and Commerce.has_sales("pool") and Commerce._guest_percent("pool") == Commerce.POOL_GUEST_PERCENT, "pool: trades like a shop and draws hotel guests")
	check.call(Commerce.visitors_for("pool", 5, Clock.WD1) > 0 and Commerce.visitors_for("pool", 5, Clock.WE) > Commerce.visitors_for("pool", 5, Clock.WD1) and Commerce.visitors_for("pool", 6, Clock.WD1) == 0, "pool: the street comes at the waves, more at the weekend, never at night")
	TestNewKinds._inside(t, 30, 60)
	_serve(t, 60, 100, LUNCH, Clock.WD1)
	var came := t.commerce.customers_today(pool)
	check.call(came >= 30, "pool: the 30 people inside swim at lunch, and the street's visitors (%d)" % came)
	check.call(Commerce.pool_takings(0) == -Commerce.POOL_WAGES and Commerce.pool_takings(100) == 100 * Commerce.POOL_ENTRY - Commerce.POOL_WAGES, "pool: an entry price a swimmer, less the staff's wages")
	var break_even := Commerce.POOL_WAGES / Commerce.POOL_ENTRY
	check.call(Commerce.pool_takings(break_even + 1) > 0 and Commerce.pool_takings(break_even - 1) < 0, "pool: it pays its way from about %d swimmers a day" % break_even)
	var balance := t.ledger.balance
	t.commerce._settle(t.floors, t.rooms, t.grid, t.tenancy, t.ledger, t.messages, t.tick, t.rng)
	check.call(t.ledger.balance - balance == Commerce.pool_takings(came), "pool: settlement credits the entry money less the wages (%d)" % (t.ledger.balance - balance))
	check.call(t.commerce.customers_last_day(pool) == came, "pool: the day's swimmers grade it")

	# Cleaning: the daily drain shuts it; a housekeeping station makes it short enough for the evening wave.
	check.call(PoolLife.is_cleaning(850, true) and not PoolLife.is_cleaning(PoolLife.CLEAN_FROM + PoolLife.CLEAN_MINUTES, true) and PoolLife.is_cleaning(1000, false), "pool: cleaning is an hour with housekeeping and four hours without")
	check.call(not PoolLife.is_open(850, true) and PoolLife.is_open(LUNCH, false) and PoolLife.is_open(EVENING, true) and not PoolLife.is_open(EVENING, false) and not PoolLife.is_open(300, true) and not PoolLife.is_open(1330, true), "pool: open 06:00 to 22:00 except while cleaned")
	check.call(PoolLife.lifeguard_on_duty(LUNCH) and PoolLife.lifeguard_on_duty(850) and not PoolLife.lifeguard_on_duty(300) and not PoolLife.lifeguard_on_duty(1330), "pool: a lifeguard in the chair through the opening hours")
	var alone := _tower()
	_put(alone, "pool", 3, POOL_X)
	TestNewKinds._inside(alone, 30, 60)
	_serve(alone, 150, 100, EVENING, Clock.WD1)
	check.call(alone.commerce.customers_today(TestNewKinds._room(alone, "pool")) == 0, "pool: with no housekeeping the evening wave finds it still shut")
	var kept := _tower()
	_put(kept, "pool", 3, POOL_X)
	var hk := _put(kept, "housekeeping", 3, 146)
	TestNewKinds._inside(kept, 30, 60)
	_serve(kept, 150, 100, EVENING, Clock.WD1)
	check.call(hk == Rooms.OK and PoolLife.has_housekeeping(kept.rooms) and not PoolLife.has_housekeeping(alone.rooms), "pool: a housekeeping station is found in the tower")
	check.call(kept.commerce.customers_today(TestNewKinds._room(kept, "pool")) >= 30, "pool: with that station the evening wave swims (%d)" % kept.commerce.customers_today(TestNewKinds._room(kept, "pool")))
	check.call(PoolLife.swimmers(0, LUNCH, true) == 0 and PoolLife.swimmers(40, 850, true) == 0 and PoolLife.swimmers(3, LUNCH, true) == 1 and PoolLife.swimmers(400, LUNCH, true) == PoolLife.SWIMMERS_MAX, "pool: swimmers drawn follow the day's customers, none while shut")

	# The cannonball: the same room and tick always give the same splash.
	var slots := 500
	var jumps := _jumps(pool, PoolLife.SLOT_TICKS * slots)
	check.call(jumps == _jumps(pool, PoolLife.SLOT_TICKS * slots) and _ages(pool, 600) == _ages(pool, 600), "pool: the same room gives the same cannonballs on every run")
	check.call(jumps > slots * 30 / 100 and jumps < slots * 50 / 100, "pool: about 40 percent of the slots have a cannonball (%d of %d)" % [jumps, slots])
	check.call(_ages(pool, 24 * 100) != _ages(pool + 10, 24 * 100), "pool: another room has a schedule of its own")
	var span := true
	for tick in range(0, PoolLife.SLOT_TICKS * 200):
		var age := PoolLife.cannonball_age(pool, tick)
		var slot_start := tick - tick % PoolLife.SLOT_TICKS
		var started := PoolLife.cannonball_age(pool, slot_start) == 0
		var expected := tick - slot_start if started and tick - slot_start < PoolLife.SPLASH_TICKS else -1
		if age != expected:
			span = false
	check.call(span, "pool: a splash starts at its slot's opening tick and lasts the splash's ticks, no more")
	var places := {}
	for slot in 300:
		places[PoolLife.jump_place(pool, slot * PoolLife.SLOT_TICKS)] = true
	check.call(places.size() == PoolLife.BOARD_PLACES and PoolLife.cannonball_age(0, 5) == -1 and PoolLife.cannonball_age(pool, -1) == -1, "pool: jumpers leap from every place on the board; no room, no splash")

	# What the view reads from the sim: the pool's moving parts.
	t.clock.set_to_tick(0)
	var look := RoomLook.describe(t, pool)
	check.call(look["kind"] == "pool" and look.has("anim") and int(look["splash"]) < RoomLook.SPLASH_FRAMES and RoomLook.handles("pool"), "pool: its look carries the swimmers, the guard and the splash")
	check.call(RoomLook.describe(t, pool + 1)["anim"] == look["anim"], "pool: both floors read the same moving parts")

	# Mood and demand for the condos and hotels near it.
	var sources: Array = [["pool", [3, 120, 24]]]
	check.call(Synergy.mood_delta("condo", [5, 120, 16], sources) == 4 and Synergy.mood_delta("condo", [12, 120, 16], sources) == 0, "pool: +4 mood for a condo within 6 floors only")
	check.call(Synergy.mood_delta("hotel_twin", [10, 120, 4], sources) == 3 and Synergy.total(Synergy.CONDO_DEMAND, "condo", [5, 120, 16], sources) == 10, "pool: +3 mood for hotels, +10 percent on a nearby condo's price")

	# The job titles (a lifeguard), the toolbar and the player's words.
	var titles: Array = Names.TITLES["pool"]
	check.call(titles.size() == 3 and (titles[1] as Array).has("Lifeguard"), "pool: job titles for three age bands, with the lifeguard")
	check.call(ToolbarScript.item_state("pool", 2)["locked"] and not ToolbarScript.item_state("pool", 3)["locked"], "pool: locked before star 3, open at star 3")

	# Save and load, and two runs of a day agree.
	var copy := TowerSim.new(1, 1)
	check.call(copy.load_state(t.save()) and copy.state_hash() == t.state_hash(), "pool: a tower with a pool survives save and load")
	var a := _tower()
	var b := _tower()
	for tower: TowerSim in [a, b]:
		_put(tower, "pool", 3, POOL_X)
		TestNewKinds._inside(tower, 40, 60)
		tower.clock.set_to_tick(0)
		for n in 2550:
			tower.step()
	check.call(a.state_hash() == b.state_hash(), "pool: two runs of a day with a pool agree")
