extends RefCounted
## Mood tests (12.2): each factor moves the target the right way, a day moves a mood at most
## STEP points, sustained low mood makes a condo or office give notice, happy rooms reach further
## for friends, the person window shows mood with its top reasons, and it all saves and is
## deterministic.

const TowerSim := preload("res://scripts/sim/tower.gd")
const MoodScript := preload("res://scripts/sim/mood.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")
const GradesScript := preload("res://scripts/sim/grades.gd")
const NoiseScript := preload("res://scripts/sim/noise.gd")
const EvaluationScript := preload("res://scripts/sim/evaluation.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const PersonInfo := preload("res://scripts/view/person_info.gd")
const TestEvaluation := preload("res://tests/test_evaluation.gd")


static func _target(t: TowerSim, counts: Dictionary = {}) -> int:
	return t.mood.target(t.rooms, t.grid, t.grades, t.people, counts, 0)


static func _has(t: TowerSim, reason: int, counts: Dictionary = {}) -> bool:
	for factor in t.mood.factors(t.rooms, t.grid, t.grades, t.people, counts, 0):
		if factor[0] == reason:
			return true
	return false


## Gives every person a mood and a count of low days.
static func _set_moods(t: TowerSim, mood: int, low_days: int) -> void:
	for i in t.people.count():
		t.people.set_mood(i, mood)
		t.people.set_low_days(i, low_days)


static func run(check: Callable) -> void:
	var t := TestEvaluation._pair("condo")
	check.call(t.people.count() > 0 and t.people.mood_of(0) == PeopleScript.MOOD_START, "mood: a new person starts at the start mood")

	# Travel: more stress, lower target.
	TestEvaluation._stress(t, 0)
	var calm := _target(t)
	TestEvaluation._stress(t, 200)
	check.call(_target(t) < calm and _has(t, MoodScript.REASON_TRAVEL), "mood: travel stress lowers the target and is listed")

	# Grade: C drags well below A.
	TestEvaluation._stress(t, TestEvaluation.A_STRESS)
	check.call(t.grade(t.people.home_of(0)) == GradesScript.GRADE_A and _has(t, MoodScript.REASON_GRADE), "mood: an A room lifts mood")
	var a_target := _target(t)
	TestEvaluation._stress(t, TestEvaluation.C_STRESS)
	check.call(t.grade(t.people.home_of(0)) == GradesScript.GRADE_C and _target(t) < a_target - MoodScript.GRADE_C_PENALTY, "mood: a C room drags mood down")

	# Crowding: a packed floor lowers it, a floor at the free limit does not, and it is capped. Stress is B
	# so the target is not clamped at the top.
	TestEvaluation._stress(t, TestEvaluation.B_STRESS)
	var floor_number: int = t.grid.run_of(t.people.home_of(0))[0]
	var quiet := _target(t, {floor_number: 0})
	var packed := _target(t, {floor_number: MoodScript.CROWD_FREE + 1000})
	check.call(packed < quiet and quiet - packed == MoodScript.CROWD_MAX, "mood: a packed floor lowers mood, capped at CROWD_MAX")
	check.call(_has(t, MoodScript.REASON_CROWD, {floor_number: MoodScript.CROWD_FREE + 20}) and not _has(t, MoodScript.REASON_CROWD, {floor_number: MoodScript.CROWD_FREE}), "mood: only a floor over the free limit is crowded")

	# Events: the shock lowers the target and the worst one of the day counts.
	var before_event := _target(t)
	t.mood.note_event(MoodScript.THREAT_SHOCK)
	t.mood.note_event(MoodScript.FIRE_SHOCK)
	check.call(_target(t) == before_event - MoodScript.FIRE_SHOCK and _has(t, MoodScript.REASON_EVENT), "mood: a fire shock lowers the target")
	t.mood.note_event(MoodScript.THREAT_SHOCK)
	check.call(t.mood.shock == MoodScript.FIRE_SHOCK, "mood: the worst shock of the day counts")

	# Noise: an office on the floor above the first condo.
	var n := TestEvaluation._pair("condo")
	TestEvaluation._stress(n, 0)
	var quiet_target := _target(n)
	n.floors.fill_span(4, 100, 160)
	n.rooms.place_room(n.grid, n.floors, n.ledger, 0, CatalogueScript.IDS.find("office"), 4, 108)
	check.call(NoiseScript.noise_at(n.grid, n.rooms, n.people.home_of(0)) > 0, "mood: the noisy neighbour is in range")
	check.call(_target(n) < quiet_target and _has(n, MoodScript.REASON_NOISE), "mood: noise lowers the target")

	# A day moves mood at most STEP toward the target and clears the shock; it settles on the target.
	var d := TestEvaluation._pair("condo")
	TestEvaluation._stress(d, 0)
	var start := d.people.mood_of(0)
	var goal := _target(d)
	d.mood.note_event(MoodScript.FIRE_SHOCK)
	d.mood.update(d.rooms, d.grid, d.grades, d.people)
	check.call(absi(d.people.mood_of(0) - start) <= MoodScript.STEP and d.mood.shock == 0, "mood: a day moves it at most one step and clears the shock")
	for k in 30:
		d.mood.update(d.rooms, d.grid, d.grades, d.people)
	check.call(d.people.mood_of(0) == goal and d.people.low_days_of(0) == 0, "mood: it settles on the target with no low days")

	# Sustained low mood: the tenants stay until the last low day, then give notice. Stress is held at B so
	# the grade rule is not what sends them away.
	for kind in ["condo", "office"]:
		var l := TestEvaluation._pair(kind)
		var room: int = l.rooms.room_ids()[0]
		TestEvaluation._stress(l, TestEvaluation.B_STRESS)
		_set_moods(l, 5, MoodScript.LEAVE_DAYS - 2)
		l.evaluate_tenants()  # low day LEAVE_DAYS - 1
		check.call(l.people.count() > 0 and l.people.low_days_of(0) == MoodScript.LEAVE_DAYS - 1, "mood %s: a low day short of notice, they stay" % kind)
		l.evaluate_tenants()  # low day LEAVE_DAYS
		check.call(l.people.count() == 0, "mood %s: sustained low mood sends the whole household away" % kind)
		check.call(not l.rooms.is_sold(room) if kind == "condo" else l.people.workers_in(room) == 0, "mood %s: the unit is vacant afterwards" % kind)
		# A recovered mood resets the count.
		var r := TestEvaluation._pair(kind)
		TestEvaluation._stress(r, 0)
		_set_moods(r, 90, MoodScript.LEAVE_DAYS - 1)
		r.evaluate_tenants()
		check.call(r.people.low_days_of(0) == 0, "mood %s: a content day resets the low-day count" % kind)

	# High mood: a vacant office just past the usual reach is only filled for a happy A room.
	for happy in [false, true]:
		var h := TestEvaluation._pair("office")
		h.destroy_room(h.rooms.room_ids()[h.rooms.room_ids().size() - 1])  # the vacant office (stairs have lower ids)
		var width: int = CatalogueScript.row("office")["width"]
		var bridge: int = CatalogueScript.row("condo")["width"]  # a room to walk through, so the far office is reachable
		var far_x := 108 + width + bridge
		h.rooms.place_room(h.grid, h.floors, h.ledger, 0, CatalogueScript.IDS.find("condo"), 3, 108 + width)
		h.rooms.place_room(h.grid, h.floors, h.ledger, 0, CatalogueScript.IDS.find("office"), 3, far_x)
		var count := h.people.count()
		var far: int = h.rooms.room_ids()[h.rooms.room_ids().size() - 1]
		check.call(h.rooms.kind_of(far) == "office" and h.grid.run_of(far)[1] == far_x and bridge > EvaluationScript.FRIEND_REACH and bridge <= EvaluationScript.FRIEND_REACH + MoodScript.FRIEND_REACH_BONUS, "mood: far vacant office placed (%s)" % happy)
		TestEvaluation._stress(h, 0)
		_set_moods(h, 100 if happy else 40, 0)
		h.evaluate_tenants()
		check.call((h.people.count() > count) == happy, "mood: a friend from just past the usual reach comes only when the room is happy (%s)" % happy)

	# Save round trip and determinism.
	var s := TestEvaluation._pair("condo")
	s.people.set_mood(0, 61)
	s.people.set_low_days(0, 3)
	s.mood.note_event(MoodScript.THREAT_SHOCK)
	var copy := TowerSim.new(7)
	check.call(copy.load_state(s.save()) and copy.people.mood_of(0) == 61 and copy.people.low_days_of(0) == 3 and copy.mood.shock == MoodScript.THREAT_SHOCK, "mood: mood, low days and the shock survive save and load")
	var one := TestEvaluation._pair("condo")
	var two := TestEvaluation._pair("condo")
	TestEvaluation._stress(one, 150)
	TestEvaluation._stress(two, 150)
	one.evaluate_tenants()
	two.evaluate_tenants()
	check.call(one.state_hash() == two.state_hash(), "mood: the same tower mood-updates the same way")

	# The person window shows mood and its top reason.
	var w := TestEvaluation._pair("condo")
	TestEvaluation._stress(w, TestEvaluation.C_STRESS)
	var info := PersonInfo.describe(w, 0)
	var lines := "\n".join(PersonInfo.lines_for(info))
	check.call(info["mood"] == w.people.mood_of(0) and lines.contains("Mood: %d" % info["mood"]), "mood: the person window shows the mood")
	check.call(not (info["mood_reasons"] as Array).is_empty() and lines.contains(MoodScript.REASON_NAMES[info["mood_reasons"][0][0]]), "mood: the person window names the top reason")
