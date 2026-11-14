extends RefCounted
## Person info window tests (5.9): names come from the seed and id, picking takes the nearest
## figure at any zoom, the window opens on a click on a person (and not under a build tool),
## shows name, from, to and stress band, and a rename persists through save and load.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const NamesScript := preload("res://scripts/sim/names.gd")
const PersonInfo := preload("res://scripts/view/person_info.gd")
const PeopleView := preload("res://scripts/view/people_view.gd")
const Ghost := preload("res://scripts/view/placement_ghost.gd")
const TestCondos := preload("res://tests/test_condos.gd")
const TestTenancy := preload("res://tests/test_tenancy.gd")
const Harness := preload("res://tests/harness.gd")


static func _fixture() -> TowerSim:
	var t := TestCondos._tower()
	TestTenancy._link(t)
	TestCondos._at(t, 10 * 60, 0)  # sold, residents exist
	TestCondos._at(t, 22 * 60, 0)  # all home on floor 3
	return t


static func _window(t: TowerSim, ghost: Ghost = null) -> PersonWindow:
	var window := PersonWindow.new()
	window.bind(t, ghost)
	return window


static func run(check: Callable) -> void:
	# Names: derived from seed and id, stable, inside the lists, and varied.
	check.call(NamesScript.generated(7, 3) == NamesScript.generated(7, 3), "names: the same seed and id give the same name")
	var seen: Dictionary = {}
	for id in 200:
		seen[NamesScript.generated(42, id)] = true
	check.call(seen.size() > 150, "names: 200 ids give mostly different names")
	var differs := 0
	for id in 50:
		if NamesScript.generated(1, id) != NamesScript.generated(2, id):
			differs += 1
	check.call(differs > 40, "names: a different seed names people differently")
	check.call(NamesScript.generated(-5, 0).split(" ").size() == 2, "names: a negative seed still gives a first and last name")

	var t := _fixture()
	check.call(t.people.count() == 3, "fixture: three residents")
	var name0 := t.names.name_of(t.people.id_at(0))
	check.call(name0 == NamesScript.generated(7, t.people.id_at(0)), "names: a person's name is the generated one until renamed")
	check.call(TowerSim.new(7).save()["names"] == [7, 0], "names: generated names are not saved, only the seed")

	# Picking: nearest figure within the radius, whatever the zoom.
	var figures := PeopleView.new().figures(t)
	check.call(figures.size() == 3 and figures[0].has("id"), "figures carry the person id")
	var first_id: int = figures[0]["id"]
	var spot := PersonInfo.figure_center(figures[0])
	check.call(PersonInfo.pick(figures, spot, 10.0) == first_id, "pick: a click on a figure picks it")
	check.call(PersonInfo.pick(figures, spot + Vector2(400, 0), 10.0) == -1, "pick: a click far from everyone picks nobody")
	var crowd: Array[Dictionary] = [
		{"id": 5, "floor": 3, "x": 10}, {"id": 6, "floor": 3, "x": 11}, {"id": 7, "floor": 3, "x": 12}]
	var at_six := PersonInfo.figure_center(crowd[1]) + Vector2(3, 0)
	check.call(PersonInfo.pick(crowd, at_six, 14.0) == 6, "pick: among a crowd the closest one is chosen, not the first")
	check.call(PersonInfo.pick(crowd, PersonInfo.figure_center(crowd[0]) + Vector2(8, 0), 14.0) == 5, "pick: a point exactly between two goes to the lower id")
	check.call(PersonInfo.pick(crowd, at_six, 3.5) == 6, "pick: a zoomed-in click with a small world radius still finds the figure")
	check.call(PersonInfo.pick(crowd, at_six + Vector2(0, 40), 14.0) == -1, "pick: a point on another floor picks nobody")
	var no_one: Array[Dictionary] = []
	check.call(PersonInfo.pick(no_one, Vector2.ZERO, 10.0) == -1, "pick: nobody on screen picks nobody")

	# The window: opens on a click on a person, not while a build tool is active.
	var ghost := Ghost.new()
	var window := _window(t, ghost)
	check.call(not window.is_open(), "window: starts closed")
	var hash_before := t.state_hash()
	check.call(window.open_at(spot, 10.0) and window.is_open() and window.person_id == first_id, "window: opens on a click on a person")
	check.call(t.state_hash() == hash_before, "window: opening it leaves the sim hash unchanged")
	check.call(window.panel.title_text() == name0, "window: the title is the person's name")
	var body := window.panel.body_text()
	check.call("From: Condo, floor 3" in body and "To: Condo, floor 3" in body, "window: at home, from and to are their room")
	var shown_stress := t.people.stress_of(t.people.index_of(first_id))
	check.call("Stress: %d (%s)" % [shown_stress, PersonInfo.BAND_NAMES[t.people.stress_band(t.people.index_of(first_id))]] in body, "window: stress shows with its band")
	check.call(window.panel.has_rename_field() and window.panel.field_text() == name0, "window: a rename field holds the current name")
	window.close()
	check.call(not window.is_open() and not window.panel.visible, "window: close hides it")
	check.call(not window.open_at(spot + Vector2(400, 0), 10.0) and not window.is_open(), "window: a click on empty space opens nothing")
	ghost.set_tool("office")
	check.call(not window.open_at(spot, 10.0) and not window.is_open(), "window: stays shut while a build tool is active")
	ghost.set_tool("")
	check.call(window.open_at(spot, 10.0), "window: opens again once the tool is off")

	# Bands and outside.
	t.people.set_stress(0, 100)
	check.call("(Uneasy)" in PersonInfo.lines_for(PersonInfo.describe(t, 0))[2], "describe: stress 100 reads uneasy")
	t.people.set_stress(0, 200)
	check.call("(Angry)" in PersonInfo.lines_for(PersonInfo.describe(t, 0))[2], "describe: stress 200 reads angry")
	TestCondos._at(t, 10 * 60, 1)  # residents are out at work
	check.call(PersonInfo.describe(t, 0)["to"] == "outside", "describe: a resident heading to work is going to outside")
	check.call(PersonInfo.room_label(t, -1) == "outside", "describe: no room reads outside")

	# Rename: a command, applied on a tick, saved and loaded, and clearable.
	var t2 := _fixture()
	var plain := _fixture()
	var w2 := _window(t2)
	var id: int = t2.people.id_at(0)
	check.call(not w2.rename("Nobody"), "rename: needs an open window")
	w2.open_person(id)
	check.call(w2.rename("  Ada Q. Tester  "), "rename: queues a RENAME_PERSON command")
	check.call(t2.names.name_of(id) == NamesScript.generated(7, id), "rename: nothing changes until the tick applies it")
	t2.step()
	plain.step()
	check.call(t2.names.name_of(id) == "Ada Q. Tester" and t2.names.is_renamed(id), "rename: the name is trimmed and applied on the tick")
	var other: int = t2.people.id_at(1)
	check.call(not t2.names.is_renamed(other), "rename: only that person changes")
	check.call(t2.state_hash() != plain.state_hash(), "rename: a rename is part of the state hash")
	var copy := Harness.clone_via_save(t2)
	check.call(copy != null and copy.names.name_of(id) == "Ada Q. Tester", "rename: persists through save and load")
	check.call(copy != null and copy.names.name_of(other) == t2.names.name_of(other), "rename: other people's generated names survive save and load")
	check.call(copy != null and copy.state_hash() == t2.state_hash(), "rename: a loaded tower has the same state hash")
	t2.enqueue(Command.make(t2.tick + 1, Command.RENAME_PERSON, [id] as Array[int]))
	t2.step()
	check.call(t2.names.name_of(id) == NamesScript.generated(7, id), "rename: an empty name restores the generated one")
	t2.enqueue(Command.make(t2.tick + 1, Command.RENAME_PERSON, [9999, 65] as Array[int]))
	t2.step()
	check.call(t2.save()["names"] == [7, 0], "rename: a rename of nobody is ignored")
	check.call(NamesScript.clean("ABCDEFGHIJKLMNOPQRSTUVWXYZ").length() == NamesScript.MAX_LENGTH, "rename: names are cut to the longest length")
	check.call(NamesScript.clean("A\nB\tC") == "ABC", "rename: control characters are dropped")

	# Save validation.
	check.call(not NamesScript.valid_ints([7, 1, 0, 3, 65]), "names: a save cut short is refused")
	check.call(not NamesScript.valid_ints([7, 1, 0, 1, 5]), "names: a save with a control code is refused")
	check.call(NamesScript.valid_ints([7, 1, 0, 1, 65]), "names: a well-formed save is accepted")
	var bad := t2.save()
	bad.erase("names")
	check.call(not TowerSim.new(0).load_state(bad), "names: a save without names is refused")

	window.free()
	w2.free()
	ghost.free()
