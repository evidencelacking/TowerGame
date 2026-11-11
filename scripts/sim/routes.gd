class_name Routes
extends RefCounted
## Route finder (3.5): walking along built floors and taking stairs, at most 4 stairs a trip.
## Pure and deterministic: reads the tower, changes nothing, integers only.
##
## A trip is a list of legs. Walking along a floor costs its distance; a stairs segment joins
## floor N and the floor above and costs STAIRS_COST. Walking over a ground-lobby cell starts a
## new leg and resets the stairs count (V). Elevators are a seam for later (ELEVATOR leg kind,
## not produced yet). Stairs are entered at their left column (unverified choice).
## Ties are broken by the lowest cost, then the lowest state index, so equal runs agree.

const GridScript := preload("res://scripts/sim/grid.gd")
const FloorsScript := preload("res://scripts/sim/floors.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")

const OK := 0
const BAD_FLOOR := 10  ## Start or goal is not a real floor number.
const NO_FLOOR := 40  ## Start or goal has no floor under it.
const NO_ROUTE := 41  ## No way there, even with unlimited stairs.
const TOO_MANY_STAIRS := 42  ## A way exists, but needs more than MAX_STAIRS stairs in one leg.

const WALK := 1  ## Leg kinds. Fields: kind, floor, from_x, to_x, to_floor.
const STAIRS := 2
const ELEVATOR := 3  ## Reserved for the elevator milestone.

const MAX_STAIRS := 4  ## M (V says 3, F's 21 is capacity).
const STAIRS_COST := 10  ## Walking-column equivalent of one stairs segment.

const _INF := 1 << 40


## Finds a route from (from_floor, from_x) to (to_floor, to_x). Returns {"reason", "legs"}:
## reason is OK or a refusal code, legs is an Array of Dictionary (empty if refused or if the
## start is the goal).
static func find(floors: FloorsScript, rooms: RoomsScript, grid: GridScript, from_floor: int, from_x: int, to_floor: int, to_x: int) -> Dictionary:
	var result := {"reason": OK, "legs": []}
	if not GridScript.is_valid_floor(from_floor) or not GridScript.is_valid_floor(to_floor):
		result["reason"] = BAD_FLOOR
		return result
	if not floors.has_floor(from_floor, from_x) or not floors.has_floor(to_floor, to_x):
		result["reason"] = NO_FLOOR
		return result
	# Nodes: 0 start, 1 goal, then a lower and an upper node per stairs.
	var node_floor: Array[int] = [from_floor, to_floor]
	var node_x: Array[int] = [from_x, to_x]
	var seen: Dictionary = {}
	for floor_number in range(GridScript.FLOOR_MIN, GridScript.FLOOR_MAX + 1):
		if not GridScript.is_valid_floor(floor_number):
			continue
		var upper := RoomsScript.floor_above(floor_number)
		if upper == 0:
			continue
		for column in GridScript.WIDTH_UNITS:
			var id := grid.cell_at(floor_number, column)
			if id == GridScript.EMPTY or seen.has(id) or rooms.kind_of(id) != "stairs":
				continue
			seen[id] = true
			node_floor.append(floor_number)
			node_x.append(column)
			node_floor.append(upper)
			node_x.append(column)
	var count := node_floor.size()
	# Edges per node, in node order: [to, cost, is_stairs, resets_count].
	var edges: Array = []
	for i in count:
		edges.append([])
	for i in count:
		for j in count:
			if i == j or node_floor[i] != node_floor[j]:
				continue
			var low := mini(node_x[i], node_x[j])
			var high := maxi(node_x[i], node_x[j])
			var walkable := true
			var lobby := false
			for column in range(low, high + 1):
				if not floors.has_floor(node_floor[i], column):
					walkable = false
					break
				if floors.has_lobby_at(node_floor[i], column):
					lobby = true
			if walkable:
				edges[i].append([j, high - low, false, lobby])
	for k in range(2, count, 2):
		edges[k].append([k + 1, STAIRS_COST, true, false])
		edges[k + 1].append([k, STAIRS_COST, true, false])

	if not _search(node_floor, node_x, edges, result):
		# Tell "too many stairs" from "no way at all" with an unlimited reachability pass.
		result["reason"] = TOO_MANY_STAIRS if _reachable(edges, count) else NO_ROUTE
	return result


## Dijkstra over (node, stairs used) states. Fills result.legs and returns true when the goal is reached.
static func _search(node_floor: Array[int], node_x: Array[int], edges: Array, result: Dictionary) -> bool:
	var step := MAX_STAIRS + 1
	var states := node_floor.size() * step
	var dist: Array[int] = []
	var prev: Array[int] = []
	var done: Array[bool] = []
	dist.resize(states)
	prev.resize(states)
	done.resize(states)
	dist.fill(_INF)
	prev.fill(-1)
	done.fill(false)
	dist[0] = 0
	var goal_state := -1
	while true:
		var best := -1
		var best_dist := _INF
		for s in states:
			if not done[s] and dist[s] < best_dist:
				best_dist = dist[s]
				best = s
		if best == -1:
			break
		done[best] = true
		var node := best / step
		var used := best % step
		if node == 1:
			goal_state = best
			break
		for edge: Array in edges[node]:
			var next_used := used
			if edge[2]:
				next_used += 1
				if next_used > MAX_STAIRS:
					continue
			elif edge[3]:
				next_used = 0
			var next_state: int = (edge[0] as int) * step + next_used
			var next_dist: int = best_dist + (edge[1] as int)
			if next_dist < dist[next_state]:
				dist[next_state] = next_dist
				prev[next_state] = best
	if goal_state == -1:
		return false
	var path: Array[int] = []
	var cursor := goal_state
	while cursor != -1:
		path.push_front(cursor / step)
		cursor = prev[cursor]
	var legs: Array = []
	for n in range(1, path.size()):
		var a: int = path[n - 1]
		var b: int = path[n]
		if node_floor[a] == node_floor[b]:
			if node_x[a] != node_x[b]:
				legs.append({"kind": WALK, "floor": node_floor[a], "from_x": node_x[a], "to_x": node_x[b], "to_floor": node_floor[a]})
		else:
			legs.append({"kind": STAIRS, "floor": node_floor[a], "from_x": node_x[a], "to_x": node_x[b], "to_floor": node_floor[b]})
	result["legs"] = legs
	return true


## True when node 1 can be reached from node 0 with any number of stairs.
static func _reachable(edges: Array, count: int) -> bool:
	var seen: Array[bool] = []
	seen.resize(count)
	seen.fill(false)
	var queue: Array[int] = [0]
	seen[0] = true
	while not queue.is_empty():
		var node: int = queue.pop_front()
		if node == 1:
			return true
		for edge: Array in edges[node]:
			if not seen[edge[0]]:
				seen[edge[0]] = true
				queue.append(edge[0])
	return false
