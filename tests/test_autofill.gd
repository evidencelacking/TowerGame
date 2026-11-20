extends RefCounted
## Auto-fill floor (#273): the ghost adds the floor between a new item and the floor beside it, with
## its price, and a click sends ordinary floor commands first. The sim itself is unchanged.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const Ghost := preload("res://scripts/view/placement_ghost.gd")
const ViewSettings := preload("res://scripts/view/view_settings.gd")
const TestShafts := preload("res://tests/test_shafts.gd")

const UNIT := 500


## The verdict for dragging a local shaft from floor `bottom` to `top` with its left edge at x.
static func _shaft_verdict(t: TowerSim, bottom: int, top: int, x: int) -> Dictionary:
	return Ghost.evaluate(t, "local_shaft", top, x, 5, "", {"start_floor": bottom, "start_column": x + 2})


## Sends the verdict's commands as a click would, and runs the ticks that apply them.
static func _click(t: TowerSim, tool_id: String, verdict: Dictionary) -> void:
	for command: Command in Ghost.commands_for(tool_id, verdict, t.tick):
		t.enqueue(command)
	t.step()
	t.step()


## A tall tower with the ground floor built across columns 100 to 199, so floor above it has support.
static func _ground() -> TowerSim:
	var t := TestShafts._tall()
	t.floors.fill_span(1, 132, 199)
	return t


static func run(check: Callable) -> void:
	var was_on := ViewSettings.auto_fill
	ViewSettings.auto_fill = true

	# A shaft 3 cells off the lobby: floor fills in on every floor it stops at.
	var t := TestShafts._tall()
	var base := _shaft_verdict(t, 1, 3, 135)
	var fills: Array = base.get("fill", [])
	check.call(base["valid"] and fills.size() == 3 and fills[0] == [1, 132, 134] and fills[2] == [3, 132, 134], "a shaft off the tower edge plans floor on each of its floors")
	ViewSettings.auto_fill = false
	var plain := _shaft_verdict(t, 1, 3, 135)
	ViewSettings.auto_fill = true
	check.call(base["cost"] == plain["cost"] + 9 * UNIT and not plain.has("fill"), "the ghost price includes the fill, and the setting off adds nothing")
	var funds := t.ledger.balance
	_click(t, "local_shaft", base)
	check.call(t.floors.has_floor(1, 133) and t.floors.has_floor(2, 132) and t.floors.has_floor(3, 134) and t.rooms.shaft_count() == 1, "the click builds the fill and the shaft")
	check.call(funds - t.ledger.balance == base["cost"], "the ledger paid exactly the ghost price")

	# Floor on both sides: both gaps fill.
	var b := TestShafts._tall()
	for f in range(1, 4):
		b.floors.fill_span(f, 150, 160)
	var both := _shaft_verdict(b, 1, 2, 140)
	check.call(both["valid"] and (both["fill"] as Array).size() == 4, "a gap on each side fills both")
	_click(b, "local_shaft", both)
	check.call(b.floors.has_floor(2, 132) and b.floors.has_floor(2, 149) and b.floors.has_floor(1, 139), "both sides are closed after the click")

	# No other floor on the level: nothing to fill.
	var empty := TowerSim.new(1, 100000000)
	var lone := _shaft_verdict(empty, 1, 2, 200)
	check.call(lone["valid"] and not lone.has("fill"), "nothing fills when the level has no other floor")

	# A room: the gap beside it fills too, and short funds refuse it.
	var r := _ground()
	var office := Ghost.evaluate(r, "office", 2, 140, 5)
	check.call(office["valid"] and (office["fill"] as Array) == [[2, 132, 139]], "a room off the edge plans its gap")
	var poor := _ground()
	var needed: int = Ghost.evaluate(poor, "office", 2, 140, 5)["cost"]
	poor.ledger.charge(poor.tick, poor.ledger.balance - (needed - 1), 0)
	check.call(not Ghost.evaluate(poor, "office", 2, 140, 5)["valid"], "a build the fill makes unaffordable is refused")

	# Stairs on two floors: each floor's gap, the upper one resting on the lower.
	var s := _ground()
	s.floors.fill_span(2, 145, 160)
	s.floors.fill_span(3, 145, 160)
	var stairs := Ghost.evaluate(s, Ghost.STAIRS, 2, 145, 5)
	check.call(stairs["valid"] and (stairs["fill"] as Array).size() == 2, "stairs fill beside both of their floors")

	ViewSettings.auto_fill = was_on
