extends RefCounted
## The tower grid. Integers only; see CLAUDE.md.
##
## Floors run B10 to B1 and 1 to 100. There is no floor 0: floor 1 is the ground and lobby
## floor (a taller lobby occupies floors 1-2 or 1-3), and B1 is the floor just below it.
## Floors are stored by index 0 to 109 (B10 is 0, B1 is 9, floor 1 is 10, floor 100 is 109);
## use floor_to_index() and index_to_floor() to convert. Each floor is WIDTH_UNITS cells wide.
## An occupant (a positive id) holds a contiguous run of cells on one floor. Floor-width
## rules and costs are not here; they belong to the room-building issues (2.x).

const FLOOR_MIN := -10  ## B10, the lowest floor. Buildable for now; the metro belongs to 11.3.
const FLOOR_MAX := 100
const FLOOR_COUNT := 110
## Cells per floor. Unverified, tune by play (check in 2.4: 11 offices fit a screen-wide lobby).
const WIDTH_UNITS := 400
const EMPTY := 0  ## What cell_at() returns for a free cell.

var _cells := PackedInt32Array()  # FLOOR_COUNT * WIDTH_UNITS occupant ids, EMPTY when free
var _runs: Dictionary = {}  # occupant id -> [floor, start, length]


func _init() -> void:
	_cells.resize(FLOOR_COUNT * WIDTH_UNITS)


static func is_valid_floor(floor_number: int) -> bool:
	return floor_number >= FLOOR_MIN and floor_number <= FLOOR_MAX and floor_number != 0


## Storage index of a floor number, or -1 for floor 0 and floors out of range.
static func floor_to_index(floor_number: int) -> int:
	if not is_valid_floor(floor_number):
		return -1
	return floor_number + 10 if floor_number < 0 else floor_number + 9


## Floor number of a storage index, or 0 (not a floor) if the index is out of range.
static func index_to_floor(index: int) -> int:
	if index < 0 or index >= FLOOR_COUNT:
		return 0
	return index - 10 if index < 10 else index - 9


## The occupant id at a cell, or EMPTY. Also EMPTY for an invalid floor or column.
func cell_at(floor_number: int, column: int) -> int:
	var index := floor_to_index(floor_number)
	if index < 0 or column < 0 or column >= WIDTH_UNITS:
		return EMPTY
	return _cells[index * WIDTH_UNITS + column]


## Places occupant id over length cells starting at column on a floor. Returns false, and
## changes nothing, for an id that is not positive or is already placed, an invalid floor,
## a run outside the width, or any overlap.
func place(id: int, floor_number: int, column: int, length: int) -> bool:
	var index := floor_to_index(floor_number)
	if id <= EMPTY or _runs.has(id) or index < 0 or length < 1:
		return false
	if column < 0 or column + length > WIDTH_UNITS:
		return false
	var base := index * WIDTH_UNITS + column
	for i in length:
		if _cells[base + i] != EMPTY:
			return false
	for i in length:
		_cells[base + i] = id
	_runs[id] = [floor_number, column, length]
	return true


## Removes occupant id. Returns false if it is not placed.
func remove(id: int) -> bool:
	if not _runs.has(id):
		return false
	var run: Array = _runs[id]
	var base: int = floor_to_index(run[0]) * WIDTH_UNITS + run[1]
	for i: int in run[2]:
		_cells[base + i] = EMPTY
	_runs.erase(id)
	return true


func has_occupant(id: int) -> bool:
	return _runs.has(id)


## [floor, column, length] of a placed occupant, or an empty array.
func run_of(id: int) -> Array[int]:
	var result: Array[int] = []
	if _runs.has(id):
		result.assign(_runs[id])
	return result


func occupant_count() -> int:
	return _runs.size()


## State for hashing and saving: groups of 4 ints (id, floor, column, length), ordered by id
## so the result does not depend on placement history.
func state_ints() -> Array[int]:
	var ids: Array = _runs.keys()
	ids.sort()
	var ints: Array[int] = []
	for id: int in ids:
		var run: Array = _runs[id]
		ints.append_array([id, run[0], run[1], run[2]] as Array[int])
	return ints


## Restores state_ints(). Returns false, changing nothing, if the data is not valid
## (wrong shape, non-integers, or runs that are out of range or overlap).
func load_ints(ints: Array) -> bool:
	if ints.size() % 4 != 0:
		return false
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	var loaded: Variant = get_script().new()
	for i in range(0, ints.size(), 4):
		if not loaded.place(ints[i], ints[i + 1], ints[i + 2], ints[i + 3]):
			return false
	_cells = loaded._cells
	_runs = loaded._runs
	return true
