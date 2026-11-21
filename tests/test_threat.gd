extends RefCounted
## Threat, #218: an anonymous notice, a 13:00 deadline, pay $200,000 or refuse and let security search
## floor by floor; a miss destroys the device's floor, 2 above and 2 below, with everything on them.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const Fixtures := preload("res://tests/fixtures.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const Msg := preload("res://scripts/sim/messages.gd")
const ThreatScript := preload("res://scripts/sim/threat.gd")
const Sec := preload("res://scripts/sim/security.gd")
const GridScript := preload("res://scripts/sim/grid.gd")

const FLOORS: Array[int] = [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 27, 28, 29, 30, 31, 32, 33]


static func _put(t: TowerSim, kind: String, floor_number: int, x: int) -> int:
	t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find(kind), floor_number, x)
	return t.grid.cell_at(floor_number, x)


## A 3-star tower with an office on every floor in FLOORS (at x 100) and a security office on floor 3.
static func _tower(seed_value: int) -> TowerSim:
	var t := TowerSim.new(seed_value, 1000000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	for f in FLOORS:
		t.floors.fill_span(f, 100, 163)
		_put(t, "office", f, 100)
	_put(t, "security", 3, 120)
	t.stars = 3
	Fixtures.connect_by_stairs(t)  # the security office on floor 3 is reached
	return t


## Makes the first threat certain once an office stands (the people gate is tested on its own).
static func _force(t: TowerSim) -> void:
	var threat := t.threat  # the closure holds the parts, not the tower, so nothing cycles and leaks
	var rooms := t.rooms
	t.events.kinds[1]["chance_of"] = func() -> int: return 100000 if Sec.threats_possible(rooms) and threat.state_ints()[1] == 0 else 0


static func _until_notice(t: TowerSim, limit: int = 6000) -> bool:
	for _i in limit:
		t.step()
		if t.threat.is_active():
			return true
	return false


static func _set_device(t: TowerSim, floor_number: int) -> void:
	var ints := t.threat.state_ints()
	ints[4] = floor_number
	t.threat.load_ints(ints)


static func _has_message(t: TowerSim, code: int) -> bool:
	for i in t.messages.count():
		if t.messages.entry(i)[1] == code:
			return true
	return false


static func _alive(t: TowerSim, floor_number: int) -> bool:
	return t.grid.cell_at(floor_number, 100) != GridScript.EMPTY


static func _answer(t: TowerSim, choice: int) -> void:
	t.enqueue(Command.make(t.tick + 1, Command.CHOOSE_EVENT, [t.events.open_events()[0][0], choice] as Array[int]))
	t.step()


static func run(check: Callable) -> void:
	# The gate: 3,000 people, a security office, halved for each office beyond the first.
	var gate := _tower(1)
	var one: int = ThreatScript.chance(gate.rooms, 3000, false)
	check.call(one == ThreatScript.CHANCE and ThreatScript.CHANCE * 2 * 100 / ThreatScript.CHANCE_DEN == 3, "with one office the odds are about 3% a day (two morning rolls)")
	check.call(ThreatScript.chance(gate.rooms, 2999, false) == 0, "no threat under 3,000 people")
	check.call(ThreatScript.chance(gate.rooms, 3000, true) == 0, "no second threat while one runs")
	_put(gate, "security", 12, 120)
	check.call(ThreatScript.chance(gate.rooms, 3000, false) == one / 2, "a second office halves the odds")
	_put(gate, "security", 30, 120)
	check.call(ThreatScript.chance(gate.rooms, 3000, false) == one / 4, "a third office halves them again")
	var bare := TowerSim.new(2, 1000000000)
	check.call(ThreatScript.chance(bare.rooms, 5000, false) == 0, "no threat without a security office")
	var small := _tower(1)  # not forced: this tower holds far fewer than 3,000 people
	for _i in 3 * 2550:
		small.step()
	check.call(small.events.rolls > 0 and not small.threat.is_active() and small.population() < ThreatScript.MIN_POPULATION, "a tower under 3,000 people gets no threat")

	# The blast range is exact: the floor, 2 above, 2 below, with no floor 0 gap, clipped at the ends.
	check.call(ThreatScript.blast_range(30) == ([28, 32] as Array[int]), "the blast covers 5 floors around the device")
	check.call(ThreatScript.blast_range(1) == ([-2, 3] as Array[int]) and ThreatScript.blast_range(100) == ([98, 100] as Array[int]), "the blast counts no floor 0 and stops at the ends")

	# The notice: a morning time, a 13:00 deadline, and a choice.
	var t := _tower(3)
	_force(t)
	check.call(_until_notice(t), "the notice comes")
	var event: Array = t.events.open_events()[0]
	var minute_now := t.clock.minute_of_day()
	check.call(event[1] == ThreatScript.KIND and minute_now >= 300 and minute_now < 660 and _has_message(t, Msg.THREAT_NOTICE), "it comes in the morning, as a message")
	var deadline: int = event[5]
	var before := TowerSim.new(0)
	before.clock.set_to_tick(deadline - 1)
	var at := TowerSim.new(0)
	at.clock.set_to_tick(deadline)
	check.call(before.clock.minute_of_day() < 780 and at.clock.minute_of_day() >= 780 and deadline > t.tick, "the deadline is 13:00 the same day")
	check.call(t.threat.device_floor() in FLOORS, "the device is on a floor that holds a room")

	# Paying ends it: $200,000, nothing destroyed.
	var rooms_before := t.rooms.room_count()
	var balance := t.ledger.balance
	_answer(t, ThreatScript.PAY)
	check.call(balance - t.ledger.balance == 200000, "paying costs $200,000")  # before rent and wages come in
	for _i in 3000:
		t.step()
	check.call(not t.threat.is_active() and t.rooms.room_count() == rooms_before and _has_message(t, Msg.THREAT_PAID), "paying ends it with nothing destroyed")

	# Found in time: the device is within reach of the office on floor 3.
	var saved := _tower(3)
	_force(saved)
	_until_notice(saved)
	_set_device(saved, 8)
	var count := saved.rooms.room_count()
	_answer(saved, 0)
	for _i in 800:
		saved.step()
	check.call(not saved.threat.is_active() and _has_message(saved, Msg.THREAT_FOUND) and saved.rooms.room_count() == count, "a floor in reach is found before the deadline and nothing is lost")

	# Missed: floor 30 is out of the office's reach, so the device goes off.
	var missed := _tower(3)
	_force(missed)
	_until_notice(missed)
	_set_device(missed, 30)
	var worker := missed.grid.cell_at(30, 100)
	missed.people.add_person(-1, worker, missed.rng)
	var stairs_ok := missed.rooms.place_stairs(missed.grid, missed.floors, missed.ledger, 0, 32, 140) == Rooms.OK
	var stairs_id := missed.rooms.link_at(32, 140)
	_answer(missed, 0)
	for _i in 800:
		missed.step()
	var gone := true
	for f in [28, 29, 30, 31, 32]:
		gone = gone and not _alive(missed, f)
	check.call(gone, "a miss destroys the device's floor, 2 above and 2 below")
	check.call(_alive(missed, 27) and _alive(missed, 33) and _alive(missed, 12) and _alive(missed, 3), "floors just outside the range are untouched")
	check.call(_has_message(missed, Msg.THREAT_EXPLODED) and not missed.threat.is_active(), "the blast is logged and the threat is over")
	check.call(missed.people.workers_in(worker) == 0 and stairs_ok and stairs_id != GridScript.EMPTY and not missed.rooms.has_room(stairs_id), "people and stairs on the destroyed floors go too")
	check.call(missed.rooms.place_room(missed.grid, missed.floors, missed.ledger, missed.tick, Catalogue.IDS.find("office"), 30, 100) == Rooms.OK, "the destroyed floors stay as empty floor")
	for _i in 500:
		missed.step()

	# Not answering is refusing: the choice times out at the deadline with the search under way.
	var silent := _tower(3)
	_force(silent)
	_until_notice(silent)
	_set_device(silent, 30)
	for _i in 2000:
		silent.step()
	check.call(not _alive(silent, 30) and _alive(silent, 27), "no answer by the deadline is a refusal")

	# More offices search more floors: a second office near floor 30 finds it in time.
	var helped := _tower(3)
	Fixtures.connect_floors(helped, 30, 148)  # a lift to the second office (a shaft spans at most 30 floors)
	_put(helped, "security", 29, 120)
	_force(helped)
	_until_notice(helped)
	_set_device(helped, 30)
	_answer(helped, 0)
	for _i in 800:
		helped.step()
	check.call(_alive(helped, 30) and _has_message(helped, Msg.THREAT_FOUND), "a second office near the device finds it in time")

	# Save and load in the middle of a search resume the same run.
	var mid := _tower(4)
	_force(mid)
	_until_notice(mid)
	_set_device(mid, 30)
	_answer(mid, 0)
	for _i in 100:
		mid.step()
	var copy := TowerSim.new(0)
	check.call(copy.load_state(mid.save()) and copy.threat.state_ints() == mid.threat.state_ints() and copy.threat.is_active(), "a save mid-threat loads with the search under way")
	_force(copy)
	for _i in 1500:
		mid.step()
		copy.step()
	check.call(copy.state_hash() == mid.state_hash() and not _alive(copy, 30), "the loaded tower reaches the same blast")
	check.call(not ThreatScript.valid_ints([1, 2, 3]), "a malformed threat save is refused")
