extends RefCounted
## The sound tables, the mixing helpers and the silent path (#247), headless. No audio file is needed:
## the game must run with none.

const Catalog := preload("res://scripts/view/sound/sound_catalog.gd")
const Mixer := preload("res://scripts/view/sound/sound_mixer.gd")
const System := preload("res://scripts/view/sound/sound_system.gd")
const RoomCatalogue := preload("res://scripts/sim/room_catalogue.gd")
const MessagesScript := preload("res://scripts/sim/messages.gd")


static func run(check: Callable) -> void:
	_tables(check)
	_mixing(check)
	_messages(check)
	_silent(check)


static func _tables(check: Callable) -> void:
	check.call(Catalog.AMBIENCE_NAMES.size() == 35 and Catalog.EVENT_NAMES.size() == 23, "58 known sound names")
	var seen: Dictionary = {}
	for sound_name in Catalog.all_names():
		check.call(not seen.has(sound_name), "sound name %s is listed once" % sound_name)
		seen[sound_name] = true
	# Everything the tables point at is a known name.
	var used: Dictionary = {}
	var constants: Dictionary = (MessagesScript as GDScript).get_script_constant_map()
	var codes: Array = constants.values()
	for code: int in Catalog.MESSAGE_SOUNDS:
		var row: Array = Catalog.MESSAGE_SOUNDS[code]
		check.call(code in codes, "message code %d exists in Messages" % code)
		check.call(row[0] in Catalog.BUSES, "message %d plays on a known bus" % code)
		check.call(not (row[1] as Array).is_empty(), "message %d has a clip" % code)
		for clip: String in row[1]:
			used[clip] = true
	for group: Array in [Catalog.THEATER_CLIPS, Catalog.BUILD_CLIPS, Catalog.REFUSED_CLIPS, Catalog.RESCUE_CLIPS,
			Catalog.ELEVATOR_OPEN_CLIPS, Catalog.BIRD_CLIPS, Catalog.CROWD_CLIPS, Catalog.SUBWAY_CLIPS, Catalog.CAR_CLIPS]:
		for clip: String in group:
			used[clip] = true
	for kind: String in Catalog.KIND_LOOPS:
		check.call(kind in RoomCatalogue.IDS, "ambience kind %s is a catalogue kind" % kind)
		used[Catalog.KIND_LOOPS[kind]] = true
	for single: String in [Catalog.BUY_CLIP, Catalog.OFFICE_CLIP, Catalog.CRICKET_LOOP, Catalog.FIRE_LOOP, Catalog.ELEVATOR_LOOP, "Intro", "Recycling"]:
		used[single] = true
	for kind: String in Catalog.OFFICE_KINDS + [Catalog.CONDO_KIND, Catalog.THEATER_KIND, Catalog.LOBBY_KIND, Catalog.RECYCLING_KIND]:
		check.call(kind in RoomCatalogue.IDS, "kind %s is a catalogue kind" % kind)
	for sound_name: String in used:
		check.call(Catalog.is_known(sound_name), "%s is a known sound name" % sound_name)
		check.call(not (sound_name in Catalog.UNMAPPED), "%s is used, so it is not listed unmapped" % sound_name)
	# The table is complete: every known name is used or openly listed as unmapped.
	for sound_name in Catalog.all_names():
		check.call(used.has(sound_name) or sound_name in Catalog.UNMAPPED, "%s is mapped or listed unmapped" % sound_name)
	for sound_name: String in Catalog.UNMAPPED:
		check.call(Catalog.is_known(sound_name), "unmapped %s is a known name" % sound_name)


static func _mixing(check: Callable) -> void:
	check.call(Mixer.zoom_factor(1) < Mixer.zoom_factor(4), "closer zoom is louder")
	check.call(Mixer.zoom_factor(6) == 1.0 and Mixer.zoom_factor(0) >= 0.3, "zoom factor is bounded")
	check.call(Mixer.level_for(0, 4) == 0.0, "no rooms in view is silent")
	check.call(Mixer.level_for(10, 3) < Mixer.level_for(40, 3), "more of a kind in view is louder")
	check.call(Mixer.level_for(10000, 6) == 1.0, "level is capped at 1")
	var levels: Dictionary = {"A": 0.9, "B": 0.5, "C": 0.7, "D": 0.6, "E": 0.8, "F": 0.001}
	var top := Mixer.strongest(levels)
	check.call(top.size() == Mixer.MAX_LOOPS, "at most %d ambience loops" % Mixer.MAX_LOOPS)
	check.call(top.has("A") and top.has("E") and top.has("C") and top.has("D") and not top.has("B"), "the strongest loops win")
	check.call(Mixer.strongest({"X": 0.5, "Y": 0.5, "Z": 0.5, "W": 0.5, "V": 0.5}).has("V"), "ties go to the earlier name")
	check.call(Mixer.strongest({}).is_empty(), "nothing in view, no loops")
	check.call(Mixer.approach(0.0, 1.0, 0.25) == 0.25 and Mixer.approach(0.9, 1.0, 0.25) == 1.0, "a fade rises and stops at its target")
	check.call(Mixer.approach(0.2, 0.0, 0.25) == 0.0, "a fade falls and stops at zero")


static func _messages(check: Callable) -> void:
	var log := Messages.new()
	log.add(5, MessagesScript.ROOM_BUILT, 1, 2)
	var first := Mixer.new_messages(log, -1, 0)
	check.call((first["entries"] as Array).size() == 1, "a fresh cursor sees the existing entry")
	var again := Mixer.new_messages(log, first["tick"], first["count"])
	check.call((again["entries"] as Array).is_empty(), "nothing is new the second time")
	log.add(5, MessagesScript.ROOM_REMOVED, 3, 4)
	log.add(6, MessagesScript.STAR_PROMOTED, 2, 0)
	var next := Mixer.new_messages(log, again["tick"], again["count"])
	var entries: Array = next["entries"]
	check.call(entries.size() == 2 and entries[0][1] == MessagesScript.ROOM_REMOVED and entries[1][1] == MessagesScript.STAR_PROMOTED, "a second entry in the same tick is not missed")
	var empty := Mixer.new_messages(Messages.new(), 99, 1)
	check.call((empty["entries"] as Array).is_empty(), "an empty record yields nothing")
	var short := Messages.new()
	short.add(1, MessagesScript.FLOOR_BUILT, 1, 0)
	var back := Mixer.new_messages(short, 99, 1)
	check.call((back["entries"] as Array).is_empty() and back["tick"] == 1, "a record that went back in time is skipped, not replayed")


static func _silent(check: Callable) -> void:
	check.call(Catalog.load_streams(["Z:/no/such/folder", "user://no_such_sounds"]).is_empty(), "missing folders load nothing, without an error")
	var local_at := -1
	var committed_at := -1
	var dirs := Catalog.search_dirs()
	for i in dirs.size():
		if dirs[i].ends_with("local_sounds") and local_at < 0:
			local_at = i
		if dirs[i].ends_with("assets/sounds"):
			committed_at = i
	check.call(local_at >= 0 and committed_at > local_at, "local_sounds is searched before assets/sounds")
	var driver := SimDriver.new()
	var system: Node = System.new()
	system.bind(driver, null, {}, false)
	check.call(not system.has_sounds(), "no sounds found means silent")
	for i in 5:
		system._process(1.0)  # must not crash or error
	check.call(not system.play_one(&"UI", "Build1"), "a missing sound plays nothing")
	system.free()
	driver.free()
