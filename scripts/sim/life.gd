class_name LifeEvents
extends RefCounted
## Life events (12.3): rare seeded daily happenings between people, run at the rest-period
## evaluation after moods (Tower.evaluate_tenants). Each step draws from the tower's seeded RNG
## once per eligible candidate, in id order, so a run is the same everywhere.
##   COUPLE      two uncoupled adults who work in the same office or live in the same condo pair up
##   MOVE_IN     a couple living in two condos moves into one that has room; the other is freed
##               (vacant again, the sale price refunded as when an owner leaves; it can be sold again)
##   CHILD       a couple sharing a condo with a free place gains a child (young, title Child)
##   PROMOTION   an adult office worker gets a senior title and a mood lift
##   RETIREMENT  a senior office worker leaves the office (the office hires a replacement, so it never
##               drains); maybe takes a condo place as a resident
##   LEFT_TOWN   someone whose mood has stayed low leaves town
## When the last resident of a sold condo leaves town or retires, the condo is vacated and the sale price
## refunded (the reference's owner-leaves rule), so vacate and resell nets zero.
## Saved: couples (pairs of ids), children, promoted ids, and a ring log of the last LOG_MAX
## stories as tick, kind, a, b, room (people ids, -1 for none). Percentages are per day per
## candidate and are instance fields (set from the RATE constants below, the one place to tune them)
## so tests can force them. All unverified and tunable.

const NamesScript := preload("res://scripts/sim/names.gd")
const ApartmentsScript := preload("res://scripts/sim/apartments.gd")
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

## Rates: every tunable chance in one place.
const COUPLE_PERCENT := 3  ## Per day, per room with two uncoupled adults.
const MOVE_IN_PERCENT := 20  ## Per day, per couple living apart.
const CHILD_PERCENT := 3  ## Per day, per couple sharing a condo with a free place.
const PROMOTION_PERCENT := 1  ## Per day, per adult office worker.
const RETIRE_PER_100000 := 36  ## Per day, per senior office worker: about 1 in 400 per week.
const LEAVE_PERCENT := 20  ## Per day, per person who has been low long enough.
const RETIRE_STAY_PERCENT := 50  ## Chance a retiree stays on as a resident when a condo has a place.

var couple_percent: int = COUPLE_PERCENT
var move_in_percent: int = MOVE_IN_PERCENT
var child_percent: int = CHILD_PERCENT
var promotion_percent: int = PROMOTION_PERCENT
var retire_per_100000: int = RETIRE_PER_100000
var leave_percent: int = LEAVE_PERCENT
var retire_stay_percent: int = RETIRE_STAY_PERCENT

var _couples: Array[int] = []  ## Flat pairs of person ids, lower id first.
var _kids: Array[int] = []
var _promoted: Array[int] = []
var _log: Array[int] = []  ## Flat STORY_INTS per story, oldest first.


# --- Reading (for the view and tests) ---------------------------------------------------------


## Id -> NamesScript.age_band for the seed in _bands_seed: the band is a pure function of both, and the daily passes ask for
## every person three times. Derived, never saved or hashed.
var _bands: Dictionary = {}
var _bands_seed: int = 0
const BANDS_MAX := 100000

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
	return CatalogueScript.is_condo(t.rooms.kind_of(room)) and not t.rooms.is_charred(room) and t.rooms.is_sold(room) and _residents(t.people, room) < t.rooms.people_in(room)


## Makes two people a couple (lower id first). Public so tests can set one up.
func pair_up(a: int, b: int) -> void:
	_couples.append(mini(a, b))
	_couples.append(maxi(a, b))


func age_band_of(t: Object, id: int) -> int:
	return age_band(t.names.name_seed, id)


## The ids in a list as a set, for a loop that asks about every person (#416).
static func _set_of(ids: Array[int]) -> Dictionary:
	var found := {}
	for id in ids:
		found[id] = true
	return found


## Same answer as age_band, read from a set of the children.
func _age_band_in(kids: Dictionary, t: Object, id: int) -> int:
	if kids.has(id):
		return NamesScript.BAND_YOUNG
	var seed_value: int = t.names.name_seed
	if seed_value != _bands_seed or _bands.size() > BANDS_MAX:  # the cache is only good for one seed, and is kept small
		_bands.clear()
		_bands_seed = seed_value
	if _bands.has(id):
		return _bands[id]
	var band := NamesScript.age_band(seed_value, id)
	_bands[id] = band
	return band


func couple_up(t: Object) -> void:
	var by_room := {}  # room -> ids of uncoupled adults, in id order
	var kids := _set_of(_kids)
	var coupled := _set_of(_couples)
	var rows: PackedInt64Array = t.people.eval_rows()  # one packed pass, and the kind test once per room (#452)
	var eligible := {}  # room -> true when its people may couple
	var b := 0
	while b < rows.size():
		var work := int(rows[b + 2])
		var room := work if work != PeopleScript.NONE else int(rows[b + 1])
		if not eligible.has(room):
			var kind: String = t.rooms.kind_of(room) if room != PeopleScript.NONE else ""
			eligible[room] = kind == "office" or CatalogueScript.is_condo(kind)
		var id := int(rows[b])
		if eligible[room] and not coupled.has(id) and _age_band_in(kids, t, id) == NamesScript.BAND_ADULT:
			if not by_room.has(room):
				by_room[room] = [] as Array[int]
			by_room[room].append(id)
		b += PeopleScript.EVAL_ROW
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


## Logs a move-in and, if the condo they left has nobody now, vacates it and refunds the sale price.
func _freed(t: Object, old: int, target: int, a: int, b: int) -> void:
	_record(t.tick, MOVE_IN, a, b, target)
	_vacate_if_empty(t, old)


## A sold condo with no residents left is vacated and its sale price refunded, as when an owner
## leaves (Evaluation), so it can be sold again and vacate-then-resell nets zero.
func _vacate_if_empty(t: Object, room: int) -> void:
	if room == PeopleScript.NONE or not CatalogueScript.is_condo(t.rooms.kind_of(room)) or not t.rooms.is_sold(room) or _residents(t.people, room) > 0:
		return
	var run: Array[int] = t.grid.run_of(room)
	var kind: String = t.rooms.kind_of(room)
	var price: int = CatalogueScript.cost(kind)
	t.rooms.set_sold(room, false)
	t.ledger.payout(t.tick, price, room)
	t.messages.add(t.tick, MessagesScript.TENANT_LEFT, CatalogueScript.IDS.find(kind), run[0] if not run.is_empty() else 0)
	t.messages.add(t.tick, MessagesScript.CONDO_REFUND, price)


func have_children(t: Object) -> void:
	var homes: Dictionary = t.people.home_counts()  # residents per room, kept up as kids are born (#452)
	for n in _couples.size() / 2:
		var a: int = _couples[2 * n]
		var ia: int = t.people.index_of(a)
		var ib: int = t.people.index_of(_couples[2 * n + 1])
		if ia == -1 or ib == -1:
			continue
		var home: int = t.people.home_of(ia)
		if home == PeopleScript.NONE or home != t.people.home_of(ib) or not (CatalogueScript.is_condo(t.rooms.kind_of(home)) and t.rooms.is_sold(home) and int(homes.get(home, 0)) < t.rooms.people_in(home)):
			continue
		if t.rng.next_below(100) < child_percent:
			var kid: int = t.people.add_person(home, PeopleScript.NONE, t.rng)
			homes[home] = int(homes.get(home, 0)) + 1
			_kids.append(kid)
			_record(t.tick, CHILD, a, kid, home)


func promote(t: Object) -> void:
	var chosen: Array[int] = []
	var kids := _set_of(_kids)
	var promoted := _set_of(_promoted)
	var rows: PackedInt64Array = t.people.eval_rows()
	var offices := {}  # room -> true for an office
	var b := 0
	while b < rows.size():
		var work := int(rows[b + 2])
		if work != PeopleScript.NONE:
			if not offices.has(work):
				offices[work] = t.rooms.kind_of(work) == "office"
			var id := int(rows[b])
			if offices[work] and _age_band_in(kids, t, id) == NamesScript.BAND_ADULT and not promoted.has(id):
				if t.rng.next_below(100) < promotion_percent:
					chosen.append(id)
		b += PeopleScript.EVAL_ROW
	for id in chosen:
		var i: int = t.people.index_of(id)
		_promoted.append(id)
		t.people.set_mood(i, t.people.mood_of(i) + PROMOTION_MOOD)
		_record(t.tick, PROMOTION, id, -1, t.people.work_of(i))


func retire(t: Object) -> void:
	var chosen: Array[int] = []
	var kids := _set_of(_kids)
	var rows: PackedInt64Array = t.people.eval_rows()
	var offices := {}
	var b := 0
	while b < rows.size():
		var work := int(rows[b + 2])
		if work != PeopleScript.NONE:
			if not offices.has(work):
				offices[work] = t.rooms.kind_of(work) == "office"
			if offices[work] and _age_band_in(kids, t, int(rows[b])) == NamesScript.BAND_SENIOR:
				if t.rng.next_below(100000) < retire_per_100000:
					chosen.append(int(rows[b]))
		b += PeopleScript.EVAL_ROW
	for id in chosen:
		var i: int = t.people.index_of(id)
		var office: int = t.people.work_of(i)
		var home: int = t.people.home_of(i)
		t.people.remove_person(i)
		_vacate_if_empty(t, home)
		t.people.add_person(PeopleScript.NONE, office, t.rng)  # the office hires to fill the seat
		var stays := -1
		if t.rng.next_below(100) < retire_stay_percent:
			var ids: Array[int] = t.rooms.room_ids()
			ids.sort()
			for room in ids:
				if _has_place(t, room):
					stays = t.people.add_person(room, PeopleScript.NONE, t.rng)
					break
			if stays < 0:  # no condo has a place: a retiree may take a room in assisted living (#378)
				for room in ids:
					if ApartmentsScript.has_place(t, room):
						stays = ApartmentsScript.add_senior(t, room)
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
		var home: int = t.people.home_of(i)
		t.people.remove_person(i)
		_vacate_if_empty(t, home)
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
