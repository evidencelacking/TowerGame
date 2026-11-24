extends SceneTree
## Prints Tower.state_hash every N ticks, to prove a sim optimisation changes no result (#467).
##   godot --headless --path . --script res://tools/hash_run.gd -- mixed|big|save=<path> [ticks=3000] [every=500] [warmup=N]
## mixed: bench_mixed seed 42 from the build (warmup 0); big: bench_big seed 42 after 400 warm-up ticks.
## A save is only read, never written. Every loop is bounded by its count.

const BenchMixed := preload("res://tools/bench_mixed.gd")
const BenchBig := preload("res://tools/bench_big.gd")


func _init() -> void:
	var mode := ""
	var ticks := 3000
	var every := 500
	var warmup := -1
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("ticks="):
			ticks = int(a.substr(6))
		elif a.begins_with("every="):
			every = maxi(1, int(a.substr(6)))
		elif a.begins_with("warmup="):
			warmup = int(a.substr(7))
		else:
			mode = a
	var t: Tower = null
	if mode == "mixed":
		t = BenchMixed.build(42)
		warmup = maxi(warmup, 0)
	elif mode == "big":
		t = BenchBig.build(42)
		warmup = 400 if warmup < 0 else warmup
	elif mode.begins_with("save="):
		t = Tower.new()
		if not t.load_state(SaveFiles.read(mode.substr(5))):
			print("FAIL: could not load the save")
			quit(1)
			return
		warmup = maxi(warmup, 0)
	else:
		print("FAIL: give mixed, big or save=<path>")
		quit(1)
		return
	for _i in warmup:
		t.step()
	var t0 := Time.get_ticks_usec()
	for i in ticks:
		t.step()
		if (i + 1) % every == 0:
			print("tick %d hash %d" % [i + 1, t.state_hash()])
	print("done %d ticks in %.1f s" % [ticks, (Time.get_ticks_usec() - t0) / 1e6])
	quit(0)
