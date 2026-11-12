extends RefCounted
## Drawing people (3.7): the 8 am commute is visible, tint and shape cue match the stress band,
## and reading the sim for drawing never changes it.

const TowerSim := preload("res://scripts/sim/tower.gd")
const TestCondos := preload("res://tests/test_condos.gd")
const TestTenancy := preload("res://tests/test_tenancy.gd")
const People := preload("res://scripts/sim/people.gd")
const PeopleView := preload("res://scripts/view/people_view.gd")


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
