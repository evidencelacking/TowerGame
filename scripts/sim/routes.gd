class_name Routes
extends RefCounted
## Route finder (3.5, 4.7): walking along built floors, taking stairs and elevators.
## Pure and deterministic: reads the tower, changes nothing, integers only.
##
## A trip is a list of legs. Walking along a floor costs its distance; a stairs segment joins
## floor N and the floor above and costs STAIRS_COST. Walking over a ground-lobby cell starts a
## new leg and resets the stairs count (V), and so does arriving by elevator at a lobby floor.
## An elevator leg rides one shaft between two of its stops (express shafts take no cars yet).
## A trip rides at most two elevators and the transfer between them happens on a lobby floor
## (is_lobby_floor, the seam for sky lobbies). Stairs are entered at their left column (unverified choice).
##
## Preference (#96): escalator first (no waiting, at most MAX_ESCALATORS in a leg), then a car that
## is waiting (see Rooms.car_waiting_at), then stairs (at most MAX_STAIRS in a leg), then a car that
## is not waiting. It lives in the edge costs: an escalator segment costs ESCALATOR_COST, a ride
## from a floor with a waiting car costs ELEVATOR_WAITING_COST plus a little per floor, stairs cost
## STAIRS_COST a segment, and a ride with no car waiting costs ELEVATOR_BASE_COST plus the same.
## Stairs and escalators share one count per leg, weighted so 4 stairs or 7 escalators fill it.
## Ties are broken by the lowest cost, then the lowest state index, so equal runs agree.

const GridScript := preload("res://scripts/sim/grid.gd")
const FloorsScript := preload("res://scripts/sim/floors.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")

const OK := 0
const BAD_FLOOR := 10  ## Start or goal is not a real floor number.
const NO_FLOOR := 40  ## Start or goal has no floor under it.
const NO_ROUTE := 41  ## No way there, even with unlimited stairs.
const TOO_MANY_STAIRS := 42  ## A way exists, but needs more than MAX_STAIRS stairs in one leg.
const TOO_MANY_TRANSFERS := 43  ## A way exists, but needs a second transfer or one off a lobby floor.

const WALK := 1  ## Leg kinds. Fields: kind, floor, from_x, to_x, to_floor.
const STAIRS := 2
const ELEVATOR := 3  ## Fields: also shaft. from_x and to_x are the shaft's column.
const ESCALATOR := 4  ## Like STAIRS: joins floor N and the floor above.

const MAX_STAIRS := 4  ## M (V says 3, F's 21 is capacity).
const MAX_ESCALATORS := 7  ## M, I (V says 6).
const LEG_LIMIT := MAX_STAIRS * MAX_ESCALATORS  ## Weighted count a leg may use up.
const STAIRS_WEIGHT := MAX_ESCALATORS  ## Of LEG_LIMIT: 4 stairs fill a leg.
const ESCALATOR_WEIGHT := MAX_STAIRS  ## Of LEG_LIMIT: 7 escalators fill a leg.
const ESCALATOR_COST := 2  ## Walking-column equivalent of one escalator segment: never waits.
const ELEVATOR_WAITING_COST := 2  ## Guess: boarding a car that is already waiting; beats a flight of stairs.
const STAIRS_COST := 10  ## Walking-column equivalent of one stairs segment.
const ELEVATOR_BASE_COST := 20  ## Guess: walking-column equivalent of waiting for and boarding a car.
const ELEVATOR_COST_PER_FLOOR := 1  ## Guess: per floor ridden; a ride beats stairs from 3 floors up.
const MAX_ELEVATORS := 2  ## One transfer a trip (M).

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
	var node_shaft: Array[int] = [0, 0]
	var node_esc: Array[bool] = [false, false]
	var seen: Dictionary = {}
	for floor_number in range(GridScript.FLOOR_MIN, GridScript.FLOOR_MAX + 1):
		if not GridScript.is_valid_floor(floor_number):
			continue
		var upper := RoomsScript.floor_above(floor_number)
		if upper == 0:
			continue
		for column in GridScript.WIDTH_UNITS:
			var id := grid.cell_at(floor_number, column)
			if id == GridScript.EMPTY or seen.has(id) or not RoomsScript.is_stair_kind(rooms.kind_of(id)):
				continue
			seen[id] = true
			var esc := rooms.kind_of(id) == "escalator"
			node_esc.append(esc)
			node_esc.append(esc)
			node_floor.append(floor_number)
			node_x.append(column)
			node_floor.append(upper)
			node_x.append(column)
			node_shaft.append(0)
			node_shaft.append(0)
	var stair_nodes := node_floor.size()
	for shaft: int in rooms.shaft_ids():
		if rooms.kind_of(shaft) == "express_shaft":
			continue
		for stop: int in rooms.stops_of(shaft):
			node_floor.append(stop)
			node_x.append(rooms.shaft_x(shaft))
			node_shaft.append(shaft)
			node_esc.append(false)
	var count := node_floor.size()
	# Edges per node, in node order: [to, cost, kind (0 walk, 1 stairs, 2 elevator), resets_count].
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
				edges[i].append([j, high - low, 0, lobby])
	for k in range(2, stair_nodes, 2):
		var kind := 3 if node_esc[k] else 1
		var cost := ESCALATOR_COST if node_esc[k] else STAIRS_COST
		edges[k].append([k + 1, cost, kind, false])
		edges[k + 1].append([k, cost, kind, false])
	for i in range(stair_nodes, count):
		for j in range(stair_nodes, count):
			if i != j and node_shaft[i] == node_shaft[j]:
				var rise := absi(GridScript.floor_to_index(node_floor[i]) - GridScript.floor_to_index(node_floor[j]))
				var base := ELEVATOR_WAITING_COST if rooms.car_waiting_at(node_shaft[i], node_floor[i]) else ELEVATOR_BASE_COST
				edges[i].append([j, base + ELEVATOR_COST_PER_FLOOR * rise, 2, is_lobby_floor(floors, node_floor[j])])

	if not _search(node_floor, node_x, node_shaft, node_esc, edges, floors, true, result):
		# Tell the refusals apart: no way at all, a transfer rule, or the stairs limit.
		if not _reachable(edges, count):
			result["reason"] = NO_ROUTE
		elif _search(node_floor, node_x, node_shaft, node_esc, edges, floors, false, {}):
			result["reason"] = TOO_MANY_TRANSFERS
		else:
			result["reason"] = TOO_MANY_STAIRS
	return result


## True when floor_number is a lobby floor, where elevator transfers are allowed. Today that is
## the ground lobby's floors; sky lobbies join here later.
static func is_lobby_floor(floors: FloorsScript, floor_number: int) -> bool:
	var span := floors.lobby_span()
	return not span.is_empty() and floor_number >= 1 and floor_number <= span[2]


## Dijkstra over (node, stairs used, elevator state) states. Elevator state: 0 none ridden, 1 one
## ridden and landed off a lobby floor (no more rides), 2 one ridden and landed on a lobby floor
## (a second ride may start on a lobby floor), 3 two ridden. With limit_transfers false any number
## of rides is fine. Fills result.legs and returns true when the goal is reached.
static func _search(node_floor: Array[int], node_x: Array[int], node_shaft: Array[int], node_esc: Array[bool], edges: Array, floors: FloorsScript, limit_transfers: bool, result: Dictionary) -> bool:
	var step := LEG_LIMIT + 1
	var states := node_floor.size() * step * 4
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
	var open: Array[int] = [0]
	var goal_state := -1
	while not open.is_empty():
		var best := -1
		var best_dist := _INF
		var best_at := 0
		for k in open.size():
			var s: int = open[k]
			if dist[s] < best_dist or (dist[s] == best_dist and s < best):
				best_dist = dist[s]
				best = s
				best_at = k
		open.remove_at(best_at)
		done[best] = true
		var es := best % 4
		var node := best / 4 / step
		var used := (best / 4) % step
		if node == 1:
			goal_state = best
			break
		for edge: Array in edges[node]:
			var next_used := used
			var next_es := es
			if edge[2] == 1 or edge[2] == 3:
				next_used += STAIRS_WEIGHT if edge[2] == 1 else ESCALATOR_WEIGHT
				if next_used > LEG_LIMIT:
					continue
			elif edge[3]:
				next_used = 0
			if edge[2] == 2 and limit_transfers:
				if es == 0:
					next_es = 2 if edge[3] else 1
				elif es == 2 and is_lobby_floor(floors, node_floor[node]):
					next_es = 3
				else:
					continue
			var next_state: int = ((edge[0] as int) * step + next_used) * 4 + next_es
			var next_dist: int = best_dist + (edge[1] as int)
			if not done[next_state] and next_dist < dist[next_state]:
				if dist[next_state] == _INF:
					open.append(next_state)
				dist[next_state] = next_dist
				prev[next_state] = best
	if goal_state == -1:
		return false
	var path: Array[int] = []
	var cursor := goal_state
	while cursor != -1:
		path.push_front(cursor / 4 / step)
		cursor = prev[cursor]
	var legs: Array = []
	for n in range(1, path.size()):
		var a: int = path[n - 1]
		var b: int = path[n]
		if node_shaft[a] != 0 and node_shaft[a] == node_shaft[b]:
			legs.append({"kind": ELEVATOR, "floor": node_floor[a], "from_x": node_x[a], "to_x": node_x[b], "to_floor": node_floor[b], "shaft": node_shaft[a]})
		elif node_floor[a] == node_floor[b]:
			if node_x[a] != node_x[b]:
				legs.append({"kind": WALK, "floor": node_floor[a], "from_x": node_x[a], "to_x": node_x[b], "to_floor": node_floor[a]})
		else:
			legs.append({"kind": ESCALATOR if node_esc[a] else STAIRS, "floor": node_floor[a], "from_x": node_x[a], "to_x": node_x[b], "to_floor": node_floor[b]})
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
