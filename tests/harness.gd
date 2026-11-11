extends RefCounted
## Headless test harness: build a Tower from a seed, queue scripted commands, step fixed
## ticks and compare state hashes. Tests go through Tower's public API only.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command


## A tower seeded with seed_value, with every command in script queued.
static func make(seed_value: int, script: Array[Command] = []) -> TowerSim:
	var tower := TowerSim.new(seed_value)
	queue_all(tower, script)
	return tower


## Queues every command; returns false if any was refused (its tick already passed).
static func queue_all(tower: TowerSim, script: Array[Command]) -> bool:
	var all_queued := true
	for command in script:
		if not tower.enqueue(command):
			all_queued = false
	return all_queued


static func step(tower: TowerSim, ticks: int) -> void:
	for _i in ticks:
		tower.step()


## Steps ticks times and returns the state hash after every tick.
static func hash_trace(tower: TowerSim, ticks: int) -> Array[int]:
	var hashes: Array[int] = []
	for _i in ticks:
		tower.step()
		hashes.append(tower.state_hash())
	return hashes


## Runs the script on a fresh tower and returns the per-tick hash trace.
static func run_script(seed_value: int, script: Array[Command], ticks: int) -> Array[int]:
	return hash_trace(make(seed_value, script), ticks)


## True if two fresh runs of the same seed and script give identical hashes at every tick.
static func is_deterministic(seed_value: int, script: Array[Command], ticks: int) -> bool:
	return run_script(seed_value, script, ticks) == run_script(seed_value, script, ticks)


## Saves the tower into a fresh one and returns it, or null if the save is refused.
static func clone_via_save(tower: TowerSim) -> TowerSim:
	var copy := TowerSim.new(0)
	return copy if copy.load_state(tower.save()) else null
