extends RefCounted
## Room placement tests (2.4): office and condo above ground, floor purchase, overlap, support.

const Harness := preload("res://tests/harness.gd")
const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")

const OFFICE := 5  # index in RoomCatalogue.IDS
const CONDO := 6


## A tower with a 1-floor ground lobby at columns 100 to 109 (the only floor built).
static func _tower(funds: int = 2000000) -> TowerSim:
	var tower := TowerSim.new(1, funds)
	_send(tower, Command.BUILD_LOBBY, [1, 100, 109, 1] as Array[int])
	return tower


static func _send(tower: TowerSim, kind: int, args: Array[int]) -> int:
	Harness.queue_all(tower, [Command.make(tower.tick + 1, kind, args)])
	tower.step()
	return tower.last_refusal


static func _room(tower: TowerSim, kind_index: int, floor_number: int, x_left: int) -> int:
	return _send(tower, Command.PLACE_ROOM, [kind_index, floor_number, x_left] as Array[int])


static func run(check: Callable) -> void:
	# Catalogue data.
	check.call(Catalogue.field("office", "people") == 6 and Catalogue.field("condo", "people") == 3, "office holds 6 workers, condo 3 residents")

	# Refusals: basement, floor 1, off the tower, unknown kind. Refusals are free.
	var t := _tower()
	var funds := t.ledger.balance
	check.call(_room(t, OFFICE, -1, 100) == RoomsScript.BELOW_GROUND, "a room on B1 is refused")
	check.call(_room(t, OFFICE, 1, 120) == RoomsScript.LOBBY_FLOOR, "a room on floor 1 is refused")
	check.call(_room(t, OFFICE, 2, 395) == RoomsScript.OFF_TOWER, "a room past the tower width is refused")
	check.call(_room(t, OFFICE, 2, -1) == RoomsScript.OFF_TOWER, "a room left of the tower is refused")
	check.call(_room(t, 0, 2, 100) == RoomsScript.UNKNOWN_KIND, "the lobby is not a placeable room")
	check.call(_room(t, 99, 2, 100) == RoomsScript.UNKNOWN_KIND, "a bad kind index is refused")
	check.call(_room(t, OFFICE, 101, 100) == RoomsScript.BAD_FLOOR, "floor 101 is refused")
	check.call(t.ledger.balance == funds and t.rooms.room_count() == 0, "refusals cost nothing and place nothing")

	# Cost: an office on a missing floor pays the room plus $500 a unit; on a built floor, the room only.
	var width: int = Catalogue.field("office", "width")
	check.call(_room(t, OFFICE, 2, 100) == RoomsScript.OK, "an office on floor 2 over the lobby builds")
	check.call(funds - t.ledger.balance == 40000 + 500 * width, "office total = room + missing floor units")
	check.call(t.ledger.lines.size() == 3, "the room is one ledger charge")
	check.call(t.floors.has_floor(2, 100) and t.floors.has_floor(2, 100 + width - 1) and not t.floors.has_floor(2, 100 + width), "the room built exactly its own floor units")
	check.call(_room(t, OFFICE, 3, 100) == RoomsScript.OK, "an office stacks on the office below")
	var condo_width: int = Catalogue.field("condo", "width")
	t.floors.fill_span(4, 100, 100 + condo_width - 1)  # a floor already built (test setup only)
	funds = t.ledger.balance
	check.call(_room(t, CONDO, 4, 100) == RoomsScript.OK, "a condo on an existing floor builds")
	check.call(funds - t.ledger.balance == 80000, "a room on an existing floor costs the room price only")
	check.call(t.rooms.kind_of(t.grid.cell_at(4, 100)) == "condo" and t.rooms.kind_of(t.grid.cell_at(2, 100)) == "office", "rooms remember their kind")

	# Overlap with another room, and with the lobby.
	check.call(_room(t, OFFICE, 2, 100 + width - 1) == RoomsScript.OVERLAPS_ROOM, "overlapping another room is refused")
	var lobby_tower := TowerSim.new(1)
	_send(lobby_tower, Command.BUILD_LOBBY, [1, 100, 109, 2] as Array[int])
	check.call(_room(lobby_tower, OFFICE, 2, 100) == RoomsScript.OVERLAPS_LOBBY, "a room inside a tall lobby is refused")

	# Shaft in the way.
	var shaft_tower := _tower()
	shaft_tower.floors.mark_shaft(2, 104)
	check.call(_room(shaft_tower, OFFICE, 2, 100) == RoomsScript.OVER_SHAFT, "a room over a shaft is refused")

	# Support: nothing below, and an overhang.
	var support := _tower()
	check.call(_room(support, OFFICE, 2, 200) == RoomsScript.NOTHING_BELOW, "a room with no floor below is refused")
	check.call(_room(support, OFFICE, 2, 105) == RoomsScript.OVERHANG, "a room hanging past the floor below is refused")
	check.call(_room(support, OFFICE, 3, 100) == RoomsScript.NOTHING_BELOW, "floor 3 over an unbuilt floor 2 is refused")

	# check_place is pure and agrees with placing.
	var before := support.state_hash()
	var preview := support.rooms.check_place(support.grid, support.floors, "office", 2, 100)
	check.call(preview["reason"] == RoomsScript.OK and preview["floor_units"] == width and preview["cost"] == 40000 + 500 * width, "check_place reports reason, cost and floor units")
	check.call(support.state_hash() == before, "check_place changes nothing")
	preview = support.rooms.check_place(support.grid, support.floors, "office", 2, 105)
	check.call(preview["reason"] == RoomsScript.OVERHANG, "check_place reports an overhang")

	# Short of funds: the lobby leaves 44,000 and an office on a missing floor needs 44,500.
	var poor := _tower(99000)
	var poor_before := poor.ledger.balance
	check.call(_room(poor, OFFICE, 2, 100) == RoomsScript.SHORT_OF_FUNDS, "a room is refused when short of funds")
	check.call(poor.ledger.balance == poor_before and poor.rooms.room_count() == 0 and not poor.floors.has_floor(2, 100), "a short refusal builds and charges nothing")

	# Save and load, and determinism.
	var saved := t.save()
	var loaded := TowerSim.new(0)
	check.call(loaded.load_state(saved) and loaded.state_hash() == t.state_hash(), "rooms survive save and load")
	check.call(loaded.rooms.kind_of(t.grid.cell_at(4, 100)) == "condo", "loaded rooms keep their kind")
	var bad := t.save()
	bad["rooms"] = [1000, 1, 777, OFFICE]  # room 777 is not on the grid
	check.call(not TowerSim.new(0).load_state(bad), "a save with a room missing from the grid is refused")
	var one := _tower()
	var two := _tower()
	for tower: TowerSim in [one, two]:
		_room(tower, OFFICE, 2, 100)
		_room(tower, OFFICE, 3, 100)
	check.call(one.rooms.room_count() == 2 and one.state_hash() == two.state_hash(), "the same placements give the same hash")
	_room(two, OFFICE, 4, 100)
	check.call(one.state_hash() != two.state_hash(), "another room changes the hash")
