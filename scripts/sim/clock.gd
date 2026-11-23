extends RefCounted
## The in-game clock. Integers only; see CLAUDE.md.
##
## A day has 6 periods. Days run WD1, WD2, WE: one such week is one quarter, and 4 quarters
## (12 days) are one year. The start state is 5:00, period 1, WD1, Q1, year 1.
## advance() moves one tick; Tower._run_systems() calls it once per tick.

const PERIODS := 6
const DAYS_PER_QUARTER := 3
const QUARTERS_PER_YEAR := 4
const MINUTES_PER_DAY := 1440
const WD1 := 0
const WD2 := 1
const WE := 2

# Per-period length in ticks. All unverified, tune by play.
# Night periods are fast (few ticks), rush hours slow (many ticks).
const PERIOD_1_TICKS := 600  # morning rush, unverified, tune by play
const PERIOD_2_TICKS := 300  # morning, unverified, tune by play
const PERIOD_3_TICKS := 600  # lunch rush, unverified, tune by play
const PERIOD_4_TICKS := 300  # afternoon, unverified, tune by play
const PERIOD_5_TICKS := 600  # evening rush, unverified, tune by play
const PERIOD_6_TICKS := 150  # night, unverified, tune by play

# In-game minute since midnight at which each period starts. Each period runs to the next
# one's start; period 6 runs to period 1 of the next day. Unverified, tune by play.
const PERIOD_1_START := 300  # 5:00, the day start (owner decision)
const PERIOD_2_START := 540  # 9:00, unverified, tune by play
const PERIOD_3_START := 660  # 11:00, unverified, tune by play
const PERIOD_4_START := 840  # 14:00, unverified, tune by play
const PERIOD_5_START := 1020  # 17:00, unverified, tune by play
const PERIOD_6_START := 1260  # 21:00, unverified, tune by play

## Set on the single tick a quarter begins (WD1 starts), cleared on the next advance().
## Rent and WD1-only systems read it. It is not set in the start state.
var quarter_started: bool = false
## Set on the single tick a day begins (a new WD1, WD2 or WE; the tick a quarter begins is also one),
## cleared on the next advance(). Derived each tick, so it is not saved or hashed.
var day_started: bool = false

var _period: int = 0  # 0-based internally; period() is 1-based
var _ticks_in_period: int = 0
var _day: int = WD1
var _quarter: int = 0  # 0-based internally; quarter() is 1-based
var _year: int = 1


## Advances one tick, rolling period, day, quarter and year over as needed.
func advance() -> void:
	quarter_started = false
	day_started = false
	_ticks_in_period += 1
	if _ticks_in_period < period_ticks(_period):
		return
	_ticks_in_period = 0
	_period += 1
	if _period < PERIODS:
		return
	_period = 0
	_day += 1
	day_started = true
	if _day < DAYS_PER_QUARTER:
		return
	_day = WD1
	_quarter += 1
	if _quarter >= QUARTERS_PER_YEAR:
		_quarter = 0
		_year += 1
	quarter_started = true


## The current period, 1 to 6.
func period() -> int:
	return _period + 1


## The day of the quarter: WD1, WD2 or WE.
func day_of_week() -> int:
	return _day


## The quarter of the year, 1 to 4.
func quarter() -> int:
	return _quarter + 1


## The year, starting at 1.
func year() -> int:
	return _year


## Ticks elapsed in the current period.
func ticks_in_period() -> int:
	return _ticks_in_period


## In-game minutes since midnight, 0 to 1,439, derived from the tick position in the period.
func minute_of_day() -> int:
	return _minute_at(_period, _ticks_in_period)


## In-game minutes since midnight at a position in a period (see minute_of_day).
static func _minute_at(period_index: int, ticks_in: int) -> int:
	var start := period_start(period_index)
	var span := posmod(period_start(period_index + 1) - start, MINUTES_PER_DAY)  # posmod: the night period wraps past midnight, and % would go negative
	if span == 0:
		span = MINUTES_PER_DAY
	return (start + ticks_in * span / period_ticks(period_index)) % MINUTES_PER_DAY


## Sim minutes that passed over the last `ticks` ticks, read from the clock alone (no history kept), so it is the same
## after a save and load. Slow systems (#459) use it to count a whole cadence's minutes in one run.
func minutes_over_last(ticks: int) -> int:
	var period_index := _period
	var ticks_in := _ticks_in_period - ticks
	while ticks_in < 0:
		period_index = (period_index + PERIODS - 1) % PERIODS
		ticks_in += period_ticks(period_index)
	return posmod(minute_of_day() - _minute_at(period_index, ticks_in), MINUTES_PER_DAY)


## Ticks until the clock next reaches a minute of the day (at least 1; a full day when it is the
## minute now). Works on a copy, so the clock is untouched.
func ticks_until_minute(target: int) -> int:
	var copy: Object = get_script().new()
	copy.load_ints(state_ints())
	var need := posmod(target - minute_of_day(), MINUTES_PER_DAY)
	if need == 0:
		need = MINUTES_PER_DAY
	var seen := 0
	var last := minute_of_day()
	var ticks := 0
	while seen < need and ticks < 4 * MINUTES_PER_DAY:  # a day is 2,550 ticks, so this always ends first
		copy.advance()
		ticks += 1
		var now: int = copy.minute_of_day()
		seen += posmod(now - last, MINUTES_PER_DAY)
		last = now
	return ticks


## The in-game hour, 0 to 23.
func hour() -> int:
	return minute_of_day() / 60


## The in-game minute within the hour, 0 to 59.
func minute() -> int:
	return minute_of_day() % 60


## Length of a 0-based period in ticks.
static func period_ticks(index: int) -> int:
	match index:
		0: return PERIOD_1_TICKS
		1: return PERIOD_2_TICKS
		2: return PERIOD_3_TICKS
		3: return PERIOD_4_TICKS
		4: return PERIOD_5_TICKS
		_: return PERIOD_6_TICKS


## Start minute of a 0-based period; index PERIODS wraps to the next day's period 1.
static func period_start(index: int) -> int:
	match index:
		0: return PERIOD_1_START
		1: return PERIOD_2_START
		2: return PERIOD_3_START
		3: return PERIOD_4_START
		4: return PERIOD_5_START
		5: return PERIOD_6_START
		_: return PERIOD_1_START


## The clock as it stands after ticks advance() calls from the start, without replaying them. quarter_started is left clear.
func set_to_tick(count: int) -> void:
	var ticks := maxi(count, 0)
	var day_ticks := 0
	for p in PERIODS:
		day_ticks += period_ticks(p)
	var days := ticks / day_ticks
	var left := ticks % day_ticks
	var index := 0
	while left >= period_ticks(index):
		left -= period_ticks(index)
		index += 1
	load_ints([index, left, days % DAYS_PER_QUARTER, (days / DAYS_PER_QUARTER) % QUARTERS_PER_YEAR, 1 + days / (DAYS_PER_QUARTER * QUARTERS_PER_YEAR), 0] as Array[int])


## State for hashing and saving, in a fixed order.
func state_ints() -> Array[int]:
	return [_period, _ticks_in_period, _day, _quarter, _year, 1 if quarter_started else 0]


## Restores state_ints(). Returns false, changing nothing, if the array is the wrong shape
## or holds a value out of range.
func load_ints(ints: Array) -> bool:
	if not valid_ints(ints):
		return false
	_period = ints[0]
	_ticks_in_period = ints[1]
	_day = ints[2]
	_quarter = ints[3]
	_year = ints[4]
	quarter_started = ints[5] != 0
	return true


## Whether ints is a state_ints() result that load_ints() would accept.
static func valid_ints(ints: Array) -> bool:
	if ints.size() != 6:
		return false
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	return (
		ints[0] >= 0 and ints[0] < PERIODS
		and ints[1] >= 0 and ints[1] < period_ticks(ints[0])
		and ints[2] >= 0 and ints[2] < DAYS_PER_QUARTER
		and ints[3] >= 0 and ints[3] < QUARTERS_PER_YEAR
		and ints[4] >= 1
		and (ints[5] == 0 or ints[5] == 1)
	)
