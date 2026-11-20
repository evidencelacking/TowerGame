extends RefCounted
## Stairs and escalator art (#282): drawing stays inside the link's cells, the escalator's scrolling
## steps depend only on the sim tick, and stacked flights meet at the same height.
## Each check is a draw into a recording canvas and a comparison, so every one can fail.

const TransportLook := preload("res://scripts/view/transport_look.gd")
const VC := preload("res://scripts/view/view_consts.gd")
const EDGE_HUE := Color.ORANGE


## Records the draw calls a painter makes.
class Recorder:
	extends RefCounted
	var calls: Array = []

	func draw_rect(r: Rect2i, c: Color) -> void:
		calls.append([r, c])


static func _span(floor_row: int, width_units: int) -> Rect2i:
	return Rect2i(40, (floor_row - 1) * VC.CELL_H, width_units * VC.CELL_W, 2 * VC.CELL_H)


static func _inside(rec: Recorder, span: Rect2i) -> bool:
	for call: Array in rec.calls:
		if not span.encloses(call[0]):
			return false
	return not rec.calls.is_empty()


static func _belt(span: Rect2i, tick: int) -> Recorder:
	var rec := Recorder.new()
	TransportLook.draw_belt(rec, span, tick, EDGE_HUE)
	return rec


static func _same(a: Recorder, b: Recorder) -> bool:
	if a.calls.size() != b.calls.size():
		return false
	for n: int in a.calls.size():
		if a.calls[n][0] != b.calls[n][0] or a.calls[n][1] != b.calls[n][1]:
			return false
	return true


## The columns (x) of the lit step edges drawn at a tick.
static func _edge_columns(span: Rect2i, tick: int) -> Array:
	var lit := EDGE_HUE.lightened(0.45)
	var xs: Array = []
	for call: Array in _belt(span, tick).calls:
		if call[1] == lit:
			xs.append((call[0] as Rect2i).position.x)
	return xs


static func run(check: Callable) -> void:
	# Drawing stays inside the link's two floors, on both climb directions and a few widths.
	for kind: String in ["stairs", "escalator"]:
		for row: int in [2, 3]:
			for width: int in [6, 8, 12]:
				var span := _span(row, width)
				var rec := Recorder.new()
				TransportLook.draw_link(rec, kind, span)
				check.call(_inside(rec, span), "transport art: %s row %d width %d draws inside its cells" % [kind, row, width])
	var belt_span := _span(2, 8)
	check.call(_inside(_belt(belt_span, 7), belt_span), "transport art: the moving steps draw inside the cells")

	# Scrolling is a pure function of the tick: the same tick draws the same, the next tick moves each
	# step edge one column up the climb, and it repeats every period.
	check.call(_same(_belt(belt_span, 5), _belt(belt_span, 5)), "transport art: the same tick draws the same steps")
	check.call(not _same(_belt(belt_span, 5), _belt(belt_span, 6)), "transport art: the next tick moves the steps")
	check.call(_same(_belt(belt_span, 5), _belt(belt_span, 5 + TransportLook.BELT_PERIOD * 3)), "transport art: the steps repeat each period")
	var step := -1 if TransportLook.flips(belt_span) else 1  # the climb's direction along x
	var before := _edge_columns(belt_span, 0)
	var after := _edge_columns(belt_span, 1)
	var moved := not before.is_empty()
	for x: int in before:
		var next := x + step
		if next > belt_span.position.x + 6 and next < belt_span.end.x - 6:  # away from the footplates
			moved = moved and after.has(next)
	check.call(moved, "transport art: each step edge moves one column up the climb per tick")

	# Stacked flights meet: the top of one flight is the bottom of the next, in the same column.
	var lower := _span(3, 8)
	var upper := _span(2, 8)
	var lower_top := TransportLook.surface_y(lower.end.y - VC.SLAB_H, lower.size.x, lower.size.x - 1)
	var upper_bottom := TransportLook.surface_y(upper.end.y - VC.SLAB_H, upper.size.x, 0)
	check.call(lower_top == upper_bottom, "transport art: stacked flights meet at the same tread height")
	check.call(TransportLook.column_x(lower, lower.size.x - 1) == TransportLook.column_x(upper, 0), "transport art: and in the same column, the flight turning back")
