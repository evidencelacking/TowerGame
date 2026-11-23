extends SceneTree
## View and sim timing harness (#399): a 60-floor tower, a dozen elevators and several hundred people.
## Reports the mean and p95 milliseconds of one sim tick, PeopleView.figures, ThoughtIcons.pick,
## SoundSystem._ambience, the renderer's _process, the thought layer's _process, and the engine gap
## between two frames (where the draw commands issued by _draw run). Headless has no GPU, so draw
## numbers are script-side cost only. Wall-clock timing lives here, in the harness: never in
## scripts/sim/. Not part of the test suite. Run: python tools/perf.py [samples=300 frames=400]
## The frame loop ends: _process returns true once _frames frames past the warm-up have run.

const TowerSim := preload("res://scripts/sim/tower.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const RendererScript := preload("res://scripts/view/tower_renderer.gd")
const LayerScript := preload("res://scripts/view/thought_layer.gd")
const IconsScript := preload("res://scripts/view/thought_icons.gd")
const SoundScript := preload("res://scripts/view/sound/sound_system.gd")

const TOP := 60  ## Floors built; shafts stop at 59 so the machine room fits on 60.
const SKY := 30  ## A local shaft spans 30 floors at most: six run 1 to 30, six more 30 to 59 off a sky lobby.
const SHAFTS_PER_GROUP := 6
const OFFICES := 100
const START_TICK := 580  ## About 8:48 on a weekday, just before the morning arrivals.
const WARMUP_FRAMES := 20
const MIN_PEOPLE := 300  ## Fewer than this and the run exits 1: a fast result must not come from an empty tower.

var _samples: int = 300
var _frames: int = 400
var _warmup: int = 700
var _tower: Tower = null
var _renderer: TowerRenderer = null
var _layer: ThoughtLayer = null
var _n: int = 0
var _carry: float = 0.0
var _gap_us: Array[int] = []
var _proc_us: Array[int] = []
var _layer_us: Array[int] = []
var _frame_end: int = 0
var _probe: Probe = null
var _layer_costs: Dictionary = {}  ## DYNAMIC_LAYERS name -> microseconds, summed over the probe's draws


## A canvas item that draws the renderer's dynamic layer on request, timing each layer: the draw
## commands of _paint_dynamic, which the renderer issues to a SubViewport (not drawn headless).
class Probe extends Node2D:
	var renderer: TowerRenderer = null
	var costs: Array[int] = []
	var by_layer: Dictionary = {}

	func _draw() -> void:
		var t0 := Time.get_ticks_usec()
		for layer: String in TowerRenderer.DYNAMIC_LAYERS:
			var l0 := Time.get_ticks_usec()
			renderer.call(layer, self)
			by_layer[layer] = int(by_layer.get(layer, 0)) + Time.get_ticks_usec() - l0
		costs.append(Time.get_ticks_usec() - t0)


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("samples="):
			_samples = int(arg.get_slice("=", 1))
		elif arg.begins_with("frames="):
			_frames = int(arg.get_slice("=", 1))
		elif arg.begins_with("warmup="):
			_warmup = int(arg.get_slice("=", 1))
	_tower = _build()
	print("built: %d floors, %d shafts, %d cars" % [TOP, _tower.rooms.shaft_count(), _tower.rooms.total_cars()])
	for _i in _warmup:
		_tower.step()
	print("people after warm-up: %d" % _tower.people.count())
	if _tower.people.count() < MIN_PEOPLE:
		print("FAIL: the tower came up short of %d people" % MIN_PEOPLE)
		quit(1)
		return
	_renderer = RendererScript.new()
	root.add_child(_renderer)
	_renderer.set_tower(_tower)
	_layer = LayerScript.new()
	root.add_child(_layer)
	_layer.bind(_tower, _renderer)
	_renderer.set_process(false)  # driven by hand below so its script cost is timed alone
	_layer.set_process(false)
	_renderer._process(0.016)
	_probe = Probe.new()
	_probe.renderer = _renderer
	root.add_child(_probe)
	_static_costs()
	_frame_end = Time.get_ticks_usec()


func _build() -> TowerSim:
	var t := TowerSim.new(42, 2000000000)
	t.stars = 5
	t.floors.build_lobby(t.ledger, 0, 1, 0, 399, 2)
	for f in range(3, TOP + 1):
		t.floors.fill_span(f, 0, 399)
	var shaft_kind := CatalogueScript.IDS.find("local_shaft")
	t.floors.build_lobby(t.ledger, 0, SKY, 0, 399, 1)
	for i in SHAFTS_PER_GROUP:
		var x := 15 + 64 * i
		t.rooms.place_shaft(t.grid, t.floors, t.ledger, 0, shaft_kind, 1, SKY, x)
		t.rooms.place_shaft(t.grid, t.floors, t.ledger, 0, shaft_kind, SKY, TOP - 1, x + 32)
	for id in t.rooms.shaft_ids():
		t.rooms.add_car(t.ledger, 0, 5, id, 1)
	var office := CatalogueScript.IDS.find("office")
	var width: int = CatalogueScript.field("office", "width")
	var per_floor := ceili(float(OFFICES) / (TOP - 2))
	var placed := 0
	for f in range(3, TOP + 1):
		var x := 0
		var here := 0
		while x + width <= 400 and placed < OFFICES and here < per_floor:
			if t.rooms.place_room(t.grid, t.floors, t.ledger, 0, office, f, x) == 0:
				placed += 1
				here += 1
				x += width
			else:
				x += 1
	t.clock.set_to_tick(START_TICK)
	return t


func _static_costs() -> void:
	var step_us: Array[int] = []
	var fig_us: Array[int] = []
	var pick_us: Array[int] = []
	var figures: Array[Dictionary] = []
	for _i in _samples:
		var t0 := Time.get_ticks_usec()
		_tower.step()
		step_us.append(Time.get_ticks_usec() - t0)
		t0 = Time.get_ticks_usec()
		figures = _renderer._people_view.figures(_tower)
		fig_us.append(Time.get_ticks_usec() - t0)
		t0 = Time.get_ticks_usec()
		IconsScript.pick(_tower, figures, true)
		pick_us.append(Time.get_ticks_usec() - t0)
	var cam := Camera2D.new()
	root.add_child(cam)
	var driver := SimDriver.new()
	driver.tower = _tower
	var sound: Node = SoundScript.new()
	root.add_child(sound)
	sound.bind(driver, cam, {}, false)
	var amb_us: Array[int] = []
	for _i in 100:
		var t0 := Time.get_ticks_usec()
		sound._ambience(_tower)
		amb_us.append(Time.get_ticks_usec() - t0)
	print("people %d, figures %d" % [_tower.people.count(), figures.size()])
	_line("sim tick", step_us)
	_line("people_view.figures", fig_us)
	_line("ThoughtIcons.pick", pick_us)
	_line("SoundSystem._ambience", amb_us)


func _process(_delta: float) -> bool:
	# One frame at speed 1: 15 ticks a second over 60 frames a second is a quarter tick a frame.
	var now := Time.get_ticks_usec()
	var gap := now - _frame_end  # engine time since our last frame ended: the draw commands run here
	_carry += 0.25
	while _carry >= 1.0:
		_tower.step()
		_carry -= 1.0
	var t0 := Time.get_ticks_usec()
	_renderer._process(0.016)
	var t1 := Time.get_ticks_usec()
	_layer._process(0.016)
	var t2 := Time.get_ticks_usec()
	_probe.queue_redraw()  # drawn by the engine before the next frame's _process
	if _n >= WARMUP_FRAMES:
		_gap_us.append(gap)
		_proc_us.append(t1 - t0)
		_layer_us.append(t2 - t1)
	_n += 1
	_frame_end = Time.get_ticks_usec()
	if _n >= _frames + WARMUP_FRAMES:
		_line("renderer._process (per frame)", _proc_us)
		_line("thought_layer._process (per frame)", _layer_us)
		_line("dynamic layer draw (_paint_dynamic)", _probe.costs.slice(WARMUP_FRAMES))
		for layer: String in _probe.by_layer:
			print("    %-14s mean %8.3f ms" % [layer, _probe.by_layer[layer] / 1000.0 / _probe.costs.size()])
		_line("engine gap between frames (draw cmds)", _gap_us)
		return true
	return false


func _line(label: String, us: Array[int]) -> void:
	var sorted := us.duplicate()
	sorted.sort()
	var total := 0
	for v in us:
		total += v
	var n := us.size()
	print("%-42s mean %8.3f ms   p95 %8.3f ms   (n=%d)" % [label, total / 1000.0 / n, sorted[n * 95 / 100] / 1000.0, n])
