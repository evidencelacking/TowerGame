extends RefCounted
## Hotel tests (6.2): single, twin and suite. One night: check in 18:00 to 23:00, sleep, check out
## 7:00 to 10:00, pay once, turn dirty. A guest who cannot reach the room leaves with a complaint.
## A suite needs a parking space. Prices, hours and capacities are tunables (see hotel.gd).

const TowerSim := preload("res://scripts/sim/tower.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const HotelScript := preload("res://scripts/sim/hotel.gd")
const LedgerScript := preload("res://scripts/sim/ledger.gd")
const Complaints := preload("res://scripts/sim/complaints.gd")
const Messages := preload("res://scripts/sim/messages.gd")
const RoomInfo := preload("res://scripts/view/room_info.gd")
const Finance := preload("res://scripts/sim/finance.gd")
const TestTenancy := preload("res://tests/test_tenancy.gd")
const TestOfficeDay := preload("res://tests/test_office_day.gd")
const Harness := preload("res://tests/harness.gd")

const PARKING_ID := 5000
const MAX_TICKS := 6000  ## Longer than any stretch the tests step: a bound so no loop can hang.


## Lobby on floors 1-2, floor 3 above it, one hotel room of the kind on floor 3; stairs when linked.
static func _tower(seed_value: int, kind: String, linked: bool, parking: bool = false) -> TowerSim:
	var t := TowerSim.new(seed_value, 100000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 131, 2)
	t.floors.fill_span(3, 100, 131)
	t.rooms.place_room(t.grid, t.floors, t.ledger, 0, CatalogueScript.IDS.find(kind), 3, 110)
	if linked:
		TestTenancy._link(t)
	if parking:
		t.grid.place(PARKING_ID, 3, 124, CatalogueScript.field("parking_space", "width"))
		t.rooms._kind_of[PARKING_ID] = CatalogueScript.IDS.find("parking_space")
	return t


static func _room(t: TowerSim) -> int:
	return t.rooms.room_ids()[0]


## Puts the clock at the minute of the day and sets the tower's tick to match.
static func _jump(t: TowerSim, minute: int, day: int) -> void:
	var at := TestOfficeDay._tick_at(minute, day)
	t.tick = at
	t.clock.set_to_tick(at)


## Steps until the clock first shows the minute on the day (bounded; fails the caller's checks if never reached).
static func _step_to(t: TowerSim, minute: int, day: int) -> void:
	var target := TestOfficeDay._tick_at(minute, day)
	var guard := 0
	while t.tick < target and guard < MAX_TICKS:
		t.step()
		guard += 1


static func _hotel_lines(t: TowerSim) -> Array:
	var found: Array = []
	for line: Array in t.ledger.lines:
		if line[2] == LedgerScript.HOTEL:
			found.append(line)
	return found


static func _peak_stress(t: TowerSim) -> int:
	var peak := 0
	for i in t.people.count():
		peak = maxi(peak, t.people.stress_of(i))
	return peak


## Runs the evening of day 0 from 17:00 to 23:30. Returns the tower if the room was booked, with
## meta = [minute the guests checked in, peak guest stress seen]; null if no one booked on this seed.
static func _evening(seed_value: int, kind: String, linked: bool, parking: bool, meta: Array) -> TowerSim:
	var t := _tower(seed_value, kind, linked, parking)
	_jump(t, 17 * 60, 0)
	var room := _room(t)
	var first := -1
	var peak := 0
	var target := TestOfficeDay._tick_at(23 * 60 + 30, 0)
	var guard := 0
	while t.tick < target and guard < MAX_TICKS:
		t.step()
		guard += 1
		peak = maxi(peak, _peak_stress(t))
		if first < 0 and t.hotel.state_of(room) != HotelScript.VACANT:
			first = t.clock.minute_of_day()
	if first < 0:
		return null
	meta.append(first)
	meta.append(peak)
	return t


## The first seed from 1 to 40 on which the room is booked that evening, or null.
static func _booked(kind: String, linked: bool, parking: bool, meta: Array) -> TowerSim:
	for seed_value in range(1, 41):
		meta.clear()
		var t := _evening(seed_value, kind, linked, parking, meta)
		if t != null:
			return t
	return null


static func run(check: Callable) -> void:
	# Catalogue data: capacities 1/2/2, default nightly prices, suites flagged and needing parking.
	check.call(CatalogueScript.field("hotel_single", "people") == 1 and CatalogueScript.field("hotel_twin", "people") == 2 and CatalogueScript.field("hotel_suite", "people") == 2, "hotel capacities are 1, 2 and 2")
	var plain := _tower(1, "hotel_single", true)
	check.call(plain.hotel.price(_room(plain)) == 2000, "a single costs $2,000 a night at the default level")
	var twin_tower := _tower(1, "hotel_twin", true)
	var suite_tower := _tower(1, "hotel_suite", true)
	check.call(twin_tower.hotel.price(_room(twin_tower)) == 4000 and suite_tower.hotel.price(_room(suite_tower)) == 8000, "a twin is $4,000 and a suite $8,000 a night")
	var suite_id := _room(suite_tower)
	var listed: Array[int] = [suite_id]
	check.call(suite_tower.hotel.is_suite(suite_id) and suite_tower.hotel.suites() == listed and plain.hotel.suites().is_empty(), "suites are flagged and listed for the VIP task")
	check.call(bool(CatalogueScript.field("hotel_suite", "needs_parking")) and not bool(CatalogueScript.field("hotel_single", "needs_parking")), "only the suite needs parking")
	check.call(plain.hotel.capacity(_room(plain)) == 1 and twin_tower.hotel.capacity(_room(twin_tower)) == 2, "capacity reads the catalogue")

	# One night, single room: check in 18:00 to 23:00, sleep, check out 7:00 to 10:00, pay once, dirty.
	var meta: Array = []
	var t := _booked("hotel_single", true, false, meta)
	check.call(t != null, "a single room is booked on some night")
	if t == null:
		return
	var room := _room(t)
	check.call(meta[0] >= HotelScript.CHECK_IN_FROM and meta[0] <= HotelScript.CHECK_IN_TO, "guests check in between 18:00 and 23:00")
	check.call(t.hotel.state_of(room) == HotelScript.STAYING and t.population() == 1, "by 23:30 the guest is in the room and counts toward population")
	check.call(t.people.home_of(0) == room and t.people.location_of(0) == room, "the guest is in their room")
	check.call(_hotel_lines(t).is_empty(), "nothing is paid before check-out")
	_step_to(t, 3 * 60, 1)
	check.call(t.hotel.state_of(room) == HotelScript.STAYING and t.population() == 1 and t.people.location_of(0) == room, "the guest stays the night")
	_step_to(t, 6 * 60 + 30, 1)
	check.call(t.hotel.state_of(room) == HotelScript.STAYING and _hotel_lines(t).is_empty(), "nobody checks out before 7:00")
	check.call(not t.hotel.is_dirty(room) and t.hotel.dirty_since(room) == -1, "an occupied room is not dirty")
	var left_at := -1
	var left_tick := -1
	var target := TestOfficeDay._tick_at(10 * 60 + 30, 1)
	var guard := 0
	while t.tick < target and guard < MAX_TICKS:
		t.step()
		guard += 1
		if left_at < 0 and t.hotel.state_of(room) == HotelScript.VACANT:
			left_at = t.clock.minute_of_day()
			left_tick = t.tick
	check.call(left_at >= HotelScript.CHECK_OUT_FROM and left_at < HotelScript.CHECK_OUT_TO + 5, "guests check out between 7:00 and 10:00")
	var lines := _hotel_lines(t)
	check.call(lines.size() == 1 and lines[0][1] == 2000 and lines[0][3] == room, "one check-out pays $2,000 into the ledger under the hotel kind, referencing the room")
	check.call(t.people.count() == 0 and t.population() == 0, "the guest has gone")
	check.call(t.hotel.is_dirty(room) and t.hotel.dirty_since(room) == left_tick, "the room turned dirty at check-out (dirty-since tick)")
	check.call(int(Finance.totals(t.ledger, Finance.quarter_of(left_tick)).get(LedgerScript.HOTEL, 0)) == 2000, "the finance report shows the hotel income by kind")
	var dirty_logged := 0
	for i in t.messages.count():
		if t.messages.entry(i)[1] == Messages.ROOM_DIRTY and t.messages.entry(i)[2] == room:
			dirty_logged += 1
	check.call(dirty_logged == 1, "check-out logs the room as dirty once")
	var info := RoomInfo.describe(t, room)
	check.call(info["dirty"] and "
".join(RoomInfo.lines_for(info)).contains("Dirty"), "the room window shows a dirty room")
	var balance := t.ledger.balance
	_step_to(t, 12 * 60, 1)
	check.call(t.hotel.is_dirty(room), "with no housekeeping station nothing cleans the room: it is still dirty at midday")
	check.call(_hotel_lines(t).size() == 1 and t.ledger.balance == balance, "income was posted once, not again")

	# The dirty hook: a dirty room takes no guests; marking it clean frees it (the control: a clean twin books).
	var d := _tower(3, "hotel_single", true)
	var dirty_room := _room(d)
	d.hotel._records[dirty_room] = [HotelScript.VACANT, -1, -1, 420, -1, 0, 77, 0] as Array[int]
	check.call(d.hotel.is_dirty(dirty_room) and d.hotel.dirty_since(dirty_room) == 77, "dirty_since reads the tick")
	_jump(d, 18 * 60, 0)
	_step_to(d, 23 * 60 + 30, 0)
	check.call(d.hotel.state_of(dirty_room) == HotelScript.VACANT and d.people.count() == 0 and d.hotel.is_dirty(dirty_room), "a dirty room takes no guests")
	d.hotel.mark_clean(dirty_room)
	check.call(not d.hotel.is_dirty(dirty_room), "mark_clean clears dirty")
	var info_d := RoomInfo.describe(d, dirty_room)
	check.call(not info_d["dirty"] and not "
".join(RoomInfo.lines_for(info_d)).contains("Dirty"), "a cleaned room is no longer shown dirty")

	# Rent level sets the nightly price.
	var priced := _tower(1, "hotel_single", true)
	priced.rent.set_rent(priced.rooms, _room(priced), 3)
	check.call(priced.hotel.price(_room(priced)) == 3000, "the highest rent level raises the nightly price")

	# Twin: two guests, $4,000.
	var twin := _booked("hotel_twin", true, false, meta)
	check.call(twin != null and twin.people.count() == 2 and twin.population() == 2, "a twin takes two guests")
	if twin != null:
		_step_to(twin, 11 * 60, 1)
		var twin_lines := _hotel_lines(twin)
		check.call(twin_lines.size() == 1 and twin_lines[0][1] == 4000 and twin.people.count() == 0, "a twin pays $4,000 once, for the room")

	# Suite: no parking space, no guests; with one, $8,000 and the space is held for the night.
	var no_park := _booked("hotel_suite", true, false, meta)
	check.call(no_park == null, "a suite without a parking space never rents (the same seeds rent with one)")
	var suite := _booked("hotel_suite", true, true, meta)
	check.call(suite != null and suite.people.count() == 2 and suite.hotel.parking_free() == 0, "a suite with a parking space rents to two guests and holds the space")
	if suite != null:
		_step_to(suite, 11 * 60, 1)
		var suite_lines := _hotel_lines(suite)
		check.call(suite_lines.size() == 1 and suite_lines[0][1] == 8000 and suite.hotel.parking_free() == 1, "a suite pays $8,000 once and frees the space")

	# No check-in after the cutoff: a tower first running at 23:10 stays empty all night.
	var late := _tower(5, "hotel_single", true)
	_jump(late, 23 * 60 + 10, 0)
	_step_to(late, 6 * 60, 1)
	check.call(late.clock.minute_of_day() >= 6 * 60 - 5 and late.people.count() == 0 and late.hotel.state_of(_room(late)) == HotelScript.VACANT, "no one checks in after 23:00")

	# Unreachable room: the guest takes stress, the room logs a complaint, the guest leaves unpaid.
	var cut := _booked("hotel_single", false, false, meta)
	check.call(cut != null, "an unconnected room is still booked")
	if cut != null:
		var cut_room := _room(cut)
		check.call(int(meta[1]) >= 30, "the guest took stress for failing to reach the room")
		_step_to(cut, 2 * 60, 1)
		check.call(cut.hotel.state_of(cut_room) == HotelScript.VACANT and cut.people.count() == 0, "the guest who cannot reach the room leaves")
		check.call(cut.hotel.unreached(cut_room) and cut.complaint_reason(cut_room) == Complaints.UNREACHED, "the room logs an unreachable complaint")
		check.call(_hotel_lines(cut).is_empty() and not cut.hotel.is_dirty(cut_room), "an unreachable guest pays nothing and leaves the room clean")
		var logged := false
		for i in cut.messages.count():
			logged = logged or cut.messages.entry(i)[1] == Messages.GUEST_UNREACHED
		check.call(logged, "the failed arrival is logged")

	# Save and load mid-stay resumes exactly.
	var mid := _booked("hotel_twin", true, false, meta)
	check.call(mid != null, "a twin is booked for the save test")
	if mid != null:
		var copy := Harness.clone_via_save(mid)
		check.call(copy != null and copy.state_hash() == mid.state_hash(), "a mid-stay save loads to the same state")
		if copy != null:
			Harness.step(mid, 400)
			Harness.step(copy, 400)
			check.call(copy.state_hash() == mid.state_hash(), "a loaded hotel keeps running identically")
