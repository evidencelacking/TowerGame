extends RefCounted
## Sky lobby tests (8.1): floors 15, 30 ... 90 only, within the ground lobby's width, not rentable,
## no effect until a shaft reaches it, and passing a lobby resets the stair and escalator counts.

const Harness := preload("res://tests/harness.gd")
const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const FloorsScript := preload("res://scripts/sim/floors.gd")
const RoutesScript := preload("res://scripts/sim/routes.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")


static func _lobby(tower: TowerSim, floor_number: int, x_start: int, x_end: int) -> int:
	Harness.queue_all(tower, [Command.make(tower.tick + 1, Command.BUILD_LOBBY, [floor_number, x_start, x_end, 1])])
	tower.step()
	return tower.last_refusal


## Floors 1 to top built over columns 100 to 131, ground lobby 1 floor tall on 100 to 131.
static func _tall(top: int) -> TowerSim:
	var t := TowerSim.new(1, 1000000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 131, 1)
	for f in range(2, top + 1):
		t.floors.fill_span(f, 100, 131)
	return t


static func _shaft(t: TowerSim, bottom: int, top: int, x: int) -> int:
	t.rooms.place_shaft(t.grid, t.floors, t.ledger, 0, CatalogueScript.IDS.find("local_shaft"), bottom, top, x)
	return t.rooms._shaft_base(t.rooms.link_at(bottom, x))


static func run(check: Callable) -> void:
	# Only the six sky floors accept a sky lobby; 14 and 16 and others are refused.
	var t := _tall(95)
	for f: int in [14, 16, 2, 29, 31, 91, 100]:
		check.call(_lobby(t, f, 100, 109) == FloorsScript.LOBBY_BAD_FLOOR, "floor %d takes no lobby" % f)
	var funds := t.ledger.balance
	for f: int in FloorsScript.SKY_LOBBY_FLOORS:
		if f > 95:
			continue
		check.call(_lobby(t, f, 100, 109) == FloorsScript.OK, "floor %d takes a sky lobby" % f)
	check.call(funds - t.ledger.balance == 5000 * 10 * 6, "a sky lobby costs the lobby price per column (floor already built)")
	check.call(t.floors.has_lobby_at(15, 100) and not t.floors.has_lobby_at(16, 100), "a sky lobby is one floor tall")

	# Width: inside the ground lobby only; needs the ground lobby; no room can rent it.
	var w := _tall(20)
	check.call(_lobby(w, 15, 95, 109) == FloorsScript.SKY_WIDER_THAN_LOBBY, "a sky lobby is no wider than the ground lobby (left)")
	check.call(_lobby(w, 15, 120, 140) == FloorsScript.SKY_WIDER_THAN_LOBBY, "a sky lobby is no wider than the ground lobby (right)")
	check.call(_lobby(w, 15, 100, 131) == FloorsScript.OK, "a sky lobby as wide as the ground lobby is fine")
	check.call(_lobby(w, 15, 100, 131) == FloorsScript.ALREADY_BUILT, "the same sky lobby twice is refused")
	var office := CatalogueScript.IDS.find("office")
	check.call(w.rooms.check_place(w.grid, w.floors, "office", 15, 100)["reason"] != 0, "a room cannot take sky lobby cells (not rentable)")
	var none := TowerSim.new(1, 1000000000)
	for f in range(1, 20):
		none.floors.fill_span(f, 100, 131)
	check.call(_lobby(none, 15, 100, 109) == FloorsScript.SKY_NEEDS_LOBBY, "a sky lobby needs the ground lobby")
	# Needs floor below; refuses over a room.
	var thin := _tall(14)
	thin.floors.fill_span(15, 100, 131)
	check.call(_lobby(thin, 30, 100, 109) == FloorsScript.NOTHING_BELOW, "a sky lobby needs a floor under it")
	var occupied := _tall(20)
	occupied.rooms.place_room(occupied.grid, occupied.floors, occupied.ledger, 0, office, 15, 100)
	check.call(_lobby(occupied, 15, 100, 109) == FloorsScript.SKY_OCCUPIED, "a sky lobby cannot go over a room")

	# No effect until a shaft reaches it: floor 15 is no transfer floor without a lobby.
	var e := _tall(30)
	check.call(not e.floors.is_lobby_floor(15) and e.floors.is_lobby_floor(1), "floor 15 is not a lobby floor before one is built")
	_lobby(e, 15, 100, 131)
	check.call(e.floors.is_lobby_floor(15), "a built sky lobby makes its floor a lobby floor")
	# Without a shaft nothing links floor 15 to the ground: the walk is only by stairs, none here.
	var r := RoutesScript.find(e.floors, e.rooms, e.grid, 1, 100, 15, 100)
	check.call(r["reason"] == RoutesScript.NO_ROUTE, "a sky lobby links nothing until a shaft reaches it")

	# A shaft can be built through a sky lobby afterwards and a lobby over a shaft: both reach it.
	var s := _tall(30)
	var a := _shaft(s, 1, 15, 100)
	var b := _shaft(s, 15, 30, 110)
	_lobby(s, 15, 100, 131)
	check.call(a != 0 and b != 0 and s.floors.has_lobby_at(15, 100) and s.floors.has_shaft(15, 100), "a sky lobby spans the shafts it connects")
	r = RoutesScript.find(s.floors, s.rooms, s.grid, 1, 100, 30, 110)
	check.call(r["reason"] == RoutesScript.OK and r["legs"].filter(func(l: Dictionary) -> bool: return l["kind"] == RoutesScript.ELEVATOR).size() == 2, "a trip changes elevators at the sky lobby")
	var nolobby := _tall(30)
	_shaft(nolobby, 1, 15, 100)
	_shaft(nolobby, 15, 30, 110)
	r = RoutesScript.find(nolobby.floors, nolobby.rooms, nolobby.grid, 1, 100, 30, 110)
	check.call(r["reason"] == RoutesScript.TOO_MANY_TRANSFERS, "without the sky lobby floor 15 is no transfer point")

	# Passing a lobby resets the stair count: 5 stairs would exceed the limit of 4 per leg, but a
	# lobby cell on the way starts a new leg.
	var d := _tall(22)
	for f in range(13, 19):
		d.rooms.place_stairs(d.grid, d.floors, d.ledger, 0, f, 100 if f % 2 == 1 else 104)
	r = RoutesScript.find(d.floors, d.rooms, d.grid, 13, 100, 19, 104)
	check.call(r["reason"] == RoutesScript.TOO_MANY_STAIRS, "six flights without a lobby exceed the stair limit")
	_lobby(d, 15, 100, 131)
	r = RoutesScript.find(d.floors, d.rooms, d.grid, 13, 100, 19, 104)
	check.call(r["reason"] == RoutesScript.OK, "walking across a sky lobby resets the stair count")
