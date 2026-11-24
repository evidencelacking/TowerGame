extends RefCounted
## Treasure, rain and the seasonal fly-past (M9 9.5 to 9.7, #220 to #222): the treasure spot comes from the
## tower seed and pays once, rain thins outside visitors (food most) and leaves hotel and tenants alone,
## and the sim flags the fly-past only on a Q4 weekend between 21:00 and 23:00.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const Weather := preload("res://scripts/sim/weather.gd")
const Clock := preload("res://scripts/sim/clock.gd")
const Commerce := preload("res://scripts/sim/commerce.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const Messages := preload("res://scripts/sim/messages.gd")
const TestHotel := preload("res://tests/test_hotel.gd")
const FlypastLayer := preload("res://scripts/view/flypast_layer.gd")

const DAY_TICKS := 2550
const PERIOD_6_AT := 2400  ## Ticks into a day when period 6 (21:00) begins.


static func _count(t: TowerSim, code: int) -> int:
	var n := 0
	for i in t.messages.count():
		if t.messages.entry(i)[1] == code:
			n += 1
	return n


## The newest message of a code as [tick, code, a, b], or an empty array.
static func _last(t: TowerSim, code: int) -> Array[int]:
	var i := t.messages.count() - 1
	while i >= 0:
		if t.messages.entry(i)[1] == code:
			return t.messages.entry(i)
		i -= 1
	return [] as Array[int]


## Builds a floor span through the real command, one tick.
static func _build(t: TowerSim, floor_number: int, x_from: int, x_to: int) -> void:
	t.enqueue(Command.make(t.tick + 1, Command.BUILD_FLOOR, [floor_number, x_from, x_to] as Array[int]))
	t.step()


## A tower with a lobby wide enough for the treasure columns and the floors below it dug down to just above `floor_number`.
static func _dug_to(seed_value: int, floor_number: int, column: int) -> TowerSim:
	var t := TowerSim.new(seed_value, 100000000)
	t.floors.build_lobby(t.ledger, 0, 1, 90, 310, 1)
	var f := -1
	while f > floor_number:
		_build(t, f, column - 3, column + 3)
		f -= 1
	return t


static func _treasure(check: Callable) -> void:
	var spots := {}
	var in_range := true
	for s in range(1, 40):
		var spot := Weather.spot_for(s)
		spots[spot] = true
		in_range = in_range and spot.y <= -3 and spot.y >= -8 and spot.x >= 100 and spot.x < 300
		in_range = in_range and Weather.spot_for(s) == spot
	check.call(in_range, "treasure: the spot is on B3 to B8 inside the build columns and the same for the same seed")
	check.call(spots.size() > 20, "treasure: different seeds give different spots (%d of 39)" % spots.size())

	var t := _dug_to(7, Weather.spot_for(7).y, Weather.spot_for(7).x)
	var spot := t.treasure_spot()
	check.call(spot == Weather.spot_for(7), "treasure: the tower's spot comes from its seed")
	check.call(not t.weather.treasure_found and _count(t, Messages.TREASURE_FOUND) == 0, "treasure: digging above the spot's floor finds nothing")
	var before := t.ledger.balance
	_build(t, spot.y, spot.x - 3, spot.x + 3)  # seven units, one of them the spot
	var cost := 7 * Catalogue.FLOOR_COST_PER_UNIT
	check.call(t.weather.treasure_found and t.ledger.balance == before - cost + Weather.TREASURE_PAYS, "treasure: building over the spot pays $500,000 once (net %d)" % (t.ledger.balance - before))
	var notice := _last(t, Messages.TREASURE_FOUND)
	check.call(_count(t, Messages.TREASURE_FOUND) == 1 and notice[2] == spot.y and notice[3] == Weather.TREASURE_PAYS, "treasure: one notice names the floor and the sum")

	# A second dig pays nothing.
	before = t.ledger.balance
	_build(t, spot.y - 1, spot.x - 3, spot.x + 3)  # a floor deeper, over the same column
	check.call(t.ledger.balance == before - cost and _count(t, Messages.TREASURE_FOUND) == 1, "treasure: a second dig pays nothing")

	# Save and load in between keeps it: found stays found, an unfound spot is still unfound and pays once.
	var after := TowerSim.new(0, 100000000)
	check.call(after.load_state(t.save()) and after.weather.treasure_found and after.treasure_spot() == spot, "treasure: a save after the find keeps it found, with the same spot")
	before = after.ledger.balance
	_build(after, spot.y - 2, spot.x - 3, spot.x + 3)
	check.call(after.ledger.balance == before - cost, "treasure: nothing more is paid after loading")

	var fresh := _dug_to(7, spot.y, spot.x)
	var early := TowerSim.new(0, 100000000)
	check.call(early.load_state(fresh.save()) and not early.weather.treasure_found and early.treasure_spot() == spot, "treasure: a save before the find keeps the spot (it comes from the saved seed)")
	before = early.ledger.balance
	_build(early, spot.y, spot.x - 3, spot.x + 3)
	check.call(early.ledger.balance == before - cost + Weather.TREASURE_PAYS and early.weather.treasure_found, "treasure: it pays once after the load")
	var again := TowerSim.new(0, 100000000)
	check.call(again.load_state(early.save()) and again.weather.treasure_found and again.state_hash() == early.state_hash(), "treasure: the found state round-trips and hashes the same")


static func _rain_schedule(check: Callable) -> void:
	var clock := Clock.new()
	var w := Weather.new()
	w.reseed(5)
	var twin := Weather.new()
	twin.reseed(5)
	var other := Weather.new()
	other.reseed(6)
	var rainy := 0
	var days := 1000
	var shaped := true
	var same := true
	var differs := false
	for _d in days:
		clock.day_started = true
		w.tick(clock)
		twin.tick(clock)
		other.tick(clock)
		same = same and w.state_ints() == twin.state_ints()
		differs = differs or w.state_ints() != other.state_ints()
		var span := w.rain_periods()
		if span[1] > span[0]:
			rainy += 1
			var length := span[1] - span[0]
			shaped = shaped and length >= 2 and length <= 4 and span[0] >= 1 and span[1] <= 7
	check.call(rainy >= 150 and rainy <= 250, "rain: about 1 day in 5 is wet (%d of %d)" % [rainy, days])
	check.call(shaped, "rain: it lasts 2 to 4 periods and ends inside the day")
	check.call(same and differs, "rain: the same seed rains the same days, another seed differs")
	clock.day_started = false
	var frozen := w.state_ints()
	w.tick(clock)
	check.call(w.state_ints() == frozen, "rain: nothing is drawn except when a day starts")
	check.call(Weather.cut(4, 50) == 2 and Weather.cut(6, 30) == 4 and Weather.cut(0, 50) == 0 and Weather.cut(10, 0) == 10, "rain: the cuts are integer percentages")


## Customers of a shop of this kind on a weekend with no staff, dry or with rain all day.
static func _visitor_day(kind: String, rain: bool) -> int:
	var t := TowerSim.new(42, 100000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	t.floors.fill_span(3, 100, 163)
	t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find(kind), 3, 112)
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 1, 100)
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 2, 104)
	t.clock.set_to_tick(Clock.WE * DAY_TICKS)
	if rain:
		t.weather.load_ints([t.weather.state_ints()[0], 0, 6, 0])
	var shop := -1
	for id in t.rooms.room_ids():
		if t.rooms.kind_of(id) == kind:
			shop = id
	var peak := 0
	for _i in DAY_TICKS - 100:  # stop before the day settles
		t.step()
		peak = maxi(peak, t.commerce.customers_today(shop))
	return peak


static func _visitors(check: Callable) -> void:
	var dry_of := {}
	var wet_of := {}
	for kind: String in ["fast_food", "restaurant", "retail"]:
		var dry := _visitor_day(kind, false)
		var wet := _visitor_day(kind, true)
		dry_of[kind] = dry
		wet_of[kind] = wet
		var want := 0
		for period in range(1, Clock.PERIODS + 1):
			want += Weather.cut(Commerce.visitors_for(kind, period, Clock.WE), Weather.FOOD_CUT_PERCENT if Weather.FOOD_KINDS.has(kind) else Weather.VISITOR_CUT_PERCENT)
		check.call(dry > 0 and wet < dry, "rain: %s has fewer visitors in rain (%d vs %d dry)" % [kind, wet, dry])
		check.call(wet == want, "rain: %s visitors follow the cut (%d, expected %d)" % [kind, wet, want])
	check.call((dry_of["fast_food"] - wet_of["fast_food"]) * dry_of["retail"] > (dry_of["retail"] - wet_of["retail"]) * dry_of["fast_food"], "rain: food loses a bigger share than other visitors")


## A hotel and an office with nobody in the way: rain all day changes none of the guests, tenants or takings.
static func _hotel_and_tenants(check: Callable) -> void:
	var states: Array = []
	for rain in [false, true]:
		var t := TestHotel._tower(3, "hotel_single", true)
		t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("office"), 3, 120)
		t.clock.set_to_tick(DAY_TICKS)
		t.tick = DAY_TICKS
		if rain:
			t.weather.load_ints([t.weather.state_ints()[0], 0, 6, 0])
		for _i in DAY_TICKS - 200:
			t.step()
		states.append([t.hotel.state_ints(), t.people.state_ints(), t.ledger.balance, t.people.count(), t.ledger.lines.size()])
	check.call(int(states[0][3]) > 0 and int(states[0][4]) > 1, "rain: the test tower has people (%d) and takings" % states[0][3])
	check.call(states[0][0] == states[1][0] and states[0][1] == states[1][1] and states[0][2] == states[1][2], "rain: hotel guests, tenants and money are the same as on a dry day")


static func _streams(check: Callable) -> void:
	var dry := TowerSim.new(9, 100000000)
	var wet := TowerSim.new(9, 100000000)
	wet.weather.load_ints([wet.weather.state_ints()[0], 0, 6, 0])
	for _i in DAY_TICKS:
		dry.step()
		wet.step()
	check.call(dry.events.rolls > 0 and dry.events.state_ints() == wet.events.state_ints() and dry.rng.state == wet.rng.state, "rain: the event scheduler's and the tower's streams are not shifted")
	var hot := TowerSim.new(9, 100000000)
	hot.weather.load_ints([123, 1, 4, 0])
	var back := TowerSim.new(9, 100000000)
	check.call(back.load_state(hot.save()) and back.weather.state_ints() == ([123, 1, 4, 0] as Array[int]) and back.weather.raining_in(2) and not back.weather.raining_in(5), "rain: today's rain and the stream round-trip through a save")
	var bad := hot.save()
	bad["weather"] = [1, 5, 2, 0]
	check.call(not TowerSim.new(9).load_state(bad), "rain: a save with a broken rain record is refused")
	var old := hot.save()
	old.erase("weather")
	old["version"] = 46
	old["vip"] = (old["vip"] as Array).slice(0, 9)  # the VIP block as v46 wrote it, before the notice fields (#219)
	var loaded := TowerSim.new(0, 100000000)
	check.call(loaded.load_state(old) and not loaded.weather.treasure_found and loaded.weather.rain_periods() == ([0, 0] as Array[int]), "rain: a v46 save without weather loads dry with the treasure unfound")


static func _flypast(check: Callable) -> void:
	var clock := Clock.new()
	var flagged := 0
	var opened := 0
	var exact := true
	var progress_ok := true
	var last := -1
	for _i in 2 * 12 * DAY_TICKS:  # two whole years
		clock.advance()
		var minute := clock.minute_of_day()
		var want := clock.quarter() == 4 and clock.day_of_week() == Clock.WE and minute >= 1260 and minute < 1380
		exact = exact and Weather.flypast_now(clock) == want
		if want:
			flagged += 1
			var progress := Weather.flypast_progress(clock)
			progress_ok = progress_ok and progress >= 0 and progress < 1000 and progress >= last
			last = progress
		else:
			progress_ok = progress_ok and Weather.flypast_progress(clock) == -1
			last = -1
		if Weather.flypast_opens(clock):
			opened += 1
	check.call(exact and flagged == 76, "fly-past: flagged only on a Q4 weekend from 21:00 to 23:00 (%d ticks in two years: 120 of period 6's 480 minutes is 38 of its 150 ticks a year)" % flagged)
	check.call(opened == 2 and progress_ok, "fly-past: opens once a year and crosses the sky from 0 to 999")
	var q4_weekend := Clock.new()
	q4_weekend.set_to_tick(11 * DAY_TICKS + PERIOD_6_AT)
	check.call(Weather.flypast_now(q4_weekend) and q4_weekend.quarter() == 4 and q4_weekend.day_of_week() == Clock.WE, "fly-past: the window starts at 21:00 on the Q4 weekend")
	var q3 := Clock.new()
	q3.set_to_tick(8 * DAY_TICKS + PERIOD_6_AT)
	check.call(q3.quarter() == 3 and q3.day_of_week() == Clock.WE and not Weather.flypast_now(q3), "fly-past: not on a Q3 weekend")
	var weekday := Clock.new()
	weekday.set_to_tick(10 * DAY_TICKS + PERIOD_6_AT)
	check.call(weekday.quarter() == 4 and weekday.day_of_week() != Clock.WE and not Weather.flypast_now(weekday), "fly-past: not on a Q4 weekday")

	# The view: the craft enters left of the view, leaves right of it, never goes backwards, and the layer hides outside the window.
	var xs: Array[float] = []
	for p in [0, 250, 500, 750, 999]:
		xs.append(FlypastLayer.x_in_view(p, 1000.0))
	check.call(xs[0] < 0.0 and xs[4] > 1000.0 and xs[0] < xs[1] and xs[1] < xs[2] and xs[2] < xs[3] and xs[3] < xs[4], "fly-past: the craft crosses the whole view, left to right")
	var layer := FlypastLayer.new()
	layer.follow(500, Vector2(4000, 1000), Vector2(1600, 900))
	check.call(layer.visible and layer.position.x > 3200 and layer.position.x < 4800, "fly-past: the craft is placed inside the camera's view")
	layer.follow(-1, Vector2(4000, 1000), Vector2(1600, 900))
	check.call(not layer.visible, "fly-past: the craft is hidden outside the window")
	layer.free()

	# In the tower the notice comes once, only on the Q4 weekend.
	var notices := {}
	for day in [8, 10, 11]:  # a Q3 weekend, a Q4 weekday, the Q4 weekend
		var t := TowerSim.new(2, 100000000)
		t.clock.set_to_tick(day * DAY_TICKS + PERIOD_6_AT - 5)
		for _i in 200:
			t.step()
		notices[day] = _count(t, Messages.FLYPAST)
	check.call(notices[8] == 0 and notices[10] == 0 and notices[11] == 1, "fly-past: the tower logs one notice, on the Q4 weekend only")


static func run(check: Callable) -> void:
	_treasure(check)
	_rain_schedule(check)
	_visitors(check)
	_hotel_and_tenants(check)
	_streams(check)
	_flypast(check)
