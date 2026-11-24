class_name Alerts
extends RefCounted
## The alert list (M9 9.8, #223): what needs the player's eye, published by the sim for any view to read. A pure
## read of state that already exists, so it saves nothing, hashes nothing and draws nothing. The overview map
## (10.4) reuses it. Integers only.
##
## An alert is [kind, floor, state, ref]:
##   kind  FIRE (a room burning), THREAT (a bomb notice or search) or EVENT (any other open event card);
##   floor the floor to look at, or 0 for none (a threat's device floor is secret, so it never says);
##   state OPEN (a card awaits the player's choice) or ACTIVE (a fire burns, a search runs);
##   ref   the room id for a fire, the event kind id for a card, 0 for a running threat.
## Order: open cards oldest first (a fire's own card carries no floor, so the burning rooms speak for it), then
## burning rooms, then a running threat whose card is already answered, then one alert per floor that holds a wet room (a
## burst pipe, #472: floor, ACTIVE, 0) and the stalled car (#473: its floor, ACTIVE, its shaft id). The festival (#474) is the
## open card on the lobby floor. Problems that are not yet sim state
## (an unreached guest, pests) are left out.

const EventsScript := preload("res://scripts/sim/events.gd")
const FireScript := preload("res://scripts/sim/fire.gd")
const ThreatScript := preload("res://scripts/sim/threat.gd")

const FIRE := 1
const THREAT := 2
const EVENT := 3
const PIPE := 4  ## A floor with a wet room.
const STALL := 5  ## A stalled elevator car.

const OPEN := 0
const ACTIVE := 1


## The alerts of a tower right now. `t` is the Tower: its events, fire, threat, rooms and grid are read.
static func list(t: Object) -> Array[Array]:
	var out: Array[Array] = []
	var threat_card := false
	for event: Array in t.events.open_events():
		if event[1] == FireScript.KIND:
			continue  # the burning rooms below say where
		var kind := THREAT if event[1] == ThreatScript.KIND else EVENT
		threat_card = threat_card or kind == THREAT
		out.append([kind, event[2], OPEN, event[1]])
	for room: int in t.fire.burning_rooms():
		var floors: Array[int] = t.rooms.floors_of(t.grid, room)
		out.append([FIRE, floors[0] if not floors.is_empty() else 0, ACTIVE, room])
	if t.threat.is_active() and not threat_card:
		out.append([THREAT, 0, ACTIVE, 0])
	for floor_number: int in t.pipe.wet_floors(t.grid):
		out.append([PIPE, floor_number, ACTIVE, 0])
	var stalled: Array[int] = t.stall.stalled_car()
	if not stalled.is_empty():
		out.append([STALL, stalled[1], ACTIVE, stalled[0]])
	return out


## What an alert is called, in plain words.
static func label_of(alert: Array, t: Object) -> String:
	match alert[0]:
		FIRE:
			return "Fire"
		THREAT:
			return "Threat"
		PIPE:
			return "Water damage"
		STALL:
			return "Stalled elevator"
	var def: Dictionary = t.events.kind_def(alert[3])
	return str(def.get("title", "Event"))
