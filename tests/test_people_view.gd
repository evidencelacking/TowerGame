extends RefCounted
## Drawing people (3.7): the 8 am commute is visible, tint and shape cue match the stress band,
## and reading the sim for drawing never changes it.

const TowerSim := preload("res://scripts/sim/tower.gd")
const TestCondos := preload("res://tests/test_condos.gd")
const TestTenancy := preload("res://tests/test_tenancy.gd")
const People := preload("res://scripts/sim/people.gd")
const PeopleView := preload("res://scripts/view/people_view.gd")
const VC := preload("res://scripts/view/view_consts.gd")


static func run(check: Callable) -> void:
	var t := TestCondos._tower()
	TestTenancy._link(t)
	TestCondos._at(t, 10 * 60, 0)  # sold, residents exist
	var view := PeopleView.new()
	TestCondos._at(t, 22 * 60, 0)
	var homes := view.figures(t)
	check.call(homes.size() == 3 and not (homes[0]["moving"] as bool) and homes[0]["floor"] == 3, "people view: residents at home are drawn in their condo")

	TestCondos._at(t, 8 * 60 - 1, 1)
	var lobby_left: int = t.floors.lobby_span()[0]
	var seen := false
	var hash_before := 0
	for n in 400:
		t.step()
		if t.clock.minute_of_day() < 8 * 60 + 5:
			continue
		hash_before = t.state_hash()
		for f: Dictionary in view.figures(t):
			if f["moving"] and (f["x"] as int) >= lobby_left and (f["x"] as int) <= 110 and (f["floor"] as int) >= 1 and (f["floor"] as int) <= 3:
				seen = true
		check.call(t.state_hash() == hash_before, "people view: drawing leaves the sim hash unchanged")
		break
	check.call(seen, "people view: at 8:05 a resident is drawn in transit between the condo and the lobby edge")

	var legs := [{"kind": 1, "floor": 3, "from_x": 110, "to_x": 100, "to_floor": 3}, {"kind": 2, "floor": 3, "from_x": 100, "to_x": 100, "to_floor": 2}]
	check.call(PeopleView.along(legs, 0, 10) == [3, 110], "people view: a trip starts at its start")
	check.call(PeopleView.along(legs, 10, 10) == [2, 100], "people view: a trip ends at its goal")

	# Smooth stairs: height moves a little every step from one floor to the next, with no halfway jump,
	# and the figure crosses the link's width as it climbs (left to right going up, back going down).
	var climb := [{"kind": 2, "floor": 1, "from_x": 100, "to_x": 100, "to_floor": 2}]
	var rows: Array[float] = []
	var columns: Array[float] = []
	for elapsed in 21:
		var step_spot := PeopleView.along_f(climb, elapsed, 20)
		rows.append(step_spot["frow"])
		columns.append(step_spot["fx"])
	var up_steps_ok := true
	for n in range(1, rows.size()):
		up_steps_ok = up_steps_ok and rows[n] < rows[n - 1] and rows[n - 1] - rows[n] < 0.1 and columns[n] > columns[n - 1]
	check.call(up_steps_ok and rows[0] == float(VC.floor_to_row(1)) and rows[20] == float(VC.floor_to_row(2)), "people view: height moves smoothly from floor to floor along a stairs leg")
	var link_end := 100.0 + PeopleView.link_columns(2) - 1
	check.call(columns[0] == 100.0 and columns[20] == link_end, "people view: climbing a stairs leg crosses the link left to right")
	var descend := [{"kind": 2, "floor": 2, "from_x": 100, "to_x": 100, "to_floor": 1}]
	check.call(PeopleView.along_f(descend, 0, 20)["fx"] == link_end and PeopleView.along_f(descend, 20, 20)["fx"] == 100.0, "people view: going down a stairs leg crosses the link right to left")
	check.call(PeopleView.along_f(climb, 10, 20)["pose"] == PeopleView.POSE_STAIRS and PeopleView.along_f(legs, 0, 10)["pose"] == PeopleView.POSE_WALK, "people view: stairs legs have the stairs pose, walking the walk pose")
	var belt := [{"kind": 4, "floor": 1, "from_x": 90, "to_x": 90, "to_floor": 2}]
	check.call(PeopleView.along_f(belt, 5, 10)["pose"] == PeopleView.POSE_ESCALATOR and (PeopleView.along_f(belt, 10, 10)["fx"] as float) == 90.0 + PeopleView.link_columns(4) - 1, "people view: an escalator leg glides across its whole belt in the escalator pose")

	check.call(PeopleView.color_of(People.BAND_CALM) == Color(0.05, 0.05, 0.05), "people view: calm is black")
	check.call(PeopleView.color_of(People.BAND_UNEASY).r > 0.9 and PeopleView.color_of(People.BAND_UNEASY).b > 0.5, "people view: uneasy is pink")
	check.call(PeopleView.color_of(People.BAND_ANGRY).r > 0.8 and PeopleView.color_of(People.BAND_ANGRY).g < 0.2, "people view: angry is red")
	check.call(PeopleView.marks_of(People.BAND_CALM) == 0 and PeopleView.marks_of(People.BAND_UNEASY) == 1 and PeopleView.marks_of(People.BAND_ANGRY) == 2, "people view: shape cue is 0, 1, 2 marks")
	var s := TestCondos._tower()
	TestTenancy._link(s)
	TestCondos._at(s, 10 * 60, 0)
	TestCondos._at(s, 22 * 60, 0)
	s.people.set_stress(0, People.UNEASY_FROM)
	s.people.set_stress(1, People.ANGRY_OVER + 1)
	var bands: Array[int] = []
	for f: Dictionary in view.figures(s):
		bands.append(f["band"])
	check.call(bands == [People.BAND_UNEASY, People.BAND_ANGRY, People.BAND_CALM], "people view: figures carry the stress band")
	# Looks are built for drawn people only (#418) and equal the direct per-person lookup.
	var looked := 0
	for f: Dictionary in view.figures(s):
		if f.has("age"):
			var j: int = s.people.index_of(f["id"])
			looked += 1
			check.call(f["age"] == s.life.age_band_of(s, f["id"]) and f["child"] == s.life.is_child(f["id"]) and f["job"] == s.rooms.kind_of(s.people.work_of(j)), "people view: a figure's look matches the direct lookup")
	check.call(looked == 3, "people view: every drawn person has a look")
