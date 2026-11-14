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
const HOME_KINDS: Array[String] = ["condo", "hotel_single", "hotel_twin", "hotel_suite"]

var _tripped: Dictionary = {}  ## Person id -> true once they have made a trip.
var _order: Array[int] = []  ## The same ids in the order first seen, for saving.
var _modifiers: Array[Callable] = []


## Marks people who are travelling as having made their first trip. Run each tick, after
## trips.tick starts trips and before they finish.
func tick(people: PeopleScript) -> void:
	for i in people.count():
		if people.trip_state(i) != PeopleScript.TRIP_IDLE:
			var id := people.id_at(i)
			if not _tripped.has(id):
				_tripped[id] = true
				_order.append(id)


## Registers a stress modifier: Callable(room_id: int) -> int, added to the room's average stress.
func add_modifier(modifier: Callable) -> void:
	_modifiers.append(modifier)


## True for room kinds that are graded by stress.
static func is_graded(kind: String) -> bool:
	return WORK_KINDS.has(kind) or HOME_KINDS.has(kind)


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


## Quality of the room 0 to STRESS_MAX, or -1 if the room is not graded. Neutral until an
## occupant has made a trip.
func quality(rooms: RoomsScript, people: PeopleScript, room: int) -> int:
	var kind := rooms.kind_of(room)
	if not is_graded(kind):
		return -1
	var by_work := WORK_KINDS.has(kind)
	var total := 0
	var n := 0
	for i in people.count():
		var occupied := people.work_of(i) if by_work else people.home_of(i)
		if occupied == room and _tripped.has(people.id_at(i)):
			total += people.stress_of(i)
			n += 1
	if n == 0:
		return NEUTRAL_QUALITY
	var average := total / n
	for modifier in _modifiers:
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
