class_name Evaluation
extends RefCounted
## Rest-period evaluation (5.2): once a day every occupied office and sold condo is graded
## (Grades). Manual p63: an A tenant brings a friend, B stays, C leaves. Offices leave only after
## a day in the red (p52); condos that leave refund the sale price, even into negative funds
## (p53, p65). Hotels are not tenanted yet (M7) and are skipped.
##
## Order at an evaluation: grades are read for every room first, so nothing changed here moves
## another room's grade; then friends arrive (against the vacancies that existed before), then
## C tenants leave. A friend is one vacant unit of the same kind on the same floor within
## FRIEND_REACH cells, that the lobby can reach, per A unit per evaluation. Rates are unverified.
##
## Saved state: the consecutive red evaluations of each office that has any.

const Clock := preload("res://scripts/sim/clock.gd")
const GridScript := preload("res://scripts/sim/grid.gd")
const FloorsScript := preload("res://scripts/sim/floors.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")
const LedgerScript := preload("res://scripts/sim/ledger.gd")
const GradesScript := preload("res://scripts/sim/grades.gd")
const MessagesScript := preload("res://scripts/sim/messages.gd")
const TenancyScript := preload("res://scripts/sim/tenancy.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const MoodScript := preload("res://scripts/sim/mood.gd")
const EvalTablesScript := preload("res://scripts/sim/eval_tables.gd")

## Minute of the day whose period start runs the evaluation, once per day: 21:00, the start of
## the night period, taken as the manual's "rest period" (owner ruling 2026-11-14: the rest
## period, not quarter start). Unverified, tunable.
const EVALUATE_MINUTE := 1260
## An office leaves at the evaluation where this many consecutive evaluations were C. The first
## C evaluation is "a day in the red" and is survived; a non-C evaluation resets the count.
const OFFICE_RED_DAYS := 2
## Chance in percent that a C condo leaves, and that an A unit brings a friend. The manual
## says C tenants leave, so 100; the RNG is only drawn when below 100. Unverified, tunable.
const CONDO_LEAVE_PERCENT := 100
const FRIEND_PERCENT := 100
## Widest gap in cells between an A unit and the vacant unit its friend takes. Tunable.
const FRIEND_REACH := 12
## Steps of the daily evaluation, one per tick from the period start (see Tower.evaluate_step): 0 warm the layout
## caches, 1 mood update, 2 grade and friends, 3 mood notices, 4 life, 5 apartments and commerce.
const STEPS := 6

var _red_days: Dictionary = {}  ## Office room id -> consecutive C evaluations (only when above 0).


## True on the single tick of each day that begins the period starting at EVALUATE_MINUTE.
static func is_due(clock: Clock) -> bool:
	return is_due_step(clock, 0)


## True when the clock is STEP k of the evening evaluation: k ticks into the period that is_due names. The evaluation's
## steps run on consecutive ticks so no one tick pays for all of them (#452). Derived from the clock alone, so it is
## never saved.
static func is_due_step(clock: Clock, k: int) -> bool:
	return clock.ticks_in_period() == k and Clock.period_start(clock.period() - 1) == EVALUATE_MINUTE


## The step (0 to STEPS - 1) that runs on this tick, or -1.
static func step_due(clock: Clock) -> int:
	if Clock.period_start(clock.period() - 1) != EVALUATE_MINUTE or clock.ticks_in_period() >= STEPS:
		return -1
	return clock.ticks_in_period()


## Consecutive C evaluations an office has had.
func red_days(room: int) -> int:
	return _red_days.get(room, 0)


func _occupied(rooms: RoomsScript, tables: EvalTablesScript, id: int) -> bool:
	var kind := rooms.kind_of(id)
	if kind == "office":
		return tables.workers.get(id, 0) > 0
	return CatalogueScript.is_condo(kind) and rooms.is_sold(id)


func _vacant_in(rooms: RoomsScript, tables: EvalTablesScript, id: int) -> bool:
	var kind := rooms.kind_of(id)
	if kind == "office":
		return tables.workers.get(id, 0) == 0
	return CatalogueScript.is_condo(kind) and not rooms.is_sold(id)


func _vacant(rooms: RoomsScript, people: PeopleScript, id: int) -> bool:
	var kind := rooms.kind_of(id)
	if kind == "office":
		return people.workers_in(id) == 0
	return CatalogueScript.is_condo(kind) and not rooms.is_sold(id)


## Vacant offices and condos grouped by kind and floor, each list in ascending id order, for _vacancy_near.
func _vacancies(rooms: RoomsScript, grid: GridScript, tables: EvalTablesScript, ids: Array[int]) -> Dictionary:
	var found: Dictionary = {}
	for id in ids:
		if not _vacant_in(rooms, tables, id):
			continue
		var run := grid.run_of(id)
		if run.is_empty():
			continue
		var key := "%s/%d" % [rooms.kind_of(id), run[0]]
		if not found.has(key):
			found[key] = [] as Array[int]
		found[key].append(id)
	return found


## Runs one evaluation of the whole tower.
func evaluate(rooms: RoomsScript, people: PeopleScript, grades: GradesScript, grid: GridScript, floors: FloorsScript, tenancy: TenancyScript, ledger: LedgerScript, messages: MessagesScript, rng: Object, at_tick: int) -> void:
	var ids := rooms.room_ids()
	ids.sort()
	var tables := EvalTablesScript.build(rooms, grid, people, grades, MoodScript.LEAVE_DAYS)
	grades.batch = tables
	var graded: Dictionary = {}  # occupied room id -> grade
	for id in ids:
		if _occupied(rooms, tables, id):
			graded[id] = grades.grade(rooms, people, id)
	for id in _red_days.keys():
		if not graded.has(id):
			_red_days.erase(id)
	# Friends first, against the vacancies that exist before anyone leaves.
	var entry_x := floors.lobby_span()[0] if floors.has_lobby() else 0
	var vacancies := _vacancies(rooms, grid, tables, ids)
	for id in ids:
		if graded.get(id, -1) == GradesScript.GRADE_A and (FRIEND_PERCENT >= 100 or rng.next_below(100) < FRIEND_PERCENT):
			var reach := FRIEND_REACH + (MoodScript.FRIEND_REACH_BONUS if MoodScript.room_average(people, id, tables) >= MoodScript.HIGH_FROM else 0)
			var friend := _vacancy_near(rooms, grid, floors, tenancy, vacancies, id, entry_x, reach)
			if friend != 0:
				_fill(rooms, people, grid, ledger, messages, rng, at_tick, friend)
				if rooms.kind_of(friend) == "office":
					tables.workers[friend] = int(tables.workers.get(friend, 0)) + rooms.people_in(friend)
				if not _vacant_in(rooms, tables, friend):
					vacancies["%s/%d" % [rooms.kind_of(friend), grid.run_of(friend)[0]]].erase(friend)
	grades.batch = null
	# Then C tenants leave.
	for id in ids:
		var grade: int = graded.get(id, -1)
		var kind := rooms.kind_of(id)
		if kind == "office":
			if grade == GradesScript.GRADE_C:
				_red_days[id] = red_days(id) + 1
				if _red_days[id] >= OFFICE_RED_DAYS:
					_red_days.erase(id)
					people.remove_room(id)
					_left(rooms, grid, messages, at_tick, id)
			else:
				_red_days.erase(id)
		elif CatalogueScript.is_condo(kind) and grade == GradesScript.GRADE_C and (CONDO_LEAVE_PERCENT >= 100 or rng.next_below(100) < CONDO_LEAVE_PERCENT):
			var price := CatalogueScript.cost(kind)
			rooms.set_sold(id, false)
			people.remove_room(id)
			ledger.payout(at_tick, price, id)
			_left(rooms, grid, messages, at_tick, id)
			messages.add(at_tick, MessagesScript.CONDO_REFUND, price)


## Mood (12.2): after the grade rule, a household whose mood has been low for LEAVE_DAYS days in a
## row AND whose room is already at a failing grade (C) gives notice, and leaves just as a C tenant
## does (condos refund the sale price). Mood alone never evicts a B-grade tenant.
func evaluate_moods(rooms: RoomsScript, people: PeopleScript, grades: GradesScript, grid: GridScript, ledger: LedgerScript, messages: MessagesScript, at_tick: int) -> void:
	var ids := rooms.room_ids()
	ids.sort()
	var tables := EvalTablesScript.build(rooms, grid, people, grades, MoodScript.LEAVE_DAYS)
	grades.batch = tables
	for id in ids:
		var kind := rooms.kind_of(id)
		if not _occupied(rooms, tables, id) or not MoodScript.gave_notice(people, id, tables) or grades.grade(rooms, people, id) != GradesScript.GRADE_C:
			continue
		tables.forget_room(people, grades, id)  # leave the tables reading as a fresh build would, without building again (#452)
		if CatalogueScript.is_condo(kind):
			var price := CatalogueScript.cost(kind)
			rooms.set_sold(id, false)
			people.remove_room(id)
			ledger.payout(at_tick, price, id)
			_left(rooms, grid, messages, at_tick, id)
			messages.add(at_tick, MessagesScript.CONDO_REFUND, price)
		else:
			_red_days.erase(id)
			people.remove_room(id)
			_left(rooms, grid, messages, at_tick, id)
	grades.batch = null


## The nearest vacant unit of the same kind and floor within FRIEND_REACH cells that the lobby
## reaches (ties: lowest id), or 0. vacancies is _vacancies, kept up to date as units fill.
func _vacancy_near(rooms: RoomsScript, grid: GridScript, floors: FloorsScript, tenancy: TenancyScript, vacancies: Dictionary, id: int, entry_x: int, reach: int = FRIEND_REACH) -> int:
	var run := grid.run_of(id)
	var kind := rooms.kind_of(id)
	var best := 0
	var best_gap := reach + 1
	for other: int in vacancies.get("%s/%d" % [kind, run[0]], [] as Array[int]):
		if other == id:
			continue
		var there := grid.run_of(other)
		var gap := maxi(there[1] - (run[1] + run[2]), run[1] - (there[1] + there[2]))
		gap = maxi(gap, 0)
		if gap < best_gap and tenancy.routed(floors, rooms, grid, other, entry_x):
			best = other
			best_gap = gap
	return best


## Moves tenants into a vacant office or condo (a sold condo credits its price).
func _fill(rooms: RoomsScript, people: PeopleScript, grid: GridScript, ledger: LedgerScript, messages: MessagesScript, rng: Object, at_tick: int, id: int) -> void:
	var kind := rooms.kind_of(id)
	if CatalogueScript.is_condo(kind):
		rooms.set_sold(id, true)
		ledger.income(at_tick, CatalogueScript.cost(kind), id)
	for n in rooms.people_in(id):
		if CatalogueScript.is_condo(kind):
			people.add_person(id, PeopleScript.NONE, rng)
		else:
			people.add_person(PeopleScript.NONE, id, rng)
	messages.add(at_tick, MessagesScript.FRIEND_ARRIVED, CatalogueScript.IDS.find(kind), grid.run_of(id)[0])


func _left(rooms: RoomsScript, grid: GridScript, messages: MessagesScript, at_tick: int, id: int) -> void:
	var run := grid.run_of(id)
	messages.add(at_tick, MessagesScript.TENANT_LEFT, CatalogueScript.IDS.find(rooms.kind_of(id)), run[0] if not run.is_empty() else 0)


func state_ints() -> Array[int]:
	var keys: Array[int] = []
	keys.assign(_red_days.keys())
	keys.sort()
	var ints: Array[int] = [keys.size()]
	for id in keys:
		ints.append_array([id, _red_days[id]] as Array[int])
	return ints


static func valid_ints(ints: Array) -> bool:
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	return ints.size() >= 1 and ints[0] >= 0 and ints.size() == 1 + 2 * ints[0]


func load_ints(ints: Array) -> void:
	_red_days = {}
	for i in ints[0]:
		_red_days[ints[1 + 2 * i]] = ints[2 + 2 * i]
