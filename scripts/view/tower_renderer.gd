class_name TowerRenderer
extends Node2D
const VC := preload("res://scripts/view/view_consts.gd")
const PeopleView := preload("res://scripts/view/people_view.gd")
const ElevatorView := preload("res://scripts/view/elevator_view.gd")
## Draws the tower with native shapes only. Reads the Tower read-only; never mutates sim state.
## All geometry is integer pixels from view_consts.gd, so edges stay aligned at any zoom.

const SKY_COLOR := Color(0.53, 0.78, 0.95)
const GROUND_COLOR := Color(0.36, 0.26, 0.17)
const GRASS_COLOR := Color(0.30, 0.62, 0.25)
const FLOOR_COLOR := Color(0.16, 0.16, 0.20)
const GRID_COLOR := Color(1, 1, 1, 0.12)
const EMPTY_ROOM_COLOR := Color(0.85, 0.2, 0.85)
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

## Back to front. Links (stairs, escalators) and shafts sit in front of the rooms behind them (#126);
## floors come after rooms because a room fills its whole row and would hide its own slab.
const DRAW_ORDER: Array[String] = ["_draw_lobby", "_draw_rooms", "_draw_links", "_draw_floors", "_draw_shafts", "_draw_queues", "_draw_cars", "_draw_people"]

var tower: Tower = null
## Colour of each placed room kind (catalogue id). Rooms placed by PLACE_ROOM use these.
const KIND_COLORS: Dictionary = {
	"office": Color(0.55, 0.70, 0.90),
	"condo": Color(0.85, 0.65, 0.85),
	"stairs": Color(0.80, 0.72, 0.45),
	"escalator": Color(0.35, 0.75, 0.80),
}

## Maps an occupant id to a ROOM_COLORS key. Replace once the sim stores room types.
var room_type_of: Callable = func(id: int) -> int: return id % ROOM_COLORS.size()
var _people_view := PeopleView.new()
var _seen_tick: int = -1
var _elevators := ElevatorView.new()
var _since_tick: float = 0.0  ## Seconds since the sim last ticked.
var _tick_len: float = 1.0 / 30.0  ## Seconds the last tick took; cars slide over this long.

var _seen_revision: int = -1
var _seen_occupants: int = -1


## Redraws when the floors or rooms change; the view never polls the whole tower.
func _process(delta: float) -> void:
	if tower == null:
		return
	_since_tick += delta
	if _elevators.observe(tower):
		_tick_len = maxf(_since_tick, 0.001)
		_since_tick = 0.0
	var occupants := tower.grid.occupant_count() + tower.rooms.links.occupant_count()
	if tower.floors.revision != _seen_revision or occupants != _seen_occupants:
		_seen_revision = tower.floors.revision
		_seen_occupants = occupants
		_people_view.route_cache.clear()
		queue_redraw()
	elif tower.tick != _seen_tick:
		queue_redraw()  # people move
	_seen_tick = tower.tick
	if tower.rooms.total_cars() > 0 and _since_tick <= _tick_len * 2.0:
		queue_redraw()  # cars slide between ticks


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
	for layer: String in DRAW_ORDER:
		call(layer)


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
			var run := grid.run_of(id)
			var rect := Rect2i(run[1] * VC.CELL_PX, VC.floor_to_row(floor_number) * VC.CELL_PX, run[2] * VC.CELL_PX, VC.CELL_PX)
			var color: Color = EMPTY_ROOM_COLOR
			if tower.rooms.has_room(id):
				color = KIND_COLORS.get(tower.rooms.kind_of(id), EMPTY_ROOM_COLOR)
			else:
				color = ROOM_COLORS.get(room_type_of.call(id), EMPTY_ROOM_COLOR)
			draw_rect(rect, color)
			draw_rect(rect, color.darkened(0.5), false, 1.0)
			column += run[2]


## Stairs and escalators (the link layer) in front of the rooms: each spans its own floor and the
## one above. Stairs are drawn with steps, escalators in teal with diagonal strips.
func _draw_links() -> void:
	var links := tower.rooms.links
	var seen: Dictionary = {}
	for index: int in Tower.Grid.FLOOR_COUNT:
		var floor_number := Tower.Grid.index_to_floor(index)
		var column := 0
		while column < Tower.Grid.WIDTH_UNITS:
			var id := links.cell_at(floor_number, column)
			if id == Tower.Grid.EMPTY or seen.has(id) or not Tower.RoomsScript.is_stair_kind(tower.rooms.kind_of(id)):
				column += 1
				continue
			seen[id] = true
			var run := links.run_of(id)
			var kind := tower.rooms.kind_of(id)
			var span := Rect2i(run[1] * VC.CELL_PX, VC.floor_to_row(Tower.RoomsScript.floor_above(floor_number)) * VC.CELL_PX, run[2] * VC.CELL_PX, 2 * VC.CELL_PX)
			var color: Color = KIND_COLORS[kind]
			draw_rect(span, color)
			draw_rect(span, color.darkened(0.5), false, 1.0)
			var strips := 4 if kind == "stairs" else 8
			for n in range(1, strips):  # steps (stairs) or slanted strips (escalator)
				var x := span.position.x + span.size.x * n / strips
				if kind == "escalator":
					draw_line(Vector2(x - VC.CELL_PX, span.end.y), Vector2(x, span.position.y), color.darkened(0.5), 1.0)
				else:
					draw_line(Vector2(x, span.end.y), Vector2(x, span.position.y + span.size.y * (strips - n) / strips), color.darkened(0.5), 1.0)
			column += run[2]


func _draw_people() -> void:
	for figure: Dictionary in _people_view.figures(tower):
		var band: int = figure["band"]
		var color := PeopleView.color_of(band)
		var x: int = (figure["x"] as int) * VC.CELL_PX + (VC.CELL_PX - PERSON_W) / 2
		var base: int = (VC.floor_to_row(figure["floor"]) + 1) * VC.CELL_PX - 3
		draw_rect(Rect2i(x, base - 7, PERSON_W, 7), color)  # body
		draw_circle(Vector2(x + PERSON_W / 2.0, base - 9), 2.0, color)  # head
		for mark in PeopleView.marks_of(band):  # shape cue: one dot uneasy, two angry
			draw_rect(Rect2i(x + mark * 3 - 1, base - 14, 2, 2), color)


const SHAFT_COLOR := Color(0.12, 0.13, 0.17)
const DOOR_COLOR := Color(0.75, 0.80, 0.85)
const DISABLED_COLOR := Color(0.75, 0.25, 0.25)
const CAR_COLOR := Color(0.95, 0.85, 0.30)
const FONT_SIZE: int = 8


## Each shaft across its span; a floor it stops at has a door mark, a disabled one a red cross.
func _draw_shafts() -> void:
	var cell := VC.CELL_PX
	for shaft: Dictionary in ElevatorView.shafts(tower):
		var top_row := VC.floor_to_row(shaft["top"])
		var bottom_row := VC.floor_to_row(shaft["bottom"])
		var rect := Rect2i((shaft["x"] as int) * cell, top_row * cell, (shaft["width"] as int) * cell, (bottom_row - top_row + 1) * cell)
		draw_rect(rect, SHAFT_COLOR)
		draw_rect(rect, SHAFT_COLOR.lightened(0.4), false, 1.0)
		for floor_number: int in shaft["stops"]:
			var y := (VC.floor_to_row(floor_number) + 1) * cell - 3
			draw_rect(Rect2i(rect.position.x + 2, y, rect.size.x - 4, 2), DOOR_COLOR)
		for floor_number: int in shaft["disabled"]:
			var top := VC.floor_to_row(floor_number) * cell
			var inset := Rect2(rect.position.x + 4, top + 3, rect.size.x - 8, cell - 6)
			draw_line(inset.position, inset.end, DISABLED_COLOR, 1.0)
			draw_line(Vector2(inset.position.x, inset.end.y), Vector2(inset.end.x, inset.position.y), DISABLED_COLOR, 1.0)


## Cars at their interpolated place, each with its load, e.g. 12/17.
func _draw_cars() -> void:
	var cell := VC.CELL_PX
	var t := clampf(_since_tick / _tick_len, 0.0, 1.0)
	for car: Dictionary in _elevators.cars(tower, t):
		var rect := Rect2((car["x"] as int) * cell + 1, ElevatorView.level_to_y(car["level"], cell) + 1, (car["width"] as int) * cell - 2, cell - 2)
		draw_rect(rect, CAR_COLOR)
		draw_rect(rect, CAR_COLOR.darkened(0.5), false, 1.0)
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(2, cell - 5), car["label"], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 2, FONT_SIZE, Color.BLACK)


## Hall queues: people going up wait left of the shaft, going down right of it; a long queue
## shows its first figures and a +N count.
func _draw_queues() -> void:
	var cell := VC.CELL_PX
	for queue: Dictionary in ElevatorView.queues(tower):
		var side: int = queue["side"]
		var base := (VC.floor_to_row(queue["floor"]) + 1) * cell - 3
		var edge: int = (queue["x"] as int) * cell if side < 0 else ((queue["x"] as int) + (queue["width"] as int)) * cell
		var color := Color(0.05, 0.05, 0.05)
		for n: int in queue["shown"]:
			var x := edge - (n + 1) * (PERSON_W + 2) if side < 0 else edge + 2 + n * (PERSON_W + 2)
			draw_rect(Rect2i(x, base - 7, PERSON_W, 7), color)
			draw_circle(Vector2(x + PERSON_W / 2.0, base - 9), 2.0, color)
		var label: String = queue["label"]
		if label != "":
			var shown_px: int = (queue["shown"] as int) * (PERSON_W + 2)
			var label_x := edge - shown_px - 18 if side < 0 else edge + shown_px + 4
			draw_string(ThemeDB.fallback_font, Vector2(label_x, base), label, HORIZONTAL_ALIGNMENT_LEFT, 16, FONT_SIZE, Color.BLACK)
