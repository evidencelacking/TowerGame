extends RefCounted
## Synergy overlay (#294): the tint per net value, the net of a room from the rules, the rooms that act on a
## hovered room, that reading changes nothing in the tower, and that painting stays on the rooms involved.
## The overlay paints world pixels, so one path serves both graphics styles.

const Look := preload("res://scripts/view/synergy_look.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const TowerSim := preload("res://scripts/sim/tower.gd")
const TestEvaluation := preload("res://tests/test_evaluation.gd")
const VC := preload("res://scripts/view/view_consts.gd")


## Records draw_rect and draw_line calls.
class Recorder:
	extends RefCounted
	var rects: Array[Rect2] = []
	var lines: int = 0
	var fills: Array[Color] = []

	func draw_rect(r: Variant, c: Color, filled: bool = true, _width: float = -1.0) -> void:
		rects.append(Rect2(r))
		if filled:
			fills.append(c)

	func draw_line(_a: Vector2, _b: Vector2, _c: Color, _width: float = -1.0) -> void:
		lines += 1


static func _place(t: TowerSim, kind: String, floor_number: int, x: int) -> int:
	return t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find(kind), floor_number, x)


static func run(check: Callable) -> void:
	_tint(check)
	_net(check)
	_in_a_tower(check)


## Clear at zero, green above, red below, stronger with size, capped.
static func _tint(check: Callable) -> void:
	check.call(Look.tint(0).a == 0.0, "synergy overlay: a net of 0 is clear")
	var plus := Look.tint(8)
	var minus := Look.tint(-8)
	check.call(plus.g > plus.r and plus.a > 0.0, "synergy overlay: a boost tints green")
	check.call(minus.r > minus.g and minus.a > 0.0, "synergy overlay: a harm tints red")
	check.call(Look.tint(16).a > Look.tint(4).a and Look.tint(-16).a > Look.tint(-4).a, "synergy overlay: a bigger net tints stronger")
	check.call(Look.tint(Look.FULL).a == Look.tint(Look.FULL * 5).a and is_equal_approx(Look.tint(Look.FULL).a, Look.MAX_ALPHA), "synergy overlay: the tint is capped at the full strength")
	check.call(is_equal_approx(Look.tint(-5).a, Look.tint(5).a), "synergy overlay: a harm and a boost of the same size tint equally strongly")


## Net of a room from the rule table, with mood, the condo's price and a shop's takings all counted.
static func _net(check: Callable) -> void:
	var office := [3, 100, 9]
	check.call(Look.net_of("office", office, []) == 0, "synergy overlay: a room with no sources nets 0")
	check.call(Look.net_of("office", office, [["gym", [3, 110, 8]]]) == 4, "synergy overlay: a gym beside an office nets +4")
	check.call(Look.net_of("office", [20, 100, 9], [["gym", [3, 110, 8]]]) == 0, "synergy overlay: a gym out of reach nets 0")
	check.call(Look.net_of("condo", [4, 100, 8], [["daycare", [4, 110, 8]]]) == 14, "synergy overlay: a daycare gives a condo its mood and price (+4 +10)")
	check.call(Look.net_of("condo", [4, 100, 8], [["nightclub", [4, 110, 8]]]) == -6, "synergy overlay: a nightclub harms a condo")
	check.call(Look.net_of("restaurant", [2, 100, 8], [["garden", [90, 0, 8]]]) == 8, "synergy overlay: a garden feeds a restaurant tower-wide")


## In a real tower: the offices read their gym, the links name it, and reading changes nothing.
static func _in_a_tower(check: Callable) -> void:
	var t := TestEvaluation._pair("office")
	check.call(Look.tinted_rooms(t).is_empty(), "synergy overlay: a tower without sources tints nothing")
	check.call(_place(t, "gym", 3, 130) == 0, "synergy overlay: the test gym places")
	var before := t.state_hash()
	var tinted := Look.tinted_rooms(t)
	check.call(not tinted.is_empty(), "synergy overlay: a gym tints the offices it reaches")
	var all_positive := true
	for room: Dictionary in tinted:
		all_positive = all_positive and int(room["net"]) > 0
	check.call(all_positive, "synergy overlay: every tinted room of a gym is a boost")
	var office_id := -1
	for id: int in t.rooms.room_ids():
		if t.rooms.kind_of(id) == "office":
			office_id = id
			break
	check.call(office_id > 0, "synergy overlay: the test tower has an office")
	var links := Look.links_to(t, office_id)
	check.call(links.size() == 1 and int(links[0]["amount"]) == 4, "synergy overlay: the hovered office links to its gym with +4 (%d links)" % links.size())
	check.call(Look.links_to(t, -1).is_empty() and Look.links_to(t, 9999).is_empty(), "synergy overlay: no room under the cursor means no links")
	var plain := Recorder.new()
	Look.draw(plain, t, -1)
	var hovered := Recorder.new()
	Look.draw(hovered, t, office_id)
	check.call(plain.lines == 0 and hovered.lines == 1, "synergy overlay: links are drawn only for the hovered room")
	check.call(plain.fills.size() == tinted.size(), "synergy overlay: one tint per tinted room")
	var floor_top := float(VC.floor_to_row(3) * VC.CELL_H)
	var inside := not hovered.rects.is_empty()
	for r: Rect2 in hovered.rects:
		inside = inside and r.position.y >= floor_top - 1.0 and r.end.y <= floor_top + float(VC.CELL_H) + 1.0
	check.call(inside, "synergy overlay: everything is painted on the floor of the rooms involved")
	check.call(t.state_hash() == before, "synergy overlay: reading and painting leave the tower unchanged")
