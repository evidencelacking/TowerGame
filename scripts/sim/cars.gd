extends RefCounted
## Elevator car motion in integer ticks (4.4). A car is [shaft id, home, floor, load, state, dir,
## target, ticks left, next] in Rooms; this runs its state machine once per tick. Rooms.send_car
## gives a car a target. Hall calls (#93) are [shaft id, floor, dir, car index or -1], kept in
## arrival order. Each tick the oldest unassigned call goes to the nearest car (lowest index on a
## tie) that is idle, or is moving the call's way and has not yet passed the call floor; such a
## moving car takes the call floor as an intermediate target and resumes its old target (NEXT)
## after the doors close. A call clears when its car's doors open. Deterministic: integers only.
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
const NEXT := 8  ## Target to resume after an intermediate stop, or 0.

# Directions of a hall call (a car's DIR uses the same signs).
const UP := 1
const DOWN := -1

# Indices into a hall call array.
const CALL_SHAFT := 0
const CALL_FLOOR := 1
const CALL_DIR := 2
const CALL_CAR := 3


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
	_dispatch(rooms)
	for n in rooms._cars.size():
		var car: Array = rooms._cars[n]
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
					idle(car)
			DOORS_OPENING:
				car[STATE] = DOORS_OPEN
				car[TICKS] = DOOR_HOLD_TICKS
				for c in range(rooms._calls.size() - 1, -1, -1):
					if rooms._calls[c][CALL_CAR] == n and rooms._calls[c][CALL_FLOOR] == car[FLOOR]:
						rooms._calls.remove_at(c)
			DOORS_OPEN:
				car[STATE] = DOORS_CLOSING
				car[TICKS] = DOOR_CLOSE_TICKS
			_:
				if car[NEXT] != 0:
					var resume: int = car[NEXT]
					car[NEXT] = 0
					start(car, resume)
				else:
					idle(car)


## Gives each unassigned call, oldest first, to the nearest idle car or car that will pass it.
static func _dispatch(rooms: RefCounted) -> void:
	for call: Array in rooms._calls:
		if call[CALL_CAR] != -1:
			continue
		var at: int = _level(call[CALL_FLOOR])
		var best := -1
		var best_distance := 0
		for n in rooms._cars.size():
			var car: Array = rooms._cars[n]
			if car[SHAFT] != call[CALL_SHAFT]:
				continue
			var ahead: int = (at - _level(car[FLOOR])) * call[CALL_DIR]
			var goes_by: bool = car[STATE] == MOVING and car[DIR] == call[CALL_DIR] and ahead > 0 and (at - _level(car[TARGET])) * call[CALL_DIR] <= 0 and (car[NEXT] == 0 or call[CALL_FLOOR] == car[TARGET])
			if car[STATE] != IDLE and not goes_by:
				continue
			var distance: int = absi(at - _level(car[FLOOR]))
			if best == -1 or distance < best_distance:
				best = n
				best_distance = distance
		if best == -1:
			continue
		call[CALL_CAR] = best
		var chosen: Array = rooms._cars[best]
		if chosen[STATE] == IDLE:
			rooms.send_car(best, call[CALL_FLOOR])
		elif chosen[TARGET] != call[CALL_FLOOR]:
			chosen[NEXT] = chosen[TARGET]
			chosen[TARGET] = call[CALL_FLOOR]


## Parks a car: idle, no target.
static func idle(car: Array) -> void:
	car[NEXT] = 0
	car[STATE] = IDLE
	car[DIR] = 0
	car[TARGET] = 0
	car[TICKS] = 0
