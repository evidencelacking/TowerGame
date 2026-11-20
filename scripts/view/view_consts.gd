extends RefCounted
## Shared view constants and world-space helpers. World space is the tower's native pixel space
## (10.2): x grows right from column 0, y grows down from the top of floor 100. A grid cell is
## CELL_W wide and CELL_H tall; the renderer draws at this resolution and the camera zooms by whole
## numbers, so one native pixel is always a whole number of screen pixels.

const CELL_W := 8  ## Native pixels per floor-unit column.
const CELL_H := 32  ## Native pixels per floor.
const FIGURE_W := 6  ## A standing figure, native pixels: about half a floor tall. Every pose derives from this pair.
const FIGURE_H := 16
const SLAB_H := 2  ## The floor slab along the bottom of each floor, inside its CELL_H.
const GridScript := preload("res://scripts/sim/grid.gd")


## Row index counted from the top: floor 100 is row 0, B10 is the last row (no floor 0).
static func floor_to_row(floor_number: int) -> int:
	if floor_number > 0:
		return GridScript.FLOOR_MAX - floor_number
	return GridScript.FLOOR_MAX - floor_number - 1


## The whole tower in pixels at zoom 1.
static func world_rect() -> Rect2:
	return Rect2(0, 0, GridScript.WIDTH_UNITS * CELL_W, GridScript.FLOOR_COUNT * CELL_H)
