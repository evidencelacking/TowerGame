extends SceneTree
## Headless game tests. Prints only failures, then a final summary line that
## tools/check.py requires. Exit code is the number of failures.

## Every tests/test_*.gd is run, in name order, through its static run(check): adding a test is adding a
## file, with nothing to register here. A test that another test calls itself (test_detailed_batch1) simply
## runs twice; tests share no state, so the order does not matter.
const TEST_DIR := "res://tests/"
const TOP_SLOWEST := 5

var failures := 0
## Wall time per test file in ms, to find the slow ones.
var _timings: Array = []


func _initialize() -> void:
	var names: Array[String] = []
	for file in DirAccess.get_files_at(TEST_DIR):
		if file.begins_with("test_") and file.ends_with(".gd"):
			names.append(file)
	names.sort()
	for file in names:
		var script: GDScript = load(TEST_DIR + file)
		var started: int = Time.get_ticks_msec()
		await script.call("run", check)  # a test may wait for frames (the renderer tests do)
		_timings.append([Time.get_ticks_msec() - started, file])
	_timings.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var slowest: Array[String] = []
	for i: int in mini(TOP_SLOWEST, _timings.size()):
		slowest.append("%s %d ms" % [_timings[i][1], _timings[i][0]])
	print("SLOWEST: " + ", ".join(slowest))
	print("TESTS FINISHED failures=%d" % failures)
	quit(failures)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: " + message)
