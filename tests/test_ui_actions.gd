extends RefCounted
## Clear mouse actions (#375) and the Medical Center / Wellness Clinic names (#384): right click
## cancels a tool but a right drag does not, a left click opens the room window only with no tool,
## the star panel lists the next star's requirements ticked or crossed from star_facts, a 5 second
## hover shows a tip that hides on a move, and the two service rooms read under their new names.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Ghost := preload("res://scripts/view/placement_ghost.gd")
const Toolbar := preload("res://scripts/view/toolbar.gd")
const RoomInfo := preload("res://scripts/view/room_info.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const StarRulesScript := preload("res://scripts/sim/star_rules.gd")
const VC := preload("res://scripts/view/view_consts.gd")
const TestRent := preload("res://tests/test_rent.gd")


static func run(check: Callable) -> void:
	# Right click cancels the tool; a drag (camera pan) does not.
	var ghost := Ghost.new()
	ghost.set_tool("office")
	ghost.right_press(Vector2(100, 100))
	check.call(ghost.right_release(Vector2(101, 100)) and ghost.tool == "", "right click: cancels the tool and returns to the pointer")
	ghost.set_tool("office")
	ghost.right_press(Vector2(100, 100))
	check.call(not ghost.right_release(Vector2(160, 100)) and ghost.tool == "office", "right drag: pans, leaves the tool alone")
	check.call(not ghost.right_release(Vector2(100, 100)) and ghost.tool == "office", "right release with no press does nothing")

	# Left click routing: details open with no tool, stay shut with one.
	var t := TestRent._two_offices()
	var room := -1
	for id in t.rooms.room_ids():
		if t.rooms.kind_of(id) == "office":
			room = id
			break
	check.call(room != -1, "fixture: the tower has an office")
	var run := t.grid.run_of(room)
	var spot := Vector2((run[1] + 0.5) * VC.CELL_W, (VC.floor_to_row(run[0]) + 0.5) * VC.CELL_H)
	var window := RoomWindow.new()
	var idle := Ghost.new()
	window.bind(t, idle)
	window.click_at(spot, 0.0)
	check.call(window.is_open() and window.pinned and window.room_id == room, "left click, no tool: opens the room details")
	var building := Ghost.new()
	building.set_tool("office")
	var window2 := RoomWindow.new()
	window2.bind(t, building)
	window2.click_at(spot, 0.0)
	check.call(not window2.is_open(), "left click with a tool: no details panel")

	# Star panel: the next star's fields, ticked or crossed.
	var s := TowerSim.new(5, 1000000000)
	var lines := StarWindow.lines_for(s)
	check.call(lines[0] == "Needed for star 2:" and StarWindow.star_lines(s).size() == 1 + StarRulesScript.REQUIREMENTS[2].size(), "star panel: star 2 lists its one field")
	check.call(lines[1].begins_with(StarWindow.MARK_NO) and "Population" in lines[1] and "/ 300" in lines[1], "star panel: population short is crossed, with the need")
	s.stars = 3
	lines = StarWindow.lines_for(s)
	check.call(StarWindow.star_lines(s).size() == 1 + StarRulesScript.REQUIREMENTS[4].size(), "star panel: star 4 lists every requirement field")
	var joined := "\n".join(lines)
	for word: String in ["Population", "Suites 0 / 2", "No open demands", "VIP"]:
		check.call(word in joined, "star panel: star 4 shows %s" % word)
	s.demands._open = (1 << (s.demands.SECURITY - 1)) | (1 << (s.demands.MEDICAL - 1))
	joined = "\n".join(StarWindow.lines_for(s))
	check.call("[X] Open demands: security, medical" in joined and "Security: build a security office" in joined and "Medical:" in joined, "star panel: open demands are named, crossed and explained")
	s.stars = 4
	joined = "\n".join(StarWindow.lines_for(s))
	check.call("Needed for star 5" in joined and "Metro stations 0 / 1" in joined, "star panel: star 5 lists population and metro")
	s.stars = 5
	check.call(StarWindow.star_lines(s).size() == 1 and StarWindow.lines_for(s)[0].begins_with("Top star"), "star panel: at the top rank there is nothing more to need")
	var before := s.state_hash()
	StarWindow.lines_for(s)
	check.call(s.state_hash() == before, "star panel: reading leaves the sim hash unchanged")

	# Hover tip: waits 5 seconds, hides on a move, says nothing during a tool.
	var tip := HoverTip.new()
	tip.bind(t, idle)
	tip.advance(0.0, Vector2(50, 50), spot, 0.0)  # first sight of the pointer
	check.call(not tip.advance(4.0, Vector2(50, 50), spot, 0.0), "hover: not shown before 5 seconds")
	check.call(tip.advance(1.5, Vector2(50, 50), spot, 0.0) and "Office" in tip.label.text, "hover: shown after 5 seconds with the room kind")
	check.call(not tip.advance(0.1, Vector2(90, 50), spot, 0.0) and not tip.is_showing(), "hover: hides when the pointer moves")
	var tip2 := HoverTip.new()
	tip2.bind(t, building)
	tip2.advance(0.0, Vector2(50, 50), spot, 0.0)
	check.call(not tip2.advance(6.0, Vector2(50, 50), spot, 0.0), "hover: nothing while a build tool is active")

	# Names and tooltips (#384).
	check.call(Toolbar.display_name("medical") == "Medical Center" and Toolbar.display_name("clinic") == "Wellness Clinic", "toolbar: new display names")
	var med_tip: String = Toolbar.item_state("medical", 5)["tooltip"]
	check.call("required" in med_tip and "4 stars" in med_tip, "toolbar: Medical Center tooltip says required, 4 stars")
	check.call("mood" in Toolbar.item_state("clinic", 5)["tooltip"], "toolbar: Wellness Clinic tooltip says mood")
	check.call(Catalogue.IDS.has("medical") and Catalogue.IDS.has("clinic"), "kind ids are unchanged")
	var m := TowerSim.new(5, 1000000000)
	m.floors.build_lobby(m.ledger, 0, 1, 100, 163, 2)
	m.floors.fill_span(3, 100, 163)
	m.rooms.place_room(m.grid, m.floors, m.ledger, 0, Catalogue.IDS.find("medical"), 3, 100)
	var medical := -1
	for id in m.rooms.room_ids():
		if m.rooms.kind_of(id) == "medical":
			medical = id
	check.call(medical != -1 and RoomInfo.describe(m, medical)["label"] == "Medical Center", "room info: the medical kind reads Medical Center")
	for node: Node in [window, window2, tip, tip2, ghost, idle, building]:
		node.free()
