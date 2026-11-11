class_name TowerRenderer
extends Node2D
const VC := preload("res://scripts/view/view_consts.gd")
## Draws the tower with native shapes only. Reads the Tower read-only; never mutates sim state.
## All geometry is integer pixels from view_consts.gd, so edges stay aligned at any zoom.

const SKY_COLOR := Color(0.53, 0.78, 0.95)
const GROUND_COLOR := Color(0.36, 0.26, 0.17)
const GRASS_COLOR := Color(0.30, 0.62, 0.25)
const FLOOR_COLOR := Color(0.16, 0.16, 0.20)
const GRID_COLOR := Color(1, 1, 1, 0.12)
const EMPTY_ROOM_COLOR := Color(0.85, 0.2, 0.85)
const PERSON_COLOR := Color(0.95, 0.9, 0.2)
const MARGIN: int = 4000  ## Sky and ground extend this far past the tower, in pixels.
const PERSON_W: int = 4
const PERSON_H: int = 10  # a cell is 16 px tall

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
## Colour of each placed room kind (catalogue id). Rooms placed by PLACE_ROOM use these.
const KIND_COLORS: Dictionary = {
	"office": Color(0.55, 0.70, 0.90),
	"condo": Color(0.85, 0.65, 0.85),
	"stairs": Color(0.80, 0.72, 0.45),
}

## Maps an occupant id to a ROOM_COLORS key. Replace once the sim stores room types.
var room_type_of: Callable = func(id: int) -> int: return id % ROOM_COLORS.size()
## Stub for people until the sim has them: each entry is [floor, x_in_pixels_within_tower].
var people: Array[Array] = []


var _seen_revision: int = -1
var _seen_occupants: int = -1


## Redraws when the floors or rooms change; the view never polls the whole tower.
func _process(_delta: float) -> void:
	if tower == null:
		return
	var occupants := tower.grid.occupant_count()
	if tower.floors.revision != _seen_revision or occupants != _seen_occupants:
		_seen_revision = tower.floors.revision
		_seen_occupants = occupants
		queue_redraw()


func set_tower(value: Tower) -> void:
	tower = value
	queue_redraw()


func _draw() -> void:
	var cell := VC.CELL_PX
	var world := Rect2i(VC.world_rect())
	var ground_y := (Tower.Grid.FLOOR_MAX) * cell  # bottom of floor 1, top of B1
	draw_rect(Rect2i(-MARGIN, world.position.y - MARGIN, world.size.x + 2 * MARGIN, ground_y + MARGIN), SKY_COLOR)
	draw_rect(Rect2i(-MARGIN, ground_y, world.size.x + 2 * MARGIN, world.size.y - ground_y + MARGIN), GROUND_COLOR)
	draw_rect(Rect2i(-MARGIN, ground_y, world.size.x + 2 * MARGIN, 4), GRASS_COLOR)
	if tower == null:
		return
	_draw_grid(world)
	_draw_lobby()
	_draw_rooms()
	_draw_floors()  # last: a room fills its whole row and would hide its own slab
	_draw_people()


## Hairline lines (1 screen pixel at any zoom) every floor and every 10 columns.
func _draw_grid(world: Rect2i) -> void:
	var cell := VC.CELL_PX
	for row in range(0, Tower.Grid.FLOOR_COUNT + 1):
		draw_line(Vector2(0, row * cell), Vector2(world.size.x, row * cell), GRID_COLOR, -1.0)
	for column in range(0, Tower.Grid.WIDTH_UNITS + 1, 10):
		draw_line(Vector2(column * cell, 0), Vector2(column * cell, world.size.y), GRID_COLOR, -1.0)


## Built floor units: a thin slab along the bottom of each floor's row.
func _draw_floors() -> void:
	for index: int in Tower.Grid.FLOOR_COUNT:
		var floor_number := Tower.Grid.index_to_floor(index)
		var column := 0
		while column < Tower.Grid.WIDTH_UNITS:
			if not tower.floors.has_floor(floor_number, column):
				column += 1
				continue
			var start := column
			while column < Tower.Grid.WIDTH_UNITS and tower.floors.has_floor(floor_number, column):
				column += 1
			var y := (VC.floor_to_row(floor_number) + 1) * VC.CELL_PX - 3
			draw_rect(Rect2i(start * VC.CELL_PX, y, (column - start) * VC.CELL_PX, 3), FLOOR_COLOR)


## The ground lobby, in the lobby room colour, over floors 1 to its height.
func _draw_lobby() -> void:
	var span := tower.floors.lobby_span()
	if span.is_empty():
		return
	var color: Color = ROOM_COLORS[0]
	var rect := Rect2i(span[0] * VC.CELL_PX, VC.floor_to_row(span[2]) * VC.CELL_PX, (span[1] - span[0] + 1) * VC.CELL_PX, span[2] * VC.CELL_PX)
	draw_rect(rect, color)
	draw_rect(rect, color.darkened(0.5), false, 1.0)


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
			if tower.rooms.is_stairs_upper(id):
				column += grid.run_of(id)[2]
				continue
			var run := grid.run_of(id)
			if tower.rooms.kind_of(id) == "stairs":
				# Stairs span their own floor and the one above.
				var span := Rect2i(run[1] * VC.CELL_PX, VC.floor_to_row(Tower.RoomsScript.floor_above(floor_number)) * VC.CELL_PX, run[2] * VC.CELL_PX, 2 * VC.CELL_PX)
				draw_rect(span, KIND_COLORS["stairs"])
				draw_rect(span, KIND_COLORS["stairs"].darkened(0.5), false, 1.0)
				column += run[2]
				continue
			var rect := Rect2i(run[1] * VC.CELL_PX, VC.floor_to_row(floor_number) * VC.CELL_PX, run[2] * VC.CELL_PX, VC.CELL_PX)
			var color: Color = EMPTY_ROOM_COLOR
			if tower.rooms.has_room(id):
				color = KIND_COLORS.get(tower.rooms.kind_of(id), EMPTY_ROOM_COLOR)
			else:
				color = ROOM_COLORS.get(room_type_of.call(id), EMPTY_ROOM_COLOR)
			draw_rect(rect, color)
			draw_rect(rect, color.darkened(0.5), false, 1.0)
			column += run[2]


func _draw_people() -> void:
	for person in people:
		if not Tower.Grid.is_valid_floor(person[0]):
			continue
		var y: int = (VC.floor_to_row(person[0]) + 1) * VC.CELL_PX - PERSON_H
		draw_rect(Rect2i(person[1], y, PERSON_W, PERSON_H), PERSON_COLOR)
