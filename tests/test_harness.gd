extends RefCounted
## Tests for the harness and fixtures themselves, plus a built-tower determinism test.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const Grid := preload("res://scripts/sim/grid.gd")
const Fixtures := preload("res://tests/fixtures.gd")
const Harness := preload("res://tests/harness.gd")

const TICKS := 300


## Builds a small tower, removes a room, and rolls dice, all as commands.
static func _script() -> Array[Command]:
	var commands: Array[Command] = []
	for i in 10:
		var floor_number := i + 1
		commands.append(Command.make(1 + i * 3, Command.PLACE, [i + 1, floor_number, 5 * i, 20] as Array[int]))
		commands.append(Command.make(2 + i * 3, Command.ROLL, [1000] as Array[int]))
	commands.append(Command.make(100, Command.REMOVE, [4] as Array[int]))
	return commands


static func run(check: Callable) -> void:
	# Fixtures place through commands.
	var tower := Fixtures.with_rooms(3, [[1, 0, 10], [2, 5, 4], [-1, 0, 2]])
	check.call(tower.tick == 1, "with_rooms leaves the tower at tick 1")
	check.call(tower.grid.cell_at(1, 9) == 1 and tower.grid.cell_at(2, 5) == 2 and tower.grid.cell_at(-1, 1) == 3, "with_rooms places each spec with ids from 1")
	check.call(tower.grid.cell_at(1, 10) == Grid.EMPTY, "a placed room covers only its length")

	var stacked := Fixtures.stack(3, -2, 3, 6)
	check.call(stacked.grid.occupant_count() == 5, "stack skips the missing floor 0")

	var removal := Fixtures.with_rooms(3, [[1, 0, 10]])
	check.call(Fixtures.remove(removal, 1), "a remove queues")
	Harness.step(removal, 1)
	check.call(removal.grid.cell_at(1, 0) == Grid.EMPTY, "a queued remove clears the room")
	check.call(not Fixtures.place(removal, 1, 1, 0, 1, removal.tick), "a place for the current tick is refused")

	# Harness: trace shape and determinism over a command script with a built tower.
	var trace := Harness.run_script(8, _script(), TICKS)
	check.call(trace.size() == TICKS, "the trace has one hash per tick")
	check.call(Harness.is_deterministic(8, _script(), TICKS), "a scripted build run is deterministic")
	check.call(trace != Harness.run_script(9, _script(), TICKS), "a different seed gives a different trace")

	var built := Harness.make(8, _script())
	Harness.step(built, TICKS)
	check.call(built.grid.occupant_count() == 9, "the script built ten rooms and removed one")
	check.call(built.state_hash() == trace[TICKS - 1], "stepping matches the trace's last hash")

	# Save mid-run, resume, and match the uninterrupted trace.
	var half := Harness.make(8, _script())
	Harness.step(half, 150)
	var copy := Harness.clone_via_save(half)
	check.call(copy != null, "clone_via_save clones a mid-run tower")
	if copy != null:
		var resumed := Harness.hash_trace(copy, TICKS - 150)
		check.call(resumed == trace.slice(150), "a saved and loaded tower resumes the same trace")
