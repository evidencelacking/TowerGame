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
const EvalTablesScript := preload("res://scripts/sim/eval_tables.gd")

const NEIGHBOUR_FLOORS := 2  ## Vertical reach, in floors (unverified, tunable).
const NEIGHBOUR_GAP := 12  ## Horizontal reach, in columns between nearest edges (unverified, tunable).
const STRESS_PER_COMPLAINER := 8  ## Stress added to a neighbour per C room in reach (unverified, tunable).
const MAX_COMPLAINERS := 3  ## Most C rooms that count, so the stack is capped at 24 stress.

var _grades: GradesScript
var _rooms: RoomsScript
var _grid: GridScript
var _people: PeopleScript
var _near_key: Array[int] = []
var _near_cache: Dictionary = {}  ## Room id -> its neighbours (see _neighbours).
var _by_floor: Dictionary = {}  ## Floor -> the graded rooms standing on it, in room id order. Valid with _near_key.
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
	var batch := _grades.batch
	if batch != null:
		var found := _batch_complainers(batch, room, here)
		_busy = false
		return found * STRESS_PER_COMPLAINER
	var complainers := 0
	for other in _neighbours(room, here):
		if _source_grade(other) == GradesScript.GRADE_C:
			complainers += 1
			if complainers >= MAX_COMPLAINERS:
				break
	_busy = false
	return complainers * STRESS_PER_COMPLAINER


## The same count as the loop over _neighbours, for a batch (#452): the C rooms are found once (a source's grade
## is memoised in the tables) and each room only looks at the few on the floors beside it. Capped at
## MAX_COMPLAINERS as the loop is. The caller holds _busy.
func _batch_complainers(batch: EvalTablesScript, room: int, here: Array[int]) -> int:
	_ensure_index()
	if not batch.source_c_ready:
		batch.source_c.clear()
		for f: int in _by_floor:
			for other: int in _by_floor[f]:
				if _source_grade(other) == GradesScript.GRADE_C:
					if not batch.source_c.has(f):
						batch.source_c[f] = [] as Array[int]
					batch.source_c[f].append(other)
		batch.source_c_ready = true
	var complainers := 0
	for f in range(here[0] - NEIGHBOUR_FLOORS, here[0] + NEIGHBOUR_FLOORS + 1):
		for other: int in batch.source_c.get(f, [] as Array[int]):
			if other != room and _near(here, _grid.run_of(other)):
				complainers += 1
	return mini(complainers, MAX_COMPLAINERS)


## A source's own grade, judged without word of mouth (the caller holds _busy). While an evaluation batch is
## running the tables hold it per room, since nothing it reads changes until the batch ends (#452).
func _source_grade(room: int) -> int:
	var batch := _grades.batch
	if batch == null:
		return _grades.grade(_rooms, _people, room)
	if batch.source_grades.has(room):
		return batch.source_grades[room]
	var g := _grades.grade(_rooms, _people, room)
	batch.source_grades[room] = g
	return g


## The graded rooms within reach of a room, in room id order. Kept per layout (#416): it depends only on the room kinds
## and where the rooms sit, so it is thrown away whenever the grid or the room list changes. Derived, never saved.
func _neighbours(room: int, here: Array[int]) -> Array[int]:
	_ensure_index()
	if _near_cache.has(room):
		return _near_cache[room]
	var found: Array[int] = []
	for f in range(here[0] - NEIGHBOUR_FLOORS, here[0] + NEIGHBOUR_FLOORS + 1):
		for other: int in _by_floor.get(f, [] as Array[int]):
			if other != room and _near(here, _grid.run_of(other)):
				found.append(other)
	found.sort()  # room id order, as the whole-list scan gave
	_near_cache[room] = found
	return found


## Rebuilds the floor index and drops the neighbour lists when the layout has changed.
func _ensure_index() -> void:
	var key: Array[int] = [_grid.get_instance_id(), _grid.revision, _rooms.layout_revision, _rooms.get_instance_id()]
	if key != _near_key:
		_near_key = key
		_near_cache = {}
		_by_floor = {}
		for other in _rooms.room_ids():
			if not GradesScript.is_graded(_rooms.kind_of(other)):
				continue
			var there := _grid.run_of(other)
			if there.is_empty():
				continue
			if not _by_floor.has(there[0]):
				_by_floor[there[0]] = [] as Array[int]
			_by_floor[there[0]].append(other)


## True when two [floor, column, length] runs are within reach of each other.
static func _near(a: Array[int], b: Array[int]) -> bool:
	if b.is_empty() or absi(a[0] - b[0]) > NEIGHBOUR_FLOORS:
		return false
	var gap := maxi(a[1] - (b[1] + b[2]), b[1] - (a[1] + a[2]))
	return gap <= NEIGHBOUR_GAP
