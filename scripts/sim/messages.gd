class_name Messages
extends RefCounted
## The message record: a bounded list of (tick, code, a, b) integer entries, oldest first. The sim
## appends when it refuses a command or something notable happens; the view words each code and
## stamps the tick with the game clock. Integers only, so it saves and hashes exactly.

## Refusal codes: a is the sim's reason code (Ledger, Floors or Rooms), b is extra detail.
const PURCHASE_REFUSED := 10
const FLOOR_REFUSED := 11  ## b: floor number.
const LOBBY_REFUSED := 12
const ROOM_REFUSED := 13  ## b: catalogue index.
const BULLDOZE_REFUSED := 14  ## b: floor number.
const REPLACE_REFUSED := 15  ## b: catalogue index.
const STAIRS_REFUSED := 16  ## b: floor number.
const RENT_REFUSED := 17  ## a: Rent result code, b: room id.
## Event codes.
const FLOOR_BUILT := 20  ## a: floor number.
const LOBBY_BUILT := 21  ## a: height in floors.
const ROOM_BUILT := 22  ## a: catalogue index, b: floor number.
const STAIRS_BUILT := 23  ## a: lower floor.
const ROOM_REMOVED := 24  ## a: catalogue index, b: floor number.
const ROOM_REPLACED := 25  ## a: new catalogue index, b: floor number.
const CONDO_REFUND := 26  ## a: dollars paid back.
const STAR_PROMOTED := 27  ## a: the new star rating.
const RENT_SET := 28  ## a: room id, b: new level.

const CAP := 500  ## Entries kept; the oldest drop first.
const FIELDS := 4

var _entries: Array[int] = []  ## Flat: tick, code, a, b per entry.


func add(at_tick: int, code: int, a: int = 0, b: int = 0) -> void:
	_entries.append_array([at_tick, code, a, b] as Array[int])
	if count() > CAP:
		_entries = _entries.slice(FIELDS)


func count() -> int:
	return _entries.size() / FIELDS


## Entry i (0 is the oldest) as [tick, code, a, b].
func entry(i: int) -> Array[int]:
	var base := i * FIELDS
	return [_entries[base], _entries[base + 1], _entries[base + 2], _entries[base + 3]] as Array[int]


## Flat ints for hashing and saving: the count, then the entries.
func state_ints() -> Array[int]:
	var ints: Array[int] = [count()]
	ints.append_array(_entries)
	return ints


static func valid_ints(ints: Array) -> bool:
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	return ints.size() >= 1 and ints[0] >= 0 and ints[0] <= CAP and ints.size() == 1 + FIELDS * ints[0]


func load_ints(ints: Array) -> void:
	_entries = []
	for i in range(1, ints.size()):
		_entries.append(ints[i])
