extends RefCounted
## Shared view constants and world-space helpers. World space: x grows right from
## column 0, y grows down from the top of floor 100. One grid cell is CELL_PX square.

const CELL_PX := 16  ## Pixels per grid cell (and per floor height) at zoom 1.
const GridScript := preload("res://scripts/sim/grid.gd")


## Row index counted from the top: floor 100 is row 0, B10 is the last row (no floor 0).
static func floor_to_row(floor_number: int) -> int:
	if floor_number > 0:
		return GridScript.FLOOR_MAX - floor_number
	return GridScript.FLOOR_MAX - floor_number - 1


## The whole tower in pixels at zoom 1.
static func world_rect() -> Rect2:
	return Rect2(0, 0, GridScript.WIDTH_UNITS * CELL_PX, GridScript.FLOOR_COUNT * CELL_PX)
