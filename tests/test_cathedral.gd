extends RefCounted
## The cathedral (#324, plan 11.4): floor 100 only, one per tower, permanent. Placement and its refusals. The wedding
## and the top-rank gate it feeds are in test_wedding.gd.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const Rooms := preload("res://scripts/sim/rooms.gd")
const Ghost := preload("res://scripts/view/placement_ghost.gd")


static func _put(t: TowerSim, kind: String, floor_number: int, x: int) -> int:
	return t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find(kind), floor_number, x)


static func run(check: Callable) -> void:
	var t := TowerSim.new(42, 1000000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	for floor_number: int in range(3, 101):
		t.floors.fill_span(floor_number, 100, 163)
	check.call(Rooms.PLACEABLE.has("cathedral"), "cathedral: it can be placed")
	check.call(Catalogue.field("cathedral", "placement") == Catalogue.PLACE_FLOOR_100 and not bool(Catalogue.field("cathedral", "removable")), "cathedral: floor 100 only and permanent")
	var low := t.rooms.check_place(t.grid, t.floors, "cathedral", 99, 100)
	check.call(low["reason"] == Rooms.NOT_FLOOR_100, "cathedral: refused on floor 99 (%d)" % low["reason"])
	var placed := _put(t, "cathedral", 100, 100)
	check.call(placed == Rooms.OK, "cathedral: places on floor 100 (%d)" % placed)
	check.call(t.rooms.room_count() == 1 and t.rooms.kind_of(t.rooms.room_ids()[0]) == "cathedral", "cathedral: the room is a cathedral")
	var again := t.rooms.check_place(t.grid, t.floors, "cathedral", 100, 132)
	check.call(again["reason"] == Rooms.ONE_CATHEDRAL, "cathedral: a second one is refused (%d)" % again["reason"])
	check.call(Ghost.ROOM_TEXT.has(Rooms.NOT_FLOOR_100) and Ghost.ROOM_TEXT.has(Rooms.ONE_CATHEDRAL), "cathedral: the ghost explains both refusals")
	check.call(Rooms.NOT_FLOOR_100 != Rooms.ONE_CATHEDRAL and Rooms.NOT_FLOOR_100 != Rooms.TOO_LOW and Rooms.ONE_CATHEDRAL != Rooms.NOT_TOP, "cathedral: its refusal codes are their own")
