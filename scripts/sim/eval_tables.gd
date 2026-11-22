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
## Ids of the people shocked by an event since the last evaluation (empty when there was none).
var shocked: Dictionary = {}


## grades must offer tripped(id: int) -> bool; leave_days is Mood.LEAVE_DAYS.
static func build(rooms: RoomsScript, grid: GridScript, people: PeopleScript, grades_of: RefCounted, leave_days: int) -> RefCounted:
	var t := new()
	t.others = SynergyScript.others_of(grid, rooms)
	for i in people.count():
		var work := people.work_of(i)
		var home := people.home_of(i)
		var mood := people.mood_of(i)
		var low := people.low_days_of(i) >= leave_days
		if work != PeopleScript.NONE:
			t.workers[work] = int(t.workers.get(work, 0)) + 1
			_note(t, work, mood, low)
		if home != PeopleScript.NONE and home != work:
			_note(t, home, mood, low)
		if grades_of.tripped(people.id_at(i)):
			var stress := people.stress_of(i)
			if work != PeopleScript.NONE:
				t.work_stress[work] = int(t.work_stress.get(work, 0)) + stress
				t.work_n[work] = int(t.work_n.get(work, 0)) + 1
			if home != PeopleScript.NONE:
				t.home_stress[home] = int(t.home_stress.get(home, 0)) + stress
				t.home_n[home] = int(t.home_n.get(home, 0)) + 1
	return t


static func _note(t: RefCounted, room: int, mood: int, low: bool) -> void:
	t.mood_total[room] = int(t.mood_total.get(room, 0)) + mood
	t.mood_n[room] = int(t.mood_n.get(room, 0)) + 1
	if low:
		t.notice[room] = true


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
