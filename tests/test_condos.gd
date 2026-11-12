extends RefCounted
## Condo tests (3.4): 3 residents per condo, sold only when reachable and never 21:00 to 7:00,
## away by day and home at night on every day of the week.

const TowerSim := preload("res://scripts/sim/tower.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const Tenancy := preload("res://scripts/sim/tenancy.gd")
const People := preload("res://scripts/sim/people.gd")
const Clock := preload("res://scripts/sim/clock.gd")
const TestTenancy := preload("res://tests/test_tenancy.gd")
const TestOfficeDay := preload("res://tests/test_office_day.gd")


static func _tower() -> TowerSim:
	var t := TowerSim.new(7, 100000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 131, 2)
	t.floors.fill_span(3, 100, 131)
	t.rooms.place_room(t.grid, t.floors, t.ledger, 0, CatalogueScript.IDS.find("condo"), 3, 110)
	return t


static func _condo(t: TowerSim) -> int:
	return t.rooms.room_ids()[0]


static func _at(t: TowerSim, minute: int, day: int) -> void:
	t.clock.set_to_tick(TestOfficeDay._tick_at(minute, day))
	for i in 10:
		t.step()


static func _all_at(t: TowerSim, room: int) -> bool:
	for i in t.people.count():
		if t.people.goal_room(i) != room:
			return false
	return t.people.count() > 0


static func run(check: Callable) -> void:
	var t := _tower()
	var condo := _condo(t)
	_at(t, 10 * 60, 0)
	check.call(not t.rooms.is_sold(condo) and t.people.count() == 0, "an unreachable condo does not sell")

	TestTenancy._link(t)
	var funds := t.ledger.balance
	_at(t, 10 * 60, 0)
	var price := CatalogueScript.cost("condo")
	check.call(t.rooms.is_sold(condo) and t.people.count() == 3, "connecting it sells it with exactly 3 residents")
	check.call(t.people.home_of(0) == condo and t.people.work_of(0) == People.NONE, "residents live in the condo and work outside")
	check.call(t.ledger.balance == funds + price, "the sale is credited once")
	_at(t, 11 * 60, 0)
	check.call(t.people.count() == 3 and t.ledger.balance == funds + price, "never more than 3 residents, never sold twice")

	for minute in [22 * 60, 6 * 60]:
		var n := _tower()
		TestTenancy._link(n)
		_at(n, minute, 0)
		check.call(not n.rooms.is_sold(_condo(n)) and n.people.count() == 0, "no sale at minute %d" % minute)

	for day in [0, 2]:  # a weekday and the weekend
		var d := _tower()
		TestTenancy._link(d)
		_at(d, 10 * 60, day)
		check.call(d.people.count() == 3, "day %d: 3 residents" % day)
		check.call(_all_at(d, People.NONE), "day %d: residents are away by day" % day)
		_at(d, 22 * 60, day)
		check.call(_all_at(d, _condo(d)), "day %d: residents are home at night" % day)
