extends RefCounted
## The link layer (#126, #125): stairs, escalators and shafts sit in front of rooms and coexist
## with them. Placement over everything, the refusals that stay, routes, bulldoze and replace
## rules, escalator placement and its tool, save and load, and draw order.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const RoutesScript := preload("res://scripts/sim/routes.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const Messages := preload("res://scripts/sim/messages.gd")
const TestRooms := preload("res://tests/test_rooms.gd")
const TestElevatorRoutes := preload("res://tests/test_elevator_routes.gd")
const Ghost := preload("res://scripts/view/placement_ghost.gd")
const Toolbar := preload("res://scripts/view/toolbar.gd")
const Renderer := preload("res://scripts/view/tower_renderer.gd")

const OFFICE := 5
const CONDO := 6


static func _stairs(t: TowerSim, floor_number: int, x: int) -> int:
	return TestRooms._send(t, Command.PLACE_STAIRS, [floor_number, x] as Array[int])


static func _escalator(t: TowerSim, floor_number: int, x: int) -> int:
	return TestRooms._send(t, Command.PLACE_ESCALATOR, [floor_number, x] as Array[int])


static func _shaft(t: TowerSim, bottom: int, top: int, x: int) -> int:
	return TestRooms._send(t, Command.PLACE_SHAFT, [CatalogueScript.IDS.find("local_shaft"), bottom, top, x] as Array[int])


static func _kinds(route: Dictionary) -> Array[int]:
	return TestElevatorRoutes._kinds(route)


static func run(check: Callable) -> void:
	# Stairs over a lobby, empty floor, office and condo: each is allowed, the room stays.
	var t := TestElevatorRoutes._plain(6)
	check.call(TestRooms._room(t, OFFICE, 3, 100) == RoomsScript.OK and TestRooms._room(t, CONDO, 4, 100) == RoomsScript.OK, "fixture: an office on floor 3 and a condo on floor 4")
	var office: int = t.grid.cell_at(3, 100)
	var condo: int = t.grid.cell_at(4, 100)
	check.call(_stairs(t, 1, 100) == RoomsScript.OK, "stairs over the ground lobby and the floor above are allowed")
	check.call(_stairs(t, 5, 100) == RoomsScript.OK, "stairs over empty built floor are allowed")
	check.call(_stairs(t, 3, 102) == RoomsScript.OK, "stairs over an office and a condo are allowed")
	check.call(t.rooms.kind_of(t.rooms.link_at(3, 102)) == "stairs" and t.rooms.is_stairs_upper(t.rooms.link_at(4, 103)), "the stairs fill both halves in the link layer")
	check.call(t.grid.cell_at(3, 102) == office and t.grid.cell_at(4, 103) == condo and t.rooms.kind_of(office) == "office" and t.rooms.kind_of(condo) == "condo", "the rooms behind keep their cells and kinds")
	check.call(t.rooms.people_in(office) == 6 and t.rooms.people_in(condo) == 3, "a room behind stairs keeps its capacity")
	check.call(_escalator(t, 3, 106) == RoomsScript.OK, "an escalator over an office and a condo is allowed")
	check.call(_shaft(t, 1, 6, 120) == RoomsScript.OK and _shaft(t, 3, 4, 108) == RoomsScript.OVERLAPS_LINK, "a shaft may stand beside links but not on the escalator")

	# Routes: stairs through the lobby, across an office floor, with the office behind them.
	var r := TestElevatorRoutes._plain(5)
	TestRooms._room(r, OFFICE, 3, 104)
	_stairs(r, 1, 100)
	_stairs(r, 2, 104)
	var route := RoutesScript.find(r.floors, r.rooms, r.grid, 1, 101, 3, 106)
	check.call(route["reason"] == RoutesScript.OK and _kinds(route).count(RoutesScript.STAIRS) == 2, "a route climbs stairs placed over the lobby and reaches a room the stairs stand over")
	var link_run: Array[int] = r.rooms.run_of(r.grid, r.rooms.link_at(2, 104))
	var room_run: Array[int] = r.rooms.run_of(r.grid, r.grid.cell_at(3, 106))
	check.call(link_run == ([2, 104, 4] as Array[int]) and room_run == ([3, 104, 9] as Array[int]), "run_of finds links and rooms")

	# An office behind stairs keeps working: workers move in.
	var w := TestElevatorRoutes._plain(4)
	TestRooms._room(w, OFFICE, 3, 104)
	_stairs(w, 1, 100)
	_stairs(w, 2, 104)
	var worker_office: int = w.grid.cell_at(3, 104)
	var moved := false
	for _n in 4000:
		w.step()
		if w.people.workers_in(worker_office) > 0:
			moved = true
			break
	check.call(moved, "an office with stairs standing over it still takes workers")

	# A shaft through the lobby, an office floor and empty floors, then a ride.
	var s := TestElevatorRoutes._plain(6)
	TestRooms._room(s, OFFICE, 3, 100)
	check.call(_shaft(s, 1, 6, 104) == RoomsScript.OK, "a shaft through the lobby, an office floor and empty floors is allowed")
	var shaft: int = s.rooms._shaft_base(s.rooms.link_at(3, 104))
	check.call(shaft != 0 and s.rooms.kind_of(s.grid.cell_at(3, 104)) == "office", "the office stays behind the shaft")
	check.call(s.rooms.add_car(s.ledger, 0, 3, shaft, 1) == RoomsScript.OK, "a car goes in a shaft that stands over a room")
	route = RoutesScript.find(s.floors, s.rooms, s.grid, 1, 110, 6, 110)
	check.call(route["reason"] == RoutesScript.OK and _kinds(route).has(RoutesScript.ELEVATOR), "a route rides a shaft that stands over a room")

	# Refusals that stay: link over link, no built floor, the limit.
	var f := TestElevatorRoutes._plain(6)
	_shaft(f, 1, 6, 104)
	check.call(_stairs(f, 3, 102) == RoomsScript.OVER_SHAFT, "stairs over a shaft are refused")
	check.call(_escalator(f, 3, 100) == RoomsScript.OVER_SHAFT, "an escalator over a shaft is refused")
	_stairs(f, 3, 120)
	check.call(_shaft(f, 1, 6, 118) == RoomsScript.OVERLAPS_LINK, "a shaft over stairs is refused")
	check.call(_stairs(f, 3, 122) == RoomsScript.OVERLAPS_LINK, "stairs over stairs are refused")
	_escalator(f, 3, 108)
	check.call(_stairs(f, 4, 110) == RoomsScript.OVERLAPS_LINK, "stairs over an escalator's upper half are refused")
	check.call(_escalator(f, 3, 112) == RoomsScript.OVERLAPS_LINK, "an escalator over an escalator is refused")
	check.call(_stairs(f, 6, 100) == RoomsScript.NO_FLOOR_FOR_STAIRS and _shaft(f, 5, 7, 112) == RoomsScript.NO_FLOOR_FOR_SHAFT, "stairs and shafts need built floor on every level")
	check.call(_stairs(f, 3, 129) == RoomsScript.NO_FLOOR_FOR_STAIRS, "stairs may not hang past the floor")
	var before := f.ledger.balance
	_stairs(f, 3, 102)
	check.call(f.ledger.balance == before, "a refused link is free")

	var big := TowerSim.new(1, 100000000)
	TestRooms._send(big, Command.BUILD_LOBBY, [1, 0, 399, 3] as Array[int])
	for i in 62:
		_stairs(big, 1, i * 4)
	_stairs(big, 2, 248)
	_stairs(big, 2, 252)
	check.call(big.rooms.room_count() == 64, "fixture: 64 stairs fill the limit")
	check.call(_escalator(big, 2, 256) == RoomsScript.STAIRS_LIMIT and _stairs(big, 2, 264) == RoomsScript.STAIRS_LIMIT, "the 64 limit is shared with escalators")

	# Bulldoze: the link wins the click; the room behind is the next click.
	var b := TestElevatorRoutes._plain(6)
	TestRooms._room(b, OFFICE, 3, 100)
	_stairs(b, 3, 102)
	var hit := b.rooms.check_bulldoze(b.grid, b.floors, 3, 103)
	check.call(hit["reason"] == RoomsScript.OK and b.rooms.kind_of(hit["room_id"]) == "stairs", "bulldoze picks the stairs over the office behind")
	check.call(b.rooms.check_bulldoze(b.grid, b.floors, 4, 103)["room_id"] == hit["room_id"], "the stairs' upper half picks the same stairs")
	check.call(TestRooms._send(b, Command.BULLDOZE, [3, 103] as Array[int]) == RoomsScript.OK and b.rooms.link_at(3, 103) == 0 and b.rooms.link_at(4, 103) == 0, "the first bulldoze removes the stairs")
	check.call(b.rooms.room_count() == 1 and b.rooms.kind_of(b.grid.cell_at(3, 103)) == "office", "the office behind is untouched")
	check.call(TestRooms._send(b, Command.BULLDOZE, [3, 103] as Array[int]) == RoomsScript.OK and b.rooms.room_count() == 0, "the second bulldoze removes the office")
	var lobby := TestElevatorRoutes._plain(3)
	_stairs(lobby, 1, 100)
	check.call(TestRooms._send(lobby, Command.BULLDOZE, [1, 102] as Array[int]) == RoomsScript.OK and TestRooms._send(lobby, Command.BULLDOZE, [1, 102] as Array[int]) == RoomsScript.PERMANENT, "stairs over the lobby go, then the lobby is permanent")
	var sh := TestElevatorRoutes._plain(6)
	TestRooms._room(sh, OFFICE, 3, 100)
	_shaft(sh, 1, 6, 104)
	check.call(TestRooms._send(sh, Command.BULLDOZE, [3, 105] as Array[int]) == RoomsScript.OK and sh.rooms.shaft_count() == 0 and sh.rooms.room_count() == 1, "bulldozing a shaft over an office leaves the office")

	# Replace: swaps the room behind a link; a link with no room behind is replaced itself.
	var p := TestElevatorRoutes._plain(6)
	TestRooms._room(p, OFFICE, 3, 100)
	_stairs(p, 3, 102)
	check.call(TestRooms._send(p, Command.REPLACE_ROOM, [CONDO, 3, 100] as Array[int]) == RoomsScript.OK, "replace swaps an office with stairs standing over it")
	check.call(p.rooms.kind_of(p.grid.cell_at(3, 100)) == "condo" and p.rooms.kind_of(p.rooms.link_at(3, 102)) == "stairs", "the new room stands behind the stairs, which stay")
	_stairs(p, 5, 100)
	check.call(TestRooms._send(p, Command.REPLACE_ROOM, [OFFICE, 5, 100] as Array[int]) == RoomsScript.OK and p.rooms.link_at(5, 100) == 0 and p.rooms.kind_of(p.grid.cell_at(5, 100)) == "office", "replace on bare stairs removes them and builds the room")

	# Save and load: links survive, hash matches, bulldoze works after loading.
	var v := TestElevatorRoutes._plain(6)
	TestRooms._room(v, OFFICE, 3, 100)
	_stairs(v, 3, 102)
	_escalator(v, 3, 106)
	_shaft(v, 1, 6, 120)
	var u := TowerSim.new(0)
	var data := v.save()
	check.call(u.load_state(data) and u.state_hash() == v.state_hash(), "a tower with links over rooms saves and loads exactly")
	check.call(u.rooms.kind_of(u.rooms.link_at(3, 107)) == "escalator" and u.rooms.is_stairs_upper(u.rooms.link_at(4, 107)) and u.rooms.shaft_count() == 1 and u.rooms.link_at(6, 121) != 0, "loaded links keep their cells")
	check.call(TestRooms._send(u, Command.BULLDOZE, [3, 108] as Array[int]) == RoomsScript.OK and u.rooms.link_at(3, 108) == 0 and u.rooms.kind_of(u.grid.cell_at(3, 104)) == "office", "a loaded escalator can be bulldozed")
	var ints: Array = (data["rooms"] as Array).duplicate()
	check.call(RoomsScript.valid_ints(ints, v.grid), "fixture: the rooms save is valid against its grid")
	ints.pop_back()
	check.call(not RoomsScript.valid_ints(ints, null), "a rooms save with a damaged link block is rejected")
	var bad := data.duplicate()
	bad["rooms"] = ints
	check.call(not TowerSim.new(0).load_state(bad), "a tower save with damaged links is rejected")

	# Escalator placement (#125).
	var e := TestElevatorRoutes._plain(6)
	var funds := e.ledger.balance
	check.call(_escalator(e, 3, 100) == RoomsScript.OK and funds - e.ledger.balance == 20000, "an escalator is placed for $20,000")
	check.call(e.rooms.kind_of(e.rooms.link_at(3, 107)) == "escalator" and e.rooms.is_stairs_upper(e.rooms.link_at(4, 100)) and e.rooms.link_at(3, 108) == 0, "an escalator is 8 wide on two floors")
	var last := e.messages.entry(e.messages.count() - 1)
	check.call(last[1] == Messages.ESCALATOR_BUILT and last[2] == 3, "building an escalator is logged")
	funds = e.ledger.balance
	check.call(_escalator(e, 6, 100) == RoomsScript.NO_FLOOR_FOR_ESCALATOR, "an escalator needs floor on both levels")
	check.call(_escalator(e, 3, 125) == RoomsScript.NO_FLOOR_FOR_ESCALATOR, "an escalator may not hang past the floor")
	check.call(_escalator(e, 3, 396) == RoomsScript.OFF_TOWER and _escalator(e, 0, 100) == RoomsScript.BAD_FLOOR, "an escalator off the tower or on floor 0 is refused")
	check.call(e.ledger.balance == funds, "escalator refusals are free")
	var poor := TestElevatorRoutes._plain(4)
	poor.ledger.charge(poor.tick, poor.ledger.balance - 19999, 0)
	check.call(_escalator(poor, 3, 100) == RoomsScript.SHORT_OF_FUNDS and poor.rooms.room_count() == 0, "an escalator is refused when short of funds")
	route = RoutesScript.find(e.floors, e.rooms, e.grid, 3, 104, 4, 104)
	check.call(route["reason"] == RoutesScript.OK and _kinds(route).has(RoutesScript.ESCALATOR) and not _kinds(route).has(RoutesScript.STAIRS), "a route uses a placed escalator")
	check.call(TestRooms._send(e, Command.BULLDOZE, [4, 103] as Array[int]) == RoomsScript.OK and e.rooms.room_count() == 0, "an escalator is bulldozed from its upper half")

	# The tool: star-locked, buildable, drawn in a distinct colour, one command.
	check.call(Toolbar.item_state("escalator", 2)["locked"] and not Toolbar.item_state("escalator", 2)["enabled"], "the escalator tool is locked below star 3")
	check.call(Toolbar.item_state("escalator", 3)["enabled"] and Ghost.is_buildable("escalator"), "the escalator tool is buildable at star 3")
	var g := TestElevatorRoutes._plain(6)
	var low := Ghost.evaluate(g, "escalator", 3, 100, 2)
	check.call(not low["valid"] and low["text"] == "Needs 3 stars", "the ghost refuses an escalator below star 3")
	var ok := Ghost.evaluate(g, "escalator", 3, 100, 3)
	check.call(ok["valid"] and ok["cost"] == 20000 and ok["width"] == 8 and ok["height"] == 2, "the ghost shows an 8 by 2 escalator at its price")
	var command := Ghost.command_for("escalator", ok, g.tick)
	check.call(command != null and command.kind == Command.PLACE_ESCALATOR and command.args == ([3, 100] as Array[int]), "a click sends PLACE_ESCALATOR")
	check.call(Renderer.KIND_COLORS["escalator"] != Renderer.KIND_COLORS["stairs"], "escalators are drawn in a different colour from stairs")

	# Draw order: rooms, then links, then shafts, then people in front.
	var order: Array[String] = Renderer.DRAW_ORDER
	check.call(order.find("_draw_rooms") < order.find("_draw_links") and order.find("_draw_links") < order.find("_draw_shafts") and order.find("_draw_shafts") < order.find("_draw_people"), "links and shafts are drawn in front of rooms, people in front of both")
	var renderer := Renderer.new()
	var all_drawn := true
	for layer: String in order:
		all_drawn = all_drawn and renderer.has_method(layer)
	renderer.free()
	check.call(all_drawn, "every draw layer names a method of the renderer")
