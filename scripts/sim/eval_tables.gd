extends RefCounted
## Tables for one daily evaluation (#416): what the mood update and the evaluation would each rescan
## the whole tower to find, built from one pass over the people and one pass over the rooms. They
## answer exactly what the scans answered, so the sim's results do not change. Derived: never saved
## or hashed, and good only until the people, moods, stress or rooms change, so each caller builds its own.
## Integers only; see CLAUDE.md.

const PeopleScript := preload("res://scripts/sim/people.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const GridScript := preload("res://scripts/sim/grid.gd")
const SynergyScript := preload("res://scripts/sim/synergy.gd")

## Synergy.others_of for the tower: the rooms that are a source of some rule.
var others: Array = []
## Room id -> total stress and head count of the occupants who have made a trip, by work room and by home room.
var work_stress: Dictionary = {}
var work_n: Dictionary = {}
var home_stress: Dictionary = {}
var home_n: Dictionary = {}
## Room id -> total mood and head count of everyone who works or lives there (a person counts once per room).
var mood_total: Dictionary = {}
var mood_n: Dictionary = {}
## Room id -> true when someone who works or lives there has had `leave_days` low days in a row.
var notice: Dictionary = {}
## Room id -> how many people work there.
var workers: Dictionary = {}
## Memo for the mood update, valid for one floor_counts: room id -> its [reason, change] terms.
var terms: Dictionary = {}
## Memo of a room's grade for the callers that read it again and again.
var grades: Dictionary = {}
## Room id -> its grade without word of mouth (a word-of-mouth source's own grade), memoised for this batch (#452).
var source_grades: Dictionary = {}
## Floor -> the rooms on it whose source grade is C, valid when source_c_ready (word of mouth, #452).
var source_c: Dictionary = {}
var source_c_ready: bool = false
## Ids of the people shocked by an event since the last evaluation (empty when there was none).
var shocked: Dictionary = {}


## grades must offer tripped(id: int) -> bool; leave_days is Mood.LEAVE_DAYS.
static func build(rooms: RoomsScript, grid: GridScript, people: PeopleScript, grades_of: RefCounted, leave_days: int) -> RefCounted:
	var t := new()
	t.others = SynergyScript.others_of(grid, rooms)
	var rows := people.eval_rows()
	var stride := PeopleScript.EVAL_ROW
	var n := rows.size()
	# Sums per room go into packed arrays indexed by room id (a dictionary update per person is the slow part), then
	# into the dictionaries the callers read, which are only ever looked up (#452).
	var size := 1
	var b := 0
	while b < n:
		size = maxi(size, maxi(int(rows[b + 1]), int(rows[b + 2])) + 1)
		b += stride
	var workers_n := PackedInt64Array()
	var mood_sum := PackedInt64Array()
	var mood_count := PackedInt64Array()
	var low_flag := PackedInt64Array()
	var w_stress := PackedInt64Array()
	var w_n := PackedInt64Array()
	var h_stress := PackedInt64Array()
	var h_n := PackedInt64Array()
	workers_n.resize(size)
	mood_sum.resize(size)
	mood_count.resize(size)
	low_flag.resize(size)
	w_stress.resize(size)
	w_n.resize(size)
	h_stress.resize(size)
	h_n.resize(size)
	b = 0
	while b < n:
		var work := int(rows[b + 2])
		var home := int(rows[b + 1])
		var mood := int(rows[b + 4])
		var low := 1 if int(rows[b + 5]) >= leave_days else 0
		if work != PeopleScript.NONE:
			workers_n[work] += 1
			mood_sum[work] += mood
			mood_count[work] += 1
			low_flag[work] |= low
		if home != PeopleScript.NONE and home != work:
			mood_sum[home] += mood
			mood_count[home] += 1
			low_flag[home] |= low
		if grades_of.tripped(int(rows[b])):
			var stress := int(rows[b + 3])
			if work != PeopleScript.NONE:
				w_stress[work] += stress
				w_n[work] += 1
			if home != PeopleScript.NONE:
				h_stress[home] += stress
				h_n[home] += 1
		b += stride
	for room in size:
		if workers_n[room] > 0:
			t.workers[room] = workers_n[room]
		if mood_count[room] > 0:
			t.mood_total[room] = mood_sum[room]
			t.mood_n[room] = mood_count[room]
		if low_flag[room] > 0:
			t.notice[room] = true
		if w_n[room] > 0:
			t.work_stress[room] = w_stress[room]
			t.work_n[room] = w_n[room]
		if h_n[room] > 0:
			t.home_stress[room] = h_stress[room]
			t.home_n[room] = h_n[room]
	return t


## Only the stress tables, for a caller that reads grades while it removes people (#452): pair it with forget_leaver.
static func build_stress(people: PeopleScript, grades_of: RefCounted) -> RefCounted:
	var t := new()
	for i in people.count():
		if grades_of.tripped(people.id_at(i)):
			_note_stress(t, people, i)
	return t


static func _note_stress(t: RefCounted, people: PeopleScript, i: int) -> void:
	var work := people.work_of(i)
	var home := people.home_of(i)
	var stress := people.stress_of(i)
	if work != PeopleScript.NONE:
		t.work_stress[work] = int(t.work_stress.get(work, 0)) + stress
		t.work_n[work] = int(t.work_n.get(work, 0)) + 1
	if home != PeopleScript.NONE:
		t.home_stress[home] = int(t.home_stress.get(home, 0)) + stress
		t.home_n[home] = int(t.home_n.get(home, 0)) + 1


## Takes person i out of the stress tables, as before remove_person: the tables then answer what a fresh scan would.
## Clears the memoised source grades, which may have read the leaver's stress.
func forget_leaver(people: PeopleScript, grades_of: RefCounted, i: int) -> void:
	if not grades_of.tripped(people.id_at(i)):
		return
	var work := people.work_of(i)
	var home := people.home_of(i)
	var stress := people.stress_of(i)
	if work != PeopleScript.NONE:
		work_stress[work] = int(work_stress.get(work, 0)) - stress
		work_n[work] = int(work_n.get(work, 0)) - 1
	if home != PeopleScript.NONE:
		home_stress[home] = int(home_stress.get(home, 0)) - stress
		home_n[home] = int(home_n.get(home, 0)) - 1
	source_grades.clear()
	source_c_ready = false


## Grades.average_stress for a room of a graded kind: -1 when no occupant has travelled.
func average_stress(room: int, by_work: bool) -> int:
	var n: int = (work_n if by_work else home_n).get(room, 0)
	if n == 0:
		return -1
	return int((work_stress if by_work else home_stress)[room]) / n


## Mood.room_average: -1 when nobody works or lives there.
func room_average(room: int) -> int:
	var n: int = mood_n.get(room, 0)
	return int(mood_total[room]) / n if n > 0 else -1
