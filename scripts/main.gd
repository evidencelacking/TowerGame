extends Node
## Entry scene. For now it only shows a sky-colour background.

const ViewSettingsScript := preload("res://scripts/view/view_settings.gd")
const SKY := Color(0.53, 0.78, 0.95)

## The tower the HUD's SimDriver steps: the view must draw this one, not a copy.
@onready var _tower: Tower = $Hud/SimDriver.tower


func _ready() -> void:
	RenderingServer.set_default_clear_color(SKY)
	UiSkin.apply(ViewSettingsScript.detailed_graphics)  # the toolbar's _ready has loaded the saved setting
	var demo := DemoMode.active()
	if demo:
		# Demo mode (#262): a fresh tower with a huge balance, the top rating, everything unlocked.
		# The driver and HUD read the driver's tower, so swap it in before anything binds to it.
		$Hud/SimDriver.tower = Tower.new(0, DemoMode.FUNDS)
		_tower = $Hud/SimDriver.tower
		_tower.enqueue(Tower.Command.make(_tower.tick + 1, Tower.Command.DEBUG_UNLOCK_ALL, [1] as Array[int]))
		_tower.enqueue(Tower.Command.make(_tower.tick + 1, Tower.Command.DEBUG_SET_STARS, [DemoMode.STARS] as Array[int]))
	else:
		# Demo content until building commands exist (refs #6).
		for i in 20:
			_tower.grid.place(i + 1, 1 + i % 8, 10 + (i * 7) % 60, 4 + i % 5)
		_tower.grid.place(100, -2, 20, 12)
	# Debug switch (#156): `python tools/play.py -- --unlock-all`. Off unless asked for.
	if "--unlock-all" in OS.get_cmdline_user_args():
		_tower.enqueue(Tower.Command.make(_tower.tick + 1, Tower.Command.DEBUG_UNLOCK_ALL, [1] as Array[int]))
	var renderer: TowerRenderer = $TowerRenderer
	renderer.set_tower(_tower)
	var thoughts := ThoughtLayer.new()
	thoughts.name = "ThoughtLayer"
	add_child(thoughts)
	thoughts.bind(_tower, renderer)
	($PlacementGhost as PlacementGhost).set_tower(_tower)
	($MessageLog as MessageLog).set_tower(_tower)
	($Toolbar as Toolbar).bind($PlacementGhost as PlacementGhost)
	var banner := CanvasLayer.new()
	banner.set_script(preload("res://scripts/view/promotion_banner.gd"))
	banner.name = "PromotionBanner"
	add_child(banner)
	banner.bind(_tower)
	banner.unlocked.connect(($Toolbar as Toolbar).mark_new)
	var person_window := PersonWindow.new()
	person_window.name = "PersonWindow"
	add_child(person_window)
	person_window.bind(_tower, $PlacementGhost as PlacementGhost, $TowerCamera as TowerCamera)
	var room_window := RoomWindow.new()
	room_window.name = "RoomWindow"
	add_child(room_window)
	room_window.bind(_tower, $PlacementGhost as PlacementGhost)
	var news := NewsTicker.new()
	news.name = "NewsTicker"
	add_child(news)
	news.bind(_tower, $TowerCamera as TowerCamera, person_window, room_window)
	var elevator_window := ElevatorWindow.new()
	elevator_window.name = "ElevatorWindow"
	add_child(elevator_window)
	elevator_window.bind(_tower, $PlacementGhost as PlacementGhost)
	var event_window := EventWindow.new()
	event_window.name = "EventWindow"
	add_child(event_window)
	event_window.bind(_tower)
	var finance_window := FinanceWindow.new()
	finance_window.name = "FinanceWindow"
	add_child(finance_window)
	finance_window.bind(_tower)
	if not demo:  # Demo towers never write or read the normal save slots.
		$Hud/SimDriver.autosave_enabled = true
		var save_menu := SaveMenu.new()
		save_menu.name = "SaveMenu"
		add_child(save_menu)
		save_menu.bind($Hud/SimDriver)
	var sound := SoundSystem.new()  # view only: reads the tower and camera, plays whatever sound files it finds (#247)
	sound.name = "SoundSystem"
	add_child(sound)
	sound.bind($Hud/SimDriver as SimDriver, $TowerCamera as Camera2D)
	var money: Label = $Hud.get_node("%MoneyLabel")
	money.mouse_filter = Control.MOUSE_FILTER_STOP
	money.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			finance_window.toggle())
