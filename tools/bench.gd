extends SceneTree
## Performance benchmark (4.10): a fixed-seed tower of about 2,000 people, stepped headless.
## Reports ms per tick (sim only), the view-side elevator gesture cost, and the final state hash.
## Run: timeout 300 <godot console exe> --headless --path . --script res://tools/bench.gd -- ticks=2550 warmup=200 > bench.txt
## Exits 1 if the tower came up short (fewer than 340 offices or 1,800 people), so a "fast"
## result cannot come from an empty tower. The hash must not change under an optimisation
## (tests/test_bench.gd pins a short run). Wall-clock timing is fine here: this is a tool, not the sim.

const CarsScript := preload("res://scripts/sim/cars.gd")
const Bench := preload("res://tools/bench_tower.gd")
const ElevatorTools := preload("res://scripts/view/elevator_tools.gd")

## sim_driver.gd: 30 base ticks/s x top speed 3 = 90 ticks/s, so 1.5 ticks per 60 fps frame
## (2 on some frames). The 16 ms frame budget therefore allows about 10.6 ms per tick.
const TICKS_PER_FRAME_AT_TOP := 1.5
const FRAME_MS := 16.0
const MIN_PEOPLE := 1800
const DAY_TICKS := 2550  ## One sim day: the clock's six periods add to this.


func _initialize() -> void:
	var ticks := DAY_TICKS
	var warmup := 200
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("ticks="):
			ticks = int(arg.get_slice("=", 1))
		elif arg.begins_with("warmup="):
			warmup = int(arg.get_slice("=", 1))
	var t := Bench.build(42)
	var offices := Bench.office_count(t)
	print("built: %d offices, %d shafts, %d cars" % [offices, t.rooms.shaft_count(), t.rooms.total_cars()])
	# The first tick moves every office's workers in (a route search per office), and the next
	# minutes send them all to their desks at once: both are reported apart, not timed.
	var move_in := Time.get_ticks_usec()
	t.step()
	print("move-in tick: %.1f ms, %d people" % [(Time.get_ticks_usec() - move_in) / 1000.0, t.people.count()])
	var settle := Time.get_ticks_usec()
	for _i in warmup:
		t.step()
	print("warm-up: %d ticks in %.1f ms" % [warmup, (Time.get_ticks_usec() - settle) / 1000.0])
	if OS.get_cmdline_user_args().has("profile"):
		_profile(t, ticks)
		quit(0)
		return
	var costs: Array[int] = []
	for _i in ticks:
		var t0 := Time.get_ticks_usec()
		t.step()
		costs.append(Time.get_ticks_usec() - t0)
	var total_us := 0
	for c in costs:
		total_us += c
	var per_tick := total_us / 1000.0 / ticks
	costs.sort()
	var p95 := costs[ticks * 95 / 100] / 1000.0
	var p99 := costs[ticks * 99 / 100] / 1000.0
	print("sim: %d ticks (from tick %d), %d people, %d in tower" % [ticks, t.tick - ticks, t.people.count(), t.population()])
	print("  %.3f ms/tick avg, %.3f p95, %.3f p99, %.3f worst, %.0f ticks/s" % [per_tick, p95, p99, costs[ticks - 1] / 1000.0, ticks * 1000000.0 / total_us])
	print("  frame at top speed: %.1f ticks x avg = %.2f ms, x p99 = %.2f ms (limit %.0f)" % [TICKS_PER_FRAME_AT_TOP, TICKS_PER_FRAME_AT_TOP * per_tick, TICKS_PER_FRAME_AT_TOP * p99, FRAME_MS])
	print("hash: %d" % t.state_hash())
	_time_gestures(t)
	if offices < Bench.OFFICES or t.people.count() < MIN_PEOPLE or t.rooms.total_cars() < 64:
		print("FAIL: tower too small (%d offices, %d people, %d cars)" % [offices, t.people.count(), t.rooms.total_cars()])
		quit(1)
		return
	quit(0)


## One shaft-tool hover, one stop toggle and one car-tool hover, as placement_ghost evaluates them.
func _time_gestures(t: Object) -> void:
	var n := 100
	var hit_x: int = t.rooms.shaft_x(t.rooms.shaft_ids()[0])
	var t0 := Time.get_ticks_usec()
	for _i in n:
		ElevatorTools.evaluate_shaft(t, "local_shaft", 5, 5, 5, 5)
	var place_ms := (Time.get_ticks_usec() - t0) / 1000.0 / n
	t0 = Time.get_ticks_usec()
	for _i in n:
		ElevatorTools.evaluate_shaft(t, "local_shaft", 5, 5, hit_x, 5)
	var stop_ms := (Time.get_ticks_usec() - t0) / 1000.0 / n
	t0 = Time.get_ticks_usec()
	for _i in n:
		ElevatorTools.evaluate_car(t, "local_car", 5, hit_x, 5)
	var car_ms := (Time.get_ticks_usec() - t0) / 1000.0 / n
	print("gesture: place %.3f ms, stop toggle %.3f ms, add car %.3f ms (per hover)" % [place_ms, stop_ms, car_ms])


## Per-system cost, mirroring Tower._run_systems (same order). Changes the tower, so it is a
## separate mode; the hash it leaves behind is not the benchmark hash.
func _profile(t: Object, ticks: int) -> void:
	var names := ["clock", "tenancy", "trips", "grades", "cars", "arrivals", "people"]
	var us: Array[int] = [0, 0, 0, 0, 0, 0, 0]
	for _i in ticks:
		t.tick += 1
		var t0 := Time.get_ticks_usec()
		t.clock.advance()
		var t1 := Time.get_ticks_usec()
		t.tenancy.tick(t.clock, t.floors, t.rooms, t.grid, t.people, t.rng, t.ledger, t.tick)
		var t2 := Time.get_ticks_usec()
		t.trips.tick(t.clock, t.floors, t.rooms, t.grid, t.people)
		var t3 := Time.get_ticks_usec()
		t.grades.tick(t.people)
		var t4 := Time.get_ticks_usec()
		CarsScript.tick(t.rooms)
		var t5 := Time.get_ticks_usec()
		t.trips.collect_arrivals(t.floors, t.rooms, t.grid, t.people)
		var t6 := Time.get_ticks_usec()
		t.people.tick(t.clock)
		var t7 := Time.get_ticks_usec()
		var marks := [t0, t1, t2, t3, t4, t5, t6, t7]
		for k in 7:
			us[k] += marks[k + 1] - marks[k]
	for k in 7:
		print("profile %-9s %.3f ms/tick" % [names[k], us[k] / 1000.0 / ticks])
	print("people %d" % t.people.count())
