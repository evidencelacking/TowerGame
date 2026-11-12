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
const CarsScript := preload("res://scripts/sim/cars.gd")
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
const MAX_SHAFT_FLOORS := 40  ## Shaft: spans more than 30 floors (basements count; express is exempt).
const MAX_SHAFTS := 41  ## Shaft: the tower already holds 24 shafts.
const NO_FLOOR_FOR_SHAFT := 42  ## Shaft: some floor it spans is not built under the shaft.
const BAD_SHAFT_SPAN := 43  ## Shaft: the top is not above the bottom.

const NOT_IN_SHAFT := 44  ## Shaft stop: the floor is not in the shaft's span (or the shaft is unknown).

const MAX_CARS := 45  ## Car: the shaft already holds MAX_CARS_PER_SHAFT cars.
const STAR_CAR_CAP := 46  ## Car: the tower's star rating allows no more cars in the shaft.
const BAD_HOME_FLOOR := 47  ## Car: the home floor is outside the shaft's span or is not a stop.
const NO_CARS_HERE := 48  ## Car: only local and service shafts take cars (so far).
const HOME_DROPPED := 49  ## Shaft resize: the new span would drop a car's home floor.
const HOME_STOP := 50  ## Shaft stop: the floor is a car's home floor, which must stay a stop.
const NOT_A_STOP := 51  ## Send car: the target is not a stop of the car's shaft.
const NO_SUCH_CAR := 52  ## Send car: there is no such car.

const MAX_CARS_PER_SHAFT := 8  ## Cars in one shaft (reference).
const CAR_CAPACITY := 17  ## People a local car holds (reference); #94 enforces it.
## Cars allowed per shaft by star rating, index = stars - 1 (a guess, tunable).
const CARS_BY_STAR: Array[int] = [2, 4, 8, 8, 8]
const SHAFT_FLOOR_LIMIT := 30  ## Local and service shafts span at most this many floors (I, K).

const PLACEABLE: Array[String] = ["office", "condo"]
const FIRST_ID := 1000  ## Room occupant ids start here, clear of ids given to PLACE commands.

var _kind_of: Dictionary = {}  # occupant id -> index in RoomCatalogue.IDS
var _sold: Dictionary = {}  # condo occupant id -> true once sold (sales come in M3; tests set it)
var _next_id: int = FIRST_ID
## Stairs hold two grid occupants, one per floor: the room id (lower floor) and id + 1 (upper).
## Running total of workers and residents removed by
## bulldozing. A room holds RoomCatalogue "people" of them.
var occupants_removed: int = 0
## Shafts hold one grid occupant per floor, ids base .. base + span - 1 from the bottom up.
var _shafts: Dictionary = {}  # shaft id (stable) -> [span, bottom floor, x_left, stops off (floors, ascending), first grid occupant id]
var _cars: Array = []  # [shaft id, home, floor, load, state, dir, target, ticks left], oldest first (see cars.gd)


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


## Index of a floor counting upward with no floor 0, so spans count basements: B1 is -1, 1 is 0.
static func _level(floor_number: int) -> int:
	return floor_number if floor_number < 0 else floor_number - 1


## Floors a shaft from bottom to top covers (inclusive; basements count), or 0 if top is not above.
static func shaft_span(bottom: int, top: int) -> int:
	if not GridScript.is_valid_floor(bottom) or not GridScript.is_valid_floor(top):
		return 0
	return maxi(0, _level(top) - _level(bottom) + 1)


func shaft_count() -> int:
	return _shafts.size()


## Shaft id owning grid occupant id, or 0 if it is not a shaft cell.
func _shaft_base(id: int) -> int:
	for shaft: int in _shafts:
		var first: int = _shafts[shaft][4]
		if id >= first and id < first + int(_shafts[shaft][0]):
			return shaft
	return 0


## Checks a shaft: kind is a catalogue id with the shaft placement, bottom and top are floor
## numbers (inclusive). Returns {"reason", "cost", "span"}. Needs 1 to 30 floors (express: any
## height), fewer than 24 shafts, a built floor under every column on every floor, and nothing
## else in the way (a lobby is fine, as for stairs).
func check_place_shaft(grid: GridScript, floors: FloorsScript, kind: String, bottom: int, top: int, x_left: int) -> Dictionary:
	var result := {"reason": OK, "cost": 0, "span": 0}
	if not CatalogueScript.IDS.has(kind) or CatalogueScript.field(kind, "placement") != CatalogueScript.PLACE_SHAFT:
		result["reason"] = UNKNOWN_KIND
		return result
	if not GridScript.is_valid_floor(bottom) or not GridScript.is_valid_floor(top):
		result["reason"] = BAD_FLOOR
		return result
	var span := shaft_span(bottom, top)
	result["span"] = span
	if span == 0:
		result["reason"] = BAD_SHAFT_SPAN
		return result
	if kind != "express_shaft" and span > SHAFT_FLOOR_LIMIT:
		result["reason"] = MAX_SHAFT_FLOORS
		return result
	if _shafts.size() >= int(CatalogueScript.field(kind, "limit")):
		result["reason"] = MAX_SHAFTS
		return result
	var width: int = CatalogueScript.field(kind, "width")
	if x_left < 0 or x_left + width > GridScript.WIDTH_UNITS:
		result["reason"] = OFF_TOWER
		return result
	var level := bottom
	for i in span:
		for column in range(x_left, x_left + width):
			if grid.cell_at(level, column) != GridScript.EMPTY:
				result["reason"] = OVERLAPS_ROOM
				return result
			if floors.has_shaft(level, column):
				result["reason"] = OVER_SHAFT
				return result
		level = floor_above(level)
	level = bottom
	for i in span:
		for column in range(x_left, x_left + width):
			if not floors.has_floor(level, column):
				result["reason"] = NO_FLOOR_FOR_SHAFT
				return result
		level = floor_above(level)
	result["cost"] = CatalogueScript.cost(kind)
	return result


## Places a shaft (the PLACE_SHAFT command): kind_index, bottom, top, x_left. One ledger charge
## (the catalogue price, however tall), ref = the catalogue index. Returns OK or a reason code.
func place_shaft(grid: GridScript, floors: FloorsScript, ledger: LedgerScript, at_tick: int, kind_index: int, bottom: int, top: int, x_left: int) -> int:
	if kind_index < 0 or kind_index >= CatalogueScript.IDS.size():
		return UNKNOWN_KIND
	var kind: String = CatalogueScript.IDS[kind_index]
	var checked := check_place_shaft(grid, floors, kind, bottom, top, x_left)
	if checked["reason"] != OK:
		return checked["reason"]
	if ledger.charge(at_tick, checked["cost"], kind_index) != LedgerScript.OK:
		return SHORT_OF_FUNDS
	var span: int = checked["span"]
	var width: int = CatalogueScript.field(kind, "width")
	var clear := false
	while not clear:  # _next_id only grows, so this ends once a free run of span ids is found
		clear = true
		for i in span:
			if grid.has_occupant(_next_id + i):
				_next_id += i + 1
				clear = false
				break
	var level := bottom
	for i in span:
		grid.place(_next_id + i, level, x_left, width)
		for column in range(x_left, x_left + width):
			floors.mark_shaft(level, column)
		level = floor_above(level)
	_kind_of[_next_id] = kind_index
	_shafts[_next_id] = [span, bottom, x_left, [] as Array[int], _next_id]
	_next_id += span
	return OK

## Occupant cells and marks of a shaft: base id, span floors from bottom, x_left, width.
func _put_shaft_cells(grid: GridScript, floors: FloorsScript, base: int, bottom: int, span: int, x_left: int, width: int) -> void:
	var level := bottom
	for i in span:
		grid.place(base + i, level, x_left, width)
		for column in range(x_left, x_left + width):
			floors.mark_shaft(level, column)
		level = floor_above(level)


func _clear_shaft_cells(grid: GridScript, floors: FloorsScript, base: int, bottom: int, span: int, x_left: int, width: int) -> void:
	var level := bottom
	for i in span:
		grid.remove(base + i)
		for column in range(x_left, x_left + width):
			floors.mark_shaft(level, column, false)
		level = floor_above(level)


## True when floor lies within the shaft's span.
func _in_shaft_span(info: Array, floor_number: int) -> bool:
	if not GridScript.is_valid_floor(floor_number):
		return false
	var offset := _level(floor_number) - _level(info[1])
	return offset >= 0 and offset < int(info[0])


## Resizes a shaft in place (the RESIZE_SHAFT command): shaft id, new bottom, new top, same
## column. Same limits as placement; free (a shaft is priced flat). Stop flags of floors that
## remain are kept; new floors are stops. The occupant ids move to a new base when the old one
## has no room to grow. Calls and cars (#93, #94) must drop the removed floors here.
func resize_shaft(grid: GridScript, floors: FloorsScript, id: int, bottom: int, top: int) -> int:
	if not _shafts.has(id):
		return NOTHING_THERE
	var info: Array = _shafts[id]
	var kind: String = kind_of(id)
	var width: int = CatalogueScript.field(kind, "width")
	var old_span: int = info[0]
	var old_bottom: int = info[1]
	var x_left: int = info[2]
	var old_base: int = info[4]
	_clear_shaft_cells(grid, floors, old_base, old_bottom, old_span, x_left, width)
	_shafts.erase(id)
	var checked := check_place_shaft(grid, floors, kind, bottom, top, x_left)
	var reason: int = checked["reason"]
	if reason == OK:
		for car: Array in _cars:
			if car[0] == id and not _in_shaft_span([checked["span"], bottom], car[1]):
				reason = HOME_DROPPED
	if reason != OK:
		_put_shaft_cells(grid, floors, old_base, old_bottom, old_span, x_left, width)
		_shafts[id] = info
		return reason
	var span: int = checked["span"]
	var base := old_base
	var clear := false
	while not clear:
		clear = true
		for i in span:
			if grid.has_occupant(base + i):
				base = _next_id
				_next_id += span
				clear = false
				break
	_put_shaft_cells(grid, floors, base, bottom, span, x_left, width)
	var off: Array[int] = []
	for floor_number: int in info[3]:
		if _in_shaft_span([span, bottom], floor_number):
			off.append(floor_number)
	_shafts[id] = [span, bottom, x_left, off, base]
	for car: Array in _cars:
		if car[0] == id and (not _in_shaft_span([span, bottom], car[2]) or (car[4] != 0 and not _in_shaft_span([span, bottom], car[6]))):
			car[2] = car[1]
			car[4] = 0
			car[5] = 0
			car[6] = 0
			car[7] = 0
	return OK


## Cars in a shaft.
func car_count(shaft_id: int) -> int:
	var total := 0
	for car: Array in _cars:
		if car[0] == shaft_id:
			total += 1
	return total


## People a car holds. #94 refuses the 18th boarder against this.
func car_capacity() -> int:
	return CAR_CAPACITY


## Cars of a shaft, oldest first: each [shaft id, home, floor, load, state, dir, target, ticks left].
func cars_of(shaft_id: int) -> Array:
	var result: Array = []
	for car: Array in _cars:
		if car[0] == shaft_id:
			result.append(car.duplicate())
	return result


## Adds a car (the ADD_CAR command): shaft id, home floor. Local and service shafts only; at most
## MAX_CARS_PER_SHAFT and the star cap; home must be a stop. Charges the catalogue car price.
func add_car(ledger: LedgerScript, at_tick: int, stars: int, shaft_id: int, home: int) -> int:
	if not _shafts.has(shaft_id):
		return NOTHING_THERE
	var shaft_kind: String = kind_of(shaft_id)
	if shaft_kind != "local_shaft" and shaft_kind != "service_shaft":
		return NO_CARS_HERE
	var count := car_count(shaft_id)
	if count >= MAX_CARS_PER_SHAFT:
		return MAX_CARS
	if count >= CARS_BY_STAR[clampi(stars, 1, 5) - 1]:
		return STAR_CAR_CAP
	if not is_stop(shaft_id, home):
		return BAD_HOME_FLOOR
	var car_index: int = CatalogueScript.IDS.find(shaft_kind.replace("_shaft", "_car"))
	if ledger.charge(at_tick, int(CatalogueScript.field(CatalogueScript.IDS[car_index], "cost")), car_index) != LedgerScript.OK:
		return SHORT_OF_FUNDS
	_cars.append([shaft_id, home, home, 0, 0, 0, 0, 0])
	return OK


## Removes the shaft's newest car (the REMOVE_CAR command). No refund.
func remove_car(shaft_id: int) -> int:
	for n in range(_cars.size() - 1, -1, -1):
		if _cars[n][0] == shaft_id:
			_cars.remove_at(n)
			return OK
	return NOTHING_THERE


## Turns a shaft's stop on a floor on or off (the SET_SHAFT_STOP command). Refused if the floor
## is outside the span. A disabled floor is passed, not stopped at.
func set_shaft_stop(id: int, floor_number: int, on: bool) -> int:
	if not _shafts.has(id) or not _in_shaft_span(_shafts[id], floor_number):
		return NOT_IN_SHAFT
	var off: Array[int] = _shafts[id][3]
	if not on:
		for car: Array in _cars:
			if car[0] == id and car[1] == floor_number:
				return HOME_STOP
	off.erase(floor_number)
	if not on:
		off.append(floor_number)
		off.sort()
	return OK


## Sends a car to a floor (the seam for dispatch, #93). The car must be idle; the floor a stop.
## Returns OK, NO_SUCH_CAR (bad index or the car is busy) or NOT_A_STOP. See cars.gd.
func send_car(car_index: int, floor_number: int) -> int:
	if car_index < 0 or car_index >= _cars.size() or _cars[car_index][4] != 0:
		return NO_SUCH_CAR
	if not is_stop(_cars[car_index][0], floor_number):
		return NOT_A_STOP
	CarsScript.start(_cars[car_index], floor_number)
	return OK


## Number of cars in the tower; car_index in send_car counts them oldest first.
func total_cars() -> int:
	return _cars.size()


## True when the shaft's cars stop at floor (in the span and not disabled).
func is_stop(id: int, floor_number: int) -> bool:
	if not _shafts.has(id) or not _in_shaft_span(_shafts[id], floor_number):
		return false
	var off: Array[int] = _shafts[id][3]
	return not off.has(floor_number)


## Floors the shaft stops at, bottom to top. Car motion (#92) uses this to skip disabled floors.
func stops_of(id: int) -> Array[int]:
	var stops: Array[int] = []
	if not _shafts.has(id):
		return stops
	var off: Array[int] = _shafts[id][3]
	var level: int = _shafts[id][1]
	for i in int(_shafts[id][0]):
		if not off.has(level):
			stops.append(level)
		level = floor_above(level)
	return stops


## Removes a room's grid occupants (stairs have two, a shaft one per floor) and clears shaft marks.
func _remove_occupants(grid: GridScript, floors: FloorsScript, id: int) -> void:
	if not _shafts.has(id):
		grid.remove(id)
	if kind_of(id) == "stairs":
		grid.remove(id + 1)
	if _shafts.has(id):
		var info: Array = _shafts[id]
		var width: int = CatalogueScript.field(kind_of(id), "width")
		var level: int = info[1]
		for i in int(info[0]):
			grid.remove(int(info[4]) + i)
		for n in range(_cars.size() - 1, -1, -1):
			if _cars[n][0] == id:
				_cars.remove_at(n)
		for i in int(info[0]):
			for column in range(info[2], info[2] + width):
				floors.mark_shaft(level, column, false)
			level = floor_above(level)
		_shafts.erase(id)


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
	if _shaft_base(id) != 0:
		id = _shaft_base(id)
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
	_remove_occupants(grid, floors, id)
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
	if _shafts.has(id):
		for i in int(_shafts[id][0]):
			after.remove(int(_shafts[id][4]) + i)
	else:
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
	_remove_occupants(grid, floors, id)
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
	var bases: Array = _shafts.keys()
	bases.sort()
	ints.append(bases.size())
	for base: int in bases:
		ints.append_array([base, _shafts[base][0], _shafts[base][1], _shafts[base][2], _shafts[base][4], _shafts[base][3].size()] as Array[int])
		ints.append_array(_shafts[base][3] as Array[int])
	ints.append(_cars.size())
	for car: Array in _cars:
		ints.append_array(car as Array[int])
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
	_shafts = {}
	var at: int = 4 + 3 * ints[1]
	for i in range(ints[at - 1]):
		var off: Array[int] = []
		for j in range(ints[at + 5]):
			off.append(ints[at + 6 + j])
		_shafts[ints[at]] = [ints[at + 1], ints[at + 2], ints[at + 3], off, ints[at + 4]]
		at += 6 + ints[at + 5]
	_cars = []
	for i in range(ints[at]):
		_cars.append(ints.slice(at + 1 + 8 * i, at + 9 + 8 * i))
	_next_id = ints[0]
	return true


## True when ints is a valid state_ints() result. With a grid, every room must be placed in it.
static func valid_ints(ints: Array, grid: GridScript) -> bool:
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	if ints.size() < 2 or ints[1] < 0 or ints.size() < 4 + 3 * ints[1] or ints[0] < 1 or ints[2 + 3 * ints[1]] < 0:
		return false
	var shaft_total: int = ints[3 + 3 * ints[1]]
	if shaft_total < 0:
		return false
	var at: int = 4 + 3 * ints[1]
	var shaft_ids: Dictionary = {}
	for i in range(shaft_total):
		if at + 6 > ints.size() or ints[at + 5] < 0 or at + 6 + ints[at + 5] > ints.size():
			return false
		var base: int = ints[at + 4]
		var span: int = ints[at + 1]
		if ints[at] < 1 or base < 1 or span < 1 or span > GridScript.FLOOR_COUNT or not GridScript.is_valid_floor(ints[at + 2]):
			return false
		if grid != null and not grid.has_occupant(base + span - 1):
			return false
		shaft_ids[ints[at]] = true
		at += 6 + ints[at + 5]
	if at >= ints.size() or ints[at] < 0 or at + 1 + 8 * ints[at] != ints.size():
		return false
	for i in range(ints[1]):
		var id: int = ints[2 + 3 * i]
		var kind_index: int = ints[3 + 3 * i]
		var sold: int = ints[4 + 3 * i]
		if id < 1 or kind_index < 0 or kind_index >= CatalogueScript.IDS.size() or (sold != 0 and sold != 1):
			return false
		if grid != null and not shaft_ids.has(id) and not grid.has_occupant(id):
			return false
		if grid != null and kind_index == CatalogueScript.IDS.find("stairs") and not grid.has_occupant(id + 1):
			return false
	return true
