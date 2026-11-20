extends RefCounted
## Rest-period evaluation tests (5.2): A brings a friend, B stays, C leaves, an office leaves
## after a second red evaluation only, a condo that leaves refunds its price, the evaluation runs
## once a day, it is deterministic and its counters save.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Evaluation := preload("res://scripts/sim/evaluation.gd")
const Grades := preload("res://scripts/sim/grades.gd")
const Messages := preload("res://scripts/sim/messages.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const TestCondos := preload("res://tests/test_condos.gd")
const TestTenancy := preload("res://tests/test_tenancy.gd")
const TestOfficeDay := preload("res://tests/test_office_day.gd")

const A_STRESS := 0  ## Quality 300: A.
const B_STRESS := 125  ## Quality 175: B.
const C_STRESS := 200  ## Quality 100: C.


## A linked tower on floor 3 with two units of kind (room ids first and second), the first
## leased or sold and its people having made a trip, the second vacant.
static func _pair(kind: String, seed_value: int = 7) -> TowerSim:
	var t := TowerSim.new(seed_value, 100000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 131, 2)
	t.floors.fill_span(3, 100, 160)
	var width: int = CatalogueScript.row(kind)["width"]
	t.rooms.place_room(t.grid, t.floors, t.ledger, 0, CatalogueScript.IDS.find(kind), 3, 108)
	TestTenancy._link(t)
	if kind == "condo":
		TestCondos._at(t, 10 * 60, 0)
		TestCondos._at(t, 19 * 60, 0)
	else:
		TestTenancy._run_at(t, TestTenancy.MORNING_TICK)
		TestOfficeDay._at(t, 12 * 60 + 30)
		for k in 600:
			t.step()
	t.rooms.place_room(t.grid, t.floors, t.ledger, 0, CatalogueScript.IDS.find(kind), 3, 108 + width)
	return t


static func _stress(t: TowerSim, value: int) -> void:
	for i in t.people.count():
		t.people.set_stress(i, value)


static func _count(t: TowerSim, code: int) -> int:
	var n := 0
	for i in t.messages.count():
		if t.messages.entry(i)[1] == code:
			n += 1
	return n


static func run(check: Callable) -> void:
	for kind in ["condo", "office"]:
		var per: int = CatalogueScript.row(kind)["people"]
		# A brings a friend into the empty unit beside it.
		var t := _pair(kind)
		var first: int = t.rooms.room_ids()[0]
		check.call(t.people.count() == per, "%s: only the first unit is tenanted" % kind)
		_stress(t, A_STRESS)
		check.call(t.grade(first) == Grades.GRADE_A, "%s: the tenants are A" % kind)
		t.evaluate_tenants()
		check.call(t.people.count() == 2 * per, "%s: A brings a friend: the vacant unit fills" % kind)
		check.call(_count(t, Messages.FRIEND_ARRIVED) == 1, "%s: the friend is logged" % kind)
		t.evaluate_tenants()
		check.call(t.people.count() == 2 * per, "%s: with no vacancy left no more arrive" % kind)

		# B changes nothing.
		var b := _pair(kind)
		_stress(b, B_STRESS)
		var before := [b.rooms.state_ints(), b.ledger.state_ints(), b.messages.state_ints(), b.people.count()]  # mood moves on the day; tenancy and money must not
		check.call(b.grade(b.rooms.room_ids()[0]) == Grades.GRADE_B, "%s: the tenants are B" % kind)
		b.evaluate_tenants()
		check.call(before == [b.rooms.state_ints(), b.ledger.state_ints(), b.messages.state_ints(), b.people.count()] and b.people.count() == per, "%s: B changes nothing" % kind)

	# A condo that is C leaves at the evaluation: vacant, refunded, not paying.
	var c := _pair("condo")
	var condo: int = c.rooms.room_ids()[0]
	_stress(c, C_STRESS)
	check.call(c.grade(condo) == Grades.GRADE_C and c.rooms.is_sold(condo), "the condo is C and sold")
	var funds := c.ledger.balance
	c.evaluate_tenants()
	check.call(not c.rooms.is_sold(condo) and c.people.count() == 0, "C vacates the condo")
	check.call(c.ledger.balance == funds - CatalogueScript.cost("condo"), "the condo's sale price is refunded")
	check.call(_count(c, Messages.TENANT_LEFT) == 1 and _count(c, Messages.CONDO_REFUND) == 1, "leaving and the refund are logged")
	var broke := _pair("condo")
	_stress(broke, C_STRESS)
	broke.ledger.refund(0, -broke.ledger.balance, 0)
	broke.evaluate_tenants()
	check.call(broke.ledger.balance == -CatalogueScript.cost("condo"), "the refund goes into negative funds")

	# An office needs two red evaluations in a row; a non-red one resets the count.
	var o := _pair("office")
	var office: int = o.rooms.room_ids()[0]
	_stress(o, C_STRESS)
	o.evaluate_tenants()
	check.call(o.people.workers_in(office) == 6 and o.evaluation.red_days(office) == 1, "one red day: the office stays, counted")
	o.evaluate_tenants()
	check.call(o.people.workers_in(office) == 0 and o.evaluation.red_days(office) == 0, "a second red day: the office leaves")
	check.call(_count(o, Messages.TENANT_LEFT) == 1, "the office leaving is logged")
	var r := _pair("office")
	office = r.rooms.room_ids()[0]
	_stress(r, C_STRESS)
	r.evaluate_tenants()
	_stress(r, B_STRESS)
	r.evaluate_tenants()
	_stress(r, C_STRESS)
	r.evaluate_tenants()
	check.call(r.people.workers_in(office) == 6 and r.evaluation.red_days(office) == 1, "a red day, a non-red day, a red day: the office stays")

	# The evaluation runs once a day at the rest period.
	var d := _pair("condo")
	_stress(d, C_STRESS)
	d.clock.set_to_tick(TestOfficeDay._tick_at(Evaluation.EVALUATE_MINUTE - 5, 0))
	var left := 0
	for k in 400:
		d.step()
		if _count(d, Messages.TENANT_LEFT) > left:
			left = _count(d, Messages.TENANT_LEFT)
			check.call(d.clock.minute_of_day() >= Evaluation.EVALUATE_MINUTE and d.clock.minute_of_day() < Evaluation.EVALUATE_MINUTE + 30, "it evaluates at the rest period")
	check.call(left == 1, "the step loop evaluates once")

	# Deterministic: the same seed and steps give the same hash; the counters survive a save.
	var x := _pair("office", 42)
	var y := _pair("office", 42)
	_stress(x, A_STRESS)
	_stress(y, A_STRESS)
	x.evaluate_tenants()
	y.evaluate_tenants()
	check.call(x.state_hash() == y.state_hash(), "the same seed gives the same evaluation")
	var s := _pair("office")
	_stress(s, C_STRESS)
	s.evaluate_tenants()
	var loaded := TowerSim.new(7, 100000000)
	check.call(loaded.load_state(s.save()) and loaded.state_hash() == s.state_hash(), "a save keeps the red-day counts")
	check.call(loaded.evaluation.red_days(s.rooms.room_ids()[0]) == 1, "the count is restored")
	var bad := s.save()
	bad["evaluation"] = [3]
	check.call(not TowerSim.new(7, 100000000).load_state(bad), "a malformed evaluation list is refused")
