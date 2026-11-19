extends RefCounted
## Room looks (#155): each M6 kind has its own colour, hotel and shop states change the look, an
## infested room is marked, and reading the sim for drawing does not change it. The drawn shapes
## themselves are checked by eye with a capture (see the PR), since a headless run draws nothing.

const TowerSim := preload("res://scripts/sim/tower.gd")
const HotelScript := preload("res://scripts/sim/hotel.gd")
const RoomLook := preload("res://scripts/view/room_look.gd")
const TestPests := preload("res://tests/test_pests.gd")


static func run(check: Callable) -> void:
	var t := TestPests._tower()
	var kinds: Array[String] = RoomLook.KINDS
	var ids: Dictionary = {}
	var floor_number := 3
	for kind in kinds:  # one floor each, so no kind runs out of width
		t.floors.fill_span(floor_number, 100, 131)
		ids[kind] = TestPests._room(t, kind, floor_number, 100)
		floor_number += 1
	var colours: Dictionary = {}
	var all_placed := true
	for kind in kinds:
		all_placed = all_placed and int(ids[kind]) >= 0
		if int(ids[kind]) >= 0:
			colours[(RoomLook.describe(t, ids[kind])["color"] as Color).to_html()] = kind
	check.call(all_placed, "room look: every M6 kind can be placed for the test")
	check.call(colours.size() == kinds.size(), "room look: each M6 kind has its own colour")

	var before := t.state_hash()
	var room: int = ids["hotel_single"]
	TestPests._clean(t, room)
	var clean := RoomLook.describe(t, room)
	check.call(clean["state"] == RoomLook.CLEAN, "room look: a vacant clean hotel room reads clean")
	TestPests._dirty(t, room, 5)
	var dirty := RoomLook.describe(t, room)
	check.call(dirty["state"] == RoomLook.DIRTY and dirty["color"] != clean["color"], "room look: a dirty room looks different from a clean one")
	t.hotel._records[room] = [HotelScript.STAYING, 0, -1, 420, 0, 0, -1, 0] as Array[int]
	var occupied := RoomLook.describe(t, room)
	check.call(occupied["state"] == RoomLook.OCCUPIED and occupied["color"] != clean["color"] and occupied["color"] != dirty["color"], "room look: an occupied room looks different from clean and dirty")
	t.pests._infested.append(room)
	check.call(RoomLook.describe(t, room)["state"] == RoomLook.INFESTED, "room look: an infested room is marked infested, ahead of occupied")
	t.pests._infested.erase(room)
	check.call(RoomLook.describe(t, room)["state"] == RoomLook.OCCUPIED, "room look: the infested mark goes when the pests do")

	var shop: int = ids["retail"]
	check.call(RoomLook.describe(t, shop)["state"] == RoomLook.LEASED, "room look: a leased shop reads leased")
	t.commerce._vacant[shop] = 0
	var vacant := RoomLook.describe(t, shop)
	check.call(vacant["state"] == RoomLook.VACANT and vacant["color"] != RoomLook.RETAIL_COLOR, "room look: a vacant shop looks different from a leased one")
	t.commerce._vacant.erase(shop)

	for kind in ["housekeeping", "fast_food", "restaurant"]:
		check.call(RoomLook.describe(t, ids[kind])["state"] == RoomLook.OPEN, "room look: %s has a single look" % kind)
	check.call(not RoomLook.handles("office") and RoomLook.handles("retail"), "room look: only the M6 kinds use it")
	t.hotel._records.erase(room)
	check.call(t.state_hash() == before, "room look: reading the looks leaves the sim hash unchanged")
