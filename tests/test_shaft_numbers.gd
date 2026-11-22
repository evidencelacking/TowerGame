extends RefCounted
## Floor numbers in the elevator shafts (#431): the label text for a floor, which floors are labelled at each
## zoom, and that the renderer draws one label per shown floor.

const ShaftNumbers := preload("res://scripts/view/shaft_numbers.gd")


## Records draw_rect calls; the plaques are the wide dark ones (alpha below 1), so one per labelled floor.
class Recorder:
	extends RefCounted
	var plaques: int = 0
	var ink: int = 0

	func draw_rect(_r: Variant, c: Color, _filled: bool = true, _width: float = -1.0) -> void:
		if c.a < 1.0:
			plaques += 1
		else:
			ink += 1


static func run(check: Callable) -> void:
	check.call(ShaftNumbers.label(1) == "1", "the lobby reads 1")
	check.call(ShaftNumbers.label(2) == "2" and ShaftNumbers.label(15) == "15", "floors above the lobby read their number")
	check.call(ShaftNumbers.label(-1) == "B1" and ShaftNumbers.label(-10) == "B10", "basements read B1, B2 ...")
	check.call(ShaftNumbers.step_for_zoom(1.0) == 5 and ShaftNumbers.step_for_zoom(2.0) == 1 and ShaftNumbers.step_for_zoom(4.0) == 1, "labels thin out below zoom 2")
	var rec := Recorder.new()
	ShaftNumbers.draw(rec, Rect2i(0, 0, 16, 32), -3, 12, 1, Color("8a6a4a"))
	check.call(rec.plaques == 15 and rec.ink > 0, "zoomed in, every floor is labelled, with no floor 0")
	rec = Recorder.new()
	ShaftNumbers.draw(rec, Rect2i(0, 0, 16, 32), -7, 12, 5, Color("8a6a4a"))
	check.call(rec.plaques == 5, "zoomed out, the ground floors and every 5th floor")
