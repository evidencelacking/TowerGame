class_name Grades
extends RefCounted
## Quality score and A/B/C grade (5.1) for offices, condos and hotels. Quality is STRESS_MAX
## minus the average stress of the room's occupants who have made a trip (docs/gameplay-reference.md,
## manual p63): A over 200, B 150 to 200, C under 150. Restaurants and shops are graded by
## customers instead (M6) and are not graded here.
##
## Stress is the live value in People, which already recovers while idle, so the average is over
## everyone's current stress, per room, with no window or sampling of its own. The average is
## integer division (rounds down, so quality rounds up). A room whose occupants have made no trip
## yet is a neutral B. Read-only for the view: Tower.quality(room) and Tower.grade(room).
##
## Hook for later work (rent #115, noise #117, word of mouth #118, complaints #119): add_modifier
## registers a Callable (room_id: int) -> int giving extra stress for that room, added to its
## average (negative to relieve it). Modifiers must be deterministic. They are not saved: the
## owner of each rule re-registers it at construction.
##
## Saved state: which people have made a first trip (their ids, in the order they first travelled).

const EvalTablesScript := preload("res://scripts/sim/eval_tables.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")

const GRADE_NONE := -1  ## Not a graded room kind.
const GRADE_A := 0
const GRADE_B := 1
const GRADE_C := 2
const LETTERS: Array[String] = ["A", "B", "C"]

const A_OVER := 200  ## Quality above this is A.
const B_FROM := 150  ## Quality at or above this (and not A) is B; below is C.
const NEUTRAL_QUALITY := 175  ## Quality of a room with no trips yet: mid B.

## Kinds graded by stress: occupants are the people who work there (offices) or live there
## (condos, hotel guests).
const WORK_KINDS: Array[String] = ["office"]
const HOME_KINDS: Array[String] = ["condo", "studio", "penthouse", "apartment", "assisted", "hotel_single", "hotel_twin", "hotel_suite"]

## The graded kinds as keys, so is_graded is one lookup instead of a scan of both lists (the mood update and the evaluation ask per room).
const _GRADED: Dictionary = {"office": true, "condo": true, "studio": true, "penthouse": true, "apartment": true, "assisted": true, "hotel_single": true, "hotel_twin": true, "hotel_suite": true}

var _tripped: Dictionary = {}  ## Person id -> true once they have made a trip.
var _order: Array[int] = []  ## The same ids in the order first seen, for saving.
var _modifiers: Array[Callable] = []
## Modifiers that read other rooms' grades (word of mouth): applied after the rest, which a batch memoises per room.
var _late_modifiers: Array[Callable] = []
## While set (a mood update or an evaluation is running), average_stress reads these tables instead of scanning everyone (#416).
var batch: EvalTablesScript = null


## True once the person has made a trip.
func tripped(id: int) -> bool:
	return _tripped.has(id)


## Marks people who have asked for a trip as having made their first trip. Takes People.trip_requests, so it costs
## nothing on a tick when nobody asked. Tower runs it every tick right after People.tick, so nothing is pending between
## ticks and a save needs no extra state (#459).
func tick(people: PeopleScript) -> void:
	for id in people.trip_requests:
		if not _tripped.has(id):
			_tripped[id] = true
			_order.append(id)
	people.trip_requests.clear()


## Registers a stress modifier: Callable(room_id: int) -> int, added to the room's average stress.
## late is for a modifier that depends on other rooms' grades: the sum of the others is memoised per room during a
## batch (EvalTables.base_stress), and a late one is added on top each time. Order does not matter: it is a sum.
func add_modifier(modifier: Callable, late: bool = false) -> void:
	if late:
		_late_modifiers.append(modifier)
	else:
		_modifiers.append(modifier)


## True for room kinds that are graded by stress.
static func is_graded(kind: String) -> bool:
	return _GRADED.has(kind)


## The grade for a quality score: GRADE_A over 200, GRADE_C under 150, else GRADE_B.
static func grade_of_quality(quality: int) -> int:
	if quality > A_OVER:
		return GRADE_A
	if quality < B_FROM:
		return GRADE_C
	return GRADE_B


## "A", "B" or "C" for a grade ("" for GRADE_NONE).
static func letter(grade: int) -> String:
	if grade < 0 or grade >= LETTERS.size():
		return ""
	return LETTERS[grade]


## Average current stress of the occupants who have made a trip, before any modifier (rent,
## noise, word of mouth): the part of the grade that travel causes. -1 if the room is not
## graded or no occupant has travelled yet.
func average_stress(rooms: RoomsScript, people: PeopleScript, room: int) -> int:
	var kind := rooms.kind_of(room)
	if not is_graded(kind):
		return -1
	var by_work := WORK_KINDS.has(kind)
	if batch != null:
		return batch.average_stress(room, by_work)
	var total := 0
	var n := 0
	for i in people.count():
		var occupied := people.work_of(i) if by_work else people.home_of(i)
		if occupied == room and _tripped.has(people.id_at(i)):
			total += people.stress_of(i)
			n += 1
	if n == 0:
		return -1
	return total / n


## Quality of the room 0 to STRESS_MAX, or -1 if the room is not graded. Neutral until an
## occupant has made a trip.
func quality(rooms: RoomsScript, people: PeopleScript, room: int) -> int:
	var kind := rooms.kind_of(room)
	if not _GRADED.has(kind):
		return -1
	var average := -1
	if batch != null:  # average_stress's batch answer, without its second kind lookup and graded check
		average = batch.average_stress(room, kind == "office")
	else:
		average = average_stress(rooms, people, room)
	if average < 0:
		return NEUTRAL_QUALITY
	if batch != null and batch.base_stress.has(room):
		average = batch.base_stress[room]
	else:
		for modifier in _modifiers:
			average += modifier.call(room)
		if batch != null:
			batch.base_stress[room] = average  # the average and every modifier but the late ones, until the stress tables change
	for modifier in _late_modifiers:
		average += modifier.call(room)
	return PeopleScript.STRESS_MAX - clampi(average, 0, PeopleScript.STRESS_MAX)


## GRADE_A, GRADE_B or GRADE_C for the room, or GRADE_NONE if it is not graded.
func grade(rooms: RoomsScript, people: PeopleScript, room: int) -> int:
	var q := quality(rooms, people, room)
	if q < 0:
		return GRADE_NONE
	return grade_of_quality(q)


func state_ints() -> Array[int]:
	var ints: Array[int] = [_order.size()]
	ints.append_array(_order)
	return ints


static func valid_ints(ints: Array) -> bool:
	if ints.is_empty() or typeof(ints[0]) != TYPE_INT or ints[0] < 0 or ints.size() != ints[0] + 1:
		return false
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	return true


func load_ints(ints: Array) -> void:
	_tripped.clear()
	_order.clear()
	for k in range(1, ints.size()):
		_order.append(ints[k])
		_tripped[ints[k]] = true
