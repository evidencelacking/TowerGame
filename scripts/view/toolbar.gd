class_name Toolbar
extends CanvasLayer
## The build toolbar: a bar of categories along the bottom, each opening a sub-menu of items.
## Items read the room catalogue (star, cost); nothing is hidden. A locked item is greyed with
## the star that unlocks it, and an item the sim cannot build yet is greyed with a tooltip saying
## so. Picking an item sets the PlacementGhost's tool, the same as its hotkey. View only.

const TowerSim := preload("res://scripts/sim/tower.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const Ghost := preload("res://scripts/view/placement_ghost.gd")
const HudScript := preload("res://scripts/view/hud.gd")

## Category -> item ids, in display order. Catalogue ids here cover CatalogueScript.IDS exactly
## once (a test checks); bulldoze and replace are player tools, not catalogue rows.
const CATEGORIES: Array = [
	["Structure", ["lobby", "floor", "stairs", "escalator"]],
	["Elevators", ["local_shaft", "local_car", "service_shaft", "service_car", "express_shaft", "express_car"]],
	["Rooms", ["office", "condo", "hotel_single", "hotel_twin", "hotel_suite"]],
	["Commerce", ["fast_food", "restaurant", "retail", "movie_theatre", "party_hall"]],
	["Services", ["housekeeping", "security", "medical", "recycling"]],
	["Parking", ["parking_ramp", "parking_space"]],
	["Landmarks", ["metro", "cathedral"]],
	["Tools", [Ghost.BULLDOZE, Ghost.REPLACE]],
]
const TOOL_STAR: int = 1  ## Bulldoze and replace are always available.
const TOOL_NAMES: Dictionary = {Ghost.BULLDOZE: "Bulldoze", Ghost.REPLACE: "Replace"}
const TOOL_TIPS: Dictionary = {
	Ghost.BULLDOZE: "Remove a room (B). Stairs, escalators and shafts go first; click again for the room behind. Permanent rooms cannot be removed.",
	Ghost.REPLACE: "Replace the room under the cursor with the last room tool you chose (R).",
}
const HOTKEYS: Dictionary = {"lobby": "L", "floor": "F", "stairs": "S", "escalator": "E", "office": "O", "condo": "C",
	Ghost.BULLDOZE: "B", Ghost.REPLACE: "R"}

var ghost: PlacementGhost = null
var _bar: PanelContainer
var _submenu: PanelContainer
var _category_buttons: Array[Button] = []
var _category_lists: Array[VBoxContainer] = []  ## One item list per category; only the open one shows.
var _item_buttons: Dictionary = {}  ## item id -> Button
var _open_category: int = -1
var _shown_stars: int = -1
var _shown_tool: String = "?"


func _ready() -> void:
	layer = 4
	_bar = PanelContainer.new()
	_bar.name = "Bar"
	_bar.anchor_left = 0.0
	_bar.anchor_right = 1.0
	_bar.anchor_top = 1.0
	_bar.anchor_bottom = 1.0
	_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_bar.add_child(row)
	_submenu = PanelContainer.new()
	_submenu.name = "SubMenu"
	_submenu.visible = false
	add_child(_submenu)
	for c in CATEGORIES.size():
		var button := Button.new()
		button.text = CATEGORIES[c][0]
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_category_pressed.bind(c))
		row.add_child(button)
		_category_buttons.append(button)
		var list := VBoxContainer.new()
		list.visible = false
		_submenu.add_child(list)
		_category_lists.append(list)
		for id: String in CATEGORIES[c][1]:
			var item := Button.new()
			item.alignment = HORIZONTAL_ALIGNMENT_LEFT
			item.focus_mode = Control.FOCUS_NONE
			item.pressed.connect(select.bind(id))
			list.add_child(item)
			_item_buttons[id] = item
	_refresh()


func bind(value: PlacementGhost) -> void:
	ghost = value
	_refresh()


func _process(_delta: float) -> void:
	if ghost != null and (ghost.stars != _shown_stars or ghost.tool != _shown_tool):
		_refresh()


## Star that unlocks an item. Player tools are always open.
static func star_of(id: String) -> int:
	return CatalogueScript.star(id) if CatalogueScript.has(id) else TOOL_STAR


static func display_name(id: String) -> String:
	return TOOL_NAMES.get(id, id.capitalize())


## What the toolbar shows for an item at a star rating: {enabled, locked, text, tooltip}.
## Locked (star too low) wins over not-yet-buildable, so the player sees what unlocks it.
static func item_state(id: String, star_rating: int) -> Dictionary:
	var star := star_of(id)
	var text := display_name(id)
	if CatalogueScript.has(id):
		text += "  " + HudScript.format_money(CatalogueScript.cost(id))
	if HOTKEYS.has(id):
		text += "  [%s]" % HOTKEYS[id]
	var out := {"enabled": false, "locked": star > star_rating, "text": text, "tooltip": ""}
	if out["locked"]:
		out["text"] = "%s  (Star %d)" % [display_name(id), star]
		out["tooltip"] = "Unlocks at star %d" % star
	elif not Ghost.is_buildable(id):
		out["tooltip"] = "Not buildable yet: the simulation does not support it."
	else:
		out["enabled"] = true
		out["tooltip"] = TOOL_TIPS.get(id, "")
	return out


## Picks an item (the same as pressing its hotkey). Returns false, changing nothing, when it
## is locked or not buildable. Picking the active item again turns the tool off.
func select(id: String) -> bool:
	if ghost == null or not item_state(id, ghost.stars)["enabled"]:
		_refresh()
		return false
	ghost.set_tool("" if ghost.tool == id else id)
	_refresh()
	return true


## Opens a category's sub-menu (or closes it if it is already open).
func toggle_category(index: int) -> void:
	_on_category_pressed(index)


func _on_category_pressed(index: int) -> void:
	_open_category = -1 if _open_category == index else index
	_refresh()


func _refresh() -> void:
	if _bar == null:
		return
	var star_rating: int = ghost.stars if ghost != null else TowerSim.START_STARS
	_shown_stars = star_rating
	_shown_tool = ghost.tool if ghost != null else ""
	for c in CATEGORIES.size():
		_category_buttons[c].set_pressed_no_signal(c == _open_category)
		_category_lists[c].visible = c == _open_category
		for id: String in CATEGORIES[c][1]:
			var item: Button = _item_buttons[id]
			var state := item_state(id, star_rating)
			item.text = state["text"]
			item.disabled = not state["enabled"]
			item.tooltip_text = state["tooltip"]
			item.toggle_mode = true
			item.set_pressed_no_signal(id == _shown_tool)
	_submenu.visible = _open_category >= 0
	_place_submenu.call_deferred()


## Sits the sub-menu just above its category button (after the layout has settled).
func _place_submenu() -> void:
	if _open_category < 0:
		return
	_submenu.reset_size()
	var button := _category_buttons[_open_category]
	_submenu.position = Vector2(button.global_position.x, _bar.global_position.y - _submenu.size.y)
