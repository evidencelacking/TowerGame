extends RefCounted
## Security office (7.4, #169): placeable at 2 stars, cannot be bulldozed, covers floors by
## distance (nearest office answers), staff never need inside stairs, satisfies star 3 and
## clears the "needs security" demand.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Msg := preload("res://scripts/sim/messages.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const Sec := preload("res://scripts/sim/security.gd")
const DemandsScript := preload("res://scripts/sim/demands.gd")


static func _tower() -> TowerSim:
	var t := TowerSim.new(5, 1000000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	for f in [3, 20, 40]:
		t.floors.fill_span(f, 100, 163)
	return t


static func _put(t: TowerSim, kind: String, floor_number: int, x: int) -> int:
	return t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find(kind), floor_number, x)


static func run(check: Callable) -> void:
	check.call(Rooms.PLACEABLE.has("security"), "security is placeable")
	check.call(Sec.COVER_FLOORS == 15, "the reach is 15 floors (owner ruling)")

	var t := _tower()
	check.call(not Sec.threats_possible(t.rooms) and Sec.response_minutes(t.rooms, t.grid, 10) == -1, "no office: no threats, no response")
	check.call(Sec.staff_count(t.rooms) == 0, "no office: no staff")
	check.call(_put(t, "security", 3, 100) == Rooms.OK, "an office places on floor 3")
	check.call(Sec.threats_possible(t.rooms) and Sec.staff_count(t.rooms) == Sec.GUARDS_PER_OFFICE, "an office brings staff and makes threats possible")
	check.call(Sec.covers(t.rooms, t.grid, 18) and not Sec.covers(t.rooms, t.grid, 19), "covers floors within 15 and not beyond")
	check.call(Sec.covers(t.rooms, t.grid, 3) and Sec.covers(t.rooms, t.grid, 1), "covers its own floor and the lobby")
	check.call(Sec.response_minutes(t.rooms, t.grid, 18) > Sec.response_minutes(t.rooms, t.grid, 4), "response time grows with distance")
	check.call(Sec.distance(1, -1) == 1, "there is no floor 0: the lobby and B1 are neighbours")

	# Nearest of two offices responds.
	_put(t, "security", 40, 100)
	var near := Sec.nearest(t.rooms, t.grid, 30)
	check.call(near["distance"] == 10 and t.grid.run_of(near["room"])[0] == 40, "the nearest of two offices responds")
	check.call(Sec.covers(t.rooms, t.grid, 30) and Sec.staff_count(t.rooms) == 2 * Sec.GUARDS_PER_OFFICE, "two offices cover the gap between them")

	# Cannot be bulldozed.
	t.tick = 20
	t.enqueue(TowerSim.Command.make(21, TowerSim.Command.BULLDOZE, [3, 100] as Array[int]))
	t.step()
	t.step()
	check.call(Sec.offices(t.rooms).size() == 2, "a security office cannot be bulldozed")

	# Star facts and the demand.
	var s := _tower()
	s.stars = 2
	s.promote_stars()
	check.call(s.demands.is_open(DemandsScript.SECURITY), "at 2 stars the tower needs security")
	check.call(s.star_facts()["security"] == 0, "no office: security fact is 0")
	_put(s, "security", 3, 100)
	s.promote_stars()
	check.call(s.star_facts()["security"] == 1 and not s.demands.is_open(DemandsScript.SECURITY), "an office satisfies the star fact and clears the demand")

	# Response (#216): covered floor, uncovered floor, nearest of two offices.
	var r := _tower()
	check.call(Sec.response_ticks(r.rooms, r.grid, 10) == -1 and Sec.responder(r.rooms, r.grid, 10) == 0, "no office: no response")
	_put(r, "security", 3, 100)
	var office: int = Sec.offices(r.rooms)[0]
	check.call(Sec.response_ticks(r.rooms, r.grid, 3) == 3, "guards reach their own floor in one minute (3 ticks)")
	check.call(Sec.response_ticks(r.rooms, r.grid, 18) > Sec.response_ticks(r.rooms, r.grid, 4) and Sec.response_ticks(r.rooms, r.grid, 18) > 0, "a covered floor gets a response that grows with distance")
	check.call(Sec.responder(r.rooms, r.grid, 18) == office, "the office answers a covered floor")
	check.call(Sec.response_ticks(r.rooms, r.grid, 19) == -1 and Sec.responder(r.rooms, r.grid, 19) == 0, "an uncovered floor gets no response")
	_put(r, "security", 40, 100)
	var far: int = Sec.offices(r.rooms)[1]
	check.call(Sec.responder(r.rooms, r.grid, 30) == far and Sec.responder(r.rooms, r.grid, 10) == office, "with two offices the nearer one answers")
	check.call(Sec.response_ticks(r.rooms, r.grid, 30) < Sec.response_ticks(r.rooms, r.grid, 18) + 1 and Sec.response_ticks(r.rooms, r.grid, 30) > 0, "a floor between offices is answered")
	check.call(Sec.search_rank(10, 10) == 0 and Sec.search_rank(10, 11) == 1 and Sec.search_rank(10, 9) == 2 and Sec.search_rank(10, 12) == 3, "a sweep goes up one, down one, and so on")
	check.call(Sec.search_rank(10, 26) == -1 and Sec.search_rank(1, -1) == 2, "a sweep stops at the reach and counts no floor 0")
