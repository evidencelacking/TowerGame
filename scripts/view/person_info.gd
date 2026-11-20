extends RefCounted
## What the person window says (5.9), and which person a click picks. Reads the sim only.

const VC := preload("res://scripts/view/view_consts.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")
const NamesScript := preload("res://scripts/sim/names.gd")
const MoodScript := preload("res://scripts/sim/mood.gd")

const BAND_NAMES: Array[String] = ["Calm", "Uneasy", "Angry"]
const OUTSIDE := "outside"
const PICK_RADIUS_PX := 16.0  ## How close, in screen pixels, a click must be to a figure.
const FEET_UP_PX := 3  ## A figure's feet sit this far above the bottom edge of its floor row.
const CENTER_UP_PX := VC.FIGURE_H / 2  ## Its middle sits this far above its feet.


## "Office, floor 3", or "outside" for no room. Floors below ground read "B2".
static func room_label(tower: Object, room: int) -> String:
	if room == PeopleScript.NONE:
		return OUTSIDE
	var kind: String = tower.rooms.kind_of(room)
	var run: Array[int] = tower.grid.run_of(room)
	if kind == "" or run.is_empty():
		return OUTSIDE
	var floor_number := run[0]
	return "%s, floor %s" % [kind.capitalize().replace("_", " "), "B%d" % -floor_number if floor_number < 0 else str(floor_number)]


## The person at index i: {"id", "name", "partner", "mood", "mood_reasons", "age", "age_name", "title", "from", "to", "stress", "band", "band_name", "renamed"}.
## From is the room they left (or are in); to is the room they are heading for.
static func describe(tower: Object, i: int) -> Dictionary:
	var people: PeopleScript = tower.people
	var here := people.location_of(i)
	if here == PeopleScript.NONE and people.trip_state(i) != PeopleScript.TRIP_IDLE:
		here = people.trip_from(i)
	var id := people.id_at(i)
	var band := people.stress_band(i)
	var seed_value: int = tower.names.name_seed
	var kind: String = tower.rooms.kind_of(people.work_of(i)) if people.work_of(i) != PeopleScript.NONE else tower.rooms.kind_of(people.home_of(i))
	var age: int = tower.life.age_band(seed_value, id)
	var title: String = tower.life.title_for(seed_value, id, kind)
	var partner: int = tower.life.partner_of(id)
	return {
		"mood": people.mood_of(i), "mood_reasons": tower.mood_factors(i),
		"partner": tower.names.name_of(partner) if partner != -1 else "", "age": age, "age_name": NamesScript.BAND_NAMES[age], "title": title,
		"id": id, "name": tower.names.name_of(id), "renamed": tower.names.is_renamed(id),
		"from": room_label(tower, here), "to": room_label(tower, people.goal_room(i)),
		"stress": people.stress_of(i), "band": band, "band_name": BAND_NAMES[band],
	}


static func lines_for(info: Dictionary) -> Array[String]:
	var who: String = info["age_name"] if info["title"] == "" else "%s, %s" % [info["title"], info["age_name"].to_lower()]
	var lines: Array[String] = [
		who,
		"From: %s" % info["from"],
		"To: %s" % info["to"],
		"Stress: %d (%s)" % [info["stress"], info["band_name"]],
		mood_line(info),
	]
	if info["partner"] != "":
		lines.append("Partner: %s" % info["partner"])
	return lines


## "Mood: 62 (travel waits -17, room grade -25)": the mood and its two biggest reasons.
static func mood_line(info: Dictionary) -> String:
	var parts: Array[String] = []
	for factor: Array in info["mood_reasons"]:
		if parts.size() >= 2:
			break
		parts.append("%s %+d" % [MoodScript.REASON_NAMES[factor[0]], factor[1]])
	var text := "Mood: %d" % info["mood"]
	return text if parts.is_empty() else "%s (%s)" % [text, ", ".join(parts)]


## Centre of a figure in world pixels (matches TowerRenderer._draw_people, floor top row plus the feet offset).
static func figure_center(figure: Dictionary) -> Vector2:
	if figure.has("px"):  # resting on a recipe spot (activity_look.gd)
		return Vector2(figure["px"] + VC.FIGURE_W / 2.0, figure["pfeet"] - CENTER_UP_PX)
	var column: float = figure.get("fx", float(figure["x"]))  # moving figures carry fractional positions
	var row: float = figure.get("frow", float(VC.floor_to_row(figure["floor"])))
	var feet := (row + 1.0) * VC.CELL_H - FEET_UP_PX
	return Vector2(column * VC.CELL_W + VC.CELL_W / 2.0, feet - CENTER_UP_PX)


## The id of the figure nearest to a world point within radius world pixels, or -1. Ties go to the
## lower id, so the pick never depends on drawing order.
static func pick(figures: Array[Dictionary], world: Vector2, radius: float) -> int:
	var best := -1
	var best_dist := radius * radius
	for figure: Dictionary in figures:
		if figure.get("staff", false):
			continue
		var d := figure_center(figure).distance_squared_to(world)
		var id: int = figure["id"]
		if d < best_dist or (d == best_dist and best != -1 and id < best):
			best = id
			best_dist = d
	return best
