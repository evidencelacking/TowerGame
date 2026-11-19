extends SceneTree
## Documentation capture for the room recipes (10.3, 10.4): a tower holding every kind of a batch, drawn by the
## real TowerRenderer, empty and with every room in use, saved as one PNG.
## Needs a window (headless has no renderer). Placement failures are printed, and the capture quits with
## an error when any room could not be placed, so a missing kind cannot pass unnoticed.
## Run: <godot exe> --path . --script res://tools/capture_recipes.gd -- set=1 out=docs/mockups/recipes_1.png
## set=1: lobby, offices, condos, hotel rooms, housekeeping (one view, empty above in use).
## set=2: everything else, in four views side by side (empty left, in use right): the shops and services with
## stairs, escalators and an elevator; the basement with parking and recycling; the metro; the cathedral.
## The sim cannot place the movie theatre, party hall, metro or cathedral yet, so those are drawn straight
## from their recipes at the spot where they would stand (SHOWCASE); everything else is placed for real.

const TowerSim := preload("res://scripts/sim/tower.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const RendererScript := preload("res://scripts/view/tower_renderer.gd")
const RoomLook := preload("res://scripts/view/room_look.gd")
const RoomRecipes := preload("res://scripts/view/room_recipes.gd")
const Palette := preload("res://scripts/view/palette.gd")
const VC := preload("res://scripts/view/view_consts.gd")

const LEFT := 100  ## First column of the capture tower.
const COLUMNS := 64
const GAP := 6  ## Pixels between pictures.
const SETTLE_FRAMES := 8  ## Frames to let the renderer draw before a screenshot.

## Rows of set 1: [floor, [[kind, count], ...]] from the bottom up; floor 1 is the lobby.
const SET_1: Array = [
	[3, [["office", 7]]],
	[4, [["condo", 4]]],
	[5, [["hotel_single", 3], ["hotel_twin", 2], ["hotel_suite", 3]]],
	[6, [["housekeeping", 4]]],
]
## Rooms of set 2 the sim places: [floor, kind, left column].
const PLACED_2: Array = [
	[3, "fast_food", 100], [3, "restaurant", 116], [3, "retail", 140],
	[4, "security", 100], [4, "medical", 116],
	[-1, "parking_ramp", 100], [-2, "parking_ramp", 100],
	[-1, "parking_space", 104], [-1, "parking_space", 108], [-1, "parking_space", 112], [-1, "parking_space", 116],
	[-2, "parking_space", 104], [-2, "parking_space", 108],
	[-3, "recycling", 124],
]
## Kinds the sim cannot place yet: [kind, floor, left column, upper half?], drawn from the recipe.
const SHOWCASE: Array = [
	["movie_theatre", 5, 100, false], ["movie_theatre", 6, 100, true],
	["party_hall", 5, 132, false],
	["metro", -10, 100, false], ["metro", -9, 100, true],
	["cathedral", 100, 100, false],
]
## Views of set 2: [top floor, bottom floor], each cropped around the capture columns.
const VIEWS_2: Array = [[6, 1], [-1, -3], [-9, -10], [100, 100]]

var _zoom: int = 3
var _set: int = 1
var _view: int = 0
var _stage: int = 0  ## 0 empty, 1 in use.
var _frames: int = 0
var _failed: bool = false
var _out: String = "docs/mockups/recipes_1.png"
var _tower: TowerSim = null
var _renderer: LitRenderer = null
var _camera: Camera2D = null
var _views: Array = []
var _shots: Array = []  ## [stage][view] images.


## The renderer with a switch that puts every room in its in-use look, and the showcase rooms drawn from recipes.
class LitRenderer:
	extends TowerRenderer

	var all_lit: bool = false
	var showcase: Array = []

	func _rooms_in_use() -> Dictionary:
		var used: Dictionary = {}
		if all_lit:
			for id: int in tower.rooms.room_ids():
				used[id] = true
		return used

	func _draw_rooms(canvas: CanvasItem) -> void:
		super._draw_rooms(canvas)
		for entry: Array in showcase:
			var kind: String = entry[0]
			var width := int(CatalogueScript.field(kind, "width")) * VC.CELL_W
			var rect := Rect2i(int(entry[2]) * VC.CELL_W, VC.floor_to_row(int(entry[1])) * VC.CELL_H, width, VC.CELL_H)
			RoomLook.draw_recipe(canvas, kind, rect, Palette.hue(RoomRecipes.hue_key(kind)), all_lit, bool(entry[3]))


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("set="):
			_set = int(arg.get_slice("=", 1))
		elif arg.begins_with("out="):
			_out = arg.get_slice("=", 1)
		elif arg.begins_with("zoom="):
			_zoom = maxi(int(arg.get_slice("=", 1)), 1)
	if _set == 1:
		var top := 2
		for row: Array in SET_1:
			top = maxi(top, row[0] as int)
		_views = [[top, 1]]
		_tower = _build_one()
	else:
		_views = VIEWS_2
		_tower = _build_two()
	_renderer = LitRenderer.new()
	if _set == 2:
		_renderer.showcase = SHOWCASE
	root.add_child(_renderer)
	_renderer.set_tower(_tower)
	_camera = Camera2D.new()
	root.add_child(_camera)
	_camera.zoom = Vector2(_zoom, _zoom)
	var widest := 0
	var tallest := 0
	for view: Array in _views:
		var rect := _view_rect(view)
		widest = maxi(widest, int(rect.size.x) * _zoom)
		tallest = maxi(tallest, int(rect.size.y) * _zoom)
	root.size = Vector2i(maxi(widest, 1280), maxi(tallest, 720))
	_shots = [[], []]
	_point_camera()


## The tower picture of a view: [top floor, bottom floor], a little margin around the columns.
func _view_rect(view: Array) -> Rect2:
	var top: int = view[0]
	var bottom: int = view[1]
	var y := VC.floor_to_row(top) * VC.CELL_H
	var height := (VC.floor_to_row(bottom) - VC.floor_to_row(top) + 1) * VC.CELL_H + 4
	return Rect2(LEFT * VC.CELL_W - 8, y, (COLUMNS + 8) * VC.CELL_W + 16, height)


func _point_camera() -> void:
	_camera.position = _view_rect(_views[_view]).get_center()


func _place(t: TowerSim, floor_number: int, kind: String, column: int) -> void:
	var code := t.rooms.place_room(t.grid, t.floors, t.ledger, 0, CatalogueScript.IDS.find(kind), floor_number, column)
	if code != RoomsScript.OK:
		printerr("could not place %s at floor %d column %d: code %d" % [kind, floor_number, column, code])
		_failed = true


func _new_tower() -> TowerSim:
	var t := TowerSim.new(7, 2000000000)
	t.stars = 5
	t.floors.build_lobby(t.ledger, 0, 1, LEFT, LEFT + COLUMNS - 1, 2)
	return t


func _build_one() -> TowerSim:
	var t := _new_tower()
	for row: Array in SET_1:
		var floor_number: int = row[0]
		t.floors.fill_span(floor_number, LEFT, LEFT + COLUMNS - 1)
		var x := LEFT
		for entry: Array in row[1]:
			var kind: String = entry[0]
			for n: int in (entry[1] as int):
				_place(t, floor_number, kind, x)
				x += int(CatalogueScript.field(kind, "width"))
	return t


func _build_two() -> TowerSim:
	var t := _new_tower()
	var right := LEFT + COLUMNS - 1
	for floor_number in [2, 3, 4, 5, 6, -1, -2, -3]:
		t.floors.fill_span(floor_number, LEFT, right)
	for floor_number in [-9, -10, 100]:
		t.floors.fill_span(floor_number, LEFT, right)
	for entry: Array in PLACED_2:
		_place(t, entry[0], entry[1], entry[2])
	_link(t, "escalator", 3, 152)
	_link(t, "escalator", 4, 152)  # a second flight straight above the first
	_link(t, "stairs", 3, 160)
	_link(t, "stairs", 4, 160)
	var shaft_code := t.rooms.place_shaft(t.grid, t.floors, t.ledger, 0, CatalogueScript.IDS.find("local_shaft"), 1, 6, right + 1)
	if shaft_code != RoomsScript.OK:
		printerr("could not place the shaft: code %d" % shaft_code)
		_failed = true
	else:
		for id: int in t.rooms.room_ids():
			if t.rooms.kind_of(id) == "local_shaft":
				t.rooms.add_car(t.ledger, 0, t.stars, id, 1)
	return t


## A flight of stairs or escalator. A refusal is reported but not fatal: flights stacked in the same columns
## are refused until #259 lands.
func _link(t: TowerSim, kind: String, floor_number: int, column: int) -> void:
	var code := RoomsScript.OK
	if kind == "stairs":
		code = t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, floor_number, column)
	else:
		code = t.rooms.place_escalator(t.grid, t.floors, t.ledger, 0, floor_number, column)
	if code != RoomsScript.OK:
		printerr("note: %s at floor %d column %d refused, code %d" % [kind, floor_number, column, code])


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false
	var full := root.get_texture().get_image()
	var size := Vector2i(_view_rect(_views[_view]).size * _zoom)
	_shots[_stage].append(full.get_region(Rect2i((full.get_size() - size) / 2, size)))
	_frames = 0
	_view += 1
	if _view < _views.size():
		_point_camera()
		return false
	_view = 0
	if _stage == 0:
		_stage = 1
		_renderer.all_lit = true
		_renderer.refresh_palette()
		_point_camera()
		return false
	_save()
	return true


## One PNG: a single view puts the empty picture above the in-use one, several views put each row's
## empty picture left of its in-use one.
func _save() -> void:
	var empties: Array = _shots[0]
	var lits: Array = _shots[1]
	var single := _views.size() == 1
	var width := 0
	var height := 0
	for n in empties.size():
		var img: Image = empties[n]
		if single:
			width = img.get_width()
			height = img.get_height() * 2 + GAP
		else:
			width = maxi(width, img.get_width() * 2 + GAP)
			height += img.get_height() + GAP
	var out := Image.create(width, height, false, (empties[0] as Image).get_format())
	out.fill(Color("101014"))
	var y := 0
	for n in empties.size():
		var empty: Image = empties[n]
		var lit: Image = lits[n]
		out.blit_rect(empty, Rect2i(Vector2i.ZERO, empty.get_size()), Vector2i(0, y))
		if single:
			out.blit_rect(lit, Rect2i(Vector2i.ZERO, lit.get_size()), Vector2i(0, y + empty.get_height() + GAP))
		else:
			out.blit_rect(lit, Rect2i(Vector2i.ZERO, lit.get_size()), Vector2i(empty.get_width() + GAP, y))
			y += empty.get_height() + GAP
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	var saved := out.save_png(_out)
	print("saved ", _out, " code ", saved, " size ", out.get_size())
	if _failed or saved != OK:
		quit(1)
