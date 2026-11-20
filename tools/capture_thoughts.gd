extends SceneTree
## Documentation capture for the thought icons (12.6): an office tower at work in the morning, every person
## set to a different mood or stress so each icon shows, drawn by the real TowerRenderer and ThoughtLayer in
## Classic (left) and Detailed (right) graphics. Needs a window (headless has no renderer).
## Run: <godot exe> --path . --script res://tools/capture_thoughts.gd -- out=docs/mockups/thought_icons.png
## The sim is not stepped, so the states set here stay; the show-window rule is off so every icon shows at once.
## The capture quits with an error when no icon was drawn.

const TowerSim := preload("res://scripts/sim/tower.gd")
const RendererScript := preload("res://scripts/view/tower_renderer.gd")
const ThoughtLayerScript := preload("res://scripts/view/thought_layer.gd")
const ThoughtIcons := preload("res://scripts/view/thought_icons.gd")
const MoodScript := preload("res://scripts/sim/mood.gd")
const ViewSettings := preload("res://scripts/view/view_settings.gd")
const TestOfficeDay := preload("res://tests/test_office_day.gd")
const VC := preload("res://scripts/view/view_consts.gd")

const ZOOM := 6
const SETTLE_FRAMES := 8
const GAP := 6
const LEFT_COLUMN := 98
const RIGHT_COLUMN := 134
const TOP_FLOOR := 4
const BOTTOM_FLOOR := 1

var _out: String = "docs/mockups/thought_icons.png"
var _tower: TowerSim = null
var _camera: Camera2D = null
var _frames: int = 0
var _stage: int = 0  ## 0 Classic, 1 Detailed.
var _shots: Array[Image] = []
var _layer: ThoughtLayer = null


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out = arg.get_slice("=", 1)
	_tower = TestOfficeDay._filled()
	print("people %d, icons by kind %s" % [_tower.people.count(), str(_force_states())])
	var renderer: TowerRenderer = RendererScript.new()
	root.add_child(renderer)
	renderer.set_tower(_tower)
	_layer = ThoughtLayerScript.new()
	_layer.respect_window = false
	root.add_child(_layer)
	_layer.bind(_tower, renderer)
	_camera = Camera2D.new()
	root.add_child(_camera)
	_camera.zoom = Vector2(ZOOM, ZOOM)
	var rect := _view_rect()
	root.size = Vector2i(rect.size * ZOOM) + Vector2i(64, 64)
	_camera.position = rect.get_center()
	ViewSettings.detailed_graphics = false


## The tower picture: a few floors, with room above the top one for the bubbles.
func _view_rect() -> Rect2:
	var y := VC.floor_to_row(TOP_FLOOR) * VC.CELL_H - 24
	var bottom := (VC.floor_to_row(BOTTOM_FLOOR) + 1) * VC.CELL_H
	return Rect2(LEFT_COLUMN * VC.CELL_W, y, (RIGHT_COLUMN - LEFT_COLUMN) * VC.CELL_W, bottom - y)


## Gives each person in turn a different state: waiting, unhappy, happy, calm. Returns how many show each icon.
func _force_states() -> Dictionary:
	var counts: Dictionary = {}
	for i in _tower.people.count():
		_tower.people.set_stress(i, 0)
		_tower.people.set_mood(i, 60)
		match i % 4:
			0: _tower.people.set_stress(i, 200)
			1: _tower.people.set_mood(i, 10)
			2: _tower.people.set_mood(i, 95)
	var floor_counts := MoodScript.floor_counts(_tower.people, _tower.grid, _tower.floors)
	for i in _tower.people.count():
		var name: String = ThoughtIcons.NAMES[ThoughtIcons.state_of(_tower, i, floor_counts)]
		counts[name] = counts.get(name, 0) + 1
	return counts


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false
	var full := root.get_texture().get_image()
	var size := Vector2i(_view_rect().size * ZOOM)
	_shots.append(full.get_region(Rect2i((full.get_size() - size) / 2, size)))
	_frames = 0
	if _stage == 0:
		_stage = 1
		ViewSettings.detailed_graphics = true
		return false
	_save()
	return true


func _save() -> void:
	var a := _shots[0]
	var b := _shots[1]
	var out := Image.create(a.get_width() * 2 + GAP, a.get_height(), false, a.get_format())
	out.fill(Color("101014"))
	out.blit_rect(a, Rect2i(Vector2i.ZERO, a.get_size()), Vector2i.ZERO)
	out.blit_rect(b, Rect2i(Vector2i.ZERO, b.get_size()), Vector2i(a.get_width() + GAP, 0))
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	var saved := out.save_png(_out)
	print("saved ", _out, " code ", saved, " size ", out.get_size(), ", icons drawn ", _layer.picks().size())
	if saved != OK or _layer.picks().is_empty():
		quit(1)
