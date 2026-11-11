class_name Floors
extends RefCounted
## Built floor units. Integers only; see CLAUDE.md.
##
## A floor unit is one cell of floor slab on one floor. Rooms (2.4) sit on top of floor units
## and buy missing ones. Floors are never removed. Spans are inclusive: x_start to x_end.
## Support rule: floor 1 sits on the ground. A floor above ground needs a floor unit directly
## below each new unit (floor 2 needs floor 1, and so on). UNVERIFIED: the reference is silent
## on basements, so each basement unit mirrors the rule and needs a unit directly above it
## (B1 needs floor 1, B2 needs B1, and so on).
## Shafts do not exist yet: mark_shaft() is the hook #10 will call. A shaft cell takes no floor.
## Ground lobby (2.2): build_lobby() builds floors 1 to its height as floor units flagged LOBBY.
## Those cells are taken, so a floor or room cannot be built on them (OCCUPIED_BY_LOBBY). The
## lobby's width caps everything above it through the no-wider-than-below rule. Floors built
## before the lobby are not capped (UNVERIFIED: the reference does not say).

const GridScript := preload("res://scripts/sim/grid.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const LedgerScript := preload("res://scripts/sim/ledger.gd")

## Result codes. OK and SHORT_OF_FUNDS match Ledger's, so Tower.last_refusal reads the same.
const OK := 0
const SHORT_OF_FUNDS := 1
const BAD_FLOOR := 10  ## Not a real floor number.
const BAD_SPAN := 11  ## Ends before it starts, or runs off the tower's width.
const NOTHING_BELOW := 12  ## No new unit of the span has a floor to rest on.
const WIDER_THAN_BELOW := 13  ## Some units rest on a floor, others hang past it.
const OVER_SHAFT := 14  ## The span crosses a shaft cell.
const ALREADY_BUILT := 15  ## Every unit in the span is already a floor.
const OCCUPIED_BY_LOBBY := 16  ## The span crosses a cell the ground lobby occupies.
const LOBBY_BAD_FLOOR := 17  ## The ground lobby goes on floor 1 only.
const LOBBY_BAD_HEIGHT := 18  ## The ground lobby is 1, 2 or 3 floors tall.
const LOBBY_EXISTS := 19  ## The tower already has its ground lobby.

const BUILT := 1  # cell flag bits
const SHAFT := 2
const LOBBY := 4  # the ground lobby occupies the cell (it is also BUILT)
const LOBBY_MAX_HEIGHT := 3

## Bumps on every change, so the view knows when to redraw. Not saved or hashed.
var revision: int = 0
var _flags := PackedByteArray()  # FLOOR_COUNT * WIDTH_UNITS flag bytes


func _init() -> void:
	_flags.resize(GridScript.FLOOR_COUNT * GridScript.WIDTH_UNITS)


func has_floor(floor_number: int, column: int) -> bool:
	return _has(floor_number, column, BUILT)


func has_shaft(floor_number: int, column: int) -> bool:
	return _has(floor_number, column, SHAFT)


## Hook for shafts (#10): marks a cell as shaft (or clears it). False for an invalid cell.
func mark_shaft(floor_number: int, column: int, on: bool = true) -> bool:
	var index := _cell_index(floor_number, column)
	if index < 0:
		return false
	if on:
		_flags[index] = _flags[index] | SHAFT
		revision += 1
	else:
		_flags[index] = _flags[index] & ~SHAFT
		revision += 1
	return true


## Floor units built across the whole tower.
func unit_count() -> int:
	var total := 0
	for value in _flags:
		total += value & BUILT
	return total


## Checks a span without changing anything. Returns {"reason": code, "new_units": n, "cost": $}.
## reason is OK when the span can be built (funds are checked by build_span). The ghost (#13)
## and rooms (#12) use this to preview.
func check_span(floor_number: int, x_start: int, x_end: int) -> Dictionary:
	var result := {"reason": OK, "new_units": 0, "cost": 0}
	if not GridScript.is_valid_floor(floor_number):
		result["reason"] = BAD_FLOOR
		return result
	if x_end < x_start or x_start < 0 or x_end >= GridScript.WIDTH_UNITS:
		result["reason"] = BAD_SPAN
		return result
	var new_units := 0
	var supported := 0
	for column in range(x_start, x_end + 1):
		if _has(floor_number, column, LOBBY):
			result["reason"] = OCCUPIED_BY_LOBBY
			return result
		if has_shaft(floor_number, column):
			result["reason"] = OVER_SHAFT
			return result
		if has_floor(floor_number, column):
			continue
		new_units += 1
		if _is_supported(floor_number, column):
			supported += 1
	if new_units == 0:
		result["reason"] = ALREADY_BUILT
	elif supported == 0:
		result["reason"] = NOTHING_BELOW
	elif supported < new_units:
		result["reason"] = WIDER_THAN_BELOW
	result["new_units"] = new_units
	result["cost"] = new_units * CatalogueScript.FLOOR_COST_PER_UNIT
	return result


## Builds a span, charging the ledger only for new units. Returns OK or a reason code, and
## changes nothing on a refusal. The ledger line's ref is the floor number.
func build_span(ledger: LedgerScript, at_tick: int, floor_number: int, x_start: int, x_end: int) -> int:
	var checked := check_span(floor_number, x_start, x_end)
	if checked["reason"] != OK:
		return checked["reason"]
	if ledger.charge(at_tick, checked["cost"], floor_number) != LedgerScript.OK:
		return SHORT_OF_FUNDS
	for column in range(x_start, x_end + 1):
		var index := _cell_index(floor_number, column)
		_flags[index] = _flags[index] | BUILT
	revision += 1
	return OK


## Builds the units of a span that are not yet floor, free of charge. The caller (a room, #12)
## has already checked support and charged. Cells with a shaft or lobby are left alone.
func fill_span(floor_number: int, x_start: int, x_end: int) -> void:
	for column in range(x_start, x_end + 1):
		var index := _cell_index(floor_number, column)
		if index >= 0 and (_flags[index] & (SHAFT | LOBBY)) == 0:
			_flags[index] = _flags[index] | BUILT
	revision += 1


## True when the ground lobby occupies this cell.
func has_lobby_at(floor_number: int, column: int) -> bool:
	return _has(floor_number, column, LOBBY)


## True once the ground lobby is built.
func has_lobby() -> bool:
	return not lobby_span().is_empty()


## The ground lobby as [x_start, x_end, height], or empty when there is none.
func lobby_span() -> Array[int]:
	var span: Array[int] = []
	var base := GridScript.floor_to_index(1) * GridScript.WIDTH_UNITS
	for column in GridScript.WIDTH_UNITS:
		if (_flags[base + column] & LOBBY) == 0:
			continue
		if span.is_empty():
			span = [column, column, 1] as Array[int]
		span[1] = column
	if span.is_empty():
		return span
	for floor_number in range(2, LOBBY_MAX_HEIGHT + 1):
		if _has(floor_number, span[0], LOBBY):
			span[2] = floor_number
	return span


## Checks a ground lobby without changing anything. Returns {"reason", "new_units", "cost"}.
## Cost is the lobby price per unit for every floor it occupies, plus the floor price for each
## unit not already built. UNVERIFIED: tall lobby priced per floor (gameplay review left it open).
func check_lobby(floor_number: int, x_start: int, x_end: int, height: int) -> Dictionary:
	var result := {"reason": OK, "new_units": 0, "cost": 0}
	if floor_number != 1:
		result["reason"] = LOBBY_BAD_FLOOR
		return result
	if height < 1 or height > LOBBY_MAX_HEIGHT:
		result["reason"] = LOBBY_BAD_HEIGHT
		return result
	if has_lobby():
		result["reason"] = LOBBY_EXISTS
		return result
	if x_end < x_start or x_start < 0 or x_end >= GridScript.WIDTH_UNITS:
		result["reason"] = BAD_SPAN
		return result
	var new_units := 0
	for level in range(1, height + 1):
		for column in range(x_start, x_end + 1):
			if has_shaft(level, column):
				result["reason"] = OVER_SHAFT
				return result
			if not has_floor(level, column):
				new_units += 1
	var width := x_end - x_start + 1
	# unverified: tall lobby priced per floor
	result["new_units"] = new_units
	result["cost"] = CatalogueScript.cost("lobby") * width * height + new_units * CatalogueScript.FLOOR_COST_PER_UNIT
	return result


## Builds the ground lobby over floors 1 to height in one charge. Returns OK or a reason code,
## and changes nothing on a refusal.
func build_lobby(ledger: LedgerScript, at_tick: int, floor_number: int, x_start: int, x_end: int, height: int) -> int:
	var checked := check_lobby(floor_number, x_start, x_end, height)
	if checked["reason"] != OK:
		return checked["reason"]
	if ledger.charge(at_tick, checked["cost"], CatalogueScript.IDS.find("lobby")) != LedgerScript.OK:
		return SHORT_OF_FUNDS
	for level in range(1, height + 1):
		for column in range(x_start, x_end + 1):
			var index := _cell_index(level, column)
			_flags[index] = _flags[index] | BUILT | LOBBY
	revision += 1
	return OK


func _is_supported(floor_number: int, column: int) -> bool:
	if floor_number == 1:
		return true
	var below := floor_number - 1
	if floor_number < 0:
		below = floor_number + 1
		if below == 0:
			below = 1  # B1 rests on floor 1 (there is no floor 0)
	return has_floor(below, column)


func _cell_index(floor_number: int, column: int) -> int:
	var row := GridScript.floor_to_index(floor_number)
	if row < 0 or column < 0 or column >= GridScript.WIDTH_UNITS:
		return -1
	return row * GridScript.WIDTH_UNITS + column


func _has(floor_number: int, column: int, flag: int) -> bool:
	var index := _cell_index(floor_number, column)
	return index >= 0 and (_flags[index] & flag) != 0


## Flat ints for hashing and saving: run count then runs (floor, flag, start, length) in
## floor, then column order, one flag value per run (bits: 1 built, 2 shaft, 4 lobby).
func state_ints() -> Array[int]:
	var runs: Array[int] = []
	for row in GridScript.FLOOR_COUNT:
		var column := 0
		while column < GridScript.WIDTH_UNITS:
			var flag := _flags[row * GridScript.WIDTH_UNITS + column]
			var start := column
			column += 1
			if flag == 0:
				continue
			while column < GridScript.WIDTH_UNITS and _flags[row * GridScript.WIDTH_UNITS + column] == flag:
				column += 1
			runs.append_array([GridScript.index_to_floor(row), flag, start, column - start] as Array[int])
	var ints: Array[int] = [runs.size() / 4]
	ints.append_array(runs)
	return ints


## Restores state_ints(). Returns false, changing nothing, for data that is not valid.
func load_ints(ints: Array) -> bool:
	if not _valid_shape(ints):
		return false
	var loaded := PackedByteArray()
	loaded.resize(_flags.size())
	for i in range(ints[0]):
		var base := 1 + 4 * i
		var row := GridScript.floor_to_index(ints[base])
		for column in range(ints[base + 2], ints[base + 2] + ints[base + 3]):
			loaded[row * GridScript.WIDTH_UNITS + column] = ints[base + 1]
	_flags = loaded
	revision += 1
	return true


## True when ints is a valid state_ints() result.
static func valid_ints(ints: Array) -> bool:
	return _valid_shape(ints)


static func _valid_shape(ints: Array) -> bool:
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	if ints.is_empty() or ints[0] < 0 or ints.size() != 1 + 4 * ints[0]:
		return false
	for i in range(ints[0]):
		var base := 1 + 4 * i
		var flag: int = ints[base + 1]
		var start: int = ints[base + 2]
		var length: int = ints[base + 3]
		if GridScript.floor_to_index(ints[base]) < 0 or flag < 1 or flag > 7:
			return false
		if start < 0 or length < 1 or start + length > GridScript.WIDTH_UNITS:
			return false
	return true
