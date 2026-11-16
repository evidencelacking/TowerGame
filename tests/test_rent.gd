extends RefCounted
## Rent level tests (5.3): four levels, per-unit, SET_RENT, rent in the catalogue, higher rent
## lowers quality for the same stress, quarterly income by level, condo lock, saves.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Rent := preload("res://scripts/sim/rent.gd")
const Grades := preload("res://scripts/sim/grades.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const Messages := preload("res://scripts/sim/messages.gd")
const TestTenancy := preload("res://tests/test_tenancy.gd")
const TestOfficeDay := preload("res://tests/test_office_day.gd")
const TestCondos := preload("res://tests/test_condos.gd")

const QUARTER_TICKS := 7650  ## 3 days of 2,550 ticks.


## A linked tower with two offices on floor 3, both leased, their workers having made trips.
static func _two_offices() -> TowerSim:
	var t := TestTenancy._tower()
	t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("office"), 3, 120)
	TestTenancy._link(t)
	TestTenancy._run_at(t, TestTenancy.MORNING_TICK)
	TestOfficeDay._at(t, 12 * 60 + 30)
	for k in 600:
		t.step()
	return t


static func _set_all(t: TowerSim, stress: int) -> void:
	for i in t.people.count():
		t.people.set_stress(i, stress)


## Applies SET_RENT through the command queue.
static func _command(t: TowerSim, room: int, level: int) -> void:
	t.enqueue(TowerSim.Command.make(t.tick + 1, TowerSim.Command.SET_RENT, [room, level] as Array[int]))
	t.step()


## Income credited at the given tick.
static func _income_at(t: TowerSim, at_tick: int) -> int:
	var total := 0
	for line: Array in t.ledger.lines:
		if line[2] == t.ledger.INCOME and line[0] == at_tick:
			total += line[1]
	return total


static func run(check: Callable) -> void:
	# Rent is catalogue data: four levels, the default is $10,000.
	var rents: Array = Catalogue.row("office")["rent"]
	check.call(rents.size() == Rent.LEVELS and Rent.LEVELS == 4, "an office has four rent levels in the catalogue")
	check.call(rents[Rent.DEFAULT_LEVEL] == 10000, "the default office rent is $10,000")
	check.call(rents[0] < rents[1] and rents[1] < rents[2] and rents[2] < rents[3], "rent rises with the level")
	check.call(Rent.is_rentable("office") and not Rent.is_rentable("condo") and not Rent.is_rentable("stairs"), "only offices have rent levels so far")

	var t := _two_offices()
	var ids := t.rooms.room_ids()
	var a: int = ids[0]
	var b: int = ids[1]
	check.call(t.rooms.kind_of(a) == "office" and t.rooms.kind_of(b) == "office", "the test tower has two offices")
	check.call(t.rent_level(a) == Rent.DEFAULT_LEVEL and t.rent_amount(a) == 10000, "a new office starts at the default level and rent")

	# Per unit: setting one office leaves the other alone.
	var hash_before := t.state_hash()
	_command(t, a, Rent.LEVEL_HIGH)
	check.call(t.rent_level(a) == Rent.LEVEL_HIGH and t.rent_level(b) == Rent.DEFAULT_LEVEL, "SET_RENT changes only the chosen office")
	check.call(t.rent_amount(a) == rents[3] and t.rent_amount(b) == rents[2], "rent amounts are per unit")
	check.call(t.last_refusal == 0, "SET_RENT succeeds with no refusal")
	check.call(t.messages.entry(t.messages.count() - 1)[1] == Messages.RENT_SET, "a rent change is logged")
	check.call(t.state_hash() != hash_before, "the rent level is part of the state hash")

	# Same stress, higher rent: worse quality and grade. Lower rent: better.
	_set_all(t, 90)
	t.rent.set_rent(t.rooms, a, Rent.DEFAULT_LEVEL)
	check.call(t.quality(a) == 210 and t.grade(a) == Grades.GRADE_A, "stress 90 at the default rent is quality 210 and A")
	t.rent.set_rent(t.rooms, a, Rent.LEVEL_HIGH)
	check.call(t.quality(a) < 210 and t.grade(a) == Grades.GRADE_B, "the highest rent lowers the grade for the same stress")
	check.call(t.quality(b) == 210, "the other office's quality is unchanged")
	_set_all(t, 120)
	t.rent.set_rent(t.rooms, a, Rent.DEFAULT_LEVEL)
	var base_quality := t.quality(a)
	check.call(t.grade(a) == Grades.GRADE_B, "stress 120 at the default rent is B")
	t.rent.set_rent(t.rooms, a, Rent.LEVEL_GREEN)
	check.call(t.quality(a) > base_quality, "a lower rent raises quality")
	t.rent.set_rent(t.rooms, a, Rent.LEVEL_LOW)
	check.call(t.quality(a) > base_quality and t.grade(a) == Grades.GRADE_A, "the lowest rent raises the grade for the same stress")
	check.call(t.rent.never_leaves(t.rooms, a) and not t.rent.never_leaves(t.rooms, b), "only the lowest level is flagged as never leaving")

	# Refusals: condos are locked, bad levels, unknown rooms.
	check.call(t.rent.set_rent(t.rooms, a, 4) == Rent.BAD_LEVEL and t.rent.set_rent(t.rooms, a, -1) == Rent.BAD_LEVEL, "levels outside 0 to 3 are refused")
	check.call(t.rent.set_rent(t.rooms, 99999, 1) == Rent.NO_SUCH_ROOM, "an unknown room is refused")
	var c := TestCondos._tower()
	var condo := TestCondos._condo(c)
	check.call(c.rent.set_rent(c.rooms, condo, 3) == Rent.CONDO_LOCKED and c.rent_level(condo) == Rent.DEFAULT_LEVEL, "condo rent cannot be changed")
	_command(c, condo, 3)
	check.call(c.last_refusal == Rent.CONDO_LOCKED and c.messages.entry(c.messages.count() - 1)[1] == Messages.RENT_REFUSED, "a SET_RENT on a condo is refused and logged")
	check.call(c.rent.stress_offset(c.rooms, condo) == 0 and c.rent_amount(condo) == 0, "a condo has no rent offset or rent")

	# Income scales with level: one quarter's rent is credited at the quarter start.
	var low := _two_offices()
	var mid := _two_offices()
	var high := _two_offices()
	for room: int in low.rooms.room_ids():
		_command(low, room, Rent.LEVEL_LOW)
	for room: int in high.rooms.room_ids():
		_command(high, room, Rent.LEVEL_HIGH)
	var gained: Array[int] = []
	for tower: TowerSim in [low, mid, high]:
		tower.clock.set_to_tick(QUARTER_TICKS - 1)
		tower.step()
		gained.append(_income_at(tower, tower.tick))
	check.call(gained[1] == 2 * 10000, "two default offices pay $20,000 at the quarter start (got %d)" % gained[1])
	check.call(gained[0] == 2 * rents[0] and gained[2] == 2 * rents[3], "rent income follows each office's level")
	check.call(gained[0] < gained[1] and gained[1] < gained[2], "income rises with the rent level")
	mid.step()
	check.call(_income_at(mid, mid.tick) == 0, "rent is credited once a quarter, not every tick")

	# An empty office pays no rent.
	var empty := TestTenancy._tower()
	empty.clock.set_to_tick(QUARTER_TICKS - 1)
	empty.step()
	check.call(empty.clock.quarter_started and _income_at(empty, empty.tick) == 0, "an unleased office pays no rent")

	# Saves: levels survive, a bad list is refused, bulldozing forgets the level.
	var other := TowerSim.new(7, 100000000)
	check.call(other.load_state(t.save()), "a save with rent levels loads")
	check.call(other.state_hash() == t.state_hash() and other.rent_level(a) == Rent.LEVEL_LOW, "rent levels survive a save round trip")
	var bad := t.save()
	bad["rent"] = [1, a, 9]
	check.call(not TowerSim.new(7, 100000000).load_state(bad), "a rent level outside 0 to 3 is refused on load")
	bad["rent"] = [3]
	check.call(not TowerSim.new(7, 100000000).load_state(bad), "a malformed rent list is refused on load")
	var no_rent := t.save()
	no_rent.erase("rent")
	check.call(not TowerSim.new(7, 100000000).load_state(no_rent), "a save without rent is refused")
	t.enqueue(TowerSim.Command.make(t.tick + 1, TowerSim.Command.BULLDOZE, [3, 110] as Array[int]))
	t.step()
	check.call(not t.rooms.has_room(a) and t.rent.state_ints().size() == 1, "bulldozing an office forgets its rent level")
