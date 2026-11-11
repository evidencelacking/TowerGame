extends RefCounted
## Simulation core tests: determinism, seeds, command timing, save and load.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command

const TICKS := 1000


## A fixed command script: a command every 7th tick, alternating kinds.
static func _script() -> Array[Command]:
	var commands: Array[Command] = []
	for t in range(7, TICKS + 1, 7):
		if t % 2 == 0:
			commands.append(Command.make(t, Command.ROLL, [100] as Array[int]))
		else:
			commands.append(Command.make(t, Command.NOTE, [t] as Array[int]))
	return commands


static func _run(seed_value: int) -> Array[int]:
	var tower := TowerSim.new(seed_value)
	for command in _script():
		tower.enqueue(command)
	var hashes: Array[int] = []
	for _i in TICKS:
		tower.step()
		hashes.append(tower.state_hash())
	return hashes


static func run(check: Callable) -> void:
	var tower := TowerSim.new(1)
	for _i in TICKS:
		tower.step()
	check.call(tower.tick == TICKS, "1,000 steps advance the tick to 1,000")

	var first := _run(42)
	var second := _run(42)
	check.call(first == second, "same seed and commands give identical hashes at ticks 1 to 1,000")
	check.call(first.size() == TICKS, "a hash is recorded at every tick")

	var other := _run(43)
	var diverged := false
	for i in TICKS:
		if first[i] != other[i]:
			diverged = true
	check.call(diverged, "a different seed diverges")

	# A command issued for tick N applies at tick N, on every run.
	for _run_index in 2:
		var timed := TowerSim.new(5)
		check.call(timed.enqueue(Command.make(10, Command.NOTE, [7] as Array[int])), "a future command queues")
		for _i in 9:
			timed.step()
		check.call(timed.notes == 0, "command for tick 10 has not applied at tick 9")
		timed.step()
		check.call(timed.tick == 10 and timed.notes == 7, "command for tick 10 applies at tick 10")
		timed.step()
		check.call(timed.notes == 7, "a command applies only once")
	var late := TowerSim.new(5)
	late.step()
	check.call(not late.enqueue(Command.make(1, Command.NOTE, [1] as Array[int])), "a command for a past or current tick is refused")

	# Commands at one tick apply in queue order: ROLL draws from the RNG, so the same
	# draw is added either way, but only the queue order of NOTE and ROLL is observable
	# through the RNG state, which both runs advance once.
	var order_a := TowerSim.new(9)
	order_a.enqueue(Command.make(1, Command.NOTE, [5] as Array[int]))
	order_a.enqueue(Command.make(1, Command.ROLL, [10] as Array[int]))
	var order_b := TowerSim.new(9)
	order_b.enqueue(Command.make(1, Command.ROLL, [10] as Array[int]))
	order_b.enqueue(Command.make(1, Command.NOTE, [5] as Array[int]))
	order_a.step()
	order_b.step()
	check.call(order_a.notes == order_b.notes, "both commands at one tick apply")
	check.call(order_a.rng.state == order_b.rng.state, "one RNG draw per ROLL regardless of order")

	# Save and load mid-run continues identically, RNG state included.
	var original := TowerSim.new(42)
	for command in _script():
		original.enqueue(command)
	for _i in 500:
		original.step()
	var copy := TowerSim.new(0)
	check.call(copy.load_state(original.save()), "a save loads")
	check.call(copy.state_hash() == original.state_hash(), "a loaded tower has the saved hash")
	var same := true
	for _i in 500:
		original.step()
		copy.step()
		if original.state_hash() != copy.state_hash():
			same = false
	check.call(same, "a loaded tower continues identically to tick 1,000")
	check.call(first[TICKS - 1] == original.state_hash(), "the resumed run matches the uninterrupted run")
	check.call(not TowerSim.new(0).load_state({"version": 999}), "an unsupported save version is refused")
