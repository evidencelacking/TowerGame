extends SceneTree
## Canvas memory and frame-time benchmark (#307): the benchmark tower drawn by the real TowerRenderer under a
## Camera2D, in the style and zoom given. Reports render-target memory, video memory, the cost of a static
## rebuild and the frame time while the camera scrolls. Needs a window (headless has no renderer): it quits
## with an error when the memory monitors read 0, since the numbers would then mean nothing.
## Run: timeout 120 <godot exe> --path . --script res://tools/bench_canvas.gd -- style=detailed zoom=2
const Bench := preload("res://tools/bench_tower.gd")
const RendererScript := preload("res://scripts/view/tower_renderer.gd")
const ViewSettings := preload("res://scripts/view/view_settings.gd")

const REBUILD_FROM := 30  ## Frames of warmup, then REBUILD_FRAMES frames each forcing a static rebuild.
const REBUILD_FRAMES := 100
const SCROLL_FROM := 140
const SCROLL_FRAMES := 200

var _tower: Tower = null
var _renderer: TowerRenderer = null
var _camera: Camera2D = null
var _n: int = 0  ## Frames seen; the run ends at SCROLL_FROM + SCROLL_FRAMES.
var _detailed: bool = true
var _zoom: int = 2
var _shot: String = ""  ## shot=PATH saves the last frame as a PNG.
var _rebuild: Array[int] = []
var _scroll: Array[int] = []
var _last: int = 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("style="):
			_detailed = arg.get_slice("=", 1) == "detailed"
		elif arg.begins_with("zoom="):
			_zoom = int(arg.get_slice("=", 1))
		elif arg.begins_with("shot="):
			_shot = arg.get_slice("=", 1)
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
		_renderer.set_tower(_tower)
		_camera.zoom = Vector2(_zoom, _zoom)
		_camera.position = Vector2(1600, 3000)
		_camera.make_current()
		_last = now
		return false
	if _n > REBUILD_FROM and _n <= REBUILD_FROM + REBUILD_FRAMES:
		_renderer.refresh_palette()  # a static rebuild every frame
		_rebuild.append(now - _last)
	elif _n > SCROLL_FROM and _n <= SCROLL_FROM + SCROLL_FRAMES:
		_camera.position.x += 6.0
		_scroll.append(now - _last)
	_last = now
	if _n <= SCROLL_FROM + SCROLL_FRAMES:
		return false
	var tex := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0
	var video := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	print("style=%s zoom=%d" % ["detailed" if ViewSettings.detailed_graphics else "classic", _zoom])
	print("  render_texture_mem_mb=%.1f video_mem_mb=%.1f" % [tex, video])
	print("  static rebuild frame: %.2f ms avg   scroll frame: %.2f ms avg" % [_avg(_rebuild), _avg(_scroll)])
	if _shot != "" and root.get_texture().get_image().save_png(_shot) != OK:
		push_error("could not save " + _shot)
	if tex <= 0.0:
		push_error("texture memory reads 0: no renderer, so nothing was measured")
	return true


func _avg(a: Array[int]) -> float:
	var t := 0
	for v: int in a:
		t += v
	return t / 1000.0 / maxi(a.size(), 1)
