extends RefCounted
## Placement ghost tests (2.5): each refusal reason has its own wording, costs include the floor
## bought under a room, and every non-removable catalogue row shows the permanent warning.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const Ghost := preload("res://scripts/view/placement_ghost.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const FloorsScript := preload("res://scripts/sim/floors.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const TestRooms := preload("res://tests/test_rooms.gd")
const FALLBACK := "Cannot build here"


## A tower with a ground lobby at columns 100 to 131.
static func _wide() -> TowerSim:
	var tower := TowerSim.new(1, 2000000)
	TestRooms._send(tower, Command.BUILD_LOBBY, [1, 100, 131, 1] as Array[int])
	return tower


static func _kind(id: String) -> int:
	return CatalogueScript.IDS.find(id)


static func _text(t: TowerSim, tool_id: String, floor_number: int, x: int, stars: int = 5) -> String:
	return Ghost.evaluate(t, tool_id, floor_number, x, stars)["text"]


static func run(check: Callable) -> void:
	var t := _wide()
	check.call(t.floors.has_lobby(), "fixture: the lobby is built")
	# Valid: cost includes the floor bought under the room (9 units at 500 on top of 40000).
	var ok := Ghost.evaluate(t, "office", 2, 100, 1)
	check.call(ok["valid"] and ok["text"] == "", "an office on the lobby is a valid ghost")
	check.call(ok["cost"] == 40000 + 9 * 500, "the ghost cost includes the floor under the room")
	check.call(Ghost.lines_for("office", ok)[0] == "office: $44500", "the label shows the total cost")
	check.call(ok["width"] == 9 and ok["x"] == 100, "the ghost footprint is the catalogue width at the snapped column")

	# One refusal reason each, worded by us.
	check.call(_text(t, "office", 2, 125) == "Too wide for the floor below", "an overhanging room reads as too wide")
	check.call(not Ghost.evaluate(t, "office", 2, 125, 1)["valid"], "an overhanging office is invalid")
	check.call(_text(t, "floor", 2, 125) == "Too wide for the floor below", "a wide floor span reads as too wide")
	check.call(_text(t, "office", -1, 100) == "Above ground only", "below ground reads as above ground only")
	check.call(_text(t, "service_shaft", 2, 100, 1) == "Needs 2 stars", "a locked room reads as star locked")
	check.call(not Ghost.evaluate(t, "service_shaft", 2, 100, 1)["valid"], "a star-locked ghost is invalid")
	check.call(Ghost.reason_text("rooms", RoomsScript.OFF_TOWER) == "Runs off the tower's edge", "off the tower reads as off the edge")
	check.call(_text(t, "office", 1, 100) == "Floor 1 is for the lobby", "an office on floor 1 reads as the lobby floor")
	check.call(_text(t, "office", 2, 20) == "Nothing below to rest on", "no floor below reads as nothing below")
	check.call(_text(t, "lobby", 1, 100) == "The lobby is already built", "a second lobby reads as already built")

	# Overlap, shaft, money.
	TestRooms._room(t, _kind("office"), 2, 100)
	check.call(_text(t, "office", 2, 100) == "Overlaps another room", "a room over a room reads as overlap")
	check.call(_text(t, "office", 2, 104) == "Overlaps another room", "a partial overlap reads as overlap")
	check.call(t.floors.mark_shaft(3, 105), "fixture: a shaft cell is marked on floor 3")
	check.call(_text(t, "floor", 3, 100) == "Over a shaft", "a floor span over a shaft reads as over a shaft")
	var poor := _wide()
	TestRooms._send(poor, Command.PURCHASE, [poor.ledger.balance - 1000, 1] as Array[int])
	var broke := Ghost.evaluate(poor, "office", 2, 100, 1)
	check.call(not broke["valid"] and broke["text"] == "Not enough money", "an unaffordable build reads as not enough money")

	# Every table entry has its own wording, never the generic fallback.
	for code: int in Ghost.ROOM_TEXT:
		check.call(Ghost.reason_text("rooms", code) != FALLBACK, "room code %d has its own wording" % code)
	for code: int in Ghost.FLOOR_TEXT:
		check.call(Ghost.reason_text("floors", code) != FALLBACK, "floor code %d has its own wording" % code)
	for code: int in Ghost.BULLDOZE_TEXT:
		check.call(Ghost.reason_text("bulldoze", code) != FALLBACK, "bulldoze code %d has its own wording" % code)
	check.call(Ghost.reason_text("rooms", 9999) == FALLBACK, "an unknown code falls back to the generic wording")

	# Bulldoze: names what goes, or why it cannot.
	var dozer := Ghost.evaluate(t, Ghost.BULLDOZE, 2, 104, 1)
	check.call(dozer["valid"] and dozer["x"] == 100 and dozer["width"] == 9, "bulldoze highlights the whole room")
	check.call("office" in dozer["text"], "bulldoze names the room it would remove")
	var lobby_hit := Ghost.evaluate(t, Ghost.BULLDOZE, 1, 104, 1)
	check.call(not lobby_hit["valid"] and lobby_hit["text"] == Ghost.reason_text("bulldoze", RoomsScript.PERMANENT), "bulldoze refuses the lobby with a reason")
	check.call(Ghost.evaluate(t, Ghost.BULLDOZE, 5, 5, 1)["text"] == "Nothing to remove here", "bulldoze on empty ground says nothing there")

	# The permanent warning shows for exactly the catalogue rows that are not removable.
	var permanent_rows := 0
	for id: String in CatalogueScript.IDS:
		var lines := Ghost.lines_for(id, Ghost.evaluate(t, id, 2, 100, 5))
		var removable: bool = CatalogueScript.field(id, "removable")
		check.call((Ghost.PERMANENT_TEXT in lines) == (not removable), "%s: permanent warning matches removable" % id)
		if not removable:
			permanent_rows += 1
	check.call(permanent_rows >= 6, "the catalogue has at least the six permanent rows (the loop covers any more)")
