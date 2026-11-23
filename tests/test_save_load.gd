extends RefCounted
## Save and load to file (#124): a busy tower survives a round trip through a file with the
## same state hash and then keeps evolving identically; bad files are refused; autosave rotates.

const TowerSim := preload("res://scripts/sim/tower.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const Bench := preload("res://tools/bench_tower.gd")
const Driver := preload("res://scripts/view/sim_driver.gd")

## Files of this run only (process id and clock), so two test runs at once never share one.
static var _run_id: String = "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
static var PATH: String = "user://test_save_load_%s.sav" % _run_id
static var BAD_PATH: String = "user://test_save_load_bad_%s.sav" % _run_id


static func _busy() -> TowerSim:
	var t := Bench.build(42, 24, 3)
	var condo := CatalogueScript.IDS.find("condo")
	for column in [200, 220, 240]:
		t.rooms.place_room(t.grid, t.floors, t.ledger, 0, condo, 6, column)
	t.rooms.place_room(t.grid, t.floors, t.ledger, 0, CatalogueScript.IDS.find("hotel_single"), 6, 260)
	t.rooms.place_escalator(t.grid, t.floors, t.ledger, 0, 3, 300)
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 4, 330)
	var offices: Array[int] = []
	for id in t.rooms.room_ids():
		if t.rooms.kind_of(id) == "office":
			offices.append(id)
	t.rent.set_rent(t.rooms, offices[0], 3)
	t.rent.set_rent(t.rooms, offices[1], 0)
	t.messages.add(0, 1, 2, 3)
	t.stars = 4
	return t


static func _run_ticks(t: TowerSim, count: int) -> void:
	for _i in count:
		t.step()


static func run(check: Callable) -> void:
	var real_template := SaveFiles.autosave_template
	SaveFiles.autosave_template = "user://test_autosave_%s_%%d.sav" % _run_id
	var t := _busy()
	var quarters := 0
	while quarters < 2 and t.tick < 20000:
		t.step()
		if t.clock.quarter_started:
			quarters += 1
	check.call(quarters == 2 and t.people.count() > 0, "save: the busy tower ran two quarters with people in it")
	t.ledger.income(t.tick, 4000000000000, 0)  # a value a float would round
	var saved_hash := t.state_hash()
	check.call(SaveFiles.write(t, PATH), "save: the tower writes to a file")
	var copy := TowerSim.new(0)
	check.call(SaveFiles.load_into(copy, PATH), "save: the file loads")
	check.call(copy.state_hash() == saved_hash, "save: the loaded tower has the saved hash")
	check.call(copy.ledger.balance == t.ledger.balance, "save: big integers stay exact")
	_run_ticks(t, 1500)
	_run_ticks(copy, 1500)
	check.call(copy.state_hash() == t.state_hash(), "save: both towers still match after stepping further")

	# Bad files are refused and change nothing.
	var untouched := TowerSim.new(5)
	var before := untouched.state_hash()
	var junk := FileAccess.open(BAD_PATH, FileAccess.WRITE)
	junk.store_string("not a save")
	junk.close()
	check.call(not SaveFiles.load_into(untouched, BAD_PATH) and untouched.state_hash() == before, "save: a junk file is refused")
	check.call(not SaveFiles.load_into(untouched, "user://does_not_exist.sav"), "save: a missing file is refused")
	var old_data := TowerSim.new(5).save()
	old_data["version"] = 39  # below the oldest version the migrator upgrades (#395)
	var old := FileAccess.open(BAD_PATH, FileAccess.WRITE)
	old.store_pascal_string(SaveFiles.MAGIC)
	old.store_var(old_data)
	old.close()
	check.call(not SaveFiles.load_into(untouched, BAD_PATH) and untouched.state_hash() == before, "save: a file from an older version is refused")
	check.call(SaveFiles.problem(BAD_PATH).contains("version 39"), "save: an old file gets a message naming its version")
	check.call(SaveFiles.problem(PATH) == "", "save: a good file has no problem")

	# Autosave: off by default; on, it writes one slot per quarter, rotating.
	var d := Driver.new()
	for _i in 4000:
		d.tower.step()
	check.call(not d.autosave_enabled, "save: autosave is off by default")
	var slots: Array[int] = []
	for q in 4:
		var clock := d.tower.clock
		slots.append(SaveFiles.autosave_slot(clock))
		while not clock.quarter_started:
			d.tower.step()
		d.tower.step()
	check.call(slots[0] != slots[1] and slots[1] != slots[2] and slots[3] == slots[0], "save: autosave slots rotate through %d files" % SaveFiles.AUTOSAVE_SLOTS)
	d.autosave_enabled = true
	for slot in SaveFiles.AUTOSAVE_SLOTS:
		DirAccess.remove_absolute(SaveFiles.autosave_path(slot))
	check.call(SaveFiles.newest_autosave() == "", "save: no autosave files at first")
	var guard := 0
	while SaveFiles.newest_autosave() == "" and guard < 5000:
		d.run_frame(1.0 / 30.0 * 20.0)
		guard += 1
	check.call(SaveFiles.newest_autosave() != "", "save: the driver autosaves when a quarter begins")
	var auto := TowerSim.new(0)
	check.call(SaveFiles.load_into(auto, SaveFiles.newest_autosave()), "save: an autosave loads")
	for slot in SaveFiles.AUTOSAVE_SLOTS:
		DirAccess.remove_absolute(SaveFiles.autosave_path(slot))
	DirAccess.remove_absolute(PATH)
	DirAccess.remove_absolute(BAD_PATH)
	SaveFiles.autosave_template = real_template
	d.free()
	_slots(check, t)


## Named slots, demo separation and the refused-version message (#386).
static func _slots(check: Callable, t: TowerSim) -> void:
	var normal_path := "user://test_slot_normal_%s.sav" % _run_id
	var demo_path := "user://test_slot_demo_%s.sav" % _run_id
	check.call(SaveFiles.slot_path(1, false) != SaveFiles.slot_path(1, true), "save: demo slots are separate files from normal slots")
	check.call(SaveFiles.quick_path(false) != SaveFiles.quick_path(true), "save: demo quick save is a separate file")
	check.call(SaveFiles.write(t, normal_path, "Alpha", false) and SaveFiles.write(t, demo_path, "Beta", true), "save: named slots write")
	check.call(SaveFiles.read_meta(demo_path).get("demo", false) == true and SaveFiles.read_meta(normal_path).get("demo", true) == false, "save: the slot records whether it is demo")
	var entry := SaveFiles.entry_for(normal_path, "Slot 1", false)
	check.call(entry["name"] == "Alpha" and entry["stars"] == t.stars and entry["population"] == t.permanent_population() and entry["day"] == SaveFiles.day_number(t), "save: a slot lists name, stars, population and day")
	var text := SaveFiles.describe(entry)
	check.call(text.contains("Alpha") and text.contains("%d stars" % t.stars) and text.contains("pop %d" % t.permanent_population()) and text.contains("day %d" % SaveFiles.day_number(t)), "save: the slot description shows the details")
	check.call(SaveFiles.describe(SaveFiles.entry_for("user://no_such_slot_%s.sav" % _run_id, "Slot 2", false)) == "Slot 2: empty", "save: a missing slot reads as empty")
	var loaded := TowerSim.new(0)
	check.call(SaveFiles.load_into(loaded, demo_path) and loaded.state_hash() == t.state_hash(), "save: a slot with a summary record still loads exactly")
	# An old version is refused with a message naming both versions, and the slot says so too.
	var old_data := t.save()
	old_data["version"] = 7
	var old := FileAccess.open(normal_path, FileAccess.WRITE)
	old.store_pascal_string(SaveFiles.MAGIC)
	old.store_var(old_data)
	old.close()
	var why := SaveFiles.problem(normal_path)
	check.call(why.contains("version 7") and why.contains("version %d" % TowerSim.SAVE_VERSION), "save: the refusal names the found and expected versions")
	check.call(SaveFiles.describe(SaveFiles.entry_for(normal_path, "Slot 1", false)).contains("version 7"), "save: the slot list shows why an old save cannot load")
	DirAccess.remove_absolute(normal_path)
	DirAccess.remove_absolute(demo_path)
