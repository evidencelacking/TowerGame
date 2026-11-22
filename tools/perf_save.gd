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
## Args: save=<path> | mixed, [ticks=2550] [noview] [loop speed=1|2|3 frames=120 warmup=500]

const BenchMixed := preload("res://tools/bench_mixed.gd")
const CarsScript := preload("res://scripts/sim/cars.gd")
const RendererScript := preload("res://scripts/view/tower_renderer.gd")
const LayerScript := preload("res://scripts/view/thought_layer.gd")
const IconsScript := preload("res://scripts/view/thought_icons.gd")
const MoodScript := preload("res://scripts/sim/mood.gd")
const EvaluationScript := preload("res://scripts/sim/evaluation.gd")
const StarRulesScript := preload("res://scripts/sim/star_rules.gd")
const HelipadScript := preload("res://scripts/sim/helipad.gd")
const RunningCostsScript := preload("res://scripts/sim/running_costs.gd")
const MessagesScript := preload("res://scripts/sim/messages.gd")
const TripsScript := preload("res://scripts/sim/trips.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const ClockScript := preload("res://scripts/sim/clock.gd")

const MIXED_SEED := 42
const MIXED_WARMUP := 400  ## Ticks that let the mixed tower's tenants move in before it is measured.
const MIN_PEOPLE := 1200  ## A mixed tower with fewer people, or no cut-off room, exits 1.
const WARMUP_FRAMES := 2  ## Frames before the view is touched, so the renderer's _ready has run.
const MIN_FRAME_SECONDS := 1.0 / 60.0
const VIEW_STEPS := 30  ## Ticks the view part steps (one per sample).
const LAYOUT_SAMPLES := 5

var _path: String = ""
var _mixed: bool = false
var _loop: bool = false
var _view: bool = true
var _ticks: int = 2550
var _speed: int = 1
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
		elif arg == "loop":
			_loop = true
		elif arg == "noview":
			_view = false
		elif arg.begins_with("ticks="):
			_ticks = int(arg.get_slice("=", 1))
		elif arg.begins_with("speed="):
			_speed = clampi(int(arg.get_slice("=", 1)), 1, SimDriver.SPEEDS.size())
		elif arg.begins_with("frames="):
			_frames = int(arg.get_slice("=", 1))
		elif arg.begins_with("warmup="):
			_warmup = int(arg.get_slice("=", 1))
	if _path.is_empty() and not _mixed:
		print("FAIL: give save=<path> or mixed")
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
	if _view:
		_view_costs(_tower)
		for _i in VIEW_STEPS:  # _view_costs stepped the tower; keep the twin level
			_twin.step()
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
	var proc := 0
	var runs := 0
	var hud := 0
	var figures: Array[Dictionary] = []
	for _i in VIEW_STEPS:
		t.step()
		a = Time.get_ticks_usec()
		figures = r._people_view.figures(t)
		fig += Time.get_ticks_usec() - a
		a = Time.get_ticks_usec()
		IconsScript.pick(t, figures, true)
		pick += Time.get_ticks_usec() - a
		a = Time.get_ticks_usec()
		t.population_breakdown()
		hud += Time.get_ticks_usec() - a
		a = Time.get_ticks_usec()
		r._process(MIN_FRAME_SECONDS)
		proc += Time.get_ticks_usec() - a
	for _i in LAYOUT_SAMPLES:
		a = Time.get_ticks_usec()
		r._rebuild_runs()
		r._in_use = r._rooms_in_use()
		r._sync_pieces()
		runs += Time.get_ticks_usec() - a
	print("view per tick (%d ticks):" % VIEW_STEPS)
	print("  figures(): %d figures, %.2f ms" % [figures.size(), fig / 1000.0 / VIEW_STEPS])
	print("  ThoughtIcons.pick: %.2f ms" % [pick / 1000.0 / VIEW_STEPS])
	print("  renderer._process on a new tick (includes its own figures()): %.2f ms" % [proc / 1000.0 / VIEW_STEPS])
	print("  layout change (_rebuild_runs + _rooms_in_use + _sync_pieces): %.2f ms" % [runs / 1000.0 / LAYOUT_SAMPLES])
	print("  population_breakdown (HUD, every frame): %.3f ms" % [hud / 1000.0 / VIEW_STEPS])
	r.queue_free()


## Adds the time since the last mark to label's total and worst, then restarts the clock.
func _mark(label: String) -> void:
	var now := Time.get_ticks_usec()
	var d := now - _mark_at
	_us[label] = int(_us.get(label, 0)) + d
	_worst[label] = maxi(int(_worst.get(label, 0)), d)
	_mark_at = Time.get_ticks_usec()


## One copy of Tower.step() and _run_systems with a timer around each system. The fidelity check in
## _process fails if this drifts from the real loop, so update it whenever _run_systems changes.
func _sim_day(t: Tower, ticks: int) -> void:
	var totals: Array[int] = []
	for _k in ticks:
		var start := Time.get_ticks_usec()
		t.tick += 1
		_mark_at = Time.get_ticks_usec()
		t._apply_due_commands()
		_mark("commands")
		t.clock.advance()
		_mark("clock")
		t.refresh_reach()
		_mark("refresh_reach")
		t.tenancy.tick(t.clock, t.floors, t.rooms, t.grid, t.people, t.rng, t.ledger, t.tick)
		_mark("tenancy")
		t.commerce.tick(t.clock, t.floors, t.rooms, t.grid, t.people, t.tenancy, t.rng, t.ledger, t.messages, t.tick, t.life)
		_mark("commerce")
		t.vip.tick(t.clock, t.stars, t.people, t.grades, t.messages, t.tick)
		_mark("vip")
		t.hotel.tick(t.clock, t.floors, t.people, t.rng, t.ledger, t.messages, t.tick)
		_mark("hotel")
		t.pests.tick(t.hotel, t.grid, t.rng, t.messages, t.tick)
		_mark("pests")
		t.housekeeping.tick(t.clock, t.floors, t.grid)
		_mark("housekeeping")
		t.recycling.tick(t.clock, t.population())
		_mark("recycling")
		if t.clock.day_started:
			t.rent.collect(t.rooms, t.people, t.ledger, t.tick, t.clock.quarter_started, t.rent_bonus_percent())
			t.commerce.collect_rent(t.rooms, t.rent, t.ledger, t.tick, t.clock.quarter_started)
			HelipadScript.collect(t.rooms, t.ledger, t.tick)
			_mark("daily rent")
		if t.clock.quarter_started:
			var rent_income := t._quarter_rent()
			var running := RunningCostsScript.charge(t.rooms, t.floors, t.ledger, t.tick)
			if rent_income > 0 or running > 0:
				t.messages.add(t.tick, MessagesScript.QUARTER_SETTLED, rent_income, running)
			_mark("quarter")
		t.trips.tick(t.clock, t.floors, t.rooms, t.grid, t.people)
		_mark("trips")
		if t.trips.blocked_transfers > 0:
			if not t.messages.recent(MessagesScript.TRIP_UNREACHABLE, t.tick - TripsScript.WARN_EVERY_TICKS + 1):
				t.messages.add(t.tick, MessagesScript.TRIP_UNREACHABLE, t.trips.blocked_transfers)
			t.trips.blocked_transfers = 0
		t.grades.tick(t.people)
		_mark("grades")
		t.rooms.schedule_slot = RoomsScript.slot_for(t.clock.day_of_week() == ClockScript.WE, t.clock.period())
		CarsScript.tick(t.rooms)
		_mark("cars")
		t.trips.collect_arrivals(t.floors, t.rooms, t.grid, t.people)
		_mark("arrivals")
		t.people.tick(t.clock)
		_mark("people")
		t.threat.population = t.population()
		_mark("population")
		t.events.tick(t.clock, t.stars, t.tick)
		t.fire.tick(t.clock, t.events, t.grid, t.people, t.messages, t.tick)
		t.threat.tick(t.events, t.grid, t.messages, t.tick)
		_mark("events/fire/threat")
		if not t.fire.burning_rooms().is_empty():
			t.mood.note_event(MoodScript.FIRE_SHOCK, t.people)
		if t.threat.is_active():
			t.mood.note_event(MoodScript.THREAT_SHOCK, t.people)
		for id in t.fire.take_burned():
			t.char_room(id)
		for id in t.threat.take_destroyed():
			t.destroy_room(id)
		_mark("fire aftermath")
		if EvaluationScript.is_due(t.clock):  # Tower.evaluate_tenants, split to time each step
			t.mood.update(t.rooms, t.grid, t.floors, t.grades, t.people)
			_mark("eval: mood.update")
			t.evaluation.evaluate(t.rooms, t.people, t.grades, t.grid, t.floors, t.tenancy, t.ledger, t.messages, t.rng, t.tick)
			_mark("eval: evaluate")
			t.evaluation.evaluate_moods(t.rooms, t.people, t.grades, t.grid, t.ledger, t.messages, t.tick)
			_mark("eval: evaluate_moods")
			t.life.daily(t)
			_mark("eval: life.daily")
			t.commerce.evaluate(t.floors, t.rooms, t.grid, t.tenancy, t.rent, t.messages, t.tick)
			_mark("eval: commerce.evaluate")
		if StarRulesScript.is_check_tick(t.tick):
			t.promote_stars()
			_mark("promote_stars")
		totals.append(Time.get_ticks_usec() - start)
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
