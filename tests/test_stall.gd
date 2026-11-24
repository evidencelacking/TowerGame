extends RefCounted
## Stuck elevator (M9 9.11, #473): a car with riders stalls in a rush, only in a local shaft of a tower with two passenger
## shafts and never a service car; riders' stress climbs on the normal 0-300 scale; the two answers (rescue crew, routine
## repair) and the timeout default; one stall per shaft per day; the car keeps its stops and schedule and the shaft's other
## cars run on; nobody aboard is lost or duplicated.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const Stall := preload("res://scripts/sim/stall.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const Messages := preload("res://scripts/sim/messages.gd")
const People := preload("res://scripts/sim/people.gd")
const Cars := preload("res://scripts/sim/cars.gd")
const Alerts := preload("res://scripts/sim/alerts.gd")
const Clock := preload("res://scripts/sim/clock.gd")
const TestOfficeDay := preload("res://tests/test_office_day.gd")

const FUNDS := 100000000


static func _shaft(t: TowerSim, kind: String, x: int, top: int) -> int:
	t.rooms.place_shaft(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find(kind), 1, top, x)
	return t.rooms._shaft_base(t.rooms.link_at(1, x))


## An office on floor 11 reached by `shafts` local shafts of `cars` cars each (and a two-car service shaft if `service`), 3 stars,
## at 8:55 on the first day, with a stall armed for a long window.
static func _tower(shafts: int = 2, cars: int = 2, service: bool = false) -> TowerSim:
	var t := TowerSim.new(7, FUNDS)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	for f in range(3, 12):
		t.floors.fill_span(f, 100, 163)
	t.stars = 3
	for n in shafts:
		var shaft := _shaft(t, "local_shaft", 100 + 8 * n, 11)
		for _c in cars:
			t.rooms.add_car(t.ledger, 0, 3, shaft, 1)
	if service:
		var service_shaft := _shaft(t, "service_shaft", 140, 11)
		t.rooms.add_car(t.ledger, 0, 3, service_shaft, 1)
		t.rooms.add_car(t.ledger, 0, 3, service_shaft, 1)
	t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("office"), 11, 120)
	t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("office"), 11, 132)
	var at := TestOfficeDay._tick_at(People.ARRIVE - 5, 0)
	t.tick = at
	t.clock.set_to_tick(at)
	_arm(t)
	return t


## Arms a stall for the next `ticks` ticks (the saved window), keeping the rest of the state.
static func _arm(t: TowerSim, ticks: int = 4000) -> void:
	var ints := t.stall.state_ints()
	ints[6] = t.tick + ticks
	t.stall.load_ints(ints)


## Steps until a car stalls or `limit` ticks pass. True when one stalled.
static func _until_stalled(t: TowerSim, limit: int = 3000) -> bool:
	for _i in limit:
		t.step()
		if t.stall.is_stalled():
			return true
	return false


static func _answer(t: TowerSim, choice: int) -> void:
	var id: int = t.events.open_events()[0][0]
	t.enqueue(Command.make(t.tick + 1, Command.CHOOSE_EVENT, [id, choice] as Array[int]))
	t.step()
	t.step()
	t.step()


static func _count(t: TowerSim, code: int) -> int:
	var n := 0
	for i in t.messages.count():
		if t.messages.entry(i)[1] == code:
			n += 1
	return n


## Everyone riding or queued, one entry per place: a person in two cars (or a car and a queue) shows up twice.
static func _placed(t: TowerSim) -> Array[int]:
	var ids: Array[int] = []
	for n in t.rooms.total_cars():
		ids.append_array(t.rooms.riders_of(n))
	ids.append_array(t.rooms.queued_ids())
	return ids


static func _stalled_index(t: TowerSim) -> int:
	var keys: Array = t.rooms.stalled.keys()
	return keys[0] if keys.size() == 1 else -1


static func _schedule_sum(t: TowerSim, shaft: int) -> int:
	return t.rooms.schedule_field(shaft, 0, 0) * 1000000 + t.rooms.schedule_field(shaft, 0, 1) * 1000 + t.rooms.schedule_field(shaft, 0, 2)


static func run(check: Callable) -> void:
	_gates(check)
	_stall_and_stress(check)
	_rescue(check)
	_routine_and_timeout(check)
	_cap_and_saving(check)


static func _gates(check: Callable) -> void:
	# Two local shafts of two cars and a stall armed: a car with riders stalls (the baseline for the gates below).
	check.call(_until_stalled(_tower()), "stall: with two shafts a car with riders stalls")
	# One passenger shaft (even with a service shaft): no stall.
	var one := _tower(1, 2, true)
	check.call(not _until_stalled(one, 2600) and one.events.open_count() == 0, "stall: no roll with one passenger shaft (a service shaft does not count)")
	# Below 2 stars: no stall.
	var low := _tower()
	low.stars = 1
	check.call(not _until_stalled(low, 2600), "stall: no stall below 2 stars")
	# A shaft with a single car is never stalled (it would be left with none).
	check.call(not _until_stalled(_tower(2, 1), 2600), "stall: a shaft left with no other car is never stalled")
	# A service shaft is never picked: with the local shafts at one car each only the service shaft has two.
	var service_only := _tower(2, 1, true)
	for _i in 2600:
		service_only.step()
	check.call(not service_only.stall.is_stalled(), "stall: service cars never stall")
	# Not armed: nothing happens however many riders.
	var unarmed := _tower()
	var rest := Stall.rest_ints()
	rest[0] = 0x2545F4914F6CDD1D  # a mixed stream state (a tiny one draws 0 first)
	unarmed.stall.load_ints(rest)
	unarmed.stall.arm_one_in = 1000000
	check.call(not _until_stalled(unarmed, 1500), "stall: nothing stalls unless a rush armed it")
	# The arming draw is one per period from the stall's own stream, the same in any tower.
	var drawn_a := _tower()
	var drawn_b := _tower(1, 1)
	for _i in 2550:
		drawn_a.step()
		drawn_b.step()
	check.call(drawn_a.stall.state_ints()[0] == drawn_b.stall.state_ints()[0], "stall: the stream draws the same in any tower")


static func _stall_and_stress(check: Callable) -> void:
	var t := _tower()
	var twin := _tower()  # the same tower, never armed: the shared Events stream must be where this one's is
	var rest := Stall.rest_ints()
	rest[0] = 0x2545F4914F6CDD1D
	twin.stall.load_ints(rest)
	twin.stall.arm_one_in = 1000000
	check.call(_until_stalled(t), "stall: a car stalls with riders aboard")
	var index := _stalled_index(t)
	var shaft: int = t.stall.stalled_car()[0]
	var riders := t.rooms.riders_of(index)
	check.call(index != -1 and not riders.is_empty() and t.events.open_count() == 1 and t.events.open_events()[0][1] == Stall.KIND, "stall: the stalled car holds riders and a card is open")
	check.call(_count(t, Messages.CAR_STALLED) == 1 and t.stall.stalled_today() == ([shaft] as Array[int]), "stall: it is logged once and the shaft is marked for the day")
	var nth: int = t.rooms.car_indexes_of(shaft).find(index)
	var car_before: Array = t.rooms.cars_of(shaft)[nth]
	var stops_before := t.rooms.stops_of(shaft)
	var schedule_before := _schedule_sum(t, shaft)
	var stress_before: Array[int] = []
	for id in riders:
		stress_before.append(t.people.stress_of(t.people.index_of(id)))
	# A hall call on the stalled shaft goes to another car; the stalled car does not move.
	t.rooms.place_call(shaft, 6, Cars.UP)
	var taken_by_stalled := false
	var others_moved := false
	for _i in 30:
		t.step()
		for call: Array in t.rooms.calls():
			taken_by_stalled = taken_by_stalled or call[3] == index
		for other_nth in t.rooms.car_indexes_of(shaft).size():
			if other_nth != nth:
				var other: Array = t.rooms.cars_of(shaft)[other_nth]
				others_moved = others_moved or other[Cars.STATE] != Cars.IDLE or other[Cars.FLOOR] != 1
	var car_now: Array = t.rooms.cars_of(shaft)[nth]
	check.call(not taken_by_stalled and car_now[Cars.FLOOR] == car_before[Cars.FLOOR] and car_now[Cars.STATE] == car_before[Cars.STATE] and car_now[Cars.TICKS] == car_before[Cars.TICKS], "stall: the stalled car holds still and takes no calls")
	check.call(others_moved, "stall: the shaft's other cars keep running and answer its calls")
	check.call(t.rooms.stops_of(shaft) == stops_before and _schedule_sum(t, shaft) == schedule_before and t.rooms.cars_of(shaft)[nth][Cars.HOME] == car_before[Cars.HOME], "stall: the shaft keeps its stops and schedule and the car its home")
	# Riders' stress climbs, inside 0 to 300.
	var climbed := true
	var inside := true
	for id in riders:
		var i := t.people.index_of(id)
		inside = inside and t.people.stress_of(i) >= 0 and t.people.stress_of(i) <= People.STRESS_MAX
		climbed = climbed and t.people.stress_of(i) > stress_before[riders.find(id)]
	check.call(climbed and inside and not t.rooms.riders_of(index).is_empty(), "stall: the riders' stress climbs while the car is stuck, on the normal scale")
	# The stall drew nothing from the shared Events stream.
	while twin.tick < t.tick:
		twin.step()
	check.call(t.events.rolls > 0 and t.events.rolls == twin.events.rolls and t.events.state_ints()[0] == twin.events.state_ints()[0], "stall: the card opens without touching the shared stream")


## Answers with the rescue crew: charged $10,000, the riders get out, the car is back after one period.
static func _rescue(check: Callable) -> void:
	var t := _tower()
	_until_stalled(t)
	var index := _stalled_index(t)
	var shaft: int = t.stall.stalled_car()[0]
	var riders := t.rooms.riders_of(index)
	var people_before := t.people.count()
	var stress_before := t.people.stress_of(t.people.index_of(riders[0]))
	var funds := t.ledger.balance
	_answer(t, Stall.CHOICE_RESCUE)
	check.call(funds - t.ledger.balance == Stall.RESCUE_COST, "stall: the rescue crew costs $10,000")
	check.call(t.rooms.riders_of(index).is_empty() and t.stall.is_stalled(), "stall: the riders are let out and the car stays out for a while")
	var after := t.people.stress_of(t.people.index_of(riders[0]))
	check.call(after >= mini(stress_before + Stall.RESCUE_JUMP, People.STRESS_MAX) and after <= People.STRESS_MAX, "stall: each rider takes a small jump in stress on the 0-300 scale")
	# Nobody lost or duplicated: all still in People, none in two places, none left riding a car they are not in.
	for _i in 10:
		t.step()
	var seen := _placed(t)
	var distinct := {}
	for id in seen:
		distinct[id] = true
	var none_aboard := true
	var all_known := true
	var sane := true
	for id in riders:
		none_aboard = none_aboard and not t.rooms.riders_of(index).has(id)
		all_known = all_known and t.people.index_of(id) != -1
		sane = sane and (t.people.trip_state(t.people.index_of(id)) != People.TRIP_RIDING or t.rooms.in_elevator(id))
	check.call(all_known and t.people.count() == people_before and distinct.size() == seen.size() and none_aboard, "stall: nobody is lost or duplicated")
	check.call(sane, "stall: every rider is back somewhere sane, not left riding a car they are not in")
	# Back after one period: still out part-way through, in service after.
	var left := Clock.period_ticks(t.clock.period() - 1)
	for _i in 100:
		t.step()
	check.call(t.stall.is_stalled(), "stall: the rescued car is still out part-way through the period")
	for _i in left + 50:
		t.step()
	check.call(not t.stall.is_stalled() and t.rooms.stalled.is_empty() and _count(t, Messages.CAR_RESUMED) == 1, "stall: the rescued car is back after a period")
	# The resumed shaft serves a call again.
	t.rooms.place_call(shaft, 4, Cars.UP)
	var worked := false
	for _i in 60:
		t.step()
		for car: Array in t.rooms.cars_of(shaft):
			worked = worked or car[Cars.FLOOR] != 1 or car[Cars.STATE] != Cars.IDLE
	check.call(worked, "stall: a resumed shaft serves calls")


## Routine repair, answered and by the timeout default: free, the riders out with a big jump, the car out for the rest of the day.
static func _routine_and_timeout(check: Callable) -> void:
	for timed_out in [false, true]:
		var t := _tower()
		_until_stalled(t)
		var index := _stalled_index(t)
		var riders := t.rooms.riders_of(index)
		var stress_before := t.people.stress_of(t.people.index_of(riders[0]))
		var funds := t.ledger.balance
		var label := "timeout" if timed_out else "routine"
		if timed_out:
			for _i in Stall.NOTICE_TICKS + 20:
				t.step()
			check.call(t.events.resolved()[-1][2] == Stall.CHOICE_REPAIR, "stall: unanswered, the card times out to routine repair")
		else:
			_answer(t, Stall.CHOICE_REPAIR)
		check.call(funds == t.ledger.balance, "stall: %s repair is free" % label)
		check.call(t.rooms.riders_of(index).is_empty() and t.stall.is_stalled(), "stall: %s repair lets the riders out and keeps the car out" % label)
		var after := t.people.stress_of(t.people.index_of(riders[0]))
		check.call(after >= mini(stress_before + Stall.RUN_JUMP, People.STRESS_MAX) and after <= People.STRESS_MAX, "stall: %s repair gives the riders the big stress jump on the 0-300 scale" % label)
		for _i in 1000:  # well into the day
			t.step()
		check.call(t.stall.is_stalled(), "stall: %s repair leaves the car out through the day" % label)
		var to_day_end := t.clock.ticks_until_minute(Clock.PERIOD_1_START)
		for _i in to_day_end + 20:
			t.step()
		check.call(not t.stall.is_stalled() and t.rooms.stalled.is_empty(), "stall: %s repair returns the car at the next day" % label)
	check.call(Stall.RUN_JUMP > Stall.RESCUE_JUMP, "stall: routine repair upsets riders more than the rescue crew")


static func _cap_and_saving(check: Callable) -> void:
	# One stall per shaft per day: after the first shaft stalled and resumed, it is not picked again the same day.
	var t := _tower(2, 2)
	_until_stalled(t)
	var first: int = t.stall.stalled_car()[0]
	_answer(t, Stall.CHOICE_RESCUE)
	for _i in Clock.period_ticks(t.clock.period() - 1) + 80:
		t.step()
	check.call(not t.stall.is_stalled(), "stall: the first car is back")
	_arm(t, 1500)
	var again := _until_stalled(t, 1500)
	var seen: Array[int] = t.stall.stalled_today()
	var duplicate := false
	for id in seen:
		duplicate = duplicate or seen.count(id) > 1
	check.call(not duplicate and (not again or t.stall.stalled_car()[0] != first), "stall: a shaft stalls at most once a day")

	# Saved mid-stall: the loaded tower is the same tower and ends the stall in step with the original.
	var s := _tower()
	_until_stalled(s)
	var loaded := TowerSim.new(0, FUNDS)
	check.call(loaded.load_state(s.save()) and loaded.state_hash() == s.state_hash() and loaded.stall.is_stalled(), "stall: a save mid-stall loads as the same tower")
	_answer(s, Stall.CHOICE_RESCUE)
	_answer(loaded, Stall.CHOICE_RESCUE)
	for _i in 1500:
		s.step()
		loaded.step()
	check.call(loaded.state_hash() == s.state_hash(), "stall: the loaded tower and the original stay in step through the answer and the resume")
	var bad := s.save()
	bad["stall"] = [1, 2]
	check.call(not TowerSim.new(0, 1).load_state(bad), "stall: a damaged stall block is refused")

	# The alert list shows the card at the car's floor, then the stalled car.
	var a := _tower()
	_until_stalled(a)
	var alerts := Alerts.list(a)
	var stalled: Array[int] = a.stall.stalled_car()
	check.call(alerts.size() == 2 and alerts[0][0] == Alerts.EVENT and alerts[0][3] == Stall.KIND and alerts[1] == [Alerts.STALL, stalled[1], Alerts.ACTIVE, stalled[0]], "stall: the card and the stalled car are alerts")
	check.call(Alerts.label_of(alerts[1], a) == "Stalled elevator" and Alerts.label_of(alerts[0], a) == "Stuck elevator", "stall: the alerts are named")

	# The kind is manual, defaults to routine repair and prices the rescue.
	var def := a.events.kind_def(Stall.KIND)
	check.call(def.get("manual", false) and def["default"] == Stall.CHOICE_REPAIR and def["costs"] == [0, Stall.RESCUE_COST], "stall: the kind is manual, defaults to routine repair and prices the rescue crew")
