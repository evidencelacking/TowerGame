extends RefCounted
## Word of mouth tests (5.6): a C room lowers nearby tenants by the configured amount, a room
## out of reach is untouched, recovery is immediate, quality stays in 0 to 300, the stack caps,
## and complaints do not chain.

const TowerSim := preload("res://scripts/sim/tower.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const Grades := preload("res://scripts/sim/grades.gd")
const WordOfMouth := preload("res://scripts/sim/word_of_mouth.gd")


## Condos at the given [floor, column] spots (width 16), each with 3 residents who have all
## made a trip. Returns the room ids in order. Fails the caller's checks if a placement fails.
static func _build(t: TowerSim, spots: Array) -> Array[int]:
	t.floors.build_lobby(t.ledger, 0, 1, 100, 331, 2)
	for floor_number in [3, 4, 5]:
		t.floors.fill_span(floor_number, 100, 331)
	for spot in spots:
		t.rooms.place_room(t.grid, t.floors, t.ledger, 0, CatalogueScript.IDS.find("condo"), spot[0], spot[1])
	var ids := t.rooms.room_ids()  # ascending, so placement order
	var tripped: Array[int] = [0]
	for id in ids:
		for k in 3:
			var i := t.people.add_person(id, -1, t.rng)
			tripped.append(t.people.id_at(i))
	tripped[0] = tripped.size() - 1
	t.grades.load_ints(tripped)
	for id in ids:
		_stress(t, id, 100)
	return ids


## Sets every resident of the room to the stress.
static func _stress(t: TowerSim, room: int, stress: int) -> void:
	for i in t.people.count():
		if t.people.home_of(i) == room:
			t.people.set_stress(i, stress)


static func run(check: Callable) -> void:
	var penalty := WordOfMouth.STRESS_PER_COMPLAINER

	# Source at column 110 (ends 126), a neighbour 4 columns on, a far room at 300.
	var t := TowerSim.new(7, 100000000)
	var ids := _build(t, [[3, 110], [3, 130], [3, 300]])
	check.call(ids.size() == 3, "three condos were placed")
	var src := ids[0]
	var near := ids[1]
	var far := ids[2]
	check.call(t.quality(src) == 200 and t.quality(near) == 200 and t.quality(far) == 200, "baseline: all three are quality 200 (B)")

	# 1. One C room lowers its B neighbour by the configured amount.
	_stress(t, src, 200)
	check.call(t.grade(src) == Grades.GRADE_C and t.quality(src) == 100, "the source is C at quality 100 and not lowered by its own complaint")
	check.call(t.grade(near) == Grades.GRADE_B and t.quality(near) == 200 - penalty, "a C neighbour lowers a B room by exactly the penalty")
	# 2. A room outside the radius is unaffected.
	check.call(t.quality(far) == 200, "a room out of reach is unaffected")

	# 3. Recovery: when the C room becomes B or A the neighbour recovers on the next read.
	_stress(t, src, 100)
	check.call(t.quality(near) == 200, "the neighbour recovers when the source is B")
	_stress(t, src, 0)
	check.call(t.quality(near) == 200, "and when the source is A (praise does not spread)")

	# 4. Quality stays within 0 to 300.
	_stress(t, src, 200)
	_stress(t, near, 300)
	check.call(t.quality(near) == 0, "a neighbour already at stress 300 stays at quality 0")
	_stress(t, near, 0)
	check.call(t.quality(near) == 300 - penalty, "a neighbour at stress 0 loses the penalty but never passes 300")

	# 5. Several C neighbours stack, capped. Middle room (floor 4, column 150) has four spots in
	# reach: floors 3 and 5 at column 150, and column 130 and 170 on floor 4.
	var many := TowerSim.new(7, 100000000)
	var m := _build(many, [[4, 150], [3, 150], [5, 150], [4, 130], [4, 170]])
	var mid := m[0]
	_stress(many, m[1], 200)
	check.call(many.quality(mid) == 200 - penalty, "one C neighbour in reach lowers by one penalty")
	_stress(many, m[2], 200)
	check.call(many.quality(mid) == 200 - 2 * penalty, "two C neighbours stack")
	_stress(many, m[3], 200)
	check.call(many.quality(mid) == 200 - 3 * penalty and WordOfMouth.MAX_COMPLAINERS == 3, "three stack to the cap")
	_stress(many, m[4], 200)
	check.call(many.quality(mid) == 200 - WordOfMouth.MAX_COMPLAINERS * penalty, "a fourth C neighbour adds nothing beyond the cap")

	# Complaints do not chain: mid is tipped to C by one complaint, and a tail room that only mid
	# reaches (24 columns from the source) stays untouched.
	var chain := TowerSim.new(7, 100000000)
	var c := _build(chain, [[3, 110], [3, 130], [3, 150]])
	_stress(chain, c[0], 200)
	_stress(chain, c[1], 150)
	check.call(chain.grade(c[1]) == Grades.GRADE_C and chain.quality(c[1]) == 150 - penalty, "word of mouth can tip a neighbour to C")
	check.call(chain.quality(c[2]) == 200, "a room reached only by that tipped neighbour is not lowered: no chains")

	# Reach is NEIGHBOUR_FLOORS floors and NEIGHBOUR_GAP columns, inclusive.
	var a: Array[int] = [3, 100, 16]
	var up: Array[int] = [3 + WordOfMouth.NEIGHBOUR_FLOORS, 100, 16]
	var too_high: Array[int] = [3 + WordOfMouth.NEIGHBOUR_FLOORS + 1, 100, 16]
	check.call(WordOfMouth._near(a, up) and not WordOfMouth._near(a, too_high), "reach is NEIGHBOUR_FLOORS floors")
	var edge: Array[int] = [3, 116 + WordOfMouth.NEIGHBOUR_GAP, 16]
	var beyond: Array[int] = [3, 116 + WordOfMouth.NEIGHBOUR_GAP + 1, 16]
	check.call(WordOfMouth._near(a, edge) and not WordOfMouth._near(a, beyond), "reach is NEIGHBOUR_GAP columns between edges")
