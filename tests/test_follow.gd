extends RefCounted
## Follow a person (#289): the camera's target tracks the figure's drawn position across ticks, a pan or
## closing the window stops it, and the person window shows today's plan. View only; the sim hash is untouched.

const TowerSim := preload("res://scripts/sim/tower.gd")
const PersonInfo := preload("res://scripts/view/person_info.gd")
const PeopleView := preload("res://scripts/view/people_view.gd")
const TestCondos := preload("res://tests/test_condos.gd")
const TestPersonWindow := preload("res://tests/test_person_window.gd")
const FOLLOW_TICKS := 120  ## A bounded run of ticks through the residents' morning departure.


static func _marked(lines: Array[String]) -> Array:
	return lines.filter(func(line: String) -> bool: return line.begins_with(">"))


static func run(check: Callable) -> void:
	var t := TestPersonWindow._fixture()
	TestCondos._at(t, 7 * 60 + 50, 0)  # ten minutes before the residents leave
	var camera := TowerCamera.new()
	var window := TestPersonWindow._window(t)
	window.camera = camera
	camera.follow_stopped.connect(window._on_follow_stopped)
	var id: int = t.people.id_at(0)
	window.open_person(id)
	check.call(window.is_open() and not window.is_following(), "follow: a window starts not following")
	var hash_before := t.state_hash()
	window.set_following(true)
	check.call(window.is_following() and window.follow_button.button_pressed, "follow: the Follow button turns it on")
	check.call(t.state_hash() == hash_before, "follow: following leaves the sim hash unchanged")

	# Across ticks the camera's target is always where the figure is drawn, and it moves with the person.
	var view := PeopleView.new()
	var always_on := true
	var drawn_ticks := 0
	var targets: Dictionary = {}
	for n in FOLLOW_TICKS:
		t.step()
		window._process(0.0)
		var at := PersonInfo.center_of(view.figures(t), id)
		if at != Vector2.INF:  # drawn: the target is exactly where
			drawn_ticks += 1
			always_on = always_on and camera.follow_target() == at
		targets[camera.follow_target()] = true
	check.call(drawn_ticks > 0 and always_on, "follow: the camera target is the figure's position at every tick it is drawn (%d ticks)" % drawn_ticks)
	check.call(targets.size() > 1, "follow: and it moves as the person walks (%d distinct spots)" % targets.size())

	# Easing closes on the target and snaps.
	var goal := Vector2(100, 0)
	var eased := TowerCamera.follow_step(Vector2.ZERO, goal)
	check.call(eased.x > 0.0 and eased.x < 100.0, "follow: the view eases toward the target")
	check.call(TowerCamera.follow_step(Vector2(99.8, 0), goal) == goal, "follow: and snaps once it is close")

	# A pan stops it and the button follows; so does Follow off, and closing the window (Esc).
	camera.pan_by_screen(Vector2(5, 0))
	check.call(not camera.is_following() and not window.follow_button.button_pressed, "follow: a pan stops it and releases the button")
	window.set_following(true)
	check.call(camera.is_following(), "follow: it can be turned on again")
	window.set_following(false)
	check.call(not camera.is_following(), "follow: the button off stops it")
	window.set_following(true)
	window.close()
	check.call(not camera.is_following() and not window.follow_button.button_pressed, "follow: closing the window stops it")

	# The window lists today's plan, with the entry in force marked.
	TestCondos._at(t, 12 * 60 + 30, 0)
	var noon := PersonInfo.plan_lines(t, 0)
	check.call(noon[0] == "Today:" and noon.size() == 3, "plan: a resident's plan has two entries under Today:")
	var at_noon := _marked(noon)
	check.call(at_noon.size() == 1 and "8:00" in at_noon[0] and "Away" in at_noon[0], "plan: at midday the 8:00 Away entry is the current one")
	TestCondos._at(t, 22 * 60, 0)
	var at_night := _marked(PersonInfo.plan_lines(t, 0))
	check.call(at_night.size() == 1 and "Home" in at_night[0], "plan: at night the Home entry is the current one")
	check.call(PersonInfo.clock_text(9 * 60 + 5) == "9:05", "plan: times read as clock text")

	window.free()
	camera.free()
