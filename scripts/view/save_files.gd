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
static var autosave_template: String = AUTOSAVE_PATH  ## Tests point this at a file of their own, so parallel runs never share autosaves.


## The autosave slot for a quarter: consecutive quarters use consecutive slots.
static func autosave_slot(clock: Clock) -> int:
	return ((clock.year() - 1) * Clock.QUARTERS_PER_YEAR + clock.quarter() - 1) % AUTOSAVE_SLOTS


static func autosave_path(slot: int) -> String:
	return autosave_template % slot


## Writes the tower's save to path. Returns true on success.
static func write(tower: TowerSim, path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_pascal_string(MAGIC)
	file.store_var(tower.save())
	file.close()
	return file.get_error() == OK


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
	if version != TowerSim.SAVE_VERSION:
		return "Save is from version %s; this game reads version %d" % [str(version), TowerSim.SAVE_VERSION]
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
