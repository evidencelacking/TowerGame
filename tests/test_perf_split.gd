extends RefCounted
## tools/sim_split.gd is the perf harness's timed copy of Tower.step(). It must not drift from tower.gd, or the
## per-system numbers describe a different loop (#447). Builds the mixed fixture twice, then steps one through the split copy and the other through Tower.step() across the evening
## evaluation and the next day's start, and compares state_hash every few ticks.

const Mixed := preload("res://tools/bench_mixed.gd")
const Split := preload("res://tools/sim_split.gd")

const WARMUP := 120
const EVAL_AT := 2380  ## Clock ticks into the day: the daily evaluation runs at 2400 and the day starts at 2550.
const TICKS := 190
const EVERY := 10
const INLINED := ["evaluate_tenants", "evaluate_step", "is_empty"]  ## Split into timed steps by the copy, or a chained call on a value.


static func run(check: Callable) -> void:
	var real := Mixed.build(42)
	var copy := Mixed.build(42)  # not a save and load: a loaded twin keeps no derived state, and drifts for that reason alone
	for _i in WARMUP:
		real.step()
		Split.step(copy, func(_label: String) -> void: pass)
	check.call(real.state_hash() == copy.state_hash(), "the split copy matches Tower.step through a warm-up")
	real.clock.set_to_tick(EVAL_AT)
	copy.clock.set_to_tick(EVAL_AT)
	var mark := func(_label: String) -> void: pass
	var drift := -1
	for i in TICKS:
		real.step()
		Split.step(copy, mark)
		if i % EVERY == EVERY - 1 and real.state_hash() != copy.state_hash():
			drift = i
			break
	check.call(drift == -1, "the perf split copy of Tower.step matches the real one for %d ticks across the evaluation and a day start (drift by tick %d)" % [TICKS, drift])
	check.call(real.people.count() > 0, "the fixture has people, so the copy is tested on something")
	_check_calls_match(check)


## A system that never fires on the mixed fixture (weather, pipe, stall, festival) drifts without changing the hash,
## so every call in Tower._run_systems must also appear in the split copy (with its `t.` prefix).
static func _check_calls_match(check: Callable) -> void:
	var tower_src := FileAccess.get_file_as_string("res://scripts/sim/tower.gd")
	var split_src := FileAccess.get_file_as_string("res://tools/sim_split.gd")
	var body := tower_src.get_slice("func _run_systems() -> void:", 1).get_slice("\nfunc ", 0)
	var pattern := RegEx.create_from_string("([A-Za-z_][A-Za-z_0-9.]*)[(]")
	var missing: Array[String] = []
	for line in body.split("\n"):
		var code := line.get_slice("#", 0).strip_edges()
		for m in pattern.search_all(code):
			var fn := m.get_string(1)
			if fn in ["if", "for", "not", "and", "or"] or fn in INLINED or fn.ends_with(".is_empty") or fn.ends_with(".call"):
				continue
			var head := fn.get_slice(".", 0)
			var wanted := fn if head.ends_with("Script") else "t." + fn
			if not split_src.contains(wanted + "(") and not missing.has(wanted):
				missing.append(wanted)
	check.call(missing.is_empty(), "every call in Tower._run_systems appears in tools/sim_split.gd (missing: %s)" % [missing])
