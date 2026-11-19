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
const ESCALATOR_BUILT := 28  ## a: lower floor.
const RENT_SET := 29  ## a: room id, b: new level.
const QUARTER_SETTLED := 30  ## a: rent collected, b: running costs charged, in dollars; logged at a quarter start when either is above 0.
const FRIEND_ARRIVED := 31  ## a: catalogue index, b: floor number.
const TENANT_LEFT := 32  ## a: catalogue index, b: floor number.
const DAILY_SALES := 35  ## a: net dollars across open shops (a loss is negative), b: shops settled; logged each day at settlement.

const GUEST_UNREACHED := 33  ## a: room id. Hotel guests could not reach their room and left.
const PESTS_WARNING := 36  ## a: room id. A dirty hotel room will get pests soon (#149).
const PESTS_FOUND := 37  ## a: room id. A hotel room is infested; only demolition clears it (#149).
const DEMAND_RAISED := 38  ## a: Demands id. The tower needs something (#168).
const DEMAND_CLEARED := 39  ## a: Demands id. The need is met.
const VIP_ARRIVED := 40  ## a: suite room id. A VIP checked in (#173).
const VIP_GOOD := 41  ## a: suite room id. The VIP left happy: star 4 can follow.
const VIP_BAD := 42  ## a: suite room id. The VIP left unhappy; another comes in a few days.
const TRIP_UNREACHABLE := 43  ## a: people whose trip needed a second transfer this minute (#184). Logged at most once a day.
const FIRE_STARTED := 44  ## a: catalogue index, b: floor number. A fire broke out in a room (#217).
const FIRE_OUT := 45  ## a: catalogue index, b: floor number. Guards put the fire in a room out.
const ROOM_BURNED := 46  ## a: catalogue index, b: floor number. A burning room was destroyed.
const RESCUE_ARRIVED := 47  ## a: fires put out, b: rooms lost. The paid rescue craft came.
const THREAT_NOTICE := 48  ## An anonymous notice: a device is hidden in the tower (#218).
const THREAT_PAID := 49  ## The owner paid and it ended.
const THREAT_FOUND := 50  ## a: floor. Guards found the device in time.
const THREAT_EXPLODED := 51  ## a: lowest floor, b: highest floor destroyed.
const ROOM_DIRTY := 34  ## a: room id. Hotel guests checked out; the room needs cleaning (#147).

const CAP := 500  ## Entries kept; the oldest drop first.
const FIELDS := 4

var _entries: Array[int] = []  ## Flat: tick, code, a, b per entry.


func add(at_tick: int, code: int, a: int = 0, b: int = 0) -> void:
	_entries.append_array([at_tick, code, a, b] as Array[int])
	if count() > CAP:
		_entries = _entries.slice(FIELDS)


## True when an entry with this code was logged at or after since_tick. Reads from the newest back.
func recent(code: int, since_tick: int) -> bool:
	var i := count() - 1
	while i >= 0 and _entries[i * FIELDS] >= since_tick:
		if _entries[i * FIELDS + 1] == code:
			return true
		i -= 1
	return false


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
