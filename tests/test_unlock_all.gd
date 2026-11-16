extends RefCounted
## Debug unlock-all switch (#156): off by default, a command turns it on, and then star-gated
## kinds (a 3-star restaurant at 1 star) pass the gates. It is hashed while on and never saved.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const Ghost := preload("res://scripts/view/placement_ghost.gd")
const ToolbarScript := preload("res://scripts/view/toolbar.gd")
const TestRooms := preload("res://tests/test_rooms.gd")


static func _switch(t: TowerSim, value: int) -> void:
	TestRooms._send(t, Command.DEBUG_UNLOCK_ALL, [value] as Array[int])


static func run(check: Callable) -> void:
	var t := TowerSim.new(1, 2000000)
	check.call(not t.unlock_all and t.unlocked_stars() == 1, "unlock-all is off by default")
	check.call(ToolbarScript.item_state("restaurant", t.unlocked_stars())["locked"], "off: the restaurant is locked at 1 star")
	var gated: String = Ghost.evaluate(t, "express_shaft", 5, 100, t.unlocked_stars())["text"]
	check.call(gated == "Needs 3 stars", "off: the star gate is what blocks a 3-star kind (%s)" % gated)
	var off := TowerSim.new(1, 2000000)
	off.step()
	_switch(t, 1)
	check.call(t.unlock_all and t.stars == 1 and t.unlocked_stars() == 5, "the command turns it on and leaves the real stars alone")
	check.call(not ToolbarScript.item_state("restaurant", t.unlocked_stars())["locked"], "on: the restaurant is unlocked at 1 star")
	var open: String = Ghost.evaluate(t, "express_shaft", 5, 100, t.unlocked_stars())["text"]
	check.call(open != "Needs 3 stars", "on: the 3-star gate no longer blocks (%s)" % open)
	var ghost := Ghost.new()
	ghost.tower = t
	check.call(ghost.stars == 5, "the ghost and toolbar read the unlocked rating")
	ghost.free()
	check.call(t.tick == off.tick and t.state_hash() != off.state_hash(), "the switch is part of the state hash")
	var loaded := TowerSim.new(1, 2000000)
	check.call(loaded.load_state(t.save()) and not loaded.unlock_all, "the switch is not saved")
	_switch(t, 0)
	check.call(not t.unlock_all, "the command can turn it off again")
