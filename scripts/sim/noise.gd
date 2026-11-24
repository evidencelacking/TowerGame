extends RefCounted
## Noise (5.5): noisy rooms disturb sensitive rooms nearby. A pure function of the grid and the
## room kinds: it keeps no state, so a reload with the same tower gives the same answer.
## Integers only; see CLAUDE.md.
##
## Owner ruling (2026-11-14): noise comes from offices, commercial and communal spaces. It is
## limited by distance and by buffers (desirable things nearby). Every number below is a
## tunable; the reference gives no radius or strengths, so all of them are UNVERIFIED.
##
## Offices disturb condos and hotel rooms but not each other (K): only SENSITIVE kinds receive
## noise, and an office is a source, not a sensitive kind.
##
## Read it with noise_at(grid, rooms, room_id) for one room or levels(grid, rooms) for all.
## #119 (complaint reasons) and the grade (#113) read these; the stress effect is behind
## STRESS_PER_NOISE_LEVEL; Complaints (#119) registers it as a Grades modifier.

const GridScript := preload("res://scripts/sim/grid.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")

## Noise a source makes right beside a room (distance 0). Offices, commercial, communal.
const SOURCES: Dictionary = {
	"office": 3, "fast_food": 4, "restaurant": 5, "retail": 3,
	"movie_theatre": 6, "party_hall": 8, "nightclub": 9, "cafe": 2, "pizza": 3, "sushi": 1, "fine_dining": 1, "bar": 6, "casino": 8, "deli": 2, "pool": 3, "helipad": 6, "ballroom": 6, "conference_center": 2,
}
## Kinds that can be disturbed: residential and hotel rooms.
const SENSITIVE: Array[String] = ["condo", "studio", "penthouse", "apartment", "assisted", "hotel_single", "hotel_twin", "hotel_suite"]
## Desirable things nearby that mute noise: each one in range removes this much.
const BUFFERS: Dictionary = {"medical": 2, "security": 1, "cathedral": 4}

const RANGE_FLOORS := 1  ## Sources and buffers reach this many floors above and below.
const RANGE_UNITS := 2  ## ...and this many empty units sideways (0 = touching or overlapping).
const FALLOFF_PER_STEP := 1  ## A source loses this much per floor and per sideways unit of distance.
## Sources that reach further than RANGE_FLOORS, and only downward from themselves (#409): the helicopter pad
## disturbs hotel rooms and condos up to 3 floors below it, with the usual falloff per floor.
const REACH_BELOW: Dictionary = {"helipad": 3}
const ASSISTED_FACTOR := 2  ## Assisted living feels noise this many times over (#378, tunable).
const MAX_LEVEL := 10  ## Noise level never exceeds this.
const STRESS_PER_NOISE_LEVEL := 5  ## Stress added to a room's grade average per noise level (tunable, unverified; 0 turns it off).


static func is_source(kind: String) -> bool:
	return SOURCES.has(kind)


static func is_sensitive(kind: String) -> bool:
	return SENSITIVE.has(kind)


## Steps between two runs [floor, column, length]: floors apart plus empty units between them.
## Returns -1 when out of range.
static func distance(a: Array, b: Array, range_floors: int = RANGE_FLOORS) -> int:
	var floors_apart: int = absi(int(a[0]) - int(b[0]))
	# There is no floor 0, so floors above and below ground are one apart across it.
	if (int(a[0]) > 0) != (int(b[0]) > 0):
		floors_apart -= 1
	var gap: int = maxi(maxi(int(a[1]) - (int(b[1]) + int(b[2])), int(b[1]) - (int(a[1]) + int(a[2]))), 0)
	if floors_apart > range_floors or gap > RANGE_UNITS:
		return -1
	return floors_apart + gap


## The pure core: noise on a room of kind `kind` at `run`, given others as [kind, run] pairs.
static func level_among(kind: String, run: Array, others: Array) -> int:
	if not is_sensitive(kind):
		return 0
	var loud := 0
	var muting := 0
	var floor_here: int = run[0]
	var left: int = run[1]
	var right: int = run[1] + run[2]
	for other: Array in others:
		var other_kind: String = other[0]
		var there: Array = other[1]
		var reach := RANGE_FLOORS
		var floor_there: int = there[0]
		if REACH_BELOW.has(other_kind):  # a roof source: only rooms below it, within its own reach
			if floor_here >= floor_there:
				continue
			reach = REACH_BELOW[other_kind]
		# distance(), inline: this loop is the cost of a cold noise cache.
		var apart := absi(floor_here - floor_there)
		if (floor_here > 0) != (floor_there > 0):
			apart -= 1  # no floor 0: across the ground the floors are one apart
		var gap := maxi(maxi(left - (int(there[1]) + int(there[2])), int(there[1]) - right), 0)
		if apart > reach or gap > RANGE_UNITS:
			continue
		var d := apart + gap
		if SOURCES.has(other_kind):
			loud += maxi(int(SOURCES[other_kind]) - FALLOFF_PER_STEP * d, 0)
		elif BUFFERS.has(other_kind):
			muting += int(BUFFERS[other_kind])
	var level := clampi(loud - muting, 0, MAX_LEVEL)
	if kind == "assisted":  # seniors are twice as bothered (#378)
		level = mini(level * ASSISTED_FACTOR, MAX_LEVEL)
	return level


## Noise level on one placed room: 0 for a quiet room, an unknown id, or a room that is not sensitive.
static func noise_at(grid: GridScript, rooms: RoomsScript, room_id: int) -> int:
	var kind := rooms.kind_of(room_id)
	if not is_sensitive(kind) or not grid.has_occupant(room_id):
		return 0
	var cache := _cache(grid, rooms)
	if cache.has(room_id):
		return cache[room_id]
	if not cache.has(_OTHERS):
		cache[_OTHERS] = _index(_others(grid, rooms, 0))
	var run := grid.run_of(room_id)
	var index: Dictionary = cache[_OTHERS]
	# Only the sources and buffers a room can hear: its own floor and the ones beside it (across the ground
	# the raw floor numbers are two apart for one floor), plus the roof sources, which reach further down.
	var near: Array = (index["roof"] as Array).duplicate()
	var by_floor: Dictionary = index["floors"]
	for f in range(int(run[0]) - RANGE_FLOORS - 1, int(run[0]) + RANGE_FLOORS + 2):
		near.append_array(by_floor.get(f, []))
	var level := level_among(kind, run, near) if not near.is_empty() else 0  # nothing within earshot: a quiet room
	cache[room_id] = level
	return level


## Rooms with noise above 0: room id -> level, ascending by id.
static func levels(grid: GridScript, rooms: RoomsScript) -> Dictionary:
	var result := {}
	for id in rooms.room_ids():
		var level := noise_at(grid, rooms, id)
		if level > 0:
			result[id] = level
	return result


## Stress a noise level adds.
static func stress_for(level: int) -> int:
	return level * STRESS_PER_NOISE_LEVEL


## Key of the cached "every placed room" list; room ids are positive, so it never clashes with one.
const _OTHERS := -1


## The cache of levels (room id -> level) and the placed-room list, for the grid and room list as they are now (#416).
## A pure function of the grid and the room kinds, so it is thrown away whenever either changes. A sensitive
## room is never a source or a buffer, so the list can include the room it is asked about.
static func _cache(grid: GridScript, rooms: RoomsScript) -> Dictionary:
	var key: Array[int] = [grid.get_instance_id(), grid.revision, rooms.layout_revision]
	if rooms.noise_key != key:
		rooms.noise_key = key
		rooms.noise_cache = {}
	return rooms.noise_cache


## The placed rooms that make or mute noise, as {"floors": floor -> [kind, run] pairs, "roof": the pairs whose kind reaches
## further down}. A room that is neither a source nor a buffer never changes a level, so it is left out. Sums are
## order-free, so bucketing cannot change a level (#452).
static func _index(others: Array) -> Dictionary:
	var floors := {}
	var roof := []
	for other: Array in others:
		var other_kind: String = other[0]
		if not (SOURCES.has(other_kind) or BUFFERS.has(other_kind)):
			continue
		if REACH_BELOW.has(other_kind):
			roof.append(other)
			continue
		var floor_number: int = other[1][0]
		if not floors.has(floor_number):
			floors[floor_number] = []
		floors[floor_number].append(other)
	return {"floors": floors, "roof": roof}


static func _others(grid: GridScript, rooms: RoomsScript, except_id: int) -> Array:
	var list := []
	for id in rooms.room_ids():
		var kind := rooms.kind_of(id)
		if not (SOURCES.has(kind) or BUFFERS.has(kind)):
			continue  # _index would drop it, and most rooms are neither: skip the run copy (#452)
		if id != except_id and grid.has_occupant(id):
			list.append([kind, grid.run_of(id)])
	return list
