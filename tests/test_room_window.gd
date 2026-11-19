extends RefCounted
## Room info window tests (5.8): hover and click pick the room under the pointer, the window shows
## occupants, grade, rent and every complaint reason worst first, the grade bar colour flips at
## 200 and 150, a rent change made in the window applies in the sim, and a vacant unit reads For Rent.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Rent := preload("res://scripts/sim/rent.gd")
const Grades := preload("res://scripts/sim/grades.gd")
const Complaints := preload("res://scripts/sim/complaints.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const RunningCosts := preload("res://scripts/sim/running_costs.gd")
const RoomInfo := preload("res://scripts/view/room_info.gd")
const Ghost := preload("res://scripts/view/placement_ghost.gd")
const VC := preload("res://scripts/view/view_consts.gd")
const TestRent := preload("res://tests/test_rent.gd")
const TestCondos := preload("res://tests/test_condos.gd")
const TestTenancy := preload("res://tests/test_tenancy.gd")


static func _of_kind(t: TowerSim, kind: String) -> Array[int]:
	var found: Array[int] = []
	for id in t.rooms.room_ids():
		if t.rooms.kind_of(id) == kind:
			found.append(id)
	return found


## The world point at the middle of a room's first cell.
static func _spot(t: TowerSim, room: int) -> Vector2:
	var run := t.grid.run_of(room)
	return Vector2((run[1] + 0.5) * VC.CELL_W, (VC.floor_to_row(run[0]) + 0.5) * VC.CELL_H)


static func run(check: Callable) -> void:
	var t := TestRent._two_offices()
	var offices := _of_kind(t, "office")
	check.call(offices.size() == 2, "fixture: two offices")
	var a := offices[0]
	var spot := _spot(t, a)
	check.call(RoomInfo.room_at(t, spot) == a, "room_at: a point inside a room finds it")
	check.call(RoomInfo.floor_at_y(spot.y) == 3, "floor_at_y: the row maps back to floor 3")
	check.call(RoomInfo.floor_at_y(VC.CELL_H * 100.5) == -1 and RoomInfo.floor_at_y(VC.CELL_H * 99.5) == 1, "floor_at_y: floor 1 sits above B1")
	check.call(RoomInfo.room_at(t, Vector2(-5, spot.y)) == -1 and RoomInfo.room_at(t, Vector2(spot.x, -5)) == -1, "room_at: off the tower finds nothing")

	var ghost := Ghost.new()
	var window := RoomWindow.new()
	window.bind(t, ghost)
	var hash_before := t.state_hash()
	check.call(not window.is_open(), "window: starts closed")
	check.call(window.hover_at(spot) and window.room_id == a and not window.pinned, "window: hover opens it unpinned")
	check.call(window.hover_at(Vector2(spot.x, -5)) == false and not window.is_open(), "window: hovering nothing closes an unpinned window")
	window.hover_at(spot)
	window.click_at(spot, 0.0)
	check.call(window.pinned and window.room_id == a, "window: a click pins the room")
	window.hover_at(Vector2(spot.x, -5))
	check.call(window.is_open(), "window: hover does not close a pinned window")
	check.call(t.state_hash() == hash_before, "window: opening it leaves the sim hash unchanged")

	# Content for a fixed tower: occupants, grade, rent, reasons.
	var info := RoomInfo.describe(t, a)
	var body := window.panel.body_text()
	check.call(window.panel.title_text() == "Office", "window: the title is the room kind")
	check.call(info["occupants"].size() > 0, "fixture: the office has occupants")
	check.call("Occupants: %d of %d" % [info["occupants"].size(), t.rooms.people_in(a)] in body, "window: shows the occupant count")
	for who: String in info["occupants"]:
		check.call(who in body, "window: lists occupant %s" % who)
	check.call("Grade %s (quality %d of 300)" % [Grades.letter(t.grade(a)), t.quality(a)] in body, "window: shows grade and quality from the sim")
	check.call("Rent: $%d a quarter (Average)" % t.rent_amount(a) in body, "window: shows the rent at the default level")
	check.call(window.bar.visible and window.bar.value == t.quality(a), "window: the grade bar fills to the quality")

	check.call(RunningCosts.upkeep_of("office") == 0 and "Upkeep" not in body, "window: an office has no upkeep, so no upkeep line")

	# Rent change made in the window applies in the sim, to that room only.
	check.call(window.set_rent(Rent.LEVEL_HIGH), "rent: the window queues a SET_RENT")
	check.call(t.rent_level(a) == Rent.DEFAULT_LEVEL, "rent: nothing changes until the tick applies it")
	t.step()
	check.call(t.rent_level(a) == Rent.LEVEL_HIGH and t.rent_level(offices[1]) == Rent.DEFAULT_LEVEL, "rent: the change applies to that room only")
	window._refresh()
	check.call("Rent: $15000 a quarter (Highest)" in window.panel.body_text(), "rent: the window shows the new rent")
	check.call(window.rent_row.visible and (window.rent_row.get_child(Rent.LEVEL_HIGH) as Button).disabled and not (window.rent_row.get_child(0) as Button).disabled, "rent: buttons show, the current level is disabled")

	# All complaint reasons, worst first.
	for i in t.people.count():
		t.people.set_stress(i, 250)
	var reasons := t.complaint_reasons(a)
	check.call(reasons.size() >= 2, "complaints: high rent and high stress give two reasons")
	window._refresh()
	body = window.panel.body_text()
	var last := -1
	var in_order := true
	for r in reasons:
		var at := body.find(Complaints.label(r))
		in_order = in_order and at > last
		last = at
	check.call(in_order and last > -1, "complaints: every reason is listed, worst first")

	# Grade bar colours flip exactly at 200 and 150.
	check.call(RoomInfo.bar_color({"grade": Grades.grade_of_quality(201)}) == RoomInfo.GRADE_COLORS[0], "bar: 201 is the A colour")
	check.call(RoomInfo.bar_color({"grade": Grades.grade_of_quality(200)}) == RoomInfo.GRADE_COLORS[1], "bar: 200 is the B colour")
	check.call(RoomInfo.bar_color({"grade": Grades.grade_of_quality(150)}) == RoomInfo.GRADE_COLORS[1], "bar: 150 is still the B colour")
	check.call(RoomInfo.bar_color({"grade": Grades.grade_of_quality(149)}) == RoomInfo.GRADE_COLORS[2], "bar: 149 is the C colour")

	# A click on empty space closes it; a build tool keeps it shut.
	window.click_at(Vector2(spot.x, -5), 0.0)
	check.call(not window.is_open(), "window: a click on empty space closes it")
	ghost.set_tool("office")
	check.call(not window.hover_at(spot), "window: stays shut while a build tool is active")
	ghost.set_tool("")

	# A vacant office reads For Rent.
	var vacant := TestTenancy._tower()
	vacant.rooms.place_room(vacant.grid, vacant.floors, vacant.ledger, 0, Catalogue.IDS.find("office"), 3, 20)
	var empty_room := _of_kind(vacant, "office")[0]
	var w2 := RoomWindow.new()
	w2.bind(vacant, null)
	w2.show_room(empty_room, true)
	check.call(w2.is_open() and "For Rent: no occupants" in w2.panel.body_text(), "window: a vacant office reads For Rent with no occupants")
	w2.free()

	# Upkeep: only office and condo can be placed and neither has upkeep yet, so the line is
	# checked on the described data with an upkeep from a kind that has one.
	var plain := RoomInfo.describe(vacant, empty_room)
	check.call(plain["upkeep"] == RunningCosts.upkeep_of("office") and "Upkeep" not in "
".join(RoomInfo.lines_for(plain)), "window: a room with no upkeep has no upkeep line")
	var costly := plain.duplicate()
	costly["upkeep"] = RunningCosts.upkeep_of("security")
	check.call(costly["upkeep"] > 0 and "Upkeep: $%d a quarter" % costly["upkeep"] in "
".join(RoomInfo.lines_for(costly)), "window: a room with upkeep shows its quarterly upkeep")

	# A condo has a grade bar but no rent buttons (its rent is locked).
	var condo_tower := TestCondos._tower()
	var condos := _of_kind(condo_tower, "condo")
	check.call(condos.size() > 0, "fixture: the condo tower has a condo")
	var w3 := RoomWindow.new()
	w3.bind(condo_tower, null)
	w3.show_room(condos[0], true)
	check.call(w3.is_open() and not w3.rent_row.visible, "window: a condo has no rent buttons")
	check.call(w3.panel.title_text() == "Condo" and w3.bar.visible, "window: a condo shows its grade bar")
	w3.free()

	window.free()
	ghost.free()
