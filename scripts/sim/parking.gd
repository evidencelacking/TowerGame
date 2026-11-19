class_name Parking
extends RefCounted
## Parking (7.7, #172): a ramp column under the ground lobby and spaces chained to it. Stateless:
## every answer is derived from the placed rooms, so nothing here is saved or hashed.
##
## The first ramp goes on B1 under the ground lobby; each next ramp goes directly below the one
## above it, in the same column. A space must touch the ramp or a working space (a shared edge on
## its sides, its top or its bottom). A room is working when a chain of touching ramps and spaces
## joins it to a ramp on B1. Cutting a link (bulldozing a ramp or a space) leaves the rooms beyond it
## broken: they stay built, are marked, and do not count, and building the link again revives them.
##
## Demand (Demands, PARKING): one working space per office (owner ruling), and one per suite. Office
## workers and suite guests come at opposite hours and share spaces, so the need is the larger of
## the two (the peak), not the sum (owner ruling, #172).

const GridScript := preload("res://scripts/sim/grid.gd")
const FloorsScript := preload("res://scripts/sim/floors.gd")

const RAMP_KIND := "parking_ramp"
const SPACE_KIND := "parking_space"
const TOP_FLOOR := -1  ## The first ramp goes on B1, just under the ground lobby.


static func is_parking(kind: String) -> bool:
	return kind == RAMP_KIND or kind == SPACE_KIND


## The ids of the ramps and spaces that are connected to the top of the ramp column.
static func working_ids(rooms: Rooms, grid: GridScript) -> Dictionary:
	var working: Dictionary = {}
	var queue: Array[int] = []
	for id in rooms.room_ids():
		if rooms.kind_of(id) == RAMP_KIND:
			var run := grid.run_of(id)
			if not run.is_empty() and run[0] == TOP_FLOOR:
				working[id] = true
				queue.append(id)
	var at := 0
	while at < queue.size():  # each id joins the queue once, so this ends
		var run := grid.run_of(queue[at])
		for next in touching_cells(rooms, grid, run[0], run[1], run[2], queue[at]):
			if not working.has(next):
				working[next] = true
				queue.append(next)
		at += 1
	return working


## Working spaces in the tower.
static func working_spaces(rooms: Rooms, grid: GridScript) -> int:
	var count := 0
	var working := working_ids(rooms, grid)
	for id: int in working:
		if rooms.kind_of(id) == SPACE_KIND:
			count += 1
	return count


## Placed ramps and spaces that are cut off from the column (the view marks them).
static func broken_ids(rooms: Rooms, grid: GridScript) -> Array[int]:
	var working := working_ids(rooms, grid)
	var broken: Array[int] = []
	for id in rooms.room_ids():
		if is_parking(rooms.kind_of(id)) and not working.has(id):
			broken.append(id)
	return broken


## The parking rooms that share an edge with a footprint (floor, left column, width), except skip.
static func touching_cells(rooms: Rooms, grid: GridScript, floor_number: int, x_left: int, width: int, skip: int) -> Array[int]:
	var found: Array[int] = []
	var cells: Array[Vector2i] = [Vector2i(floor_number, x_left - 1), Vector2i(floor_number, x_left + width)]
	var above := Rooms.floor_above(floor_number)
	var below := Rooms.floor_below(floor_number)
	for column in range(x_left, x_left + width):
		if above != 0:
			cells.append(Vector2i(above, column))
		if below != 0:
			cells.append(Vector2i(below, column))
	for cell in cells:
		var other := grid.cell_at(cell.x, cell.y)
		if other != GridScript.EMPTY and other != skip and is_parking(rooms.kind_of(other)) and not found.has(other):
			found.append(other)
	found.sort()
	return found


## What the tower's parking is asked for: the larger of the offices and the suites.
static func needed(offices: int, suites: int) -> int:
	return maxi(offices, suites)


## Why a ramp cannot go at (floor, x_left), or Rooms.OK. The first ramp goes on B1 with every
## column under the ground lobby; later ramps share the column of the first and sit directly below a ramp.
static func check_ramp(rooms: Rooms, grid: GridScript, floors: FloorsScript, floor_number: int, x_left: int, width: int) -> int:
	var column := -1
	for id in rooms.room_ids():
		if rooms.kind_of(id) == RAMP_KIND:
			column = grid.run_of(id)[1]
			break
	if column != -1 and x_left != column:
		return Rooms.RAMP_COLUMN
	if column == -1 and floor_number != TOP_FLOOR:
		return Rooms.RAMP_NOT_UNDER_LOBBY  # the first ramp is on B1
	if floor_number == TOP_FLOOR:
		var span := floors.lobby_span()
		if span.is_empty() or x_left < span[0] or x_left + width - 1 > span[1]:
			return Rooms.RAMP_NOT_UNDER_LOBBY
		return Rooms.OK
	var above := grid.cell_at(Rooms.floor_above(floor_number), x_left)
	if above == GridScript.EMPTY or rooms.kind_of(above) != RAMP_KIND:
		return Rooms.RAMP_NOT_BELOW_RAMP
	return Rooms.OK


## Why a space cannot go at (floor, x_left, width), or Rooms.OK: it must touch the ramp or a working space.
static func check_space(rooms: Rooms, grid: GridScript, floor_number: int, x_left: int, width: int) -> int:
	var working := working_ids(rooms, grid)
	for other in touching_cells(rooms, grid, floor_number, x_left, width, GridScript.EMPTY):
		if working.has(other):
			return Rooms.OK
	return Rooms.NOT_CHAINED
