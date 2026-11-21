extends RefCounted
## Burned-out rooms (#373) look charred in both graphics styles, Classic and Detailed: describe() reports the
## state, and drawing the room paints the soot and scorch marks that an intact room does not.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const GraphicsStyle := preload("res://scripts/view/graphics_style.gd")
const RoomLook := preload("res://scripts/view/room_look.gd")


## Records every draw call, so two draws can be compared.
class Recorder:
	extends RefCounted
	var calls: Array = []

	func draw_rect(r: Variant, c: Color, filled: bool = true, width: float = -1.0) -> void:
		calls.append(["rect", r, c, filled, width])

	func draw_line(a: Vector2, b: Vector2, c: Color, width: float = -1.0) -> void:
		calls.append(["line", a, b, c, width])

	func has_colour(c: Color) -> bool:
		for call: Array in calls:
			if call[0] == "rect" and call[2] == c:
				return true
		return false


static func run(check: Callable) -> void:
	var t := TowerSim.new(5, 1000000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 163, 2)
	t.floors.fill_span(3, 100, 163)
	t.rooms.place_room(t.grid, t.floors, t.ledger, 0, Catalogue.IDS.find("office"), 3, 100)
	var office := t.grid.cell_at(3, 100)
	var rect := Rect2i(100 * 8, 0, 9 * 8, 32)
	check.call(RoomLook.describe(t, office)["state"] == RoomLook.OPEN, "an intact office is not charred")
	for detailed in [false, true]:
		var style := GraphicsStyle.for_detailed(detailed)
		var intact := Recorder.new()
		style.room(intact, t, office, rect, [] as Array[int], false, false)
		check.call(not intact.calls.is_empty() and not intact.has_colour(RoomLook.SOOT) and not intact.has_colour(RoomLook.SCORCH), "an intact room draws, with no soot (detailed %s)" % detailed)
	t.rooms.charred[office] = true
	var look := RoomLook.describe(t, office)
	check.call(look["state"] == RoomLook.CHARRED and look["color"] == RoomLook.CHARRED_COLOR, "a burned-out room describes as charred")
	check.call(RoomLook.appearance(look, true, false)[1] == false, "a charred room is never drawn in use, whoever is lit")
	for detailed in [false, true]:
		var style := GraphicsStyle.for_detailed(detailed)
		var burnt := Recorder.new()
		style.room(burnt, t, office, rect, [] as Array[int], true, false)
		check.call(burnt.has_colour(RoomLook.SOOT) and burnt.has_colour(RoomLook.SCORCH) and burnt.has_colour(RoomLook.EMBER), "a charred room draws soot, scorch and embers (detailed %s)" % detailed)
		var again := Recorder.new()
		style.room(again, t, office, rect, [] as Array[int], true, false)
		check.call(again.calls == burnt.calls, "the charred look is the same every frame (detailed %s)" % detailed)
