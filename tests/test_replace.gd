extends RefCounted
## Replace tests (2.7): bulldoze and place as one atomic command with one ledger step.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const LedgerScript := preload("res://scripts/sim/ledger.gd")
const TestRooms := preload("res://tests/test_rooms.gd")
const TestBulldoze := preload("res://tests/test_bulldoze.gd")


static func _replace(tower: TowerSim, kind_index: int, floor_number: int, x_left: int) -> int:
	return TestRooms._send(tower, Command.REPLACE_ROOM, [kind_index, floor_number, x_left] as Array[int])


static func run(check: Callable) -> void:
	# Office to condo: one charge for the condo and the new floor units, the old room gone.
	var t := TestBulldoze._wide()
	check.call(TestRooms._room(t, TestRooms.OFFICE, 2, 100) == RoomsScript.OK, "an office is placed")
	var old_id := t.grid.cell_at(2, 100)
	var preview := t.rooms.check_replace(t.grid, t.floors, t.ledger.balance, "condo", 2, 100)
	check.call(preview["reason"] == RoomsScript.OK and preview["room_id"] == old_id, "the preview accepts office to condo")
	check.call(preview["net"] == preview["cost"] and preview["cost"] > 80000 and preview["floor_units"] == 7, "the preview shows the condo cost and 7 new floor units")
	check.call(t.grid.cell_at(2, 100) == old_id and t.grid.run_of(old_id)[2] == 9, "the preview changes nothing")
	var balance := t.ledger.balance
	var lines := t.ledger.lines.size()
	check.call(_replace(t, TestRooms.CONDO, 2, 100) == RoomsScript.OK, "the office is replaced by a condo")
	check.call(t.ledger.balance == balance - preview["net"] and t.ledger.lines.size() == lines + 1, "money drops by the net cost in one ledger line")
	check.call(TestBulldoze._sum_ok(t), "the balance matches the lines")
	check.call(not t.grid.has_occupant(old_id) and t.rooms.room_count() == 1 and t.rooms.kind_of(t.grid.cell_at(2, 100)) == "condo", "the condo stands where the office was")
	check.call(t.grid.run_of(t.grid.cell_at(2, 100))[2] == 16 and t.floors.has_floor(2, 115), "the condo is 16 wide on a built floor")
	check.call(t.rooms.occupants_removed == 6, "the office's workers are counted as removed")

	# A sold condo: the payback and the new cost net in ONE line.
	var s := TestBulldoze._wide()
	check.call(TestRooms._room(s, TestRooms.CONDO, 2, 100) == RoomsScript.OK, "a condo is placed")
	s.rooms.set_sold(s.grid.cell_at(2, 100), true)
	var sp := s.rooms.check_replace(s.grid, s.floors, s.ledger.balance, "office", 2, 100)
	check.call(sp["refund"] == 80000 and sp["cost"] == 40000 and sp["net"] == 120000, "the preview nets the refund and the new cost to $120,000")
	var before := s.ledger.balance
	var n := s.ledger.lines.size()
	check.call(_replace(s, TestRooms.OFFICE, 2, 100) == RoomsScript.OK, "a sold condo is replaced by an office")
	check.call(s.ledger.balance == before - 120000 and s.ledger.lines.size() == n + 1 and TestBulldoze._sum_ok(s), "one $120,000 line is charged")
	check.call(s.rooms.kind_of(s.grid.cell_at(2, 100)) == "office" and not s.rooms.is_sold(s.grid.cell_at(2, 100)), "an unsold office stands there")

	# Refusal leaves everything alone: a wider room hitting a neighbour.
	var w := TestBulldoze._wide()
	check.call(TestRooms._room(w, TestRooms.OFFICE, 2, 100) == RoomsScript.OK, "an office is placed")
	check.call(TestRooms._room(w, TestRooms.OFFICE, 2, 109) == RoomsScript.OK, "a neighbour is placed beside it")
	var w_id := w.grid.cell_at(2, 100)
	var w_balance := w.ledger.balance
	var w_prev := w.rooms.check_replace(w.grid, w.floors, w.ledger.balance, "condo", 2, 100)
	check.call(w_prev["reason"] == RoomsScript.OVERLAPS_ROOM, "the preview reports the overlap")
	check.call(_replace(w, TestRooms.CONDO, 2, 100) == RoomsScript.OVERLAPS_ROOM, "a wider room over a neighbour is refused")
	check.call(w.grid.has_occupant(w_id) and w.grid.cell_at(2, 100) == w_id and w.ledger.balance == w_balance and w.rooms.room_count() == 2, "the old room stays and money is unchanged")
	check.call(w.rooms.occupants_removed == 0, "no occupants are removed")

	# Unaffordable: the old room stays.
	var p := TestBulldoze._wide()
	check.call(TestRooms._room(p, TestRooms.OFFICE, 2, 100) == RoomsScript.OK, "an office is placed")
	var drain := p.ledger.balance - 50000
	TestRooms._send(p, Command.REFUND, [-drain, 0] as Array[int])
	check.call(p.ledger.balance == 50000, "funds are down to $50,000")
	var p_id := p.grid.cell_at(2, 100)
	check.call(_replace(p, TestRooms.CONDO, 2, 100) == RoomsScript.SHORT_OF_FUNDS, "an unaffordable replace is refused")
	check.call(p.grid.cell_at(2, 100) == p_id and p.ledger.balance == 50000 and p.rooms.room_count() == 1, "the old room stays and money is unchanged")
	check.call(p.rooms.check_replace(p.grid, p.floors, 50000, "condo", 2, 100)["reason"] == RoomsScript.SHORT_OF_FUNDS, "the preview reports short of funds")

	# Permanent, empty, bad inputs.
	var q := TestBulldoze._wide()
	check.call(_replace(q, TestRooms.OFFICE, 1, 104) == RoomsScript.PERMANENT, "the lobby cannot be replaced")
	check.call(_replace(q, TestRooms.OFFICE, 5, 104) == RoomsScript.NOTHING_THERE, "an empty cell cannot be replaced")
	check.call(TestRooms._room(q, TestRooms.OFFICE, 2, 100) == RoomsScript.OK, "an office is placed")
	var q_after := q.ledger.balance
	check.call(_replace(q, 0, 2, 100) == RoomsScript.UNKNOWN_KIND, "the lobby is not a replacement kind")
	check.call(_replace(q, 99, 2, 100) == RoomsScript.UNKNOWN_KIND, "a bad kind index is refused")
	check.call(q.rooms.room_count() == 1 and q.ledger.balance == q_after, "refusals change nothing")

	# Determinism and save/load.
	var a := TestBulldoze._wide()
	var b := TestBulldoze._wide()
	for tower: TowerSim in [a, b]:
		TestRooms._room(tower, TestRooms.OFFICE, 2, 100)
		_replace(tower, TestRooms.CONDO, 2, 100)
	check.call(a.state_hash() == b.state_hash(), "replace is deterministic")
	var copy := TowerSim.new(0)
	check.call(copy.load_state(a.save()) and copy.state_hash() == a.state_hash(), "a replaced tower saves and loads")
