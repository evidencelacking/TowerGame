class_name Mood
extends RefCounted
## Mood (12.2): each person has a mood from 0 to 100 (People, saved) that moves once a day, at the
## rest-period evaluation, toward a target the day's conditions give. The target is BASE plus a
## list of factors, each a (reason, change) pair:
##   TRAVEL  their current travel stress (elevator and stair waits, walking), up to -TRAVEL_MAX
##   NOISE   noise at their room, -NOISE_PER_LEVEL a level up to -NOISE_MAX
##   GRADE   their room's grade: A lifts, C drags (offices, condos and hotel rooms)
##   CROWD   many people on their floor at once, -CROWD_PER_STEP for each CROWD_STEP over CROWD_FREE,
##           capped at CROWD_MAX; lobby and sky-lobby floors are never counted as crowded
##   EVENT   a fire or a threat since the last evaluation, felt only by people who were inside the
##           tower while it happened (the shock and who felt it are saved, then cleared)
## A day moves the mood at most STEP points. A mood below LOW_BELOW is a low day; LEAVE_DAYS in
## a row make the household give notice, but only if the room is already at a failing grade (C):
## mood alone never evicts a tenant the evaluation keeps (Evaluation.evaluate_moods). A room whose occupants average HIGH_FROM or more brings friends from
## further away (Evaluation). All values are unverified and tunable. Integers only.

const PeopleScript := preload("res://scripts/sim/people.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const GridScript := preload("res://scripts/sim/grid.gd")
const GradesScript := preload("res://scripts/sim/grades.gd")
const FloorsScript := preload("res://scripts/sim/floors.gd")
const NoiseScript := preload("res://scripts/sim/noise.gd")
const SynergyScript := preload("res://scripts/sim/synergy.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const EvalTablesScript := preload("res://scripts/sim/eval_tables.gd")

const REASON_TRAVEL := 0
const REASON_NOISE := 1
const REASON_GRADE := 2
const REASON_CROWD := 3
const REASON_EVENT := 4
const REASON_NEIGHBOURS := 5  ## Gyms, daycares, clinics, nightclubs nearby (synergy.gd).
const REASON_RENTER := 6  ## Renting rather than owning (#379).
const REASON_CARE := 7  ## Assisted living with no clinic or medical center within reach (#378).
const REASON_NAMES: Array[String] = ["travel waits", "noise", "room grade", "crowding", "a fire or threat", "neighbours", "renting", "no clinic nearby"]

const BASE := 100
const TRAVEL_MAX := 50  ## Travel stress at STRESS_MAX costs this much.
const NOISE_PER_LEVEL := 8
const NOISE_MAX := 24
const CARE_PENALTY := 15  ## Assisted living without care in reach (#378, tunable).
const RENTER_PENALTY := 5  ## An apartment's mood baseline sits this far under a condo's.
const GRADE_A_BONUS := 5
const GRADE_C_PENALTY := 25
const CROWD_FREE := 40  ## People located on a floor before it feels crowded.
const CROWD_STEP := 10
const CROWD_PER_STEP := 5
const CROWD_MAX := 20
const FIRE_SHOCK := 25
const THREAT_SHOCK := 15
const STEP := 8  ## Most a mood moves in one day.
const LOW_BELOW := 35
const LEAVE_DAYS := 5
const HIGH_FROM := 85  ## A room averaging this or more has happy tenants.
const FRIEND_REACH_BONUS := 6  ## Extra cells a happy room's friend may come from.

## The worst event shock since the last evaluation. Saved.
var shock: int = 0
## Ids of the people who were inside the tower while an event was on since the last evaluation. Saved.
var _shocked: Array[int] = []
## The same ids as keys, so membership is one lookup (#448). Derived: rebuilt on load, cleared with the array.
var _shocked_set: Dictionary = {}


## Records an event shock (the larger of today's shocks counts) against everyone inside the tower now.
func note_event(amount: int, people: PeopleScript) -> void:
	shock = maxi(shock, amount)
	for id in people.inside_ids():
		if not _shocked_set.has(id):
			_shocked_set[id] = true
			_shocked.append(id)


## The room whose conditions a person lives in: where they work, else where they live.
static func room_of(people: PeopleScript, i: int) -> int:
	return people.work_of(i) if people.work_of(i) != PeopleScript.NONE else people.home_of(i)


## People currently located on each floor: floor -> count. Lobby and sky-lobby floors are left out
## (they are busy by design, so they never count as crowded).
static func floor_counts(people: PeopleScript, grid: GridScript, floors: FloorsScript) -> Dictionary:
	var by_room := {}  # location room -> how many people are in it
	var rows := people.eval_rows()
	var b := 6
	var n := rows.size()
	while b < n:
		var here := int(rows[b])
		if here != PeopleScript.NONE:
			by_room[here] = int(by_room.get(here, 0)) + 1
		b += PeopleScript.EVAL_ROW
	var counts := {}
	for here: int in by_room:  # one run lookup per room, not per person (#452)
		var run := grid.run_of(here)
		if not run.is_empty() and not floors.is_lobby_floor(run[0]):
			counts[run[0]] = counts.get(run[0], 0) + by_room[here]
	return counts


## The factors of person i that depend only on their room, as [reason, change] pairs in a fixed order:
## noise, grade, neighbours, crowding. tables (EvalTables) supplies the rooms that are synergy sources and
## memoises the answer per room; pass it only while counts and the tower stay as they are.
func _room_terms(rooms: RoomsScript, grid: GridScript, grades: GradesScript, people: PeopleScript, counts: Dictionary, room: int, tables: EvalTablesScript) -> Array[Array]:
	if tables != null and tables.terms.has(room):
		return tables.terms[room]
	var found: Array[Array] = []
	if room != PeopleScript.NONE and rooms.kind_of(room) != "":
		var noise := mini(NoiseScript.noise_at(grid, rooms, room) * NOISE_PER_LEVEL, NOISE_MAX)
		if noise > 0:
			found.append([REASON_NOISE, -noise])
		var grade := grades.grade(rooms, people, room)
		if grade == GradesScript.GRADE_A:
			found.append([REASON_GRADE, GRADE_A_BONUS])
		elif grade == GradesScript.GRADE_C:
			found.append([REASON_GRADE, -GRADE_C_PENALTY])
		var run := grid.run_of(room)
		if rooms.kind_of(room) == "apartment":
			found.append([REASON_RENTER, -RENTER_PENALTY])
		if not run.is_empty():
			var others: Array = tables.others if tables != null else SynergyScript.others_of(grid, rooms)
			var nearby := SynergyScript.mood_delta("condo" if CatalogueScript.is_rental(rooms.kind_of(room)) else rooms.kind_of(room), run, others)  # neighbours treat a rented home as a condo
			if rooms.kind_of(room) == "assisted" and not SynergyScript.has_care(run, others):
				found.append([REASON_CARE, -CARE_PENALTY])
			if nearby != 0:
				found.append([REASON_NEIGHBOURS, nearby])
			var over: int = counts.get(run[0], 0) - CROWD_FREE
			if over > 0:
				found.append([REASON_CROWD, -mini(over / CROWD_STEP * CROWD_PER_STEP, CROWD_MAX)])
	if tables != null:
		tables.terms[room] = found
	return found


func _shocked_has(id: int, tables: EvalTablesScript) -> bool:
	return tables.shocked.has(id) if tables != null else _shocked_set.has(id)


## The factors on person i as [reason, change] pairs (changes are not zero), worst first.
## counts is floor_counts (pass it in so a whole tower shares one pass). tables is optional (see _room_terms).
func factors(rooms: RoomsScript, grid: GridScript, grades: GradesScript, people: PeopleScript, counts: Dictionary, i: int, tables: EvalTablesScript = null) -> Array[Array]:
	var found: Array[Array] = []
	var travel := mini(people.stress_of(i) * TRAVEL_MAX / PeopleScript.STRESS_MAX, TRAVEL_MAX)
	if travel > 0:
		found.append([REASON_TRAVEL, -travel])
	found.append_array(_room_terms(rooms, grid, grades, people, counts, room_of(people, i), tables))
	if shock > 0 and _shocked_has(people.id_at(i), tables):
		found.append([REASON_EVENT, -shock])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1] or (a[1] == b[1] and a[0] < b[0]))
	return found


## The mood the day's conditions pull person i toward, 0 to MOOD_MAX.
func target(rooms: RoomsScript, grid: GridScript, grades: GradesScript, people: PeopleScript, counts: Dictionary, i: int, tables: EvalTablesScript = null) -> int:
	var total := BASE
	if tables == null:
		for factor in factors(rooms, grid, grades, people, counts, i):
			total += factor[1]
		return clampi(total, 0, PeopleScript.MOOD_MAX)
	# The same sum without the sort, which cannot change it.
	total -= mini(people.stress_of(i) * TRAVEL_MAX / PeopleScript.STRESS_MAX, TRAVEL_MAX)
	for factor in _room_terms(rooms, grid, grades, people, counts, room_of(people, i), tables):
		total += factor[1]
	if shock > 0 and _shocked_has(people.id_at(i), tables):
		total -= shock
	return clampi(total, 0, PeopleScript.MOOD_MAX)


## Moves everyone's mood one day toward its target, counts low days, then clears the event shock.
func update(rooms: RoomsScript, grid: GridScript, floors: FloorsScript, grades: GradesScript, people: PeopleScript) -> void:
	var counts := floor_counts(people, grid, floors)
	var tables := EvalTablesScript.build(rooms, grid, people, grades, LEAVE_DAYS)
	for id in _shocked:
		tables.shocked[id] = true
	grades.batch = tables
	var recovery := SynergyScript.recovery_bonus(tables.others)  # clinics: moods rise faster
	# The same sum target() gives, from one packed pass over the people (#452): the room's terms add up once per room.
	var rows := people.eval_rows()
	var stride := PeopleScript.EVAL_ROW
	var room_sums: Dictionary = {}
	var event := shock > 0
	var b := 0
	var i := 0
	var n := rows.size()
	while b < n:
		var work := rows[b + 2]
		var room: int = work if work != PeopleScript.NONE else rows[b + 1]
		if not room_sums.has(room):
			var sum := 0
			for factor in _room_terms(rooms, grid, grades, people, counts, room, tables):
				sum += factor[1]
			room_sums[room] = sum
		var total: int = BASE - mini(int(rows[b + 3]) * TRAVEL_MAX / PeopleScript.STRESS_MAX, TRAVEL_MAX) + int(room_sums[room])
		if event and tables.shocked.has(rows[b]):
			total -= shock
		var mood := int(rows[b + 4])
		mood += clampi(clampi(total, 0, PeopleScript.MOOD_MAX) - mood, -STEP, STEP + recovery)
		people.set_mood(i, mood)
		people.set_low_days(i, int(rows[b + 5]) + 1 if clampi(mood, 0, PeopleScript.MOOD_MAX) < LOW_BELOW else 0)
		b += stride
		i += 1
	grades.batch = null
	shock = 0
	_shocked.clear()
	_shocked_set.clear()


## Average mood of the people who work or live in a room, or -1 if there are none. tables (EvalTables,
## built after the last mood change) answers without scanning everyone.
static func room_average(people: PeopleScript, room: int, tables: EvalTablesScript = null) -> int:
	if tables != null:
		return tables.room_average(room)
	var total := 0
	var n := 0
	for i in people.count():
		if people.work_of(i) == room or people.home_of(i) == room:
			total += people.mood_of(i)
			n += 1
	return total / n if n > 0 else -1


## True when someone who works or lives in the room has had LEAVE_DAYS low days in a row. tables as in room_average.
static func gave_notice(people: PeopleScript, room: int, tables: EvalTablesScript = null) -> bool:
	if tables != null:
		return tables.notice.has(room)
	for i in people.count():
		if (people.work_of(i) == room or people.home_of(i) == room) and people.low_days_of(i) >= LEAVE_DAYS:
			return true
	return false


func state_ints() -> Array[int]:
	var ints: Array[int] = [shock, _shocked.size()]
	ints.append_array(_shocked)
	return ints


static func valid_ints(ints: Array) -> bool:
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	return ints.size() >= 2 and ints[0] >= 0 and ints[1] >= 0 and ints.size() == 2 + ints[1]


func load_ints(ints: Array) -> void:
	shock = ints[0]
	_shocked.clear()
	_shocked_set.clear()
	for k in range(2, ints.size()):
		_shocked.append(ints[k])
		_shocked_set[ints[k]] = true
