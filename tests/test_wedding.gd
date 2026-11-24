extends RefCounted
## The top-rank wedding (M11 11.5, #33): the gate needs every part, the wedding sets itself for the next weekend and holds on
## its midday, guests must arrive, a fire or a lost cathedral calls it off for a retry, success sets a saved flag once, and
## the ceremony state survives a save and load with the same hash.

const TowerSim := preload("res://scripts/sim/tower.gd")
const FixtureTower := preload("res://tests/star_fixture_tower.gd")
const Wedding := preload("res://scripts/sim/wedding.gd")
const Rules := preload("res://scripts/sim/star_rules.gd")
const Clock := preload("res://scripts/sim/clock.gd")
const Messages := preload("res://scripts/sim/messages.gd")

const DAY_TICKS := 2550
const WE_START := 2 * DAY_TICKS  ## First tick of the first quarter's weekend.
const GATE := {"population": 15000, "cathedral": true}


static func _tower(fixture: Dictionary = GATE, stars: int = 5) -> FixtureTower:
	var t := FixtureTower.new(7, 1000000)
	t.stars = stars
	t.star_fixture = fixture.duplicate()
	return t


static func _count(t: TowerSim, code: int) -> int:
	var n := 0
	for i in t.messages.count():
		if t.messages.entry(i)[1] == code:
			n += 1
	return n


## The newest message with this code, or an empty array.
static func _last(messages: Messages, code: int) -> Array:
	var found: Array = []
	for i in messages.count():
		if messages.entry(i)[1] == code:
			found = messages.entry(i)
	return found


static func _step_to(t: TowerSim, target: int) -> void:
	while t.tick < target:
		t.step()


## Puts the clock `before` ticks ahead of the target and steps up to it, so a day start is crossed by stepping.
static func _jump(t: TowerSim, target: int, before: int = 5) -> void:
	t.tick = target - before
	t.clock.set_to_tick(target - before)
	_step_to(t, target)


static func run(check: Callable) -> void:
	_gate(check)
	_schedule_and_success(check)
	_called_off(check)
	_guests(check)
	_after_success(check)
	_saving(check)


static func _gate(check: Callable) -> void:
	check.call(Rules.meets_top_rank({"stars": 5, "population": 15000, "cathedral": true}), "wedding: five stars, 15,000 and a cathedral open the gate")
	check.call(not Rules.meets_top_rank({"stars": 4, "population": 15000, "cathedral": true}), "wedding: four stars do not")
	check.call(not Rules.meets_top_rank({"stars": 5, "population": 14999, "cathedral": true}), "wedding: 14,999 people do not")
	check.call(not Rules.meets_top_rank({"stars": 5, "population": 15000, "cathedral": false}), "wedding: no reached, unburned cathedral does not")
	check.call(not Rules.meets_top_rank({"stars": 5, "population": 15000}), "wedding: a missing cathedral fact counts as false")
	# In a tower: each missing part keeps the wedding unset, with the checks running.
	for case: Array in [[{"population": 14999, "cathedral": true}, 5], [{"population": 15000, "cathedral": false}, 5], [GATE, 4]]:
		var t := _tower(case[0], case[1])
		_step_to(t, 100)
		check.call(not t.wedding.is_scheduled() and _count(t, Messages.WEDDING_SET) == 0, "wedding: a tower missing a gate part sets nothing (%s, %d stars)" % [str(case[0]), case[1]])
	var full := _tower()
	_step_to(full, 100)
	check.call(full.wedding.is_scheduled(), "wedding: the same tower with every part sets it (the others are really blocked by their part)")
	# The real cathedral test: no cathedral in the tower, so the gate is shut.
	var bare := TowerSim.new(7, 1000000)
	check.call(not bare.cathedral_ready() and not bare.star_facts()["cathedral"], "wedding: a tower with no cathedral is not ready")


static func _schedule_and_success(check: Callable) -> void:
	var t := _tower()
	_step_to(t, 40)
	check.call(t.wedding.is_scheduled() and _count(t, Messages.WEDDING_SET) == 1, "wedding: when the gate holds it sets itself and posts one notice")
	var note := _last(t.messages, Messages.WEDDING_SET)
	check.call(note[2] == 1 and note[3] == 1, "wedding: set for the first quarter's weekend, year 1")
	_step_to(t, 400)
	check.call(_count(t, Messages.WEDDING_SET) == 1, "wedding: the notice is posted once, not on every check")
	_jump(t, 2 * DAY_TICKS - 100, 5)
	check.call(t.wedding.is_scheduled() and not t.wedding.is_day(), "wedding: it does not start on a weekday")
	_jump(t, WE_START + 20, 25)
	check.call(t.wedding.is_day() and not t.wedding.top_rank(), "wedding: the weekend day begins the wedding day")
	_jump(t, WE_START + 905, 10)  # 11:00
	check.call(t.wedding.arrived() < 5, "wedding: guests have only started to arrive at 11:00")
	_step_to(t, WE_START + 1100)  # midday
	check.call(t.wedding.arrived() >= Wedding.MIN_GUESTS and t.wedding.is_day() and not t.wedding.top_rank(), "wedding: by midday the guests are in and the ceremony is on")
	_step_to(t, WE_START + 1250)
	check.call(t.wedding.is_day() and not t.wedding.top_rank(), "wedding: the ceremony lasts 60 minutes, so it is still on at 12:40")
	_step_to(t, WE_START + 1420)
	check.call(t.wedding.top_rank() and not t.wedding.is_day() and _count(t, Messages.WEDDING_DONE) == 1, "wedding: success sets the top-rank flag and posts the celebration")
	check.call(t.stars == 5, "wedding: the game goes on (nothing ends, the stars stay)")


static func _called_off(check: Callable) -> void:
	# A fire on the day calls it off; the next check sets it for the next weekend (quarter 2).
	var t := _tower()
	_step_to(t, 40)
	_jump(t, WE_START + 20, 25)
	_jump(t, WE_START + 960, 10)  # about 11:30
	check.call(t.wedding.is_day() and t.wedding.arrived() > 0, "wedding (fire): the day is on with guests arriving")
	t.fire_fixture = true
	t.step()
	var off := _last(t.messages, Messages.WEDDING_CALLED_OFF)
	check.call(not t.wedding.is_day() and _count(t, Messages.WEDDING_CALLED_OFF) == 1 and off[2] == Wedding.CALLED_OFF_FIRE, "wedding (fire): a fire calls the wedding off with a message")
	check.call(not t.wedding.top_rank() and t.wedding.failed_count() == 1, "wedding (fire): no top rank, one failed day counted")
	t.fire_fixture = false
	_step_to(t, t.tick + 40)
	var again := _last(t.messages, Messages.WEDDING_SET)
	check.call(t.wedding.is_scheduled() and _count(t, Messages.WEDDING_SET) == 2 and again[2] == 2 and again[3] == 1, "wedding (fire): it is set again for the next quarter's weekend, not today")
	# The cathedral lost on the day calls it off too.
	var u := _tower()
	_step_to(u, 40)
	_jump(u, WE_START + 20, 25)
	u.star_fixture["cathedral"] = false
	_step_to(u, u.tick + 3)
	var lost := _last(u.messages, Messages.WEDDING_CALLED_OFF)
	check.call(not u.wedding.is_day() and _count(u, Messages.WEDDING_CALLED_OFF) == 1 and lost[2] == Wedding.CALLED_OFF_CATHEDRAL, "wedding (cathedral): a cathedral cut off or burned calls it off")


## Drives a lone Wedding over the first weekend with the lobby crowded for the first `blocked` minutes of the arrival window,
## and a fire from `fire_at_minute` of the weekend (-1: none).
static func _lone_day(blocked: int, fire_at_minute: int = -1) -> Dictionary:
	var clock := Clock.new()
	var messages := Messages.new()
	var w := Wedding.new()
	clock.set_to_tick(DAY_TICKS)  # weekday 2, the start of the day
	w.check(true, clock, messages, 0)
	var guard := 0
	while guard < 4 * DAY_TICKS and not (clock.day_of_week() == Clock.WE and clock.minute_of_day() >= Wedding.CEREMONY_START + 120):
		guard += 1
		clock.advance()
		var minute := clock.minute_of_day()
		var weekend := clock.day_of_week() == Clock.WE
		var crowd := 100 if weekend and minute >= Wedding.ARRIVE_START and minute < Wedding.ARRIVE_START + blocked else 0
		var fire := fire_at_minute >= 0 and weekend and minute >= fire_at_minute
		w.tick(clock, fire, true, crowd, messages, guard)
	return {"w": w, "messages": messages, "ended": guard < 4 * DAY_TICKS}


static func _guests(check: Callable) -> void:
	var full := _lone_day(0)
	check.call(full["ended"] and full["w"].top_rank(), "wedding (guests): with the lobby clear all guests arrive and it succeeds")
	var edge := _lone_day(30)
	check.call(edge["w"].top_rank(), "wedding (guests): exactly the minimum, %d, arriving is enough" % Wedding.MIN_GUESTS)
	var short := _lone_day(32)
	var w: Wedding = short["w"]
	var failed := _last(short["messages"], Messages.WEDDING_FAILED)
	check.call(not w.top_rank() and w.failed_count() == 1 and not failed.is_empty() and failed[2] == Wedding.MIN_GUESTS - 1 and failed[3] == Wedding.MIN_GUESTS, "wedding (guests): one guest short fails with a hint message and no top rank")
	var jam := _lone_day(60)
	check.call(not jam["w"].top_rank() and jam["w"].failed_count() == 1, "wedding (guests): a jammed lobby turns every guest away and it fails")
	var fire := _lone_day(0, Wedding.ARRIVE_START + 10)
	check.call(not fire["w"].top_rank() and fire["w"].failed_count() == 1 and not _last(fire["messages"], Messages.WEDDING_CALLED_OFF).is_empty(), "wedding (guests): a fire on the day stops the ceremony")
	# A failed day is retried: the next gate check sets it again.
	var clock := Clock.new()
	w.check(true, clock, Messages.new(), 0)
	check.call(w.is_scheduled(), "wedding (guests): after a failure the next check sets it for the next weekend")


static func _after_success(check: Callable) -> void:
	var t := _tower()
	_step_to(t, 40)
	_jump(t, WE_START + 20, 25)
	_step_to(t, WE_START + 1420)
	check.call(t.wedding.top_rank(), "wedding (after): it succeeded")
	var sets := _count(t, Messages.WEDDING_SET)
	var done_state := t.wedding.state_ints()
	_jump(t, 3 * DAY_TICKS + WE_START + 1500, 40)  # on past the next quarter's weekend
	check.call(_count(t, Messages.WEDDING_SET) == sets and _count(t, Messages.WEDDING_DONE) == 1 and t.wedding.state_ints() == done_state, "wedding (after): no second wedding is set and the flag stays (idempotent)")
	t.wedding.check(true, t.clock, t.messages, t.tick)
	check.call(not t.wedding.is_scheduled(), "wedding (after): even a direct check does not set another")


static func _saving(check: Callable) -> void:
	# Mid-ceremony: save, load, and both go on the same way to the same hash.
	var a := _tower()
	_step_to(a, 40)
	_jump(a, WE_START + 20, 25)
	_step_to(a, WE_START + 1150)  # 12:10, the ceremony under way
	check.call(a.wedding.is_day() and a.wedding.arrived() >= Wedding.MIN_GUESTS, "wedding (save): a ceremony is under way to save")
	var saved := a.save()
	check.call(saved["version"] == TowerSim.SAVE_VERSION and saved.has("wedding"), "wedding (save): the save holds the ceremony block at the current version")
	var b := _tower()
	check.call(b.load_state(saved) and b.state_hash() == a.state_hash() and b.wedding.state_ints() == a.wedding.state_ints(), "wedding (save): a loaded save has the same state and hash")
	_step_to(a, WE_START + 1420)
	_step_to(b, WE_START + 1420)
	check.call(a.wedding.top_rank() and b.wedding.top_rank() and a.state_hash() == b.state_hash(), "wedding (save): both finish the wedding with the same hash")
	var c := _tower()
	check.call(c.load_state(a.save()) and c.wedding.top_rank() and c.state_hash() == a.state_hash(), "wedding (save): the top-rank flag survives a save and load")
	check.call(TowerSim.new(3).wedding.hash_ints().is_empty(), "wedding (save): an untouched wedding adds nothing to the hash")
	check.call(not Wedding.valid_ints([0, 2, 0, 0]) and not Wedding.valid_ints([3, 0, 0, 0]) and not Wedding.valid_ints([0, 0, -1, 0]) and Wedding.valid_ints(Wedding.rest_ints()), "wedding (save): bad ints are refused")
