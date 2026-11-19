extends RefCounted
## Joined suites (#276, step 1, view only): neighbouring rooms of one kind on one floor, all in use, draw as
## one space. The shared walls vanish and a suite recipe spans the joined width; figures sit on the suite's
## spots. Pure functions of the rooms' kinds, positions and use: nothing is saved, and the same tower in the
## same state always joins the same rooms. The simulation knows nothing of suites.

const RoomRecipes := preload("res://scripts/view/room_recipes.gd")

## Kinds that join: the ones with a suite recipe.
const KINDS: Array[String] = ["office", "restaurant", "fast_food", "retail"]


## Whether a kind can join its neighbours.
static func joins(kind: String) -> bool:
	return KINDS.has(kind) and RoomRecipes.has_suite(kind)


## Groups of two or more neighbours. entries is one Dictionary per room in floor-then-left-to-right order:
## {"key": the floor (any int unique to it), "x": left edge in px, "w": width in px, "kind": String,
## "in_use": bool}. A room joins the one before it when both are in use, of one joining kind, on one floor,
## and touching. Returns arrays of entry indexes, each in order; rooms with no neighbour appear in none.
static func groups(entries: Array) -> Array[Array]:
	var found: Array[Array] = []
	var current: Array[int] = []
	for i: int in entries.size():
		var entry: Dictionary = entries[i]
		var joined := false
		if not current.is_empty():
			var before: Dictionary = entries[current[current.size() - 1]]
			joined = before["key"] == entry["key"] and (before["x"] as int) + (before["w"] as int) == (entry["x"] as int) \
				and before["kind"] == entry["kind"] and (before["in_use"] as bool) and (entry["in_use"] as bool) and joins(entry["kind"] as String)
		if joined:
			current.append(i)
			continue
		if current.size() >= 2:
			found.append(current)
		current = [i]
	if current.size() >= 2:
		found.append(current)
	return found


## The left edge and total width in px of a group of entries.
static func span(entries: Array, group: Array[int]) -> Array[int]:
	var first: Dictionary = entries[group[0]]
	var last: Dictionary = entries[group[group.size() - 1]]
	return [first["x"] as int, (last["x"] as int) + (last["w"] as int) - (first["x"] as int)]


## Room ids that count as in use for joining: rooms with a tenant (staff on the books; for a shop, a renter),
## not who happens to be inside now, so a suite stays joined overnight and on weekends instead of
## splitting whenever its rooms empty.
static func tenanted_rooms(tower: Object) -> Dictionary:
	var out: Dictionary = {}
	for id: int in tower.rooms.room_ids():
		var kind: String = tower.rooms.kind_of(id)
		if not joins(kind):
			continue
		if (kind == "retail" and not tower.commerce.is_vacant(id)) or tower.people.workers_in(id) > 0:
			out[id] = true
	return out


## The entries groups() takes, from the renderer's room runs ([id, owning room, rect]) in floor-then-column
## order and the set of room ids in use.
static func entries_for(tower: Tower, runs: Array[Array], in_use: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for run: Array in runs:
		var rect: Rect2i = run[2]
		out.append({"key": rect.position.y, "x": rect.position.x, "w": rect.size.x, "kind": tower.rooms.kind_of(run[0] as int), "in_use": in_use.has(run[1])})
	return out
