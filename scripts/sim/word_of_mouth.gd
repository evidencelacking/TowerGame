class_name WordOfMouth
extends RefCounted
## Word of mouth (5.6): a C-grade room spreads complaints to nearby tenants (manual p61), which
## adds stress to their rooms and so lowers their quality. Registered as a Grades modifier, so
## it is recomputed from the current grades every time a quality is read: nothing is stored, no
## saved state, and a room that recovers to B or A stops hurting its neighbours at once (which
## also means the lower-then-restore rent exploit leaves no lasting penalty).
##
## Neighbourhood: another graded room within NEIGHBOUR_FLOORS floors and with at most
## NEIGHBOUR_GAP columns between their nearest edges. It crosses room types. Only complaints
## spread; A rooms do not spread praise. A source's own grade is judged without word of mouth
## (the _busy flag makes the nested call return 0), so complaints do not chain from room to
## room and the recursion ends after one level. All values are unverified and tunable.

const GradesScript := preload("res://scripts/sim/grades.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const GridScript := preload("res://scripts/sim/grid.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")

const NEIGHBOUR_FLOORS := 2  ## Vertical reach, in floors (unverified, tunable).
const NEIGHBOUR_GAP := 12  ## Horizontal reach, in columns between nearest edges (unverified, tunable).
const STRESS_PER_COMPLAINER := 8  ## Stress added to a neighbour per C room in reach (unverified, tunable).
const MAX_COMPLAINERS := 3  ## Most C rooms that count, so the stack is capped at 24 stress.

var _grades: GradesScript
var _rooms: RoomsScript
var _grid: GridScript
var _people: PeopleScript
var _busy := false  ## True while judging sources, so their grade leaves word of mouth out.


## Registers word of mouth as a stress modifier on grades. Tower calls it from _init, after
## all four members exist (they are member initialisers, so they are built before _init runs).
func attach(grades: GradesScript, rooms: RoomsScript, grid: GridScript, people: PeopleScript) -> void:
	_grades = grades
	_rooms = rooms
	_grid = grid
	_people = people
	grades.add_modifier(stress_for)


## Extra stress for a room from C-grade neighbours.
func stress_for(room: int) -> int:
	if _busy or not GradesScript.is_graded(_rooms.kind_of(room)):
		return 0
	var here := _grid.run_of(room)
	if here.is_empty():
		return 0
	_busy = true
	var complainers := 0
	for other in _rooms.room_ids():
		if other == room or not GradesScript.is_graded(_rooms.kind_of(other)):
			continue
		if not _near(here, _grid.run_of(other)):
			continue
		if _grades.grade(_rooms, _people, other) == GradesScript.GRADE_C:
			complainers += 1
			if complainers >= MAX_COMPLAINERS:
				break
	_busy = false
	return complainers * STRESS_PER_COMPLAINER


## True when two [floor, column, length] runs are within reach of each other.
static func _near(a: Array[int], b: Array[int]) -> bool:
	if b.is_empty() or absi(a[0] - b[0]) > NEIGHBOUR_FLOORS:
		return false
	var gap := maxi(a[1] - (b[1] + b[2]), b[1] - (a[1] + a[2]))
	return gap <= NEIGHBOUR_GAP
