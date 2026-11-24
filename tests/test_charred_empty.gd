extends RefCounted
## A burned-out room is empty (#486): charring clears every kind's residents and workers, nothing moves into it
## while it stands charred (daily fills, retirees staying on), and a save that holds a resident in one clears them on load.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const People := preload("res://scripts/sim/people.gd")
const Names := preload("res://scripts/sim/names.gd")

const DAY_TICKS := 2550


static func _tower(kinds: Array) -> TowerSim:
	var t := TowerSim.new(42, 100000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	for f in range(3, 12):
		t.floors.fill_span(f, 100, 163)
	var floor_number := 3  # one kind to a floor, clear of the shaft at x 100
	for kind: String in kinds:
		var code: int = t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find(kind), floor_number, 110)
		assert(code == 0, "%s places (%d)" % [kind, code])
		floor_number += 1
	t.rooms.place_shaft(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("local_shaft"), 1, 11, 100)
	t.rooms.add_car(t.ledger, 0, 3, t.rooms._shaft_base(t.rooms.link_at(1, 100)), 1)
	t.step()
	return t


static func _room(t: TowerSim, kind: String) -> int:
	for id in t.rooms.room_ids():
		if t.rooms.kind_of(id) == kind:
			return id
	return -1


static func _occupants(t: TowerSim, id: int) -> int:
	return t.people.homes_in(id) + t.people.workers_in(id)


static func run(check: Callable) -> void:
	var kinds: Array = ["office", "condo", "apartment", "studio", "assisted", "hotel_single", "hotel_twin", "hotel_suite"]
	# Every kind with homes or workers: fill it, char it, and it is empty.
	for kind: String in kinds:
		var t := _tower([kind])
		var id := _room(t, kind)
		var seats: int = t.rooms.people_in(id)
		t.people.remove_room(id)  # whoever the first tick moved in
		for n in seats:
			if kind == "office":
				t.people.add_person(People.NONE, id, t.rng)
			else:
				t.people.add_person(id, People.NONE, t.rng)
		check.call(_occupants(t, id) == seats, "%s: filled before the fire" % kind)
		t.rooms.charred[id] = true
		t.char_room(id)
		check.call(_occupants(t, id) == 0, "%s: charring leaves no resident or worker" % kind)

	# Over a few days nobody moves into a charred room, whatever its kind.
	var all := _tower(kinds)
	var ids: Array[int] = []
	for id in all.rooms.room_ids():
		if kinds.has(all.rooms.kind_of(id)):
			ids.append(id)
			all.rooms.charred[id] = true
			all.char_room(id)
	for n in 4 * DAY_TICKS:
		all.step()
	var leaked := 0
	for id in ids:
		leaked += _occupants(all, id)
	check.call(leaked == 0, "no one moves into a charred room over four days (%d did)" % leaked)

	# A retiring senior with no other place does not stay on in a charred assisted-living room.
	var s := _tower(["office", "assisted"])
	var home := _room(s, "assisted")
	s.rooms.charred[home] = true
	s.char_room(home)
	s.life.retire_per_100000 = 100000
	s.life.retire_stay_percent = 100
	var office := _room(s, "office")
	var guard := 0
	while Names.age_band(s.names.name_seed, s.people.next_id()) != Names.BAND_SENIOR and guard < 64:
		s.people.skip_id()
		guard += 1
	s.people.add_person(People.NONE, office, s.rng)
	s.life.retire(s)
	check.call(s.people.homes_in(home) == 0, "a retiree does not stay on in a charred assisted-living room")

	# An older save holding a resident in a charred room clears them on load.
	var old := _tower(["assisted"])
	var room := _room(old, "assisted")
	old.people.add_person(room, People.NONE, old.rng)
	old.rooms.charred[room] = true
	var data := old.save()
	var loaded := TowerSim.new(1, 0)
	check.call(loaded.load_state(data) and loaded.people.homes_in(room) == 0, "a saved resident of a charred room is cleared on load")
