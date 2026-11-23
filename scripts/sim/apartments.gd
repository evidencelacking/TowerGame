class_name Apartments
extends RefCounted
## Rental apartments (#379): a home that is rented, not sold. Once a day (Tower.evaluate_tenants) each
## apartment the lobby reaches may take one new resident, up to its catalogue "people" (2), with a
## FILL_PERCENT chance, so a new block fills over a few days instead of in one sale. Each resident
## may also move out, with LEAVE_PERCENT a day, or LEAVE_PERCENT_C when the room's grade is C. At the
## lowest rent level nobody leaves (Rent.never_leaves). A vacancy refills over the following days.
## Rent comes in on the daily/quarterly cycle in Rent.collect; the renter mood factor is in Mood.
## Residents are ordinary people (home = the room), so population, mood and Life.leave_town cover them.
## Couples and children are condo-only (Life); apartments are flatmates. All numbers are unverified tunables.
## Integers only; the seeded Tower RNG; nothing here is saved (it reads People and Rooms).

const PeopleScript := preload("res://scripts/sim/people.gd")
const GradesScript := preload("res://scripts/sim/grades.gd")
const MessagesScript := preload("res://scripts/sim/messages.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")

const NamesScript := preload("res://scripts/sim/names.gd")
const EvalTablesScript := preload("res://scripts/sim/eval_tables.gd")

const KIND := "apartment"
const ASSISTED := "assisted"  ## Assisted living (#378): same cycle, seniors only, steadier (see _fill_percent, _leave_percent).
const SKIP_LIMIT := 64  ## Most ids passed over to find a senior one.
const FILL_PERCENT := 50  ## Daily chance a reachable apartment with a vacancy takes one resident.
const LEAVE_PERCENT := 2  ## Daily chance each resident leaves.
const LEAVE_PERCENT_C := 10  ## ...in an apartment graded C.
const ASSISTED_FILL_PERCENT := 40  ## Assisted living (#378): fills a little slower...
const ASSISTED_LEAVE_PERCENT := 1  ## ...and loses fewer residents: a low-turnover home.
const ASSISTED_LEAVE_PERCENT_C := 4


## One day's arrivals and departures, for every apartment in id order. t is the Tower.
func daily(t: Object) -> void:
	var ids: Array[int] = t.rooms.room_ids()
	ids.sort()
	var entry_x := 0
	var linked: bool = t.floors.has_lobby()
	if linked:
		entry_x = t.floors.lobby_span()[0]
	# One pass over the people instead of one per apartment (#452): each apartment's residents as person ids in
	# index order, which is the order the draws below must follow. Leavers are the only change to anyone's
	# home before an apartment is reached, and they leave their own apartment's list. The stress tables
	# keep grades equal to a fresh scan as people go.
	var residents: Dictionary = {}
	for i in t.people.count():
		var home: int = t.people.home_of(i)
		if home != PeopleScript.NONE:
			if not residents.has(home):
				residents[home] = [] as Array[int]
			residents[home].append(t.people.id_at(i))
	var tables := EvalTablesScript.build_stress(t.people, t.grades)
	t.grades.batch = tables
	for id in ids:
		var kind: String = t.rooms.kind_of(id)
		if kind != KIND and kind != ASSISTED:
			continue
		var living: Array[int] = residents.get(id, [] as Array[int])
		_leave_among(t, id, living, tables)
		if linked and t.tenancy.routed(t.floors, t.rooms, t.grid, id, entry_x):
			_fill(t, id, living.size())
	t.grades.batch = null


func _fill(t: Object, id: int, residents: int) -> void:
	if residents >= t.rooms.people_in(id):
		return
	var assisted: bool = t.rooms.kind_of(id) == ASSISTED
	if t.rng.next_below(100) < (ASSISTED_FILL_PERCENT if assisted else FILL_PERCENT):
		if assisted:
			add_senior(t, id)
		else:
			t.people.add_person(id, PeopleScript.NONE, t.rng)


## Moves a senior resident into a room: passes over ids whose age band is not senior (a bounded, fixed scan),
## then adds the person. Used by the daily fill and by Life when a retiree stays on (#378). Returns the id.
static func add_senior(t: Object, room: int) -> int:
	var passed := 0
	while passed < SKIP_LIMIT and NamesScript.age_band(t.names.name_seed, t.people.next_id()) != NamesScript.BAND_SENIOR:
		t.people.skip_id()
		passed += 1
	return t.people.add_person(room, PeopleScript.NONE, t.rng)


## True if an assisted-living room has space for another resident.
static func has_place(t: Object, room: int) -> bool:
	return t.rooms.kind_of(room) == ASSISTED and t.people.homes_in(room) < t.rooms.people_in(room)


## One apartment's departures on its own: finds the residents and the stress tables itself. For tests; daily shares them.
func _leave(t: Object, id: int) -> void:
	var living: Array[int] = []
	for i in t.people.count():
		if t.people.home_of(i) == id:
			living.append(t.people.id_at(i))
	var tables := EvalTablesScript.build_stress(t.people, t.grades)
	var was = t.grades.batch
	t.grades.batch = tables
	_leave_among(t, id, living, tables)
	t.grades.batch = was


func _leave_among(t: Object, id: int, living: Array[int], tables: RefCounted) -> void:
	if t.rent.never_leaves(t.rooms, id):
		return
	var c_grade: bool = t.grades.grade(t.rooms, t.people, id) == GradesScript.GRADE_C
	var percent := LEAVE_PERCENT_C if c_grade else LEAVE_PERCENT
	if t.rooms.kind_of(id) == ASSISTED:
		percent = ASSISTED_LEAVE_PERCENT_C if c_grade else ASSISTED_LEAVE_PERCENT
	var leavers: Array[int] = []
	for who in living:
		if t.rng.next_below(100) < percent:
			leavers.append(who)
	for who in leavers:
		var at: int = t.people.index_of(who)
		tables.forget_leaver(t.people, t.grades, at)
		t.people.remove_person(at)
		living.erase(who)
	if not leavers.is_empty():
		var run: Array[int] = t.grid.run_of(id)
		t.messages.add(t.tick, MessagesScript.TENANT_LEFT, CatalogueScript.IDS.find(t.rooms.kind_of(id)), run[0] if not run.is_empty() else 0)
