extends RefCounted
## The tower news (12.4): life stories (LifeEvents) and notable tower events (Messages) merged into one
## newest-first list of short sentences with names, each with a click target. Reads the sim only.
## An item is {"tick", "text", "people": Array[int] of person ids, "room": room id or -1, "floor": floor or 0}.

const LifeScript := preload("res://scripts/sim/life.gd")
const Msg := preload("res://scripts/sim/messages.gd")
const MessageLogScript := preload("res://scripts/view/message_log.gd")
const VC := preload("res://scripts/view/view_consts.gd")

## Message codes that make the news, and what their args say: "floor" (b is a floor), "floor_a" (a is a
## floor), "room" (a is a room id), "none" (no place).
const TOWER_STORIES := {
	Msg.FRIEND_ARRIVED: "floor", Msg.FIRE_STARTED: "floor", Msg.FIRE_OUT: "floor", Msg.ROOM_BURNED: "floor",
	Msg.VIP_ARRIVED: "room", Msg.VIP_GOOD: "room", Msg.VIP_BAD: "room",
	Msg.STAR_PROMOTED: "none", Msg.THREAT_NOTICE: "none", Msg.THREAT_FOUND: "floor_a", Msg.THREAT_EXPLODED: "floor_a",
}


static func _floor_name(floor_number: int) -> String:
	return "B%d" % -floor_number if floor_number < 0 else str(floor_number)


## The newest `limit` items, newest first.
static func latest(tower: Object, limit: int) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var n: int = tower.life.story_count() - 1
	while n >= 0 and items.size() < limit:
		items.append(life_item(tower, n))
		n -= 1
	var i: int = tower.messages.count() - 1
	var kept := 0
	while i >= 0 and kept < limit:  # messages are oldest first: walk back and stop once enough
		var item := message_item(tower, tower.messages.entry(i))
		if not item.is_empty():
			items.append(item)
			kept += 1
		i -= 1
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["tick"] > b["tick"])
	return items.slice(0, limit)


## Story n of the life log as an item. The sentence names the people, and adds the floor when known.
static func life_item(tower: Object, n: int) -> Dictionary:
	var entry: Array[int] = tower.life.story(n)
	var text: String = tower.life.describe(n, tower.names)
	var run: Array[int] = tower.grid.run_of(entry[4]) if entry[4] >= 0 else ([] as Array[int])
	var floor_number := 0 if run.is_empty() else run[0]
	if floor_number != 0:
		text += " on floor %s" % _floor_name(floor_number)
	var people: Array[int] = [entry[2]]
	if entry[3] >= 0 and (entry[1] == LifeScript.COUPLE or entry[1] == LifeScript.MOVE_IN):
		people.append(entry[3])
	return {"tick": entry[0], "text": text, "people": people, "room": entry[4], "floor": floor_number}


## A message entry [tick, code, a, b] as an item, or an empty Dictionary when it is not news.
static func message_item(tower: Object, entry: Array[int]) -> Dictionary:
	if not TOWER_STORIES.has(entry[1]):
		return {}
	var room := -1
	var floor_number := 0
	match TOWER_STORIES[entry[1]]:
		"floor": floor_number = entry[3]
		"floor_a": floor_number = entry[2]
		"room":
			room = entry[2]
			var run: Array[int] = tower.grid.run_of(room)
			floor_number = 0 if run.is_empty() else run[0]
	return {"tick": entry[0], "text": MessageLogScript.describe(entry[1], entry[2], entry[3]), "people": [] as Array[int], "room": room, "floor": floor_number}


## The newest `limit` stories that involve this person, newest first, as text.
static func stories_for(tower: Object, id: int, limit: int) -> Array[String]:
	var out: Array[String] = []
	var n: int = tower.life.story_count() - 1
	while n >= 0 and out.size() < limit:
		var item := life_item(tower, n)
		if (item["people"] as Array).has(id):
			out.append(item["text"])
		n -= 1
	return out


## Where the camera goes for an item that is not about a person: the middle of its room, else its floor
## (x is -1.0 then: keep the current column), else Vector2.INF.
static func place_of(tower: Object, item: Dictionary) -> Vector2:
	var room: int = item["room"]
	var run: Array[int] = tower.grid.run_of(room) if room >= 0 else ([] as Array[int])
	if not run.is_empty():
		return Vector2((run[1] + run[2] / 2.0) * VC.CELL_W, (VC.floor_to_row(run[0]) + 0.5) * VC.CELL_H)
	var floor_number: int = item["floor"]
	if floor_number != 0:
		return Vector2(-1.0, (VC.floor_to_row(floor_number) + 0.5) * VC.CELL_H)
	return Vector2.INF
