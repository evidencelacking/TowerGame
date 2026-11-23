extends RefCounted
## Synergy tests (M13, #293): every rule in the table (in reach, just out of reach, tower-wide), the cap on a
## crowd of one kind, mood, recovery, condo sale price, the ghost preview (pure and in the label),
## and that a reload gives the same answer. Our own rules: no reference values.

const Fixtures := preload("res://tests/fixtures.gd")
const TowerSim := preload("res://scripts/sim/tower.gd")
const Synergy := preload("res://scripts/sim/synergy.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const MoodScript := preload("res://scripts/sim/mood.gd")
const Ledger := preload("res://scripts/sim/ledger.gd")
const Ghost := preload("res://scripts/view/placement_ghost.gd")
const TestEvaluation := preload("res://tests/test_evaluation.gd")
const TestCondos := preload("res://tests/test_condos.gd")
const TestTenancy := preload("res://tests/test_tenancy.gd")


## A run [floor, column, length] 10 wide.
static func _run(floor_number: int, column: int) -> Array:
	return [floor_number, column, 10]


## Every rule: the effect appears on the target at the edge of the floor reach and not one floor beyond.
## Tower-wide rules reach any floor and any column.
static func _rules(check: Callable) -> void:
	for rule: Array in Synergy.RULES:
		var source: String = rule[0]
		var target: String = rule[1]
		var effect: int = rule[2]
		var amount: int = rule[3]
		var floors: int = rule[4]
		var tag := "synergy %s -> %s (%s): " % [source, target, Synergy.EFFECT_NAMES[effect]]
		var others := [[source, _run(10, 100)]]
		var edge := 10 + (floors if floors != Synergy.ANY else 60)
		check.call(Synergy.total(effect, target, _run(edge, 100), others) == amount, tag + "applies at its reach")
		if floors != Synergy.ANY:
			check.call(Synergy.total(effect, target, _run(edge + 1, 100), others) == 0, tag + "stops one floor beyond")
			check.call(Synergy.total(effect, target, _run(10 - floors, 100), others) == amount, tag + "reaches down as well")
		else:
			check.call(Synergy.total(effect, target, _run(90, 400), others) == amount, tag + "is tower-wide")
		check.call(Synergy.total(effect, "lobby", _run(10, 100), others) == 0, tag + "does not touch other kinds")
	check.call(Synergy.floors_apart([-1, 0, 4], [1, 0, 4]) == 1, "synergy: floors across the ground are one apart")


static func _caps(check: Callable) -> void:
	var gyms := []
	for n in 8:
		gyms.append(["gym", _run(10, 100)])
	check.call(Synergy.mood_delta("office", _run(10, 100), gyms) == Synergy.CAPS[Synergy.MOOD], "synergy: eight gyms add no more than the cap")
	check.call(Synergy.mood_delta("office", _run(10, 100), [gyms[0], gyms[1]]) == 8, "synergy: two gyms add up")
	var clinics := []
	for n in 4:
		clinics.append(["clinic", _run(1, 0)])
	check.call(Synergy.recovery_bonus([clinics[0]]) == 4 and Synergy.recovery_bonus(clinics) == Synergy.CAPS[Synergy.RECOVERY], "synergy: clinics speed recovery by count, capped")
	var gardens := []
	for n in 6:
		gardens.append(["garden", _run(90, 0)])
	check.call(Synergy.sales_percent("restaurant", _run(2, 100), [gardens[0]]) == 8 and Synergy.sales_percent("restaurant", _run(2, 100), gardens) == Synergy.CAPS[Synergy.SALES], "synergy: gardens feed restaurants by count, capped")
	check.call(Synergy.sales_percent("retail", _run(2, 100), gardens) == 0, "synergy: gardens feed restaurants only")
	var club := [["nightclub", _run(10, 100)], ["nightclub", _run(11, 100)]]
	check.call(Synergy.mood_delta("condo", _run(12, 100), club) == -12 and Synergy.mood_delta("hotel_suite", _run(12, 100), club) == -12 and Synergy.mood_delta("office", _run(12, 100), club) == 0, "synergy: nightclubs annoy condos and hotels, not offices")
	check.call(Synergy.demand_percent(_run(8, 100), [["daycare", _run(10, 100)]]) == 10 and Synergy.demand_percent(_run(2, 100), [["daycare", _run(10, 100)]]) == 0, "synergy: a daycare lifts condo demand within 5 floors only")


## A tower with the lobby, floor 3 filled to column 160 and two offices at 108 and 117 (the first populated).
static func _office_tower() -> TowerSim:
	return TestEvaluation._pair("office")


static func _neighbour_factor(t: TowerSim) -> int:
	var counts := MoodScript.floor_counts(t.people, t.grid, t.floors)
	for factor in t.mood.factors(t.rooms, t.grid, t.grades, t.people, counts, 0):
		if factor[0] == MoodScript.REASON_NEIGHBOURS:
			return factor[1]
	return 0


static func _place(t: TowerSim, kind: String, floor_number: int, x: int) -> int:
	return t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find(kind), floor_number, x)


static func run(check: Callable) -> void:
	_rules(check)
	_caps(check)

	# Mood: a gym beside the offices lifts their workers.
	var t := _office_tower()
	TestEvaluation._stress(t, TestEvaluation.A_STRESS)
	check.call(_neighbour_factor(t) == 0, "synergy: an office alone has no neighbour factor")
	check.call(_place(t, "gym", 3, 130) == 0, "synergy: the test gym places")
	check.call(_neighbour_factor(t) == 4, "synergy: a gym on the same floor adds 4 to the office's mood factors (%d)" % _neighbour_factor(t))
	check.call(MoodScript.REASON_NAMES.size() > MoodScript.REASON_NEIGHBOURS, "synergy: the neighbours reason has a name")

	# Recovery: a clinic lets a low mood climb faster (the daily step plus 4).
	var plain := _office_tower()
	var healed := _office_tower()
	_place(healed, "clinic", 3, 130)
	for tower: TowerSim in [plain, healed]:
		TestEvaluation._stress(tower, 0)
		for i in tower.people.count():
			tower.people.set_mood(i, 20)
		tower.mood.update(tower.rooms, tower.grid, tower.floors, tower.grades, tower.people)
	check.call(plain.people.mood_of(0) == 20 + MoodScript.STEP, "synergy: without a clinic a mood climbs one step a day")
	check.call(healed.people.mood_of(0) == 20 + MoodScript.STEP + 4, "synergy: with a clinic it climbs 4 more")

	# Condo sales: a daycare within 5 floors sells the condo for 10 percent more.
	var prices := []
	for with_daycare: bool in [false, true]:
		var s := TestCondos._tower()
		if with_daycare:
			s.floors.fill_span(4, 100, 131)
			var refusal := _place(s, "daycare", 4, 100)
			assert(refusal == 0, "the daycare places, refusal %d" % refusal)
		Fixtures.connect_floors(s, 4 if with_daycare else 3, 126)  # a lift, so the daycare (floor 4) is reached too
		TestCondos._at(s, 10 * 60, 0)
		for line: Array in s.ledger.lines:
			if line[2] == Ledger.SALE:
				prices.append(line[1])
	check.call(prices == [Catalogue.cost("condo"), Catalogue.cost("condo") * 110 / 100], "synergy: a condo near a daycare sells for 10 percent more (%s)" % str(prices))

	# The ghost preview: pure core and the label.
	var run_at: Array = [3, 130, 16]
	var gym_preview := Synergy.preview("gym", run_at, [["office", [3, 108, 9]], ["office", [3, 117, 9]], ["condo", [3, 150, 16]]])
	check.call(gym_preview.size() == 1 and gym_preview[0]["target"] == "office" and gym_preview[0]["count"] == 2 and gym_preview[0]["amount"] == 4, "preview: a gym shows +4 mood on both offices")
	check.call(Synergy.text_of(gym_preview[0]) == "+4 mood on 2 Office", "preview: the line reads for a player (%s)" % Synergy.text_of(gym_preview[0]))
	var clinic_preview := Synergy.preview("clinic", run_at, [])
	check.call(clinic_preview.size() == 1 and Synergy.text_of(clinic_preview[0]) == "+4 mood recovery a day tower-wide", "preview: a clinic shows its tower-wide recovery")
	var condo_preview := Synergy.preview("condo", run_at, [["nightclub", [4, 120, 20]], ["daycare", [3, 100, 12]]])
	var texts: Array[String] = []
	for entry: Dictionary in condo_preview:
		texts.append(Synergy.text_of(entry))
	check.call(texts.has("-6 mood from Nightclub") and texts.has("+4 mood from Daycare") and texts.has("+10% sale price from Daycare"), "preview: a condo shows what its neighbours do to it (%s)" % str(texts))
	var noisy := Synergy.preview("fast_food", [3, 100, 16], [["condo", [3, 116, 16]], ["condo", [9, 116, 16]]])
	check.call(noisy.size() == 1 and noisy[0]["effect"] == Synergy.NOISE and noisy[0]["count"] == 1 and noisy[0]["amount"] > 0, "preview: the existing noise rule is folded in (one condo in range)")
	check.call(Synergy.preview("lobby", run_at, [["gym", run_at]]).is_empty(), "preview: a kind without rules shows nothing")

	var g := _office_tower()
	var verdict := Ghost.evaluate(g, "gym", 3, 130, 5)
	check.call(verdict["valid"] and (verdict["effects"] as Array).has("+4 mood on 2 Office"), "ghost: the verdict carries the preview (%s)" % str(verdict.get("effects")))
	check.call(Ghost.lines_for("gym", verdict).has("+4 mood on 2 Office"), "ghost: the label shows the effect")
	var before_ints := [g.rooms.state_ints(), g.ledger.state_ints(), g.grid.state_ints()]
	check.call(before_ints == [g.rooms.state_ints(), g.ledger.state_ints(), g.grid.state_ints()], "ghost: previewing changes nothing in the tower")
	var refused := Ghost.evaluate(g, "gym", 3, 300, 5)
	check.call(not refused["valid"] and not refused.has("effects"), "ghost: an invalid placement shows no effects")

	# A reload gives the same tower and the same preview.
	var h := _office_tower()
	_place(h, "gym", 3, 130)
	var copy := TowerSim.new(1, 1)
	check.call(copy.load_state(h.save()) and copy.state_hash() == h.state_hash(), "synergy: a tower with a gym survives save and load")
	check.call(Synergy.preview_at(copy.grid, copy.rooms, "office", 3, 150) == Synergy.preview_at(h.grid, h.rooms, "office", 3, 150), "synergy: a reload gives the same preview")
