class_name UiSkin
extends RefCounted
## The G Lit skin for the toolbar, HUD and windows (#307): dark slate panels, wood-brown buttons with a cream
## label and a warm gold highlight, square corners, matching the Detailed art (docs/mockups/art_g_*.png).
## Every Control reads Godot's default theme, so the skin is written into it and undone from a record of what
## each item held before, which makes Classic exactly what it was. View only: nothing here touches the sim.

const SLATE := Color("2c2b36")  ## Panel fill: the stairwell and shaft stone.
const SLATE_DARK := Color("1d1c25")  ## Inset fill: fields, bars, popups.
const STONE := Color("4d4b5c")  ## Panel edge.
const WOOD := Color("7a5233")  ## Button fill: the desks and counters.
const WOOD_LIGHT := Color("9a6c40")
const WOOD_DARK := Color("4f3320")
const CREAM := Color("f2e6c8")  ## Text.
const CREAM_DIM := Color("b9ad92")
const GOLD := Color("e8b04a")  ## Hover and selection: the lit window.
const GREEN := Color("4cc870")  ## The stairwell's exit lights: bars and ticks.
const CLEAR := Color(0, 0, 0, 0)

## What each themed item held before the skin touched it: "kind|type|name" -> the value, or null if absent.
static var _original: Dictionary = {}
static var _on: bool = false


## Puts the skin on or takes it off. Safe to call repeatedly with the same value.
static func apply(detailed: bool) -> void:
	var theme := ThemeDB.get_default_theme()
	if theme == null or detailed == _on:
		return
	_on = detailed
	for item: Array in items():
		var kind: String = item[0]
		var type: String = item[1]
		var item_name: String = item[2]
		var key := "%s|%s|%s" % [kind, type, item_name]
		if detailed:
			if not _original.has(key):
				_original[key] = _read_item(theme, kind, type, item_name) if _has_item(theme, kind, type, item_name) else null
			_write_item(theme, kind, type, item_name, item[3])
		elif _original.has(key):
			if _original[key] == null:
				_clear_item(theme, kind, type, item_name)
			else:
				_write_item(theme, kind, type, item_name, _original[key])


static func is_on() -> bool:
	return _on


## Every item the skin sets: [kind, theme type, item name, value]. kind is "style" or "color".
static func items() -> Array[Array]:
	var out: Array[Array] = []
	var panel := _box(SLATE, STONE, 2, 6)
	for type: String in ["PanelContainer", "Panel"]:
		out.append(["style", type, "panel", panel])
	out.append(["style", "PopupPanel", "panel", _box(SLATE_DARK, STONE, 2, 4)])
	out.append(["style", "PopupMenu", "panel", _box(SLATE_DARK, STONE, 2, 4)])
	out.append(["style", "PopupMenu", "hover", _box(WOOD, GOLD, 1, 3)])
	out.append(["style", "TooltipPanel", "panel", _box(SLATE_DARK, GOLD, 1, 4)])
	for type: String in ["Button", "OptionButton", "MenuButton"]:
		out.append(["style", type, "normal", _box(WOOD, WOOD_DARK, 2, 6)])
		out.append(["style", type, "hover", _box(WOOD_LIGHT, GOLD, 2, 6)])
		out.append(["style", type, "pressed", _box(WOOD_DARK, GOLD, 2, 6)])
		out.append(["style", type, "disabled", _box(SLATE, STONE, 2, 6)])
		out.append(["style", type, "focus", _box(CLEAR, GOLD, 1, 6)])
	out.append(["style", "CheckButton", "normal", _box(CLEAR, CLEAR, 0, 4)])
	out.append(["style", "CheckButton", "hover", _box(Color(1, 1, 1, 0.06), CLEAR, 0, 4)])
	out.append(["style", "CheckButton", "pressed", _box(Color(1, 1, 1, 0.1), CLEAR, 0, 4)])
	out.append(["style", "ProgressBar", "background", _box(SLATE_DARK, STONE, 1, 2)])
	out.append(["style", "ProgressBar", "fill", _box(GREEN, GREEN.darkened(0.4), 1, 2)])
	out.append(["style", "LineEdit", "normal", _box(SLATE_DARK, STONE, 2, 4)])
	out.append(["style", "LineEdit", "focus", _box(SLATE_DARK, GOLD, 2, 4)])
	for type: String in ["Label", "CheckButton", "Button", "OptionButton", "MenuButton"]:
		out.append(["color", type, "font_color", CREAM])
	for type: String in ["Button", "OptionButton", "MenuButton"]:
		out.append(["color", type, "font_hover_color", Color.WHITE])
		out.append(["color", type, "font_pressed_color", GOLD])
		out.append(["color", type, "font_disabled_color", CREAM_DIM.darkened(0.3)])
	out.append(["color", "CheckButton", "font_hover_color", Color.WHITE])
	out.append(["color", "CheckButton", "font_pressed_color", GOLD])
	out.append(["color", "PopupMenu", "font_color", CREAM])
	out.append(["color", "PopupMenu", "font_hover_color", Color.WHITE])
	out.append(["color", "TooltipLabel", "font_color", CREAM])
	out.append(["color", "LineEdit", "font_color", CREAM])
	return out


static func _box(fill: Color, edge: Color, border: int, margin: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(border)
	box.set_corner_radius_all(0)  # pixel art: square corners
	box.set_content_margin_all(margin)
	return box


static func _has_item(theme: Theme, kind: String, type: String, item_name: String) -> bool:
	if kind == "style":
		return theme.has_stylebox(item_name, type)
	return theme.has_color(item_name, type)


static func _read_item(theme: Theme, kind: String, type: String, item_name: String) -> Variant:
	if kind == "style":
		return theme.get_stylebox(item_name, type)
	return theme.get_color(item_name, type)


static func _write_item(theme: Theme, kind: String, type: String, item_name: String, value: Variant) -> void:
	if kind == "style":
		theme.set_stylebox(item_name, type, value as StyleBox)
	else:
		theme.set_color(item_name, type, value as Color)


static func _clear_item(theme: Theme, kind: String, type: String, item_name: String) -> void:
	if kind == "style":
		theme.clear_stylebox(item_name, type)
	else:
		theme.clear_color(item_name, type)
