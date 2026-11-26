extends RefCounted
## Difficulty presets (#380): Normal is all 100 percent (so the pinned hashes elsewhere stay put), Easy and Hard scale
## funds, income, event odds and prices and mood recovery, and nothing else; the star thresholds are the same under every
## preset; the preset is saved, and a save from before it loads as Normal.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Difficulty := preload("res://scripts/sim/difficulty.gd")
const StarRules := preload("res://scripts/sim/star_rules.gd")
const Fire := preload("res://scripts/sim/fire.gd")
const Threat := preload("res://scripts/sim/threat.gd")


static func _tower(preset: int) -> TowerSim:
	return TowerSim.new(5, 2000000, preset)


## What one rent and one hotel payment of 1000 add to the balance.
static func _gain(t: TowerSim) -> int:
	var before := t.ledger.balance
	t.ledger.income(0, 1000, 0)
	t.ledger.hotel(0, 1000, 0)
	return t.ledger.balance - before


static func run(check: Callable) -> void:
	for knob: String in [Difficulty.FUNDS, Difficulty.INCOME, Difficulty.CHANCE, Difficulty.COST, Difficulty.MOOD]:
		check.call(Difficulty.percent(Difficulty.NORMAL, knob) == 100, "difficulty: Normal leaves %s at 100 percent" % knob)
	check.call(Difficulty.DEFAULT == Difficulty.NORMAL and TowerSim.new().difficulty == Difficulty.NORMAL, "difficulty: a tower built without a preset is Normal")
	check.call(Difficulty.scale(1000, Difficulty.EASY, Difficulty.INCOME) == 1200 and Difficulty.scale(1000, Difficulty.HARD, Difficulty.INCOME) == 900, "difficulty: scale is value * percent / 100 in whole numbers")
	check.call(not Difficulty.is_valid(3) and not Difficulty.is_valid(-1) and not Difficulty.is_valid("1") and Difficulty.is_valid(0), "difficulty: only 0 to 2 are presets")

	var easy := _tower(Difficulty.EASY)
	var normal := _tower(Difficulty.NORMAL)
	var hard := _tower(Difficulty.HARD)
	check.call(easy.ledger.balance == 3000000 and normal.ledger.balance == 2000000 and hard.ledger.balance == 1500000, "difficulty: starting funds are 150, 100 and 75 percent")
	check.call(_gain(easy) == 2400 and _gain(normal) == 2000 and _gain(hard) == 1800, "difficulty: rent and hotel takings are 120, 100 and 90 percent")

	check.call(easy.fire.rescue_cost() == 250000 and normal.fire.rescue_cost() == 500000 and hard.fire.rescue_cost() == 625000, "difficulty: the fire rescue costs 50, 100 and 125 percent")
	check.call(easy.events.kind_def(Fire.KIND)["costs"] == [0, 250000] and hard.events.kind_def(Fire.KIND)["costs"] == [0, 625000], "difficulty: the fire card charges the scaled rescue")
	check.call(easy.events.kind_def(Threat.KIND)["costs"] == [0, 100000] and normal.events.kind_def(Threat.KIND)["costs"] == [0, 200000] and hard.events.kind_def(Threat.KIND)["costs"] == [0, 250000], "difficulty: the ransom is scaled")
	check.call(normal.events.kind_def(Threat.KIND)["labels"][1] == "Pay $200,000" and hard.events.kind_def(Threat.KIND)["labels"][1] == "Pay $250,000", "difficulty: the ransom label quotes the scaled price")
	check.call(easy.pipe.plumber_cost() == 12500 and normal.pipe.plumber_cost() == 25000 and hard.pipe.plumber_cost() == 31250, "difficulty: the plumber is scaled")
	check.call(easy.stall.rescue_cost() == 5000 and normal.stall.rescue_cost() == 10000 and hard.stall.rescue_cost() == 12500, "difficulty: the stall rescue crew is scaled")
	check.call(Fire.repair_cost("office", easy.fire.cost_pct) * 2 == Fire.repair_cost("office") and Fire.repair_cost("office") > 0, "difficulty: repairs are half price on Easy")
	check.call(easy.fire.chance_pct == 50 and hard.fire.chance_pct == 150 and easy.threat.chance_pct == 50 and hard.stall.chance_pct == 150, "difficulty: event odds are 50, 100 and 150 percent")
	check.call(easy.mood.step_pct == 125 and normal.mood.step_pct == 100 and hard.mood.step_pct == 75, "difficulty: mood moves 125, 100 and 75 percent as far")

	# Never scaled: the star thresholds and the top rank are the same under every preset.
	var requirements := {2: {"population": 300}, 3: {"population": 1000, "security": 1}, 4: {"population": 5000, "suites": 2, "demands_met": true, "vip_good": true}, 5: {"population": 10000, "metro": 1}}
	var top := {"stars": 5, "population": 15000, "cathedral": true}
	for t: TowerSim in [easy, normal, hard]:
		check.call(StarRules.REQUIREMENTS == requirements and StarRules.TOP_RANK == top, "difficulty: star thresholds and top rank are the literal reference values under preset %d" % t.difficulty)
		check.call(not StarRules.meets(2, {"population": 299}) and StarRules.meets(2, {"population": 300}) and StarRules.population_for(5) == 10000, "difficulty: promotion at 300 people under preset %d" % t.difficulty)

	# Save and load.
	var saved := hard.save()
	check.call(saved["version"] == TowerSim.SAVE_VERSION and saved["version"] == 54 and saved["difficulty"] == Difficulty.HARD, "difficulty: the save holds the preset at version 54")
	var loaded := TowerSim.new()
	check.call(loaded.load_state(saved) and loaded.difficulty == Difficulty.HARD, "difficulty: a Hard save loads as Hard")
	check.call(loaded.fire.cost_pct == 125 and loaded.ledger.income_pct == 90 and loaded.state_hash() == hard.state_hash(), "difficulty: a loaded Hard tower applies its knobs and hashes the same")
	var hash_hard := hard.state_hash()
	hard.set_difficulty(Difficulty.NORMAL)
	check.call(hard.state_hash() != hash_hard, "difficulty: the preset is part of the hash off Normal")
	var old := normal.save()
	old.erase("difficulty")
	old["version"] = 52
	var upgraded := TowerSim.new(0, 2000000, Difficulty.HARD)
	check.call(upgraded.load_state(old) and upgraded.difficulty == Difficulty.NORMAL and upgraded.fire.cost_pct == 100, "difficulty: a version 52 save loads as Normal")
	var bad := normal.save()
	bad["difficulty"] = 7
	check.call(not TowerSim.new().load_state(bad), "difficulty: an unknown preset in a save is refused")
