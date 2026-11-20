class_name LifeEvents
extends RefCounted
## Life events (12.3): rare seeded daily happenings between people, run at the rest-period
## evaluation after moods (Tower.evaluate_tenants). Each step draws from the tower's seeded RNG
## once per eligible candidate, in id order, so a run is the same everywhere.
##   COUPLE      two uncoupled adults who work in the same office or live in the same condo pair up
##   MOVE_IN     a couple living in two condos moves into one that has room; the other is freed
##               (vacant again, the sale price refunded, as when a tenant leaves)
##   CHILD       a couple sharing a condo with a free place gains a child (young, title Child)
##   PROMOTION   an adult office worker gets a senior title and a mood lift
##   RETIREMENT  a senior office worker leaves the office; maybe takes a condo place as a resident
##   LEFT_TOWN   someone whose mood has stayed low leaves town
## Saved: couples (pairs of ids), children, promoted ids, and a ring log of the last LOG_MAX
## stories as tick, kind, a, b, room (people ids, -1 for none). Percentages are per day per
## candidate and are instance fields so tests can force them. All unverified and tunable.

const NamesScript := preload("res://scripts/sim/names.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")
const MoodScript := preload("res://scripts/sim/mood.gd")
const MessagesScript := preload("res://scripts/sim/messages.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")

const COUPLE := 0
const MOVE_IN := 1
const CHILD := 2
const PROMOTION := 3
const RETIREMENT := 4
const LEFT_TOWN := 5
const KIND_COUNT := 6
const KIND_NAMES: Array[String] = ["became a couple", "moved in together", "had a child", "was promoted", "retired", "left town"]

const LOG_MAX := 50
const STORY_INTS := 5
const PROMOTION_MOOD := 10
const LEAVE_LOW_DAYS := 2  ## Days of low mood before someone may leave town.

var couple_percent: int = 3
var move_in_percent: int = 20
var child_percent: int = 3
var promotion_percent: int = 1
var retire_percent: int = 4
var leave_percent: int = 20
var retire_stay_percent: int = 50  ## Chance a retiree stays on as a resident when a condo has a place.

var _couples: Array[int] = []  ## Flat pairs of person ids, lower id first.
var _kids: Array[int] = []
var _promoted: Array[int] = []
var _log: Array[int] = []  ## Flat STORY_INTS per story, oldest first.


# --- Reading (for the view and tests) ---------------------------------------------------------

func partner_of(id: int) -> int:
	for n in _couples.size() / 2:
		if _couples[2 * n] == id:
			return _couples[2 * n + 1]
		if _couples[2 * n + 1] == id:
			return _couples[2 * n]
	return -1


func couple_count() -> int:
	return _couples.size() / 2


func is_child(id: int) -> bool:
	return _kids.has(id)


func is_promoted(id: int) -> bool:
	return _promoted.has(id)


func story_count() -> int:
	return _log.size() / STORY_INTS


## Story n (0 is the oldest kept) as [tick, kind, a, b, room].
func story(n: int) -> Array[int]:
	var found: Array[int] = []
	for k in STORY_INTS:
		found.append(_log[n * STORY_INTS + k])
	return found


## A person's age band: children are always young.
func age_band(seed_value: int, id: int) -> int:
	return NamesScript.BAND_YOUNG if is_child(id) else NamesScript.age_band(seed_value, id)


## A person's title: "Child" for children, a senior title for the promoted, else the usual one.
func title_for(seed_value: int, id: int, kind: String) -> String:
	if is_child(id):
		return "Child"
	if is_promoted(id) and kind == "office":
		return NamesScript.title_for(seed_value, id, kind, NamesScript.BAND_SENIOR)
	return NamesScript.title_for(seed_value, id, kind, age_band(seed_value, id))


## Story n as a sentence for the view, from the people's names.
func describe(n: int, names: Object) -> String:
	var entry := story(n)
	var who: String = names.name_of(entry[2])
	if entry[3] >= 0 and (entry[1] == COUPLE or entry[1] == MOVE_IN):
		who += " and " + names.name_of(entry[3])
	return "%s %s" % [who, KIND_NAMES[entry[1]]]


# --- The day -----------------------------------------------------------------------------------

## Runs every step once. t is the Tower (rooms, people, grid, ledger, messages, rng, names, tick).
func daily(t: Object) -> void:
	_prune(t.people)
	couple_up(t)
	move_in(t)
	have_children(t)
	promote(t)
	retire(t)
	leave_town(t)


func _record(tick: int, kind: int, a: int, b: int, room: int) -> void:
	_log.append_array([tick, kind, a, b, room] as Array[int])
	while _log.size() > LOG_MAX * STORY_INTS:
		for k in STORY_INTS:
			_log.remove_at(0)


## Forgets couples, children and promotions of people who are gone.
func _prune(people: PeopleScript) -> void:
	var couples: Array[int] = []
	for n in _couples.size() / 2:
		if people.index_of(_couples[2 * n]) != -1 and people.index_of(_couples[2 * n + 1]) != -1:
			couples.append(_couples[2 * n])
			couples.append(_couples[2 * n + 1])
	_couples = couples
	var kids: Array[int] = []
	for id in _kids:
		if people.index_of(id) != -1:
			kids.append(id)
	_kids = kids
	var promoted: Array[int] = []
	for id in _promoted:
		if people.index_of(id) != -1:
			promoted.append(id)
	_promoted = promoted


func _residents(people: PeopleScript, room: int) -> int:
	var n := 0
	for i in people.count():
		if people.home_of(i) == room:
			n += 1
	return n


func _has_place(t: Object, room: int) -> bool:
	return t.rooms.kind_of(room) == "condo" and t.rooms.is_sold(room) and _residents(t.people, room) < t.rooms.people_in(room)


## Makes two people a couple (lower id first). Public so tests can set one up.
func pair_up(a: int, b: int) -> void:
	_couples.append(mini(a, b))
	_couples.append(maxi(a, b))


func age_band_of(t: Object, id: int) -> int:
	return age_band(t.names.name_seed, id)


func couple_up(t: Object) -> void:
	var by_room := {}  # room -> ids of uncoupled adults, in id order
	for i in t.people.count():
		var id: int = t.people.id_at(i)
		var room := MoodScript.room_of(t.people, i)
		var kind: String = t.rooms.kind_of(room) if room != PeopleScript.NONE else ""
		if (kind == "office" or kind == "condo") and partner_of(id) == -1 and age_band_of(t, id) == NamesScript.BAND_ADULT:
			if not by_room.has(room):
				by_room[room] = [] as Array[int]
			by_room[room].append(id)
	var rooms: Array = by_room.keys()
	rooms.sort()
	for room: int in rooms:
		var ids: Array[int] = by_room[room]
		if ids.size() >= 2 and t.rng.next_below(100) < couple_percent:
			pair_up(ids[0], ids[1])
			_record(t.tick, COUPLE, ids[0], ids[1], room)


func move_in(t: Object) -> void:
	for n in _couples.size() / 2:
		var a: int = _couples[2 * n]
		var b: int = _couples[2 * n + 1]
		var ia: int = t.people.index_of(a)
		var ib: int = t.people.index_of(b)
		if ia == -1 or ib == -1:
			continue
		var ha: int = t.people.home_of(ia)
		var hb: int = t.people.home_of(ib)
		if ha == PeopleScript.NONE or hb == PeopleScript.NONE or ha == hb:
			continue
		if t.rng.next_below(100) >= move_in_percent:
			continue
		if _has_place(t, ha):
			t.people.set_home(ib, ha)
			_freed(t, hb, ha, a, b)
		elif _has_place(t, hb):
			t.people.set_home(ia, hb)
			_freed(t, ha, hb, a, b)


## Logs a move-in and, if the condo they left has nobody now, frees it: vacant, price refunded.
func _freed(t: Object, old: int, target: int, a: int, b: int) -> void:
	_record(t.tick, MOVE_IN, a, b, target)
	if _residents(t.people, old) > 0:
		return
	var run: Array[int] = t.grid.run_of(old)
	var price: int = CatalogueScript.cost("condo")
	t.rooms.set_sold(old, false)
	t.ledger.payout(t.tick, price, old)
	t.messages.add(t.tick, MessagesScript.TENANT_LEFT, CatalogueScript.IDS.find("condo"), run[0] if not run.is_empty() else 0)
	t.messages.add(t.tick, MessagesScript.CONDO_REFUND, price)


func have_children(t: Object) -> void:
	for n in _couples.size() / 2:
		var a: int = _couples[2 * n]
		var ia: int = t.people.index_of(a)
		var ib: int = t.people.index_of(_couples[2 * n + 1])
		if ia == -1 or ib == -1:
			continue
		var home: int = t.people.home_of(ia)
		if home == PeopleScript.NONE or home != t.people.home_of(ib) or not _has_place(t, home):
			continue
		if t.rng.next_below(100) < child_percent:
			var kid: int = t.people.add_person(home, PeopleScript.NONE, t.rng)
			_kids.append(kid)
			_record(t.tick, CHILD, a, kid, home)


func promote(t: Object) -> void:
	var chosen: Array[int] = []
	for i in t.people.count():
		var id: int = t.people.id_at(i)
		var work: int = t.people.work_of(i)
		if work != PeopleScript.NONE and t.rooms.kind_of(work) == "office" and age_band_of(t, id) == NamesScript.BAND_ADULT and not is_promoted(id):
			if t.rng.next_below(100) < promotion_percent:
				chosen.append(id)
	for id in chosen:
		var i: int = t.people.index_of(id)
		_promoted.append(id)
		t.people.set_mood(i, t.people.mood_of(i) + PROMOTION_MOOD)
		_record(t.tick, PROMOTION, id, -1, t.people.work_of(i))


func retire(t: Object) -> void:
	var chosen: Array[int] = []
	for i in t.people.count():
		var work: int = t.people.work_of(i)
		if work != PeopleScript.NONE and t.rooms.kind_of(work) == "office" and age_band_of(t, t.people.id_at(i)) == NamesScript.BAND_SENIOR:
			if t.rng.next_below(100) < retire_percent:
				chosen.append(t.people.id_at(i))
	for id in chosen:
		var i: int = t.people.index_of(id)
		var office: int = t.people.work_of(i)
		t.people.remove_person(i)
		var stays := -1
		if t.rng.next_below(100) < retire_stay_percent:
			var ids: Array[int] = t.rooms.room_ids()
			ids.sort()
			for room in ids:
				if _has_place(t, room):
					stays = t.people.add_person(room, PeopleScript.NONE, t.rng)
					break
		_record(t.tick, RETIREMENT, id, stays, office)


func leave_town(t: Object) -> void:
	var chosen: Array[int] = []
	for i in t.people.count():
		if t.people.mood_of(i) < MoodScript.LOW_BELOW and t.people.low_days_of(i) >= LEAVE_LOW_DAYS and t.rng.next_below(100) < leave_percent:
			chosen.append(t.people.id_at(i))
	for id in chosen:
		var i: int = t.people.index_of(id)
		var room := MoodScript.room_of(t.people, i)
		var partner := partner_of(id)
		t.people.remove_person(i)
		_record(t.tick, LEFT_TOWN, id, partner, room)
	_prune(t.people)


# --- Saving ------------------------------------------------------------------------------------

func state_ints() -> Array[int]:
	var ints: Array[int] = [_couples.size() / 2]
	ints.append_array(_couples)
	ints.append(_kids.size())
	ints.append_array(_kids)
	ints.append(_promoted.size())
	ints.append_array(_promoted)
	ints.append(_log.size() / STORY_INTS)
	ints.append_array(_log)
	return ints


static func valid_ints(ints: Array) -> bool:
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	var at := 0
	for width in [2, 1, 1]:
		if at >= ints.size() or ints[at] < 0 or ints[at] > 1000000:
			return false
		at += 1 + width * ints[at]
	if at >= ints.size() or ints[at] < 0 or ints[at] > LOG_MAX or ints.size() != at + 1 + STORY_INTS * ints[at]:
		return false
	for n in ints[at]:
		var kind: int = ints[at + 2 + n * STORY_INTS]
		if kind < 0 or kind >= KIND_COUNT:
			return false
	return true


func load_ints(ints: Array) -> void:
	var at := 0
	_couples = []
	_kids = []
	_promoted = []
	_log = []
	for n in ints[at] * 2:
		_couples.append(ints[at + 1 + n])
	at += 1 + 2 * ints[at]
	for n in ints[at]:
		_kids.append(ints[at + 1 + n])
	at += 1 + ints[at]
	for n in ints[at]:
		_promoted.append(ints[at + 1 + n])
	at += 1 + ints[at]
	for n in ints[at] * STORY_INTS:
		_log.append(ints[at + 1 + n])
