extends RefCounted
## Toolbar tests (2.10): items come from the catalogue, star-locked items are greyed with their
## unlock star, unbuildable ones are greyed with a tooltip, and every M2 item picks its ghost tool.

const Toolbar := preload("res://scripts/view/toolbar.gd")
const Ghost := preload("res://scripts/view/placement_ghost.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const TowerSim := preload("res://scripts/sim/tower.gd")
const TestGhost := preload("res://tests/test_ghost.gd")
const TestRooms := preload("res://tests/test_rooms.gd")
const Command := TowerSim.Command

const M2_ITEMS: Array[String] = ["lobby", "floor", "stairs", "office", "condo", Ghost.BULLDOZE, Ghost.REPLACE]


static func _ids() -> Array[String]:
	var ids: Array[String] = []
	for entry: Array in Toolbar.CATEGORIES:
		for id: String in entry[1]:
			ids.append(id)
	return ids


static func run(check: Callable) -> void:
	# Every catalogue row is in exactly one category, so nothing is hidden.
	var ids := _ids()
	for id: String in CatalogueScript.IDS:
		check.call(ids.count(id) == 1, "%s sits in exactly one toolbar category" % id)
	check.call(ids.size() == CatalogueScript.IDS.size() + 2, "the toolbar holds the catalogue plus bulldoze and replace")

	# At 1 star only star-1 items are enabled; every locked item names its unlock star.
	var ghost := Ghost.new()
	var bar := Toolbar.new()
	bar.bind(ghost)
	check.call(ghost.stars == 1, "fixture: the ghost starts at 1 star")
	for id in ids:
		var state := Toolbar.item_state(id, 1)
		if state["enabled"]:
			check.call(Toolbar.star_of(id) == 1, "%s is enabled at 1 star only if it is a star 1 item" % id)
		if CatalogueScript.has(id) and CatalogueScript.star(id) > 1:
			check.call(not state["enabled"] and state["locked"], "%s is locked at 1 star" % id)
			check.call(("Star %d" % CatalogueScript.star(id)) in state["text"], "%s shows its unlock star" % id)
			check.call(str(CatalogueScript.star(id)) in state["tooltip"], "%s tooltip names its unlock star" % id)
	check.call(not Toolbar.item_state("service_shaft", 1)["enabled"], "a star 2 item is greyed at 1 star")
	check.call(not Toolbar.item_state("hotel_single", 1)["enabled"], "a star 2 room is greyed at 1 star")
	# Star 1 items the sim cannot build yet show, cannot be picked, and say why.
	for id in ["local_shaft", "fast_food"]:
		var pending := Toolbar.item_state(id, 1)
		check.call(not pending["enabled"] and not pending["locked"], "%s is greyed but not star-locked" % id)
		check.call("Not buildable" in pending["tooltip"], "%s tooltip says it is not buildable yet" % id)
		check.call(not bar.select(id) and ghost.tool == "", "%s cannot be selected" % id)
	check.call(not bar.select("service_shaft") and ghost.tool == "", "a locked item cannot be selected")
	check.call(Toolbar.item_state("hotel_single", 5)["tooltip"] != "", "an unlocked but unbuilt item still explains itself")

	# Every M2 item can be picked and activates the matching ghost tool.
	for id in M2_ITEMS:
		check.call(Toolbar.item_state(id, 1)["enabled"], "%s is enabled at 1 star" % id)
		check.call(bar.select(id) and ghost.tool == id, "%s selects the matching ghost tool" % id)
		check.call(bar.select(id) and ghost.tool == "", "picking %s again turns the tool off" % id)
	bar.select("condo")
	check.call(ghost.last_room == "condo", "choosing a room tool sets the room replace builds")
	ghost.tower = TowerSim.new(0)
	ghost.tower.stars = 2
	check.call(ghost.stars == 2, "the ghost reads the sim's star rating")
	check.call(Toolbar.item_state("service_shaft", 2)["locked"] == false, "a star 2 item unlocks at 2 stars")

	# The ghost's click sends the matching command for each M2 tool.
	var t := TestGhost._wide()
	TestRooms._room(t, CatalogueScript.IDS.find("office"), 2, 100)
	var cases := [
		["office", 3, 100, Command.PLACE_ROOM], ["floor", 2, 120, Command.BUILD_FLOOR],
		[Ghost.BULLDOZE, 2, 104, Command.BULLDOZE], [Ghost.REPLACE, 2, 104, Command.REPLACE_ROOM],
	]
	for entry: Array in cases:
		var verdict := Ghost.evaluate(t, entry[0], entry[1], entry[2], 1, "condo")
		var command := Ghost.command_for(entry[0], verdict, t.tick, "condo")
		check.call(command != null and command.kind == entry[3] and command.tick == t.tick + 1, "%s click queues its command" % entry[0])
	TestRooms._send(t, Command.BUILD_FLOOR, [2, 110, 119] as Array[int])
	var stairs := Ghost.evaluate(t, "stairs", 1, 112, 1)
	check.call(stairs["valid"] and stairs["height"] == 2, "stairs preview comes from check_place_stairs and spans two floors")
	check.call(Ghost.command_for("stairs", stairs, t.tick).kind == Command.PLACE_STAIRS, "stairs click queues PLACE_STAIRS")
	var replace := Ghost.evaluate(t, Ghost.REPLACE, 2, 104, 1, "condo")
	check.call(replace["valid"] and replace["x"] == 100, "replace previews from the room's left edge")
	check.call(Ghost.command_for("office", Ghost.evaluate(t, "office", 2, 100, 1), t.tick) == null, "an invalid verdict queues nothing")
	ghost.free()
	bar.free()
