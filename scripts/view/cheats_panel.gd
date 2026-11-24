class_name CheatsPanel
extends CanvasLayer
## The Cheats panel (#39): our own cheats, kept apart from normal play. It opens with its key (F9) only while the Cheats
## setting is on. Each control queues one sim command (CHEAT_MONEY, CHEAT_UNLOCK_ALL, CHEAT_SET_STARS); the sim sets the
## saved `cheated` flag. No "instant build" (building has no construction time) and no "fill demand" (tenants move in on
## the sim's own clock with no safe way to force it). View only.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command

const MONEY := 1_000_000  ## What "Add $1,000,000" adds.

var tower: TowerSim = null
var panel: PanelContainer
var _unlock_box: CheckBox
var _stars_box: OptionButton
var _syncing: bool = false


func _init() -> void:
	layer = 7
	name = "CheatsPanel"
	add_to_group("cheats_panel")
	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.visible = false
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.offset_left = -16.0
	panel.offset_right = -16.0
	add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var title := Label.new()
	title.text = "Cheats (our own; this tower will be marked)"
	column.add_child(title)
	var money := Button.new()
	money.name = "AddMoney"
	money.text = "Add $1,000,000"
	money.pressed.connect(add_money)
	column.add_child(money)
	_unlock_box = CheckBox.new()
	_unlock_box.name = "UnlockAll"
	_unlock_box.text = "Unlock all rooms"
	_unlock_box.toggled.connect(func(on: bool) -> void:
		if not _syncing:
			unlock_all(on))
	column.add_child(_unlock_box)
	var row := HBoxContainer.new()
	column.add_child(row)
	var label := Label.new()
	label.text = "Set stars"
	row.add_child(label)
	_stars_box = OptionButton.new()
	_stars_box.name = "SetStars"
	for n in range(1, 6):
		_stars_box.add_item(str(n), n)
	_stars_box.item_selected.connect(func(index: int) -> void:
		if not _syncing:
			set_stars(_stars_box.get_item_id(index)))
	row.add_child(_stars_box)


func bind(tower_value: TowerSim) -> void:
	tower = tower_value
	_sync()


func is_open() -> bool:
	return panel.visible


## Opens only while the Cheats setting is on. Returns whether it is open.
func open() -> bool:
	if not CheatSettings.is_enabled() or tower == null:
		return false
	_sync()
	panel.visible = true
	return true


func close() -> void:
	panel.visible = false


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


func add_money() -> bool:
	return _send(Command.CHEAT_MONEY, [MONEY] as Array[int])


func unlock_all(on: bool) -> bool:
	return _send(Command.CHEAT_UNLOCK_ALL, [1 if on else 0] as Array[int])


func set_stars(n: int) -> bool:
	return _send(Command.CHEAT_SET_STARS, [clampi(n, 1, 5)] as Array[int])


## The one door to the sim: nothing is queued while the setting is off.
func _send(kind: int, args: Array[int]) -> bool:
	if not CheatSettings.is_enabled() or tower == null:
		return false
	return tower.enqueue(Command.make(tower.tick + 1, kind, args))


func _process(_delta: float) -> void:
	if panel.visible and tower != null:
		_sync()


func _sync() -> void:
	if tower == null:
		return
	_syncing = true
	_unlock_box.button_pressed = tower.unlock_all
	_stars_box.select(clampi(tower.stars, 1, 5) - 1)
	_syncing = false


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if KeyBindings.is_key(key, "cheats"):
		if CheatSettings.is_enabled():
			toggle()
			get_viewport().set_input_as_handled()
	elif key.keycode == KEY_ESCAPE and is_open():
		close()
		get_viewport().set_input_as_handled()
