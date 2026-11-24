extends RefCounted
## A view kept through a build and a bulldoze equals one made fresh afterwards (#458). The renderer and the people
## view keep their pieces, runs and per-person reads between layout changes and rework only what the change
## touched; after each change this compares them with a second renderer set up on the same tower: the same room
## pieces, runs and floor rects, the same figures in the same order, and the same rooms in use and asleep.
## Each comparison first asserts its own inputs (the command was accepted, the layout revision moved, rooms were
## compared), so a test that compared nothing would fail.

const Mixed := preload("res://tools/bench_mixed.gd")
const Command := preload("res://scripts/sim/tower.gd").Command
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const PeopleView := preload("res://scripts/view/people_view.gd")
const VC := preload("res://scripts/view/view_consts.gd")
const TestRooms := preload("res://tests/test_rooms.gd")

const FRAME := 1.0 / 60.0
const WARM_TICKS := 700  ## Ticks before the first look, so people are up and about.
const EMPTY_FLOOR := 20  ## A built floor with room to spare at the right of the rooms.
const EMPTY_COLUMN := 330


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func _view(tower: Tower) -> Array:
	var renderer := TowerRenderer.new()
	var camera := Camera2D.new()
	_tree().root.add_child(renderer)
	_tree().root.add_child(camera)
	await _tree().process_frame  # _ready runs
	renderer.set_tower(tower)
	camera.position = Vector2(100 * VC.CELL_W, VC.floor_to_row(12) * VC.CELL_H)
	camera.zoom = Vector2(0.2, 0.2)
	camera.make_current()
	return [renderer, camera]


static func _stop(pair: Array) -> void:
	(pair[0] as Node).queue_free()
	(pair[1] as Node).queue_free()
	await _tree().process_frame


## Where two views differ, or "" when they match.
static func _difference(kept: TowerRenderer, fresh: TowerRenderer) -> String:
	if kept._floor_rects != fresh._floor_rects:
		return "floor rects"
	if kept._room_runs != fresh._room_runs:
		return "room runs"
	if kept._link_runs != fresh._link_runs:
		return "link runs"
	if kept._room_pieces.size() != fresh._room_pieces.size():
		return "piece count %d against %d" % [kept._room_pieces.size(), fresh._room_pieces.size()]
	for key: Variant in fresh._room_pieces:
		if not kept._room_pieces.has(key):
			return "missing piece %s" % key
		var a: TowerRenderer.Piece = kept._room_pieces[key]
		var b: TowerRenderer.Piece = fresh._room_pieces[key]
		if a.rect != b.rect or a.runs != b.runs or a.suite_kind != b.suite_kind:
			return "piece %s" % key
	if kept._figures != fresh._figures:
		return "figures (%d against %d)" % [kept._figures.size(), fresh._figures.size()]
	if kept._people_view.in_use != fresh._people_view.in_use or kept._people_view.asleep != fresh._people_view.asleep:
		return "rooms in use or asleep"
	return ""


## An office with someone resting in it, found in the runs: [floor, left column, kind index]; empty when none.
static func _busy_office(tower: Tower, renderer: TowerRenderer) -> Array[int]:
	var office := CatalogueScript.IDS.find("office")
	for run: Array in renderer._room_runs:
		if tower.rooms.kind_of(run[0]) != "office" or not renderer._people_view.in_use.has(run[1]):
			continue
		var at: Array[int] = tower.grid.run_of(run[0])
		return [at[0], at[1], office]
	return []


static func run(check: Callable) -> void:
	var tower := Mixed.build(42)
	for _i in WARM_TICKS:
		tower.step()
	var pair := await _view(tower)
	var kept: TowerRenderer = pair[0]
	for _i in 4:
		kept._process(FRAME)
	var target := _busy_office(tower, kept)
	check.call(not target.is_empty() and kept._figures.size() > 100, "layout incremental: the fixture has people about and an office in use to bulldoze")
	if target.is_empty():
		await _stop(pair)
		return
	var steps: Array[Array] = [
		["bulldoze", Command.BULLDOZE, [target[0], target[1]] as Array[int]],
		["build", Command.PLACE_ROOM, [target[2], target[0], target[1]] as Array[int]],
		["build elsewhere", Command.PLACE_ROOM, [target[2], EMPTY_FLOOR, EMPTY_COLUMN] as Array[int]],
		["bulldoze that", Command.BULLDOZE, [EMPTY_FLOOR, EMPTY_COLUMN] as Array[int]],
	]
	for step: Array in steps:
		var revision := tower.floors.revision
		var cells := tower.grid.occupant_count()
		var refused := TestRooms._send(tower, step[1], step[2])
		check.call(refused == 0 and (tower.floors.revision != revision or tower.grid.occupant_count() != cells), "layout incremental: %s is accepted and changes the layout" % step[0])
		var pieces_before := kept._room_pieces.size()
		kept._process(FRAME)
		kept._process(FRAME)
		var other := await _view(tower)
		var fresh: TowerRenderer = other[0]
		fresh._process(FRAME)
		fresh._process(FRAME)
		var diff := _difference(kept, fresh)
		check.call(diff == "", "layout incremental: after %s the kept view equals a fresh one (differs in: %s)" % [step[0], diff])
		var stale_reads := 0
		for seen: PeopleView.Seen in kept._people_view._seen.values():
			if seen.room >= 0 and tower.grid.run_of(seen.room) != seen.run:
				stale_reads += 1
		check.call(stale_reads == 0, "layout incremental: after %s no kept read of a person's room is out of date (%d are)" % [step[0], stale_reads])
		check.call(not fresh._room_pieces.is_empty() and kept._room_pieces.size() > pieces_before - 3, "layout incremental: after %s the views hold room pieces" % step[0])
		await _stop(other)
	await _stop(pair)
