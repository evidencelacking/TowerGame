extends RefCounted
## Save migration (#395): every SAVE_VERSION has a step, each step upgrades a hand-reversed older
## save exactly, and an upgraded save loads as the same tower.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Migration := preload("res://scripts/sim/save_migration.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const Pipe := preload("res://scripts/sim/pipe.gd")
const Stall := preload("res://scripts/sim/stall.gd")
const Festival := preload("res://scripts/sim/festival.gd")
const Bench := preload("res://tools/bench_tower.gd")


static func _current() -> Dictionary:
	var t := Bench.build(42, 24, 3)
	var condo := CatalogueScript.IDS.find("condo")
	for column in [200, 220, 240]:
		t.rooms.place_room(t.grid, t.floors, t.ledger, 0, condo, 6, column)
	for _n in 400:
		t.step()
	# The v46 VIP stream is seeded per tower, which an upgrade cannot know: pin it to what the step appends.
	var vip_ints := t.vip.state_ints().slice(0, 6)
	vip_ints.append_array([0, -1, 0, 0, 0, 0])
	t.vip.load_ints(vip_ints)
	t.weather.load_ints([0, 0, 0, 0])  # likewise the v47 rain stream (Weather.DEFAULT_STREAM): seeded per tower, so pinned to what the step appends
	t.pipe.load_ints(Pipe.rest_ints())  # the v49 streams (DEFAULT_STREAM): seeded per tower, so pinned to what the step appends
	t.stall.load_ints(Stall.rest_ints())
	t.festival.load_ints(Festival.rest_ints())
	return t.save()


## The save as the previous version wrote it: undoes the step from version v - 1 to v. Only valid
## while the new state is at its defaults (no charred rooms, no life events, everyone at the
## starting mood), as in the tower above.
static func _reverse(data: Dictionary, v: int) -> Dictionary:
	var out: Dictionary = data.duplicate(true)
	match v:
		41:
			var rooms: Array = out["rooms"]
			rooms.resize(rooms.size() - 1)
		42:
			out.erase("mood")
			var people: Array = out["people"]
			var old: Array = people.slice(0, Migration.PEOPLE_HEADER)
			for n in people[2]:
				var at: int = Migration.PEOPLE_HEADER + n * (Migration.PEOPLE_OLD_FIELDS + 2)
				old.append_array(people.slice(at, at + Migration.PEOPLE_OLD_FIELDS))
			out["people"] = old
		43:
			out.erase("life")
			var mood: Array = out["mood"]
			mood.resize(1)  # v42 had the shock alone
		44:
			var commerce: Array = out["commerce"]
			commerce.resize(commerce.size() - 1)
		45:
			var fire: Array = out["fire"]
			fire.resize(fire.size() - 1)
		46:
			var vip: Array = out["vip"]
			vip.resize(vip.size() - 3)
		47:
			out.erase("weather")
		48:
			var vip48: Array = out["vip"]
			vip48.resize(vip48.size() - 3)
		49:
			out.erase("pipe")
			out.erase("stall")
			out.erase("festival")
		50:
			out.erase("wedding")
		51:
			out.erase("cheated")
		52:
			out.erase("theatre")
		53:
			out.erase("difficulty")
		54:
			pass  # no layout change: the bowling alley and arcade append catalogue ids (#324)
	out["version"] = v - 1
	return out


## The current save taken back to version down_to.
static func _older(data: Dictionary, down_to: int) -> Dictionary:
	var out := data
	for v in range(TowerSim.SAVE_VERSION, down_to, -1):
		out = _reverse(out, v)
	return out


static func run(check: Callable) -> void:
	# The rule: a bump without a step fails here. Every version from MIN_VERSION has a step up.
	check.call(Migration.can_migrate(Migration.MIN_VERSION, TowerSim.SAVE_VERSION), "migration: every version from %d up to SAVE_VERSION %d has a step (add one to save_migration.gd when bumping)" % [Migration.MIN_VERSION, TowerSim.SAVE_VERSION])
	check.call(Migration.upgrade_step(TowerSim.SAVE_VERSION, {"version": TowerSim.SAVE_VERSION}).is_empty(), "migration: there is no step from the current version")
	check.call(not Migration.can_migrate(Migration.MIN_VERSION - 1, TowerSim.SAVE_VERSION), "migration: a version below the oldest supported is refused")
	check.call(not Migration.can_migrate(TowerSim.SAVE_VERSION + 1, TowerSim.SAVE_VERSION), "migration: a newer save is refused")

	var current := _current()
	var original := TowerSim.new(0)
	check.call(original.load_state(current), "migration: the current save loads")
	var hash_now := original.state_hash()
	check.call(original.people.count() > 0, "migration: the test tower has people")

	# One test per step: the old save, taken one step forward, is the next version's save exactly.
	for v in range(Migration.MIN_VERSION, TowerSim.SAVE_VERSION):
		var old := _older(current, v)
		var want := _older(current, v + 1)
		var got := Migration.upgrade_step(v, old)
		check.call(old["version"] == v, "migration: the test save for v%d has that version" % v)
		check.call(got == want, "migration: step v%d -> v%d gives the v%d save" % [v, v + 1, v + 1])

	# Each old version migrates all the way, loads, and matches the tower it came from.
	for v in range(Migration.MIN_VERSION, TowerSim.SAVE_VERSION):
		var old := _older(current, v)
		var loaded := TowerSim.new(0)
		check.call(loaded.load_state(old), "migration: a v%d save loads" % v)
		check.call(old["version"] == v, "migration: loading a v%d save leaves it as it was" % v)
		check.call(loaded.tick == original.tick and loaded.ledger.balance == original.ledger.balance and loaded.rooms.room_ids().size() == original.rooms.room_ids().size() and loaded.people.count() == original.people.count(), "migration: a v%d save keeps tick, money, rooms and people" % v)
		check.call(loaded.state_hash() == hash_now, "migration: a v%d save loads to the same state hash" % v)

	# A refused version changes nothing.
	var untouched := TowerSim.new(5)
	var before := untouched.state_hash()
	var too_old := _older(current, Migration.MIN_VERSION)
	too_old["version"] = Migration.MIN_VERSION - 1
	check.call(not untouched.load_state(too_old) and untouched.state_hash() == before, "migration: a save below the oldest step is refused and changes nothing")
	var damaged := _older(current, 41)
	var people: Array = damaged["people"]
	people.append(0)
	check.call(not TowerSim.new(0).load_state(damaged), "migration: a save with a damaged people list is refused")
