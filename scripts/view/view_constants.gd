class_name ViewConstants
extends RefCounted
## Pixel geometry shared by the view scripts (renderer, camera). One world unit is one pixel at
## zoom 1. World y grows downward; y = 0 is the ground line (the bottom of floor 1, the top of B1).

const CELL_W: int = 8  ## Pixels per grid cell, horizontally.
const FLOOR_H: int = 36  ## Pixels per floor, vertically.
const TOWER_PX_W: int = Tower.Grid.WIDTH_UNITS * CELL_W  ## Width of one floor in pixels.


## Top edge (world y) of a floor given its storage index (see Grid.floor_to_index()).
static func floor_top_y(floor_index: int) -> int:
	return -(floor_index - 9) * FLOOR_H


## Left edge (world x) of a grid column.
static func column_x(column: int) -> int:
	return column * CELL_W
