extends SceneTree
## Headless game tests. Prints only failures, then a final summary line that
## tools/check.py requires. Exit code is the number of failures.

const TestTower := preload("res://tests/test_tower.gd")

var failures := 0


func _initialize() -> void:
	TestTower.run(check)
	print("TESTS FINISHED failures=%d" % failures)
	quit(failures)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: " + message)
