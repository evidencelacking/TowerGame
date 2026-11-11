extends RefCounted
## Bulldoze tests (2.6): free, refuses permanent rooms, removes occupants, pays back sold condos.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const LedgerScript := preload("res://scripts/sim/ledger.gd")
const TestRooms := preload("res://tests/test_rooms.gd")


## A tower with a ground lobby at columns 100 to 131, wide enough to carry a condo (16 units) on floor 2.
static func _wide() -> TowerSim:
	var tower := TowerSim.new(1, 2000000)
	TestRooms._send(tower, Command.BUILD_LOBBY, [1, 100, 131, 1] as Array[int])
	return tower


static func _dozer(tower: TowerSim, floor_number: int, x: int) -> int:
	return TestRooms._send(tower, Command.BULLDOZE, [floor_number, x] as Array[int])


static func _sum_ok(tower: TowerSim) -> bool:
	return tower.ledger.balance == tower.ledger.line_sum()


static func run(check: Callable) -> void:
	var t := _wide()
	# Lobby and empty cells are refused, free.
	var funds := t.ledger.balance
	check.call(_dozer(t, 1, 104) == RoomsScript.PERMANENT, "bulldozing the lobby is refused")
	check.call(t.floors.has_lobby_at(1, 104), "the lobby is still there")
	check.call(_dozer(t, 5, 104) == RoomsScript.NOTHING_THERE, "bulldozing an empty cell is refused")
	check.call(_dozer(t, 500, 104) == RoomsScript.BAD_FLOOR, "bulldozing a bad floor is refused")
	check.call(t.ledger.balance == funds and t.rooms.occupants_removed == 0, "refusals change nothing")

	# Office: free, workers gone, floor stays.
	check.call(TestRooms._room(t, TestRooms.OFFICE, 2, 100) == RoomsScript.OK, "an office is placed")
	var office_id := t.grid.cell_at(2, 100)
	var preview := t.rooms.check_bulldoze(t.grid, t.floors, 2, 104)
	check.call(preview["reason"] == RoomsScript.OK and preview["refund"] == 0 and preview["occupants"] == 6, "the preview shows 6 workers and no refund")
	var balance := t.ledger.balance
	var lines := t.ledger.lines.size()
	check.call(_dozer(t, 2, 104) == RoomsScript.OK, "an office is bulldozed")
	check.call(t.ledger.balance == balance and t.ledger.lines.size() == lines, "bulldozing an office is free")
	check.call(t.rooms.occupants_removed == 6, "the office's 6 workers are gone")
	check.call(t.rooms.room_count() == 0 and not t.grid.has_occupant(office_id) and t.grid.cell_at(2, 100) == 0, "the office is removed from the grid")
	check.call(t.floors.has_floor(2, 100) and t.floors.has_floor(2, 108), "the floor units under it stay")
	check.call(_dozer(t, 2, 104) == RoomsScript.NOTHING_THERE, "the cell is empty after")

	# A room stacked on top keeps its support after the room below goes.
	check.call(TestRooms._room(t, TestRooms.OFFICE, 2, 100) == RoomsScript.OK, "an office is placed again")
	check.call(TestRooms._room(t, TestRooms.OFFICE, 3, 100) == RoomsScript.OK, "one is stacked above it")
	check.call(_dozer(t, 2, 100) == RoomsScript.OK, "the lower office is bulldozed")
	check.call(t.floors.has_floor(2, 100) and t.floors.has_floor(3, 100) and t.rooms.room_count() == 1, "the upper office keeps its floor")
	var rebuild := t.ledger.balance
	check.call(TestRooms._room(t, TestRooms.OFFICE, 2, 100) == RoomsScript.OK and t.ledger.balance == rebuild - 40000, "a room is rebuilt on the kept floor for its price alone")

	# Condo: an unsold condo pays nothing, a sold one pays back $80,000.
	var c := _wide()
	check.call(TestRooms._room(c, TestRooms.CONDO, 2, 100) == RoomsScript.OK, "a condo is placed")
	var unsold := c.ledger.balance
	check.call(_dozer(c, 2, 100) == RoomsScript.OK and c.ledger.balance == unsold, "an unsold condo pays nothing back")
	check.call(c.rooms.occupants_removed == 3, "the condo's 3 residents are gone")
	check.call(TestRooms._room(c, TestRooms.CONDO, 2, 100) == RoomsScript.OK, "a condo is placed again")
	var condo_id := c.grid.cell_at(2, 100)
	check.call(c.rooms.set_sold(condo_id, true) and c.rooms.is_sold(condo_id), "a condo can be marked sold")
	check.call(not c.rooms.set_sold(999999, true), "a non-room cannot be marked sold")
	check.call(c.rooms.check_bulldoze(c.grid, c.floors, 2, 100)["refund"] == 80000, "the preview shows the $80,000 refund")
	var h_sold := c.state_hash()
	var saved := c.save()
	var after_place := c.ledger.balance
	check.call(_dozer(c, 2, 100) == RoomsScript.OK, "a sold condo is bulldozed")
	check.call(c.ledger.balance == after_place - 80000, "the sale price is paid out")
	check.call(c.ledger.lines[c.ledger.lines.size() - 1][2] == LedgerScript.PAYOUT and _sum_ok(c), "the payout is a PAYOUT line and the balance matches the lines")
	check.call(c.state_hash() != h_sold, "bulldozing changes the hash")
	var restored := TowerSim.new(0)
	check.call(restored.load_state(saved) and restored.rooms.is_sold(condo_id) and restored.state_hash() == h_sold, "the sold flag saves and loads")

	# Into the red: a sold condo can take the balance below zero, never refused.
	var poor := _wide()
	check.call(TestRooms._room(poor, TestRooms.CONDO, 2, 100) == RoomsScript.OK, "a condo is placed")
	poor.rooms.set_sold(poor.grid.cell_at(2, 100), true)
	var drain := 50000 - poor.ledger.balance
	TestRooms._send(poor, Command.REFUND, [drain, 0] as Array[int])
	check.call(poor.ledger.balance == 50000, "funds are down to $50,000")
	check.call(_dozer(poor, 2, 100) == RoomsScript.OK and poor.ledger.balance == -30000 and _sum_ok(poor), "the refund takes the balance to -$30,000")

	# Determinism and save/load after a bulldoze.
	var a := _wide()
	var b := _wide()
	for tower: TowerSim in [a, b]:
		check.call(TestRooms._room(tower, TestRooms.OFFICE, 2, 100) == RoomsScript.OK, "office placed")
		check.call(TestRooms._room(tower, TestRooms.CONDO, 2, 110) == RoomsScript.OK, "condo placed")
		check.call(_dozer(tower, 2, 100) == RoomsScript.OK, "office bulldozed")
	check.call(a.state_hash() == b.state_hash(), "bulldoze is deterministic")
	var copy := TowerSim.new(0)
	check.call(copy.load_state(a.save()) and copy.state_hash() == a.state_hash() and copy.rooms.occupants_removed == 6 and copy.rooms.room_count() == 1, "a bulldozed tower saves and loads")
