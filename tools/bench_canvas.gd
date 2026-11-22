extends SceneTree
## Canvas memory and frame-time benchmark (#307): the benchmark tower drawn by the real TowerRenderer under a
## Camera2D, in the style and zoom given. Reports render-target memory, video memory, the cost of a static
## rebuild and the frame time while the camera scrolls. Needs a window (headless has no renderer): it quits
## with an error when the memory monitors read 0, since the numbers would then mean nothing.
## edit=1 also bulldozes and rebuilds a room near the camera (#349): the frame times of each edit are reported
## and, with shot=PATH, a PNG after the bulldoze (PATH_bulldoze.png) and after the rebuild (PATH_build.png)
## is saved, to diff Classic and Detailed renders between two versions of the renderer (compare the bytes).
## Run: timeout 120 <godot exe> --path . --script res://tools/bench_canvas.gd -- style=detailed zoom=2
const Bench := preload("res://tools/bench_tower.gd")
const RendererScript := preload("res://scripts/view/tower_renderer.gd")
const ViewSettings := preload("res://scripts/view/view_settings.gd")
const VC := preload("res://scripts/view/view_consts.gd")
const TransportGlass := preload("res://scripts/view/transport_glass.gd")

const SETTLE_FRAMES := 30  ## Idle frames before the forced rebuild, so the GPU has drained the warmup renders and does not bill them to it.
const REBUILD_FROM := 30  ## Frames of warmup at least, and until the first draw has finished.
const REBUILD_MAX_FRAMES := 1500  ## Give up waiting for the tiles after this many frames.
const SCROLL_FRAMES := 200

var _tower: Tower = null
var _renderer: TowerRenderer = null
var _camera: Camera2D = null
var _n: int = 0  ## Frames seen; the run ends after the scroll.
var _detailed: bool = true
var _zoom: int = 2
var _shot: String = ""  ## shot=PATH saves the last frame as a PNG.
var _rebuild: Array[int] = []
var _scroll: Array[int] = []
var _last: int = 0
var _phase: int = 0  ## 0 warm up, 1 rebuild, 2 scroll, 3 report.
var _phase_start: int = 0
var _idle: int = 0
var _edit: bool = false
var _links: bool = false  ## links=1 adds a stairs and an escalator near the camera (#367).
var _glass: bool = true  ## glass=0 draws Detailed transport opaque, as before #367.
var _edit_step: int = 0  ## 0 not started, 1 bulldozed (waiting for the tiles), 2 rebuilt (waiting).
var _edit_room: Array[int] = []  ## [kind index, floor, column] of the room edited.
var _edit_frames: Array[int] = []
var _edit_wait: int = 0
var _edit_last: int = 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("style="):
			_detailed = arg.get_slice("=", 1) == "detailed"
		elif arg.begins_with("zoom="):
			_zoom = int(arg.get_slice("=", 1))
		elif arg == "edit=1":
			_edit = true
		elif arg.begins_with("shot="):
			_shot = arg.get_slice("=", 1)
		elif arg == "links=1":
			_links = true
		elif arg == "glass=0":
			_glass = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_tower = Bench.build(42)
	_renderer = RendererScript.new()
	root.add_child(_renderer)
	_camera = Camera2D.new()
	root.add_child(_camera)
	_last = Time.get_ticks_usec()


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	_n += 1
	if _n == 1:  # the nodes are in the tree now, and the renderer's _ready has loaded the saved setting
		ViewSettings.detailed_graphics = _detailed
		if not _glass:
			TransportGlass.on = false
		_renderer.set_tower(_tower)
		_camera.zoom = Vector2(_zoom, _zoom)
		_camera.position = Vector2(1600, 3000)
		_camera.make_current()
		_last = now
		return false
	if _n == 10 and _links:  # placed as a player would, once the tower is on screen
		_tower.ledger.balance = maxi(_tower.ledger.balance, 100000000)
		var stairs_code: int = _tower.rooms.place_stairs(_tower.grid, _tower.floors, _tower.ledger, 0, 5, 330)
		var escalator_code: int = _tower.rooms.place_escalator(_tower.grid, _tower.floors, _tower.ledger, 0, 1, 340)
		print("links: stairs code %d, escalator code %d, link cells %d" % [stairs_code, escalator_code, _tower.rooms.links.occupant_count()])
	if _phase == 0:
		_idle = _idle + 1 if (not _renderer.has_method("pending_work") or int(_renderer.call("pending_work")) == 0) else 0
	if _phase == 0 and _n >= REBUILD_FROM and _idle >= SETTLE_FRAMES:  # one forced full rebuild, timed frame by frame until every tile near the view is redrawn
		_renderer.refresh_palette()
		_phase = 1
		_phase_start = _n
	elif _phase == 1:
		_rebuild.append(now - _last)
		var settled := not _renderer.has_method("pending_work") or (_n - _phase_start > 2 and int(_renderer.call("pending_work")) == 0)
		if settled or _n - _phase_start > REBUILD_MAX_FRAMES:
			_phase = 2
			_phase_start = _n
	elif _phase == 2:
		if _n - _phase_start > SCROLL_FRAMES:
			_phase = 3
		else:
			_camera.position.x += 6.0
			_scroll.append(now - _last)
	_last = now
	if _phase == 3 and _edit and not _edit_done():
		return false
	if _phase < 3:
		return false
	var tex := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0
	var video := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	print("style=%s zoom=%d" % ["detailed" if ViewSettings.detailed_graphics else "classic", _zoom])
	print("  render_texture_mem_mb=%.1f video_mem_mb=%.1f" % [tex, video])
	print("  full static rebuild: %d frames, %.2f ms avg, %.2f ms worst   scroll frame: %.2f ms avg, %.2f ms worst" % [_rebuild.size(), _avg(_rebuild), _worst(_rebuild), _avg(_scroll), _worst(_scroll)])
	var top := _rebuild.duplicate()
	top.sort()
	top.reverse()
	print("  slowest rebuild frames ms: ", top.slice(0, 6).map(func(v: int) -> float: return v / 1000.0))
	if _edit:
		print("  edit frames (bulldoze then rebuild, until settled): %d frames, %.2f ms avg, %.2f ms worst" % [_edit_frames.size(), _avg(_edit_frames), _worst(_edit_frames)])
		var slow := _edit_frames.duplicate()
		slow.sort()
		slow.reverse()
		print("  slowest edit frames ms (frame order of the worst: %d): " % _edit_frames.find(slow[0]), slow.slice(0, 6).map(func(v: int) -> float: return v / 1000.0))
	if _shot != "" and not _edit and root.get_texture().get_image().save_png(_shot) != OK:
		push_error("could not save " + _shot)
	if tex <= 0.0:
		push_error("texture memory reads 0: no renderer, so nothing was measured")
	return true


## Bulldozes a room near the camera, waits for the picture to settle, saves a shot, rebuilds it, waits and saves
## again. True once both are done. Every frame from the first edit on is timed into _edit_frames.
func _edit_done() -> bool:
	var now := Time.get_ticks_usec()
	if _edit_step == 0:
		_camera.position = Vector2(1600, 3000)
		var best := -1
		var best_distance := 1 << 60
		for id: int in _tower.rooms.room_ids():
			if _tower.rooms.kind_of(id) != "office":
				continue
			var at := _tower.grid.run_of(id)
			var d := absi(at[1] * VC.CELL_W - 1600) + absi(VC.floor_to_row(at[0]) * VC.CELL_H - 3000)
			if d < best_distance:
				best = id
				best_distance = d
		var at := _tower.grid.run_of(best)
		_edit_room = [Tower.CatalogueScript.IDS.find("office"), at[0], at[1]]
		_tower.ledger.balance = maxi(_tower.ledger.balance, 100000000)
		_tower.rooms.bulldoze(_tower.grid, _tower.floors, _tower.ledger, _tower.tick, _edit_room[1], _edit_room[2])
		_edit_step = 1
		_edit_wait = 0
		_edit_last = now
		return false
	_edit_frames.append(now - _edit_last)
	_edit_last = now
	_edit_wait += 1
	if _edit_wait < 3 or int(_renderer.call("pending_work")) != 0:
		return false
	if _shot != "":
		root.get_texture().get_image().save_png(_shot.get_basename() + ("_bulldoze.png" if _edit_step == 1 else "_build.png"))
	_edit_last = Time.get_ticks_usec()  # the PNG write is not a frame
	if _edit_step == 1:
		_tower.rooms.place_room(_tower.grid, _tower.floors, _tower.ledger, _tower.tick, _edit_room[0], _edit_room[1], _edit_room[2])
		_edit_step = 2
		_edit_wait = 0
		return false
	return true


func _worst(a: Array[int]) -> float:
	var w := 0
	for v: int in a:
		w = maxi(w, v)
	return w / 1000.0


func _avg(a: Array[int]) -> float:
	var t := 0
	for v: int in a:
		t += v
	return t / 1000.0 / maxi(a.size(), 1)
