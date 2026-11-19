extends Control
## Art mock-up viewer: the same floor slice in day (top) and night (bottom), drawn at native
## resolution into SubViewports and shown nearest-filtered at a whole-number scale.
## Esc quits. Launch with: python tools/play.py res://mockups/art_a.tscn
## Capture: ... res://mockups/art_a.tscn -- --capture=<dir> writes art_<x>_day.png and _night.png.

const Drawer: GDScript = preload("res://mockups/art_drawer.gd")

@export var style_id: int = 0
@export var title_text: String = ""
@export var file_stem: String = "art_a"

var _views: Array[SubViewport] = []
var _rects: Array[TextureRect] = []
var _label: Label = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg: ColorRect = ColorRect.new()
	bg.color = Color("101014")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	for is_night: bool in [false, true]:
		var vp: SubViewport = SubViewport.new()
		vp.size = Vector2i(Drawer.NATIVE_W, Drawer.NATIVE_H)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var drawer: Node2D = Drawer.new()
		vp.add_child(drawer)
		drawer.call("setup", style_id, is_night)
		_views.append(vp)
		var tr: TextureRect = TextureRect.new()
		tr.texture = vp.get_texture()
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		add_child(tr)
		_rects.append(tr)
	_label = Label.new()
	_label.text = "%s     (top: day, bottom: night)     Esc quits" % title_text
	add_child(_label)
	resized.connect(_layout)
	_layout()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_capture(arg.trim_prefix("--capture="))


func _layout() -> void:
	var avail: Vector2 = size - Vector2(0, 40)
	var sc: int = maxi(1, mini(int(avail.x) / Drawer.NATIVE_W, int(avail.y) / (Drawer.NATIVE_H * 2)))
	var w: int = Drawer.NATIVE_W * sc
	var h: int = Drawer.NATIVE_H * sc
	var x: int = (int(size.x) - w) / 2
	var y: int = 40 + (int(avail.y) - 2 * h) / 2
	_label.position = Vector2(x, 8)
	for i: int in 2:
		_rects[i].position = Vector2(x, y + i * h)
		_rects[i].size = Vector2(w, h)


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		get_tree().quit()


func _capture(dir: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(dir)
	var names: Array[String] = ["day", "night"]
	for i: int in 2:
		var img: Image = _views[i].get_texture().get_image()
		if img == null or img.is_empty():
			printerr("capture failed: no image (renderer cannot draw headless?)")
			get_tree().quit(1)
			return
		img.resize(img.get_width() * 3, img.get_height() * 3, Image.INTERPOLATE_NEAREST)
		img.save_png("%s/%s_%s.png" % [dir, file_stem, names[i]])
	get_tree().quit()
