extends SceneTree
## Save and fixture profiler (#419), run by `python tools/perf.py save=<path>`, `... mixed` or `... loop`.
## The synthetic towers of perf.gd missed the worst hotspots, which sit in real saves (hotels, condos, shops,
## cut-off rooms), so this loads a save (or builds the mixed fixture, tools/bench_mixed.gd) and reports:
##   - load time, tower size, and the cost of save(), var_to_bytes and state_hash;
##   - the view per tick: figures, ThoughtIcons.pick, renderer._process, a layout change and the HUD's
##     population_breakdown;
##   - one sim day through a copy of Tower._run_systems with a timer around each system;
##   - a fidelity check: a twin is stepped with Tower.step() for the same ticks and the state hashes must
##     match, or the per-system numbers describe a different loop (MISMATCH, exit 1);
##   - in loop mode, the real frame loop: SimDriver.run_frame plus the renderer and thought layer, each
##     frame's measured time feeding the next delta, to show catch-up spirals.
## Wall-clock timing lives in tools/ only, never in scripts/sim/. Not part of the test suite.
## Startup order: _initialize loads the tower (and the twin); the view and the timed runs start in _process
## from frame 2, once the tree is live. Every loop is over a fixed count, so the run ends.
## Args: save=<path> | mixed, [ticks=2550] [noview] [loop speed=1|2|3 frames=120 warmup=500 overlay=disruptions|synergies|income|mood|traffic|rent|grade|hotel]

const BenchMixed := preload("res://tools/bench_mixed.gd")
const BenchBig := preload("res://tools/bench_big.gd")
const SimSplit := preload("res://tools/sim_split.gd")
const RendererScript := preload("res://scripts/view/tower_renderer.gd")
const LayerScript := preload("res://scripts/view/thought_layer.gd")
const IconsScript := preload("res://scripts/view/thought_icons.gd")
const HeatLook := preload("res://scripts/view/heat_look.gd")
const DisruptionLook := preload("res://scripts/view/disruption_look.gd")
const SynergyLook := preload("res://scripts/view/synergy_look.gd")

const RUSH_MS := 10  ## Ticks costing more than this many ms make up the rush-hour view.
const MIXED_SEED := 42
const BIG_SEED := 42
const BIG_WARMUP := 400
const NIGHT_HOURS := 4  ## _print_night covers the clock hours before this.
const MIN_BIG_PEOPLE := 5000  ## The big tower is reported short of this, but still profiled.
const MIXED_WARMUP := 400  ## Ticks that let the mixed tower's tenants move in before it is measured.
const MIN_PEOPLE := 1200  ## A mixed tower with fewer people, or no cut-off room, exits 1.
const WARMUP_FRAMES := 2  ## Frames before the view is touched, so the renderer's _ready has run.
const MIN_FRAME_SECONDS := 1.0 / 60.0
const VIEW_STEPS := 30  ## Ticks the view part steps (one per sample).
const LAYOUT_SAMPLES := 5

var _path: String = ""
var _mixed: bool = false
var _big: bool = false
var _tick_us: Dictionary = {}  ## system label -> microseconds in the tick being timed
var _loop: bool = false
var _view: bool = true
var _ticks: int = 2550
var _speed: int = 1
var _overlay: String = ""  ## overlay=<name> (loop mode): a view overlay held on, to time its cost against the same run with it off.
var _overlay_tick: int = -1000000  ## Tick the overlay was last painted at (it repaints every 30 ticks, 10 for traffic, 120 for the slow ones).
var _canvas := NullCanvas.new()
var _disruption_cache: Dictionary = {}
var _frames: int = 120
var _warmup: int = 500
var _tower: Tower = null  ## Stays null when loading failed or the fixture came up short: _process then quits.
var _twin: Tower = null  ## Stepped with Tower.step() alongside the timed copy, for the fidelity check.
var _frame: int = 0
var _us: Dictionary = {}  ## system label -> total microseconds
var _worst: Dictionary = {}  ## system label -> worst single-tick microseconds
var _mark_at: int = 0
var _exit_code: int = 0
# Loop mode
var _driver: SimDriver = null
var _renderer: TowerRenderer = null
var _layer: ThoughtLayer = null
var _delta: float = MIN_FRAME_SECONDS
var _line: String = ""
var _loop_ticks: int = 0
var _loop_us: int = 0
var _view_us: int = 0
var _capped: int = 0
var _cap: int = 0
var _loop_n: int = 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("save="):
			_path = arg.get_slice("=", 1)
		elif arg == "mixed":
			_mixed = true
		elif arg == "big":
			_big = true
		elif arg == "loop":
			_loop = true
		elif arg == "noview":
			_view = false
		elif arg.begins_with("ticks="):
			_ticks = int(arg.get_slice("=", 1))
		elif arg.begins_with("overlay="):
			_overlay = arg.get_slice("=", 1)
		elif arg.begins_with("speed="):
			_speed = clampi(int(arg.get_slice("=", 1)), 1, SimDriver.SPEEDS.size())
		elif arg.begins_with("frames="):
			_frames = int(arg.get_slice("=", 1))
		elif arg.begins_with("warmup="):
			_warmup = int(arg.get_slice("=", 1))
	if _path.is_empty() and not _mixed and not _big:
		print("FAIL: give save=<path>, mixed or big")
		_exit_code = 2
		return
	var t0 := Time.get_ticks_usec()
	var made := _make(true)
	if made == null:
		print("FAIL: could not load %s" % _path)
		_exit_code = 1
		return
	if _mixed:
		print("mixed tower built and warmed %d ticks in %.1f s" % [MIXED_WARMUP, (Time.get_ticks_usec() - t0) / 1e6])
		if not _check_mixed(made):
			_exit_code = 1
			return
	if _big:
		print("big tower built and warmed %d ticks in %.1f s" % [BIG_WARMUP, (Time.get_ticks_usec() - t0) / 1e6])
		var rooms_n := made.rooms.room_ids().size()
		print("big: %d people, %d rooms, %d cut-off rooms, %d shafts, %d cars%s" % [made.people.count(), rooms_n, made.rooms.cut_off.size(), made.rooms.shaft_count(), made.rooms.total_cars(), "" if made.people.count() >= MIN_BIG_PEOPLE else " (SHORT of %d people)" % MIN_BIG_PEOPLE])
	_print_size(made)
	if not _loop:
		_print_save_costs(made)
		_twin = _make(false)
		if _twin == null:
			print("FAIL: could not load the twin")
			_exit_code = 1
			return
	_tower = made
	if _loop:
		_start_loop()


## A fresh copy of the tower under test: the loaded save, or the built and warmed mixed tower.
func _make(report: bool) -> Tower:
	if _mixed:
		var built := BenchMixed.build(MIXED_SEED)
		for _i in MIXED_WARMUP:
			built.step()
		return built
	if _big:
		var built := BenchBig.build(BIG_SEED)
		for _i in BIG_WARMUP:
			built.step()
		return built
	var t0 := Time.get_ticks_usec()
	var data := SaveFiles.read(_path)
	var t1 := Time.get_ticks_usec()
	var t := Tower.new()
	var ok := t.load_state(data)
	var t2 := Time.get_ticks_usec()
	if report:
		print("load ok=%s: read %.1f ms, load_state %.1f ms" % [ok, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0])
	return t if ok else null


## Fails (false) when the mixed tower is too small or has no cut-off room to be a fair test.
func _check_mixed(t: Tower) -> bool:
	var people := t.people.count()
	var cut := t.rooms.cut_off.size()
	print("mixed: %d people, %d cut-off rooms" % [people, cut])
	if people < MIN_PEOPLE or cut == 0:
		print("FAIL: the mixed tower needs at least %d people and one cut-off room" % MIN_PEOPLE)
		return false
	return true


func _print_size(t: Tower) -> void:
	print("tick %d stars %d people %d population %d rooms %d shafts %d cars %d cut-off %d" % [t.tick, t.stars, t.people.count(), t.population(), t.rooms.room_ids().size(), t.rooms.shaft_count(), t.rooms.total_cars(), t.rooms.cut_off.size()])


func _print_save_costs(t: Tower) -> void:
	var t0 := Time.get_ticks_usec()
	var saved := t.save()
	var t1 := Time.get_ticks_usec()
	var bytes := var_to_bytes(saved)
	var t2 := Time.get_ticks_usec()
	t.state_hash()
	var t3 := Time.get_ticks_usec()
	print("save(): %.1f ms, var_to_bytes %.1f ms (%d bytes), state_hash %.1f ms" % [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, bytes.size(), (t3 - t2) / 1000.0])


func _process(_delta_unused: float) -> bool:
	if _tower == null:  # setup failed or the fixture came up short
		quit(_exit_code)
		return true
	_frame += 1
	if _frame < WARMUP_FRAMES:  # the tree is live from frame 2: the renderer's _ready has run by then
		return false
	if _loop:
		return _loop_frame()
	if _view:  # on a third copy: the view part steps the tower and bulldozes and rebuilds rooms, which would break the twin check
		_view_costs(_make(false))
	_sim_day(_tower, _ticks)
	for _i in _ticks:
		_twin.step()
	var a := _tower.state_hash()
	var b := _twin.state_hash()
	var match_ok := a == b
	print("fidelity: %s (hash %d vs %d)" % ["MATCH" if match_ok else "MISMATCH", a, b])
	quit(0 if match_ok else 1)
	return true


## The view's per-tick costs on a live renderer: each sample steps the tower one tick first.
func _view_costs(t: Tower) -> void:
	var r: TowerRenderer = RendererScript.new()
	root.add_child(r)
	var a := Time.get_ticks_usec()
	r.set_tower(t)
	r._process(MIN_FRAME_SECONDS)
	print("renderer first _process (full layout build): %.1f ms" % [(Time.get_ticks_usec() - a) / 1000.0])
	var fig := 0
	var pick := 0
	var pick_memo := 0
	var memo: Dictionary = {}
	var proc := 0
	var runs := 0
	var part_runs := 0
	var part_use := 0
	var part_sync := 0
	var hud := 0
	var figures: Array[Dictionary] = []
	for _i in VIEW_STEPS:
		t.step()
		a = Time.get_ticks_usec()
		figures = r._people_view.figures(t, r._people_area())
		fig += Time.get_ticks_usec() - a
		a = Time.get_ticks_usec()
		IconsScript.pick(t, figures, true)
		pick += Time.get_ticks_usec() - a
		a = Time.get_ticks_usec()
		IconsScript.pick(t, figures, true, memo, LayerScript.MEMO_TICKS)  # as the thought layer calls it
		pick_memo += Time.get_ticks_usec() - a
		a = Time.get_ticks_usec()
		t.population_breakdown()
		hud += Time.get_ticks_usec() - a
		a = Time.get_ticks_usec()
		r._process(MIN_FRAME_SECONDS)
		proc += Time.get_ticks_usec() - a
	for _i in LAYOUT_SAMPLES:
		a = Time.get_ticks_usec()
		r._rebuild_runs()
		var b := Time.get_ticks_usec()
		r._in_use = r._rooms_in_use()
		var c := Time.get_ticks_usec()
		r._sync_pieces()
		var d := Time.get_ticks_usec()
		part_runs += b - a
		part_use += c - b
		part_sync += d - c
		runs += d - a
	_real_layout_changes(t, r)
	print("view per tick (%d ticks):" % VIEW_STEPS)
	print("  figures(): %d figures, %.2f ms" % [figures.size(), fig / 1000.0 / VIEW_STEPS])
	print("  ThoughtIcons.pick: %.2f ms (every person looked up), %.2f ms as the thought layer calls it (memo)" % [pick / 1000.0 / VIEW_STEPS, pick_memo / 1000.0 / VIEW_STEPS])
	print("  renderer._process on a new tick (includes its own figures()): %.2f ms" % [proc / 1000.0 / VIEW_STEPS])
	print("  layout change (_rebuild_runs + _rooms_in_use + _sync_pieces): %.2f ms" % [runs / 1000.0 / LAYOUT_SAMPLES])
	print("    of which _rebuild_runs %.2f, _rooms_in_use %.2f, _sync_pieces %.2f ms" % [part_runs / 1000.0 / LAYOUT_SAMPLES, part_use / 1000.0 / LAYOUT_SAMPLES, part_sync / 1000.0 / LAYOUT_SAMPLES])
	print("  population_breakdown (HUD, every frame): %.3f ms" % [hud / 1000.0 / VIEW_STEPS])
	r.queue_free()


## A real bulldoze and rebuild of one room, each timed as the renderer's whole _process frame (#349).
func _real_layout_changes(t: Tower, r: TowerRenderer) -> void:
	t.ledger.balance = maxi(t.ledger.balance, 100000000)
	var picked: Array = []
	for run: Array in r._room_runs:
		var kind_index: int = Tower.CatalogueScript.IDS.find(t.rooms.kind_of(run[1]))
		var at: Array[int] = t.grid.run_of(run[0])
		if kind_index >= 0 and t.rooms.kind_of(run[1]) == "office":
			picked = [kind_index, at[0], at[1]]
			if at[0] > 3:
				break
	if picked.is_empty():
		print("  real layout change: no room to bulldoze")
		return
	var worst_dozer := 0.0
	var worst_build := 0.0
	var dozer_total := 0.0
	var build_total := 0.0
	const ROUNDS := 5
	for _i in ROUNDS:
		var a := Time.get_ticks_usec()
		t.rooms.bulldoze(t.grid, t.floors, t.ledger, t.tick, picked[1], picked[2])
		r._process(MIN_FRAME_SECONDS)
		var b := Time.get_ticks_usec()
		t.rooms.place_room(t.grid, t.floors, t.ledger, t.tick, picked[0], picked[1], picked[2])
		r._process(MIN_FRAME_SECONDS)
		var c := Time.get_ticks_usec()
		dozer_total += (b - a) / 1000.0
		build_total += (c - b) / 1000.0
		worst_dozer = maxf(worst_dozer, (b - a) / 1000.0)
		worst_build = maxf(worst_build, (c - b) / 1000.0)
	print("  real layout change, whole _process: bulldoze %.2f ms (worst %.2f), build %.2f ms (worst %.2f)" % [dozer_total / ROUNDS, worst_dozer, build_total / ROUNDS, worst_build])


## Adds the time since the last mark to label's total, worst and this tick's figure, then restarts the clock.
## The label "" only restarts the clock (SimSplit.step calls it first).
func _mark(label: String) -> void:
	var now := Time.get_ticks_usec()
	if not label.is_empty():
		var d := now - _mark_at
		_us[label] = int(_us.get(label, 0)) + d
		_worst[label] = maxi(int(_worst.get(label, 0)), d)
		_tick_us[label] = int(_tick_us.get(label, 0)) + d
	_mark_at = Time.get_ticks_usec()


## One tick through SimSplit (a timed copy of Tower.step()). The fidelity check in _process fails if it
## drifts from the real loop; tests/test_perf_split.gd guards it too.
func _sim_day(t: Tower, ticks: int) -> void:
	var totals: Array[int] = []
	var mark := Callable(self, "_mark")
	var rush_us: Dictionary = {}  # label -> microseconds summed over the ticks costing over RUSH_MS
	var rush_n := 0
	var night_us: Dictionary = {}  # label -> microseconds summed over the ticks from 00:00 to 03:59 (#453)
	var night_n := 0
	var hour_us: Array[int] = []
	var hour_n: Array[int] = []
	var hour_max: Array[int] = []
	for _h in 24:
		hour_us.append(0)
		hour_n.append(0)
		hour_max.append(0)
	for _k in ticks:
		var start := Time.get_ticks_usec()
		_tick_us = {}
		SimSplit.step(t, mark)
		var total := Time.get_ticks_usec() - start
		totals.append(total)
		var hour := t.clock.hour()
		hour_us[hour] += total
		hour_n[hour] += 1
		hour_max[hour] = maxi(hour_max[hour], total)
		if hour < NIGHT_HOURS:
			night_n += 1
			for k: String in _tick_us:
				night_us[k] = int(night_us.get(k, 0)) + int(_tick_us[k])
		if total > RUSH_MS * 1000:
			rush_n += 1
			for k: String in _tick_us:
				rush_us[k] = int(rush_us.get(k, 0)) + int(_tick_us[k])
	var sum := 0
	for v in totals:
		sum += v
	var sorted := totals.duplicate()
	sorted.sort()
	print("SIM %d ticks to tick %d: mean %.2f ms p50 %.2f p95 %.2f p99 %.2f max %.1f ms; people now %d queued %d" % [ticks, t.tick, sum / 1000.0 / ticks, sorted[ticks / 2] / 1000.0, sorted[ticks * 95 / 100] / 1000.0, sorted[ticks * 99 / 100] / 1000.0, sorted[ticks - 1] / 1000.0, t.people.count(), t.rooms.queued_ids().size()])
	var keys := _us.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return _us[a] > _us[b])
	for k: String in keys:
		print("  %-26s total %9.1f ms  per tick %7.3f ms  worst %8.1f ms" % [k, _us[k] / 1000.0, _us[k] / 1000.0 / ticks, _worst[k] / 1000.0])
	_print_rush(rush_us, rush_n, ticks)
	_print_night(night_us, night_n)
	_print_hours(hour_us, hour_n, hour_max)


## The per-system mean ms per tick over the ticks that cost more than RUSH_MS: what the rush hours spend.
func _print_rush(rush_us: Dictionary, rush_n: int, ticks: int) -> void:
	print("RUSH ticks over %d ms: %d of %d (%.1f%%)" % [RUSH_MS, rush_n, ticks, 100.0 * rush_n / maxi(ticks, 1)])
	if rush_n == 0:
		return
	var keys := rush_us.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return rush_us[a] > rush_us[b])
	for k: String in keys:
		print("  %-26s mean %7.3f ms per rush tick  worst %8.1f ms" % [k, rush_us[k] / 1000.0 / rush_n, _worst[k] / 1000.0])


## The per-system mean ms per tick from 00:00 to 03:59, when almost nothing moves (#453).
func _print_night(night_us: Dictionary, night_n: int) -> void:
	print("NIGHT 00:00-%02d:00 ticks: %d" % [NIGHT_HOURS, night_n])
	var keys := night_us.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return night_us[a] > night_us[b])
	for k: String in keys:
		print("  %-26s mean %7.3f ms per night tick" % [k, night_us[k] / 1000.0 / maxi(night_n, 1)])


## Total ms per tick by sim hour (the clock's hour, 0 to 23) over the timed ticks.
func _print_hours(hour_us: Array[int], hour_n: Array[int], hour_max: Array[int]) -> void:
	print("BY SIM HOUR (total ms per tick)")
	for h in 24:
		if hour_n[h] == 0:
			print("  %02d:00  no ticks" % h)
		else:
			print("  %02d:00  mean %7.2f ms  max %7.1f ms  (%d ticks)" % [h, hour_us[h] / 1000.0 / hour_n[h], hour_max[h] / 1000.0, hour_n[h]])


## Builds the driver, renderer and thought layer for loop mode, and runs the untimed warm-up.
func _start_loop() -> void:
	_driver = SimDriver.new()
	_driver.tower = _tower
	_driver.set_speed(_speed - 1)
	if "max_ticks_per_frame" in _driver:  # a var once the cap is tunable, a const today
		_cap = int(_driver.get("max_ticks_per_frame"))
	else:
		_cap = int(_driver.get_script().get_script_constant_map().get("MAX_TICKS_PER_FRAME", 0))
	for _i in _warmup:
		_tower.step()
	_renderer = RendererScript.new()
	root.add_child(_renderer)
	_renderer.set_tower(_tower)
	_renderer.set_process(false)  # driven by hand so the frame time is measured here
	_layer = LayerScript.new()
	root.add_child(_layer)
	_layer.bind(_tower, _renderer)
	_layer.set_process(false)
	_set_overlay()


## A canvas that takes the overlays' draw calls and drops them: the headless run has no draw phase, so this times the
## overlay's own work (reading the sim, building the colours and calling draw) without the engine's rasterising.
class NullCanvas:
	extends RefCounted

	func draw_rect(_r: Variant, _c: Color, _filled: bool = true, _w: float = -1.0) -> void:
		pass

	func draw_line(_a: Vector2, _b: Vector2, _c: Color, _w: float = -1.0) -> void:
		pass

	func draw_string(_f: Font, _p: Vector2, _t: String, _a: int = 0, _w: float = -1.0, _s: int = 16, _c: Color = Color.WHITE) -> void:
		pass

	func draw_string_outline(_f: Font, _p: Vector2, _t: String, _a: int = 0, _w: float = -1.0, _s: int = 16, _o: int = 1, _c: Color = Color.WHITE) -> void:
		pass


## Switches the named overlay on (the options are statics, so this is the whole of "toggling" it).
func _set_overlay() -> void:
	SynergyLook.on = _overlay == "synergies"
	DisruptionLook.on = _overlay == "disruptions"
	var names: Array[String] = []
	for n: String in HeatLook.NAMES:
		names.append(n.to_lower())
	HeatLook.mode = maxi(names.find(_overlay), HeatLook.OFF)
	if _overlay != "" and not SynergyLook.on and not DisruptionLook.on and HeatLook.mode == HeatLook.OFF:
		print("FAIL: unknown overlay %s" % _overlay)
		_exit_code = 2


## The overlay's share of a frame: a repaint when its refresh interval has passed, as the overlay nodes do.
func _overlay_frame() -> void:
	if _overlay == "":
		return
	var every := 30  # the overlay nodes' own intervals: see their REFRESH_TICKS
	if HeatLook.mode == HeatLook.TRAFFIC:
		every = 10
	elif DisruptionLook.on or HeatLook.mode in [HeatLook.RENT, HeatLook.GRADE, HeatLook.HOTEL]:
		every = 120
	if _tower.tick - _overlay_tick < every:
		return
	_overlay_tick = _tower.tick
	if SynergyLook.on:
		SynergyLook.draw(_canvas, _tower, -1)
	elif DisruptionLook.on:
		_disruption_cache.clear()
		DisruptionLook.draw(_canvas, _tower, -1, _disruption_cache)
	else:
		HeatLook.draw(_canvas, _tower, HeatLook.mode)


## One frame of the real loop; true when the run is over. The measured frame time is the next delta.
func _loop_frame() -> bool:
	if _loop_n == 0:
		_renderer._process(MIN_FRAME_SECONDS)  # the first full layout build, untimed
	_loop_n += 1
	var a := Time.get_ticks_usec()
	var ran := _driver.run_frame(_delta)
	var b := Time.get_ticks_usec()
	_renderer._process(_delta)
	_layer._process(_delta)
	_overlay_frame()
	var end := Time.get_ticks_usec()
	var us := end - a
	_view_us += end - b
	_delta = maxf(us / 1000000.0, MIN_FRAME_SECONDS)
	_loop_ticks += ran
	_loop_us += maxi(us, int(MIN_FRAME_SECONDS * 1000000.0))
	if _cap > 0 and ran >= _cap:
		_capped += 1
	_line += "%d:%.0f " % [ran, us / 1000.0]
	if _loop_n < _frames:
		return false
	print("speed %d, ticks:ms per frame: %s" % [_speed, _line])
	var target := SimDriver.BASE_TICKS_PER_SECOND * SimDriver.SPEEDS[_speed - 1]
	print("LOOP speed %d: delivered %.1f ticks/s against %.0f; mean frame %.1f ms (view %.1f ms, %.0f%%); %d of %d frames hit the cap of %d ticks" % [_speed, _loop_ticks * 1000000.0 / _loop_us, target, _loop_us / 1000.0 / _frames, _view_us / 1000.0 / _frames, 100.0 * _view_us / maxi(_loop_us, 1), _capped, _frames, _cap])
	quit(0)
	return true
