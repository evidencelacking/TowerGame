extends RefCounted
## Building behind transport (#272): a room, floor or lobby may stand behind a shaft (and its machine
## rooms), stairs or an escalator, in either order. Bulldoze takes the front item first.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const TestRooms := preload("res://tests/test_rooms.gd")
const TestShafts := preload("res://tests/test_shafts.gd")
const TestLinks := preload("res://tests/test_links.gd")


static func _room(t: TowerSim, kind: String, floor_number: int, x: int) -> int:
	return TestRooms._room(t, CatalogueScript.IDS.find(kind), floor_number, x)


static func _bulldoze(t: TowerSim, floor_number: int, x: int) -> int:
	return TestRooms._send(t, Command.BULLDOZE, [floor_number, x] as Array[int])


static func run(check: Callable) -> void:
	# Shaft first, then the room behind it, on a stop floor and on a machine room floor.
	var t := TestShafts._tall()
	check.call(TestLinks._shaft(t, 5, 8, 100) == RoomsScript.OK, "fixture: a shaft from 5 to 8")
	check.call(_room(t, "office", 6, 100) == RoomsScript.OK, "a room goes behind a shaft stop")
	check.call(_room(t, "office", 9, 100) == RoomsScript.OK, "a room goes behind the machine room above")
	var shaft_id: int = t.rooms.shaft_ids()[0]
	check.call(t.rooms.stops_of(shaft_id).has(6), "the shaft still stops at the room's floor")
	check.call(t.rooms.link_at(6, 100) != 0 and t.grid.cell_at(6, 100) != 0, "the shaft and the room share the cell")
	# Bulldoze: the shaft first, then the room.
	var rooms := t.rooms.room_count()
	check.call(_bulldoze(t, 6, 100) == RoomsScript.OK and t.rooms.shaft_count() == 0 and t.rooms.room_count() == rooms - 1, "the first bulldoze takes the shaft")
	check.call(t.grid.cell_at(6, 100) != 0, "the room behind the shaft is still there")
	check.call(_bulldoze(t, 6, 100) == RoomsScript.OK and t.grid.cell_at(6, 100) == 0, "the second bulldoze takes the room")

	# Room first, then the shaft over it.
	var r := TestShafts._tall()
	check.call(_room(r, "office", 6, 100) == RoomsScript.OK and _room(r, "office", 9, 100) == RoomsScript.OK, "fixture: rooms on a stop floor and a machine floor")
	check.call(TestLinks._shaft(r, 5, 8, 100) == RoomsScript.OK, "a shaft goes in front of existing rooms")
	check.call(TestLinks._shaft(r, 6, 7, 102) == RoomsScript.OVER_SHAFT, "a shaft still refuses another shaft")
	check.call(TestLinks._stairs(r, 6, 100) == RoomsScript.OVER_SHAFT, "stairs still refuse a shaft")

	# Stairs and escalator, both orders.
	var s := TestShafts._tall()
	check.call(TestLinks._stairs(s, 6, 100) == RoomsScript.OK, "fixture: stairs on 6")
	check.call(_room(s, "office", 6, 100) == RoomsScript.OK, "a room goes behind stairs")
	check.call(_bulldoze(s, 6, 100) == RoomsScript.OK and s.grid.cell_at(6, 100) != 0 and s.rooms.link_at(6, 100) == 0, "bulldoze takes the stairs before the room")
	var e := TestShafts._tall()
	check.call(_room(e, "retail", 6, 100) == RoomsScript.OK and TestLinks._escalator(e, 6, 100) == RoomsScript.OK, "an escalator goes in front of a shop")
	check.call(_bulldoze(e, 6, 100) == RoomsScript.OK and e.grid.cell_at(6, 100) != 0, "bulldoze takes the escalator before the shop")
	var f := TestShafts._tall()
	check.call(TestLinks._escalator(f, 6, 100) == RoomsScript.OK and _room(f, "retail", 6, 100) == RoomsScript.OK, "a shop goes behind an escalator")

	# A floor span over a shaft: the shaft built its own units, the rest of the span is new.
	var g := TestShafts._tall()
	check.call(TestLinks._shaft(g, 41, 41, 100) == RoomsScript.OK and not g.floors.has_floor(41, 110), "fixture: a shaft on floor 41 builds only its own units")
	check.call(TestRooms._send(g, Command.BUILD_FLOOR, [41, 100, 110] as Array[int]) == 0 and g.floors.has_floor(41, 110), "a floor span may cross a shaft")

	# A save keeps a room that shares cells with a shaft.
	var h := TowerSim.new(0)
	check.call(h.load_state(r.save()) and h.state_hash() == r.state_hash() and h.grid.cell_at(6, 100) != 0 and h.rooms.link_at(6, 100) != 0, "a tower with a room behind a shaft saves and loads exactly")
