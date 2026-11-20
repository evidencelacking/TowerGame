extends Node2D
## Night lighting for Detailed graphics (#305). Night is not darker paint: the renderer multiplies the
## whole static canvas by an ambient colour that follows the sky (ambient()), and this node, drawn above
## it with additive blending and so untouched by that darkening, paints the lights a lit room adds as soft
## gradients: ceiling and bedside lamp pools, the warm glow of a window, a screen's cool glow. Every light is
## one quad of the same radial texture, so a whole tower costs one texture and a draw call per light, with
## no per-room PointLight2D (the renderer lights at most 16 sources per item). A light is clipped to the room
## that casts it, so it never spills into a dark neighbour. Rooms record lights while they are painted
## (detail_prims.gd glow); the renderer clears the list before each static repaint and redraws this node after.

const SkyLook := preload("res://scripts/view/sky_look.gd")
const AMBIENT_DAY: Color = Color("fff4e2")  ## The mock-up's CanvasModulate colours.
const AMBIENT_NIGHT: Color = Color("3a4478")
const TEX := 128
## Overall light level (#353): additive lights at full strength clipped to white blobs; the mock-up's lamps tint a room warm.
const BRIGHTNESS := 0.55

## Recorded lights: [clip Rect2, centre Vector2, radii Vector2, colour, strength, owner], in world pixels. The owner
## is the id of the renderer piece painting when the light was added (0 when none): a piece repainting drops its own.
static var lights: Array = []
static var painter_id: int = 0
static var _texture: GradientTexture2D = null


static func clear() -> void:
	lights.clear()


static func add(clip: Rect2, centre: Vector2, radii: Vector2, color: Color, strength: float) -> void:
	lights.append([clip, centre, radii, color, strength, painter_id])


## Removes the lights recorded by one piece.
static func drop(owner_id: int) -> void:
	var kept: Array = []
	for light: Array in lights:
		if light[5] != owner_id:
			kept.append(light)
	lights = kept


## The ambient colour multiplied over the world for a daylight value 0 to FULL.
static func ambient(daylight: int) -> Color:
	return AMBIENT_NIGHT.lerp(AMBIENT_DAY, clampf(float(daylight) / float(SkyLook.FULL), 0.0, 1.0))


## How strong the lights are: off by day, full once the sky is half dark.
static func intensity(daylight: int) -> float:
	return clampf(1.0 - float(daylight) / (SkyLook.FULL / 2.0), 0.0, 1.0)


static func texture() -> GradientTexture2D:
	if _texture == null:
		var grad := Gradient.new()
		grad.colors = PackedColorArray([Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
		grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		_texture = GradientTexture2D.new()
		_texture.gradient = grad
		_texture.fill = GradientTexture2D.FILL_RADIAL
		_texture.fill_from = Vector2(0.5, 0.5)
		_texture.fill_to = Vector2(1.0, 0.5)
		_texture.width = TEX
		_texture.height = TEX
	return _texture


func _init() -> void:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat


func _draw() -> void:
	var k := intensity(SkyLook.daylight)
	if k <= 0.0:
		return
	var tex := texture()
	for light: Array in lights:
		var clip: Rect2 = light[0]
		var centre: Vector2 = light[1]
		var radii: Vector2 = light[2]
		var area := Rect2(centre - radii, radii * 2.0).intersection(clip)
		if not area.has_area():
			continue
		var src := Rect2((area.position - (centre - radii)) / (radii * 2.0) * float(TEX), area.size / (radii * 2.0) * float(TEX))
		var c: Color = light[3]
		var s: float = float(light[4]) * k * BRIGHTNESS
		draw_texture_rect_region(tex, area, src, Color(c.r * s, c.g * s, c.b * s, 1.0))
