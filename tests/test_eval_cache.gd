extends RefCounted
## Evaluation tables, the noise cache and the people index (#416): each answers what the scan it replaced answered.

const TowerSim := preload("res://scripts/sim/tower.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const NoiseSim := preload("res://scripts/sim/noise.gd")
const MoodScript := preload("res://scripts/sim/mood.gd")
const EvalTablesScript := preload("res://scripts/sim/eval_tables.gd")


static func run(check: Callable) -> void:
	_forget_room(check)
	var t := TowerSim.new(7, 1000000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 131, 2)
	for f in range(2, 6):
		t.floors.fill_span(f, 100, 170)
	for spec: Array in [["condo", 3, 100], ["office", 4, 100], ["condo", 3, 120], ["office", 3, 140]]:
		t.rooms.place_room(t.grid, t.floors, t.ledger, 0, CatalogueScript.IDS.find(spec[0]), spec[1], spec[2])
	var ids := t.rooms.room_ids()
	check.call(ids.size() == 4, "eval cache: fixture rooms placed")
	for id in ids:
		for n in t.rooms.people_in(id):
			if t.rooms.kind_of(id) == "office":
				t.people.add_person(-1, id, t.rng)
			else:
				t.people.add_person(id, -1, t.rng)
	for i in t.people.count():
		t.people.set_stress(i, 20 * i)
		t.people.set_mood(i, 30 + 3 * i)
		t.people.set_low_days(i, i % 7)
		t.grades._tripped[t.people.id_at(i)] = i % 3 != 0

	# The tables answer what the scans answer.
	var tables := EvalTablesScript.build(t.rooms, t.grid, t.people, t.grades, MoodScript.LEAVE_DAYS)
	var same := true
	for id in ids:
		var scanned_grade := t.grades.grade(t.rooms, t.people, id)
		var scanned_avg := MoodScript.room_average(t.people, id)
		var scanned_notice := MoodScript.gave_notice(t.people, id)
		var scanned_workers := t.people.workers_in(id)
		var scanned_stress := t.grades.average_stress(t.rooms, t.people, id)
		t.grades.batch = tables
		same = same and t.grades.grade(t.rooms, t.people, id) == scanned_grade and t.grades.average_stress(t.rooms, t.people, id) == scanned_stress
		t.grades.batch = null
		same = same and MoodScript.room_average(t.people, id, tables) == scanned_avg and MoodScript.gave_notice(t.people, id, tables) == scanned_notice
		same = same and int(tables.workers.get(id, 0)) == scanned_workers
	check.call(same, "eval cache: tables give the same grade, stress, average mood, notice and workers as the scans")

	# Mood targets and factors agree with and without the tables.
	var counts := MoodScript.floor_counts(t.people, t.grid, t.floors)
	t.grades.batch = tables
	var targets_same := true
	for i in t.people.count():
		targets_same = targets_same and t.mood.target(t.rooms, t.grid, t.grades, t.people, counts, i, tables) == t.mood.target(t.rooms, t.grid, t.grades, t.people, counts, i)
		targets_same = targets_same and t.mood.factors(t.rooms, t.grid, t.grades, t.people, counts, i, tables) == t.mood.factors(t.rooms, t.grid, t.grades, t.people, counts, i)
	t.grades.batch = null
	check.call(targets_same, "eval cache: mood target and factors match with and without tables")

	# The noise cache follows the layout.
	var condo := ids[2]
	var before := NoiseSim.noise_at(t.grid, t.rooms, condo)
	t.rooms.place_room(t.grid, t.floors, t.ledger, 0, CatalogueScript.IDS.find("office"), 4, 124)
	var after := NoiseSim.noise_at(t.grid, t.rooms, condo)
	check.call(after > before, "eval cache: noise is recomputed after a room is placed")
	check.call(NoiseSim.noise_at(t.grid, t.rooms, condo) == after and NoiseSim.levels(t.grid, t.rooms).get(condo, 0) == after, "eval cache: noise reads the same twice")
	t.grid.remove(t.rooms.room_ids()[-1])
	check.call(NoiseSim.noise_at(t.grid, t.rooms, condo) == before, "eval cache: removing the added room restores the old level")

	# The people index follows adds, removals and loads.
	var ok := true
	for i in t.people.count():
		ok = ok and t.people.index_of(t.people.id_at(i)) == i
	check.call(ok and t.people.index_of(99999) == -1, "people index: every id finds its index")
	var gone := t.people.id_at(1)
	t.people.remove_person(1)
	ok = t.people.index_of(gone) == -1
	for i in t.people.count():
		ok = ok and t.people.index_of(t.people.id_at(i)) == i
	check.call(ok, "people index: stays right after a removal")
	t.people.remove_room(t.people.home_of(0))
	ok = true
	for i in t.people.count():
		ok = ok and t.people.index_of(t.people.id_at(i)) == i
	var copy := TowerSim.new(7, 1000000000)
	copy.people.load_ints(t.people.state_ints())
	for i in copy.people.count():
		ok = ok and copy.people.index_of(copy.people.id_at(i)) == i
	check.call(ok, "people index: stays right after remove_room and a load")


static func _forget_room(check: Callable) -> void:
	# Taking a room's people out of the tables leaves what a fresh build gives (#452), including a person whose
	# home and work are different rooms.
	var t := TowerSim.new(7, 1000000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 131, 2)
	for f in range(2, 6):
		t.floors.fill_span(f, 100, 170)
	for spec: Array in [["condo", 3, 100], ["office", 4, 100], ["condo", 3, 120], ["office", 3, 140]]:
		t.rooms.place_room(t.grid, t.floors, t.ledger, 0, CatalogueScript.IDS.find(spec[0]), spec[1], spec[2])
	var ids := t.rooms.room_ids()
	for id in ids:
		for n in t.rooms.people_in(id):
			if t.rooms.kind_of(id) == "office":
				t.people.add_person(-1, id, t.rng)
			else:
				t.people.add_person(id, -1, t.rng)
	for i in t.people.count():
		t.people.set_stress(i, 20 * i)
		t.people.set_mood(i, 30 + 3 * i)
		t.people.set_low_days(i, i % 7)
		t.grades._tripped[t.people.id_at(i)] = i % 3 != 0
	var cross := t.people.add_person(ids[0], ids[1], t.rng)
	var cross_at := t.people.index_of(cross)
	t.people.set_mood(cross_at, 0)
	t.people.set_low_days(cross_at, MoodScript.LEAVE_DAYS)
	t.grades._tripped[cross] = true
	for gone_room: int in [ids[0], ids[3], ids[1]]:
		var live := EvalTablesScript.build(t.rooms, t.grid, t.people, t.grades, MoodScript.LEAVE_DAYS)
		live.forget_room(t.people, t.grades, gone_room)
		t.people.remove_room(gone_room)
		var fresh := EvalTablesScript.build(t.rooms, t.grid, t.people, t.grades, MoodScript.LEAVE_DAYS)
		var tables_match := true
		for field: String in ["workers", "mood_total", "mood_n", "notice", "work_stress", "work_n", "home_stress", "home_n"]:
			var a: Dictionary = live.get(field)
			var b: Dictionary = fresh.get(field)
			var keys_a := a.keys()
			var keys_b := b.keys()
			keys_a.sort()
			keys_b.sort()
			tables_match = tables_match and keys_a == keys_b
			for key: int in keys_b:
				tables_match = tables_match and a.get(key) == b[key]
		check.call(tables_match, "eval cache: forgetting room %d leaves the tables a fresh build gives" % gone_room)
