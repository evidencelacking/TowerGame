extends RefCounted
## Floor tests (2.3): $500 a unit, support below, shafts, funds, determinism.

const Harness := preload("res://tests/harness.gd")
const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const FloorsScript := preload("res://scripts/sim/floors.gd")
const LedgerScript := preload("res://scripts/sim/ledger.gd")


## Builds a span through the command queue and returns the result code.
static func _build(tower: TowerSim, floor_number: int, x_start: int, x_end: int) -> int:
	Harness.queue_all(tower, [Command.make(tower.tick + 1, Command.BUILD_FLOOR, [floor_number, x_start, x_end])])
	tower.step()
	return tower.last_refusal


static func run(check: Callable) -> void:
	var tower := Harness.make(1)
	var start_funds := tower.ledger.balance
	var empty_hash := tower.state_hash()
	check.call(_build(tower, 1, 10, 19) == FloorsScript.OK, "floor 1 builds on the ground")
	check.call(start_funds - tower.ledger.balance == 10 * 500, "a 10-unit span costs exactly $5,000")
	check.call(tower.floors.has_floor(1, 10) and tower.floors.has_floor(1, 19) and not tower.floors.has_floor(1, 20), "the span is inclusive at both ends")

	# Wider than below, and nothing under it.
	check.call(_build(tower, 2, 15, 25) == FloorsScript.WIDER_THAN_BELOW, "a floor wider than the one below is refused")
	check.call(_build(tower, 2, 30, 35) == FloorsScript.NOTHING_BELOW, "a floor with nothing under it is refused")
	check.call(_build(tower, 3, 10, 12) == FloorsScript.NOTHING_BELOW, "floor 3 needs floor 2 under it")
	check.call(tower.ledger.balance == start_funds - 5000, "refused spans charge nothing")
	check.call(_build(tower, 2, 12, 17) == FloorsScript.OK and tower.floors.has_floor(2, 12), "a narrower floor above is allowed")

	# Only new units are charged.
	var funds := tower.ledger.balance
	check.call(_build(tower, 1, 5, 24) == FloorsScript.OK, "a span over an existing floor builds")
	check.call(funds - tower.ledger.balance == 10 * 500, "only the 10 new units of a 20-unit span are charged")
	funds = tower.ledger.balance
	check.call(_build(tower, 1, 5, 24) == FloorsScript.ALREADY_BUILT and tower.ledger.balance == funds, "a fully built span is refused and free")

	# Basements (unverified rule: each unit needs the floor above it).
	check.call(_build(tower, -1, 10, 12) == FloorsScript.OK, "B1 builds under floor 1")
	check.call(_build(tower, -2, 10, 13) == FloorsScript.WIDER_THAN_BELOW, "B2 cannot be wider than B1")
	check.call(_build(tower, -3, 10, 12) == FloorsScript.NOTHING_BELOW, "B3 needs B2 above it")
	check.call(_build(tower, -1, 200, 202) == FloorsScript.NOTHING_BELOW, "B1 needs floor 1 above it")

	# Bad input.
	check.call(_build(tower, 0, 1, 2) == FloorsScript.BAD_FLOOR, "floor 0 does not exist")
	check.call(_build(tower, 101, 1, 2) == FloorsScript.BAD_FLOOR, "floor 101 does not exist")
	check.call(_build(tower, 1, 9, 5) == FloorsScript.BAD_SPAN, "a span that ends before it starts is refused")
	check.call(_build(tower, 1, 390, 400) == FloorsScript.BAD_SPAN, "a span off the width is refused")

	# Shafts.
	check.call(tower.floors.mark_shaft(1, 30), "a shaft can be marked")
	check.call(_build(tower, 1, 28, 32) == FloorsScript.OVER_SHAFT and not tower.floors.has_floor(1, 28), "a floor over a shaft is refused and builds nothing")
	check.call(_build(tower, 1, 31, 33) == FloorsScript.OK, "a floor beside a shaft is allowed")

	# Funds.
	var poor := TowerSim.new(1, 2499)
	check.call(_build(poor, 1, 0, 4) == FloorsScript.SHORT_OF_FUNDS, "a span over the balance is refused for funds")
	check.call(poor.ledger.balance == 2499 and not poor.floors.has_floor(1, 0) and poor.ledger.lines.size() == 1, "a funds refusal changes nothing")
	var exact := TowerSim.new(1, 2500)
	check.call(_build(exact, 1, 0, 4) == FloorsScript.OK and exact.ledger.balance == 0, "an exact-balance span succeeds")
	check.call(exact.ledger.balance == exact.ledger.line_sum(), "the ledger still sums to the balance")

	# Preview, save and determinism.
	var preview := tower.floors.check_span(2, 12, 28)
	check.call(preview["reason"] == FloorsScript.WIDER_THAN_BELOW and preview["new_units"] == 11 and preview["cost"] == 5500, "check_span previews reason, new units and cost")
	check.call(tower.state_hash() != empty_hash, "building floors changes the state hash")
	var loaded := TowerSim.new(0)
	check.call(loaded.load_state(tower.save()) and loaded.state_hash() == tower.state_hash() and loaded.floors.has_shaft(1, 30), "floors and shafts survive save and load")
	var bad := tower.save()
	bad["floors"] = [1, 1, 3, 5, 99999]
	check.call(not TowerSim.new(0).load_state(bad), "a save with out-of-range floor runs is refused")
	var script: Array[Command] = [
		Command.make(1, Command.BUILD_FLOOR, [1, 0, 30]),
		Command.make(2, Command.BUILD_FLOOR, [2, 5, 20]),
		Command.make(3, Command.BUILD_FLOOR, [2, 5, 40]),
	]
	var run_a := Harness.run_script(7, script, 4)
	var run_b := Harness.run_script(7, script, 4)
	check.call(run_a == run_b, "the same floor commands give the same hash trace")
