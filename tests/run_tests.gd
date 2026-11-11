extends SceneTree
## Headless game tests. Prints only failures, then a final summary line that
## tools/check.py requires. Exit code is the number of failures.

const TestTower := preload("res://tests/test_tower.gd")
const TestClock := preload("res://tests/test_clock.gd")
const TestGrid := preload("res://tests/test_grid.gd")
const TestCamera := preload("res://tests/test_camera.gd")
const TestDriver := preload("res://tests/test_driver.gd")

var failures := 0


func _initialize() -> void:
	TestTower.run(check)
	TestClock.run(check)
	TestGrid.run(check)
	TestCamera.run(check)
	TestDriver.run(check)
	print("TESTS FINISHED failures=%d" % failures)
	quit(failures)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: " + message)
