extends RefCounted
## Joined suites (#276, step 1): neighbouring rooms of one kind, all in use, draw as one suite; an empty room,
## a different kind, another floor or a gap breaks it; the suite recipe and the figures' spots stay inside
## the joined width; the same tower gives the same suites and the simulation is untouched.

const TowerSim := preload("res://scripts/sim/tower.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const TestTenancy := preload("res://tests/test_tenancy.gd")
const TestOfficeDay := preload("res://tests/test_office_day.gd")
const RoomRecipes := preload("res://scripts/view/room_recipes.gd")
const Suites := preload("res://scripts/view/suites.gd")
const PeopleView := preload("res://scripts/view/people_view.gd")
const ActivityLook := preload("res://scripts/view/activity_look.gd")
const VC := preload("res://scripts/view/view_consts.gd")

const OFFICE_COLUMNS: Array[int] = [110, 119, 128]  ## Three offices side by side, 9 columns each.


static func _entry(key: int, x: int, w: int, kind: String, in_use: bool) -> Dictionary:
	return {"key": key, "x": x, "w": w, "kind": kind, "in_use": in_use}


## A floor of three adjacent offices, reachable by stairs, at mid-morning when they are full of workers.
static func _tower() -> TowerSim:
	var t := TowerSim.new(7, 100000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 131, 2)
	t.floors.fill_span(3, 100, 140)
	for x: int in OFFICE_COLUMNS:
		t.rooms.place_room(t.grid, t.floors, t.ledger, 0, CatalogueScript.IDS.find("office"), 3, x)
	TestTenancy._link(t)
	TestTenancy._run_at(t, TestTenancy.MORNING_TICK)
	TestOfficeDay._at(t, 10 * 60 + 5)
	return t


static func run(check: Callable) -> void:
	# The rule, on plain entries. Results are compared as text so typed and untyped arrays agree.
	var w := 72
	var two: Array = [_entry(0, 0, w, "office", true), _entry(0, w, w, "office", true)]
	check.call(str(Suites.groups(two)) == "[[0, 1]]", "suites: two neighbouring offices in use join")
	var three: Array = two + [_entry(0, 2 * w, w, "office", true)]
	check.call(str(Suites.groups(three)) == "[[0, 1, 2]]", "suites: a third neighbour joins the suite")
	var empty_between: Array = [_entry(0, 0, w, "office", true), _entry(0, w, w, "office", false), _entry(0, 2 * w, w, "office", true)]
	check.call(Suites.groups(empty_between).is_empty(), "suites: an empty room does not join, and splits what is around it")
	var empty_last: Array = [_entry(0, 0, w, "office", true), _entry(0, w, w, "office", true), _entry(0, 2 * w, w, "office", false)]
	check.call(str(Suites.groups(empty_last)) == "[[0, 1]]", "suites: an empty third stays out of the pair")
	check.call(Suites.groups([_entry(0, 0, w, "office", true), _entry(0, w, w, "retail", true)]).is_empty(), "suites: a different kind does not join")
	check.call(Suites.groups([_entry(0, 0, w, "office", true), _entry(0, w + 8, w, "office", true)]).is_empty(), "suites: rooms with a gap between do not join")
	check.call(Suites.groups([_entry(0, 0, w, "office", true), _entry(32, w, w, "office", true)]).is_empty(), "suites: rooms on different floors do not join")
	check.call(Suites.groups([_entry(0, 0, 40, "lobby", true), _entry(0, 40, 40, "lobby", true)]).is_empty(), "suites: kinds without a suite recipe do not join")
	var spans := Suites.span(three, [0, 1, 2] as Array[int])
	check.call(str(spans) == "[0, 216]", "suites: the span covers every joined room (%s)" % str(spans))

	# Every suite recipe fits every joined width and has spots to stand on.
	var bad: Array[String] = []
	for kind: String in Suites.KINDS:
		check.call(RoomRecipes.has_suite(kind), "suites: %s has a suite recipe" % kind)
		var one: int = int(CatalogueScript.field(kind, "width")) * VC.CELL_W
		for rooms_joined: int in [2, 3, 4, 7]:
			var width_px := one * rooms_joined
			var room := Rect2i(0, 0, width_px, RoomRecipes.INTERIOR_H)
			var parts := RoomRecipes.layout(kind, width_px, false, RoomRecipes.SUITE)
			for shape: Array in parts["shapes"]:
				if not room.encloses(Rect2i(shape[0], shape[1], shape[2], shape[3])) or (shape[2] as int) <= 0:
					bad.append("%s x%d shape %s" % [kind, rooms_joined, str(shape)])
			if (parts["spots"] as Array).size() < rooms_joined:
				bad.append("%s x%d has %d spots" % [kind, rooms_joined, (parts["spots"] as Array).size()])
			for spot: Vector2i in parts["spots"]:
				if not RoomRecipes.spot_inside(spot, width_px):
					bad.append("%s x%d spot %s" % [kind, rooms_joined, str(spot)])
			for act: int in ActivityLook.COUNT:
				if act == ActivityLook.SLEEPING:
					continue
				for turn in 6:
					var at := ActivityLook.place(act, ActivityLook.spot_for(kind, width_px, turn * 3, turn, act, RoomRecipes.SUITE), width_px)
					if not room.encloses(ActivityLook.body_rect(act, at.x, at.y)):
						bad.append("%s x%d %s pose" % [kind, rooms_joined, ActivityLook.NAMES[act]])
	check.call(bad.is_empty(), "suites: suite recipes, spots and poses stay inside the joined width (%s)" % str(bad.slice(0, 3)))
	var base_layout := RoomRecipes.layout("office", 144, false, 0)
	check.call(RoomRecipes.layout("office", 144, false, RoomRecipes.SUITE)["shapes"] != base_layout["shapes"], "suites: a suite draws differently from two single rooms")

	# In a tower: three neighbouring offices, all at work, are one suite and the workers sit inside it.
	var t := _tower()
	var hash_before := t.state_hash()
	var view := PeopleView.new()
	var figures := view.figures(t)
	var runs: Array[Array] = []
	var in_use: Dictionary = {}
	for id: int in t.rooms.room_ids():
		var run: Array[int] = t.grid.run_of(id)
		if t.rooms.kind_of(id) != "office" or run.is_empty():
			continue
		runs.append([id, id, Rect2i(run[1] * VC.CELL_W, VC.floor_to_row(run[0]) * VC.CELL_H, run[2] * VC.CELL_W, VC.CELL_H)])
	runs.sort_custom(func(a: Array, b: Array) -> bool: return (a[2] as Rect2i).position.x < (b[2] as Rect2i).position.x)
	for f: Dictionary in figures:
		if not f["moving"]:
			in_use[t.rooms.room_of(t.grid.cell_at(f["floor"], f["x"]))] = true
	var found := Suites.groups(Suites.entries_for(t, runs, in_use))
	check.call(runs.size() == 3 and str(found) == "[[0, 1, 2]]", "suites: three neighbouring offices at work draw as one suite (%d rooms, %s)" % [runs.size(), str(found)])
	var union := Rect2i(0, 0, 3 * 9 * VC.CELL_W, RoomRecipes.INTERIOR_H)  # the suite in its own coordinates
	var resting := 0
	var inside := true
	var slices: Dictionary = {}
	for f: Dictionary in figures:
		if f["moving"]:
			continue
		resting += 1
		var row_top := VC.floor_to_row(f["floor"]) * VC.CELL_H
		var local_x: int = (f["px"] as int) - OFFICE_COLUMNS[0] * VC.CELL_W
		inside = inside and union.encloses(ActivityLook.body_rect(f["act"], local_x, (f["pfeet"] as int) - row_top))
		slices[local_x / (9 * VC.CELL_W)] = true  # which office-width slice of the suite
	check.call(resting > 0 and inside, "suites: figures stand inside the joined suite (%d resting)" % resting)
	check.call(slices.size() >= 2, "suites: workers spread along the suite, not just one office's width (%d slices)" % slices.size())
	check.call(view.figures(t) == figures, "suites: the same tower gives the same figures")
	check.call(t.state_hash() == hash_before, "suites: reading suites leaves the sim hash unchanged")

	# With the middle office empty nothing joins.
	var dim: Dictionary = in_use.duplicate()
	dim.erase(runs[1][1])
	check.call(Suites.groups(Suites.entries_for(t, runs, dim)).is_empty(), "suites: with the middle office empty nothing joins")
