class_name SaveFiles
extends RefCounted
## Save files (5.x): writes Tower.save() to disk and reads it back. File I/O lives here, in the
## view layer, so the sim stays file-free. The format is Godot's binary var encoding, which keeps
## 64-bit integers exact (JSON would turn them into floats).

const TowerSim := preload("res://scripts/sim/tower.gd")
const Clock := preload("res://scripts/sim/clock.gd")

const MANUAL_PATH := "user://tower.sav"
const AUTOSAVE_SLOTS := 3  ## Autosaves rotate through this many files, oldest overwritten first.
const AUTOSAVE_PATH := "user://autosave_%d.sav"
const MAGIC := "TOWERSAVE"
const SLOTS := 6  ## Named manual slots per mode.
const SLOT_PATH := "user://slot_%d.sav"
const DEMO_SLOT_PATH := "user://demo_slot_%d.sav"
const QUICK_PATH := "user://quicksave.sav"
const DEMO_QUICK_PATH := "user://demo_quicksave.sav"
const DEMO_AUTOSAVE_PATH := "user://demo_autosave_%d.sav"
## True in demo mode: autosaves and quick saves then go to the demo files and are marked demo.
static var demo: bool = false
## A save to apply after the scene reloads (switching between demo and normal play), or "".
static var pending_load: String = ""
static var autosave_template: String = AUTOSAVE_PATH  ## Tests point this at a file of their own, so parallel runs never share autosaves.


## The autosave slot for a quarter: consecutive quarters use consecutive slots.
static func autosave_slot(clock: Clock) -> int:
	return ((clock.year() - 1) * Clock.QUARTERS_PER_YEAR + clock.quarter() - 1) % AUTOSAVE_SLOTS


static func autosave_path(slot: int) -> String:
	return autosave_template % slot


## Writes the tower's save to path. Returns true on success.
## The optional slot name, demo flag and a summary (stars, population, day) go in a second record
## after the tower data, so the tower record itself is unchanged.
static func write(tower: TowerSim, path: String, slot_name: String = "", is_demo: bool = demo) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_pascal_string(MAGIC)
	file.store_var(tower.save())
	file.store_var({"name": slot_name, "demo": is_demo, "stars": tower.stars, "population": tower.population(), "day": day_number(tower)})
	file.close()
	return file.get_error() == OK


## The tower's day count since it began (1 on the first day).
static func day_number(tower: TowerSim) -> int:
	var clock := tower.clock
	return ((clock.year() - 1) * Clock.QUARTERS_PER_YEAR + clock.quarter() - 1) * Clock.DAYS_PER_QUARTER + clock.day_of_week() + 1


static func slot_path(slot: int, is_demo: bool) -> String:
	return (DEMO_SLOT_PATH if is_demo else SLOT_PATH) % slot


static func quick_path(is_demo: bool) -> String:
	return DEMO_QUICK_PATH if is_demo else QUICK_PATH


## The summary record of a save file ({} for older files without one or for non-saves).
static func read_meta(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var meta: Variant = null
	if file.get_length() > MAGIC.length() + 4 and file.get_pascal_string() == MAGIC:
		file.get_var(false)
		if file.get_position() < file.get_length():
			meta = file.get_var(false)
	file.close()
	return meta if meta is Dictionary else {}


## Every save file for a mode, in display order. Each entry: path, label, exists, demo, name,
## date (text), stars, population, day, problem ("" when loadable), modified (unix time).
static func entries(is_demo: bool) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for slot in range(1, SLOTS + 1):
		list.append(entry_for(slot_path(slot, is_demo), "Slot %d" % slot, is_demo))
	list.append(entry_for(quick_path(is_demo), "Quick save", is_demo))
	for slot in AUTOSAVE_SLOTS:
		var path := (DEMO_AUTOSAVE_PATH if is_demo else AUTOSAVE_PATH) % slot
		list.append(entry_for(path, "Autosave %d" % (slot + 1), is_demo))
	if not is_demo:
		list.append(entry_for(MANUAL_PATH, "Old manual save", is_demo))
	return list


static func entry_for(path: String, label: String, is_demo: bool) -> Dictionary:
	var entry := {"path": path, "label": label, "exists": FileAccess.file_exists(path), "demo": is_demo, "name": "", "date": "", "stars": 0, "population": 0, "day": 0, "problem": "", "modified": 0}
	if not entry["exists"]:
		return entry
	var meta := read_meta(path)
	entry["modified"] = FileAccess.get_modified_time(path)
	entry["date"] = Time.get_datetime_string_from_unix_time(entry["modified"], true).replace("T", " ").substr(0, 16)
	entry["name"] = str(meta.get("name", ""))
	entry["stars"] = int(meta.get("stars", 0))
	entry["population"] = int(meta.get("population", 0))
	entry["day"] = int(meta.get("day", 0))
	entry["problem"] = problem(path)
	return entry


## The most recently written loadable save across both modes, or {} if there is none.
static func latest() -> Dictionary:
	var best: Dictionary = {}
	for is_demo in [false, true]:
		for entry in entries(is_demo):
			if entry["exists"] and entry["problem"] == "" and (best.is_empty() or entry["modified"] > best["modified"]):
				best = entry
	return best


## One-line description of an entry for the slot list.
static func describe(entry: Dictionary) -> String:
	if not entry["exists"]:
		return "%s: empty" % entry["label"]
	var title := "%s" % entry["label"]
	if entry["name"] != "":
		title += " \"%s\"" % entry["name"]
	if entry["problem"] != "":
		return "%s, %s: %s" % [title, entry["date"], entry["problem"]]
	var text := "%s, %s" % [title, entry["date"]]
	if entry["day"] > 0:
		text += ", %d stars, pop %d, day %d" % [entry["stars"], entry["population"], entry["day"]]
	return text


## Reads a save file's data, or an empty Dictionary if it is missing or not a save.
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var magic_ok := file.get_length() > MAGIC.length() + 4 and file.get_pascal_string() == MAGIC
	var data: Variant = file.get_var(false) if magic_ok else null
	file.close()
	return data if data is Dictionary else {}


## Why a file cannot be loaded, for the player; "" if it looks loadable.
static func problem(path: String) -> String:
	if path == "" or not FileAccess.file_exists(path):
		return "No save file found"
	var data := read(path)
	if data.is_empty():
		return "Not a tower save file"
	var version: Variant = data.get("version", 0)
	if version != TowerSim.SAVE_VERSION and not SaveMigration.can_migrate(version, TowerSim.SAVE_VERSION):
		return "Save is from version %s but this game reads version %d (upgrades start at version %d), so it cannot be loaded" % [str(version), TowerSim.SAVE_VERSION, SaveMigration.MIN_VERSION]
	return ""


## Loads path into the tower. Returns false, leaving the tower unchanged, if it cannot.
static func load_into(tower: TowerSim, path: String) -> bool:
	var data := read(path)
	return not data.is_empty() and tower.load_state(data)


## Writes the tower to its quarter's autosave slot.
static func autosave(tower: TowerSim) -> bool:
	return write(tower, autosave_path(autosave_slot(tower.clock)))


## The autosave path holding the latest tick, or "" if there is none.
static func newest_autosave() -> String:
	var best := ""
	var best_tick := -1
	for slot in AUTOSAVE_SLOTS:
		var data := read(autosave_path(slot))
		if not data.is_empty() and data.get("tick", -1) is int and data["tick"] > best_tick:
			best_tick = data["tick"]
			best = autosave_path(slot)
	return best
