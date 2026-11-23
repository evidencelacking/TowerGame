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
