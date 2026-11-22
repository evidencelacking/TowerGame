extends RefCounted
## See-through transport (#367): the option flips Detailed shafts, stairs and escalators between a glass or
## outline look and the opaque one, and the glass look covers far less of the room behind. Each check draws into
## a recording canvas and compares the two modes, so it fails if the option did nothing.

const Glass := preload("res://scripts/view/transport_glass.gd")
const DetailTransport := preload("res://scripts/view/detail_transport.gd")
const VC := preload("res://scripts/view/view_consts.gd")


## Records draw_rect calls: the rectangles and their colours, in order.
class Recorder:
	extends RefCounted
	var rects: Array[Rect2] = []
	var colours: Array[Color] = []

	func draw_rect(r: Variant, c: Color, _filled: bool = true, _width: float = -1.0) -> void:
		rects.append(Rect2(r))
		colours.append(c)

	## Area covered by calls that are fully opaque (overlaps counted twice; both modes are measured alike).
	func opaque_area() -> float:
		var area := 0.0
		for i: int in rects.size():
			if colours[i].a >= 0.99:
				area += rects[i].get_area()
		return area


static func run(check: Callable) -> void:
	var was := Glass.on
	_toggle(check)
	_shaft(check)
	_links(check)
	Glass.set_on(was)  # the toggle saves to user://settings.cfg: put back what was there


static func _toggle(check: Callable) -> void:
	Glass.on = false
	Glass.toggle()
	check.call(Glass.on, "toggle turns the option on")
	Glass.toggle()
	check.call(not Glass.on, "toggle turns the option off")


static func _shaft_calls(on: bool) -> Recorder:
	Glass.on = on
	var rec := Recorder.new()
	var rect := Rect2i(80, 0, 4 * VC.CELL_W, 3 * VC.CELL_H)
	var caps: Array[Rect2i] = []
	var rows: Array[int] = [VC.CELL_H - VC.SLAB_H, 2 * VC.CELL_H - VC.SLAB_H]
	DetailTransport.shaft(rec, rect, Color("8a6a4a"), caps, rows, false)
	return rec


static func _shaft(check: Callable) -> void:
	var opaque := _shaft_calls(false)
	var glass := _shaft_calls(true)
	check.call(not opaque.rects.is_empty() and not glass.rects.is_empty(), "a shaft draws in both modes")
	check.call(opaque.opaque_area() > 3.0 * glass.opaque_area(), "a glass shaft covers far less opaque area than the solid one")
	var tint := false
	for i: int in glass.rects.size():
		tint = tint or (glass.colours[i].a < 0.5 and glass.rects[i].size.x >= 4 * VC.CELL_W and glass.rects[i].size.y >= 3 * VC.CELL_H)
	check.call(tint, "a glass shaft has a translucent tint over its whole column")


static func _link_calls(kind: String, on: bool) -> Recorder:
	Glass.on = on
	var rec := Recorder.new()
	var span := Rect2i(40, 0, (4 if kind == "stairs" else 8) * VC.CELL_W, 2 * VC.CELL_H)
	if kind == "stairs":
		DetailTransport.stairs(rec, span)
	else:
		DetailTransport.escalator(rec, span)
	return rec


static func _links(check: Callable) -> void:
	for kind: String in ["stairs", "escalator"]:
		var solid := _link_calls(kind, false)
		var outline := _link_calls(kind, true)
		check.call(not outline.rects.is_empty(), "%s draw in outline mode" % kind)
		check.call(solid.opaque_area() > 1.5 * outline.opaque_area(), "%s cover less opaque area as an outline than as a solid block" % kind)
