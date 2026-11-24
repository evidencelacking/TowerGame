extends RefCounted
## Bulk rent (#28): SET_RENT_MANY equals N single SET_RENT commands, skips condos and unknown rooms
## and counts them, saves; the panel scopes, mixed counts, and the whole-tower confirm gate the command.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Rent := preload("res://scripts/sim/rent.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const TestCondos := preload("res://tests/test_condos.gd")


## A tower with a condo (x 110 to 125) and three offices on floor 3, and one more office on floor 4.
static func _tower() -> TowerSim:
	var t := TestCondos._tower()
	t.floors.fill_span(3, 132, 160)
	t.floors.fill_span(4, 100, 160)
	var office := Catalogue.IDS.find("office")
	for x in [100, 126, 135]:
		t.rooms.place_room(t.grid, t.floors, t.ledger, 0, office, 3, x)
	t.rooms.place_room(t.grid, t.floors, t.ledger, 0, office, 4, 100)
	return t


static func _ids(t: TowerSim, kind: String) -> Array[int]:
	var out: Array[int] = []
	for id in t.rooms.room_ids():
		if t.rooms.kind_of(id) == kind:
			out.append(id)
	return out


static func _many(t: TowerSim, level: int, ids: Array[int]) -> void:
	var args: Array[int] = [level]
	args.append_array(ids)
	t.enqueue(TowerSim.Command.make(t.tick + 1, TowerSim.Command.SET_RENT_MANY, args))
	t.step()


static func run(check: Callable) -> void:
	var bulk := _tower()
	var singles := _tower()
	var offices := _ids(bulk, "office")
	check.call(offices.size() == 4 and _ids(bulk, "condo").size() == 1, "fixture: four offices and a condo")
	# Bulk equals N singles (given out of order, with a duplicate): same state hash.
	var shuffled: Array[int] = [offices[2], offices[0], offices[3], offices[0]]
	_many(bulk, Rent.LEVEL_LOW, shuffled)
	for id in [offices[0], offices[2], offices[3]]:
		singles.enqueue(TowerSim.Command.make(singles.tick + 1, TowerSim.Command.SET_RENT, [id, Rent.LEVEL_LOW] as Array[int]))
	singles.step()
	check.call(bulk.state_hash() == singles.state_hash(), "a bulk call equals N single SET_RENT commands (same state hash)")
	check.call(bulk.rent_level(offices[0]) == Rent.LEVEL_LOW and bulk.rent_level(offices[1]) == Rent.DEFAULT_LEVEL, "only the listed rooms changed")
	check.call(bulk.last_bulk_rent[0] == 3 and bulk.last_bulk_rent[1] == 0, "three set, none skipped")
	# Condos, unknown rooms and a bad level are skipped and counted, not an error.
	var condo := _ids(bulk, "condo")[0]
	var mixed: Array[int] = [offices[1], condo, 99999]
	_many(bulk, Rent.LEVEL_HIGH, mixed)
	check.call(bulk.last_bulk_rent[0] == 1 and bulk.last_bulk_rent[1] == 2, "a condo and an unknown room are skipped and counted")
	check.call(bulk.rent_level(offices[1]) == Rent.LEVEL_HIGH and bulk.rent_level(condo) == Rent.DEFAULT_LEVEL and bulk.last_refusal == 0, "the rest still applied and nothing was refused")
	_many(bulk, 9, offices)
	check.call(bulk.last_bulk_rent[0] == 0 and bulk.last_bulk_rent[1] == 4, "a bad level skips every room")
	# Saves keep the levels.
	var other := TowerSim.new(7, 100000000)
	check.call(other.load_state(bulk.save()) and other.state_hash() == bulk.state_hash() and other.rent_level(offices[0]) == Rent.LEVEL_LOW, "bulk-set levels survive a save round trip")

	await _panel(check)


static func _panel(check: Callable) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var t := _tower()
	var offices := _ids(t, "office")
	var condo := _ids(t, "condo")[0]
	var panel := BulkRent.new()
	tree.root.add_child(panel)
	panel.bind(t, null)
	panel.open(offices[0])
	# Floor scope: the three floor-3 offices (the condo has no rent levels and is left out).
	panel.set_scope(BulkRent.Scope.FLOOR)
	var floor_three: Array[int] = [offices[0], offices[1], offices[2]]
	check.call(panel.target_ids() == floor_three, "floor scope: every rentable room on the clicked room's floor")
	panel.set_scope(BulkRent.Scope.TYPE)
	check.call(panel.target_ids() == offices, "type scope: every room of the clicked room's type in the tower")
	# Mixed counts.
	t.rent.set_rent(t.rooms, offices[0], Rent.LEVEL_GREEN)
	t.rent.set_rent(t.rooms, offices[1], Rent.LEVEL_GREEN)
	check.call(panel.summary_text() == "2 low, 2 average", "mixed selection shows a count per level: " + panel.summary_text())
	# A dragged rectangle over floor 3 takes in the condo, which is flagged as unable to change.
	panel.select_rect(Vector2i(3, 100), Vector2i(3, 160))
	check.call(panel.selection.has(condo) and panel.summary_text().ends_with("(1 cannot change)"), "selection includes a condo, flagged as unable to change: " + panel.summary_text())
	# Selection scope applies at once; the report counts the skip.
	(panel.find_child("Level3", true, false) as Button).pressed.emit()
	t.step()
	panel._process(0.0)
	check.call(t.rent_level(offices[0]) == Rent.LEVEL_HIGH and t.rent_level(offices[3]) == Rent.DEFAULT_LEVEL, "the dragged selection applied, and only it")
	check.call(panel.status.text == "Rent set for 3 rooms, 1 skipped", "the report counts changed and skipped: " + panel.status.text)
	# Whole tower waits for the confirm: nothing changes until Yes.
	panel.set_scope(BulkRent.Scope.TOWER)
	(panel.find_child("Level0", true, false) as Button).pressed.emit()
	t.step()
	check.call(panel.confirm_box.visible and panel.confirm_text.text == "Set rent for 4 rooms across the tower?", "whole tower: asks first: " + panel.confirm_text.text)
	check.call(t.rent_level(offices[3]) == Rent.DEFAULT_LEVEL and t.rent_level(offices[0]) == Rent.LEVEL_HIGH, "whole tower: nothing changes before the answer")
	(panel.find_child("ConfirmNo", true, false) as Button).pressed.emit()
	t.step()
	check.call(not panel.confirm_box.visible and t.rent_level(offices[3]) == Rent.DEFAULT_LEVEL, "cancel sends nothing")
	(panel.find_child("Level0", true, false) as Button).pressed.emit()
	(panel.find_child("ConfirmYes", true, false) as Button).pressed.emit()
	t.step()
	check.call(t.rent_level(offices[3]) == Rent.LEVEL_LOW and t.rent_level(offices[0]) == Rent.LEVEL_LOW, "confirming applies to every rentable room")
	panel.queue_free()
