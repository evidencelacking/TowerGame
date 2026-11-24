class_name Routes
extends RefCounted
## Route finder (3.5, 4.7): walking along built floors, taking stairs and elevators.
## Pure and deterministic: reads the tower, changes nothing, integers only.
##
## A trip is a list of legs. Walking along a floor costs its distance; a stairs segment joins
## floor N and the floor above and costs STAIRS_COST. Walking over a ground-lobby cell starts a
## new leg and resets the stairs count (V), and so does arriving by elevator at a lobby floor.
## An elevator leg rides one shaft between two of its stops (express shafts stop at lobbies and basements only).
## A trip rides at most two elevators and the transfer between them happens on a lobby floor
## (is_lobby_floor: the ground lobby and the sky lobbies): at most one transfer in a tower of 100 floors; a trip needing
## a second is refused as TOO_MANY_TRANSFERS and the walkers give up (Trips). Stairs are entered at their left column (unverified choice).
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
const HEAP_SHIFT := 1 << 24  ## Search states stay below this, so dist * HEAP_SHIFT + state orders by cost then state.


## Finds a route from (from_floor, from_x) to (to_floor, to_x). Returns {"reason", "legs"}:
## reason is OK or a refusal code, legs is an Array of Dictionary (empty if refused or if the
## start is the goal). staff routes ride service shafts only (no standard cars, no escalators);
## everyone else never rides a service shaft, even when it is the only link (6.1). waiting_set, when given, is
## {key: true} for every key of rooms.waiting_keys() as it stands now: a caller making many queries between car
## moves reads it once instead of once a query. reads_out, when given a PackedInt32Array, gets one entry for every car-waiting
## lookup the search made, as key * 2 + 1 if the key was in the waiting set and key * 2 if not: the answer is the same for
## any waiting set that agrees on those keys (the search reads nothing else that changes between car moves).
static func find(floors: FloorsScript, rooms: RoomsScript, grid: GridScript, from_floor: int, from_x: int, to_floor: int, to_x: int, staff: bool = false, waiting_set: Variant = null, reads_out: Variant = null) -> Dictionary:
	var result := {"reason": OK, "legs": []}
	if not GridScript.is_valid_floor(from_floor) or not GridScript.is_valid_floor(to_floor):
		result["reason"] = BAD_FLOOR
		return result
	if not floors.has_floor(from_floor, from_x) or not floors.has_floor(to_floor, to_x):
		result["reason"] = NO_FLOOR
		return result
	var cache := _static_graph(floors, rooms, grid, staff)
	var node_floor: Array[int] = cache["floor"]
	var node_x: Array[int] = cache["x"]
	var node_shaft: Array[int] = cache["shaft"]
	var node_esc: Array[bool] = cache["esc"]
	node_floor[0] = from_floor
	node_x[0] = from_x
	node_floor[1] = to_floor
	node_x[1] = to_x
	var count := node_floor.size()
	# Edges per node: [to, cost, kind (0 walk, 1 stairs, 2 elevator), resets_count], flat in packed rows. An elevator
	# edge holds only its rise: _run_search adds the base cost of its source node from the waiting cars. The cached
	# graph holds the rows between its own nodes; `extra` holds this query's edges to and from nodes 0 and 1 (and the
	# rows of 0 and 1 themselves). The order of a node's edges does not matter: they lead to different states.
	var extra: Dictionary = {}  # node -> row, for the few nodes with one; the rest have none
	var on_floor: Dictionary = cache["on_floor"]
	var row0 := PackedInt32Array()
	var row1 := PackedInt32Array()
	var seeds: Array[int] = []  # the cached nodes with a walk to the goal
	var zero_cost := false  # a walk of no columns from or to the query's own nodes
	var levels: Array[int] = [from_floor]
	if to_floor != from_floor:
		levels.append(to_floor)
	for level: int in levels:
		var counts := floors.span_counts(level)
		var unbuilt: PackedInt32Array = counts[0]
		var lobbies: PackedInt32Array = counts[1]
		var here: Array[int] = []
		if level == from_floor:
			here.append(0)
		if level == to_floor:
			here.append(1)
		var others: Array[int] = on_floor.get(level, [] as Array[int])
		for k: int in others:
			var row := PackedInt32Array()
			for i: int in here:
				var low := mini(node_x[i], node_x[k])
				var high := maxi(node_x[i], node_x[k])
				if unbuilt[high + 1] - unbuilt[low] == 0:
					zero_cost = zero_cost or high == low
					var resets := 1 if lobbies[high + 1] - lobbies[low] > 0 else 0
					row.append_array(PackedInt32Array([i, high - low, 0, resets]))
					if i == 0:
						row0.append_array(PackedInt32Array([k, high - low, 0, resets]))
					else:
						row1.append_array(PackedInt32Array([k, high - low, 0, resets]))
						seeds.append(k)
			if not row.is_empty():
				extra[k] = row
	if from_floor == to_floor:  # nodes 0 and 1 see each other
		var low := mini(from_x, to_x)
		var high := maxi(from_x, to_x)
		var counts := floors.span_counts(from_floor)
		var unbuilt: PackedInt32Array = counts[0]
		var lobbies: PackedInt32Array = counts[1]
		if unbuilt[high + 1] - unbuilt[low] == 0:
			zero_cost = zero_cost or high == low
			var resets := 1 if lobbies[high + 1] - lobbies[low] > 0 else 0
			row0.append_array(PackedInt32Array([1, high - low, 0, resets]))
			row1.append_array(PackedInt32Array([0, high - low, 0, resets]))
	extra[0] = row0
	extra[1] = row1
	var waiting: Dictionary = {}  # what car_waiting_at would say, from one pass over the cars
	if waiting_set != null:
		waiting = waiting_set
	else:
		for key: int in rooms.waiting_keys():
			waiting[key] = true

	var viable := _viability(cache, floors, seeds, to_floor)
	# A walk of no columns (a tie between a state and one it leads to) makes the pop order something other than (dist,
	# state) order, which the tie rule of the A* search relies on. With one at the query's own nodes the search is plain
	# Dijkstra: no estimate, no tie rule. With one between cached nodes it runs as A* and is repeated as plain
	# Dijkstra only if that walk would make Dijkstra pop out of order (see _run_search).
	var heuristic := PackedInt32Array()
	if zero_cost:
		heuristic.resize(count)
	else:
		heuristic = _heuristic(cache, to_floor, to_x)  # see _run_search
		var goal_rise := absi(GridScript.floor_to_index(from_floor) - GridScript.floor_to_index(to_floor))
		heuristic[0] = absi(from_x - to_x) + (goal_rise + 1 if goal_rise > 0 else 0)

	var reads: PackedInt32Array = reads_out if reads_out != null else PackedInt32Array()
	var found := _search(node_floor, node_x, node_shaft, node_esc, extra, floors, waiting, cache, viable, heuristic, not zero_cost, true, result, reads)
	if result.has("zero_hit"):  # it met a walk of no columns that Dijkstra would order differently: do it again as plain Dijkstra
		result.erase("zero_hit")
		var plain := PackedInt32Array()
		plain.resize(count)
		found = _search(node_floor, node_x, node_shaft, node_esc, extra, floors, waiting, cache, viable, plain, false, true, result, reads)
	if not found:
		# Tell the refusals apart: no way at all, a transfer rule, or the stairs limit.
		if not _reachable(extra, cache, count):
			result["reason"] = NO_ROUTE
		elif _search(node_floor, node_x, node_shaft, node_esc, extra, floors, waiting, cache, viable, heuristic, false, false, {}, reads):
			result["reason"] = TOO_MANY_TRANSFERS
		else:
			result["reason"] = TOO_MANY_STAIRS
	return result


## The part of the graph that does not depend on the query, cached on the Rooms (one per staff flag) until the floors,
## the room list or a shaft's stops change (#415). Returns {floor, x, shaft, esc, edges, on_floor}. Nodes 0 and 1 are
## placeholders the query fills in; edges hold no edge to them, and an elevator edge holds its rise only. A node's list
## ends with its elevator edges, `rides` counts them (the query's edges are prepended, so the tail is unchanged).
static func _static_graph(floors: FloorsScript, rooms: RoomsScript, grid: GridScript, staff: bool) -> Dictionary:
	var slot := 1 if staff else 0
	var key: Array[int] = [floors.get_instance_id(), floors.revision, rooms.layout_revision, grid.get_instance_id()]
	var held: Variant = rooms.route_cache[slot]
	if held != null and (held as Dictionary)["key"] == key:
		return held as Dictionary
	# Nodes: 0 start, 1 goal, then a lower and an upper node per stairs.
	var node_floor: Array[int] = [0, 0]
	var node_x: Array[int] = [0, 0]
	var node_shaft: Array[int] = [0, 0]
	var node_esc: Array[bool] = [false, false]
	for spot: Array in _stair_spots(rooms, grid):
		var esc: bool = spot[2]
		if staff and esc:
			continue  # staff use stairs and service cars, not escalators (6.1)
		var floor_number: int = spot[0]
		var column: int = spot[1]
		var upper := RoomsScript.floor_above(floor_number)
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
		if (rooms.kind_of(shaft) == "service_shaft") != staff:
			continue  # service shafts are staff only, and staff ride nothing else (6.1)
		for stop: int in rooms.stops_of(shaft):
			node_floor.append(stop)
			node_x.append(rooms.shaft_x(shaft))
			node_shaft.append(shaft)
			node_esc.append(false)
	var count := node_floor.size()
	var edges: Array = []
	for i in count:
		edges.append([])
	var on_floor: Dictionary = {}  # floor -> cached node indices on it (2 and up), ascending
	for i in range(2, count):
		if not on_floor.has(node_floor[i]):
			on_floor[node_floor[i]] = [] as Array[int]
		on_floor[node_floor[i]].append(i)
	for floor_number: int in on_floor:
		var nodes: Array[int] = on_floor[floor_number]
		var counts := floors.span_counts(floor_number)
		var unbuilt: PackedInt32Array = counts[0]
		var lobbies: PackedInt32Array = counts[1]
		for i in nodes:
			for j in nodes:
				if i == j:
					continue
				var low := mini(node_x[i], node_x[j])
				var high := maxi(node_x[i], node_x[j])
				if unbuilt[high + 1] - unbuilt[low] == 0:
					edges[i].append([j, high - low, 0, lobbies[high + 1] - lobbies[low] > 0])
	for k in range(2, stair_nodes, 2):
		var kind := 3 if node_esc[k] else 1
		var cost := ESCALATOR_COST if node_esc[k] else STAIRS_COST
		edges[k].append([k + 1, cost, kind, false])
		edges[k + 1].append([k, cost, kind, false])
	var walk_edges: Array[int] = []
	for i in count:
		walk_edges.append(edges[i].size())  # everything so far; the elevator edges are appended after
	var group_start := stair_nodes  # a shaft's stop nodes are contiguous, in stop order
	for i in range(stair_nodes, count):
		if node_shaft[i] != node_shaft[group_start]:
			group_start = i
		var j := group_start
		while j < count and node_shaft[j] == node_shaft[i]:
			if j != i:
				var rise := absi(GridScript.floor_to_index(node_floor[i]) - GridScript.floor_to_index(node_floor[j]))
				edges[i].append([j, ELEVATOR_COST_PER_FLOOR * rise, 2, floors.is_lobby_floor(node_floor[j])])
			j += 1
	var node_index: Array[int] = []  # each node's floor as a storage index, for the heuristic; nodes 0 and 1 are the query's
	for i in count:
		node_index.append(GridScript.floor_to_index(node_floor[i]))
	var walk_rows: Array = []  # per node, the same edges flat: [to, cost, kind, resets (0 or 1)] repeated, walking and stairs first
	var ride_rows: Array = []  # and its elevator edges, kept apart so a search can skip them
	for i in count:
		var walk_row := PackedInt32Array()
		var ride_row := PackedInt32Array()
		for n in edges[i].size():
			var edge: Array = edges[i][n]
			var flat := PackedInt32Array([edge[0], edge[1], edge[2], 1 if edge[3] else 0])
			if n >= walk_edges[i]:
				ride_row.append_array(flat)
			else:
				walk_row.append_array(flat)
		walk_rows.append(walk_row)
		ride_rows.append(ride_row)
	var rides: Array[int] = []  # how many elevator edges close each node's list: 0 off the shafts
	rides.resize(count)
	rides.fill(0)
	for i in range(stair_nodes, count):
		rides[i] = edges[i].size() - walk_edges[i]
	var states := count * (LEG_LIMIT + 1) * 4
	var dist: Array[int] = []
	var prev: Array[int] = []
	var done: Array[bool] = []
	dist.resize(states)
	prev.resize(states)
	done.resize(states)
	dist.fill(_INF)
	prev.fill(-1)
	done.fill(false)
	var built := {"dist": dist, "prev": prev, "done": done, "key": key, "floor": node_floor, "x": node_x, "shaft": node_shaft, "esc": node_esc, "edges": edges, "on_floor": on_floor, "rides": rides, "viable": {}, "heuristic": {}, "index": node_index, "walk_rows": walk_rows, "ride_rows": ride_rows}
	rooms.route_cache[slot] = built
	return built


## Which floors and columns a walker starting at (from_floor, from_x) can stand on: the start and every stairs, escalator
## and shaft node a route reaches within the same rules as find (stairs limit, transfers). Returns floor -> Array of
## columns, empty when the start is not on a built floor. A cell is the goal of an OK find exactly when it is built and
## some column in the map is walkable to it on its floor, see map_reaches. One search for every target (#415): reaching a
## state does not depend on its cost, so this agrees with a find per target.
static func reach_map(floors: FloorsScript, rooms: RoomsScript, grid: GridScript, from_floor: int, from_x: int) -> Dictionary:
	var map: Dictionary = {}
	if not GridScript.is_valid_floor(from_floor) or not floors.has_floor(from_floor, from_x):
		return map
	var cache := _static_graph(floors, rooms, grid, false)
	var node_floor: Array[int] = cache["floor"]
	var node_x: Array[int] = cache["x"]
	node_floor[0] = from_floor
	node_x[0] = from_x
	var edges: Array = (cache["edges"] as Array).duplicate()
	var counts := floors.span_counts(from_floor)
	var unbuilt: PackedInt32Array = counts[0]
	var lobbies: PackedInt32Array = counts[1]
	var list0: Array = []
	for k: int in (cache["on_floor"] as Dictionary).get(from_floor, [] as Array[int]):
		var low := mini(from_x, node_x[k])
		var high := maxi(from_x, node_x[k])
		if unbuilt[high + 1] - unbuilt[low] == 0:
			var resets: bool = lobbies[high + 1] - lobbies[low] > 0
			list0.append([k, high - low, 0, resets])
			var prefix: Array = [[0, high - low, 0, resets]]
			prefix.append_array(edges[k])
			edges[k] = prefix
	edges[0] = list0
	edges[1] = []  # no goal node: nothing leads to it
	var step := LEG_LIMIT + 1
	var done: Array[bool] = cache["done"]
	var touched := PackedInt32Array([0])
	done[0] = true
	var head := 0
	while head < touched.size():  # touched grows by each new state and head catches up one a pass, so it ends
		var state := touched[head]
		head += 1
		var es := state % 4
		var node := state / 4 / step
		var used := (state / 4) % step
		var column: int = node_x[node]
		if not map.has(node_floor[node]):
			map[node_floor[node]] = []
		if not (map[node_floor[node]] as Array).has(column):
			(map[node_floor[node]] as Array).append(column)
		for edge: Array in edges[node]:
			var next_used := used
			var next_es := es
			if edge[2] == 1 or edge[2] == 3:
				next_used += STAIRS_WEIGHT if edge[2] == 1 else ESCALATOR_WEIGHT
				if next_used > LEG_LIMIT:
					continue
			elif edge[3]:
				next_used = 0
			if edge[2] == 2:
				if es == 0:
					next_es = 2 if edge[3] else 1
				elif es == 2 and floors.is_lobby_floor(node_floor[node]):
					next_es = 3
				else:
					continue
			var next_state: int = ((edge[0] as int) * step + next_used) * 4 + next_es
			if not done[next_state]:
				done[next_state] = true
				touched.append(next_state)
	for state in touched:
		done[state] = false
	return map


## True when a find to (to_floor, to_x) would say OK given reach_map's map: the cell is built and a reached column on
## its floor can walk to it.
static func map_reaches(floors: FloorsScript, map: Dictionary, to_floor: int, to_x: int) -> bool:
	if not GridScript.is_valid_floor(to_floor) or not floors.has_floor(to_floor, to_x) or not map.has(to_floor):
		return false
	var counts := floors.span_counts(to_floor)
	var unbuilt: PackedInt32Array = counts[0]
	for column: int in map[to_floor]:
		if unbuilt[maxi(column, to_x) + 1] - unbuilt[mini(column, to_x)] == 0:
			return true
	return false


## True when floor_number is a lobby floor, where elevator transfers are allowed: the ground
## lobby's floors and the sky lobby floors that have a lobby (Floors.is_lobby_floor).
static func is_lobby_floor(floors: FloorsScript, floor_number: int) -> bool:
	return floors.is_lobby_floor(floor_number)


## Every stairs and escalator as [floor, column, is_escalator], bottom floor first and left to
## right within a floor: the order a scan of the grid from the lowest floor up would find them.
## A scan visits each cell; this reads the placed rooms instead.
static func _stair_spots(rooms: RoomsScript, grid: GridScript) -> Array:
	var keyed: Dictionary = {}
	for id in rooms.room_ids():
		var kind := rooms.kind_of(id)
		if not RoomsScript.is_stair_kind(kind):
			continue
		var run := rooms.run_of(grid, id)
		if run.is_empty() or RoomsScript.floor_above(run[0]) == 0:
			continue
		keyed[GridScript.floor_to_index(run[0]) * GridScript.WIDTH_UNITS + run[1]] = [run[0], run[1], kind == "escalator"]
	var keys: Array = keyed.keys()
	keys.sort()
	var spots: Array = []
	for key: int in keys:
		spots.append(keyed[key])
	return spots


## The A* estimate of _run_search for each cached node (a copy, for the caller to set node 0, the start) towards the goal
## (to_floor, to_x): the columns to walk plus, on another floor, its rise plus one. Kept on the cached graph per goal.
static func _heuristic(cache: Dictionary, to_floor: int, to_x: int) -> PackedInt32Array:
	var held: Dictionary = cache["heuristic"]
	var key := to_floor * 100000 + to_x
	if held.has(key):
		return (held[key] as PackedInt32Array).duplicate()
	var node_index: Array[int] = cache["index"]
	var node_x: Array[int] = cache["x"]
	var estimate := PackedInt32Array()
	estimate.resize(node_index.size())
	var goal_index := GridScript.floor_to_index(to_floor)
	for n in range(2, node_index.size()):  # nodes 0 and 1 are the query's; 1, the goal, stays 0
		var rise := absi(node_index[n] - goal_index)
		estimate[n] = absi(node_x[n] - to_x) + (rise + 1 if rise > 0 else 0)
	held[key] = estimate
	return estimate.duplicate()


## The elevator edges of `node` worth trying towards the goal that `viable` (from _viability) is for: those to a lobby
## floor and those to a node a walker can still reach the goal from. The others are refused whatever the state.
static func _rides(viable: Dictionary, ride_rows: Array, node: int) -> PackedInt32Array:
	var kept: Array = viable["rides"]
	if kept[node] != null:
		return kept[node]
	var best: PackedInt32Array = viable["best"]
	var row: PackedInt32Array = ride_rows[node]
	var keep := PackedInt32Array()
	for at in range(0, row.size(), 4):
		if row[at + 3] == 1 or best[row[at]] >= 0:
			keep.append_array(row.slice(at, at + 4))
	kept[node] = keep
	return keep


## For a goal whose walkable neighbours (the cached nodes on its floor with a built span to it) are `seeds`: per node, the
## largest stairs count `used` with which a walker who may ride no more (elevator state 1 or 3) can still get there by
## walking and stairs, or -1 for none. A superset of the truth, so _run_search can drop those states without changing
## any route: such a state is never on a path to the goal, and it only ever feeds states that cannot reach it either.
## It ignores the query's start node (a walk through it is a walk on its floor, which every cached node there already
## has) and lets any walk on a floor with a lobby cell reset the count, which covers a walk through the start. It does
## not depend on the cars or the start, so it is kept on the cached graph under the seed set (most goals on a floor
## share one).
static func _viability(cache: Dictionary, floors: FloorsScript, seeds: Array[int], goal_floor: int) -> Dictionary:
	var held: Dictionary = cache["viable"]
	var key := str(goal_floor) + ":"
	for k: int in seeds:
		key += str(k) + ","
	if held.has(key):
		return held[key]
	var node_floor: Array[int] = cache["floor"]
	var edges: Array = cache["edges"]
	var rides: Array[int] = cache["rides"]
	var best := PackedInt32Array()
	best.resize(node_floor.size())
	best.fill(-1)
	var resets: Dictionary = {}  # floor -> whether a walk on it may cross a lobby cell
	var work: Array[int] = []
	for k: int in seeds:
		best[k] = LEG_LIMIT  # the last walk to the goal has no limit
		work.append(k)
	var head := 0
	while head < work.size():
		var q: int = work[head]
		head += 1
		var reach := best[q]
		var q_edges: Array = edges[q]
		for e in q_edges.size() - rides[q]:
			var edge: Array = q_edges[e]  # the graph is symmetric: this is also the edge into q
			var p: int = edge[0]
			var carry := reach
			if edge[2] == 0:
				var floor_number := node_floor[p]
				if not resets.has(floor_number):
					var lobbies: PackedInt32Array = floors.span_counts(floor_number)[1]
					resets[floor_number] = lobbies[lobbies.size() - 1] > 0
				if resets[floor_number]:
					carry = LEG_LIMIT
			else:
				carry = reach - (STAIRS_WEIGHT if edge[2] == 1 else ESCALATOR_WEIGHT)
			if carry > best[p]:
				best[p] = carry
				work.append(p)
	# Per node, the rides worth trying, filled in when first needed (see _rides): one to a floor that is not a lobby floor
	# lands in state 1 (or 3), which `best` refuses when no walk or stairs from there reaches the goal.
	var kept: Array = []
	kept.resize(best.size())
	var made := {"best": best, "rides": kept}
	held[key] = made
	return made


## Dijkstra over (node, stairs used, elevator state) states. Elevator state: 0 none ridden, 1 one
## ridden and landed off a lobby floor (no more rides), 2 one ridden and landed on a lobby floor
## (a second ride may start on a lobby floor), 3 two ridden. With limit_transfers false any number
## of rides is fine. Fills result.legs and returns true when the goal is reached.
## The state arrays come from the cached graph (scratch) and are put back after the search by resetting only the
## states it touched, so a query does not pay to fill them.
static func _search(node_floor: Array[int], node_x: Array[int], node_shaft: Array[int], node_esc: Array[bool], extra: Dictionary, floors: FloorsScript, waiting: Dictionary, scratch: Dictionary, viable: Dictionary, heuristic: PackedInt32Array, ties: bool, limit_transfers: bool, result: Dictionary, reads: PackedInt32Array) -> bool:
	var dist: Array[int] = scratch["dist"]
	var prev: Array[int] = scratch["prev"]
	var done: Array[bool] = scratch["done"]
	var touched := PackedInt32Array([0])
	var found := _run_search(node_floor, node_x, node_shaft, node_esc, extra, scratch["walk_rows"], scratch["ride_rows"], floors, waiting, dist, prev, done, viable, heuristic, ties, touched, limit_transfers, result, reads)
	for state in touched:
		dist[state] = _INF
		prev[state] = -1
		done[state] = false
	return found


static func _run_search(node_floor: Array[int], node_x: Array[int], node_shaft: Array[int], node_esc: Array[bool], extra: Dictionary, walk_rows: Array, ride_rows: Array, floors: FloorsScript, waiting: Dictionary, dist: Array[int], prev: Array[int], done: Array[bool], viable_set: Dictionary, heuristic: PackedInt32Array, ties: bool, touched: PackedInt32Array, limit_transfers: bool, result: Dictionary, reads: PackedInt32Array) -> bool:
	var none := PackedInt32Array()
	var step := LEG_LIMIT + 1
	var viable: PackedInt32Array = viable_set["best"]
	dist[0] = 0
	# A* with a heuristic that is a lower bound and consistent: the walking columns still to go (stairs and cars keep
	# the column, so at least the distance to the goal's) plus, when the goal is on another floor, its rise plus one
	# (a car costs 2 plus its rise, a stairs flight 10 and an escalator 2 a floor). Open states live in a binary heap of
	# (dist + heuristic) * HEAP_SHIFT + state, so the lowest estimate comes out first and ties come out lowest state first.
	# Dijkstra's routes are kept exactly: a state's predecessor is the one that would have been popped first (the lowest
	# dist, then state) of those that reach it at its final cost and come out before it, whatever order they are expanded
	# in; and the search runs on until nothing open could still reach the goal's cost, so every such predecessor is seen.
	var open := PackedInt64Array([heuristic[0] * HEAP_SHIFT])
	var goal_state := -1
	var goal_dist := 0
	while not open.is_empty():
		var top := _heap_pop(open)
		var best := top % HEAP_SHIFT
		var estimate := top / HEAP_SHIFT
		var es := best % 4
		var node := best / 4 / step
		var used := (best / 4) % step
		if goal_state != -1 and estimate > goal_dist:
			break  # nothing left that can reach the goal at its cost
		var best_dist := dist[best]
		if done[best] or estimate != best_dist + heuristic[node]:
			continue  # a stale entry: the state was reached cheaper since
		done[best] = true
		if node == 1:
			if goal_state == -1:
				goal_state = best  # the first to come out: the lowest dist, then the lowest state
				goal_dist = best_dist
			if not ties:
				break
			continue
		var base := 0  # a ride's boarding cost: a car waiting at this stop, or not
		if node_shaft[node] != 0:
			var wait_key := node_shaft[node] * 1000 + node_floor[node] + 100
			if waiting.has(wait_key):
				base = ELEVATOR_WAITING_COST
				reads.append(wait_key * 2 + 1)
			else:
				base = ELEVATOR_BASE_COST
				reads.append(wait_key * 2)
		# Which edge rows apply: the query's, the walking and stairs ones, and the rides when this state may start one.
		var may_ride := not limit_transfers or es == 0 or (es == 2 and floors.is_lobby_floor(node_floor[node]))
		var part := 0
		while part < 3:
			var row: PackedInt32Array
			if part == 0:
				row = extra.get(node, none)
			elif part == 1:
				row = walk_rows[node]
			elif may_ride:
				row = _rides(viable_set, ride_rows, node) if limit_transfers else ride_rows[node]
			else:
				break  # a ride from here is refused for every elevator edge
			part += 1
			var at := 0
			var end := row.size()
			while at < end:
				var target := row[at]
				var kind := row[at + 2]
				var next_used := used
				var next_es := es
				if kind == 1 or kind == 3:
					next_used += STAIRS_WEIGHT if kind == 1 else ESCALATOR_WEIGHT
					if next_used > LEG_LIMIT:
						at += 4
						continue
				elif row[at + 3] == 1:
					next_used = 0
				if kind == 2 and limit_transfers:
					if es == 0:
						next_es = 2 if row[at + 3] == 1 else 1
					else:  # es 2 on a lobby floor: the second ride
						next_es = 3
				if (next_es == 1 or next_es == 3) and limit_transfers and target >= 2 and next_used > viable[target]:
					at += 4
					continue  # no more rides, and walking and stairs from there never reach the goal: see _viability
				var next_state := (target * step + next_used) * 4 + next_es
				var next_dist := best_dist + row[at + 1] + (base if kind == 2 else 0)
				var known := dist[next_state]
				if ties and next_dist == best_dist and next_state < best and not done[next_state] and next_dist <= known:
					# A walk of no columns to a state that Dijkstra would pop next, ahead of its place in (dist, state)
					# order: the tie rule below assumes that order, so the caller repeats this as plain Dijkstra.
					result["zero_hit"] = true
					return false
				if next_dist < known:
					if known == _INF:
						touched.append(next_state)
					dist[next_state] = next_dist
					prev[next_state] = best
					_heap_push(open, (next_dist + heuristic[target]) * HEAP_SHIFT + next_state)
				elif ties and next_dist == known:
					var held := prev[next_state]  # the same cost by another way: the one popped first by Dijkstra wins
					if held != -1 and (best_dist < next_dist or best < next_state) and (best_dist < dist[held] or (best_dist == dist[held] and best < held)):
						prev[next_state] = best
				at += 4
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


static func _heap_push(heap: PackedInt64Array, key: int) -> void:
	heap.append(key)
	var at := heap.size() - 1
	while at > 0:
		var parent := (at - 1) / 2
		if heap[parent] <= key:
			break
		heap[at] = heap[parent]
		at = parent
	heap[at] = key


static func _heap_pop(heap: PackedInt64Array) -> int:
	var top := heap[0]
	var last := heap[heap.size() - 1]
	heap.resize(heap.size() - 1)
	var size := heap.size()
	if size > 0:
		var at := 0
		while true:
			var child := at * 2 + 1
			if child >= size:
				break
			if child + 1 < size and heap[child + 1] < heap[child]:
				child += 1
			if heap[child] >= last:
				break
			heap[at] = heap[child]
			at = child
		heap[at] = last
	return top


## True when node 1 can be reached from node 0 with any number of stairs.
static func _reachable(extra: Dictionary, cache: Dictionary, count: int) -> bool:
	var walk_rows: Array = cache["walk_rows"]
	var ride_rows: Array = cache["ride_rows"]
	var seen: Array[bool] = []
	seen.resize(count)
	seen.fill(false)
	var queue: Array[int] = [0]
	seen[0] = true
	while not queue.is_empty():
		var node: int = queue.pop_front()
		if node == 1:
			return true
		for row: PackedInt32Array in [extra.get(node, PackedInt32Array()), walk_rows[node], ride_rows[node]]:
			for at in range(0, row.size(), 4):
				if not seen[row[at]]:
					seen[row[at]] = true
					queue.append(row[at])
	return false
