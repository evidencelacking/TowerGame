class_name DragGesture
extends RefCounted
## A small reusable drag: where it began and where it is now, locked to one axis. The elevator
## shaft tools use it vertically; the lobby and floor tools (#127) will use it horizontally.
## View only: it holds cells (floor number, column), never pixels, so tests drive it directly.

enum Axis { VERTICAL, HORIZONTAL }

var axis: Axis = Axis.VERTICAL
var active: bool = false
var start_floor: int = 0
var start_column: int = 0
var floor_now: int = 0
var column_now: int = 0


func _init(drag_axis: Axis = Axis.VERTICAL) -> void:
	axis = drag_axis


## Starts a drag at a cell.
func begin(floor_number: int, column: int) -> void:
	active = true
	start_floor = floor_number
	start_column = column
	floor_now = floor_number
	column_now = column


## Follows the pointer. The locked axis keeps its starting value.
func update(floor_number: int, column: int) -> void:
	if not active:
		return
	if axis == Axis.VERTICAL:
		floor_now = floor_number
	else:
		column_now = column


## Finishes the drag and returns {start_floor, start_column, floor, column}; empty if none.
func end(floor_number: int, column: int) -> Dictionary:
	if not active:
		return {}
	update(floor_number, column)
	var out := {"start_floor": start_floor, "start_column": start_column,
		"floor": floor_now, "column": column_now}
	active = false
	return out


func cancel() -> void:
	active = false


## True once the pointer has left the cell the drag began in.
func moved() -> bool:
	return active and (floor_now != start_floor or column_now != start_column)


## Changes whenever the drag's verdict could change (cache key for the ghost).
func key() -> Array:
	return [active, start_floor, start_column, floor_now, column_now]
