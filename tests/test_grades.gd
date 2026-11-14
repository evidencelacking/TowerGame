extends RefCounted
## Quality score and grade tests (5.1): thresholds, neutral until a first trip, stress average,
## ungraded kinds, the modifier hook and save round trip.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Grades := preload("res://scripts/sim/grades.gd")
const TestCondos := preload("res://tests/test_condos.gd")
const TestTenancy := preload("res://tests/test_tenancy.gd")


## A connected tower with one sold condo whose 3 residents have all made a trip (home by 19:00).
static func _travelled() -> TowerSim:
	var t := TestCondos._tower()
	TestTenancy._link(t)
	TestCondos._at(t, 10 * 60, 0)
	TestCondos._at(t, 19 * 60, 0)
	return t


static func _set_all(t: TowerSim, stress: int) -> void:
	for i in t.people.count():
		t.people.set_stress(i, stress)


static func run(check: Callable) -> void:
	# Thresholds: quality 149 is C, 150 and 200 are B, 201 is A (stress 151, 150, 100, 99).
	check.call(Grades.grade_of_quality(149) == Grades.GRADE_C, "quality 149 is C")
	check.call(Grades.grade_of_quality(150) == Grades.GRADE_B, "quality 150 is B")
	check.call(Grades.grade_of_quality(200) == Grades.GRADE_B, "quality 200 is B")
	check.call(Grades.grade_of_quality(201) == Grades.GRADE_A, "quality 201 is A")
	check.call(Grades.grade_of_quality(0) == Grades.GRADE_C and Grades.grade_of_quality(300) == Grades.GRADE_A, "the ends are C and A")
	check.call(Grades.letter(Grades.GRADE_A) == "A" and Grades.letter(Grades.GRADE_C) == "C" and Grades.letter(Grades.GRADE_NONE) == "", "grade letters")

	# A new room is a neutral B until its occupants make a trip.
	var fresh := TestCondos._tower()
	var condo := TestCondos._condo(fresh)
	for k in 3:
		fresh.people.add_person(condo, -1, fresh.rng)
	check.call(fresh.people.count() == 3 and fresh.quality(condo) == Grades.NEUTRAL_QUALITY and fresh.grade(condo) == Grades.GRADE_B, "a new condo is a neutral B before any trip")
	_set_all(fresh, 0)
	check.call(fresh.grade(condo) == Grades.GRADE_B, "no trips yet: stress alone does not move the grade")

	# After their first trips stress counts.
	var t := _travelled()
	condo = TestCondos._condo(t)
	_set_all(t, 0)
	check.call(t.quality(condo) == 300 and t.grade(condo) == Grades.GRADE_A, "zero stress after trips is quality 300 and A")
	for case in [[99, 201, Grades.GRADE_A], [100, 200, Grades.GRADE_B], [150, 150, Grades.GRADE_B], [151, 149, Grades.GRADE_C], [300, 0, Grades.GRADE_C]]:
		_set_all(t, case[0])
		check.call(t.quality(condo) == case[1] and t.grade(condo) == case[2], "stress %d is quality %d" % [case[0], case[1]])

	# The average is over the occupants, rounded down.
	t.people.set_stress(0, 100)
	t.people.set_stress(1, 100)
	t.people.set_stress(2, 101)
	check.call(t.quality(condo) == 200, "average stress 100 (301 over 3 rounds down) is quality 200")

	# Not graded: an unknown room gives -1 and GRADE_NONE.
	check.call(t.quality(-5) == -1 and t.grade(-5) == Grades.GRADE_NONE, "an unknown room is not graded")
	check.call(not Grades.is_graded("restaurant") and not Grades.is_graded("retail") and Grades.is_graded("office") and Grades.is_graded("hotel_suite"), "only offices, condos and hotels are graded")

	# The modifier hook adds stress to the average, clamped.
	_set_all(t, 100)
	t.grades.add_modifier(func(_room: int) -> int: return 51)
	check.call(t.quality(condo) == 149 and t.grade(condo) == Grades.GRADE_C, "a +51 stress modifier drops 200 to 149")
	t.grades.add_modifier(func(_room: int) -> int: return 1000)
	check.call(t.quality(condo) == 0, "modifiers clamp so quality stays within 0 to 300")

	# Save round trip keeps who has travelled.
	var saved := _travelled()
	var other := TowerSim.new(7, 100000000)
	check.call(other.load_state(saved.save()), "a save with grades loads")
	check.call(other.state_hash() == saved.state_hash(), "grades state survives a save round trip")
	_set_all(saved, 0)
	_set_all(other, 0)
	check.call(other.quality(TestCondos._condo(other)) == 300 and saved.quality(TestCondos._condo(saved)) == 300, "the travelled flags survive a save: quality is not the neutral value")
	var bad := saved.save()
	bad["grades"] = [5]
	check.call(not TowerSim.new(7, 100000000).load_state(bad), "a malformed grades list is refused")
