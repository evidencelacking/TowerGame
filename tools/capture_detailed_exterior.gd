extends SceneTree
## Documentation capture for the Detailed exterior (#306): a stepped tower seen from the street, by day at two
## stars (a small city) and at night at five stars (a big one, windows and lamps lit), drawn by the real
## TowerRenderer in the Detailed graphics style and saved as one PNG, day above night.
## Needs a window (headless has no renderer).
## Run: <godot exe> --path . --script res://tools/capture_detailed_exterior.gd -- out=docs/mockups/detailed_exterior.png
## Options: out=PATH, zoom=N (use an even number), classic=1 draws Classic instead, for comparison.

const TowerSim := preload("res://scripts/sim/tower.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const ViewSettings := preload("res://scripts/view/view_settings.gd")
const VC := preload("res://scripts/view/view_consts.gd")

const LEFT := 100  ## First column of the capture tower.
const COLUMNS := 64
const SIDE := 150  ## World pixels of street and sky shown beside the tower.
const SETTLE_FRAMES := 10  ## Frames to let the renderer draw before a screenshot.
const GAP := 6
const TOP_FLOOR := 12
const DAY_MINUTE := 12 * 60
const NIGHT_MINUTE := 23 * 60

var _zoom: int = 2
var _out: String = "docs/mockups/detailed_exterior.png"
var _classic: bool = false
var _failed: bool = false
var _frames: int = 0
var _stage: int = 0  ## 0 day at two stars, 1 night at five stars.
var _style_set: bool = false
var _tower: TowerSim = null
var _renderer: LitRenderer = null
var _camera: Camera2D = null
var _shots: Array[Image] = []


## The renderer with a switch that puts every room in its lit look, so the night picture glows.
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
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out = arg.get_slice("=", 1)
		elif arg == "classic=1":
			_classic = true
		elif arg.begins_with("zoom="):
			_zoom = maxi(int(arg.get_slice("=", 1)), 1)
	_tower = TowerSim.new(7, 2000000000)
	_build(_tower)
	_renderer = LitRenderer.new()
	root.add_child(_renderer)
	_set_time(DAY_MINUTE)
	_tower.stars = 2
	_renderer.set_tower(_tower)
	_camera = Camera2D.new()
	root.add_child(_camera)
	_camera.zoom = Vector2(_zoom, _zoom)
	var size := _view_rect().size * _zoom
	root.size = Vector2i(maxi(int(size.x), 1280), maxi(int(size.y), 720))
	_camera.position = _view_rect().get_center()


## The picture's rectangle in world pixels: the tower, street and sky beside it, down to the road.
func _view_rect() -> Rect2:
	var top := VC.floor_to_row(TOP_FLOOR + 1) * VC.CELL_H - 20
	var bottom := VC.floor_to_row(1) * VC.CELL_H + VC.CELL_H + 44
	return Rect2(LEFT * VC.CELL_W - SIDE, top, COLUMNS * VC.CELL_W + 2 * SIDE, bottom - top)


func _set_time(minute: int) -> void:
	_tower.clock.set_to_tick(0)
	_tower.clock.set_to_tick(_tower.clock.ticks_until_minute(minute))


func _place(floor_number: int, kind: String, column: int) -> void:
	var code := _tower.rooms.place_room(_tower.grid, _tower.floors, _tower.ledger, 0, CatalogueScript.IDS.find(kind), floor_number, column)
	if code != RoomsScript.OK:
		printerr("could not place %s at floor %d column %d: code %d" % [kind, floor_number, column, code])
		_failed = true


## A lobby, then floors that step in as they rise, so there are roofs at three heights.
func _build(t: TowerSim) -> void:
	t.floors.build_lobby(t.ledger, 0, 1, LEFT, LEFT + COLUMNS - 1, 2)
	for floor_number in range(3, 7):
		t.floors.fill_span(floor_number, LEFT, LEFT + COLUMNS - 1)
	for floor_number in range(7, 10):
		t.floors.fill_span(floor_number, LEFT + 8, LEFT + COLUMNS - 9)
	for floor_number in range(10, TOP_FLOOR + 1):
		t.floors.fill_span(floor_number, LEFT + 20, LEFT + COLUMNS - 21)
	for column in [LEFT, LEFT + 9, LEFT + 18, LEFT + 27]:
		_place(3, "office", column)
	for column in [LEFT]:
		_place(4, "condo", column)
	for column in [LEFT + 8, LEFT + 17, LEFT + 26]:
		_place(7, "office", column)


func _process(_delta: float) -> bool:
	if _frames == 0 and not _style_set:  # the renderer reads the saved settings in its _ready, so set the style after it
		_style_set = true
		ViewSettings.detailed_graphics = not _classic
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false
	var full := root.get_texture().get_image()
	var size := Vector2i(_view_rect().size * _zoom)
	_shots.append(full.get_region(Rect2i((full.get_size() - size) / 2, size)))
	_frames = 0
	if _stage == 0:
		_stage = 1
		_tower.stars = 5
		_set_time(NIGHT_MINUTE)
		_renderer.all_lit = true
		_renderer.refresh_palette()
		return false
	_save()
	return true


func _save() -> void:
	var day: Image = _shots[0]
	var night: Image = _shots[1]
	var out := Image.create(day.get_width(), day.get_height() * 2 + GAP, false, day.get_format())
	out.fill(Color("101014"))
	out.blit_rect(day, Rect2i(Vector2i.ZERO, day.get_size()), Vector2i.ZERO)
	out.blit_rect(night, Rect2i(Vector2i.ZERO, night.get_size()), Vector2i(0, day.get_height() + GAP))
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	var saved := out.save_png(_out)
	print("saved ", _out, " code ", saved, " size ", out.get_size())
	if _failed or saved != OK:
		quit(1)
