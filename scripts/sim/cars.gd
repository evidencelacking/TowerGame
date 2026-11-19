extends RefCounted
## Elevator car motion in integer ticks (4.4). A car is [shaft id, home, floor, load, state, dir,
## target, time units left, next] in Rooms; this runs its state machine once per tick. Rooms.send_car
## gives a car a target. Hall calls (#93) are [shaft id, floor, dir, car index or -1], kept in
## arrival order. Each tick the oldest unassigned call goes to the nearest car (lowest index on a
## tie) that is idle, or is moving the call's way and has not yet passed the call floor; such a
## moving car takes the call floor as an intermediate target and resumes its old target (NEXT)
## after the doors close. A call clears when its car's doors open. Deterministic: integers only.
##
## Boarding (#94): when the doors reach DOORS_OPEN, riders bound for the floor alight first (the
## Rooms.on_alight hook), then people queued there (Rooms.join_queue) board in arrival order while
## the car is heading their way and holds fewer than car_capacity(). Each rider's destination is a
## car stop (Rooms.add_car_stop). A full car does not take calls and passes a call floor it
## reaches without stopping; the call goes back to unassigned for another car or a later pass.
## After the doors close a car goes to the nearest pending stop in its heading, then the nearest
## the other way, and idles when none is left.
##
## Time (#103): the clock runs 2.5 ticks per sim minute, so a full-height ride must fit in about
## 10 ticks (4 sim minutes). A tick is TICK_UNITS time units. Motion and doors cost units, and a
## car spends a tick's units across phases, so leftover units carry from one phase into the next
## within the tick. A floor costs LOCAL_UNITS_PER_FLOOR (local and service cars) or
## EXPRESS_UNITS_PER_FLOOR (express shafts, about 2x faster) and a stop costs the doors, 0.7 tick.
##
## Schedules (#188): the slot in force (Rooms.schedule_slot: weekday or weekend, morning, midday or
## evening) sets, per shaft, a mode, a response distance and a departure wait. In express-to-top or
## to-bottom mode an idle, empty car is sent to the top or bottom stop at once and parks there in
## place of its home. The response distance (floors, 0 for no limit) keeps a moving car from
## diverting for a call farther ahead than that. The departure wait holds a car's doors open at its
## home floor for that many sim seconds (SECONDS_PER_TICK each tick) or until it is full, taking on
## riders that join meanwhile. A new slot is read at the next idle moment, wait or dispatch.
##
## Home (#109): a car with no calls, no stops and no riders that is away from its home floor counts
## idle time (its TICKS, which an idle car does not otherwise use). After IDLE_DWELL units it heads
## home. A car on its way home counts as moving, not waiting (Rooms.car_waiting_at), but dispatch may
## take it for a call from wherever it is. Any call or rider resets the dwell. It parks on arrival.

const IDLE := 0
const MOVING := 1
const DOORS_OPENING := 2
const DOORS_OPEN := 3
const DOORS_CLOSING := 4

# Timing in time units (TICK_UNITS per tick). All unverified, tune by play.
const TICK_UNITS := 100
const LOCAL_UNITS_PER_FLOOR := 9  ## 100 floors in 9 ticks.
const EXPRESS_UNITS_PER_FLOOR := 5  ## 100 floors in 5 ticks: about 2x local (8.2).
const DOOR_OPEN_UNITS := 20
const DOOR_HOLD_UNITS := 30
const DOOR_CLOSE_UNITS := 20
const SECONDS_PER_TICK := 24  ## The clock runs 2.5 ticks per sim minute.
const IDLE_DWELL := 500  ## Idle time before a car returns home: 5 ticks, 2 sim minutes. Unverified.

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


## Time units one floor takes a car: express shafts are faster than local and service ones.
static func units_per_floor(kind: String) -> int:
	return EXPRESS_UNITS_PER_FLOOR if kind == "express_shaft" else LOCAL_UNITS_PER_FLOOR


static func _next(floor_number: int, dir: int) -> int:
	if dir > 0:
		return 1 if floor_number == -1 else floor_number + 1
	return -1 if floor_number == 1 else floor_number - 1


## Gives an idle car a target (a stop; Rooms.send_car checks). Its own floor just cycles the doors.
static func start(car: Array, target: int, units_per_floor_now: int = LOCAL_UNITS_PER_FLOOR) -> void:
	car[TARGET] = target
	if car[FLOOR] == target:
		car[STATE] = DOORS_OPENING
		car[DIR] = 0
		car[TICKS] = DOOR_OPEN_UNITS
		return
	car[STATE] = MOVING
	car[DIR] = 1 if _level(target) > _level(car[FLOOR]) else -1
	car[TICKS] = units_per_floor_now


## Runs every car one tick: TICK_UNITS time units, spent across phases until they run out.
static func tick(rooms: RefCounted) -> void:
	_dispatch(rooms)
	for n in rooms._cars.size():
		var car: Array = rooms._cars[n]
		if car[STATE] == IDLE:
			_count_idle(rooms, n)
		elif car[STATE] == DOORS_OPEN and car[TICKS] > DOOR_HOLD_UNITS:
			_board_while_held(rooms, n)
		var budget := TICK_UNITS
		while budget > 0 and car[STATE] != IDLE:
			var spent := mini(budget, car[TICKS])
			budget -= spent
			car[TICKS] -= spent
			if car[TICKS] > 0:
				break
			_finish_phase(rooms, n)


## Car n has used up its current phase: a floor passed, or a door phase done.
static func _finish_phase(rooms: RefCounted, n: int) -> void:
	var car: Array = rooms._cars[n]
	match car[STATE]:
		MOVING:
			car[FLOOR] = _next(car[FLOOR], car[DIR])
			if car[FLOOR] != car[TARGET]:
				car[TICKS] = units_per_floor(rooms.kind_of(car[SHAFT]))
			elif going_home(rooms, n) and car[FLOOR] == park_floor(rooms, n):
				idle(car)
			elif not rooms.is_stop(car[SHAFT], car[FLOOR]):
				_alight_all_here(rooms, n)
				_resume(rooms, n)
			elif car[LOAD] >= rooms.car_capacity(car[SHAFT]) and not rooms._stops[n].has(car[FLOOR]):
				for call: Array in rooms._calls:
					if call[CALL_CAR] == n and call[CALL_FLOOR] == car[FLOOR]:
						call[CALL_CAR] = -1
				_resume(rooms, n)
			else:
				car[STATE] = DOORS_OPENING
				car[DIR] = 0
				car[TICKS] = DOOR_OPEN_UNITS
		DOORS_OPENING:
			car[STATE] = DOORS_OPEN
			car[TICKS] = DOOR_HOLD_UNITS
			_exchange(rooms, n)
			if car[FLOOR] == car[HOME] and car[LOAD] < rooms.car_capacity(car[SHAFT]):
				car[TICKS] += wait_units(rooms, car[SHAFT])
		DOORS_OPEN:
			car[STATE] = DOORS_CLOSING
			car[TICKS] = DOOR_CLOSE_UNITS
		_:
			_resume(rooms, n)


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
			if car[SHAFT] != call[CALL_SHAFT] or car[LOAD] >= rooms.car_capacity(car[SHAFT]):
				continue
			var homing := going_home(rooms, n)
			var ahead: int = (at - _level(car[FLOOR])) * call[CALL_DIR]
			var response: int = rooms.schedule_field(car[SHAFT], rooms.schedule_slot, 1)
			if response > 0 and car[STATE] != IDLE and ahead > response:
				continue
			var goes_by: bool = car[STATE] == MOVING and car[DIR] == call[CALL_DIR] and ahead > 0 and (at - _level(car[TARGET])) * call[CALL_DIR] <= 0 and (car[NEXT] == 0 or call[CALL_FLOOR] == car[TARGET])
			if car[STATE] != IDLE and not goes_by and not homing:
				continue
			var distance: int = absi(at - _level(car[FLOOR]))
			if best == -1 or distance < best_distance:
				best = n
				best_distance = distance
		if best == -1:
			continue
		var returning := going_home(rooms, best)
		call[CALL_CAR] = best
		var chosen: Array = rooms._cars[best]
		if chosen[STATE] == IDLE:
			rooms.send_car(best, call[CALL_FLOOR])
		elif returning:
			_redirect(rooms, best, call[CALL_FLOOR])
		elif chosen[TARGET] != call[CALL_FLOOR]:
			chosen[NEXT] = chosen[TARGET]
			chosen[TARGET] = call[CALL_FLOOR]


## True when car n is on its way home with nothing else to do: moving to its home floor, empty,
## with no stops and no call assigned to it.
static func going_home(rooms: RefCounted, n: int) -> bool:
	var car: Array = rooms._cars[n]
	if car[STATE] != MOVING or car[TARGET] != park_floor(rooms, n) or car[NEXT] != 0 or car[LOAD] != 0:
		return false
	if not rooms._riders[n].is_empty() or not rooms._stops[n].is_empty():
		return false
	for call: Array in rooms._calls:
		if call[CALL_CAR] == n:
			return false
	return true


## Sends a car that is on its way home to a call floor instead, from where it is.
static func _redirect(rooms: RefCounted, n: int, floor_number: int) -> void:
	var car: Array = rooms._cars[n]
	var dir := dir_to(car[FLOOR], floor_number)
	if dir != 0 and dir == car[DIR]:
		car[TARGET] = floor_number
		return
	start(car, floor_number, units_per_floor(rooms.kind_of(car[SHAFT])))


## An idle car counts its dwell in TICKS and heads home when it runs out. Anything to do (a call,
## a stop, a rider), or being home already, resets the count.
static func _count_idle(rooms: RefCounted, n: int) -> void:
	var car: Array = rooms._cars[n]
	var park := park_floor(rooms, n)
	var busy: bool = car[FLOOR] == park or car[LOAD] != 0 or not rooms._riders[n].is_empty() or not rooms._stops[n].is_empty()
	for call: Array in rooms._calls:
		busy = busy or call[CALL_CAR] == n
	if busy:
		car[TICKS] = 0
		return
	car[TICKS] += TICK_UNITS
	if car[TICKS] >= IDLE_DWELL or park != car[HOME]:  # an express mode sends the car without the home dwell
		start(car, park, units_per_floor(rooms.kind_of(car[SHAFT])))


## Where car n parks when idle: its home floor, or in express-to-top / to-bottom mode the top / bottom
## stop of its shaft (the schedule slot in force).
static func park_floor(rooms: RefCounted, n: int) -> int:
	var car: Array = rooms._cars[n]
	var mode: int = rooms.schedule_field(car[SHAFT], rooms.schedule_slot, 0)
	if mode == rooms.MODE_NORMAL:
		return car[HOME]
	var stops: Array[int] = rooms.stops_of(car[SHAFT])
	if stops.is_empty():
		return car[HOME]
	return stops[stops.size() - 1] if mode == rooms.MODE_TOP else stops[0]


## The departure wait of a shaft in the slot in force, in time units.
static func wait_units(rooms: RefCounted, shaft_id: int) -> int:
	return rooms.schedule_field(shaft_id, rooms.schedule_slot, 2) * TICK_UNITS / SECONDS_PER_TICK


## A car holding its doors at home for the departure wait takes on people who joined the queue
## since, and leaves when it is full.
static func _board_while_held(rooms: RefCounted, n: int) -> void:
	var car: Array = rooms._cars[n]
	_exchange(rooms, n)
	if car[LOAD] >= rooms.car_capacity(car[SHAFT]):
		car[TICKS] = DOOR_HOLD_UNITS
	for c in range(rooms._calls.size() - 1, -1, -1):  # calls from people who just boarded are done
		var call: Array = rooms._calls[c]
		if call[CALL_SHAFT] != car[SHAFT] or call[CALL_FLOOR] != car[FLOOR] or call[CALL_CAR] != -1:
			continue
		var wanted := false
		for entry: Array in rooms._queue:
			wanted = wanted or (entry[1] == car[SHAFT] and entry[2] == car[FLOOR] and dir_to(car[FLOOR], entry[3]) == call[CALL_DIR])
		if not wanted:
			rooms._calls.remove_at(c)


## Parks a car: idle, no target.
static func idle(car: Array) -> void:
	car[NEXT] = 0
	car[STATE] = IDLE
	car[DIR] = 0
	car[TARGET] = 0
	car[TICKS] = 0


## Direction (UP or DOWN) from one floor to another, 0 when they are the same.
static func dir_to(from_floor: int, to_floor: int) -> int:
	return signi(_level(to_floor) - _level(from_floor))


## Car n has just opened its doors: riders bound here alight, the car's calls here clear, then
## queued people going the car's way board in arrival order up to the capacity.
static func _exchange(rooms: RefCounted, n: int) -> void:
	var car: Array = rooms._cars[n]
	var floor_number: int = car[FLOOR]
	_alight_all_here(rooms, n)
	var dir := 0
	for call: Array in rooms._calls:
		if call[CALL_CAR] == n and call[CALL_FLOOR] == floor_number and dir == 0:
			dir = call[CALL_DIR]
	for c in range(rooms._calls.size() - 1, -1, -1):
		if rooms._calls[c][CALL_CAR] == n and rooms._calls[c][CALL_FLOOR] == floor_number:
			rooms._calls.remove_at(c)
	var riders: Array = rooms._riders[n]
	if not riders.is_empty():
		dir = dir_to(floor_number, riders[0][1])
	for entry: Array in rooms._queue:
		if dir == 0 and entry[1] == car[SHAFT] and entry[2] == floor_number:
			dir = dir_to(floor_number, entry[3])
	rooms._heading[n] = dir
	var q := 0
	while q < rooms._queue.size() and riders.size() < rooms.car_capacity(car[SHAFT]):
		var entry: Array = rooms._queue[q]
		if entry[1] == car[SHAFT] and entry[2] == floor_number and dir_to(floor_number, entry[3]) == dir:
			riders.append([entry[0], entry[3]])
			rooms.add_car_stop(n, entry[3])
			rooms._queue.remove_at(q)
		else:
			q += 1
	car[LOAD] = riders.size()
	for entry: Array in rooms._queue:
		if entry[1] == car[SHAFT] and entry[2] == floor_number:
			rooms.place_call(entry[1], floor_number, dir_to(floor_number, entry[3]))


## Riders of car n whose destination is its floor get off, and that floor stops being a stop.
static func _alight_all_here(rooms: RefCounted, n: int) -> void:
	var car: Array = rooms._cars[n]
	var kept: Array = []
	for rider: Array in rooms._riders[n]:
		if rider[1] == car[FLOOR]:
			rooms.on_alight(rider[0], car[FLOOR])
		else:
			kept.append(rider)
	rooms._riders[n] = kept
	rooms._stops[n].erase(car[FLOOR])
	car[LOAD] = kept.size()


## After the doors close (or a pass): go to the nearest pending stop in the heading, else the
## nearest the other way, else idle. NEXT counts as a stop and is kept unless chosen.
static func _resume(rooms: RefCounted, n: int) -> void:
	var car: Array = rooms._cars[n]
	var options: Array[int] = []
	for stop: int in rooms._stops[n]:
		options.append(stop)
	if car[NEXT] != 0 and not options.has(car[NEXT]):
		options.append(car[NEXT])
	options.erase(car[FLOOR])
	var heading: int = rooms._heading[n]
	var best := 0
	var best_distance := 0
	for pass_number in 2:
		for stop in options:
			if pass_number == 0 and dir_to(car[FLOOR], stop) != heading:
				continue
			var distance: int = absi(_level(stop) - _level(car[FLOOR]))
			if best == 0 or distance < best_distance:
				best = stop
				best_distance = distance
		if best != 0:
			break
	if best == 0:
		idle(car)
		return
	rooms._heading[n] = dir_to(car[FLOOR], best)
	if car[NEXT] == best:
		car[NEXT] = 0
	start(car, best, units_per_floor(rooms.kind_of(car[SHAFT])))
