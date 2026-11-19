extends RefCounted
## Activities in rooms (10.6): the classification of what a resting person does, poses that stay inside
## their room on every recipe spot, the same sim moment drawing the same, and the sleepers' lights.

const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const TestCondos := preload("res://tests/test_condos.gd")
const TestOfficeDay := preload("res://tests/test_office_day.gd")
const TestTenancy := preload("res://tests/test_tenancy.gd")
const People := preload("res://scripts/sim/people.gd")
const PeopleView := preload("res://scripts/view/people_view.gd")
const ActivityLook := preload("res://scripts/view/activity_look.gd")
const RoomRecipes := preload("res://scripts/view/room_recipes.gd")
const VC := preload("res://scripts/view/view_consts.gd")


## Records the draw calls a painter makes, so two draws can be compared.
class Recorder:
	extends RefCounted
	var calls: Array = []

	func draw_rect(r: Rect2i, c: Color) -> void:
		calls.append([r, c])


static func run(check: Callable) -> void:
	var A := ActivityLook
	check.call(A.classify("hotel_single", false, People.DEST_HOME, true, 23 * 60, false) == A.SLEEPING, "activity: a guest sleeps at night")
	check.call(A.classify("hotel_single", false, People.DEST_HOME, true, 12 * 60, false) == A.IDLE, "activity: a guest by day is idle")
	check.call(A.classify("condo", false, People.DEST_HOME, false, 2 * 60, false) == A.SLEEPING, "activity: a resident sleeps at night")
	check.call(A.classify("office", true, People.DEST_WORK, false, 10 * 60, false) == A.WORKING, "activity: working at the desk")
	check.call(A.classify("office", true, People.DEST_BREAK, false, 630, false) == A.BREAK, "activity: break")
	check.call(A.classify("office", true, People.DEST_LUNCH, false, 12 * 60, false) == A.LUNCH, "activity: lunch")
	check.call(A.classify("restaurant", false, People.DEST_HOME, false, 12 * 60, false) == A.EATING, "activity: a visitor eats in a food room")
	check.call(A.classify("retail", false, People.DEST_HOME, false, 12 * 60, false) == A.SHOPPING, "activity: a visitor shops")
	check.call(A.classify("housekeeping", true, People.DEST_WORK, false, 10 * 60, false) == A.CLEANING, "activity: housekeeping staff clean")
	check.call(A.classify("office", true, People.DEST_WORK, false, 10 * 60, true) == A.QUEUEING, "activity: waiting to set off is queueing")

	# Every pose on every spot of every kind (and several widths) lies inside the room, and a draw
	# stays inside the box the pose reports.
	var bad: Array[String] = []
	var drew_all := true
	for kind: String in CatalogueScript.IDS:
		if not RoomRecipes.has(kind):
			continue
		var widths: Array[int] = [int(CatalogueScript.field(kind, "width")) * VC.CELL_W, 40 * VC.CELL_W]
		for width_px: int in widths:
			var room := Rect2i(0, 0, width_px, RoomRecipes.INTERIOR_H)
			for act: int in A.COUNT:
				if act == A.SLEEPING and not (kind.begins_with("hotel_") or kind == "condo"):
					continue  # only beds sleep
				for turn in 5:
					var spot := A.spot_for(kind, width_px, turn * 7, turn, act)
					var at := A.place(act, spot, width_px)
					var box := A.body_rect(act, at.x, at.y)
					if not room.encloses(box):
						bad.append("%s %s %s" % [kind, A.NAMES[act], str(box)])
					var rec := Recorder.new()
					A.draw(rec, at.x, at.y, act, turn, Color.RED, Color.WHITE, Color.GOLD, Color.WHITE)
					drew_all = drew_all and not rec.calls.is_empty()
					for call: Array in rec.calls:
						if not box.encloses(call[0]):
							bad.append("%s %s draws outside its box %s" % [kind, A.NAMES[act], str(call[0])])
	check.call(bad.is_empty(), "activity: poses stay inside the room (%s)" % str(bad.slice(0, 3)))
	check.call(drew_all, "activity: every activity draws something")

	# The same moment draws the same.
	var rec_a := Recorder.new()
	var rec_b := Recorder.new()
	A.draw(rec_a, 5, 30, A.WORKING, A.frame(3, 1000), Color.RED, Color.WHITE, Color.GOLD, Color.WHITE)
	A.draw(rec_b, 5, 30, A.WORKING, A.frame(3, 1000), Color.RED, Color.WHITE, Color.GOLD, Color.WHITE)
	check.call(rec_a.calls == rec_b.calls, "activity: the same moment draws the same")
	var frames: Dictionary = {}
	for tick in 64:
		frames[A.frame(3, tick)] = true
	check.call(frames.size() == 4, "activity: idle motion cycles through its frames over time")

	# In a tower: workers sit on distinct office spots inside the room, the sleeper lies in the condo.
	var office_tower := TestOfficeDay._filled()
	TestOfficeDay._at(office_tower, 10 * 60 + 5)
	var view := PeopleView.new()
	var first := view.figures(office_tower)
	var second := view.figures(office_tower)
	check.call(first == second, "activity: the same sim moment gives the same figures")
	var resting := 0
	var inside := true
	var spots_used: Dictionary = {}
	var hash_before := office_tower.state_hash()
	for f: Dictionary in first:
		if f["moving"]:
			continue
		resting += 1
		var run: Array[int] = office_tower.grid.run_of(office_tower.grid.cell_at(f["floor"], f["x"]))
		var rect := Rect2i(0, 0, run[2] * VC.CELL_W, RoomRecipes.INTERIOR_H)
		var local := ActivityLook.body_rect(f["act"], (f["px"] as int) - run[1] * VC.CELL_W, (f["pfeet"] as int) - VC.floor_to_row(run[0]) * VC.CELL_H)
		inside = inside and rect.encloses(local)
		inside = inside and f["act"] == A.WORKING
		spots_used[Vector2i(f["px"], f["pfeet"])] = true
	check.call(resting > 0 and inside, "activity: office workers sit working inside their room (%d resting)" % resting)
	var office_spots := RoomRecipes.spots("office", int(CatalogueScript.field("office", "width")) * VC.CELL_W).size()
	check.call(spots_used.size() == mini(resting, office_spots), "activity: workers fill the office spots before sharing (%d spots, %d workers)" % [office_spots, resting])
	check.call(office_tower.state_hash() == hash_before, "activity: reading figures leaves the sim unchanged")

	var condo := TestCondos._tower()
	TestTenancy._link(condo)
	TestCondos._at(condo, 10 * 60, 0)
	TestCondos._at(condo, 23 * 60, 0)
	var sleepers := 0
	for f: Dictionary in view.figures(condo):
		if not f["moving"] and f["act"] == A.SLEEPING:
			sleepers += 1
	check.call(sleepers == 3, "activity: residents at home at night are asleep (%d)" % sleepers)
