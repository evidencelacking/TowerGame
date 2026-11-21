class_name StarWindow
extends CanvasLayer
## Progress toward the next star (#375): click the star rating in the top bar to open it. One line
## per StarRules.REQUIREMENTS field of the next star, ticked or crossed from Tower.star_facts.
## Esc or a second click closes it. View only: it reads the sim and never writes to it.

const TowerSim := preload("res://scripts/sim/tower.gd")
const StarRulesScript := preload("res://scripts/sim/star_rules.gd")
const DemandsScript := preload("res://scripts/sim/demands.gd")
const HudScript := preload("res://scripts/view/hud.gd")

const MARK_OK := "[OK]"
const MARK_NO := "[X]"

var tower: TowerSim = null
var panel: InfoPanel
var _open: bool = false
var _shown_tick: int = -1


## The panel lines for a tower: a heading then one "[OK] text" or "[X] text" per requirement of the
## next star. Pure: reads star_facts and the demands, changes nothing.
static func lines_for(t: Object) -> Array[String]:
	var star: int = t.stars + 1
	var lines: Array[String] = []
	if not StarRulesScript.REQUIREMENTS.has(star):
		lines.append("Top star reached: no further requirements.")
		return lines
	var facts: Dictionary = t.star_facts()
	var row: Dictionary = StarRulesScript.REQUIREMENTS[star]
	lines.append("Needed for star %d:" % star)
	for field: String in row:
		var need: Variant = row[field]
		var ok := bool(facts.get(field, false)) if typeof(need) == TYPE_BOOL else int(facts.get(field, 0)) >= int(need)
		var have := int(facts.get(field, 0)) if typeof(need) != TYPE_BOOL else 0
		var text := ""
		match field:
			"population": text = "Population %d of %d" % [have, int(need)]
			"security": text = "Security offices %d of %d" % [have, int(need)]
			"suites": text = "Hotel suites %d of %d" % [have, int(need)]
			"metro": text = "Metro stations %d of %d" % [have, int(need)]
			"demands_met":
				var open_names := open_demand_names(t.demands)
				text = "No open demands" if open_names.is_empty() else "Open demands: " + ", ".join(open_names)
			"vip_good": text = "Last VIP visit went well"
			_: text = "%s: need %s" % [field, str(need)]
		lines.append("%s %s" % [MARK_OK if ok else MARK_NO, text])
	return lines


## The names of the open demands, by id order.
static func open_demand_names(demands: DemandsScript) -> Array[String]:
	var names: Array[String] = []
	for id: int in DemandsScript.IDS:
		if demands.is_open(id):
			names.append(HudScript.DEMAND_NAMES[id])
	return names


func _init() -> void:
	layer = 6
	panel = InfoPanel.new()
	panel.name = "StarPanel"
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.offset_top = 48.0
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


func _process(_delta: float) -> void:
	if _open and tower != null and tower.tick != _shown_tick:
		_refresh()


func _refresh() -> void:
	_shown_tick = tower.tick
	panel.show_info("Star progress (now %d)" % tower.stars, lines_for(tower))


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if _open and key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
