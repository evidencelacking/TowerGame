extends RefCounted
## The daily evaluation runs one step a tick across the first STEPS ticks of the 21:00 period (#452). The schedule is
## read from the clock alone, so it must fire each step once a day, and a save taken between steps must resume the
## sequence exactly.

const Clock := preload("res://scripts/sim/clock.gd")
const TowerSim := preload("res://scripts/sim/tower.gd")
const Mixed := preload("res://tools/bench_mixed.gd")
const EvaluationScript := preload("res://scripts/sim/evaluation.gd")

const WARMUP := 120
const EVAL_TICK := 2400  ## Clock ticks into the day at which the 21:00 period begins.


static func _day_ticks() -> int:
	var total := 0
	for i in Clock.PERIODS:
		total += Clock.period_ticks(i)
	return total


static func run(check: Callable) -> void:
	_check_schedule(check)
	_check_save_mid_sequence(check)


static func _check_schedule(check: Callable) -> void:
	var clock := Clock.new()
	var day := _day_ticks()
	var seen: Array[int] = []
	seen.resize(EvaluationScript.STEPS)
	seen.fill(0)
	var in_order := true
	var bad_ticks := 0
	for t in day:
		var k := EvaluationScript.step_due(clock)
		var expected := t - EVAL_TICK if t >= EVAL_TICK and t < EVAL_TICK + EvaluationScript.STEPS else -1
		if k != expected:
			bad_ticks += 1
		if k >= 0:
			seen[k] += 1
			if t != EVAL_TICK + k:
				in_order = false
		clock.advance()
	check.call(bad_ticks == 0, "step_due is k on tick k of the 21:00 period and -1 on every other tick of the day (%d wrong)" % bad_ticks)
	check.call(in_order and seen.count(1) == EvaluationScript.STEPS, "each evaluation step appears exactly once a day (%s)" % [seen])
	check.call(EvaluationScript.STEPS < Clock.period_ticks(5), "the steps fit inside the 21:00 period (%d < %d ticks)" % [EvaluationScript.STEPS, Clock.period_ticks(5)])


static func _moods(t: TowerSim) -> Array[int]:
	var out: Array[int] = []
	for i in t.people.count():
		out.append(t.people.mood_of(i))
	return out


static func _check_save_mid_sequence(check: Callable) -> void:
	var real := Mixed.build(42)
	for _i in WARMUP:
		real.step()
	check.call(real.people.count() > 0, "the fixture has people, so the sequence runs on something")
	real.clock.set_to_tick(EVAL_TICK - 2)
	var before := _moods(real)
	# Ticks 0 to 2 of the period run steps 0 to 2; stop with step 2 done and 3 to 5 still to come.
	for _i in 5:
		real.step()
	check.call(real.clock.ticks_in_period() == 3, "stopped just after step 2 (tick %d of the period)" % real.clock.ticks_in_period())
	var loaded := Mixed.build(42)
	check.call(loaded.load_state(real.save()), "the mid-sequence save loads")
	check.call(loaded.state_hash() == real.state_hash(), "the loaded tower matches at the save point")
	var drift := -1
	for i in Clock.period_ticks(5) + 400:  # past step 5, the rest of the night and into the next day
		real.step()
		loaded.step()
		if real.state_hash() != loaded.state_hash():
			drift = i
			break
	check.call(drift == -1, "a tower loaded between steps 2 and 3 matches the original through steps 3 to 5 and into the next day (drift at tick %d)" % drift)
	# Regression guard: skipping the steps would leave every mood as it was.
	check.call(_moods(real) != before, "the evening evaluation changed some mood, so a skipped step would show")
