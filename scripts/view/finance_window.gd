class_name FinanceWindow
extends CanvasLayer
## The finance window (5.10): income and costs by kind for the current and the last few
## quarters, built from the ledger through Finance. T or a click on the money display toggles it;
## Esc closes it. View only: it reads the sim and never writes to it.

const TowerSim := preload("res://scripts/sim/tower.gd")
const FinanceScript := preload("res://scripts/sim/finance.gd")
const HudScript := preload("res://scripts/view/hud.gd")

const QUARTERS_SHOWN := 4  ## The current quarter and the three before it.
const HOTKEY := KEY_T

var tower: TowerSim = null
var panel: InfoPanel
var _open: bool = false
var _shown_tick: int = -1


func _init() -> void:
	layer = 6
	panel = InfoPanel.new()
	panel.name = "FinancePanel"
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.offset_left = 16.0
	panel.offset_right = 16.0
	add_child(panel)


func bind(tower_value: TowerSim) -> void:
	tower = tower_value


func is_open() -> bool:
	return _open


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func open() -> void:
	if tower == null:
		return
	_open = true
	_refresh()


func close() -> void:
	_open = false
	panel.visible = false


## The window text for the quarters up to the current one, newest first. Each quarter lists its
## non-zero kinds and the net change; the last line is the balance.
static func lines_for(tower_value: TowerSim) -> Array[String]:
	var lines: Array[String] = []
	var current := FinanceScript.quarter_of(tower_value.tick)
	for quarter in range(current, maxi(current - QUARTERS_SHOWN, -1), -1):
		lines.append("%s%s" % [FinanceScript.quarter_label(quarter), " (this quarter)" if quarter == current else ""])
		var sums := FinanceScript.totals(tower_value.ledger, quarter)
		for kind in FinanceScript.KINDS:
			if sums.has(kind) and int(sums[kind]) != 0:
				lines.append("  %s: %s" % [FinanceScript.LABELS[kind], HudScript.format_money(int(sums[kind]))])
		lines.append("  Net: %s" % HudScript.format_money(FinanceScript.net(tower_value.ledger, quarter)))
	lines.append("Balance: %s" % HudScript.format_money(tower_value.ledger.balance))
	return lines


func _process(_delta: float) -> void:
	if _open and tower != null and tower.tick != _shown_tick:
		_refresh()


func _refresh() -> void:
	_shown_tick = tower.tick
	panel.show_info("Finances", lines_for(tower))


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if KeyBindings.is_key(key, "finance"):
		toggle()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_ESCAPE and _open:
		close()
		get_viewport().set_input_as_handled()
