extends RefCounted
## The slow cadence (#459): slow state checks run every Tower.SLOW_EVERY ticks, and a day's totals must still match the
## per-tick behaviour. REFERENCE was measured on main before the change (tools/cadence_metrics.gd, the mixed tower, seed 42,
## three days from its start tick): rows of rent, hotel, sale, shop, complaints, grade A, B, C, total quality.

const Metrics := preload("res://tools/cadence_metrics.gd")
const MoodScript := preload("res://scripts/sim/mood.gd")
const TestPopulation := preload("res://tests/test_population.gd")

const REFERENCE: Array[Array] = [
	[806586, 144000, 5760000, 0, 507, 344, 142, 0, 120480],
	[806586, 104000, 0, 0, 243, 326, 160, 0, 123355],
	[806828, 34000, 0, 0, 507, 316, 170, 0, 117445],
]
const DAYS := 2  ## Days measured: the first two of the reference's three, a day of stepping less (was 3, #466).
const RENT_TOLERANCE_PERCENT := 1  ## Rent is collected daily from the same tenants: it should barely move.
const HOTEL_TOLERANCE_PERCENT := 5  ## Over the measured days: a check-out lands a few minutes later, so one night may move a day.
const COMPLAINT_TOLERANCE_PERCENT := 5
const GRADE_TOLERANCE := 6  ## Rooms, of about 490 graded rooms.
const QUALITY_TOLERANCE_PERCENT := 2


static func run(check: Callable) -> void:
	run_membership(check)
	run_permanent_population(check)
	run_threat_population_after_load(check)
	run_daily_totals(check)


## The shocked set keeps insertion order and answers membership without scanning (#448).
static func run_membership(check: Callable) -> void:
	var t := TestPopulation._tower()
	TestPopulation._at(t, 10 * 60)
	t.mood.note_event(MoodScript.FIRE_SHOCK, t.people)
	var once := t.mood.state_ints()
	check.call(once[1] > 0, "membership fixture: someone was inside to be shocked (%d)" % once[1])
	t.mood.note_event(MoodScript.FIRE_SHOCK, t.people)
	check.call(t.mood.state_ints() == once, "noting an event twice adds nobody twice")
	var copy := MoodScript.new()
	copy.load_ints(once)
	copy.note_event(MoodScript.FIRE_SHOCK, t.people)
	check.call(copy.state_ints() == once, "a loaded shocked list answers membership too")


## The permanent population counts every registered person once, whether or not they are inside, and no visitors.
static func run_permanent_population(check: Callable) -> void:
	var t := TestPopulation._tower()
	TestPopulation._at(t, 10 * 60)
	check.call(t.permanent_population() == t.people.count() and t.permanent_population() > 0, "permanent population is everyone registered")
	check.call(t.permanent_population() >= t.people.in_tower_count(), "the permanent population is never below the people inside now")
	check.call(t.star_facts()["population"] == t.permanent_population(), "star_facts reads the permanent population")


## The threat gate's population is set on every Events roll tick from the live count, so a game loaded between
## cadence runs rolls with the same number as one that never stopped (rules-keeper on #462).
static func run_threat_population_after_load(check: Callable) -> void:
	var t := TestPopulation._tower()
	TestPopulation._at(t, 10 * 60)
	t.step()  # off any cadence boundary on purpose: the save lands between runs
	var copy := Tower.new()
	check.call(copy.load_state(t.save()), "threat fixture: the tower saves and loads")
	var rolled := false
	for _i in 3000:  # a period is far shorter than this, so a roll tick comes; the loop always ends
		t.step()
		copy.step()
		if t.clock.ticks_in_period() == 0:
			rolled = true
			break
	check.call(rolled and copy.threat.population == t.threat.population and t.threat.population == t.population(), "after a load the next roll sees the same live population (%d, %d)" % [copy.threat.population, t.threat.population])

## The first days on the mixed tower stay within tolerance of the per-tick reference.
static func run_daily_totals(check: Callable) -> void:
	var rows := Metrics.measure(DAYS)
	check.call(rows.size() == DAYS, "the cadence metrics ran for %d days" % DAYS)
	var hotel := 0
	var hotel_ref := 0
	for day in mini(rows.size(), DAYS):
		var row: Array = rows[day]
		var ref: Array = REFERENCE[day]
		var label := "day %d" % (day + 1)
		check.call(_within_percent(row[0], ref[0], RENT_TOLERANCE_PERCENT), "%s rent %d is within %d%% of the per-tick %d" % [label, row[0], RENT_TOLERANCE_PERCENT, ref[0]])
		check.call(row[2] == ref[2] and row[3] == ref[3], "%s condo sales and shop takings match (%d, %d)" % [label, row[2], row[3]])
		check.call(_within_percent(row[4], ref[4], COMPLAINT_TOLERANCE_PERCENT), "%s complaints %d are within %d%% of the per-tick %d" % [label, row[4], COMPLAINT_TOLERANCE_PERCENT, ref[4]])
		for g in range(5, 8):
			check.call(absi(row[g] - ref[g]) <= GRADE_TOLERANCE, "%s grade count %d is %d against the per-tick %d" % [label, g - 5, row[g], ref[g]])
		check.call(_within_percent(row[8], ref[8], QUALITY_TOLERANCE_PERCENT), "%s total quality %d is within %d%% of the per-tick %d" % [label, row[8], QUALITY_TOLERANCE_PERCENT, ref[8]])
		hotel += row[1]
		hotel_ref += ref[1]
	check.call(_within_percent(hotel, hotel_ref, HOTEL_TOLERANCE_PERCENT), "hotel income over %d days %d is within %d%% of the per-tick %d" % [DAYS, hotel, HOTEL_TOLERANCE_PERCENT, hotel_ref])


static func _within_percent(value: int, reference: int, percent: int) -> bool:
	return absi(value - reference) * 100 <= reference * percent
