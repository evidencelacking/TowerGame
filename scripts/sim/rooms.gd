class_name Rooms
extends RefCounted
## Placed rooms (2.4). Integers only; see CLAUDE.md.
##
## A room is a grid occupant (its position lives in Grid) plus a kind, stored here as an index
## into RoomCatalogue.IDS. Only kinds in PLACEABLE can be placed for now; add a kind there once
## its rules are built. Population, rent and "condo sold once" (M3+) come later.
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

const PLACEABLE: Array[String] = ["office", "condo"]
const FIRST_ID := 1000  ## Room occupant ids start here, clear of ids given to PLACE commands.

var _kind_of: Dictionary = {}  # occupant id -> index in RoomCatalogue.IDS
var _next_id: int = FIRST_ID


func room_count() -> int:
	return _kind_of.size()


func has_room(id: int) -> bool:
	return _kind_of.has(id)


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


## Flat ints for hashing and saving: next id, count, then (id, kind index) pairs ordered by id.
func state_ints() -> Array[int]:
	var ids: Array = _kind_of.keys()
	ids.sort()
	var ints: Array[int] = [_next_id, ids.size()]
	for id: int in ids:
		ints.append_array([id, _kind_of[id]] as Array[int])
	return ints


## Restores state_ints(). Returns false, changing nothing, for data that is not valid.
func load_ints(ints: Array) -> bool:
	if not valid_ints(ints, null):
		return false
	_kind_of = {}
	for i in range(ints[1]):
		_kind_of[ints[2 + 2 * i]] = ints[3 + 2 * i]
	_next_id = ints[0]
	return true


## True when ints is a valid state_ints() result. With a grid, every room must be placed in it.
static func valid_ints(ints: Array, grid: GridScript) -> bool:
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	if ints.size() < 2 or ints[1] < 0 or ints.size() != 2 + 2 * ints[1] or ints[0] < 1:
		return false
	for i in range(ints[1]):
		var id: int = ints[2 + 2 * i]
		var kind_index: int = ints[3 + 2 * i]
		if id < 1 or kind_index < 0 or kind_index >= CatalogueScript.IDS.size():
			return false
		if grid != null and not grid.has_occupant(id):
			return false
	return true
