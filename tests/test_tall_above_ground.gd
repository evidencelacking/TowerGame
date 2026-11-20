extends RefCounted
## Two-floor rooms above ground (#328 step 1). No catalogue kind is tall above ground yet, so the
## placement check is called directly with a wide above-ground kind (casino, 40 wide). Recycling must
## behave exactly as before, and room_of / is_tall_upper must not care which side of the ground.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const GridScript := preload("res://scripts/sim/grid.gd")


static func _tower() -> TowerSim:
	var t := TowerSim.new(5, 1000000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	t.floors.fill_span(2, 100, 163)  # floor 2 above the lobby, wide enough to carry the room
	t.floors.fill_span(-1, 90, 200)
	return t


static func _tall(t: TowerSim, kind: String, floor_number: int, x: int) -> Dictionary:
	return t.rooms._check_place_tall(t.grid, t.floors, kind, floor_number, x)


static func run(check: Callable) -> void:
	var t := _tower()
	check.call(not RoomsScript.TALL_KINDS.has("casino"), "tall: the casino is still a one-floor room in this step")

	# Above ground: lower floor 3 rests on floor 2, the upper floor 4 rests on the lower.
	var ok := _tall(t, "casino", 3, 110)
	check.call(ok["reason"] == RoomsScript.OK, "tall above ground: a room on floor 3 over floor 2 is accepted")
	check.call(ok["floor_units"] == 80 and ok["cost"] == Catalogue.cost("casino") + 80 * Catalogue.FLOOR_COST_PER_UNIT, "tall above ground: both floors' missing units are charged")
	check.call(_tall(t, "casino", 3, 100)["reason"] == RoomsScript.OK, "tall above ground: flush with the supporting floor's edge is accepted")
	check.call(_tall(t, "casino", 3, 130)["reason"] == RoomsScript.OVERHANG, "tall above ground: hanging past the floor below is an overhang")
	check.call(_tall(t, "casino", 3, 170)["reason"] == RoomsScript.NOTHING_BELOW, "tall above ground: nothing below it is refused")
	check.call(_tall(t, "casino", 5, 110)["reason"] == RoomsScript.NOTHING_BELOW, "tall above ground: a gap of empty floors below is refused")
	check.call(_tall(t, "casino", 1, 110)["reason"] == RoomsScript.LOBBY_FLOOR, "tall above ground: not on the lobby floor")
	check.call(_tall(t, "casino", -3, 110)["reason"] == RoomsScript.BELOW_GROUND, "tall above ground: not underground")
	check.call(_tall(t, "casino", GridScript.FLOOR_MAX, 110)["reason"] == RoomsScript.BAD_FLOOR, "tall above ground: the top floor has no floor above it")
	check.call(_tall(t, "casino", 3, GridScript.WIDTH_UNITS - 10)["reason"] == RoomsScript.OFF_TOWER, "tall above ground: the tower's edge is respected")

	# The upper floor counts as occupied: a room already on floor 4 blocks the tall room.
	t.floors.fill_span(3, 100, 163)
	t.floors.fill_span(4, 100, 163)
	t.grid.place(900, 4, 120, 10)
	check.call(_tall(t, "casino", 3, 110)["reason"] == RoomsScript.OVERLAPS_ROOM, "tall above ground: a room on its upper floor blocks it")

	# Recycling keeps its basement rules.
	check.call(_tall(t, "recycling", -3, 100)["reason"] == RoomsScript.OK, "tall: recycling still places on B3/B2 under B1")
	check.call(_tall(t, "recycling", -1, 100)["reason"] == RoomsScript.NOT_UNDERGROUND, "tall: recycling still needs both floors below B1")
	check.call(_tall(t, "recycling", 3, 100)["reason"] == RoomsScript.NOT_UNDERGROUND, "tall: recycling still refuses above ground")

	# room_of and is_tall_upper work on the id pair.
	var placed := t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("recycling"), -3, 100)
	check.call(placed == RoomsScript.OK, "tall: recycling placed")
	var low: int = t.grid.cell_at(-3, 100)
	check.call(t.rooms.room_of(low) == low and t.rooms.room_of(low + 1) == low and t.rooms.is_tall_upper(low + 1) and not t.rooms.is_tall_upper(low), "tall: room_of maps the upper half to the room")
	check.call(t.rooms.room_of(900) == 0, "tall: an occupant that is no room maps to 0")
	check.call(t.rooms.highest_room_floor(t.grid) == 0, "tall: an underground tall room leaves the highest above-ground floor at 0")
