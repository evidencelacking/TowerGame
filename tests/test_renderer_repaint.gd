extends RefCounted
## The renderer draws what the player just did within a frame or two, however much background repaint is
## queued (#372), and a resized shaft is drawn over its whole new span (#365). It drives a real renderer in
## the scene tree, frame by frame, with a camera that sees the whole tower.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const ElevatorView := preload("res://scripts/view/elevator_view.gd")
const VC := preload("res://scripts/view/view_consts.gd")
const TransportGlass := preload("res://scripts/view/transport_glass.gd")
const TestRooms := preload("res://tests/test_rooms.gd")
const TestShafts := preload("res://tests/test_shafts.gd")

const SETTLE_LIMIT: int = 600  ## Frames a drain may take before the test calls it stuck.
const NEW_ROOM_FRAMES: int = 3  ## A placed room must be painted and rendered within this many frames.


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## Waits for the renderer's backlog to drain. Returns the frames it took, or -1 when it never did.
static func _settle(renderer: TowerRenderer) -> int:
	for frame: int in SETTLE_LIMIT:
		await _tree().process_frame
		if frame > 2 and renderer.pending_work() == 0:
			return frame
	return -1


static func _rect_of(shaft: Dictionary) -> Rect2i:
	var top_row := VC.floor_to_row(shaft["top"])
	var bottom_row := VC.floor_to_row(shaft["bottom"])
	return Rect2i((shaft["x"] as int) * VC.CELL_W, top_row * VC.CELL_H, (shaft["width"] as int) * VC.CELL_W, (bottom_row - top_row + 1) * VC.CELL_H)


## Every tile that is not waiting was rendered after every piece that touches it was last repainted.
static func _tiles_are_current(renderer: TowerRenderer) -> bool:
	for tile: TowerRenderer.Tile in renderer._tiles:
		if tile.pending:
			continue
		var pieces: Array[TowerRenderer.Piece] = renderer._frame_pieces.duplicate()
		for key: Variant in renderer._room_pieces:
			pieces.append(renderer._room_pieces[key] as TowerRenderer.Piece)
		for piece: TowerRenderer.Piece in pieces:
			if piece.rect.grow(TowerRenderer.TILE_PAD).intersects(tile.rect) and tile.rendered_frame < piece.painted_frame:
				return false
	return true


static func _start(tower: TowerSim) -> Array:
	var renderer := TowerRenderer.new()
	var camera := Camera2D.new()
	_tree().root.add_child(renderer)
	_tree().root.add_child(camera)
	await _tree().process_frame  # _ready runs
	renderer.set_tower(tower)
	camera.position = Vector2(115 * VC.CELL_W, VC.floor_to_row(25) * VC.CELL_H)
	camera.zoom = Vector2(0.2, 0.2)  # the whole tower is on screen
	camera.make_current()
	return [renderer, camera]


static func _stop(pair: Array) -> void:
	(pair[0] as Node).queue_free()
	(pair[1] as Node).queue_free()
	await _tree().process_frame


static func run(check: Callable) -> void:
	await _placed_room(check)
	await _extended_shaft(check)
	await _bulldozed_room(check)
	await _transport_glass_key(check)
	_cursor(check)


## A room placed while a big repaint is queued is painted and rendered first.
static func _placed_room(check: Callable) -> void:
	var tower := TestShafts._tall()
	var office := CatalogueScript.IDS.find("office")
	for floor_number in range(2, 30):
		TestRooms._room(tower, office, floor_number, 100)
		TestRooms._room(tower, office, floor_number, 110)
	var pair := await _start(tower)
	var renderer: TowerRenderer = pair[0]
	check.call(await _settle(renderer) >= 0, "the renderer settles on a built tower")
	renderer._mark_all_stale()  # a palette or style change: every piece and tile is queued
	renderer._mark_tiles(renderer._canvas)
	var before: Array = renderer._room_pieces.keys()
	await _tree().process_frame
	check.call(TestRooms._room(tower, office, 32, 100) == 0, "the new office is placed")
	var drawn := -1
	var work_left := 0
	for frame in NEW_ROOM_FRAMES + 3:
		await _tree().process_frame
		var fresh: TowerRenderer.Piece = null
		for key: Variant in renderer._room_pieces:
			if not before.has(key):
				fresh = renderer._room_pieces[key]
		if fresh == null or fresh.stale:
			continue
		var waiting := 0
		for tile: TowerRenderer.Tile in renderer._tiles:
			if tile.pending and tile.rect.intersects(fresh.rect.grow(TowerRenderer.TILE_PAD)):
				waiting += 1
		if waiting == 0:
			drawn = frame + 1
			work_left = renderer.pending_work()
			break
	check.call(drawn > 0 and drawn <= NEW_ROOM_FRAMES, "a placed room is repainted and rendered within %d frames (took %d)" % [NEW_ROOM_FRAMES, drawn])
	check.call(work_left > 0, "the background repaint was still queued, so the new room really went first")
	check.call(await _settle(renderer) >= 0, "the background repaint drains")
	check.call(_tiles_are_current(renderer), "every tile was rendered after the pieces on it were last repainted")
	await _stop(pair)


## A shaft extended past the built tower is drawn over its whole new span.
static func _extended_shaft(check: Callable) -> void:
	var tower := TestShafts._tall()
	TestShafts._shaft(tower, 21, 25, 100)
	var pair := await _start(tower)
	var renderer: TowerRenderer = pair[0]
	check.call(await _settle(renderer) >= 0, "the renderer settles with a short shaft")
	var id: int = tower.rooms._shaft_base(tower.rooms.link_at(21, 100))
	var grown := renderer._canvas
	check.call(TestRooms._send(tower, Command.RESIZE_SHAFT, [id, 21, 50] as Array[int]) == 0, "the shaft is extended above the built floors")
	check.call(await _settle(renderer) >= 0, "the renderer settles after the extension")
	check.call(renderer._canvas != grown, "the canvas grew with the shaft")
	var shaft: Dictionary = ElevatorView.shafts(tower)[0]
	check.call(shaft["bottom"] == 21 and shaft["top"] == 50, "the shaft's span is the new one")
	var want := _rect_of(shaft)
	check.call(Rect2i(renderer._canvas).encloses(want), "the canvas covers the extended shaft")
	check.call(renderer._seen_shafts.size() == 1 and renderer._seen_shafts.values()[0] == want, "the renderer drew the shaft over its new span")
	var floors_now := renderer._floor_rects.duplicate()
	var rooms_now := renderer._room_runs.duplicate()
	var links_now := renderer._link_runs.duplicate()
	renderer._row_cache.clear()  # a from-scratch scan must find what the incremental one kept (#349)
	renderer._rebuild_runs()
	check.call(floors_now == renderer._floor_rects and rooms_now == renderer._room_runs and links_now == renderer._link_runs, "the incremental run scan matches a full one after the layout changed")
	var all_framed := true
	for piece: TowerRenderer.Piece in renderer._frame_pieces:
		all_framed = all_framed and piece.rect == renderer._canvas and not piece.stale
	check.call(all_framed, "the frame pieces cover the grown canvas and are repainted")
	check.call(_tiles_are_current(renderer), "no tile of the extended shaft was rendered before its repaint")
	var covered := true
	for tile: TowerRenderer.Tile in renderer._tiles:
		if tile.rect.intersects(want):
			covered = covered and not tile.pending
	check.call(covered, "every tile the extended shaft crosses is rendered")
	await _stop(pair)


## The see-through transport key (#367) flips the option and every frame piece is repainted after it.
static func _transport_glass_key(check: Callable) -> void:
	var tower := TestShafts._tall()
	TestShafts._shaft(tower, 21, 25, 100)
	var pair := await _start(tower)
	var renderer: TowerRenderer = pair[0]
	check.call(await _settle(renderer) >= 0, "the renderer settles before the glass key")
	var was := TransportGlass.on
	for piece: TowerRenderer.Piece in renderer._frame_pieces:
		piece.cost_us = -1  # _paint_frame_piece sets it, so a repainted piece loses the marker
	var key := InputEventKey.new()
	key.keycode = KeyBindings.keycode("transport_glass") as Key
	key.pressed = true
	renderer._unhandled_key_input(key)
	check.call(TransportGlass.on != was, "the bound key flips the see-through transport option")
	check.call(await _settle(renderer) >= 0, "the renderer settles after the glass key")
	var repainted := not renderer._frame_pieces.is_empty()
	for piece: TowerRenderer.Piece in renderer._frame_pieces:
		repainted = repainted and piece.cost_us >= 0 and not piece.stale
	check.call(repainted, "every frame piece is repainted after the option changed")
	check.call(_tiles_are_current(renderer), "no tile was rendered before its pieces were repainted after the option changed")
	TransportGlass.set_on(was)
	await _stop(pair)


## A bulldozed room's piece is gone and cannot paint, even when a redraw was queued and the renderer ran twice
## with no engine frame between (the node waits for deletion until the frame ends).
static func _bulldozed_room(check: Callable) -> void:
	var tower := TestShafts._tall()
	var office := CatalogueScript.IDS.find("office")
	TestRooms._room(tower, office, 2, 100)
	TestRooms._room(tower, office, 2, 110)
	var pair := await _start(tower)
	var renderer: TowerRenderer = pair[0]
	check.call(await _settle(renderer) >= 0, "the renderer settles before the bulldoze")
	var doomed: int = tower.grid.cell_at(2, 100)
	check.call(doomed != 0 and renderer._room_pieces.size() > 0, "the office to bulldoze has a piece")
	for piece: TowerRenderer.Piece in renderer._room_pieces.values():
		piece.node.queue_redraw()  # a redraw is pending on every piece, the doomed one included
	var rooms_before := renderer._room_pieces.size()
	TestRooms._send(tower, Command.BULLDOZE, [2, 100] as Array[int])
	tower.step()
	renderer._process(1.0 / 60.0)
	renderer._process(1.0 / 60.0)  # no engine frame in between
	check.call(not tower.grid.has_occupant(doomed), "the office is gone from the grid")
	check.call(renderer._room_pieces.size() == rooms_before - 1, "no piece is left for the removed room")
	var waiting := 0
	var painters_ok := true
	for node: Node in renderer._statics.get_children():
		if node.is_queued_for_deletion():
			waiting += 1
			painters_ok = painters_ok and not (node.get("painter") as Callable).is_valid()
	check.call(waiting > 0 and painters_ok, "the piece waiting for deletion has no painter")
	await _stop(pair)


static func _cursor(check: Callable) -> void:
	var tower := TestShafts._tall()
	TestShafts._shaft(tower, 5, 10, 100)
	var at_top: Dictionary = PlacementGhost.evaluate(tower, "local_shaft", 10, 100, 5, "", {})
	var at_middle: Dictionary = PlacementGhost.evaluate(tower, "local_shaft", 7, 100, 5, "", {})
	var empty: Dictionary = PlacementGhost.evaluate(tower, "local_shaft", 7, 10, 5, "", {})
	check.call(PlacementGhost.cursor_for(at_top, 10) == Input.CURSOR_VSIZE, "a shaft's end shows the resize cursor")
	check.call(PlacementGhost.cursor_for(at_middle, 7) == Input.CURSOR_ARROW, "the middle of a shaft shows the plain cursor")
	check.call(PlacementGhost.cursor_for(empty, 7) == Input.CURSOR_ARROW, "empty ground shows the plain cursor")
	check.call(PlacementGhost.cursor_for({"shaft": {"top": 10, "bottom": 5}, "mode": "resize"}, 12) == Input.CURSOR_VSIZE, "dragging a machine room shows the resize cursor")
