class_name TowerRenderer
extends Node2D
## Draws the tower with native shapes only. Reads the Tower read-only; never mutates sim state.
## All geometry is integer pixels from ViewConstants, so edges stay aligned at any zoom.

const SKY_COLOR := Color(0.53, 0.78, 0.95)
const GROUND_COLOR := Color(0.36, 0.26, 0.17)
const GRASS_COLOR := Color(0.30, 0.62, 0.25)
const FLOOR_COLOR := Color(0.16, 0.16, 0.20)
const GRID_COLOR := Color(1, 1, 1, 0.12)
const EMPTY_ROOM_COLOR := Color(0.85, 0.2, 0.85)
const PERSON_COLOR := Color(0.95, 0.9, 0.2)
const MARGIN: int = 4000  ## Sky and ground extend this far past the tower, in pixels.
const PERSON_W: int = 4
const PERSON_H: int = 10

## Room type -> colour. The only place room colours are defined. Room types do not exist in
## the sim yet (issue 2.x); keys are placeholder type ids until they do.
const ROOM_COLORS: Dictionary = {
	0: Color(0.80, 0.80, 0.85),  # lobby
	1: Color(0.55, 0.70, 0.90),  # office
	2: Color(0.95, 0.75, 0.35),  # hotel room
	3: Color(0.90, 0.45, 0.40),  # restaurant
	4: Color(0.60, 0.85, 0.55),  # shop
}

var tower: Tower = null
## Maps an occupant id to a ROOM_COLORS key. Replace once the sim stores room types.
var room_type_of: Callable = func(id: int) -> int: return id % ROOM_COLORS.size()
## Stub for people until the sim has them: each entry is [floor, x_in_pixels_within_tower].
var people: Array[Array] = []


func set_tower(value: Tower) -> void:
	tower = value
	queue_redraw()


func _draw() -> void:
	var top := ViewConstants.floor_top_y(Tower.Grid.FLOOR_COUNT - 1)
	var bottom := ViewConstants.floor_top_y(0) + ViewConstants.FLOOR_H
	var left := -MARGIN
	var width := ViewConstants.TOWER_PX_W + 2 * MARGIN
	draw_rect(Rect2i(left, top - MARGIN, width, -top + MARGIN), SKY_COLOR)
	draw_rect(Rect2i(left, 0, width, bottom + MARGIN), GROUND_COLOR)
	draw_rect(Rect2i(left, 0, width, 4), GRASS_COLOR)
	if tower == null:
		return
	_draw_floors()
	_draw_rooms()
	_draw_people()


func _draw_floors() -> void:
	for index: int in Tower.Grid.FLOOR_COUNT:
		var y := ViewConstants.floor_top_y(index)
		if index >= 10:  # floor separator lines, 1 screen pixel at any zoom
			var line_y := y + ViewConstants.FLOOR_H
			draw_line(Vector2(0, line_y), Vector2(ViewConstants.TOWER_PX_W, line_y), GRID_COLOR, -1.0)
	for column in range(0, Tower.Grid.WIDTH_UNITS + 1, 10):
		var x := ViewConstants.column_x(column)
		var y0 := ViewConstants.floor_top_y(Tower.Grid.FLOOR_COUNT - 1)
		draw_line(Vector2(x, y0), Vector2(x, y0 + Tower.Grid.FLOOR_COUNT * ViewConstants.FLOOR_H), GRID_COLOR, -1.0)


func _draw_rooms() -> void:
	var grid := tower.grid
	var seen: Dictionary = {}
	for index: int in Tower.Grid.FLOOR_COUNT:
		var floor_number := Tower.Grid.index_to_floor(index)
		var column := 0
		while column < Tower.Grid.WIDTH_UNITS:
			var id := grid.cell_at(floor_number, column)
			if id == Tower.Grid.EMPTY or seen.has(id):
				column += 1
				continue
			seen[id] = true
			var run := grid.run_of(id)
			var rect := Rect2i(ViewConstants.column_x(run[1]), ViewConstants.floor_top_y(index), run[2] * ViewConstants.CELL_W, ViewConstants.FLOOR_H)
			var type_id: int = room_type_of.call(id)
			var color: Color = ROOM_COLORS.get(type_id, EMPTY_ROOM_COLOR)
			draw_rect(rect, color)
			draw_rect(rect, color.darkened(0.5), false, 1.0)
			column += run[2]


func _draw_people() -> void:
	for person in people:
		var index := Tower.Grid.floor_to_index(person[0])
		if index < 0:
			continue
		var y := ViewConstants.floor_top_y(index) + ViewConstants.FLOOR_H - PERSON_H
		draw_rect(Rect2i(person[1], y, PERSON_W, PERSON_H), PERSON_COLOR)
