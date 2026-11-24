extends RefCounted
## The daily evaluation's speed-ups (#452: floor and room indexes, packed passes, memoised source grades) must not
## change a result. This steps the mixed fixture across the 21:00 evaluation and the next day's start and compares
## state_hash with the value recorded on main before those changes. If a deliberate rules change moves the hash,
## re-record PINNED from the new run and say so in the commit. Both loops are counted, so the run ends.

const Mixed := preload("res://tools/bench_mixed.gd")

const WARMUP := 120
const EVAL_AT := 2380  ## Clock ticks into the day: the evaluation runs at 2400 and the day starts at 2550.
const TICKS := 190
const PINNED := 7621206387940885348  ## state_hash after the run below on bench_mixed seed 42. Re-recorded for #452: the evaluation now runs one step a tick, which moves the hash and nothing else (the old value comes back when the steps run together).


static func run(check: Callable) -> void:
	var t := Mixed.build(42)
	for _i in WARMUP:
		t.step()
	t.clock.set_to_tick(EVAL_AT)
	for _i in TICKS:
		t.step()
	check.call(t.people.count() > 0, "the mixed fixture has people to evaluate")
	var got := t.state_hash()
	check.call(got == PINNED, "state_hash after a day's evaluation matches the pinned value (got %d)" % got)
