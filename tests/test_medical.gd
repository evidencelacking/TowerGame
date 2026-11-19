extends RefCounted
## Medical centre (7.5, #170): placeable at 3 stars, cannot be bulldozed, one centre serves
## 20 offices (owner ruling); the demand rises with offices, clears when enough centres exist
## and re-raises when offices outgrow them.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Msg := preload("res://scripts/sim/messages.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const D := preload("res://scripts/sim/demands.gd")


static func _kinds(offices: int, medical: int) -> Dictionary:
	return {"office": offices, "medical": medical}


static func run(check: Callable) -> void:
	var all: Array[String] = ["office", "medical"]
	var raised := 1 << (D.MEDICAL - 1)
	check.call(Rooms.PLACEABLE.has("medical"), "medical is placeable")
	check.call(D.OFFICES_PER_MEDICAL == 20, "one centre serves 20 offices (owner ruling)")
	check.call(D.compute(3, _kinds(0, 0), all) & raised == 0, "no offices: no medical demand")
	check.call(D.compute(2, _kinds(5, 0), all) & raised == 0, "no medical demand before 3 stars")
	check.call(D.compute(3, _kinds(1, 0), all) & raised != 0, "an office without medical raises the demand")
	check.call(D.compute(3, _kinds(20, 1), all) & raised == 0, "one centre serves 20 offices")
	check.call(D.compute(3, _kinds(21, 1), all) & raised != 0, "a 21st office needs a second centre")
	check.call(D.compute(3, _kinds(40, 2), all) & raised == 0 and D.compute(3, _kinds(41, 2), all) & raised != 0, "two centres serve 40")

	# On a tower: built through the real rules, message logged once and cleared once.
	var t := TowerSim.new(5, 1000000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	t.floors.fill_span(3, 100, 163)
	var cat := Catalogue.IDS
	check.call(t.rooms.place_room(t.grid, t.floors, t.ledger, 0, cat.find("office"), 3, 100) == Rooms.OK, "fixture: an office")
	t.stars = 3
	t.promote_stars()
	check.call(t.demands.is_open(D.MEDICAL), "office at 3 stars: the tower needs medical care")
	check.call(t.rooms.place_room(t.grid, t.floors, t.ledger, 0, cat.find("medical"), 3, 120) == Rooms.OK, "a medical centre places for $500,000")
	t.promote_stars()
	check.call(not t.demands.is_open(D.MEDICAL), "the centre clears the demand")
	var n_raised := 0
	var n_cleared := 0
	for i in t.messages.count():
		var e := t.messages.entry(i)
		if e[2] == D.MEDICAL and e[1] == Msg.DEMAND_RAISED:
			n_raised += 1
		elif e[2] == D.MEDICAL and e[1] == Msg.DEMAND_CLEARED:
			n_cleared += 1
	check.call(n_raised == 1 and n_cleared == 1, "raised once and cleared once")

	# Cannot be bulldozed.
	t.tick = 20
	t.enqueue(TowerSim.Command.make(21, TowerSim.Command.BULLDOZE, [3, 120] as Array[int]))
	t.step()
	t.step()
	var left := 0
	for id in t.rooms.room_ids():
		if t.rooms.kind_of(id) == "medical":
			left += 1
	check.call(left == 1, "a medical centre cannot be bulldozed")
