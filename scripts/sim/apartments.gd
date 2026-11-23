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

const KIND := "apartment"
const FILL_PERCENT := 50  ## Daily chance a reachable apartment with a vacancy takes one resident.
const LEAVE_PERCENT := 2  ## Daily chance each resident leaves.
const LEAVE_PERCENT_C := 10  ## ...in an apartment graded C.


## One day's arrivals and departures, for every apartment in id order. t is the Tower.
func daily(t: Object) -> void:
	var ids: Array[int] = t.rooms.room_ids()
	ids.sort()
	var entry_x := 0
	var linked: bool = t.floors.has_lobby()
	if linked:
		entry_x = t.floors.lobby_span()[0]
	for id in ids:
		if t.rooms.kind_of(id) != KIND:
			continue
		_leave(t, id)
		if linked and t.tenancy.routed(t.floors, t.rooms, t.grid, id, entry_x):
			_fill(t, id)


func _fill(t: Object, id: int) -> void:
	if t.people.homes_in(id) >= t.rooms.people_in(id):
		return
	if t.rng.next_below(100) < FILL_PERCENT:
		t.people.add_person(id, PeopleScript.NONE, t.rng)


func _leave(t: Object, id: int) -> void:
	if t.rent.never_leaves(t.rooms, id):
		return
	var percent := LEAVE_PERCENT_C if t.grades.grade(t.rooms, t.people, id) == GradesScript.GRADE_C else LEAVE_PERCENT
	var leavers: Array[int] = []
	for i in t.people.count():
		if t.people.home_of(i) == id and t.rng.next_below(100) < percent:
			leavers.append(t.people.id_at(i))
	for who in leavers:
		t.people.remove_person(t.people.index_of(who))
	if not leavers.is_empty():
		var run: Array[int] = t.grid.run_of(id)
		t.messages.add(t.tick, MessagesScript.TENANT_LEFT, CatalogueScript.IDS.find(KIND), run[0] if not run.is_empty() else 0)
