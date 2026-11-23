extends RefCounted
## Where to draw each person and in what colour. Reads the sim only; never writes to it.
## Each figure has an integer floor and column. Moving ones also carry a fractional column ("fx")
## and row ("frow") so stairs and escalator legs can be drawn as a smooth diagonal; resting people
## stand in their room; people outside are skipped.

const PeopleScript := preload("res://scripts/sim/people.gd")
const RoutesScript := preload("res://scripts/sim/routes.gd")
const TripsScript := preload("res://scripts/sim/trips.gd")
const HotelScript := preload("res://scripts/sim/hotel.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const VC := preload("res://scripts/view/view_consts.gd")
const ActivityLook := preload("res://scripts/view/activity_look.gd")
const RoomRecipes := preload("res://scripts/view/room_recipes.gd")
const Suites := preload("res://scripts/view/suites.gd")

## Colour per stress band: calm black, uneasy pink, angry red.
const BAND_COLORS: Array[Color] = [Color(0.05, 0.05, 0.05), Color(1.0, 0.45, 0.70), Color(0.85, 0.08, 0.08)]
## Marks drawn above the head per band, so the band reads without colour: 0, 1 or 2.
const BAND_MARKS: Array[int] = [0, 1, 2]
const _STAIRS_WEIGHT := TripsScript.WALK_COLUMNS_PER_MINUTE * TripsScript.STAIRS_MINUTES  ## Columns a stairs leg counts as.

## Poses a figure can have; the renderer picks the sprite frames from them.
const POSE_WALK := 0
const POSE_STAIRS := 1
const POSE_ESCALATOR := 2

const TENANT_TICKS := 6
const FLAG_KNOWN := 1  ## Per room while figures() runs: someone resting there was met,
const FLAG_VISIBLE := 2  ## the room touches the area figures are built for,
const FLAG_USED := 4  ## someone there is awake,
const FLAG_ASLEEP := 8  ## someone there is asleep,
const FLAG_TENANT := 16  ## the room has a tenant, so it may join a suite,
const FLAG_LIVE := 32  ## someone in its suite (or it alone) is drawn: turns there are counted.

## Routes already found, keyed by trip ends; the caller keeps it and it is cleared when the
## floors or rooms change (see tower_renderer.gd).
var route_cache: Dictionary = {}
var _seen: Dictionary = {}  ## Person id -> Seen: what was worked out for them, kept while nothing it hangs on changed (#434).
var _seen_key: int = -1  ## What _seen was made for: the tower, its layout and the day.
var _seen_tick: int = 0
var _tenanted: Dictionary = {}
var _tenanted_key: int = -2
var _tenanted_tick: int = 0
var _room_cap: int = 64  ## Room ids seen so far, to size the per-room flags.
## What was worked out per person, by their index in the sim's list (kept like _seen): the id they were read
## for, their room and work room, the act key and act, and whether they are drawn (0 no, 1 yes, 2 in a hotel).
var _p_id := PackedInt32Array()
var _p_room := PackedInt32Array()
var _p_work := PackedInt32Array()
var _p_key := PackedInt32Array()
var _p_act := PackedInt32Array()
var _p_valid := PackedInt32Array()

## Rooms with someone resting in them, and rooms where someone resting is asleep, from the last figures()
## call: they cover everyone, culled or not (the renderer lights rooms by them).
var in_use: Dictionary = {}
var asleep: Dictionary = {}


## What figures() keeps per person, so a tick redoes only what moved: the room's run and kind, the
## Detailed look, the activity, and the placed figure of a resting person.
class Seen extends RefCounted:
	var room: int = -2  ## The room run, kind and column were read for (-2: none yet).
	var work: int = -2  ## The work room the look was read for.
	var run: Array[int] = []
	var kind: String = ""
	var column: int = 0
	var hotel: bool = false
	var look: Dictionary = {}
	var act_key: int = -1
	var act: int = 0
	var place_key: int = -1
	var figure: Dictionary = {}


static func color_of(band: int) -> Color:
	return BAND_COLORS[clampi(band, 0, BAND_COLORS.size() - 1)]


static func marks_of(band: int) -> int:
	return BAND_MARKS[clampi(band, 0, BAND_MARKS.size() - 1)]


## Where a trip is after elapsed of total minutes: [floor, column], whole numbers. The floor on a
## stairs or escalator leg is the nearer one; see along_f for the smooth version.
static func along(legs: Array, elapsed: int, total: int) -> Array[int]:
	var at := along_f(legs, elapsed, total)
	return [at["floor"], roundi(at["fx"])]


## Where a trip is after elapsed of total minutes, smoothly (the view may use floats):
## {"floor" (nearest floor), "fx" (column, fractional), "frow" (row, fractional, so height moves
## continuously between floors), "pose"}. A stairs or escalator leg crosses its link's width while
## it climbs one floor, so the figure moves along the drawn tread: up goes left to right, down
## right to left.
static func along_f(legs: Array, elapsed: int, total: int) -> Dictionary:
	var weight := 0
	for leg: Dictionary in legs:
		weight += _leg_weight(leg)
	var at := float(weight) * clampi(elapsed, 0, maxi(total, 1)) / maxi(total, 1)
	var done := 0.0
	for n in legs.size():
		var w := _leg_weight(legs[n])
		if at <= done + w or n == legs.size() - 1:
			var f := 0.0 if w == 0 else clampf((at - done) / w, 0.0, 1.0)
			return _leg_spot(legs[n], f)
		done += w
	return {}


static func _leg_spot(leg: Dictionary, f: float) -> Dictionary:
	var floor_number: int = leg["floor"]
	var from_row := VC.floor_to_row(floor_number)
	var kind: int = leg["kind"]
	var from_x: int = leg["from_x"]
	var to_x: int = leg["to_x"]
	if kind == RoutesScript.STAIRS or kind == RoutesScript.ESCALATOR:
		var to_row := VC.floor_to_row(leg["to_floor"])
		var across := f if to_row < from_row else 1.0 - f  # climbing runs left to right
		return {
			"floor": leg["to_floor"] if f > 0.5 else floor_number,
			"fx": from_x + across * (link_columns(kind) - 1),
			"frow": from_row + (to_row - from_row) * f,
			"pose": POSE_STAIRS if kind == RoutesScript.STAIRS else POSE_ESCALATOR,
		}
	return {"floor": floor_number, "fx": from_x + (to_x - from_x) * f, "frow": float(from_row), "pose": POSE_WALK}


## Columns the drawn link of a leg kind spans (its catalogue width).
static func link_columns(kind: int) -> int:
	return CatalogueScript.field("stairs" if kind == RoutesScript.STAIRS else "escalator", "width")


static func _leg_weight(leg: Dictionary) -> int:
	if leg["kind"] == RoutesScript.WALK:
		return absi((leg["to_x"] as int) - (leg["from_x"] as int))
	return _STAIRS_WEIGHT


## One entry per person drawn: {"id", "floor", "x", "fx", "frow", "pose", "band", "moving"}. A resting
## person also has "act" (an ActivityLook activity) and "px", "pfeet": where the pose is drawn, in native
## pixels, on a recipe spot of the room. Figures of resting people are kept between ticks while nothing
## they depend on changes, so treat them as read-only.
## area (world pixels; empty for everyone) limits the resting figures to rooms touching it (#451): the
## rest are skipped, but still take their turn at a spot so the ones kept sit where they always did.
## Moving figures are all kept, so they glide in from where they were. in_use and asleep are filled for
## everyone, culled or not.
func figures(tower: Object, area: Rect2 = Rect2()) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var people: PeopleScript = tower.people
	_forget_if_stale(tower)
	if _p_id.size() < people.count():  # grow the per-person arrays to the head count; a new slot knows no one
		var old := _p_id.size()
		_p_id.resize(people.count())
		_p_room.resize(people.count())
		_p_work.resize(people.count())
		_p_key.resize(people.count())
		_p_act.resize(people.count())
		_p_valid.resize(people.count())
		for k in range(old, _p_id.size()):
			_p_id[k] = -1
	var cull := area.size != Vector2.ZERO
	var left := area.position.x
	var right := area.end.x
	var top := area.position.y
	var bottom := area.end.y
	var flags := PackedByteArray()  # per room id: FLAG_* bits, grown as rooms are met
	flags.resize(_room_cap)
	var entries: Array = []  # one per room with someone resting, for Suites.groups
	var seq_room := PackedInt32Array()  # every resting person in order: their room
	var seq_slot := PackedInt32Array()  # ... and their place in the s_* arrays, or -1 when culled
	var s_seen: Array[Seen] = []
	var s_id := PackedInt32Array()
	var s_act := PackedInt32Array()
	var s_band := PackedInt32Array()
	var s_out := PackedInt32Array()
	var minute: int = tower.clock.minute_of_day()
	var night := ActivityLook.is_night(minute)
	var tenanted := _tenanted_rooms(tower)
	var met := PackedInt32Array()  # every room with someone resting
	var rows := people.drawn_rows()
	for at: int in range(0, rows.size(), PeopleScript.DRAWN_ROW):
		var state := rows[at + 2]
		if state == PeopleScript.TRIP_RIDING:
			continue  # queued at a shaft or riding: elevator_view draws the queue and the car's load
		var i := rows[at]
		var id := rows[at + 1]
		if _p_id[i] != id:  # a new person at this index: nothing is known of them
			_p_id[i] = id
			_p_room[i] = -2
			_p_work[i] = -2
			_p_key[i] = -1
		if state == PeopleScript.TRIP_MOVING:
			var spot := _moving_spot(tower, i)
			if not spot.is_empty():
				var mover := _seen_of(id)
				_read_look(tower, people, i, mover)
				var figure := {"id": id, "floor": spot["floor"], "x": roundi(spot["fx"]), "fx": spot["fx"], "frow": spot["frow"],
					"pose": spot["pose"], "band": PeopleScript.band_of(rows[at + 6]), "moving": true}
				figure.merge(mover.look, true)
				out.append(figure)
			continue
		var room := rows[at + 3]
		var work := rows[at + 4]
		if _p_room[i] != room or _p_work[i] != work:
			var changed := _seen_of(id)
			if changed.room != room or changed.work != work:
				_read_room(tower, people, i, changed)
			_p_room[i] = room
			_p_work[i] = work
			_p_key[i] = -1
			_p_valid[i] = 0 if changed.run.is_empty() else (2 if changed.hotel else 1)
		var valid := _p_valid[i]
		if valid == 0:
			continue
		var staying: bool = valid == 2 and tower.hotel.state_of(room) == HotelScript.STAYING
		var works_here := work == room
		var goal := rows[at + 5]
		var waiting := state == PeopleScript.TRIP_REQUESTED
		var act_key := ((((goal + 1) * 2 + int(works_here)) * 2 + int(waiting)) * 2 + int(staying)) * 2 + int(night)
		if act_key != _p_key[i]:
			_p_key[i] = act_key
			_p_act[i] = ActivityLook.classify(_seen_of(id).kind, works_here, goal, staying, minute, waiting)
		var act := _p_act[i]
		if room >= flags.size():
			flags.resize(room + 64)
		var flag := flags[room]
		if flag == 0:  # the first resting person met in this room
			var first := _seen_of(id)
			var run := first.run
			var x0 := run[1] * VC.CELL_W
			var y0 := VC.floor_to_row(run[0]) * VC.CELL_H
			met.append(room)
			flag = FLAG_KNOWN
			if tenanted.has(room):  # only tenanted rooms can join into suites
				flag |= FLAG_TENANT
				entries.append({"key": VC.floor_to_row(run[0]), "x": x0, "w": run[2] * VC.CELL_W, "kind": first.kind, "in_use": true, "room": room})
			if not cull or (x0 < right and x0 + run[2] * VC.CELL_W > left and y0 < bottom and y0 + VC.CELL_H > top):
				flag |= FLAG_VISIBLE
		flags[room] = flag | (FLAG_ASLEEP if act == ActivityLook.SLEEPING else FLAG_USED)
		if not flag & (FLAG_VISIBLE | FLAG_TENANT):
			continue  # off the area and in no suite: nobody's turn depends on this person
		seq_room.append(room)
		if flag & FLAG_VISIBLE:
			seq_slot.append(s_id.size())
			s_seen.append(_seen_of(id))
			s_id.append(id)
			s_act.append(act)
			s_band.append(PeopleScript.band_of(rows[at + 6]))
			s_out.append(out.size())
			out.append({})  # filled in below, once the suites are known
		else:
			seq_slot.append(-1)
	_room_cap = maxi(_room_cap, flags.size())
	var used: Dictionary = {}
	var sleeping: Dictionary = {}
	for room_id: int in met:
		var bits := flags[room_id]
		if bits & FLAG_USED:
			used[room_id] = true
		if bits & FLAG_ASLEEP:
			sleeping[room_id] = true
	if not seq_room.is_empty():
		_place_resting(out, seq_room, seq_slot, s_seen, s_id, s_act, s_band, s_out, entries, met, flags)
	var staff := _cleaners(tower)
	for cleaner: Dictionary in staff:
		used[cleaner["id"]] = true
	out.append_array(staff)
	in_use = used
	asleep = sleeping
	return out


## The tenanted rooms (Suites.tenanted_rooms), kept for TENANT_TICKS: they change when staff are hired or a
## shop is let, and the renderer reads them no more often (IN_USE_CHECK_TICKS).
func _tenanted_rooms(tower: Object) -> Dictionary:
	if _tenanted_key != _seen_key or tower.tick - _tenanted_tick >= TENANT_TICKS or tower.tick < _tenanted_tick:
		_tenanted = Suites.tenanted_rooms(tower)
		_tenanted_key = _seen_key
		_tenanted_tick = tower.tick
	return _tenanted


## The Seen kept for person id, made when there is none.
func _seen_of(id: int) -> Seen:
	var seen: Seen = _seen.get(id)
	if seen == null:
		seen = Seen.new()
		_seen[id] = seen
	return seen


## Clears what was kept per person when the tower, its layout or the day changed (a person's room, work
## and age band can then differ), or when time ran backwards (a load).
func _forget_if_stale(tower: Object) -> void:
	var clock: Object = tower.clock
	var key := [tower.get_instance_id(), tower.floors.revision, tower.grid.occupant_count(), tower.rooms.links.occupant_count(),
		tower.rooms.links_over.occupant_count(), clock.year(), clock.quarter(), clock.day_of_week()].hash()
	if key != _seen_key or tower.tick < _seen_tick or _seen.size() > 2 * tower.people.count() + 64:
		_seen.clear()
		_seen_key = key
		_p_id.clear()
		_p_room.clear()
		_p_work.clear()
		_p_key.clear()
		_p_act.clear()
		_p_valid.clear()
	_seen_tick = tower.tick


## Reads what a person's room and work fix: the run, kind, column and look.
func _read_room(tower: Object, people: PeopleScript, i: int, seen: Seen) -> void:
	var room := people.location_of(i)
	seen.room = room
	seen.act_key = -1
	seen.place_key = -1
	seen.run = tower.grid.run_of(room)
	if seen.run.is_empty():
		return
	seen.kind = tower.rooms.kind_of(room)
	seen.hotel = tower.hotel.is_hotel(room)
	seen.column = seen.run[1] + people.id_at(i) % maxi(seen.run[2], 1)
	seen.work = -2
	_read_look(tower, people, i, seen)


## Reads the Detailed look of person i once per work room.
func _read_look(tower: Object, people: PeopleScript, i: int, seen: Seen) -> void:
	var work := people.work_of(i)
	if seen.work != work:
		seen.work = work
		seen.look = _look_of(tower, people, i)
		seen.place_key = -1


## The Detailed look of person i: {"age", "child", "job"}. Built only for people who are drawn (#418).
static func _look_of(tower: Object, people: PeopleScript, i: int) -> Dictionary:
	var id: int = people.id_at(i)
	return {"age": tower.life.age_band_of(tower, id), "child": tower.life.is_child(id), "job": tower.rooms.kind_of(people.work_of(i))}


## Places the resting figures: each takes the next spot of its room, or of its suite when neighbouring
## rooms of one kind are all in use and draw as one (#276). seq_room and seq_slot list every resting person
## in order (their room, and their place in the p_* arrays or -1 when culled); each person takes a turn
## even when culled, so the others sit where they would with everyone drawn. entries is one per room for
## Suites.groups.
static func _place_resting(out: Array[Dictionary], seq_room: PackedInt32Array, seq_slot: PackedInt32Array, p_seen: Array[Seen], p_id: PackedInt32Array, p_act: PackedInt32Array, p_band: PackedInt32Array, p_out: PackedInt32Array, entries: Array, met: PackedInt32Array, flags: PackedByteArray) -> void:
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["key"] < b["key"] or (a["key"] == b["key"] and a["x"] < b["x"]))
	var suite_of: Dictionary = {}  # room id -> [left px, width px, first room of the suite]
	for group: Array[int] in Suites.groups(entries):
		var bounds := Suites.span(entries, group)
		for index: int in group:
			suite_of[(entries[index] as Dictionary)["room"]] = [bounds[0], bounds[1], (entries[group[0]] as Dictionary)["room"]]
	var live: Dictionary = {}  # seat -> true when someone there is drawn: only these seats need turns counted
	for room_id: int in met:
		if flags[room_id] & FLAG_VISIBLE:
			var shared: Array = suite_of.get(room_id, [])
			live[room_id if shared.is_empty() else shared[2]] = true
	for room_id: int in met:
		var shared: Array = suite_of.get(room_id, [])
		if live.has(room_id if shared.is_empty() else shared[2]):
			flags[room_id] |= FLAG_LIVE
	var turns: Dictionary = {}  # room (or a suite's first room) -> people placed there so far
	for n: int in seq_room.size():
		var room := seq_room[n]
		if not flags[room] & FLAG_LIVE:
			continue
		var joined: Variant = suite_of.get(room)
		var suite: Array = [] if joined == null else joined
		var seat: int = room if joined == null else suite[2]
		var turn: int = turns.get(seat, 0)
		turns[seat] = turn + 1
		var slot := seq_slot[n]
		if slot < 0:
			continue
		var seen := p_seen[slot]
		var band := p_band[slot]
		var act := p_act[slot]
		var suite_key := 0
		if not suite.is_empty():
			suite_key = (suite[0] as int) * 65536 + (suite[1] as int) + 1
		var key := ((turn * 16 + act) * 4 + band) * 4294967296 + suite_key
		if seen.place_key != key:  # a person whose turn, activity, mood and suite are as before keeps the figure
			seen.place_key = key
			seen.figure = _resting(seen.run, p_id[slot], seen.kind, act, turn, band, seen.column, room, suite)
			seen.figure.merge(seen.look, true)
		out[p_out[slot]] = seen.figure


## A resting figure of a run [floor, column, width, ...] doing `act`, placed on a spot of its room.
static func _resting(run: Array[int], id: int, kind: String, act: int, turn: int, band: int, column: int, room: int = 0, suite: Array = []) -> Dictionary:
	var width_px: int = run[2] * VC.CELL_W
	var origin: int = run[1] * VC.CELL_W
	var variant := RoomRecipes.variant_for(kind, room)
	if not suite.is_empty():  # one space across the joined rooms: its width, its left edge, its recipe
		origin = suite[0]
		width_px = suite[1]
		variant = RoomRecipes.SUITE
	var at := ActivityLook.place(act, ActivityLook.spot_for(kind, width_px, id, turn, act, variant), width_px)
	var row_top := VC.floor_to_row(run[0]) * VC.CELL_H
	return {"id": id, "floor": run[0], "x": column, "fx": float(column), "frow": float(VC.floor_to_row(run[0])),
		"pose": POSE_WALK, "band": band, "moving": false, "act": act, "px": origin + at.x, "pfeet": row_top + at.y}


## A housekeeper in each dirty hotel room one has claimed (on the way to it or cleaning it; the sim keeps
## no finer state to show). Their id is the room's id, a stand-in for a staff id.
func _cleaners(tower: Object) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if tower.housekeeping.busy_count() == 0:
		return out  # no one is on a job, so no room is claimed
	for room: int in tower.rooms.room_ids():
		if not tower.hotel.is_hotel(room) or not tower.hotel.is_dirty(room) or not tower.housekeeping.is_claimed(room):
			continue
		var run: Array[int] = tower.grid.run_of(room)
		if run.is_empty():
			continue
		var cleaner := _resting(run, room, tower.rooms.kind_of(room), ActivityLook.CLEANING, 1, 0, run[1], room)
		cleaner["age"] = 1  # Names.BAND_ADULT
		cleaner["child"] = false
		cleaner["job"] = "housekeeping"
		cleaner["staff"] = true  # not a person: the id is the room's, so a click must not open a person window
		out.append(cleaner)
	return out


func _moving_spot(tower: Object, i: int) -> Dictionary:
	var people: PeopleScript = tower.people
	var span: Array = tower.floors.lobby_span()
	if span.is_empty():
		return {}
	var entry: Array[int] = [TripsScript.GROUND_FLOOR, span[0]]
	var from := _spot(tower, people.trip_from(i), entry)
	var to := _spot(tower, people.goal_room(i), entry)
	var key := [from, to]
	if not route_cache.has(key):
		var route: Dictionary = RoutesScript.find(tower.floors, tower.rooms, tower.grid, from[0], from[1], to[0], to[1])
		route_cache[key] = route["legs"] if route["reason"] == RoutesScript.OK else []
	var legs: Array = route_cache[key]
	if legs.is_empty():
		return _still(from)
	var leg := people.trip_leg(i)
	legs = TripsScript.segment(legs, leg)
	if legs.is_empty():
		return _still(from)
	var total := people.trip_total(i)
	return along_f(legs, total - people.trip_left(i), total)


static func _still(spot: Array[int]) -> Dictionary:
	return {"floor": spot[0], "fx": float(spot[1]), "frow": float(VC.floor_to_row(spot[0])), "pose": POSE_WALK}


static func _spot(tower: Object, room: int, entry: Array[int]) -> Array[int]:
	var run: Array[int] = tower.grid.run_of(room)  # empty for NONE
	if run.is_empty():
		return entry
	return [run[0], run[1]]
