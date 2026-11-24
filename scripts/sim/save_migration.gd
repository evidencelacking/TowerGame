class_name SaveMigration
extends RefCounted
## Save migration (#395): upgrades an older save dictionary, one version at a time, so a
## SAVE_VERSION bump does not strand the saves players already have.
##
## EVERY SAVE_VERSION BUMP IN Tower MUST ADD A STEP HERE. A step upgrades version N to N + 1: add
## a case for N in upgrade_step (a pure function: it returns a changed deep copy and never touches
## the argument or any tower), and describe it in the list below. tests/test_save_migration.gd fails
## if the current SAVE_VERSION has no step reaching it, and each step has its own test there.
## A bump whose change cannot be upgraded faithfully (state that cannot be derived from the old
## save) may instead raise MIN_VERSION above it, so older saves are refused with a clear message.
##
## Tower.load_state calls migrate before it validates anything, so a migrated save is held to the
## same checks as a fresh one. Integers and arrays only, so the simulation stays deterministic.
##
## Steps (each fills the new state with the defaults of a tower where it is unused):
##   40 -> 41  rooms: appends the empty stacked-flight layer (count 0)            (#259)
##   41 -> 42  adds "mood" (no shock); people records grow from 12 to 14 ints,
##             every person gaining mood 75 and 0 low days                        (#286)
##   42 -> 43  adds "life" (no couples, children, promotions or stories); a one-int mood
##             array (shock only) gains the empty shocked list                    (#287)
##   43 -> 44  commerce: appends visitors_today 0                                 (#383)
##   44 -> 45  fire: appends the charred-room list, empty                         (#373)
##   48 -> 49  adds "pipe", "stall" and "festival" at rest: no burst, stall or festival, each stream at 0  (#472 to #474)
##   45 -> 46  vip: appends the air-arrival stream (state 0), no draw yet (day -1), not by air  (#409)
## Versions below MIN_VERSION are refused: the layout before #259 is not recorded here.

const PipeScript := preload("res://scripts/sim/pipe.gd")
const StallScript := preload("res://scripts/sim/stall.gd")
const FestivalScript := preload("res://scripts/sim/festival.gd")
const WeddingScript := preload("res://scripts/sim/wedding.gd")
const MIN_VERSION := 40
const PEOPLE_HEADER := 3  ## Ints before the person records in "people".
const PEOPLE_OLD_FIELDS := 12  ## Per person before mood (v41).
const MOOD_START := 75  ## People.MOOD_START: a person arriving fairly content.


## True when a save of this version can be upgraded up to target by the steps below.
static func can_migrate(version: Variant, target: int) -> bool:
	if typeof(version) != TYPE_INT or version < MIN_VERSION or version > target:
		return false
	for v in range(version, target):
		if upgrade_step(v, {"version": v}).is_empty():
			return false
	return true


## Upgrades data to version target, or returns an empty dictionary if it cannot be done.
## A save already at target comes back as it was.
static func migrate(data: Dictionary, target: int) -> Dictionary:
	var version: Variant = data.get("version", 0)
	if not can_migrate(version, target):
		return {}
	var current := data
	for v in range(version, target):
		current = upgrade_step(v, current)
		if current.is_empty():
			return {}
	return current


## One step, version -> version + 1, as a changed deep copy. Returns an empty dictionary when
## there is no step for version or the data does not have the shape that version had.
static func upgrade_step(version: int, data: Dictionary) -> Dictionary:
	var out: Dictionary = data.duplicate(true)
	match version:
		40:
			_append(out, "rooms", [0])
		41:
			out["mood"] = [0]  # the v42 layout: the shock alone
			if not _widen_people(out):
				return {}
		42:
			out["life"] = [0, 0, 0, 0]
			var mood: Variant = out.get("mood")
			if mood is Array and mood.size() == 1:
				mood.append(0)
		43:
			_append(out, "commerce", [0])
		44:
			_append(out, "fire", [0])
		45:
			_append(out, "vip", [0, -1, 0])  # Vip.DEFAULT_STREAM, no draw made, not by air
		46:
			out["weather"] = [0, 0, 0, 0]  # Weather.DEFAULT_STREAM, no rain, treasure not found: its spot comes from the seed
		47:
			_append(out, "vip", [0, 0, 0])  # no open notice, no rate chosen, no reasons
		48:
			out["pipe"] = PipeScript.rest_ints()  # no burst, the stream at its default (#472)
			out["stall"] = StallScript.rest_ints()  # no stall, nothing armed (#473)
			out["festival"] = FestivalScript.rest_ints()  # no festival armed, announced or held (#474)
		49:
			out["wedding"] = WeddingScript.rest_ints()  # no wedding set, no top rank (#33)
		50:
			out["cheated"] = 0  # no cheats used (#39)
		_:
			return {}
	out["version"] = version + 1
	return out


static func _append(out: Dictionary, key: String, extra: Array) -> void:
	var ints: Variant = out.get(key)
	if ints is Array:
		ints.append_array(extra)


## Adds mood and low days to each person record. False if the array is not a whole number of records.
static func _widen_people(out: Dictionary) -> bool:
	var ints: Variant = out.get("people")
	if not ints is Array:
		return true  # absent or not an array: load_state refuses it
	if ints.size() < PEOPLE_HEADER or typeof(ints[2]) != TYPE_INT or ints.size() != PEOPLE_HEADER + PEOPLE_OLD_FIELDS * ints[2]:
		return false
	var wide: Array = ints.slice(0, PEOPLE_HEADER)
	for n in ints[2]:
		var at: int = PEOPLE_HEADER + n * PEOPLE_OLD_FIELDS
		wide.append_array(ints.slice(at, at + PEOPLE_OLD_FIELDS))
		wide.append_array([MOOD_START, 0])
	out["people"] = wide
	return true
