extends Control
## Viewer for the Detailed art mock-ups (E Illustrated, F Rich pixel, G Lit): one tower slice at
## 16 px per column and 64 px per floor, drawn into a SubViewport and shown at a whole-number scale.
## N or Space switches day and night, Esc quits.
## Launch: python tools/play.py --scene res://mockups/art_e.tscn
## Capture: ... --scene res://mockups/art_e.tscn -- --capture=<dir> writes <stem>_day.png and _night.png.

const Drawer: GDScript = preload("res://mockups/detail_drawer.gd")
const SUPERSAMPLE_E: int = 4
const AMBIENT_DAY: Color = Color("fff4e2")
const AMBIENT_NIGHT: Color = Color("3a4478")

@export var style_id: int = 0  ## 0 E Illustrated, 1 F Rich pixel, 2 G Lit
@export var title_text: String = ""
@export var file_stem: String = "art_e"

var _night: bool = false
var _ss: int = 1
var _view: SubViewport = null
var _rect: TextureRect = null
var _label: Label = null
var _drawers: Array[Node2D] = []
var _world: Node2D = null
var _lights_root: Node2D = null
var _modulate: CanvasModulate = null
var _busy: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg: ColorRect = ColorRect.new()
	bg.color = Color("101014")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_ss = SUPERSAMPLE_E if style_id == 0 else 1
	_view = SubViewport.new()
	_view.size = Vector2i(Drawer.W * _ss, Drawer.H * _ss)
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)
	_build_layers()
	_rect = TextureRect.new()
	_rect.texture = _view.get_texture()
	_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if style_id == 0 else CanvasItem.TEXTURE_FILTER_NEAREST
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_rect)
	_label = Label.new()
	add_child(_label)
	resized.connect(_layout)
	_layout()
	await _apply(false)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			await _capture(arg.trim_prefix("--capture="))


func _make_drawer(layer: int) -> Node2D:
	var d: Node2D = Drawer.new()
	d.scale = Vector2(_ss, _ss)
	d.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_drawers.append(d)
	d.set("pass_layer", layer)
	return d


func _build_layers() -> void:
	if style_id != 2:
		_world = _make_drawer(0)
		_view.add_child(_world)
		return
	var bg_layer: CanvasLayer = CanvasLayer.new()
	bg_layer.layer = -1
	_view.add_child(bg_layer)
	bg_layer.add_child(_make_drawer(2))
	_modulate = CanvasModulate.new()
	_view.add_child(_modulate)
	_world = _make_drawer(0)
	_view.add_child(_world)
	_lights_root = Node2D.new()
	_view.add_child(_lights_root)
	var emit_layer: CanvasLayer = CanvasLayer.new()
	emit_layer.layer = 1
	_view.add_child(emit_layer)
	var emit: Node2D = _make_drawer(1)
	var mat: CanvasItemMaterial = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	emit.material = mat
	emit_layer.add_child(emit)


func _layout() -> void:
	var sc: int = maxi(1, mini(int(size.x) / Drawer.W, int(size.y) / Drawer.H))
	var w: int = Drawer.W * sc
	var h: int = Drawer.H * sc
	_rect.position = Vector2((int(size.x) - w) / 2, (int(size.y) - h) / 2)
	_rect.size = Vector2(w, h)
	_label.position = Vector2(8, 4)


func _apply(is_night: bool) -> void:
	_busy = true
	_night = is_night
	for d: Node2D in _drawers:
		d.call("setup", style_id, _night, int(d.get("pass_layer")))
	if _modulate != null:
		_modulate.color = AMBIENT_NIGHT if _night else AMBIENT_DAY
	_label.text = "%s  [%s]     N or Space: day/night, Esc quits" % [title_text, "night" if _night else "day"]
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_spawn_lights()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_busy = false


func _spawn_lights() -> void:
	if _lights_root == null:
		return
	for c: Node in _lights_root.get_children():
		c.queue_free()
	_lights_root.scale = Vector2(_ss, _ss)
	var tex: GradientTexture2D = GradientTexture2D.new()
	var grad: Gradient = Gradient.new()
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	var lights: Array = _world.get("lights")
	for l: Array in lights:
		var pl: PointLight2D = PointLight2D.new()
		pl.texture = tex
		pl.position = Vector2(float(l[0]), float(l[1]))
		pl.texture_scale = float(l[2]) * 2.0 / 256.0
		pl.energy = float(l[3])
		pl.color = l[4]
		pl.shadow_enabled = true
		pl.shadow_filter = Light2D.SHADOW_FILTER_PCF5
		_lights_root.add_child(pl)
	var occ: Array = _world.get("occluders")
	for o: Array in occ:
		var lo: LightOccluder2D = LightOccluder2D.new()
		var poly: OccluderPolygon2D = OccluderPolygon2D.new()
		var x: float = float(o[0])
		var y: float = float(o[1])
		poly.polygon = PackedVector2Array([Vector2(x, y), Vector2(x + float(o[2]), y), Vector2(x + float(o[2]), y + float(o[3])), Vector2(x, y + float(o[3]))])
		lo.occluder = poly
		_lights_root.add_child(lo)


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed:
		return
	if key.keycode == KEY_ESCAPE:
		get_tree().quit()
	elif (key.keycode == KEY_N or key.keycode == KEY_SPACE) and not _busy:
		_apply(not _night)


func _capture(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for night: bool in [false, true]:
		await _apply(night)
		var img: Image = _view.get_texture().get_image()
		if img == null or img.is_empty():
			printerr("capture failed: no image (renderer cannot draw headless?)")
			get_tree().quit(1)
			return
		if _ss == 1:
			img.resize(img.get_width() * 3, img.get_height() * 3, Image.INTERPOLATE_NEAREST)
		else:  # supersampled: shrink to 3x native with a good filter for smooth edges
			img.resize(Drawer.W * 3, Drawer.H * 3, Image.INTERPOLATE_LANCZOS)
		img.save_png("%s/%s_%s.png" % [dir, file_stem, "night" if night else "day"])
	get_tree().quit()
