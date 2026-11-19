class_name Demands
extends RefCounted
## Demand messages (7.3): what the tower currently needs, as an open set of demand ids.
## Our own wording and our own rules (owner rulings on #168): security and suite are star
## requirements in the original, and showing them as "needs" messages is our addition.
##
## A demand is open while its trigger holds and its remedy is missing:
##   SECURITY   from 2 stars (star 3 asks for a security office), no security office.
##   SUITE      from 3 stars (star 4 asks for 2 suites), fewer than SUITES_FOR_STAR_4 suites.
##   MEDICAL    from 3 stars, at least one office, no medical centre.
##   RECYCLING  from 3 stars, at least one office, no recycling centre.
##   PARKING    from 3 stars, at least one office, no parking space.
## A demand only opens once its remedy can be built (its room kind is in Rooms.PLACEABLE), so
## the demands for rooms that do not exist yet stay quiet instead of blocking star 4 for ever
## (decision on #168). Any open demand blocks star 4 (StarRules "demands_met"). Integers only.
##
## Saved state: one int, the bitmask of open demands (bit = 1 << (id - 1)).

const SECURITY := 1
const SUITE := 2
const MEDICAL := 3
const RECYCLING := 4
const PARKING := 5
const IDS: Array[int] = [SECURITY, SUITE, MEDICAL, RECYCLING, PARKING]

const SUITES_FOR_STAR_4 := 2  ## Mirrors StarRules.REQUIREMENTS[4]["suites"].
const _REMEDY: Dictionary = {SECURITY: "security", MEDICAL: "medical", RECYCLING: "recycling", PARKING: "parking_space"}
const _MIN_STARS: Dictionary = {SECURITY: 2, SUITE: 3, MEDICAL: 3, RECYCLING: 3, PARKING: 3}

var _open: int = 0


## True while the demand is open.
func is_open(id: int) -> bool:
	return _open & (1 << (id - 1)) != 0


func open_count() -> int:
	var n := 0
	for id in IDS:
		if is_open(id):
			n += 1
	return n


## True when no demand is open (the star rules' "demands_met").
func all_met() -> bool:
	return _open == 0


## The demands that hold for a tower: stars, and a count of rooms per kind. Pure.
## buildable lists the room kinds the player can place now.
static func compute(stars: int, kind_counts: Dictionary, buildable: Array[String]) -> int:
	var mask := 0
	var offices: int = kind_counts.get("office", 0)
	for id in IDS:
		if stars < int(_MIN_STARS[id]):
			continue
		var wanted := false
		if id == SUITE:
			wanted = buildable.has("hotel_suite") and int(kind_counts.get("hotel_suite", 0)) < SUITES_FOR_STAR_4
		else:
			var remedy: String = _REMEDY[id]
			wanted = buildable.has(remedy) and int(kind_counts.get(remedy, 0)) == 0
			if id != SECURITY:
				wanted = wanted and offices > 0
		if wanted:
			mask |= 1 << (id - 1)
	return mask


## Recomputes the open set and logs one message for each demand raised or cleared.
func update(rooms: Rooms, stars: int, messages: Messages, at_tick: int, buildable: Array[String] = Rooms.PLACEABLE) -> void:
	var counts: Dictionary = {}
	for room in rooms.room_ids():
		var kind := rooms.kind_of(room)
		counts[kind] = int(counts.get(kind, 0)) + 1
	var now := compute(stars, counts, buildable)
	if now == _open:
		return
	for id in IDS:
		var bit := 1 << (id - 1)
		if now & bit != 0 and _open & bit == 0:
			messages.add(at_tick, Messages.DEMAND_RAISED, id)
		elif now & bit == 0 and _open & bit != 0:
			messages.add(at_tick, Messages.DEMAND_CLEARED, id)
	_open = now


func state_ints() -> Array[int]:
	return [_open] as Array[int]


static func valid_ints(ints: Array) -> bool:
	return ints.size() == 1 and typeof(ints[0]) == TYPE_INT and ints[0] >= 0 and ints[0] < (1 << IDS.size())


func load_ints(ints: Array) -> void:
	_open = ints[0]
