class_name StarWindow
extends CanvasLayer
## The goals panel (#374, was the star progress window #375): click the star rating in the top bar or
## press G to open it. Three sections: what the next star needs (current / needed, ticked when met),
## the open demands with what is short, and the active events (time left, "If ignored:") with the VIP
## state. Esc, G or a second click closes it. View only: it reads the sim and never writes to it.

const TowerSim := preload("res://scripts/sim/tower.gd")
const StarRulesScript := preload("res://scripts/sim/star_rules.gd")
const DemandsScript := preload("res://scripts/sim/demands.gd")
const HudScript := preload("res://scripts/view/hud.gd")
const EventWindowScript := preload("res://scripts/view/event_window.gd")
const HotelScript := preload("res://scripts/sim/hotel.gd")
const VipScript := preload("res://scripts/sim/vip.gd")

const MARK_OK := "[OK]"
const MARK_NO := "[X]"

var tower: TowerSim = null
var panel: InfoPanel
var _open: bool = false
var _shown_tick: int = -1


## 1840 as "1,840".
static func group(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	for k in digits.length():
		if k > 0 and (digits.length() - k) % 3 == 0:
			out += ","
		out += digits[k]
	return ("-" if n < 0 else "") + out


## The panel lines for a tower: the next star's requirements, the open demands, then the active
## events. Pure: reads the sim, changes nothing.
static func lines_for(t: Object) -> Array[String]:
	var lines: Array[String] = []
	lines.append_array(star_lines(t))
	lines.append("")
	lines.append_array(demand_lines(t))
	lines.append("")
	lines.append_array(event_lines(t))
	return lines


## A heading then one "[OK] text" or "[X] text" per requirement of the next star, with progress.
static func star_lines(t: Object) -> Array[String]:
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
			"population": text = "Population %s / %s" % [group(have), group(int(need))]
			"security": text = "Security offices %d / %d" % [have, int(need)]
			"suites": text = "Suites %d / %d" % [have, int(need)]
			"metro": text = "Metro stations %d / %d" % [have, int(need)]
			"demands_met":
				var open_names := open_demand_names(t.demands)
				text = "No open demands" if open_names.is_empty() else "Open demands: " + ", ".join(open_names)
			"vip_good":
				var verdict: String = "good" if ok else ("bad, awaiting another visit" if t.vip.verdict() == VipScript.BAD else "pending")
				text = "VIP verdict: " + verdict
			_: text = "%s: need %s" % [field, str(need)]
		lines.append("%s %s" % [MARK_OK if ok else MARK_NO, text])
	return lines


## One line per open demand saying what is short, or a line saying there are none.
static func demand_lines(t: Object) -> Array[String]:
	var lines: Array[String] = ["Open demands:"]
	var counts: Dictionary = {}
	for room: int in t.rooms.room_ids():
		var kind: String = t.rooms.kind_of(room)
		counts[kind] = int(counts.get(kind, 0)) + 1
	var offices: int = counts.get("office", 0)
	var suites: int = counts.get("hotel_suite", 0)
	var any := false
	for id: int in DemandsScript.IDS:
		if not t.demands.is_open(id):
			continue
		any = true
		match id:
			DemandsScript.SECURITY:
				lines.append("Security: build a security office (0 / 1)")
			DemandsScript.SUITE:
				lines.append("Suites: %d / %d hotel suites" % [suites, DemandsScript.SUITES_FOR_STAR_4])
			DemandsScript.MEDICAL:
				var need_med := (offices + DemandsScript.OFFICES_PER_MEDICAL - 1) / DemandsScript.OFFICES_PER_MEDICAL
				lines.append("Medical: %d / %d medical centres for %d offices" % [int(counts.get("medical", 0)) + int(counts.get("emergency_room", 0)), need_med, offices])
			DemandsScript.RECYCLING:
				lines.append("Recycling: " + ("build a recycling centre" if int(counts.get("recycling", 0)) == 0 else "rubbish is overflowing, add recycling capacity"))
			DemandsScript.PARKING:
				lines.append("Parking: %d of %d spaces needed" % [Parking.working_spaces(t.rooms, t.grid), Parking.needed(offices, suites)])
	if not any:
		lines.append("None")
	return lines


## One block per open event (title, time left, "If ignored:"), then the VIP state.
static func event_lines(t: Object) -> Array[String]:
	var lines: Array[String] = ["Active events:"]
	for entry: Dictionary in EventWindowScript.describe(t):
		lines.append("%s: %s" % [entry["title"], entry["time"]])
		if str(entry["ignored"]) != "":
			lines.append("  If ignored: " + str(entry["ignored"]))
	lines.append(vip_line(t))
	return lines


## The VIP state: a visit in progress, the days until the next one may come, or why none can.
static func vip_line(t: Object) -> String:
	var vip: VipScript = t.vip
	if vip.is_visiting():
		return "VIP visit in progress: the verdict comes at 10:00 am"
	if vip.is_good():
		return "VIP: the last visit went well"
	if t.stars < VipScript.VISIT_STARS:
		return "VIP: none comes before %d stars" % VipScript.VISIT_STARS
	var days: int = vip.next_day() - HotelScript.night_of(t.clock)
	if days > 0:
		return "VIP: the next visit may come in %d day%s" % [days, "" if days == 1 else "s"]
	return "VIP: a visit may start any evening from 6:00 pm if a suite is ready"


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
	panel.show_info("Goals (stars now %d)" % tower.stars, lines_for(tower))


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if _open and key.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
	elif KeyBindings.is_key(key, "stars") and not key.ctrl_pressed and not key.alt_pressed and not (get_viewport().gui_get_focus_owner() is LineEdit):
		toggle()
		get_viewport().set_input_as_handled()
