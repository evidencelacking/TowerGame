extends SceneTree
func _init() -> void:
	var suites := OS.get_environment("SUITES").split(",")
	var fails := [0]
	var check := func(ok: bool, msg: String) -> void:
		if not ok:
			fails[0] += 1
			print("FAIL: ", msg)
	for s in suites:
		load("res://tests/%s.gd" % s).run(check)
	print("done fails=", fails[0])
	quit(fails[0])
