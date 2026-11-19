extends CanvasLayer
## Shows the promotion banner (#167) across the top of the screen for a few seconds when the
## tower earns a star, and tells the toolbar what is new. The sound hook is the `promoted` signal:
## there is no audio yet, so nothing listens. The message log entry comes from the sim itself
## (Messages.STAR_PROMOTED). View only.

const Tower := preload("res://scripts/sim/tower.gd")
const PromotionScript := preload("res://scripts/view/promotion.gd")

signal promoted(stars: int)  ## The sound hook: emitted once per announcement.
signal unlocked(ids: Array)  ## What the promotion opened, for the toolbar's "new" marks.

const SHOW_SECONDS := 6.0

var tower: Tower = null
var _promotion := PromotionScript.new()
var _panel: PanelContainer
var _headline: Label
var _unlocks: Label
var _left: float = 0.0


func _ready() -> void:
	layer = 6
	_panel = PanelContainer.new()
	_panel.name = "Banner"
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.offset_top = 60.0
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var column := VBoxContainer.new()
	_panel.add_child(column)
	_headline = Label.new()
	_headline.name = "Headline"
	_headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_headline.add_theme_font_size_override("font_size", 24)
	column.add_child(_headline)
	_unlocks = Label.new()
	_unlocks.name = "Unlocks"
	_unlocks.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_unlocks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_unlocks.custom_minimum_size = Vector2(560, 0)
	column.add_child(_unlocks)


func bind(value: Tower) -> void:
	tower = value
	check()


func _process(delta: float) -> void:
	check()
	if _panel.visible:
		_left -= delta
		if _left <= 0.0:
			_panel.visible = false


## Looks at the tower and announces a new rank. Public so tests can drive it without frames.
func check() -> void:
	if tower == null or _panel == null:
		return
	var info := _promotion.observe(tower)
	if not info.is_empty():
		announce(info["stars"], info["unlocks"])


func announce(stars: int, ids: Array) -> void:
	_headline.text = PromotionScript.headline(stars)
	_unlocks.text = PromotionScript.unlock_line(ids)
	_panel.visible = true
	_left = SHOW_SECONDS
	unlocked.emit(ids)
	promoted.emit(stars)


func is_showing() -> bool:
	return _panel != null and _panel.visible
