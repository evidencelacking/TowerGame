extends SceneTree
## Headless game tests. Prints only failures, then a final summary line that
## tools/check.py requires. Exit code is the number of failures.

## Every tests/test_*.gd is run, in name order, through its static run(check): adding a test is adding a
## file, with nothing to register here. A test that another test calls itself (test_detailed_batch1) simply
## runs twice; tests share no state, so the order does not matter.
const TEST_DIR := "res://tests/"

var failures := 0


func _initialize() -> void:
	var names: Array[String] = []
	for file in DirAccess.get_files_at(TEST_DIR):
		if file.begins_with("test_") and file.ends_with(".gd"):
			names.append(file)
	names.sort()
	for file in names:
		var script: GDScript = load(TEST_DIR + file)
		script.call("run", check)
	print("TESTS FINISHED failures=%d" % failures)
	quit(failures)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: " + message)
