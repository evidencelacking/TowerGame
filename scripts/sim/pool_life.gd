class_name PoolLife
extends RefCounted
## The swimming pool's day (#328, our own design, every number an unverified tunable). Pure functions of the
## room id, the tick, the minute of day and the room kinds: nothing here is saved, so a reload with the same
## tower gives the same answer, and the view reads it to show the pool's life.
##
## Open: OPEN_FROM to OPEN_TO, with a lifeguard on duty the whole time (one of the pool's four staff, names.gd).
## Cleaning: the pool is drained and scrubbed once a day. With a housekeeping station in the tower it is shut
## CLEAN_MINUTES from CLEAN_FROM (a quiet hour between the waves); without one the staff do it alone and it takes
## CLEAN_MINUTES_ALONE, which swallows the evening wave (commerce.gd skips a wave that starts while it is shut).
## Cannonball: the day is cut into slots of SLOT_TICKS ticks; in each slot a hash of the room id and the slot
## number decides, CANNONBALL_PERCENT out of 100, whether somebody leaps off the board at the slot's opening tick,
## and from which of the board's places. No clock, no rng draw: the same room and tick always give the same
## splash, so two runs agree and a reloaded tower replays it.

const RoomsScript := preload("res://scripts/sim/rooms.gd")

const KIND := "pool"
const OPEN_FROM := 360  ## 06:00.
const OPEN_TO := 1320  ## 22:00.
const CLEAN_FROM := 840  ## 14:00.
const CLEAN_MINUTES := 60
const CLEAN_MINUTES_ALONE := 240
const SWIMMERS_MAX := 8  ## Most swimmers the view draws.
const CUSTOMERS_PER_SWIMMER := 4  ## Customers served today per swimmer drawn.
const SLOT_TICKS := 24
const CANNONBALL_PERCENT := 40
const SPLASH_TICKS := 10  ## How long a splash lasts, in ticks from the jump.
const BOARD_PLACES := 3  ## Places on the diving board a jumper may leap from.
const _MASK := 0x7fffffff


## True when the tower has a housekeeping station (it shortens the pool's cleaning).
static func has_housekeeping(rooms: RoomsScript) -> bool:
	for id in rooms.room_ids():
		if rooms.kind_of(id) == "housekeeping":
			return true
	return false


## Minutes the daily cleaning shuts the pool for.
static func clean_minutes(housekeeping: bool) -> int:
	return CLEAN_MINUTES if housekeeping else CLEAN_MINUTES_ALONE


## True while the pool is shut for its daily cleaning.
static func is_cleaning(minute: int, housekeeping: bool) -> bool:
	return minute >= CLEAN_FROM and minute < CLEAN_FROM + clean_minutes(housekeeping)


## True between the opening and closing hours and not while it is being cleaned.
static func is_open(minute: int, housekeeping: bool) -> bool:
	return minute >= OPEN_FROM and minute < OPEN_TO and not is_cleaning(minute, housekeeping)


## True while the lifeguard sits in the chair: the opening hours, cleaning included (a drained pool still has a guard).
static func lifeguard_on_duty(minute: int) -> bool:
	return minute >= OPEN_FROM and minute < OPEN_TO


## The swimmers the view draws: none when shut, otherwise one per CUSTOMERS_PER_SWIMMER served today (at least one
## once anyone has come), at most SWIMMERS_MAX.
static func swimmers(customers_today: int, minute: int, housekeeping: bool) -> int:
	if customers_today <= 0 or not is_open(minute, housekeeping):
		return 0
	return clampi(customers_today / CUSTOMERS_PER_SWIMMER, 1, SWIMMERS_MAX)


static func _mix(room: int, slot: int) -> int:
	var h := (room * 73856093 + slot * 19349663 + 40503) & _MASK
	h = ((h ^ (h >> 15)) * 2246822519) & _MASK
	return (h ^ (h >> 13)) & _MASK


## Ticks since the cannonball of this slot (0 at the jump) while its splash lasts, or -1 for none. The jump happens
## at the slot's opening tick, so the same tick gives the same answer on every run.
static func cannonball_age(room: int, tick: int) -> int:
	if tick < 0 or room <= 0:
		return -1
	var age := tick % SLOT_TICKS
	if age >= SPLASH_TICKS:
		return -1
	if _mix(room, tick / SLOT_TICKS) % 100 >= CANNONBALL_PERCENT:
		return -1
	return age


## Which of the board's places (0 to BOARD_PLACES - 1) the jumper of the splash at this tick leaps from.
static func jump_place(room: int, tick: int) -> int:
	return (_mix(room, tick / SLOT_TICKS) / 100) % BOARD_PLACES
