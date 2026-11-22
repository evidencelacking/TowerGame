extends RefCounted
## Floor numbers in the elevator shafts (#431): the label text for a floor, which floors are labelled at each
## zoom, and that the renderer draws one label per shown floor.

const ShaftNumbers := preload("res://scripts/view/shaft_numbers.gd")


class Recorder:
	extends RefCounted
	var texts: Array[String] = []

	func draw_string_outline(_font: Variant, _pos: Vector2, _text: String, _align: int = 0, _width: float = -1.0, _size: int = 16, _outline: int = 1, _color: Color = Color.WHITE) -> void:
		pass

	func draw_string(_font: Variant, _pos: Vector2, text: String, _align: int = 0, _width: float = -1.0, _size: int = 16, _color: Color = Color.WHITE) -> void:
		texts.append(text)


static func run(check: Callable) -> void:
	check.call(ShaftNumbers.label(1) == "1", "the lobby reads 1")
	check.call(ShaftNumbers.label(2) == "2" and ShaftNumbers.label(15) == "15", "floors above the lobby read their number")
	check.call(ShaftNumbers.label(-1) == "B1" and ShaftNumbers.label(-10) == "B10", "basements read B1, B2 ...")
	check.call(ShaftNumbers.step_for_zoom(1.0) == 5 and ShaftNumbers.step_for_zoom(2.0) == 1 and ShaftNumbers.step_for_zoom(4.0) == 1, "labels thin out below zoom 2")
	var rec := Recorder.new()
	ShaftNumbers.draw(rec, Rect2i(0, 0, 16, 32), -3, 12, 1, Color("8a6a4a"))
	check.call(rec.texts == ["B3", "B2", "B1", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12"], "zoomed in, every floor is labelled, with no floor 0")
	rec = Recorder.new()
	ShaftNumbers.draw(rec, Rect2i(0, 0, 16, 32), -7, 12, 5, Color("8a6a4a"))
	check.call(rec.texts == ["B5", "B1", "1", "5", "10"], "zoomed out, the ground floors and every 5th floor")
