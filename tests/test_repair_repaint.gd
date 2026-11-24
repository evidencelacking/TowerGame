extends RefCounted
## A repaired (or burned-out) room is redrawn at once (#483): a change in a room's named state jumps the repaint
## queue, and its tiles render ahead of the background ones, even while a crowd of other pieces keeps going
## stale. Run on a real renderer, with every other piece made costly and re-staled each frame, so the old
## dictionary-order queue spent its whole budget on the same few pieces and never reached the one the player
## was watching. Every loop counts up to a fixed bound, so each ends.

const TowerSim := preload("res://scripts/sim/tower.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const VC := preload("res://scripts/view/view_consts.gd")
const TestPests := preload("res://tests/test_pests.gd")

const FRAMES_ALLOWED := 6  ## The repaint and its tile render must land within this many frames of the change.
const CROWD_COST_US := 4500  ## What each other piece claims to cost, so the budget fits one of them a frame.


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func _piece_of(renderer: TowerRenderer, room: int) -> TowerRenderer.Piece:
	for key: Variant in renderer._room_pieces:
		var candidate: TowerRenderer.Piece = renderer._room_pieces[key]
		for run: Array in candidate.runs:
			if int(run[0]) == room:
				return candidate
	return null


## True when every tile the piece touches has been rendered since the piece last repainted.
static func _tiles_rendered(renderer: TowerRenderer, piece: TowerRenderer.Piece) -> bool:
	var grown := piece.rect.grow(TowerRenderer.TILE_PAD)
	var touched := 0
	for tile: TowerRenderer.Tile in renderer._tiles:
		if tile.rect.intersects(grown):
			touched += 1
			if tile.rendered_frame < piece.painted_frame:
				return false
	return touched > 0


## Frames until the piece has repainted after `before` and its tiles are rendered, or -1; the crowd goes stale
## again each frame.
static func _frames_to_show(renderer: TowerRenderer, piece: TowerRenderer.Piece, before: int) -> int:
	for i in FRAMES_ALLOWED * 4:
		for key: Variant in renderer._room_pieces:
			var other: TowerRenderer.Piece = renderer._room_pieces[key]
			if other != piece:
				other.stale = true
				other.cost_us = CROWD_COST_US
		await _tree().process_frame
		if piece.painted_frame > before and _tiles_rendered(renderer, piece):
			return i + 1
	return -1


static func run(check: Callable) -> void:
	var t := TestPests._tower()
	for spot: Array in [[3, 100], [3, 109], [3, 118], [4, 100], [4, 109]]:  # the crowd, built first so it queues first
		TestPests._room(t, "office", spot[0], spot[1])
	var target := TestPests._room(t, "office", 4, 118)
	var renderer := TowerRenderer.new()
	var camera := Camera2D.new()
	_tree().root.add_child(renderer)
	_tree().root.add_child(camera)
	await _tree().process_frame
	renderer.set_tower(t)
	camera.position = Vector2(122 * VC.CELL_W, VC.floor_to_row(4) * VC.CELL_H)
	camera.make_current()
	for i in 40:
		await _tree().process_frame
		if i > 2 and renderer.pending_work() == 0:
			break
	var piece := _piece_of(renderer, target)
	check.call(target >= 0 and piece != null and not piece.stale and renderer._room_pieces.size() >= 6, "repair repaint: the renderer has painted the offices")
	if piece != null:
		t.rooms.charred[target] = true
		t.char_room(target)
		var shown := await _frames_to_show(renderer, piece, piece.painted_frame)
		check.call(shown > 0 and shown <= FRAMES_ALLOWED, "a room that burns out is drawn burned out within a few frames, amid a crowd of stale pieces (took %d)" % shown)
		t.ledger.balance = 100000000
		check.call(t.repair_room(4, 118) == RoomsScript.OK, "the burned-out office is repaired")
		shown = await _frames_to_show(renderer, piece, piece.painted_frame)
		check.call(shown > 0 and shown <= FRAMES_ALLOWED, "a repaired room is redrawn, and its tiles rendered, within a few frames amid a crowd of stale pieces (took %d)" % shown)
	renderer.queue_free()
	camera.queue_free()
	await _tree().process_frame
