extends RefCounted
## Vacant looks (#358): each unit kind returns its vacant look when unrented and its normal look when
## occupied, in both graphics styles, and a vacancy change repaints the room. Drawing is checked here by what
## reaches a recording canvas (the sign plate and its colour); what it looks like is checked by eye in a capture.
## Every loop here counts up to a fixed bound, so each ends; each check fails if its look were not drawn.

const TowerSim := preload("res://scripts/sim/tower.gd")
const HotelScript := preload("res://scripts/sim/hotel.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")
const RoomLook := preload("res://scripts/view/room_look.gd")
const VacantLook := preload("res://scripts/view/vacant_look.gd")
const VC := preload("res://scripts/view/view_consts.gd")
const TestPests := preload("res://tests/test_pests.gd")

const WIDE := 64  ## Wide enough for "OUT OF BUSINESS" (59 px of lettering plus its plate).


## Records the colours a room look draws.
class Recorder:
	extends RefCounted
	var colors: Array[Color] = []

	func draw_rect(_r: Variant, c: Color, _filled: bool = true, _width: float = -1.0) -> void:
		colors.append(c)

	func draw_line(_a: Vector2, _b: Vector2, c: Color, _width: float = -1.0) -> void:
		colors.append(c)

	func has(c: Color) -> bool:
		for k: Color in colors:
			if k.is_equal_approx(c):
				return true
		return false


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## What a look draws for one room, in the style (fine is Detailed).
static func _drawn(t: TowerSim, id: int, fine: bool) -> Recorder:
	var rec := Recorder.new()
	var look := RoomLook.describe(t, id)
	RoomLook.draw_marks(rec, look, Rect2i(0, 0, WIDE, VC.CELL_H), false, fine)
	return rec


static func run(check: Callable) -> void:
	_kinds(check)
	_lettering(check)
	await _repaint(check)


static func _kinds(check: Callable) -> void:
	var t := TestPests._tower()
	t.floors.fill_span(5, 100, 131)
	t.floors.fill_span(6, 100, 131)
	var shop := TestPests._room(t, "retail", 3, 100)
	var office := TestPests._room(t, "office", 4, 100)
	var condo := TestPests._room(t, "condo", 5, 100)
	var hotel := TestPests._room(t, "hotel_single", 6, 100)
	check.call(shop >= 0 and office >= 0 and condo >= 0 and hotel >= 0, "vacant look: the unit kinds are placed")
	for fine: bool in [false, true]:
		var style := "detailed" if fine else "classic"
		# Shop: leased until its renter leaves.
		check.call(not _drawn(t, shop, fine).has(VacantLook.SIGN_INK), "%s: a leased shop has no Closed sign" % style)
		t.commerce._vacant[shop] = 0
		check.call(bool(RoomLook.describe(t, shop)["empty"]), "a vacant shop is empty")
		check.call(_drawn(t, shop, fine).has(VacantLook.SIGN_INK), "%s: a vacant shop shows its sign" % style)
		check.call(_drawn(t, shop, fine).has(VacantLook.SHUTTER), "%s: a vacant shop has its shutter down" % style)
		t.commerce._vacant.erase(shop)
		# Office: empty until it has workers.
		check.call(_drawn(t, office, fine).has(VacantLook.LEASE_INK), "%s: an unleased office shows For Lease" % style)
		t.people.add_person(PeopleScript.NONE, office, t.rng)
		check.call(not bool(RoomLook.describe(t, office)["empty"]), "an office with a worker is not empty")
		check.call(not _drawn(t, office, fine).has(VacantLook.LEASE_INK), "%s: a tenanted office has no sign" % style)
		t.people.remove_person(t.people.count() - 1)
		# Condo: blinds until sold.
		check.call(_drawn(t, condo, fine).has(VacantLook.BLIND), "%s: an unsold condo has its blinds drawn" % style)
		t.rooms.set_sold(condo, true)
		check.call(not _drawn(t, condo, fine).has(VacantLook.BLIND), "%s: a sold condo has its blinds open" % style)
		t.rooms.set_sold(condo, false)
		# Hotel room: blinds while nobody stays.
		check.call(bool(RoomLook.describe(t, hotel)["empty"]) and _drawn(t, hotel, fine).has(VacantLook.BLIND), "%s: an unoccupied hotel room has its blinds drawn" % style)
	t.hotel._records[hotel] = [HotelScript.STAYING, -1, -1, 420, -1, 0, 0, 0] as Array[int]
	check.call(not bool(RoomLook.describe(t, hotel)["empty"]) and not _drawn(t, hotel, false).has(VacantLook.BLIND), "an occupied hotel room is not drawn vacant")
	check.call(VacantLook.family("recycling") == "", "kinds that are not rented units have no vacant look")


static func _lettering(check: Callable) -> void:
	check.call(VacantLook.sign_text("retail", WIDE) == "OUT OF BUSINESS", "a wide vacant shop says Out of Business")
	check.call(VacantLook.sign_text("retail", 32) == "CLOSED", "a narrower one says Closed")
	check.call(VacantLook.sign_text("retail", 8) == "", "a room too narrow for a sign shows none")
	check.call(VacantLook.sign_text("office", WIDE) == "FOR LEASE", "an empty office says For Lease")
	var all_drawn := true
	for text: String in ["OUT OF BUSINESS", "CLOSED", "FOR LEASE"]:
		for ch: String in text:
			all_drawn = all_drawn and (ch == " " or VacantLook.GLYPHS.has(ch))
	check.call(all_drawn, "every letter on the signs has a glyph")


## A vacancy change marks the room's piece for repaint on a real renderer.
static func _repaint(check: Callable) -> void:
	var t := TestPests._tower()
	var shop := TestPests._room(t, "retail", 3, 100)
	var renderer := TowerRenderer.new()
	var camera := Camera2D.new()
	_tree().root.add_child(renderer)
	_tree().root.add_child(camera)
	await _tree().process_frame
	renderer.set_tower(t)
	camera.position = Vector2(115 * VC.CELL_W, VC.floor_to_row(3) * VC.CELL_H)
	camera.make_current()
	for i in 30:
		await _tree().process_frame
		if i > 2 and renderer.pending_work() == 0:
			break
	var piece: TowerRenderer.Piece = null
	for key: Variant in renderer._room_pieces:
		var candidate: TowerRenderer.Piece = renderer._room_pieces[key]
		for run: Array in candidate.runs:
			if int(run[0]) == shop:
				piece = candidate
	check.call(piece != null and not piece.stale, "the renderer has painted the shop")
	if piece != null:
		var before: int = piece.painted_frame
		t.commerce._vacant[shop] = 0
		renderer._mark_changed_rooms()
		check.call(piece.stale, "a shop going vacant marks its room for repaint")
		for i in 30:
			await _tree().process_frame
			if piece.painted_frame > before:
				break
		check.call(piece.painted_frame > before, "the vacant shop is repainted within a few frames")
	renderer.queue_free()
	camera.queue_free()
	await _tree().process_frame
