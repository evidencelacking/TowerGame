extends RefCounted
## Disruptions view (#487): the tint per suffering score, the sources and reasons on a fixture with a noisy
## neighbour, a synergy harm and a distance complaint, and that reading and painting change nothing.

const Look := preload("res://scripts/view/disruption_look.gd")
const SynergyLook := preload("res://scripts/view/synergy_look.gd")
const Complaints := preload("res://scripts/sim/complaints.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const TowerSim := preload("res://scripts/sim/tower.gd")
const TestEvaluation := preload("res://tests/test_evaluation.gd")


## Records the draw calls of a canvas.
class Recorder:
	extends RefCounted
	var fills: Array[Color] = []
	var outlines: Array[Rect2] = []
	var lines: int = 0
	var strings: Array[String] = []

	func draw_rect(r: Variant, c: Color, filled: bool = true, _width: float = -1.0) -> void:
		if filled:
			fills.append(c)
		else:
			outlines.append(Rect2(r))

	func draw_line(_a: Vector2, _b: Vector2, _c: Color, _width: float = -1.0) -> void:
		lines += 1

	func draw_string(_f: Font, _p: Vector2, text: String, _a: int = 0, _w: float = -1.0, _s: int = 16, _c: Color = Color.WHITE) -> void:
		strings.append(text)

	func draw_string_outline(_f: Font, _p: Vector2, _t: String, _a: int = 0, _w: float = -1.0, _s: int = 16, _o: int = 1, _c: Color = Color.WHITE) -> void:
		pass


static func _place(t: TowerSim, kind: String, floor_number: int, x: int) -> int:
	return t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find(kind), floor_number, x)


static func run(check: Callable) -> void:
	_tint(check)
	_in_a_tower(check)


static func _tint(check: Callable) -> void:
	check.call(Look.tint(0).a == 0.0, "disruptions: no suffering is clear")
	check.call(Look.tint(6).r > Look.tint(6).g and Look.tint(6).a > 0.0, "disruptions: suffering tints red")
	check.call(Look.tint(15).a > Look.tint(5).a, "disruptions: more suffering tints stronger")
	check.call(is_equal_approx(Look.tint(Look.FULL * 4).a, Look.MAX_ALPHA) and Look.tint(Look.FULL).a == Look.tint(Look.FULL * 4).a, "disruptions: the tint is capped at the full strength")
	check.call(Look.reason_text(Complaints.DISTANCE) == "too far to an elevator" and Look.reason_text(Complaints.RENT) == "rent too high", "disruptions: the distance and rent reasons read in words")
	check.call(Look.reason_text(Complaints.NO_GROCERY) != "", "disruptions: the other reasons use the complaint label")


static func _in_a_tower(check: Callable) -> void:
	var t := TestEvaluation._pair("condo")
	var condo := _id_of(t, "condo")
	check.call(condo > 0, "disruptions: the test condo places")
	var calm: Dictionary = Look.suffering_of(t, condo, Look.context(t))
	check.call(int(calm["noise"]) == 0 and int(calm["harm"]) == 0, "disruptions: a condo with no noisy neighbour has no noise or harm")
	t.floors.fill_span(4, 100, 200)
	var placed := _place(t, "nightclub", 4, 108)
	check.call(placed == 0, "disruptions: the test nightclub places (code %d)" % placed)
	var ctx := Look.context(t)
	var s := Look.suffering_of(t, condo, ctx)
	check.call(int(s["noise"]) > 0 and int(s["harm"]) > 0, "disruptions: a nightclub beside a condo gives noise (%d) and a synergy harm (%d)" % [int(s["noise"]), int(s["harm"])])
	check.call(int(s["points"]) > int(calm["points"]), "disruptions: the nightclub adds to the condo's suffering")
	var club_id := _id_of(t, "nightclub")
	var club := SynergyLook.rect_of(t.grid.run_of(club_id))
	var links := Look.links_to(t, condo, ctx)
	var noise_label := false
	var harm_label := false
	var all_club := not links.is_empty()
	for link: Dictionary in links:
		noise_label = noise_label or link["label"] == "noise from the nightclub"
		harm_label = harm_label or str(link["label"]).contains("mood from nightclub")
		all_club = all_club and link["rect"] == club
	check.call(noise_label, "disruptions: the condo links to the nightclub's noise")
	check.call(harm_label, "disruptions: the condo links to the nightclub's synergy harm, with its mood amount")
	check.call(all_club, "disruptions: every link of the condo reaches the nightclub")
	var causes := Look.cause_rects(t, Look.suffering_rooms(t, ctx), ctx)
	check.call(causes == [club], "disruptions: the nightclub is the one room marked as a cause (%d marked)" % causes.size())
	check.call(Look.links_to(t, -1).is_empty() and Look.links_to(t, 9999).is_empty(), "disruptions: no room under the cursor means no links")
	check.call(Look.links_to(t, club_id, ctx).is_empty(), "disruptions: the nightclub itself has no one acting on it")

	TestEvaluation._stress(t, 150)
	var tired := Look.suffering_of(t, condo, ctx)
	check.call((tired["reasons"] as Array).has(Complaints.DISTANCE), "disruptions: travel stress gives the distance complaint")
	check.call(int(tired["points"]) >= int(s["points"]) + Look.REASON_POINTS, "disruptions: the distance complaint adds its points")
	var rooms := Look.suffering_rooms(t, ctx)
	check.call(_has(rooms, condo), "disruptions: the condo is among the suffering rooms")

	var before := t.state_hash()
	var plain := Recorder.new()
	Look.draw(plain, t, -1)
	var hovered := Recorder.new()
	Look.draw(hovered, t, condo)
	check.call(plain.lines == 0 and plain.strings.is_empty() and hovered.lines == links.size(), "disruptions: links and labels are drawn only for the hovered room")
	check.call(hovered.strings.has("noise from the nightclub") and hovered.strings.has("too far to an elevator"), "disruptions: the hovered room shows its cause and its reason in words")
	check.call(plain.fills.size() == rooms.size(), "disruptions: one tint per suffering room")
	check.call(t.state_hash() == before, "disruptions: reading and painting leave the tower unchanged")


static func _id_of(t: TowerSim, kind: String, last: bool = false) -> int:
	var found := -1
	for id: int in t.rooms.room_ids():
		if t.rooms.kind_of(id) == kind:
			found = id
			if not last:
				return found
	return found


static func _has(rooms: Array[Dictionary], id: int) -> bool:
	for room: Dictionary in rooms:
		if room["id"] == id:
			return true
	return false
