extends RefCounted
## Promotion moment tests (7.2, #167): the banner fires once per rank, not for a new or loaded
## tower, once for two ranks in one tick with every unlock listed, the sound hook fires once,
## the message log entry exists, and the toolbar marks exactly the new unlocks.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Msg := preload("res://scripts/sim/messages.gd")
const Promotion := preload("res://scripts/view/promotion.gd")
const Banner := preload("res://scripts/view/promotion_banner.gd")
const Toolbar := preload("res://scripts/view/toolbar.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const Ghost := preload("res://scripts/view/placement_ghost.gd")


static func _sorted(ids: Array) -> Array:
	var copy := ids.duplicate()
	copy.sort()
	return copy


static func run(check: Callable) -> void:
	# What each rank unlocks comes from the catalogue, in toolbar order.
	var two := Promotion.unlocks_between(1, 2)
	for id in ["service_shaft", "hotel_single", "housekeeping", "security"]:
		check.call(two.has(id), "star 2 unlocks %s" % id)
	var expected: Array = []
	for id: String in Catalogue.IDS:
		if Toolbar.star_of(id) == 2:
			expected.append(id)
	check.call(_sorted(two) == _sorted(expected), "star 2 lists exactly the star 2 rooms")
	var three := Promotion.unlocks_between(2, 3)
	for id in ["escalator", "express_shaft", "hotel_twin", "hotel_suite", "restaurant", "retail", "movie_theatre", "party_hall", "medical", "recycling", "parking_ramp", "parking_space"]:
		check.call(three.has(id), "star 3 unlocks %s" % id)
	check.call(not three.has("security") and not three.has("office"), "star 3 does not repeat earlier unlocks")
	check.call(Promotion.unlocks_between(1, 3).size() == two.size() + three.size(), "two ranks at once list both ranks' unlocks")

	# Once only.
	var tower := TowerSim.new(1)
	var seen := Promotion.new()
	check.call(seen.observe(tower).is_empty(), "a new tower shows no banner")
	tower.stars = 2
	var info := seen.observe(tower)
	check.call(info.get("stars", 0) == 2 and _sorted(info["unlocks"]) == _sorted(two), "reaching 2 stars announces star 2 with its unlocks")
	check.call(seen.observe(tower).is_empty() and seen.observe(tower).is_empty(), "the same rank is announced only once")
	tower.stars = 4
	info = seen.observe(tower)
	check.call(info.get("stars", 0) == 4 and info["unlocks"].has("escalator") and info["unlocks"].has("metro"), "two ranks in one tick give one announcement for the higher rank with all unlocks")
	check.call(seen.observe(tower).is_empty(), "and not again")

	# A loaded tower is adopted silently, even at a high rank, and a lower rank is not announced.
	var loaded := TowerSim.new(2)
	loaded.stars = 3
	check.call(seen.observe(loaded).is_empty(), "loading a tower at 3 stars shows no banner")
	check.call(seen.observe(loaded).is_empty(), "and none afterwards")
	loaded.stars = 4
	check.call(seen.observe(loaded).get("stars", 0) == 4, "a later promotion on the loaded tower is announced")

	# The message log entry comes from the sim's promotion.
	var sim := TowerSim.new(3)
	for i in 300:
		sim.people.add_person(0, People.NONE, sim.rng)
	sim.promote_stars()
	var logged := 0
	for i in sim.messages.count():
		if sim.messages.entry(i)[1] == Msg.STAR_PROMOTED:
			logged += 1
	check.call(logged == 1, "the promotion adds one message log entry")

	# The banner node: shows once, fires the sound hook once, and the toolbar marks the unlocks.
	var banner := Banner.new()
	banner._ready()
	var hooks: Array[int] = []
	banner.promoted.connect(func(stars: int) -> void: hooks.append(stars))
	var bar := Toolbar.new()
	bar._ready()
	banner.unlocked.connect(bar.mark_new)
	var world := TowerSim.new(4)
	banner.bind(world)
	check.call(not banner.is_showing() and hooks.is_empty(), "the banner is hidden at the start")
	world.stars = 2
	banner.check()
	banner.check()
	check.call(banner.is_showing() and hooks == [2], "the banner shows and the sound hook fires once")
	check.call(banner._headline.text.contains("2") and banner._unlocks.text.contains("Security"), "the banner names the rank and what it unlocks")
	banner._process(Banner.SHOW_SECONDS + 1.0)
	check.call(not banner.is_showing() and hooks == [2], "the banner goes away after a few seconds and does not return")
	check.call(bar.is_new("security") and bar.is_new("hotel_single") and not bar.is_new("office") and not bar.is_new("escalator"), "the toolbar marks exactly the new unlocks")
	var ghost := Ghost.new()
	ghost.tower = world
	bar.bind(ghost)
	bar.select("hotel_single")
	check.call(not bar.is_new("hotel_single") and bar.is_new("security"), "picking an item clears its mark")
	ghost.free()
	bar.free()
	banner.free()
