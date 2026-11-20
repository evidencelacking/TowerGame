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

const REASON_TRAVEL := 0
const REASON_NOISE := 1
const REASON_GRADE := 2
const REASON_CROWD := 3
const REASON_EVENT := 4
const REASON_NEIGHBOURS := 5  ## Gyms, daycares, clinics, nightclubs nearby (synergy.gd).
const REASON_NAMES: Array[String] = ["travel waits", "noise", "room grade", "crowding", "a fire or threat", "neighbours"]

const BASE := 100
const TRAVEL_MAX := 50  ## Travel stress at STRESS_MAX costs this much.
const NOISE_PER_LEVEL := 8
const NOISE_MAX := 24
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


## Records an event shock (the larger of today's shocks counts) against everyone inside the tower now.
func note_event(amount: int, people: PeopleScript) -> void:
	shock = maxi(shock, amount)
	for i in people.count():
		if people.location_of(i) == PeopleScript.NONE and people.trip_state(i) == PeopleScript.TRIP_IDLE:
			continue
		var id := people.id_at(i)
		if not _shocked.has(id):
			_shocked.append(id)


## The room whose conditions a person lives in: where they work, else where they live.
static func room_of(people: PeopleScript, i: int) -> int:
	return people.work_of(i) if people.work_of(i) != PeopleScript.NONE else people.home_of(i)


## People currently located on each floor: floor -> count. Lobby and sky-lobby floors are left out
## (they are busy by design, so they never count as crowded).
static func floor_counts(people: PeopleScript, grid: GridScript, floors: FloorsScript) -> Dictionary:
	var counts := {}
	for i in people.count():
		var here := people.location_of(i)
		if here == PeopleScript.NONE:
			continue
		var run := grid.run_of(here)
		if not run.is_empty() and not floors.is_lobby_floor(run[0]):
			counts[run[0]] = counts.get(run[0], 0) + 1
	return counts


## The factors on person i as [reason, change] pairs (changes are not zero), worst first.
## counts is floor_counts (pass it in so a whole tower shares one pass).
func factors(rooms: RoomsScript, grid: GridScript, grades: GradesScript, people: PeopleScript, counts: Dictionary, i: int) -> Array[Array]:
	var found: Array[Array] = []
	var travel := mini(people.stress_of(i) * TRAVEL_MAX / PeopleScript.STRESS_MAX, TRAVEL_MAX)
	if travel > 0:
		found.append([REASON_TRAVEL, -travel])
	var room := room_of(people, i)
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
		if not run.is_empty():
			var nearby := SynergyScript.mood_delta(rooms.kind_of(room), run, SynergyScript.others_of(grid, rooms))
			if nearby != 0:
				found.append([REASON_NEIGHBOURS, nearby])
			var over: int = counts.get(run[0], 0) - CROWD_FREE
			if over > 0:
				found.append([REASON_CROWD, -mini(over / CROWD_STEP * CROWD_PER_STEP, CROWD_MAX)])
	if shock > 0 and _shocked.has(people.id_at(i)):
		found.append([REASON_EVENT, -shock])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1] or (a[1] == b[1] and a[0] < b[0]))
	return found


## The mood the day's conditions pull person i toward, 0 to MOOD_MAX.
func target(rooms: RoomsScript, grid: GridScript, grades: GradesScript, people: PeopleScript, counts: Dictionary, i: int) -> int:
	var total := BASE
	for factor in factors(rooms, grid, grades, people, counts, i):
		total += factor[1]
	return clampi(total, 0, PeopleScript.MOOD_MAX)


## Moves everyone's mood one day toward its target, counts low days, then clears the event shock.
func update(rooms: RoomsScript, grid: GridScript, floors: FloorsScript, grades: GradesScript, people: PeopleScript) -> void:
	var counts := floor_counts(people, grid, floors)
	var recovery := SynergyScript.recovery_bonus(SynergyScript.others_of(grid, rooms))  # clinics: moods rise faster
	for i in people.count():
		var mood := people.mood_of(i)
		mood += clampi(target(rooms, grid, grades, people, counts, i) - mood, -STEP, STEP + recovery)
		people.set_mood(i, mood)
		people.set_low_days(i, people.low_days_of(i) + 1 if people.mood_of(i) < LOW_BELOW else 0)
	shock = 0
	_shocked.clear()


## Average mood of the people who work or live in a room, or -1 if there are none.
static func room_average(people: PeopleScript, room: int) -> int:
	var total := 0
	var n := 0
	for i in people.count():
		if people.work_of(i) == room or people.home_of(i) == room:
			total += people.mood_of(i)
			n += 1
	return total / n if n > 0 else -1


## True when someone who works or lives in the room has had LEAVE_DAYS low days in a row.
static func gave_notice(people: PeopleScript, room: int) -> bool:
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
	for k in range(2, ints.size()):
		_shocked.append(ints[k])
