extends RefCounted
## Fire, #217: needs 3 stars and a security office, starts in a random room, spreads sideways and up
## each period, destroys a room after 3 periods unless guards reach it (#216), and the owner may pay
## $500,000 for a rescue craft that puts out every fire except the first two rooms that burned.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const Msg := preload("res://scripts/sim/messages.gd")
const FireScript := preload("res://scripts/sim/fire.gd")
const Sec := preload("res://scripts/sim/security.gd")
const GridScript := preload("res://scripts/sim/grid.gd")


## A 3-star tower with floors 3, 4, 30 and 31 built. Seeded.
static func _tower(seed_value: int) -> TowerSim:
	var t := TowerSim.new(seed_value, 1000000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	for f in [3, 4, 30, 31]:
		t.floors.fill_span(f, 100, 163)
	t.stars = 3
	return t


static func _put(t: TowerSim, kind: String, floor_number: int, x: int) -> int:
	t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find(kind), floor_number, x)
	return t.grid.cell_at(floor_number, x)


## Makes the first fire certain (once a security office stands), so tests do not wait on 4% a day.
static func _force(t: TowerSim) -> void:
	t.events.kinds[0]["chance_of"] = func() -> int: return 100000 if Sec.threats_possible(t.rooms) and t.fire.state_ints()[1] == 0 else 0


## Steps until a room burns; false if none does within the limit.
static func _until_burning(t: TowerSim, limit: int = 2000) -> bool:
	for _i in limit:
		t.step()
		if not t.fire.burning_rooms().is_empty():
			return true
	return false


static func _has_message(t: TowerSim, code: int) -> bool:
	for i in t.messages.count():
		if t.messages.entry(i)[1] == code:
			return true
	return false


## A tower with an office on floor 3 and one office on floor 30, which no office covers.
static func _uncovered(seed_value: int) -> TowerSim:
	var t := _tower(seed_value)
	_put(t, "security", 3, 100)
	_put(t, "office", 30, 100)
	_force(t)
	return t


static func run(check: Callable) -> void:
	# Gate: no fire without a security office, whatever the odds.
	var bare := _tower(1)
	_put(bare, "office", 4, 100)
	_force(bare)
	check.call(bare.fire.chance(bare.rooms) == 0, "no security office: the fire's chance is 0")
	for _i in 3 * 2550:
		bare.step()
	check.call(bare.events.rolls > 0 and bare.events.open_count() == 0 and bare.fire.burning_rooms().is_empty(), "no fire without a security office")
	_put(bare, "security", 3, 100)
	check.call(bare.fire.chance(bare.rooms) == FireScript.CHANCE and FireScript.CHANCE * 6 / 1000 == 4, "with an office the odds are about 4% a day (670 per 100,000 per period)")
	var young := _tower(1)
	young.stars = 2
	_put(young, "security", 3, 100)
	_put(young, "office", 4, 100)
	_force(young)
	for _i in 2 * 2550:
		young.step()
	check.call(young.events.open_count() == 0 and young.fire.burning_rooms().is_empty(), "no fire below 3 stars")

	# Left to the guards: a covered room is put out within the response time, nothing is lost.
	var guarded := _tower(2)
	_put(guarded, "security", 3, 100)
	var covered := _put(guarded, "office", 4, 100)
	_force(guarded)
	check.call(_until_burning(guarded), "a covered fire starts")
	check.call(guarded.fire.burning_rooms() == ([covered] as Array[int]) and guarded.events.open_count() == 1, "the fire starts in a room and opens a choice")
	for _i in Sec.response_ticks(guarded.rooms, guarded.grid, 4):
		guarded.step()
	check.call(guarded.fire.burning_rooms().is_empty() and guarded.rooms.has_room(covered) and _has_message(guarded, Msg.FIRE_OUT), "guards reach a covered fire and put it out")
	check.call(not _has_message(guarded, Msg.ROOM_BURNED) and guarded.events.open_count() == 0, "nothing is lost and the choice closes")

	# Left to burn: no guards reach floor 30, so the room goes after 3 periods.
	var burnt := _uncovered(3)
	var target := burnt.grid.cell_at(30, 100)
	check.call(_until_burning(burnt) and burnt.fire.burning_rooms() == ([target] as Array[int]), "an uncovered fire starts in the room on floor 30")
	var boundaries := 0
	var alive_before_third := false
	for _i in 3000:
		burnt.step()
		if burnt.clock.ticks_in_period() == 0:
			boundaries += 1
			if boundaries == 2:
				alive_before_third = burnt.rooms.has_room(target)
			if boundaries == 3:
				break
	check.call(alive_before_third and not burnt.rooms.has_room(target), "an unattended room burns for 3 periods, then is destroyed")
	check.call(burnt.grid.cell_at(30, 100) == GridScript.EMPTY and burnt.fire.burning_rooms().is_empty() and _has_message(burnt, Msg.ROOM_BURNED), "the destroyed room leaves empty floor")
	check.call(burnt.rooms.place_room(burnt.grid, burnt.floors, burnt.ledger, burnt.tick, Catalogue.IDS.find("office"), 30, 100) == Rooms.OK, "the floor under it is still there")

	# The paid rescue: costs $500,000, arrives in a period, loses the room that was burning.
	var rescued := _uncovered(3)
	var doomed := rescued.grid.cell_at(30, 100)
	_until_burning(rescued)
	var event_id: int = rescued.events.open_events()[0][0]
	var balance := rescued.ledger.balance
	rescued.enqueue(Command.make(rescued.tick + 1, Command.CHOOSE_EVENT, [event_id, FireScript.PAY] as Array[int]))
	rescued.step()
	check.call(balance - rescued.ledger.balance == 500000 and rescued.events.open_count() == 0, "paying charges $500,000 and closes the choice")
	var paid_at := rescued.tick
	check.call(rescued.fire.rescue_at() > paid_at and rescued.fire.rescue_at() - paid_at <= 600, "the rescue craft arrives within one period")
	var arrived := 0
	for _i in 700:
		rescued.step()
		if arrived == 0 and rescued.fire.burning_rooms().is_empty():
			arrived = rescued.tick
	check.call(arrived != 0 and arrived - paid_at <= 600 and _has_message(rescued, Msg.RESCUE_ARRIVED), "the rescue craft puts the fire out")
	check.call(not rescued.rooms.has_room(doomed), "the first room that was burning is lost even so")

	# Rescue with three fires: the first two are lost, the third is saved.
	var three := _uncovered(4)
	var a := three.grid.cell_at(30, 100)
	var b := _put(three, "office", 30, 109)
	var c := _put(three, "office", 30, 118)
	var ints := three.fire.state_ints()
	ints[3] = three.tick + 5
	ints[4] = 3
	ints.append_array([a, 0, 0, b, 0, 0, c, 0, 0] as Array[int])
	three.fire.load_ints(ints)
	for _i in 6:
		three.step()
	check.call(not three.rooms.has_room(a) and not three.rooms.has_room(b) and three.rooms.has_room(c) and three.fire.burning_rooms().is_empty(), "the rescue saves every fire except the first two rooms that burned")

	# Not enough money: the choice is refused and stays open.
	var poor := _uncovered(3)
	_until_burning(poor)
	poor.ledger.balance = 100000
	poor.enqueue(Command.make(poor.tick + 1, Command.CHOOSE_EVENT, [poor.events.open_events()[0][0], FireScript.PAY] as Array[int]))
	poor.step()
	check.call(poor.ledger.balance == 100000 and poor.events.open_count() == 1 and poor.fire.rescue_at() == 0, "a rescue the owner cannot afford is refused")

	# Not answering leaves it to burn, and the choice times out.
	var silent := _uncovered(3)
	var silent_room := silent.grid.cell_at(30, 100)
	_until_burning(silent)
	for _i in 3000:
		silent.step()
	check.call(not silent.rooms.has_room(silent_room) and silent.events.open_count() == 0, "an unanswered fire is left to burn and the choice times out")

	# Spread: over some seeds a fire reaches the neighbours, over others it does not.
	var spread := 0
	var single := 0
	for seed_value in 12:
		var s := _uncovered(seed_value)
		_put(s, "office", 30, 109)
		_put(s, "office", 31, 100)
		_until_burning(s)
		var most := 1
		for _i in 2000:
			s.step()
			most = maxi(most, s.fire.burning_rooms().size())
		if most > 1:
			spread += 1
		else:
			single += 1
	check.call(spread > 0 and single > 0, "a fire sometimes spreads to the rooms beside and above it, and sometimes does not (%d of 12 seeds)" % spread)

	# People who worked in a burned room go with it, and the tower keeps running.
	var staffed := _uncovered(5)
	var work := staffed.grid.cell_at(30, 100)
	staffed.people.add_person(-1, work, staffed.rng)
	_until_burning(staffed)
	for _i in 3000:
		staffed.step()
	check.call(not staffed.rooms.has_room(work) and staffed.people.count() == 0, "people tied to a burned room are removed")

	# Save and load in the middle of a fire resume the same run.
	var live := _uncovered(6)
	_put(live, "office", 30, 109)
	_until_burning(live)
	for _i in 400:
		live.step()
	var copy := TowerSim.new(0)
	check.call(copy.load_state(live.save()) and copy.fire.state_ints() == live.fire.state_ints() and not copy.fire.burning_rooms().is_empty(), "a save mid-fire loads with the fire intact")
	_force(copy)
	for _i in 3000:
		live.step()
		copy.step()
	check.call(copy.state_hash() == live.state_hash() and copy.fire.state_ints() == live.fire.state_ints(), "the loaded tower and the original stay identical to the end of the fire")
	check.call(not FireScript.valid_ints([1, 2, 3]) and not FireScript.valid_ints([0, 0, 0, 0, 1]), "a malformed fire save is refused")
