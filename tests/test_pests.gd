extends RefCounted
## Pests tests (6.5): a hotel room dirty for 3 days is infested, the log warns a day earlier,
## pests spread one neighbouring hotel room a day along the floor only, infested rooms take no
## guests, cleaning does not cure them and demolition does. Numbers are tunables (see pests.gd).

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const HotelScript := preload("res://scripts/sim/hotel.gd")
const PestsScript := preload("res://scripts/sim/pests.gd")
const MessagesScript := preload("res://scripts/sim/messages.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const TestHotel := preload("res://tests/test_hotel.gd")
const TestRooms := preload("res://tests/test_rooms.gd")

const DAY := PestsScript.TICKS_PER_DAY


## Lobby on 1-2, floors 3 and 4 built across the tower width used here.
static func _tower(seed_value: int = 1) -> TowerSim:
	var t := TowerSim.new(seed_value, 100000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 131, 2)
	t.floors.fill_span(3, 100, 131)
	t.floors.fill_span(4, 100, 131)
	return t


static func _room(t: TowerSim, kind: String, floor_number: int, x: int) -> int:
	if t.rooms.place_room(t.grid, t.floors, t.ledger, 0, CatalogueScript.IDS.find(kind), floor_number, x) != RoomsScript.OK:
		return -1
	return t.grid.cell_at(floor_number, x)


static func _dirty(t: TowerSim, room: int, since: int) -> void:
	t.hotel._records[room] = [HotelScript.VACANT, -1, -1, 420, -1, 0, since, 0] as Array[int]


static func _clean(t: TowerSim, room: int) -> void:
	t.hotel._records[room] = [HotelScript.VACANT, -1, -1, 420, -1, 0, -1, 0] as Array[int]


static func _daily(t: TowerSim, at_tick: int) -> void:
	t.pests.tick(t.hotel, t.grid, t.rng, t.messages, at_tick)


static func _count(t: TowerSim, code: int) -> int:
	var n := 0
	for i in t.messages.count():
		if t.messages.entry(i)[1] == code:
			n += 1
	return n


static func run(check: Callable) -> void:
	# Warning a day ahead, once; pests at 3 days dirty.
	var t := _tower()
	var a := _room(t, "hotel_single", 3, 100)
	_dirty(t, a, 0)
	_daily(t, DAY)
	check.call(not t.pests.is_infested(a) and _count(t, MessagesScript.PESTS_WARNING) == 0, "one day dirty: no pests and no warning")
	_daily(t, 2 * DAY)
	check.call(not t.pests.is_infested(a) and _count(t, MessagesScript.PESTS_WARNING) == 1, "two days dirty: a warning in the log, no pests yet")
	_daily(t, 2 * DAY + 1)
	check.call(_count(t, MessagesScript.PESTS_WARNING) == 1, "the warning comes once a day at most")
	_daily(t, 3 * DAY)
	check.call(t.pests.is_infested(a) and _count(t, MessagesScript.PESTS_FOUND) == 1, "three days dirty: the room is infested and the log says so")

	# A room cleaned in time never gets pests.
	var c := _tower()
	var kept := _room(c, "hotel_single", 3, 100)
	_dirty(c, kept, 0)
	_daily(c, 2 * DAY)
	c.hotel.mark_clean(kept)
	_daily(c, 3 * DAY)
	_daily(c, 6 * DAY)
	check.call(c.pests.infested_count() == 0, "a cleaned room never gets pests")

	# Infested: not dirty for staff, and cleaning does not cure it.
	check.call(not t.hotel.is_dirty(a) and t.hotel.is_infested(a), "an infested room reads as not dirty, so staff skip it")
	t.hotel.mark_clean(a)
	check.call(t.pests.is_infested(a), "cleaning does not cure an infested room")

	# Spread: one room a day along the floor, never up or across a gap.
	var s := _tower()
	var r0 := _room(s, "hotel_single", 3, 100)
	var r1 := _room(s, "hotel_single", 3, 104)
	var r2 := _room(s, "hotel_single", 3, 108)
	var gap := _room(s, "hotel_single", 3, 116)  # columns 112-115 left empty
	var above := _room(s, "hotel_single", 4, 100)
	_dirty(s, r0, 0)
	_daily(s, 3 * DAY)
	check.call(s.pests.infested_rooms() == ([r0] as Array[int]), "day 0: only the dirty room is infested")
	_daily(s, 4 * DAY)
	check.call(s.pests.infested_count() == 2 and s.pests.is_infested(r1), "day 1: the pests move to the neighbour")
	_daily(s, 5 * DAY)
	check.call(s.pests.infested_count() == 3 and s.pests.is_infested(r2), "day 2: and on to the next room")
	_daily(s, 6 * DAY)
	_daily(s, 7 * DAY)
	check.call(s.pests.infested_count() == 3 and not s.pests.is_infested(gap) and not s.pests.is_infested(above), "spread is horizontal only and stops at a gap")

	# Infested rooms take no guests; clean ones do.
	var g := _tower(3)
	var bad := _room(g, "hotel_single", 3, 100)
	var good: Array[int] = []
	for x in [104, 108, 112, 116, 120]:
		good.append(_room(g, "hotel_single", 3, x))
	_dirty(g, bad, 0)
	_daily(g, 3 * DAY)
	_clean(g, bad)  # even with the dirt gone, the pests keep guests out
	TestHotel._jump(g, 17 * 60, 3)
	TestHotel._step_to(g, 22 * 60, 3)
	var booked := 0
	for room in good:
		if g.hotel._records[room][1] != -1:  # the planned night: set once the room is offered to guests
			booked += 1
	check.call(g.pests.is_infested(bad) and g.hotel._records[bad][1] == -1 and booked == good.size(), "an infested room takes no guests while clean ones do")

	# Demolition clears pests.
	var d := _tower()
	var doomed := _room(d, "hotel_single", 3, 100)
	_dirty(d, doomed, 0)
	_daily(d, 3 * DAY)
	var infested_before := d.pests.is_infested(doomed)
	var result := TestRooms._send(d, Command.BULLDOZE, [3, 100] as Array[int])
	check.call(infested_before and result == RoomsScript.OK and d.pests.infested_count() == 0, "demolition clears the pests")

	# Deterministic with the seeded RNG, and saved with the tower.
	var one := _spread_run(5)
	var two := _spread_run(5)
	check.call(one.pests.infested_count() > 1 and one.state_hash() == two.state_hash() and one.pests.infested_rooms() == two.pests.infested_rooms(), "spread is deterministic for a seed")
	var loaded := TowerSim.new(0)
	check.call(loaded.load_state(one.save()) and loaded.state_hash() == one.state_hash() and loaded.pests.infested_rooms() == one.pests.infested_rooms(), "infested rooms survive a save and load")
	var damaged := one.save()
	damaged["pests"] = [1, 5, 0]
	check.call(not TowerSim.new(0).load_state(damaged) and not PestsScript.valid_ints([0, 2, 7]), "damaged pest records are refused")


## A row of five hotel rooms with the middle one dirty; seven daily steps from day 3.
static func _spread_run(seed_value: int) -> TowerSim:
	var t := _tower(seed_value)
	var ids: Array[int] = []
	for x in [100, 104, 108, 112, 116]:
		ids.append(_room(t, "hotel_single", 3, x))
	_dirty(t, ids[2], 0)
	for day in range(3, 10):
		_daily(t, day * DAY)
	return t
