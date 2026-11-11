extends RefCounted
## Placeholder simulation test.

const TowerSim := preload("res://scripts/sim/tower.gd")


static func run(check: Callable) -> void:
	var tower := TowerSim.new()
	for _i in 1000:
		tower.step()
	check.call(tower.tick == 1000, "1,000 steps advance the tick to 1,000")
