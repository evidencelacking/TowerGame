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
## STRESS_PER_NOISE_LEVEL, which is 0 (off) until the owner wants it.

const GridScript := preload("res://scripts/sim/grid.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")

## Noise a source makes right beside a room (distance 0). Offices, commercial, communal.
const SOURCES: Dictionary = {
	"office": 3, "fast_food": 4, "restaurant": 5, "retail": 3,
	"movie_theatre": 6, "party_hall": 8,
}
## Kinds that can be disturbed: residential and hotel rooms.
const SENSITIVE: Array[String] = ["condo", "hotel_single", "hotel_twin", "hotel_suite"]
## Desirable things nearby that mute noise: each one in range removes this much.
const BUFFERS: Dictionary = {"medical": 2, "security": 1, "cathedral": 4}

const RANGE_FLOORS := 1  ## Sources and buffers reach this many floors above and below.
const RANGE_UNITS := 2  ## ...and this many empty units sideways (0 = touching or overlapping).
const FALLOFF_PER_STEP := 1  ## A source loses this much per floor and per sideways unit of distance.
const MAX_LEVEL := 10  ## Noise level never exceeds this.
const STRESS_PER_NOISE_LEVEL := 0  ## Stress added per level per evaluation; 0 keeps stress unchanged.


static func is_source(kind: String) -> bool:
	return SOURCES.has(kind)


static func is_sensitive(kind: String) -> bool:
	return SENSITIVE.has(kind)


## Steps between two runs [floor, column, length]: floors apart plus empty units between them.
## Returns -1 when out of range.
static func distance(a: Array, b: Array) -> int:
	var floors_apart: int = absi(int(a[0]) - int(b[0]))
	# There is no floor 0, so floors above and below ground are one apart across it.
	if (int(a[0]) > 0) != (int(b[0]) > 0):
		floors_apart -= 1
	var gap: int = maxi(maxi(int(a[1]) - (int(b[1]) + int(b[2])), int(b[1]) - (int(a[1]) + int(a[2]))), 0)
	if floors_apart > RANGE_FLOORS or gap > RANGE_UNITS:
		return -1
	return floors_apart + gap


## The pure core: noise on a room of kind `kind` at `run`, given others as [kind, run] pairs.
static func level_among(kind: String, run: Array, others: Array) -> int:
	if not is_sensitive(kind):
		return 0
	var loud := 0
	var muting := 0
	for other: Array in others:
		var other_kind: String = other[0]
		var d := distance(run, other[1])
		if d < 0:
			continue
		if SOURCES.has(other_kind):
			loud += maxi(int(SOURCES[other_kind]) - FALLOFF_PER_STEP * d, 0)
		elif BUFFERS.has(other_kind):
			muting += int(BUFFERS[other_kind])
	return clampi(loud - muting, 0, MAX_LEVEL)


## Noise level on one placed room: 0 for a quiet room, an unknown id, or a room that is not sensitive.
static func noise_at(grid: GridScript, rooms: RoomsScript, room_id: int) -> int:
	var kind := rooms.kind_of(room_id)
	if not is_sensitive(kind) or not grid.has_occupant(room_id):
		return 0
	return level_among(kind, grid.run_of(room_id), _others(grid, rooms, room_id))


## Rooms with noise above 0: room id -> level, ascending by id.
static func levels(grid: GridScript, rooms: RoomsScript) -> Dictionary:
	var result := {}
	for id in rooms.room_ids():
		var level := noise_at(grid, rooms, id)
		if level > 0:
			result[id] = level
	return result


## Stress a noise level adds (0 while STRESS_PER_NOISE_LEVEL is 0).
static func stress_for(level: int) -> int:
	return level * STRESS_PER_NOISE_LEVEL


static func _others(grid: GridScript, rooms: RoomsScript, except_id: int) -> Array:
	var list := []
	for id in rooms.room_ids():
		if id != except_id and grid.has_occupant(id):
			list.append([rooms.kind_of(id), grid.run_of(id)])
	return list
