extends Node
## Entry scene. For now it only shows a sky-colour background.

const SKY := Color(0.53, 0.78, 0.95)

## The tower the HUD's SimDriver steps: the view must draw this one, not a copy.
@onready var _tower: Tower = $Hud/SimDriver.tower


func _ready() -> void:
	RenderingServer.set_default_clear_color(SKY)
	# Demo content until building commands exist (refs #6).
	for i in 20:
		_tower.grid.place(i + 1, 1 + i % 8, 10 + (i * 7) % 60, 4 + i % 5)
	_tower.grid.place(100, -2, 20, 12)
	# Debug switch (#156): `python tools/play.py -- --unlock-all`. Off unless asked for.
	if "--unlock-all" in OS.get_cmdline_user_args():
		_tower.enqueue(Tower.Command.make(_tower.tick + 1, Tower.Command.DEBUG_UNLOCK_ALL, [1] as Array[int]))
	var renderer: TowerRenderer = $TowerRenderer
	renderer.set_tower(_tower)
	($PlacementGhost as PlacementGhost).set_tower(_tower)
	($MessageLog as MessageLog).set_tower(_tower)
	($Toolbar as Toolbar).bind($PlacementGhost as PlacementGhost)
	var person_window := PersonWindow.new()
	person_window.name = "PersonWindow"
	add_child(person_window)
	person_window.bind(_tower, $PlacementGhost as PlacementGhost)
	var room_window := RoomWindow.new()
	room_window.name = "RoomWindow"
	add_child(room_window)
	room_window.bind(_tower, $PlacementGhost as PlacementGhost)
	var finance_window := FinanceWindow.new()
	finance_window.name = "FinanceWindow"
	add_child(finance_window)
	finance_window.bind(_tower)
	var money: Label = $Hud.get_node("%MoneyLabel")
	money.mouse_filter = Control.MOUSE_FILTER_STOP
	money.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			finance_window.toggle())
