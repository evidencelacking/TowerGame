extends SceneTree
## Documentation capture for the synergy overlay (#294): a small tower with a gym among offices, a daycare
## among condos and a clinic, drawn by the real TowerRenderer with the overlay on and an office hovered, in
## Classic (top) and Detailed (bottom), saved as one PNG. Needs a window (headless has no renderer); quits
## with an error when a room could not be placed, the overlay is missing, or the picture could not be saved.
## Run: <godot exe> --path . --script res://tools/capture_synergy_overlay.gd -- out=docs/mockups/synergy_overlay.png

const TowerSim := preload("res://scripts/sim/tower.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const SynergyLook := preload("res://scripts/view/synergy_look.gd")
const ViewSettings := preload("res://scripts/view/view_settings.gd")
const VC := preload("res://scripts/view/view_consts.gd")

const LEFT := 100
const COLUMNS := 64
const ZOOM := 3
const SETTLE_FRAMES := 10
const MAX_FRAMES := 600  ## Give up (with an error) if the window never produces frames.
## [floor, [[kind, count], ...]] from the bottom up.
const ROWS: Array = [
	[3, [["office", 3], ["gym", 1], ["office", 2]]],
	[4, [["condo", 2], ["daycare", 1], ["condo", 1]]],
	[5, [["office", 2], ["clinic", 1], ["office", 2]]],
]

var _frames: int = 0
var _total: int = 0
var _stage: int = 0  ## 0 Classic, 1 Detailed.
var _failed: bool = false
var _out: String = "docs/mockups/synergy_overlay.png"
var _tower: TowerSim = null
var _renderer: TowerRenderer = null
var _overlay: SynergyOverlay = null
var _shots: Array[Image] = []


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out = arg.get_slice("=", 1)
	_tower = TowerSim.new(7, 2000000000)
	_tower.stars = 5
	_tower.floors.build_lobby(_tower.ledger, 0, 1, LEFT, LEFT + COLUMNS - 1, 2)
	for row: Array in ROWS:
		var floor_number: int = row[0]
		_tower.floors.fill_span(floor_number, LEFT, LEFT + COLUMNS - 1)
		var x := LEFT
		for entry: Array in row[1]:
			var kind: String = entry[0]
			for n: int in (entry[1] as int):
				var code := _tower.rooms.place_room(_tower.grid, _tower.floors, _tower.ledger, 0, CatalogueScript.IDS.find(kind), floor_number, x)
				if code != RoomsScript.OK:
					printerr("could not place %s at floor %d column %d: code %d" % [kind, floor_number, x, code])
					_failed = true
				x += int(CatalogueScript.field(kind, "width"))
	_renderer = TowerRenderer.new()
	root.add_child(_renderer)
	_renderer.set_tower(_tower)
	var camera := Camera2D.new()
	root.add_child(camera)
	camera.zoom = Vector2(ZOOM, ZOOM)
	var top := VC.floor_to_row(5) * VC.CELL_H
	camera.position = Vector2((LEFT + COLUMNS / 2) * VC.CELL_W, top + 1.5 * VC.CELL_H)
	root.size = Vector2i(COLUMNS * VC.CELL_W * ZOOM + 80, 3 * VC.CELL_H * ZOOM + 40)
	SynergyLook.on = true


func _process(_delta: float) -> bool:
	_total += 1
	if _failed or _total > MAX_FRAMES:
		quit(1)
		return true
	if _overlay == null:  # the renderer's children exist once the tree has run its first frame
		for child: Node in _renderer.get_children():
			if child is SynergyOverlay:
				_overlay = child
		if _overlay == null:
			printerr("the renderer has no synergy overlay")
			quit(1)
			return true
		for id: int in _tower.rooms.room_ids():
			if _tower.rooms.kind_of(id) == "office":
				_overlay.hover_override = id  # the first office: its links point at the gym
				break
	if _frames == 0:  # the renderer reads the saved style in its _ready, so set it after
		ViewSettings.detailed_graphics = _stage == 1
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false
	_shots.append(root.get_texture().get_image())
	_frames = 0
	_stage += 1
	if _stage < 2:
		return false
	var width := _shots[0].get_width()
	var height := _shots[0].get_height()
	var sheet := Image.create(width, height * 2 + 6, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.BLACK)
	sheet.blit_rect(_shots[0], Rect2i(0, 0, width, height), Vector2i(0, 0))
	sheet.blit_rect(_shots[1], Rect2i(0, 0, width, height), Vector2i(0, height + 6))
	var err := sheet.save_png(_out)
	print("saved ", _out, " code ", err)
	quit(0 if err == OK else 1)
	return true
