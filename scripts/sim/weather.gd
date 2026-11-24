class_name Weather
extends RefCounted
## The outdoors for M9: buried treasure (#220), rain (#221) and the seasonal fly-past (#222). Integers only.
##
## Treasure: one per tower, on a fixed spot on floors B3 to B8, a pure function of the tower seed
## (spot_for) with its own salt, so nothing shifts any stream. The first floor unit built over it
## pays TREASURE_PAYS dollars once, with a notice (Tower does the paying); `treasure_found` is saved.
##
## Rain: its own PCG32 stream, seeded from the tower seed XOR SEED_SALT. When a day begins the stream
## is drawn three times, whatever the draws say: [1 day in 5] rains, for [2 to 4 periods], starting in
## a period that lets it finish inside the day. Outside visitors fall by VISITOR_CUT_PERCENT and food
## visits by FOOD_CUT_PERCENT while it rains (Commerce reads cut_percent). Hotel check-ins and tenants
## are untouched.
##
## Fly-past: no state at all. A Q4 weekend (clock) between 21:00 and 23:00 is the window in which
## the view draws a craft crossing the sky; the sim only words a notice when the window opens.
##
## Saved: the rain stream, the first and one past the last rainy period of today (0 and 0 for a dry
## day) and whether the treasure was found.

const Rng := preload("res://scripts/sim/sim_rng.gd")
const ClockScript := preload("res://scripts/sim/clock.gd")
const FloorsScript := preload("res://scripts/sim/floors.gd")

const SEED_SALT := 0x5241494E  ## "RAIN".
const TREASURE_SALT := 0x54524541  ## "TREA".
const TREASURE_PAYS := 500000  ## Dollars (owner ruling, #22).
const TREASURE_TOP := -3  ## B3, the shallowest spot.
const TREASURE_BOTTOM := -8  ## B8, the deepest.
const TREASURE_X_FROM := 100  ## The spot lies in these columns, where towers get built.
const TREASURE_X_COUNT := 200
const RAIN_ONE_DAY_IN := 5
const RAIN_MIN_PERIODS := 2
const RAIN_MAX_PERIODS := 4
const VISITOR_CUT_PERCENT := 30  ## Outside visitor arrivals fall by this while it rains.
const FOOD_CUT_PERCENT := 50  ## Food (restaurant, fast food) arrivals fall by this instead.
const FOOD_KINDS: Array[String] = ["restaurant", "fast_food"]
const DEFAULT_STREAM := 0  ## The stream state a migrated old save gets (save_migration.gd, v46 to v47).
const FLYPAST_QUARTER := 4
const FLYPAST_FROM := 1260  ## 21:00.
const FLYPAST_TO := 1380  ## 23:00.

var treasure_found: bool = false
var _rng: Rng = Rng.new()
var _rain_from: int = 0  ## First rainy period of today, 0-based.
var _rain_to: int = 0  ## One past the last; equal to _rain_from for a dry day.


func reseed(tower_seed: int) -> void:
	_rng.reseed(tower_seed ^ SEED_SALT)


## The treasure's spot for a tower seed: x is the column, y the floor (-3 to -8).
static func spot_for(tower_seed: int) -> Vector2i:
	var rng: Rng = Rng.new(tower_seed ^ TREASURE_SALT)
	var depth: int = rng.next_below(TREASURE_TOP - TREASURE_BOTTOM + 1)
	var column: int = TREASURE_X_FROM + rng.next_below(TREASURE_X_COUNT)
	return Vector2i(column, TREASURE_TOP - depth)


## True once the floors hold a unit over the spot and the treasure was not yet taken.
func treasure_due(spot: Vector2i, floors: FloorsScript) -> bool:
	return not treasure_found and floors.has_floor(spot.y, spot.x)


## Run once per tick after the clock: a new day draws the rain.
func tick(clock: ClockScript) -> void:
	if not clock.day_started:
		return
	var rains: bool = _rng.next_below(RAIN_ONE_DAY_IN) == 0
	var length: int = RAIN_MIN_PERIODS + _rng.next_below(RAIN_MAX_PERIODS - RAIN_MIN_PERIODS + 1)
	var first: int = _rng.next_below(ClockScript.PERIODS - length + 1)
	_rain_from = first if rains else 0
	_rain_to = first + length if rains else 0


## Whether it rains in a 1-based clock period of today.
func raining_in(period: int) -> bool:
	return period - 1 >= _rain_from and period - 1 < _rain_to


func is_raining(clock: ClockScript) -> bool:
	return raining_in(clock.period())


## Percent an outside-visitor arrival count falls by in a period: 0 when dry.
func cut_percent(kind: String, period: int) -> int:
	if not raining_in(period):
		return 0
	return FOOD_CUT_PERCENT if FOOD_KINDS.has(kind) else VISITOR_CUT_PERCENT


## Count after the cut, in integers, rounded half up.
static func cut(count: int, percent: int) -> int:
	return (count * (100 - percent) + 50) / 100


## Today's rain as [first period, one past the last] (1-based, both 0 for a dry day), for the view and tests.
func rain_periods() -> Array[int]:
	if _rain_to <= _rain_from:
		return [0, 0] as Array[int]
	return [_rain_from + 1, _rain_to + 1] as Array[int]


## The sim flags the fly-past: a Q4 weekend between 21:00 and 23:00.
static func flypast_now(clock: ClockScript) -> bool:
	var minute: int = clock.minute_of_day()
	return clock.quarter() == FLYPAST_QUARTER and clock.day_of_week() == ClockScript.WE and minute >= FLYPAST_FROM and minute < FLYPAST_TO


## True on the one tick the fly-past window opens (21:00 begins period 6).
static func flypast_opens(clock: ClockScript) -> bool:
	return clock.ticks_in_period() == 0 and flypast_now(clock)


## How far across the sky the craft is, 0 to 1000, or -1 outside the window.
static func flypast_progress(clock: ClockScript) -> int:
	if not flypast_now(clock):
		return -1
	return (clock.minute_of_day() - FLYPAST_FROM) * 1000 / (FLYPAST_TO - FLYPAST_FROM)


func state_ints() -> Array[int]:
	return [_rng.state, _rain_from, _rain_to, 1 if treasure_found else 0]


## What the state hash takes: today's rain and the treasure flag, and nothing while it is dry and the treasure unfound.
## The stream is left out: it only follows the seed and the day count, so it adds no information.
func hash_ints() -> Array[int]:
	if _rain_to == _rain_from and not treasure_found:
		return [] as Array[int]
	return [_rain_from, _rain_to, 1 if treasure_found else 0] as Array[int]


static func valid_ints(ints: Array) -> bool:
	if ints.size() != 4:
		return false
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	return ints[1] >= 0 and ints[2] >= ints[1] and ints[2] <= ClockScript.PERIODS and (ints[3] == 0 or ints[3] == 1)


func load_ints(ints: Array) -> void:
	_rng.state = ints[0]
	_rain_from = ints[1]
	_rain_to = ints[2]
	treasure_found = ints[3] != 0
