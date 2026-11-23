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
	check.call(d.run_frame(10.0) == Driver.MAX_TICKS_PER_FRAME and d.dropping_now(), "driver: a stall is capped and flagged dropping")
	check.call(Driver.MAX_TICKS_PER_FRAME <= 4 and d.run_frame(10.0) <= Driver.MAX_TICKS_PER_FRAME, "driver: a huge delta runs at most the cap")
	check.call(d.run_frame(1.0 / 80.0) == 1 and not d.dropping_now(), "driver: keeping up clears the dropping flag")
	d.budget_usec = 0  # spent at once: still one tick, and the rest of the debt is dropped
	var t0: int = d.tower.tick
	check.call(d.run_frame(10.0) == 1 and d.tower.tick == t0 + 1 and d.dropping_now(), "driver: a spent budget still runs one tick")
	check.call(d.run_frame(0.0) == 0, "driver: dropped debt is not carried")
	d.budget_usec = -1
	d.set_speed(99)
	check.call(d.speed_index == 2, "driver: speed index is clamped")
	d.free()
	_slow_label_tests(check)


## Slow flag hysteresis (#436). Speed 3x at 1/30 s gives 3 ticks due, so a cap of 1 drops and a cap of 4 does not.
static func _slow_label_tests(check: Callable) -> void:
	var dt := 1.0 / 30.0
	var d := Driver.new()
	d.budget_usec = -1
	d.set_speed(2)
	# (a) alternating slow and fast frames never toggle the label.
	var toggles := 0
	var last := d.running_slow()
	for i in 240:
		d.max_ticks_per_frame = 1 if i % 2 == 0 else 4
		d.run_frame(dt)
		if d.running_slow() != last:
			toggles += 1
			last = d.running_slow()
	check.call(toggles == 0 and not d.running_slow(), "driver: alternating slow and fast frames leave the slow flag steady")
	# (b) sustained dropping turns it on, and only after about a second; sustained recovery turns it off.
	d.max_ticks_per_frame = 1
	for i in 15:
		d.run_frame(dt)
	check.call(d.dropping_now() and not d.running_slow(), "driver: half a second of drops is not yet slow")
	for i in 25:
		d.run_frame(dt)
	check.call(d.running_slow(), "driver: over a second of drops turns slow on")
	d.max_ticks_per_frame = 4
	for i in 20:
		d.run_frame(dt)
	check.call(d.running_slow() and not d.dropping_now(), "driver: slow stays on until a second without drops")
	for i in 15:
		d.run_frame(dt)
	check.call(not d.running_slow(), "driver: a second without drops turns slow off")
	# While on, alternating frames keep it on without toggling.
	d.max_ticks_per_frame = 1
	for i in 40:
		d.run_frame(dt)
	toggles = 0
	for i in 240:
		d.max_ticks_per_frame = 1 if i % 2 == 0 else 4
		d.run_frame(dt)
		if not d.running_slow():
			toggles += 1
	check.call(toggles == 0, "driver: slow stays on through alternating frames")
	# (c) pausing clears it.
	d.set_paused(true)
	d.run_frame(dt)
	check.call(not d.running_slow() and not d.dropping_now(), "driver: pausing clears the slow flag")
	d.set_paused(false)
	d.max_ticks_per_frame = 1
	d.run_frame(dt)
	check.call(not d.running_slow(), "driver: slow starts over after a pause")
	d.free()
