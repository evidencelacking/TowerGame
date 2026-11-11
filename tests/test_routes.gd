extends RefCounted
## Route finder tests (3.5): walking, stairs, the 4-stairs-a-trip limit, lobbies reset it.

const TowerSim := preload("res://scripts/sim/tower.gd")
const RoutesScript := preload("res://scripts/sim/routes.gd")


static func _stairs_legs(route: Dictionary) -> int:
	var n := 0
	for leg: Dictionary in route["legs"]:
		if leg["kind"] == RoutesScript.STAIRS:
			n += 1
	return n


static func _find(t: TowerSim, ff: int, fx: int, tf: int, tx: int) -> Dictionary:
	return RoutesScript.find(t.floors, t.rooms, t.grid, ff, fx, tf, tx)


## Floors 1 to top_floor over columns 100-131, stairs on floors 1 to top_floor - 1 alternating
## between x=100 and x=104 (a chain up the tower).
static func _chain(top_floor: int) -> TowerSim:
	var t := TowerSim.new(1, 100000000)
	for f in range(1, top_floor + 1):
		t.floors.fill_span(f, 100, 131)
	for f in range(1, top_floor):
		t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, f, 100 if f % 2 == 1 else 104)
	return t


## Left and right stair chains over floors 1 to 5, joined only on floors 1 and 2, which are
## the ground lobby when with_lobby is set and plain floor otherwise.
static func _two_chains(with_lobby: bool) -> TowerSim:
	var t := TowerSim.new(1, 100000000)
	if with_lobby:
		t.floors.build_lobby(t.ledger, 0, 1, 100, 131, 2)
	else:
		t.floors.fill_span(1, 100, 131)
		t.floors.fill_span(2, 100, 131)
	for f in range(3, 6):
		t.floors.fill_span(f, 100, 111)
		t.floors.fill_span(f, 118, 131)
	for f in range(1, 5):
		t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, f, 100 if f % 2 == 1 else 104)
		t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, f, 120 if f % 2 == 1 else 124)
	return t


static func run(check: Callable) -> void:
	# Walking along one floor.
	var t := _chain(5)
	var r := _find(t, 1, 100, 1, 130)
	check.call(r["reason"] == RoutesScript.OK and r["legs"].size() == 1 and r["legs"][0]["kind"] == RoutesScript.WALK, "same-floor trip is one walk")
	var same := _find(t, 1, 110, 1, 110)
	check.call(same["legs"].is_empty() and same["reason"] == RoutesScript.OK, "start is goal: no legs")
	check.call(_find(t, 1, 50, 1, 110)["reason"] == RoutesScript.NO_FLOOR, "no floor under the start is refused")
	check.call(_find(t, 1, 110, 8, 110)["reason"] == RoutesScript.NO_FLOOR, "no floor under the goal is refused")
	check.call(_find(t, 0, 110, 1, 110)["reason"] == RoutesScript.BAD_FLOOR, "floor 0 is refused")

	# Stairs: 1 to 5 is four stairs and accepted; 1 to 6 is five and refused.
	r = _find(t, 1, 100, 5, 100)
	check.call(r["reason"] == RoutesScript.OK and _stairs_legs(r) == 4, "4-floor stair trip accepted with 4 stairs")
	var t6 := _chain(6)
	r = _find(t6, 1, 100, 6, 100)
	check.call(r["reason"] == RoutesScript.TOO_MANY_STAIRS, "5-floor stair trip refused")
	r = _find(t6, 6, 100, 1, 100)
	check.call(r["reason"] == RoutesScript.TOO_MANY_STAIRS, "5-floor trip down is refused too")
	r = _find(t6, 2, 100, 6, 104)
	check.call(r["reason"] == RoutesScript.OK and _stairs_legs(r) == 4, "any 4-stair stretch of the chain works")

	# Walk then stairs: legs are in order and stairs go to the adjacent floor.
	r = _find(t, 1, 130, 2, 130)
	check.call(r["reason"] == RoutesScript.OK and r["legs"].size() == 3 and r["legs"][0]["kind"] == RoutesScript.WALK and r["legs"][1]["kind"] == RoutesScript.STAIRS and r["legs"][1]["to_floor"] == 2 and r["legs"][2]["kind"] == RoutesScript.WALK, "walk, stairs, walk")

	# Unreachable: a floor with no stairs to it.
	var island := _chain(3)
	island.floors.fill_span(5, 100, 131)
	check.call(_find(island, 1, 100, 5, 100)["reason"] == RoutesScript.NO_ROUTE, "a floor with no stairs is no route")

	# Lobby resets the count: stairs down, across the lobby, more stairs up.
	var lobby := _two_chains(true)
	r = _find(lobby, 5, 100, 5, 130)
	check.call(r["reason"] == RoutesScript.OK and _stairs_legs(r) > 4, "stairs, lobby, more stairs accepted")
	var plain := _two_chains(false)
	check.call(_find(plain, 5, 100, 5, 130)["reason"] == RoutesScript.TOO_MANY_STAIRS, "the same trip with no lobby is refused")

	# Deterministic.
	check.call(var_to_str(_find(lobby, 5, 100, 5, 130)) == var_to_str(r), "the same query gives the same route")
