extends RefCounted
## Noise tests (5.5): offices disturb condos not offices; above, below, beside, out of range,
## buffers, removal, determinism, and the pure core for kinds not yet placeable.

const TowerSim := preload("res://scripts/sim/tower.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const NoiseSim := preload("res://scripts/sim/noise.gd")


static func _tower() -> TowerSim:
	var t := TowerSim.new(7, 1000000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 131, 2)
	for f in range(2, 9):
		t.floors.fill_span(f, 100, 131)
	return t


## Places a room and returns its id, or -1 when it was not placed.
static func _place(t: TowerSim, kind: String, floor_number: int, x: int) -> int:
	var before := t.rooms.room_ids().size()
	t.rooms.place_room(t.grid, t.floors, t.ledger, 0, CatalogueScript.IDS.find(kind), floor_number, x)
	var ids := t.rooms.room_ids()
	return ids[ids.size() - 1] if ids.size() > before else -1


static func run(check: Callable) -> void:
	var t := _tower()
	var condo := _place(t, "condo", 4, 100)  # columns 100..115
	var office_beside := _place(t, "office", 4, 117)  # one empty unit between
	check.call(office_beside >= 0 and condo >= 0, "noise: rooms placed")
	check.call(NoiseSim.noise_at(t.grid, t.rooms, condo) == 2, "noise: office beside a condo disturbs it (3 - 1)")
	check.call(NoiseSim.noise_at(t.grid, t.rooms, office_beside) == 0, "noise: the office beside a condo is not disturbed")

	var office_above := _place(t, "office", 5, 100)
	check.call(NoiseSim.noise_at(t.grid, t.rooms, condo) == 4, "noise: office above adds noise (3 - 1)")
	var office_below := _place(t, "office", 3, 100)
	check.call(NoiseSim.noise_at(t.grid, t.rooms, condo) == 6, "noise: office below adds noise")
	check.call(NoiseSim.levels(t.grid, t.rooms) == {condo: 6}, "noise: only the condo is disturbed; offices stay quiet")

	# Offices next to offices raise nothing.
	var t2 := _tower()
	var a := _place(t2, "office", 4, 100)
	var b := _place(t2, "office", 4, 109)
	check.call(a >= 0 and b >= 0, "noise: two offices placed")
	check.call(NoiseSim.noise_at(t2.grid, t2.rooms, a) == 0 and NoiseSim.noise_at(t2.grid, t2.rooms, b) == 0, "noise: office next to office raises none")
	check.call(NoiseSim.levels(t2.grid, t2.rooms).is_empty(), "noise: no disturbed rooms in an office-only tower")

	# Out of range: two floors away, or too far sideways.
	var t3 := _tower()
	var c3 := _place(t3, "condo", 4, 100)
	var far_above := _place(t3, "office", 6, 100)
	check.call(c3 >= 0 and far_above >= 0, "noise: out-of-range rooms placed")
	check.call(NoiseSim.noise_at(t3.grid, t3.rooms, c3) == 0, "noise: office two floors away is out of range")
	var far_side := _place(t3, "office", 4, 119)  # three empty units away
	check.call(far_side >= 0, "noise: far-side office placed")
	check.call(NoiseSim.noise_at(t3.grid, t3.rooms, c3) == 0, "noise: office 3 units away sideways is out of range")
	check.call(t3.grid.remove(far_side), "noise: far-side office removed")
	var near_side := _place(t3, "office", 4, 116)  # touching
	check.call(near_side >= 0 and NoiseSim.noise_at(t3.grid, t3.rooms, c3) == 3, "noise: a touching office is 3 (no falloff)")

	# Removal clears it next evaluation.
	for id in [office_beside, office_above, office_below]:
		check.call(t.grid.remove(id), "noise: removed office %d" % id)
		t.rooms._kind_of.erase(id)
	check.call(NoiseSim.noise_at(t.grid, t.rooms, condo) == 0, "noise: removing the offices clears the noise")

	# Same tower, same answer (pure).
	check.call(NoiseSim.levels(t3.grid, t3.rooms) == NoiseSim.levels(t3.grid, t3.rooms), "noise: repeatable")

	# Pure core: other kinds, buffers, caps, distance.
	var suite := [4, 100, 10]
	check.call(NoiseSim.level_among("hotel_suite", suite, [["party_hall", [4, 110, 24]]]) == 8, "noise: party hall touching a suite is 8")
	check.call(NoiseSim.level_among("hotel_suite", suite, [["retail", [4, 111, 4]]]) == 2, "noise: retail 1 unit away is 3 - 1")
	check.call(NoiseSim.level_among("hotel_suite", suite, [["party_hall", [4, 110, 24]], ["medical", [5, 100, 16]]]) == 6, "noise: a medical room nearby mutes 2")
	check.call(NoiseSim.level_among("hotel_suite", suite, [["party_hall", [4, 110, 24]], ["cathedral", [4, 90, 10]]]) == 4, "noise: a cathedral mutes 4")
	check.call(NoiseSim.level_among("hotel_suite", suite, [["office", [4, 110, 9]], ["cathedral", [4, 90, 10]]]) == 0, "noise: buffers never push below 0")
	check.call(NoiseSim.level_among("hotel_suite", suite, [["party_hall", [4, 110, 24]], ["medical", [4, 20, 16]]]) == 8, "noise: a distant buffer does nothing")
	check.call(NoiseSim.level_among("hotel_twin", suite, [["party_hall", [4, 110, 24]], ["party_hall", [5, 100, 24]], ["movie_theatre", [3, 100, 32]]]) == 10, "noise: level capped at MAX_LEVEL")
	check.call(NoiseSim.level_among("office", suite, [["party_hall", [4, 110, 24]]]) == 0, "noise: offices are not sensitive")
	check.call(NoiseSim.level_among("condo", [1, 100, 16], [["office", [-1, 100, 9]]]) == 2, "noise: B1 and floor 1 are one floor apart")
	check.call(NoiseSim.stress_for(5) == NoiseSim.STRESS_PER_NOISE_LEVEL * 5, "noise: stress follows its one constant")
