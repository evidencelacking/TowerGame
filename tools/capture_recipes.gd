extends SceneTree
## Documentation capture for the room recipes (10.3, 10.4): a tower holding every kind of a batch, drawn by the
## real TowerRenderer, empty (top) and with every room in use (bottom), saved as one PNG at 3x.
## Needs a window (headless has no renderer). Placement failures are printed, and the capture quits with
## an error when any room could not be placed, so a missing kind cannot pass unnoticed.
## Run: <godot exe> --path . --script res://tools/capture_recipes.gd -- set=1 out=docs/mockups/recipes_1.png
## set=1: lobby, offices, condos, hotel rooms, housekeeping. set=2: everything else.

const TowerSim := preload("res://scripts/sim/tower.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const RendererScript := preload("res://scripts/view/tower_renderer.gd")
const VC := preload("res://scripts/view/view_consts.gd")

const ZOOM := 3
const LEFT := 100  ## First column of the capture tower.
const COLUMNS := 64
const GAP := 6  ## Pixels between the empty and in-use halves of the picture.
const SETTLE_FRAMES := 8  ## Frames to let the renderer draw before a screenshot.

## Rows of a set: [floor, [[kind, count], ...]] from the bottom up; floor 1 is the lobby.
const SET_1: Array = [
	[3, [["office", 7]]],
	[4, [["condo", 4]]],
	[5, [["hotel_single", 3], ["hotel_twin", 2], ["hotel_suite", 3]]],
	[6, [["housekeeping", 4]]],
]
const SET_2: Array = []

var _stage: int = 0
var _frames: int = 0
var _failed: bool = false
var _out: String = "docs/mockups/recipes_1.png"
var _top: Image = null
var _tower: TowerSim = null
var _crop: Vector2i = Vector2i.ZERO  ## Size of the tower picture in screen pixels, cut from the window centre.
var _renderer: LitRenderer = null


## The renderer with a switch that puts every room in its in-use look.
class LitRenderer:
	extends TowerRenderer

	var all_lit: bool = false

	func _rooms_in_use() -> Dictionary:
		var used: Dictionary = {}
		if all_lit:
			for id: int in tower.rooms.room_ids():
				used[id] = true
		return used


func _initialize() -> void:
	var rows: Array = SET_1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("set="):
			rows = SET_1 if int(arg.get_slice("=", 1)) == 1 else SET_2
		elif arg.begins_with("out="):
			_out = arg.get_slice("=", 1)
	_tower = _build(rows)
	_renderer = LitRenderer.new()
	root.add_child(_renderer)
	_renderer.set_tower(_tower)
	var top_floor := 2
	for row: Array in rows:
		top_floor = maxi(top_floor, row[0] as int)
	var rect := Rect2(LEFT * VC.CELL_W - 8, VC.floor_to_row(top_floor) * VC.CELL_H, COLUMNS * VC.CELL_W + 16, top_floor * VC.CELL_H + 4)
	var camera := Camera2D.new()
	root.add_child(camera)
	camera.zoom = Vector2(ZOOM, ZOOM)
	camera.position = rect.get_center()
	_crop = Vector2i(int(rect.size.x) * ZOOM, int(rect.size.y) * ZOOM)
	root.size = Vector2i(maxi(_crop.x, 1280), maxi(_crop.y, 720))


func _build(rows: Array) -> TowerSim:
	var t := TowerSim.new(7, 2000000000)
	t.stars = 5
	t.floors.build_lobby(t.ledger, 0, 1, LEFT, LEFT + COLUMNS - 1, 2)
	for row: Array in rows:
		var floor_number: int = row[0]
		t.floors.fill_span(floor_number, LEFT, LEFT + COLUMNS - 1)
		var x := LEFT
		for entry: Array in row[1]:
			var kind: String = entry[0]
			for n: int in (entry[1] as int):
				var code := t.rooms.place_room(t.grid, t.floors, t.ledger, 0, CatalogueScript.IDS.find(kind), floor_number, x)
				if code != RoomsScript.OK:
					printerr("could not place %s at floor %d column %d: code %d" % [kind, floor_number, x, code])
					_failed = true
				x += int(CatalogueScript.field(kind, "width"))
	return t


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false
	var full := root.get_texture().get_image()
	var image := full.get_region(Rect2i((full.get_size() - _crop) / 2, _crop))
	if _stage == 0:
		_top = image
		_renderer.all_lit = true
		_renderer.refresh_palette()
		_stage = 1
		_frames = 0
		return false
	var out := Image.create(image.get_width(), image.get_height() * 2 + GAP, false, image.get_format())
	out.fill(Color("101014"))
	out.blit_rect(_top, Rect2i(Vector2i.ZERO, _top.get_size()), Vector2i.ZERO)
	out.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(0, image.get_height() + GAP))
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	var saved := out.save_png(_out)
	print("saved ", _out, " code ", saved, " size ", out.get_size())
	if _failed or saved != OK:
		quit(1)
	return true
