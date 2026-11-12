class_name Rooms
extends RefCounted
## Placed rooms (2.4). Integers only; see CLAUDE.md.
##
## A room is a grid occupant (its position lives in Grid) plus a kind, stored here as an index
## into RoomCatalogue.IDS. Only kinds in PLACEABLE can be placed for now; add a kind there once
## its rules are built. Rent and "condo sold once" (M3+) come later.
## Rules: floor 2 or higher (floor 1 is the lobby floor, basements are refused; UNVERIFIED: the
## reference only says "above ground"), no overlap with another room, the lobby or a shaft, inside
## the tower width, and every new floor unit under the room needs a floor directly below it (the
## same no-overhang rule as Floors). The room pays its price plus FLOOR_COST_PER_UNIT for each
## unit of floor under it that is not built yet, in one charge, and builds those units.

const GridScript := preload("res://scripts/sim/grid.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const LedgerScript := preload("res://scripts/sim/ledger.gd")
const FloorsScript := preload("res://scripts/sim/floors.gd")

## Result codes. OK and SHORT_OF_FUNDS match Floors' and Ledger's; 10 to 19 belong to Floors.
const OK := 0
const SHORT_OF_FUNDS := 1
const BAD_FLOOR := 10  ## Not a real floor number (same code as Floors).
const UNKNOWN_KIND := 20  ## Not a room kind that can be placed yet.
const BELOW_GROUND := 21  ## Basements take no office or condo.
const LOBBY_FLOOR := 22  ## Floor 1 is the lobby floor (unverified).
const OFF_TOWER := 23  ## The room runs off the tower's width.
const OVERLAPS_ROOM := 24  ## Another room is in the way.
const OVERLAPS_LOBBY := 25  ## The ground lobby is in the way.
const OVER_SHAFT := 26  ## A shaft is in the way.
const NOTHING_BELOW := 27  ## No new floor unit has a floor to rest on.
const OVERHANG := 28  ## Some units rest on a floor, others hang past it.
const NO_FLOOR_FOR_STAIRS := 29  ## Stairs: one of the two floors is not built under the stairs.
const NOTHING_THERE := 30  ## Bulldoze: the cell is empty (or off the tower).
const PERMANENT := 31  ## Bulldoze: the lobby or another room the player cannot remove.
const NOT_A_ROOM := 32  ## Bulldoze: the cell holds an occupant that is not a placed room.

const STAIRS_LIMIT := 34  ## Stairs: the tower already holds the most stairs and escalators.

const PLACEABLE: Array[String] = ["office", "condo"]
const FIRST_ID := 1000  ## Room occupant ids start here, clear of ids given to PLACE commands.

var _kind_of: Dictionary = {}  # occupant id -> index in RoomCatalogue.IDS
var _sold: Dictionary = {}  # condo occupant id -> true once sold (sales come in M3; tests set it)
var _next_id: int = FIRST_ID
## Stairs hold two grid occupants, one per floor: the room id (lower floor) and id + 1 (upper).
## Running total of workers and residents removed by
## bulldozing. A room holds RoomCatalogue "people" of them.
var occupants_removed: int = 0


func room_count() -> int:
	return _kind_of.size()


func has_room(id: int) -> bool:
	return _kind_of.has(id)


## Ids of every placed room, ascending.
func room_ids() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(_kind_of.keys())
	ids.sort()
	return ids


## The catalogue id ("office", "condo") of a placed room, or "" if id is not a room.
func kind_of(id: int) -> String:
	if not _kind_of.has(id):
		return ""
	return CatalogueScript.IDS[_kind_of[id]]


## Checks a placement without changing anything. Returns {"reason", "cost", "floor_units"}:
## cost is the room price plus the missing floor units; floor_units is how many it would build.
## The placement ghost (#13) uses this. kind is a catalogue id such as "office".
func check_place(grid: GridScript, floors: FloorsScript, kind: String, floor_number: int, x_left: int) -> Dictionary:
	var result := {"reason": OK, "cost": 0, "floor_units": 0}
	if not PLACEABLE.has(kind):
		result["reason"] = UNKNOWN_KIND
		return result
	if not GridScript.is_valid_floor(floor_number):
		result["reason"] = BAD_FLOOR
		return result
	if floor_number < 0:
		result["reason"] = BELOW_GROUND
		return result
	if floor_number == 1:
		result["reason"] = LOBBY_FLOOR
		return result
	var width: int = CatalogueScript.field(kind, "width")
	if x_left < 0 or x_left + width > GridScript.WIDTH_UNITS:
		result["reason"] = OFF_TOWER
		return result
	var new_units := 0
	var supported := 0
	for column in range(x_left, x_left + width):
		if grid.cell_at(floor_number, column) != GridScript.EMPTY:
			result["reason"] = OVERLAPS_ROOM
			return result
		if floors.has_lobby_at(floor_number, column):
			result["reason"] = OVERLAPS_LOBBY
			return result
		if floors.has_shaft(floor_number, column):
			result["reason"] = OVER_SHAFT
			return result
		if floors.has_floor(floor_number, column):
			continue
		new_units += 1
		if floors.has_floor(floor_number - 1, column):
			supported += 1
	if new_units > 0 and supported == 0:
		result["reason"] = NOTHING_BELOW
	elif supported < new_units:
		result["reason"] = OVERHANG
	result["floor_units"] = new_units
	result["cost"] = CatalogueScript.cost(kind) + new_units * CatalogueScript.FLOOR_COST_PER_UNIT
	return result


## Places a room by catalogue index (the PLACE_ROOM command's first arg). Returns OK or a reason
## code, and changes nothing on a refusal. One ledger charge; its ref is the catalogue index.
func place_room(grid: GridScript, floors: FloorsScript, ledger: LedgerScript, at_tick: int, kind_index: int, floor_number: int, x_left: int) -> int:
	if kind_index < 0 or kind_index >= CatalogueScript.IDS.size():
		return UNKNOWN_KIND
	var kind: String = CatalogueScript.IDS[kind_index]
	var checked := check_place(grid, floors, kind, floor_number, x_left)
	if checked["reason"] != OK:
		return checked["reason"]
	if ledger.charge(at_tick, checked["cost"], kind_index) != LedgerScript.OK:
		return SHORT_OF_FUNDS
	var width: int = CatalogueScript.field(kind, "width")
	floors.fill_span(floor_number, x_left, x_left + width - 1)
	while grid.has_occupant(_next_id):
		_next_id += 1
	grid.place(_next_id, floor_number, x_left, width)
	_kind_of[_next_id] = kind_index
	_next_id += 1
	return OK


## The floor above floor_number, or 0 when there is none (floor 100; there is no floor 0).
static func floor_above(floor_number: int) -> int:
	if floor_number == -1:
		return 1
	if floor_number == GridScript.FLOOR_MAX:
		return 0
	return floor_number + 1


## How many stairs and escalators the tower holds (they share one limit).
func _stairs_and_escalators() -> int:
	var count := 0
	for id: int in _kind_of:
		if CatalogueScript.field(kind_of(id), "limit_group") == "stairs_escalators":
			count += 1
	return count


## Checks stairs linking floor_number and the floor above, x_left being the left column. Returns
## {"reason", "cost"}. Needs a built floor (a lobby counts) under all columns on both floors, no
## shaft on either, nothing else in the way (a lobby is fine), and room under the 64 stairs and
## escalators limit. The placement ghost (#13) uses this.
func check_place_stairs(grid: GridScript, floors: FloorsScript, floor_number: int, x_left: int) -> Dictionary:
	var result := {"reason": OK, "cost": 0}
	var upper := floor_above(floor_number)
	if not GridScript.is_valid_floor(floor_number) or upper == 0:
		result["reason"] = BAD_FLOOR
		return result
	var width: int = CatalogueScript.field("stairs", "width")
	if x_left < 0 or x_left + width > GridScript.WIDTH_UNITS:
		result["reason"] = OFF_TOWER
		return result
	for column in range(x_left, x_left + width):
		for level: int in [floor_number, upper]:
			if grid.cell_at(level, column) != GridScript.EMPTY:
				result["reason"] = OVERLAPS_ROOM
				return result
			if floors.has_shaft(level, column):
				result["reason"] = OVER_SHAFT
				return result
	for column in range(x_left, x_left + width):
		if not floors.has_floor(floor_number, column) or not floors.has_floor(upper, column):
			result["reason"] = NO_FLOOR_FOR_STAIRS
			return result
	if _stairs_and_escalators() >= int(CatalogueScript.field("stairs", "limit")):
		result["reason"] = STAIRS_LIMIT
		return result
	result["cost"] = CatalogueScript.cost("stairs")
	return result


## Places stairs (the PLACE_STAIRS command): args are the lower floor and the left column. One
## ledger charge, ref = the catalogue index of "stairs". Returns OK or a reason code.
func place_stairs(grid: GridScript, floors: FloorsScript, ledger: LedgerScript, at_tick: int, floor_number: int, x_left: int) -> int:
	var checked := check_place_stairs(grid, floors, floor_number, x_left)
	if checked["reason"] != OK:
		return checked["reason"]
	var kind_index: int = CatalogueScript.IDS.find("stairs")
	if ledger.charge(at_tick, checked["cost"], kind_index) != LedgerScript.OK:
		return SHORT_OF_FUNDS
	var width: int = CatalogueScript.field("stairs", "width")
	while grid.has_occupant(_next_id) or grid.has_occupant(_next_id + 1):
		_next_id += 1
	grid.place(_next_id, floor_number, x_left, width)
	grid.place(_next_id + 1, floor_above(floor_number), x_left, width)
	_kind_of[_next_id] = kind_index
	_next_id += 2
	return OK


## True when id is the upper-floor half of a stairs (not a room of its own).
func is_stairs_upper(id: int) -> bool:
	return not _kind_of.has(id) and kind_of(id - 1) == "stairs"


## Marks a room sold (or not). Only a condo can be sold; returns false otherwise. Sales
## themselves come in M3; this lets tests and later code set the flag.
func set_sold(id: int, sold: bool) -> bool:
	if kind_of(id) != "condo":
		return false
	if sold:
		_sold[id] = true
	else:
		_sold.erase(id)
	return true


func is_sold(id: int) -> bool:
	return _sold.has(id)


## Workers or residents a room holds when full (the catalogue's "people"; tenancy fills it).
func people_in(id: int) -> int:
	var kind := kind_of(id)
	if kind == "":
		return 0
	return int(CatalogueScript.row(kind).get("people", 0))


## Checks a bulldoze without changing anything. Returns {"reason", "refund", "room_id",
## "occupants"}: refund is what a sold condo pays back to its buyer (0 otherwise). The ghost (#13)
## uses this.
func check_bulldoze(grid: GridScript, floors: FloorsScript, floor_number: int, x: int) -> Dictionary:
	var result := {"reason": OK, "refund": 0, "room_id": 0, "occupants": 0}
	if not GridScript.is_valid_floor(floor_number):
		result["reason"] = BAD_FLOOR
		return result
	var id := grid.cell_at(floor_number, x)
	if id == GridScript.EMPTY:
		# Stairs can stand inside a lobby, so only an empty lobby cell is the lobby itself.
		result["reason"] = PERMANENT if floors.has_lobby_at(floor_number, x) else NOTHING_THERE
		return result
	if is_stairs_upper(id):
		id -= 1
	if not _kind_of.has(id):
		result["reason"] = NOT_A_ROOM
		return result
	var kind := kind_of(id)
	if not CatalogueScript.field(kind, "removable"):
		result["reason"] = PERMANENT
		return result
	result["room_id"] = id
	result["occupants"] = people_in(id)
	if _sold.has(id):
		result["refund"] = CatalogueScript.cost(kind)
	return result


## Removes the room covering the cell, free. Its occupants go (counted in occupants_removed), and
## a sold condo pays its sale price back as a PAYOUT ledger line, even into a negative balance.
## The floor units under the room stay, so a room stacked above keeps its support. Returns OK or
## a reason code, changing nothing on a refusal.
func bulldoze(grid: GridScript, floors: FloorsScript, ledger: LedgerScript, at_tick: int, floor_number: int, x: int) -> int:
	var checked := check_bulldoze(grid, floors, floor_number, x)
	if checked["reason"] != OK:
		return checked["reason"]
	var id: int = checked["room_id"]
	occupants_removed += checked["occupants"]
	if checked["refund"] > 0:
		ledger.payout(at_tick, checked["refund"], id)
	grid.remove(id)
	if kind_of(id) == "stairs":
		grid.remove(id + 1)
	_kind_of.erase(id)
	_sold.erase(id)
	return OK


## Checks a replace without changing anything: the room covering (floor_number, x_left) goes and
## a new room of kind (a catalogue id) takes its place with its left edge at x_left. Returns
## {"reason", "cost", "refund", "net", "room_id", "floor_units"}: cost is the new room's price plus
## missing floor units, refund is a sold condo's payback, and net is cost + refund, the one amount
## the replace charges. The new placement is judged on a copy of the grid with the old room gone.
func check_replace(grid: GridScript, floors: FloorsScript, balance: int, kind: String, floor_number: int, x_left: int) -> Dictionary:
	var result := {"reason": OK, "cost": 0, "refund": 0, "net": 0, "room_id": 0, "floor_units": 0}
	var removal := check_bulldoze(grid, floors, floor_number, x_left)
	if removal["reason"] != OK:
		result["reason"] = removal["reason"]
		return result
	var id: int = removal["room_id"]
	result["room_id"] = id
	result["refund"] = removal["refund"]
	var after: GridScript = GridScript.new()
	after.load_ints(grid.state_ints())
	after.remove(id)
	if kind_of(id) == "stairs":
		after.remove(id + 1)
	var placed := check_place(after, floors, kind, floor_number, x_left)
	result["cost"] = placed["cost"]
	result["floor_units"] = placed["floor_units"]
	result["net"] = placed["cost"] + removal["refund"]
	if placed["reason"] != OK:
		result["reason"] = placed["reason"]
	elif result["net"] > balance:
		result["reason"] = SHORT_OF_FUNDS
	return result


## Replaces a room in one step (the REPLACE_ROOM command): bulldoze the room covering
## (floor_number, x_left), then place kind_index there. All or nothing: on any refusal the old room
## stays and money is unchanged. The sold-condo payback and the new cost are one CHARGE line.
func replace_room(grid: GridScript, floors: FloorsScript, ledger: LedgerScript, at_tick: int, kind_index: int, floor_number: int, x_left: int) -> int:
	if kind_index < 0 or kind_index >= CatalogueScript.IDS.size():
		return UNKNOWN_KIND
	var kind: String = CatalogueScript.IDS[kind_index]
	var checked := check_replace(grid, floors, ledger.balance, kind, floor_number, x_left)
	if checked["reason"] != OK:
		return checked["reason"]
	var id: int = checked["room_id"]
	if ledger.charge(at_tick, checked["net"], kind_index) != LedgerScript.OK:
		return SHORT_OF_FUNDS
	occupants_removed += people_in(id)
	grid.remove(id)
	if kind_of(id) == "stairs":
		grid.remove(id + 1)
	_kind_of.erase(id)
	_sold.erase(id)
	var width: int = CatalogueScript.field(kind, "width")
	floors.fill_span(floor_number, x_left, x_left + width - 1)
	while grid.has_occupant(_next_id):
		_next_id += 1
	grid.place(_next_id, floor_number, x_left, width)
	_kind_of[_next_id] = kind_index
	_next_id += 1
	return OK


## Flat ints for hashing and saving: next id, count, then (id, kind index, sold) triples ordered
## by id, then occupants_removed.
func state_ints() -> Array[int]:
	var ids: Array = _kind_of.keys()
	ids.sort()
	var ints: Array[int] = [_next_id, ids.size()]
	for id: int in ids:
		ints.append_array([id, _kind_of[id], 1 if _sold.has(id) else 0] as Array[int])
	ints.append(occupants_removed)
	return ints


## Restores state_ints(). Returns false, changing nothing, for data that is not valid.
func load_ints(ints: Array) -> bool:
	if not valid_ints(ints, null):
		return false
	_kind_of = {}
	_sold = {}
	for i in range(ints[1]):
		_kind_of[ints[2 + 3 * i]] = ints[3 + 3 * i]
		if ints[4 + 3 * i] == 1:
			_sold[ints[2 + 3 * i]] = true
	occupants_removed = ints[2 + 3 * ints[1]]
	_next_id = ints[0]
	return true


## True when ints is a valid state_ints() result. With a grid, every room must be placed in it.
static func valid_ints(ints: Array, grid: GridScript) -> bool:
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	if ints.size() < 2 or ints[1] < 0 or ints.size() != 3 + 3 * ints[1] or ints[0] < 1 or ints[2 + 3 * ints[1]] < 0:
		return false
	for i in range(ints[1]):
		var id: int = ints[2 + 3 * i]
		var kind_index: int = ints[3 + 3 * i]
		var sold: int = ints[4 + 3 * i]
		if id < 1 or kind_index < 0 or kind_index >= CatalogueScript.IDS.size() or (sold != 0 and sold != 1):
			return false
		if grid != null and not grid.has_occupant(id):
			return false
		if grid != null and kind_index == CatalogueScript.IDS.find("stairs") and not grid.has_occupant(id + 1):
			return false
	return true
