extends RefCounted
## Office lunch (#439, our own design, unverified numbers): the lunch coverage figure, the weekday stress through the
## Grades modifier, the NO_FOOD complaint, the food demand and its one-shot message, the weekend and small-tower
## exemptions, and a sustained shortfall that drops the grade and moves the tenant out.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Commerce := preload("res://scripts/sim/commerce.gd")
const Complaints := preload("res://scripts/sim/complaints.gd")
const Demands := preload("res://scripts/sim/demands.gd")
const Messages := preload("res://scripts/sim/messages.gd")
const Grades := preload("res://scripts/sim/grades.gd")
const Clock := preload("res://scripts/sim/clock.gd")
const TestComplaints := preload("res://tests/test_complaints.gd")

const FIRST_ID := 7000
const STRESS := 85  ## An A office (quality 215): +10 stays A, +20 drops to B.


## offices offices and the listed shop kinds, injected straight into the grid and kind table (as the complaint tests do).
## Offices are ids FIRST_ID and up, one per floor; shops follow on floors 60 and up. Inject everything before the first
## read: the coverage is cached per layout revision, which injection does not bump.
static func _tower(offices: int, shops: Array[String]) -> TowerSim:
	var t := TestComplaints._tower()
	for k in offices:
		TestComplaints._inject(t, FIRST_ID + k, "office", 10 + k, 100)
	for k in shops.size():
		TestComplaints._inject(t, FIRST_ID + 500 + k, shops[k], 60 + k, 100)
	return t


static func _has_food_reason(t: TowerSim, office: int) -> bool:
	return t.complaint_reasons(office).has(Complaints.NO_FOOD)


static func _raised(t: TowerSim) -> int:
	var n := 0
	for i in t.messages.count():
		var e := t.messages.entry(i)
		if e[1] == Messages.DEMAND_RAISED and e[2] == Demands.FOOD:
			n += 1
	return n


static func run(check: Callable) -> void:
	# The figure: one fast food is 24 seats x 60 / 30 = 48; a second doubles it; pizza and sushi serve lunch, the cafe does not.
	var one := _tower(1, ["fast_food"])
	var two := _tower(1, ["fast_food", "fast_food"])
	check.call(Commerce.lunch_capacity(one.rooms) == 48, "lunch: one fast food seats 48 at lunch (%d)" % Commerce.lunch_capacity(one.rooms))
	check.call(Commerce.lunch_capacity(two.rooms) == 96, "lunch: a second fast food doubles it (%d)" % Commerce.lunch_capacity(two.rooms))
	check.call(Commerce.lunch_coverage(one.rooms) == 800, "lunch: coverage is capacity x 100 over 6 workers per office (%d)" % Commerce.lunch_coverage(one.rooms))
	check.call(Commerce.lunch_capacity(_tower(1, ["pizza"]).rooms) > 0 and Commerce.lunch_capacity(_tower(1, ["sushi"]).rooms) > 0, "lunch: pizza and sushi count")
	check.call(Commerce.lunch_capacity(_tower(1, ["cafe", "restaurant", "fine_dining", "bar"]).rooms) == 0, "lunch: the cafe and the dinner-only places do not count")
	check.call(Commerce.lunch_coverage(_tower(0, ["fast_food"]).rooms) == -1, "lunch: no offices, no coverage figure")

	# 20 offices, no food: NO_FOOD on all, the demand open, +20 stress.
	var office := FIRST_ID
	var bare := _tower(20, [])
	TestComplaints._occupy(bare, office, STRESS)
	check.call(Commerce.lunch_coverage(bare.rooms) == 0, "lunch: no food is 0 percent")
	check.call(_has_food_reason(bare, office) and _has_food_reason(bare, FIRST_ID + 19), "lunch: every office complains of no food")
	var calm := _tower(20, [])
	TestComplaints._occupy(calm, office, 10)  # under the distance line, so food is the only cause
	check.call(calm.complaint_reason(office) == Complaints.NO_FOOD, "lunch: with no other cause it is the main reason")
	check.call(Complaints.label(Complaints.NO_FOOD) != "", "lunch: the complaint has words")
	check.call(bare.quality(office) == 300 - STRESS - 20, "lunch: under 25 percent adds 20 stress (quality %d)" % bare.quality(office))
	var fed := _tower(20, ["fast_food", "fast_food", "fast_food"])
	TestComplaints._occupy(fed, office, STRESS)
	check.call(Commerce.lunch_coverage(fed.rooms) == 120, "lunch: three fast foods cover 120 percent")
	check.call(not _has_food_reason(fed, office) and fed.quality(office) == 300 - STRESS, "lunch: enough food clears the reason and the stress")
	bare.promote_stars()
	fed.promote_stars()
	check.call(bare.demands.is_open(Demands.FOOD) and _raised(bare) == 1, "lunch: the food demand opens with one message")
	bare.promote_stars()
	check.call(_raised(bare) == 1, "lunch: the demand message is one-shot")
	check.call(not fed.demands.is_open(Demands.FOOD) and _raised(fed) == 0, "lunch: enough food leaves the demand closed")

	# The steps: 25 to 49 percent is +10, under 25 is +20, 50 and over is nothing.
	var mid := _tower(20, ["fast_food"])  # 48 / 120 = 40 percent
	TestComplaints._occupy(mid, office, STRESS)
	check.call(Commerce.lunch_coverage(mid.rooms) == 40 and mid.quality(office) == 300 - STRESS - 10, "lunch: 40 percent adds 10 stress")
	check.call(_has_food_reason(mid, office), "lunch: 40 percent still complains")
	var half := _tower(20, ["fast_food", "fast_food"])  # 96 / 120 = 80 percent
	TestComplaints._occupy(half, office, STRESS)
	check.call(not _has_food_reason(half, office) and half.quality(office) == 300 - STRESS, "lunch: 80 percent has no complaint and no stress")
	half.promote_stars()
	check.call(half.demands.is_open(Demands.FOOD), "lunch: 80 percent still leaves the demand open")

	# 5 offices, no food: no penalty.
	var few := _tower(5, [])
	TestComplaints._occupy(few, office, STRESS)
	check.call(not _has_food_reason(few, office) and few.quality(office) == 300 - STRESS, "lunch: five offices pay nothing")

	# Weekend: no penalty.
	var weekend := _tower(20, [])
	TestComplaints._occupy(weekend, office, STRESS)
	weekend.clock._day = Clock.WE
	check.call(not _has_food_reason(weekend, office) and weekend.quality(office) == 300 - STRESS, "lunch: the weekend has no penalty")
	weekend.clock._day = Clock.WD2
	check.call(_has_food_reason(weekend, office) and weekend.quality(office) == 300 - STRESS - 20, "lunch: the second weekday has it")

	# Only offices complain.
	var mixed := _tower(20, [])
	TestComplaints._inject(mixed, 9000, "condo", 80, 100)
	check.call(not _has_food_reason(mixed, 9000), "lunch: a condo has no food complaint")

	# Priority: after RENT and before UNREACHED.
	var order := Complaints.PRIORITY
	check.call(order.find(Complaints.NO_FOOD) == order.find(Complaints.RENT) + 1 and order.find(Complaints.NO_FOOD) + 1 == order.find(Complaints.UNREACHED), "lunch: NO_FOOD sits after RENT and before UNREACHED")

	# Sustained shortfall: a B office falls to C, gives notice and leaves; the same office with food stays.
	var gone := _tower(20, [])
	TestComplaints._occupy(gone, office, 140)
	check.call(gone.grade(office) == Grades.GRADE_C, "lunch: the shortfall drops a B office to C")
	var fine := _tower(20, ["fast_food", "fast_food", "fast_food"])
	TestComplaints._occupy(fine, office, 140)
	check.call(fine.grade(office) == Grades.GRADE_B, "lunch: the same office with food stays B")
	var heads := gone.people.workers_in(office)
	check.call(heads > 0, "lunch: the office starts occupied")
	for day in 8:
		gone.evaluate_tenants()
		fine.evaluate_tenants()
	check.call(gone.people.workers_in(office) == 0, "lunch: a sustained shortfall moves the tenant out")
	check.call(fine.people.workers_in(office) == heads, "lunch: with food the tenant stays")

	# Deterministic.
	var d1 := _tower(20, ["fast_food"])
	var d2 := _tower(20, ["fast_food"])
	TestComplaints._occupy(d1, office, STRESS)
	TestComplaints._occupy(d2, office, STRESS)
	check.call(d1.quality(office) == d2.quality(office) and d1.complaint_reasons(office) == d2.complaint_reasons(office), "lunch: the same tower gives the same answer")
