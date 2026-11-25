extends RefCounted
## The tutorial (#503): each step's trigger, a scripted command sequence that completes every step and
## reaches 300 people before the money runs out, skip, replay, the panel, and that it never touches the sim.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")

const LOBBY_X := 100
const LOBBY_W := 80
const TOP := 18  ## The scripted shaft serves floors 1 to 18.
const DAY := 1440


static func _kind(room: String) -> int:
	return Catalogue.IDS.find(room)


static func _send(tower: TowerSim, kind: int, args: Array[int]) -> void:
	assert(tower.enqueue(Command.make(tower.tick + 1, kind, args)), "the command queues")


static func _run(tower: TowerSim, ticks: int, tutorial: Tutorial = null) -> void:
	for _i in ticks:
		tower.step()
		if tutorial != null:
			tutorial.update(tower)


static func _lobby(tower: TowerSim) -> void:
	_send(tower, Command.BUILD_LOBBY, [1, LOBBY_X, LOBBY_X + LOBBY_W - 1, 1] as Array[int])


static func _floor(tower: TowerSim, f: int) -> void:
	_send(tower, Command.BUILD_FLOOR, [f, LOBBY_X, LOBBY_X + LOBBY_W - 1] as Array[int])


## One floor of the scripted tower: a floor strip, condos and an office beside the shaft at LOBBY_X
## (floor 2 swaps one condo for fast food, since floor 1 takes no rooms).
static func _build_floor(tower: TowerSim, f: int, food: bool = false) -> void:
	_floor(tower, f)
	var x := LOBBY_X + 4
	var condos := 4
	if food:
		_send(tower, Command.PLACE_ROOM, [_kind("fast_food"), f, x] as Array[int])
		x += 16
		condos = 3
	for _i in condos:
		_send(tower, Command.PLACE_ROOM, [_kind("condo"), f, x] as Array[int])
		x += 16
	_send(tower, Command.PLACE_ROOM, [_kind("office"), f, x] as Array[int])


## The scripted run, all through normal commands: lobby, floor with offices, elevator with a car, fast food and
## condos, then a floor a day while money lasts, until 2 stars. Steps `tutorial` (if any) after every tick, and
## returns the lowest balance seen.
static func play(tower: TowerSim, tutorial: Tutorial = null) -> int:
	var lowest := tower.ledger.balance
	_lobby(tower)
	_run(tower, 2, tutorial)
	_build_floor(tower, 2, true)
	_run(tower, 2, tutorial)
	_send(tower, Command.PLACE_SHAFT, [_kind("local_shaft"), 1, TOP, LOBBY_X] as Array[int])
	_run(tower, 2, tutorial)
	_send(tower, Command.ADD_CAR, [tower.rooms.shaft_ids()[0], 1] as Array[int])
	_run(tower, 2, tutorial)
	var f := 3
	for _day in 40:
		if f <= TOP and tower.ledger.balance > 600000:
			_build_floor(tower, f)
			f += 1
		for _i in DAY:
			_run(tower, 1, tutorial)
			lowest = mini(lowest, tower.ledger.balance)
		if tower.stars >= 2:
			break
	return lowest


static func _crowd(tower: TowerSim, n: int) -> void:
	for _i in n:
		tower.people.add_person(0, People.NONE, tower.rng)


static func run(check: Callable) -> void:
	# Each step's trigger, on a tower built a command at a time.
	var t := TowerSim.new(Tutorial.SEED)
	check.call(not Tutorial.done(0, t), "tutorial: no lobby, step 1 not done")
	_lobby(t)
	_run(t, 1)
	check.call(Tutorial.done(0, t), "tutorial: the lobby finishes step 1")
	check.call(not Tutorial.done(1, t), "tutorial: no offices yet")
	_floor(t, 2)
	_send(t, Command.PLACE_ROOM, [_kind("office"), 2, LOBBY_X + 4] as Array[int])
	_run(t, 1)
	check.call(not Tutorial.done(1, t), "tutorial: one office is not enough for step 2")
	_send(t, Command.PLACE_ROOM, [_kind("office"), 2, LOBBY_X + 14] as Array[int])
	_run(t, 1)
	check.call(Tutorial.done(1, t), "tutorial: two offices finish step 2")
	check.call(not Tutorial.done(2, t), "tutorial: offices with no elevator do not finish step 3")
	_send(t, Command.PLACE_SHAFT, [_kind("local_shaft"), 1, 2, LOBBY_X + 60] as Array[int])
	_run(t, 2)
	check.call(Tutorial.done(2, t), "tutorial: an elevator reaching the offices finishes step 3")

	# An office on floor 1 alone does not pass step 3: floor 1 takes no rooms, and a shaft with nothing above it
	# (or an office above the shaft's top) is not an elevator reaching an office.
	var low := TowerSim.new(Tutorial.SEED)
	_lobby(low)
	_floor(low, 2)
	_floor(low, 3)
	_send(low, Command.PLACE_ROOM, [_kind("office"), 1, LOBBY_X + 4] as Array[int])
	_send(low, Command.PLACE_SHAFT, [_kind("local_shaft"), 1, 2, LOBBY_X + 60] as Array[int])
	_send(low, Command.PLACE_ROOM, [_kind("office"), 3, LOBBY_X + 4] as Array[int])
	_run(low, 2)
	check.call(low.rooms.shaft_ids().size() == 1 and not Tutorial.done(2, low), "tutorial: an office on floor 1 and one the shaft does not reach do not finish step 3")
	check.call(not Tutorial.done(3, t), "tutorial: no fast food yet")
	_send(t, Command.PLACE_ROOM, [_kind("fast_food"), 2, LOBBY_X + 24] as Array[int])
	_run(t, 1)
	check.call(Tutorial.done(3, t), "tutorial: fast food finishes step 4")
	check.call(not Tutorial.done(4, t), "tutorial: no condo yet")
	_floor(t, 3)
	_send(t, Command.PLACE_ROOM, [_kind("condo"), 3, LOBBY_X + 4] as Array[int])
	_run(t, 1)
	check.call(Tutorial.done(4, t), "tutorial: a condo finishes step 5")

	var c := TowerSim.new(Tutorial.SEED)
	_crowd(c, 299)
	check.call(not Tutorial.done(5, c) and not Tutorial.done(6, c), "tutorial: 299 people finish neither of the last two steps")
	_crowd(c, 1)
	check.call(Tutorial.done(5, c), "tutorial: 300 people finish step 6")
	check.call(not Tutorial.done(6, c), "tutorial: 300 people at 1 star do not finish step 7 yet")
	c.promote_stars()
	check.call(c.stars == 2 and Tutorial.done(6, c), "tutorial: reaching 2 stars finishes step 7")

	# The scripted run completes every step and reaches 300 people before the money runs out.
	var tower := TowerSim.new(Tutorial.SEED)
	var tutorial := Tutorial.new()
	var lowest := play(tower, tutorial)
	check.call(tutorial.finished and not tutorial.is_active(), "tutorial: the scripted run completes the tutorial")
	check.call(tower.permanent_population() >= 300 and tower.stars == 2, "tutorial: the scripted run reaches 300 people and 2 stars")
	check.call(lowest > 100000, "tutorial: the scripted run never runs short of money (lowest %d)" % lowest)
	check.call(tutorial.title() == Tutorial.DONE_TITLE, "tutorial: the finished title shows")
	for word: String in ["security", "housekeeping", "hotels", "3 stars"]:
		check.call(Tutorial.DONE_TEXT.containsn(word), "tutorial: the completion message names %s" % word)
	check.call(Tutorial.STEPS.size() == 7, "tutorial: seven steps")

	# The tutorial only reads: the same commands without it end in the same state.
	var bare := TowerSim.new(Tutorial.SEED)
	play(bare)
	check.call(bare.state_hash() == tower.state_hash(), "tutorial: following the tower leaves the sim unchanged")

	# Replay: a fresh Tutorial on a new tower starts over.
	var again := Tutorial.new()
	again.update(TowerSim.new(Tutorial.SEED))
	check.call(again.step == 0 and again.is_active() and again.title() == "Lay the lobby", "tutorial: replay starts at step 1")
	again.update(tower)
	check.call(again.finished, "tutorial: a tower that has done everything completes it in one update")

	# Skip ends it cleanly: no more steps, and the tower is untouched.
	var skipped := Tutorial.new()
	var fresh := TowerSim.new(Tutorial.SEED)
	var hash_before := fresh.state_hash()
	skipped.skip()
	skipped.update(tower)
	check.call(not skipped.is_active() and not skipped.finished and skipped.step == 0, "tutorial: skip ends it without advancing")
	check.call(fresh.state_hash() == hash_before, "tutorial: skip leaves the tower alone")

	await _panel(check)


## The panel: shows the step, follows the tower a tick at a time, Skip frees it, and a loaded save ends it.
static func _panel(check: Callable) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var driver := SimDriver.new()
	tree.root.add_child(driver)
	driver.tower = TowerSim.new(Tutorial.SEED)
	var panel := TutorialPanel.new()
	tree.root.add_child(panel)
	panel.bind(driver)
	check.call(panel.title_label.text.contains("Lay the lobby") and panel.hint_label.text != "", "tutorial panel: shows the first step and a hint")
	check.call(panel.skip_button.text == "Skip tutorial", "tutorial panel: has a Skip button")
	_lobby(driver.tower)
	driver.tower.step()
	panel.poll()
	check.call(panel.tutorial.step == 1 and panel.title_label.text.contains("offices"), "tutorial panel: moves on when the sim reports the step done")
	panel.skip_button.pressed.emit()
	check.call(not panel.tutorial.is_active() and panel.is_queued_for_deletion(), "tutorial panel: Skip ends the tutorial and frees the panel")

	var loaded := TutorialPanel.new()
	tree.root.add_child(loaded)
	loaded.bind(driver)
	SaveFiles.loads += 1  # what SaveFiles.load_into does after a successful load
	loaded.poll()
	check.call(not loaded.tutorial.is_active() and loaded.is_queued_for_deletion(), "tutorial panel: loading a save ends the tutorial")
	SaveFiles.loads -= 1

	var shown_before := StartMenu.shown
	var save_menu := SaveMenu.new()
	tree.root.add_child(save_menu)
	var start := StartMenu.new()
	tree.root.add_child(start)
	start.bind(driver, save_menu)
	var button := start.find_child("Tutorial", true, false) as Button
	check.call(button != null and button.text == "Tutorial", "tutorial: the start menu has a Tutorial button")
	StartMenu.shown = shown_before
	start.queue_free()
	save_menu.queue_free()
	driver.queue_free()
