extends RefCounted
## Elevator car motion in integer ticks (4.4). A car is [shaft id, home, floor, load, state, dir,
## target, ticks left] in Rooms; this runs its state machine once per tick. Rooms.send_car gives
## a car a target (dispatch, #93, will call it). Deterministic: integers only, no randomness.
##
## The clock runs 2.5 ticks per sim minute, so TICKS_PER_FLOOR 1 makes a 10-floor trip 10 ticks
## (4 sim minutes) and a full stop's doors take 8 ticks (3.2 minutes).

const IDLE := 0
const MOVING := 1
const DOORS_OPENING := 2
const DOORS_OPEN := 3
const DOORS_CLOSING := 4

# Timing in ticks. All unverified, tune by play.
const TICKS_PER_FLOOR := 1  # per floor passed, stops or not, unverified, tune by play
const DOOR_OPEN_TICKS := 2  # unverified, tune by play
const DOOR_HOLD_TICKS := 4  # unverified, tune by play
const DOOR_CLOSE_TICKS := 2  # unverified, tune by play

# Indices into a car array.
const SHAFT := 0
const HOME := 1
const FLOOR := 2
const LOAD := 3
const STATE := 4
const DIR := 5
const TARGET := 6
const TICKS := 7


## Position of a floor on one line (there is no floor 0): basements are 0 and below.
static func _level(floor_number: int) -> int:
	return floor_number if floor_number > 0 else floor_number + 1


static func _next(floor_number: int, dir: int) -> int:
	if dir > 0:
		return 1 if floor_number == -1 else floor_number + 1
	return -1 if floor_number == 1 else floor_number - 1


## Gives an idle car a target (a stop; Rooms.send_car checks). Its own floor just cycles the doors.
static func start(car: Array, target: int) -> void:
	car[TARGET] = target
	if car[FLOOR] == target:
		car[STATE] = DOORS_OPENING
		car[DIR] = 0
		car[TICKS] = DOOR_OPEN_TICKS
		return
	car[STATE] = MOVING
	car[DIR] = 1 if _level(target) > _level(car[FLOOR]) else -1
	car[TICKS] = TICKS_PER_FLOOR


## Runs every car one tick.
static func tick(rooms: RefCounted) -> void:
	for car: Array in rooms._cars:
		var state: int = car[STATE]
		if state == IDLE:
			continue
		car[TICKS] -= 1
		if car[TICKS] > 0:
			continue
		match state:
			MOVING:
				car[FLOOR] = _next(car[FLOOR], car[DIR])
				if car[FLOOR] != car[TARGET]:
					car[TICKS] = TICKS_PER_FLOOR
				elif rooms.is_stop(car[SHAFT], car[FLOOR]):
					car[STATE] = DOORS_OPENING
					car[DIR] = 0
					car[TICKS] = DOOR_OPEN_TICKS
				else:
					_idle(car)
			DOORS_OPENING:
				car[STATE] = DOORS_OPEN
				car[TICKS] = DOOR_HOLD_TICKS
			DOORS_OPEN:
				car[STATE] = DOORS_CLOSING
				car[TICKS] = DOOR_CLOSE_TICKS
			_:
				_idle(car)


static func _idle(car: Array) -> void:
	car[STATE] = IDLE
	car[DIR] = 0
	car[TARGET] = 0
	car[TICKS] = 0
