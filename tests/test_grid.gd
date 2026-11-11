extends RefCounted
## Grid tests: floor numbering, placing, querying, removing, hashing, save and load.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Grid := preload("res://scripts/sim/grid.gd")
const Fixtures := preload("res://tests/fixtures.gd")
const Harness := preload("res://tests/harness.gd")


static func run(check: Callable) -> void:
	# Floor numbers and indexes.
	check.call(Grid.FLOOR_COUNT == 110, "there are 110 floors")
	check.call(Grid.floor_to_index(-10) == 0, "B10 is index 0")
	check.call(Grid.floor_to_index(-1) == 9, "B1 is index 9")
	check.call(Grid.floor_to_index(1) == 10, "floor 1 is index 10")
	check.call(Grid.floor_to_index(100) == 109, "floor 100 is index 109")
	check.call(Grid.floor_to_index(0) == -1, "floor 0 has no index")
	check.call(Grid.floor_to_index(-11) == -1, "floor -11 has no index")
	check.call(Grid.floor_to_index(101) == -1, "floor 101 has no index")
	var round_trips := true
	for index in Grid.FLOOR_COUNT:
		if Grid.floor_to_index(Grid.index_to_floor(index)) != index:
			round_trips = false
	check.call(round_trips, "every index round-trips through its floor number")
	var floors_ok := true
	for floor_number in range(-10, 101):
		if floor_number != 0 and Grid.index_to_floor(Grid.floor_to_index(floor_number)) != floor_number:
			floors_ok = false
	check.call(floors_ok, "every floor number round-trips through its index")
	check.call(Grid.index_to_floor(-1) == 0, "index -1 is not a floor")
	check.call(Grid.index_to_floor(110) == 0, "index 110 is not a floor")

	# Place and query at the edges.
	var grid := Grid.new()
	check.call(grid.place(1, -10, 0, 1), "place at B10")
	check.call(grid.place(2, -1, 5, 1), "place at B1")
	check.call(grid.place(3, 1, 399, 1), "place at floor 1, last column")
	check.call(grid.place(4, 100, 0, 1), "place at floor 100")
	check.call(grid.cell_at(-10, 0) == 1, "query B10")
	check.call(grid.cell_at(-1, 5) == 2, "query B1")
	check.call(grid.cell_at(1, 399) == 3, "query floor 1")
	check.call(grid.cell_at(100, 0) == 4, "query floor 100")
	check.call(grid.cell_at(1, 398) == Grid.EMPTY, "a free cell is empty")

	# Rejections change nothing.
	var before := grid.state_ints()
	check.call(not grid.place(9, 0, 0, 1), "reject floor 0")
	check.call(not grid.place(9, -11, 0, 1), "reject floor -11")
	check.call(not grid.place(9, 101, 0, 1), "reject floor 101")
	check.call(not grid.place(9, 2, -1, 1), "reject a negative column")
	check.call(not grid.place(9, 2, 400, 1), "reject column 400")
	check.call(not grid.place(9, 2, 398, 3), "reject a run past the width")
	check.call(not grid.place(9, 2, 0, 0), "reject a zero-length run")
	check.call(not grid.place(9, 1, 395, 5), "reject overlap with an occupant")
	check.call(grid.cell_at(1, 395) == Grid.EMPTY, "a rejected overlap places no cells")
	check.call(not grid.place(0, 2, 0, 1), "reject id 0")
	check.call(not grid.place(1, 2, 0, 1), "reject an id already placed")
	check.call(grid.state_ints() == before, "rejections change nothing")
	check.call(grid.place(10, 2, 395, 5), "a run ending at the last cell fits")

	# Multi-cell occupants and removal.
	var wide := Grid.new()
	check.call(wide.place(7, 3, 10, 9), "place a 9-cell occupant")
	var all_cells := true
	for column in range(10, 19):
		if wide.cell_at(3, column) != 7:
			all_cells = false
	check.call(all_cells, "every cell of a multi-cell occupant returns its id")
	check.call(wide.cell_at(3, 9) == Grid.EMPTY and wide.cell_at(3, 19) == Grid.EMPTY, "the cells beside it are empty")
	var expected_run: Array[int] = [3, 10, 9]
	check.call(wide.run_of(7) == expected_run, "run_of reports the floor, column and length")
	check.call(wide.remove(7), "remove an occupant")
	var cleared := true
	for column in range(10, 19):
		if wide.cell_at(3, column) != Grid.EMPTY:
			cleared = false
	check.call(cleared, "after removal every cell is empty")
	check.call(not wide.remove(7), "removing an absent id returns false")
	check.call(wide.place(8, 3, 10, 9), "a removed run can be placed again")

	# Through the Tower: commands, hash, save and load.
	var tower := Fixtures.grid_sample(5)
	check.call(tower.grid.cell_at(-10, 3) == 1, "a PLACE command places on the grid")
	check.call(tower.grid.cell_at(1, 39) == 2, "a PLACE command covers its whole run")
	check.call(tower.grid.cell_at(5, 20) == Grid.EMPTY, "a REMOVE command clears the occupant")
	check.call(Fixtures.grid_sample(5).state_hash() == tower.state_hash(), "the grid hashes identically across two runs")
	var empty_hash := TowerSim.new(5)
	Harness.step(empty_hash, 6)
	check.call(empty_hash.state_hash() != tower.state_hash(), "the grid is part of the hash")

	var copy := Harness.clone_via_save(tower)
	check.call(copy != null, "a save with a grid loads")
	check.call(copy.state_hash() == tower.state_hash(), "the grid survives save and load")
	check.call(copy.grid.cell_at(100, 399) == 3, "a loaded grid answers queries")

	# An invalid save changes nothing.
	var untouched := Fixtures.grid_sample(5)
	var good := untouched.save()
	var hash_before := untouched.state_hash()
	var bad_clock := good.duplicate(true)
	bad_clock["clock"] = [0, 0, 0, 0, 1, 7]
	check.call(not untouched.load_state(bad_clock), "a save with a bad clock is refused")
	var bad_grid := good.duplicate(true)
	bad_grid["grid"] = [1, 0, 0, 1]
	bad_grid["tick"] = 999
	bad_grid["notes"] = 999
	check.call(not untouched.load_state(bad_grid), "a save with a bad grid is refused")
	var overlap := good.duplicate(true)
	overlap["grid"] = [1, 1, 0, 5, 2, 1, 4, 5]
	overlap["tick"] = 999
	check.call(not untouched.load_state(overlap), "a save with overlapping occupants is refused")
	var bad_queue := good.duplicate(true)
	bad_queue["queue"] = [[1, 2]]
	bad_queue["tick"] = 999
	check.call(not untouched.load_state(bad_queue), "a save with a bad queue is refused")
	var no_grid := good.duplicate(true)
	no_grid.erase("grid")
	no_grid["tick"] = 999
	check.call(not untouched.load_state(no_grid), "a save missing its grid is refused")
	check.call(untouched.state_hash() == hash_before, "refused saves leave the tower unchanged")
	check.call(untouched.tick == 6 and untouched.grid.cell_at(-10, 0) == 1, "the tick and grid are still as they were")
