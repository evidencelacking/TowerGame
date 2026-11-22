extends RefCounted
## Fixed-tick driver tests: pause, speed, and the catch-up cap.

const Driver := preload("res://scripts/view/sim_driver.gd")


static func run(check: Callable) -> void:
	var d := Driver.new()
	check.call(d.run_frame(1.0 / 30.0) == 1 and d.tower.tick == 1, "driver: 1x runs 1 tick per 1/30 s")
	d.set_speed(2)
	check.call(d.run_frame(1.0 / 30.0) == 3, "driver: 3x runs 3 ticks per 1/30 s")
	d.set_paused(true)
	var before: int = d.tower.tick
	check.call(d.run_frame(10.0) == 0 and d.tower.tick == before, "driver: paused runs no ticks")
	d.set_paused(false)
	d.budget_usec = -1  # no clock in the tests
	check.call(d.run_frame(10.0) == Driver.MAX_TICKS_PER_FRAME and d.running_slow(), "driver: a stall is capped and flagged slow")
	check.call(Driver.MAX_TICKS_PER_FRAME <= 4 and d.run_frame(10.0) <= Driver.MAX_TICKS_PER_FRAME, "driver: a huge delta runs at most the cap")
	check.call(d.run_frame(1.0 / 80.0) == 1 and not d.running_slow(), "driver: keeping up clears the slow flag")
	d.budget_usec = 0  # spent at once: still one tick, and the rest of the debt is dropped
	var t0: int = d.tower.tick
	check.call(d.run_frame(10.0) == 1 and d.tower.tick == t0 + 1 and d.running_slow(), "driver: a spent budget still runs one tick")
	check.call(d.run_frame(0.0) == 0, "driver: dropped debt is not carried")
	d.budget_usec = -1
	d.set_speed(99)
	check.call(d.speed_index == 2, "driver: speed index is clamped")
	d.free()
