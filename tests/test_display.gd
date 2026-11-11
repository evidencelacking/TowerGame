extends RefCounted
## Pixel scale choice and the saved setting, headless.

const DS := preload("res://scripts/view/display_settings.gd")


static func run(check: Callable) -> void:
	check.call(DS.auto_scale(Vector2i(3840, 2160)) == 2, "4K auto scale is 2")
	check.call(DS.auto_scale(Vector2i(1920, 1080)) == 1, "1080p auto scale is 1")
	check.call(DS.auto_scale(Vector2i(2560, 1440)) == 1, "1440p auto scale is 1")
	check.call(DS.auto_scale(Vector2i(1280, 720)) == 1, "720p auto scale is 1")
	check.call(DS.auto_scale(Vector2i(1024, 600)) == 1, "minimum window scale is 1")
	check.call(DS.auto_scale(Vector2i(7680, 4320)) == 4, "8K auto scale is 4")
	check.call(DS.auto_scale(Vector2i(3840, 1080)) == 1, "ultrawide limited by height")
	check.call(DS.resolve_scale(0, Vector2i(3840, 2160)) == 2, "0 means auto")
	check.call(DS.resolve_scale(3, Vector2i(1280, 720)) == 3, "forced scale wins")
	check.call(DS.resolve_scale(9, Vector2i(1280, 720)) == 4, "forced scale clamps to 4")
	var ds: Node = DS.new()
	check.call(ds.pixel_scale == 0, "pixel_scale defaults to Auto")
	ds.free()
