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
const MODE_NONE := 0  ## Per person: not drawn,
const MODE_OTHER := 1  ## drawn by someone else (in an elevator) or in no room that exists,
const MODE_MOVING := 2  ## moving: a figure every call,
const MODE_RESTING := 3  ## resting in a room: on that room's list.

## Routes already found, keyed by trip ends; the caller keeps it and it is cleared when the
## floors or rooms change (see tower_renderer.gd).
var route_cache: Dictionary = {}
var _seen: Dictionary = {}  ## Person id -> Seen: what was worked out for them, kept while nothing it hangs on changed (#434).
var _day_key: int = -1
var _room_snap: Dictionary = {}  ## Room -> [run, kind, hotel] as a Seen read it, to find the rooms a layout change touched.
var _work_snap: Dictionary = {}  ## Work room -> its kind as a Seen's look read it.
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
## Kept per person so that a call works out only who changed (#451): what the row looked like (rooms, goal,
## state, mood band), the pass that last saw them, how they are kept (MODE_*), the room list they are on (-1
## for none), their mood band, the activity key without its staying and night bits, and their Seen.
var _p_sig := PackedInt64Array()
var _p_stamp := PackedInt32Array()
var _p_mode := PackedInt32Array()
var _p_in := PackedInt32Array()
var _p_band := PackedInt32Array()
var _p_base := PackedInt32Array()
var _p_seen: Array[Seen] = []
var _synced: bool = false  ## The per-person arrays match the sim's people list as of _count and _next_id.
var _count: int = 0
var _next_id: int = 0
var _night: bool = false
var _pass: int = 0
var _tracked: int = 0  ## People with a mode other than MODE_NONE.
var _moving: Dictionary = {}  ## Person index -> true, for those moving.
var _hotel: Dictionary = {}  ## Person index -> true, for those resting in a hotel room.
var _rp: Dictionary = {}  ## Room id -> Array[int] of the resting people's indexes there, in the sim's order.
var _r_n := PackedInt32Array()  ## Per room id: how many rest there, how many of them are awake, how many asleep.
var _r_ver := PackedInt32Array()  ## Per room id: counts the times someone there came, went or changed activity.
var _seat_figs: Dictionary = {}  ## Room (or first room of a suite) -> [its versions and shape, the area it was placed for, its figures in turn order, and whose they are].
var _vis_epoch: int = 0  ## Counts the times the rooms on the area were chosen again.
var _r_used := PackedInt32Array()
var _r_sleep := PackedInt32Array()
var _used_set: Dictionary = {}  ## Rooms with someone awake resting in them, and rooms with someone asleep.
var _asleep_set: Dictionary = {}
var _room_runs: Dictionary = {}  ## Room id -> run, for each room someone has rested in since the last reset.
var _met_version: int = 0  ## Counts the times a room gained its first or lost its last resting person.
var _vis_area := Rect2()
var _vis_known: int = -1
var _vis_rooms: Array[int] = []  ## Rooms in _room_runs touching _vis_area, and the same as a set.
var _vis_set: Dictionary = {}
var _suite_met: int = -1  ## What the suites below were joined for: _met_version and the tenants.
var _suite_tenants: int = -1
var _suite_of: Dictionary = {}  ## Room id -> [left px, width px, first room of the suite], for joined rooms.
var _suite_rooms: Dictionary = {}  ## First room of a suite -> its rooms in order.
var _t_room := PackedInt32Array()  ## The tenanted rooms in floor-then-left order, with their floor row, left and width px.
var _t_floor := PackedInt32Array()
var _t_left := PackedInt32Array()
var _t_width := PackedInt32Array()
var _t_kind: Array[String] = []
var _tenanted_made: int = 0  ## Counts the times _tenanted was made.

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
## everyone, culled or not. Figures come out in the sim's person order, then the housekeepers.
## Nothing here works everyone out each call: one light pass over the sim's rows compares each person with
## the last call, and only those who changed are worked out again (#451). The room lists, light counts and
## spot turns are kept from that, so a call costs what moved plus what is on the area.
func figures(tower: Object, area: Rect2 = Rect2()) -> Array[Dictionary]:
	var people: PeopleScript = tower.people
	_forget_if_stale(tower)
	_sync_people(people)
	var minute: int = tower.clock.minute_of_day()
	var night := ActivityLook.is_night(minute)
	if night != _night:  # every activity key holds the night bit: work everyone out again
		_night = night
		_p_sig.fill(-1)
	_pass += 1
	var rows := people.drawn_rows()
	var row_count := rows.size() / PeopleScript.DRAWN_ROW
	for at: int in range(0, rows.size(), PeopleScript.DRAWN_ROW):
		var i := rows[at]
		var stress := rows[at + 6]
		var band := 2 if stress > PeopleScript.ANGRY_OVER else (1 if stress >= PeopleScript.UNEASY_FROM else 0)
		var sig := ((((((rows[at + 3] + 1) << 24 | (rows[at + 4] + 1)) << 4 | (rows[at + 5] + 1)) << 2) | rows[at + 2]) << 2) | band
		_p_stamp[i] = _pass
		if _p_sig[i] == sig:
			continue
		_p_sig[i] = sig
		_apply(tower, people, rows, at, band, minute, night)
	if _tracked != row_count:  # someone drawn last time is not any more
		for i: int in _p_mode.size():
			if _p_mode[i] != MODE_NONE and _p_stamp[i] != _pass:
				_drop(i)
	_recheck_hotel(tower, minute)
	_keep_suites(tower)
	_keep_visible(area)
	var figs: Array[Dictionary] = []
	var order := PackedInt64Array()  # person index << 24 | place in figs, sorted to give the sim's order
	_place_rooms(figs, order)
	for i: int in _moving:
		var id := _p_id[i]
		var spot := _moving_spot(tower, i)
		if spot.is_empty():
			continue
		var mover := _seen_of(id)
		_read_look(tower, people, i, mover)
		var figure := {"id": id, "floor": spot["floor"], "x": roundi(spot["fx"]), "fx": spot["fx"], "frow": spot["frow"],
			"pose": spot["pose"], "band": _p_band[i], "moving": true}
		figure.merge(mover.look, true)
		order.append(i << 24 | figs.size())
		figs.append(figure)
	order.sort()
	var out: Array[Dictionary] = []
	out.resize(order.size())
	for n: int in order.size():
		out[n] = figs[order[n] & 0xFFFFFF]
	var used := _used_set.duplicate()  # copies: the renderer reads them at its own pace
	var staff := _cleaners(tower)
	for cleaner: Dictionary in staff:
		used[cleaner["id"]] = true
	out.append_array(staff)
	in_use = used
	asleep = _asleep_set.duplicate()
	return out


## Sizes the per-person arrays to the head count. People added at the end (the ids and the count grew
## together) keep what is known of everyone else; any other change (a removal shifts the indexes) starts over.
func _sync_people(people: PeopleScript) -> void:
	var n := people.count()
	var next := people.next_id()
	if _synced and n >= _count and n - _count == next - _next_id:
		if n > _count:
			_resize_people(n)
	else:
		_reset_people()
		_resize_people(n)
		_synced = true
	_count = n
	_next_id = next


func _resize_people(n: int) -> void:
	var old := _p_id.size()
	_p_id.resize(n)
	_p_room.resize(n)
	_p_work.resize(n)
	_p_key.resize(n)
	_p_act.resize(n)
	_p_valid.resize(n)
	_p_sig.resize(n)
	_p_stamp.resize(n)
	_p_mode.resize(n)
	_p_in.resize(n)
	_p_band.resize(n)
	_p_base.resize(n)
	_p_seen.resize(n)
	for k in range(old, n):
		_p_id[k] = -1
		_p_sig[k] = -1
		_p_in[k] = -1
		_p_mode[k] = MODE_NONE
		_p_stamp[k] = 0


## Forgets everything kept per person and per room.
func _reset_people() -> void:
	_p_id.clear()
	_p_room.clear()
	_p_work.clear()
	_p_key.clear()
	_p_act.clear()
	_p_valid.clear()
	_p_sig.clear()
	_p_stamp.clear()
	_p_mode.clear()
	_p_in.clear()
	_p_band.clear()
	_p_base.clear()
	_p_seen.clear()
	_tracked = 0
	_moving.clear()
	_hotel.clear()
	_rp.clear()
	_r_n.clear()
	_r_ver.clear()
	_seat_figs.clear()
	_r_used.clear()
	_r_sleep.clear()
	_used_set.clear()
	_asleep_set.clear()
	_room_runs.clear()
	_met_version += 1
	_vis_known = -1
	_suite_met = -1
	_suite_tenants = -1


## Works out the person at rows[at], whose state, rooms, goal or mood band differ from the last call: where
## they are kept now (moving, resting on a room's list, or nowhere).
func _apply(tower: Object, people: PeopleScript, rows: PackedInt32Array, at: int, band: int, minute: int, night: bool) -> void:
	var i := rows[at]
	var id := rows[at + 1]
	var state := rows[at + 2]
	match _p_mode[i]:
		MODE_NONE:
			_tracked += 1
		MODE_MOVING:
			_moving.erase(i)
		MODE_RESTING:
			_unlist(i)
	if _p_id[i] != id:  # a new person at this index: nothing is known of them
		_p_id[i] = id
		_p_room[i] = -2
		_p_work[i] = -2
		_p_key[i] = -1
	_p_band[i] = band
	if state == PeopleScript.TRIP_RIDING:
		_p_mode[i] = MODE_OTHER  # queued at a shaft or riding: elevator_view draws the queue and the car's load
		return
	if state == PeopleScript.TRIP_MOVING:
		_p_mode[i] = MODE_MOVING
		_moving[i] = true
		return
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
		_p_mode[i] = MODE_OTHER
		return
	var seen := _seen_of(id)
	var staying: bool = valid == 2 and tower.hotel.state_of(room) == HotelScript.STAYING
	var goal := rows[at + 5]
	var works_here := work == room
	var waiting := state == PeopleScript.TRIP_REQUESTED
	_p_base[i] = ((goal + 1) * 2 + int(works_here)) * 2 + int(waiting)
	var act_key := (_p_base[i] * 2 + int(staying)) * 2 + int(night)
	if act_key != _p_key[i]:
		_p_key[i] = act_key
		_p_act[i] = ActivityLook.classify(seen.kind, works_here, goal, staying, minute, waiting)
	_p_seen[i] = seen
	_p_mode[i] = MODE_RESTING
	_list(i, room, seen)
	if valid == 2:
		_hotel[i] = true


## A person no longer drawn: forget where they were kept.
func _drop(i: int) -> void:
	match _p_mode[i]:
		MODE_MOVING:
			_moving.erase(i)
		MODE_RESTING:
			_unlist(i)
	_p_mode[i] = MODE_NONE
	_p_sig[i] = -1
	_tracked -= 1


## Adds resting person i to their room's list (by index, so the list is in the sim's order) and counts them
## towards the room's lights by their activity.
func _list(i: int, room: int, seen: Seen) -> void:
	if room >= _r_n.size():
		var grown := room + 64
		_r_ver.resize(grown)
		_r_n.resize(grown)
		_r_used.resize(grown)
		_r_sleep.resize(grown)
	var list: Array[int] = _rp.get(room, [] as Array[int])
	if list.is_empty():
		_rp[room] = list
	list.insert(list.bsearch(i), i)
	_p_in[i] = room
	if not _room_runs.has(room):
		_room_runs[room] = seen.run
	_r_n[room] += 1
	if _r_n[room] == 1:
		_met_version += 1
	_count_act(room, _p_act[i], 1)


func _unlist(i: int) -> void:
	var room := _p_in[i]
	var list: Array[int] = _rp[room]
	list.remove_at(list.bsearch(i))
	_p_in[i] = -1
	_hotel.erase(i)
	_r_n[room] -= 1
	if _r_n[room] == 0:
		_met_version += 1
	_count_act(room, _p_act[i], -1)


## Adds delta resting people doing act to the room's lights: awake ones light it, sleeping ones darken it.
func _count_act(room: int, act: int, delta: int) -> void:
	_r_ver[room] += 1
	if act == ActivityLook.SLEEPING:
		_r_sleep[room] += delta
		if _r_sleep[room] > 0:
			_asleep_set[room] = true
		else:
			_asleep_set.erase(room)
	else:
		_r_used[room] += delta
		if _r_used[room] > 0:
			_used_set[room] = true
		else:
			_used_set.erase(room)


## Guests come and go without their row changing, so each resting guest's activity is looked at every call.
func _recheck_hotel(tower: Object, minute: int) -> void:
	for i: int in _hotel:
		var room := _p_in[i]
		var staying: bool = tower.hotel.state_of(room) == HotelScript.STAYING
		var act_key := (_p_base[i] * 2 + int(staying)) * 2 + int(_night)
		if act_key == _p_key[i]:
			continue
		_p_key[i] = act_key
		var seen := _p_seen[i]
		var goal := _p_base[i] / 4 - 1
		var works_here := (_p_base[i] / 2) % 2 == 1
		var act := ActivityLook.classify(seen.kind, works_here, goal, staying, minute, _p_base[i] % 2 == 1)
		if act != _p_act[i]:
			_count_act(room, _p_act[i], -1)
			_p_act[i] = act
			_count_act(room, act, 1)


## Joins the tenanted rooms with someone resting into suites (Suites.groups, #276), again only when the
## tenants or the rooms with someone resting changed.
func _keep_suites(tower: Object) -> void:
	var tenanted := _tenanted_rooms(tower)
	if _suite_tenants != _tenanted_made:
		_suite_tenants = _tenanted_made
		var packed := PackedInt64Array()
		for room: int in tenanted:
			var run: Array[int] = tower.grid.run_of(room)
			if not run.is_empty():  # floor row, left px, room: sorted as the entries are, floor then left
				packed.append(((VC.floor_to_row(run[0]) + (1 << 20)) << 42) | ((run[1] * VC.CELL_W) << 21) | room)
		packed.sort()
		_t_room.resize(packed.size())
		_t_floor.resize(packed.size())
		_t_left.resize(packed.size())
		_t_width.resize(packed.size())
		_t_kind.clear()
		for n: int in packed.size():
			var room := (packed[n] & 0x1FFFFF) as int
			var run: Array[int] = tower.grid.run_of(room)
			_t_room[n] = room
			_t_floor[n] = VC.floor_to_row(run[0])
			_t_left[n] = run[1] * VC.CELL_W
			_t_width[n] = run[2] * VC.CELL_W
			_t_kind.append(tower.rooms.kind_of(room))
		_suite_met = -1
	if _suite_met == _met_version:
		return
	_suite_met = _met_version
	_suite_of.clear()
	_suite_rooms.clear()
	var group: Array[int] = []
	for n: int in _t_room.size():
		var room := _t_room[n]
		if room >= _r_n.size() or _r_n[room] <= 0:
			continue
		if not group.is_empty():
			var before: int = group[group.size() - 1]
			if _t_floor[before] == _t_floor[n] and _t_left[before] + _t_width[before] == _t_left[n] \
					and _t_kind[before] == _t_kind[n] and Suites.joins(_t_kind[n]):
				group.append(n)
				continue
			_close_suite(group)
		group = [n]
	_close_suite(group)


func _close_suite(group: Array[int]) -> void:
	if group.size() < 2:
		return
	var last: int = group[group.size() - 1]
	var left: int = _t_left[group[0]]
	var seat: int = _t_room[group[0]]
	var rooms: Array[int] = []
	for n: int in group:
		_suite_of[_t_room[n]] = [left, _t_left[last] + _t_width[last] - left, seat]
		rooms.append(_t_room[n])
	_suite_rooms[seat] = rooms


## The rooms known so far that touch the area (all of them when it is empty), again only when the area or
## the rooms known changed.
func _keep_visible(area: Rect2) -> void:
	if _vis_known == _room_runs.size() and _vis_area == area:
		return
	_vis_known = _room_runs.size()
	_vis_area = area
	var rooms: Array[int] = []
	var set: Dictionary = {}
	var cull := area.size != Vector2.ZERO
	for room: int in _room_runs:
		var run: Array[int] = _room_runs[room]
		var x0 := run[1] * VC.CELL_W
		var y0 := VC.floor_to_row(run[0]) * VC.CELL_H
		if not cull or (x0 < area.end.x and x0 + run[2] * VC.CELL_W > area.position.x and y0 < area.end.y and y0 + VC.CELL_H > area.position.y):
			rooms.append(room)
			set[room] = true
	if set != _vis_set:  # the same rooms again leave the figures placed for them good
		_vis_epoch += 1
	_vis_rooms = rooms
	_vis_set = set


## Places the resting figures of the rooms on the area: each takes the next spot of its room, or of its
## suite when neighbouring rooms of one kind are all in use and draw as one (#276). A suite counts its
## turns across all its rooms in the sim's order, those off the area included, so the ones drawn sit where
## they would with everyone drawn.
func _place_rooms(figs: Array[Dictionary], order: PackedInt64Array) -> void:
	var done: Dictionary = {}
	for room: int in _vis_rooms:
		if room >= _r_n.size() or _r_n[room] <= 0:
			continue
		var joined: Variant = _suite_of.get(room)
		var suite: Array = [] if joined == null else joined
		var seat: int = room if joined == null else suite[2]
		if done.has(seat):
			continue
		done[seat] = true
		var members: Array[int] = [room]
		if joined != null:
			members = _suite_rooms[seat]
		var stamp := _r_ver[room] if joined == null else 0
		if joined != null:  # moves when anyone in any room of the suite changes
			for member: int in members:
				if member < _r_ver.size():
					stamp += _r_ver[member]
		var shape := 0 if joined == null else (suite[0] as int) * 65536 + (suite[1] as int) + 1
		var kept: Array = _seat_figs.get(seat, [])
		if kept.is_empty() or kept[0] != stamp or kept[1] != shape or kept[2] != _vis_epoch:
			var everyone: Array[int] = []
			for member: int in members:
				if member < _r_n.size() and _r_n[member] > 0:
					everyone.append_array(_rp[member] as Array[int])
			if joined != null:
				everyone.sort()
			var placed: Array[Dictionary] = []
			var scratch := PackedInt64Array()
			var who := PackedInt32Array()
			for turn: int in everyone.size():
				var at_room := _p_in[everyone[turn]]
				if _vis_set.has(at_room):
					_place(placed, scratch, everyone[turn], turn, at_room, suite)
					who.append(everyone[turn])
			kept = [stamp, shape, _vis_epoch, placed, who]
			_seat_figs[seat] = kept
		var here: Array[Dictionary] = kept[3]
		var who_here: PackedInt32Array = kept[4]
		for n: int in here.size():
			order.append(who_here[n] << 24 | figs.size())
			figs.append(here[n])


func _place(figs: Array[Dictionary], order: PackedInt64Array, i: int, turn: int, room: int, suite: Array) -> void:
	var seen := _p_seen[i]
	var band := _p_band[i]
	var act := _p_act[i]
	var suite_key := 0
	if not suite.is_empty():
		suite_key = (suite[0] as int) * 65536 + (suite[1] as int) + 1
	var key := ((turn * 16 + act) * 4 + band) * 4294967296 + suite_key
	if seen.place_key != key:  # a person whose turn, activity, mood and suite are as before keeps the figure
		seen.place_key = key
		seen.figure = _resting(seen.run, _p_id[i], seen.kind, act, turn, band, seen.column, room, suite)
		seen.figure.merge(seen.look, true)
	order.append(i << 24 | figs.size())
	figs.append(seen.figure)


## The tenanted rooms (Suites.tenanted_rooms), kept for TENANT_TICKS: they change when staff are hired or a
## shop is let, and the renderer reads them no more often (IN_USE_CHECK_TICKS).
func _tenanted_rooms(tower: Object) -> Dictionary:
	if _tenanted_key != _day_key or tower.tick - _tenanted_tick >= TENANT_TICKS or tower.tick < _tenanted_tick:
		_tenanted = Suites.tenanted_rooms(tower)
		_tenanted_key = _day_key
		_tenanted_tick = tower.tick
		_tenanted_made += 1
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
	var day_key := [tower.get_instance_id(), clock.year(), clock.quarter(), clock.day_of_week()].hash()
	var key := [day_key, tower.floors.revision, tower.grid.occupant_count(), tower.rooms.links.occupant_count(),
		tower.rooms.links_over.occupant_count()].hash()
	if day_key != _day_key or tower.tick < _seen_tick or _seen.size() > 2 * tower.people.count() + 64:
		_seen.clear()
		_room_snap.clear()
		_work_snap.clear()
		_seen_key = key
		_day_key = day_key
		_synced = false
	elif key != _seen_key:  # the layout changed: only people whose rooms changed are worked out again
		_seen_key = key
		_revalidate_layout(tower)
	_seen_tick = tower.tick


## After a layout change keeps what was worked out for everyone whose room and work room are as they were
## (same run, kind and hotel flag), and marks the rest to be read again. Rooms are never renumbered, so a
## room that is unchanged looks the same to everyone in it.
func _revalidate_layout(tower: Object) -> void:
	var gone: Dictionary = {}  # rooms whose run, kind or hotel flag differ from when a Seen read them
	for room: int in _room_snap:
		var snap: Array = _room_snap[room]
		var run: Array[int] = tower.grid.run_of(room)
		if run != snap[0] or (not run.is_empty() and (tower.rooms.kind_of(room) != snap[1] or tower.hotel.is_hotel(room) != snap[2])):
			gone[room] = true
	for room: int in _work_snap:
		if not gone.has(room) and tower.rooms.kind_of(room) != _work_snap[room]:
			gone[room] = true
	if gone.is_empty():
		return
	var stale: Dictionary = {}  # person id -> true, for those to read again
	for id: int in _seen:
		var seen: Seen = _seen[id]
		if gone.has(seen.room) or gone.has(seen.work):
			seen.room = -2
			seen.work = -2
			stale[id] = true
	for room: int in gone:
		_room_snap.erase(room)
		_work_snap.erase(room)
		_room_runs.erase(room)
	_vis_known = -1
	for i: int in _p_id.size():
		if stale.has(_p_id[i]):
			_p_room[i] = -2
			_p_work[i] = -2
			_p_sig[i] = -1


## Reads what a person's room and work fix: the run, kind, column and look.
func _read_room(tower: Object, people: PeopleScript, i: int, seen: Seen) -> void:
	var room := people.location_of(i)
	seen.room = room
	seen.act_key = -1
	seen.place_key = -1
	seen.run = tower.grid.run_of(room)
	if seen.run.is_empty():
		_room_snap[room] = [seen.run, "", false]
		return
	seen.kind = tower.rooms.kind_of(room)
	seen.hotel = tower.hotel.is_hotel(room)
	_room_snap[room] = [seen.run, seen.kind, seen.hotel]
	seen.column = seen.run[1] + people.id_at(i) % maxi(seen.run[2], 1)
	seen.work = -2
	_read_look(tower, people, i, seen)


## Reads the Detailed look of person i once per work room.
func _read_look(tower: Object, people: PeopleScript, i: int, seen: Seen) -> void:
	var work := people.work_of(i)
	if seen.work != work:
		seen.work = work
		seen.look = _look_of(tower, people, i)
		_work_snap[work] = seen.look["job"]
		seen.place_key = -1


## The Detailed look of person i: {"age", "child", "job"}. Built only for people who are drawn (#418).
static func _look_of(tower: Object, people: PeopleScript, i: int) -> Dictionary:
	var id: int = people.id_at(i)
	return {"age": tower.life.age_band_of(tower, id), "child": tower.life.is_child(id), "job": tower.rooms.kind_of(people.work_of(i))}


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
