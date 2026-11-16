extends RefCounted
## What the person window says (5.9), and which person a click picks. Reads the sim only.

const VC := preload("res://scripts/view/view_consts.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")

const BAND_NAMES: Array[String] = ["Calm", "Uneasy", "Angry"]
const OUTSIDE := "outside"
const PICK_RADIUS_PX := 14.0  ## How close, in screen pixels, a click must be to a figure.
const FEET_UP_PX := 3  ## A figure's feet sit this far above the bottom edge of its floor row.
const CENTER_UP_PX := 6  ## Its middle sits this far above its feet (the body is 7 px, the head above).


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


## The person at index i: {"id", "name", "from", "to", "stress", "band", "band_name", "renamed"}.
## From is the room they left (or are in); to is the room they are heading for.
static func describe(tower: Object, i: int) -> Dictionary:
	var people: PeopleScript = tower.people
	var here := people.location_of(i)
	if here == PeopleScript.NONE and people.trip_state(i) != PeopleScript.TRIP_IDLE:
		here = people.trip_from(i)
	var id := people.id_at(i)
	var band := people.stress_band(i)
	return {
		"id": id, "name": tower.names.name_of(id), "renamed": tower.names.is_renamed(id),
		"from": room_label(tower, here), "to": room_label(tower, people.goal_room(i)),
		"stress": people.stress_of(i), "band": band, "band_name": BAND_NAMES[band],
	}


static func lines_for(info: Dictionary) -> Array[String]:
	return [
		"From: %s" % info["from"],
		"To: %s" % info["to"],
		"Stress: %d (%s)" % [info["stress"], info["band_name"]],
	]


## Centre of a figure in world pixels (matches TowerRenderer._draw_people).
static func figure_center(figure: Dictionary) -> Vector2:
	var x: int = (figure["x"] as int) * VC.CELL_PX + VC.CELL_PX / 2
	var feet: int = (VC.floor_to_row(figure["floor"]) + 1) * VC.CELL_PX - FEET_UP_PX
	return Vector2(x, feet - CENTER_UP_PX)


## The id of the figure nearest to a world point within radius world pixels, or -1. Ties go to the
## lower id, so the pick never depends on drawing order.
static func pick(figures: Array[Dictionary], world: Vector2, radius: float) -> int:
	var best := -1
	var best_dist := radius * radius
	for figure: Dictionary in figures:
		var d := figure_center(figure).distance_squared_to(world)
		var id: int = figure["id"]
		if d < best_dist or (d == best_dist and best != -1 and id < best):
			best = id
			best_dist = d
	return best
