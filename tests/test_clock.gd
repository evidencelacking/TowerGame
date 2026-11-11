extends RefCounted
## Clock tests: initial state, every rollover, the quarter-start flag, and save and load.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Clock := preload("res://scripts/sim/clock.gd")


static func _day_ticks() -> int:
	var total := 0
	for i in Clock.PERIODS:
		total += Clock.period_ticks(i)
	return total


static func _advance(clock: Clock, ticks: int) -> void:
	for _i in ticks:
		clock.advance()


static func _state(clock: Clock) -> Array[int]:
	return [clock.year(), clock.quarter(), clock.day_of_week(), clock.period(), clock.hour(), clock.minute()]


static func run(check: Callable) -> void:
	# The initial state is 5:00, period 1, WD1, Q1, year 1.
	var clock := Clock.new()
	check.call(_state(clock) == [1, 1, Clock.WD1, 1, 5, 0], "start state is year 1, Q1, WD1, period 1, 5:00")
	check.call(not clock.quarter_started, "the quarter-start flag is not set in the start state")

	# Period to period: each period lasts exactly its length, and the next one starts then.
	for p in Clock.PERIODS - 1:
		_advance(clock, Clock.period_ticks(p) - 1)
		check.call(clock.period() == p + 1, "period %d lasts to its last tick" % (p + 1))
		clock.advance()
		check.call(clock.period() == p + 2, "period %d follows period %d" % [p + 2, p + 1])
		check.call(clock.minute_of_day() == Clock.period_start(p + 1), "period %d starts at its start minute" % (p + 2))
	# The last period rolls to the next day's period 1 at 5:00.
	_advance(clock, Clock.PERIOD_6_TICKS - 1)
	check.call(clock.period() == 6 and clock.day_of_week() == Clock.WD1, "period 6 lasts to its last tick")
	clock.advance()
	check.call(_state(clock) == [1, 1, Clock.WD2, 1, 5, 0], "period 6 rolls to period 1 of WD2 at 5:00")

	# Hour and minute stay within range and never run backwards inside a period.
	var fresh := Clock.new()
	var in_range := true
	for _i in _day_ticks():
		fresh.advance()
		if fresh.hour() < 0 or fresh.hour() > 23 or fresh.minute() < 0 or fresh.minute() > 59:
			in_range = false
	check.call(in_range, "hour is 0 to 23 and minute 0 to 59 all day")
	check.call(_state(fresh) == [1, 1, Clock.WD2, 1, 5, 0], "one day of ticks returns the time to 5:00")

	# Days: WD1 to WD2 to WE to the next quarter's WD1.
	var days := Clock.new()
	_advance(days, _day_ticks())
	check.call(days.day_of_week() == Clock.WD2 and days.quarter() == 1, "WD1 is followed by WD2")
	_advance(days, _day_ticks())
	check.call(days.day_of_week() == Clock.WE and days.quarter() == 1, "WD2 is followed by WE")
	_advance(days, _day_ticks())
	check.call(_state(days) == [1, 2, Clock.WD1, 1, 5, 0], "WE is followed by WD1 of the next quarter")

	# Q4 WE rolls to year+1 Q1 WD1, and a year is exactly 12 days.
	var year := Clock.new()
	var day_changes := 0
	var last_day := year.day_of_week()
	var year_ticks := _day_ticks() * Clock.DAYS_PER_QUARTER * Clock.QUARTERS_PER_YEAR
	for _i in year_ticks - 1:
		year.advance()
		if year.day_of_week() != last_day:
			day_changes += 1
			last_day = year.day_of_week()
	check.call(_state(year).slice(0, 4) == [1, 4, Clock.WE, 6] and year.ticks_in_period() == Clock.PERIOD_6_TICKS - 1, "one tick before 12 days is the last tick of Q4 WE")
	year.advance()
	check.call(_state(year) == [2, 1, Clock.WD1, 1, 5, 0], "Q4 WE rolls to year 2, Q1, WD1")
	check.call(day_changes == 11, "a year has 12 days (11 day changes, then the year rolls)")

	# The quarter-start flag fires on the tick WD1 begins, exactly once per quarter.
	var quarters := Clock.new()
	var fires := 0
	var fire_ticks: Array[int] = []
	var quarter_ticks := _day_ticks() * Clock.DAYS_PER_QUARTER
	for t in range(1, quarter_ticks * 8 + 1):
		quarters.advance()
		if quarters.quarter_started:
			fires += 1
			fire_ticks.append(t)
	check.call(fires == 8, "the quarter-start flag fires 8 times in 2 years")
	check.call(fire_ticks == [quarter_ticks, quarter_ticks * 2, quarter_ticks * 3, quarter_ticks * 4, quarter_ticks * 5, quarter_ticks * 6, quarter_ticks * 7, quarter_ticks * 8], "the flag fires on the tick each quarter starts")
	check.call(not _fires_next_tick(quarters), "the flag is cleared on the tick after")

	# The clock runs inside the Tower: it advances with step(), is hashed, and saves and loads.
	var tower := TowerSim.new(3)
	var before := tower.state_hash()
	tower.step()
	check.call(tower.clock.ticks_in_period() == 1, "Tower.step() advances the clock one tick")
	check.call(tower.state_hash() != before, "the clock is part of the state hash")
	for _i in Clock.PERIOD_1_TICKS * 2 + 77:
		tower.step()
	var copy := TowerSim.new(0)
	check.call(copy.load_state(tower.save()), "a save with clock state loads")
	check.call(_state(copy.clock) == _state(tower.clock) and copy.state_hash() == tower.state_hash(), "a loaded tower has the saved clock and hash")
	var same := true
	for _i in quarter_ticks:
		tower.step()
		copy.step()
		if tower.state_hash() != copy.state_hash():
			same = false
	check.call(same, "a loaded tower's clock continues identically across a quarter rollover")
	var broken := tower.save()
	broken["clock"] = [1, 2]
	var untouched := tower.state_hash()
	check.call(not tower.load_state(broken) and tower.state_hash() == untouched, "a save with a malformed clock is refused and changes nothing")


static func _fires_next_tick(clock: Clock) -> bool:
	clock.advance()
	return clock.quarter_started
