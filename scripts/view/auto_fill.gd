extends RefCounted
## Auto-fill floor (#273), view side. For each floor a new item stands on, the empty cells between the
## item and the nearest floor on either side of that level are planned as ordinary floor spans, so no
## air is left beside a shaft, stairs or room. The ghost shows the cells and adds their price; a click
## sends them as BUILD_FLOOR commands before the item's own command. The sim is not changed.

const GridScript := preload("res://scripts/sim/grid.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const TowerSim := preload("res://scripts/sim/tower.gd")
const ViewSettings := preload("res://scripts/view/view_settings.gd")


## The spans to fill beside an item at columns x to x + width - 1 on the given floors (any order).
## Returns {"spans": [[floor, x_start, x_end], ...] bottom to top, "cost": dollars}. A gap whose cells
## would have nothing to rest on (counting the gaps planned on the floor below) is left out.
static func plan(t: TowerSim, levels: Array[int], x: int, width: int) -> Dictionary:
	var sorted: Array[int] = []
	sorted.assign(levels)
	sorted.sort_custom(func(a: int, b: int) -> bool: return GridScript.floor_to_index(a) < GridScript.floor_to_index(b))
	var pending := {}  # floor * 1000 + column -> true, cells planned so far
	var spans: Array = []
	var units := 0
	for level: int in sorted:
		for side: int in [-1, 1]:
			var gap := _gap(t, level, x, width, side)
			if gap.is_empty() or not _all_supported(t, level, gap[0], gap[1], pending):
				continue
			spans.append([level, gap[0], gap[1]])
			units += gap[1] - gap[0] + 1
			for column in range(gap[0], gap[1] + 1):
				pending[level * 1000 + column] = true
	return {"spans": spans, "cost": units * CatalogueScript.FLOOR_COST_PER_UNIT}


## [start, end] columns of the empty cells between the item and the nearest floor on one side
## (-1 left, 1 right) of its level, or [] when there is no floor on that side or no gap.
static func _gap(t: TowerSim, level: int, x: int, width: int, side: int) -> Array[int]:
	var none: Array[int] = []
	var edge := x - 1 if side < 0 else x + width
	var column := edge
	while column >= 0 and column < GridScript.WIDTH_UNITS and not t.floors.has_floor(level, column):
		column += side
	if column < 0 or column >= GridScript.WIDTH_UNITS or column == edge:
		return none
	var out: Array[int] = []
	if side < 0:
		out.assign([column + 1, edge])
	else:
		out.assign([edge, column - 1])
	return out


static func _all_supported(t: TowerSim, level: int, start: int, end: int, pending: Dictionary) -> bool:
	if level == 1:
		return true
	var below := RoomsScript.floor_above(level) if level < 0 else RoomsScript.floor_below(level)
	for column in range(start, end + 1):
		if not t.floors.has_floor(below, column) and not pending.has(below * 1000 + column):
			return false
	return true


## Adds the plan to a valid verdict: its cost, the spans in verdict["fill"], and a hint. A verdict
## that can no longer be paid becomes invalid. No-op when the setting is off or nothing is to fill.
static func apply(t: TowerSim, out: Dictionary, levels: Array[int], x: int, width: int) -> void:
	if not ViewSettings.auto_fill or not out["valid"]:
		return
	var planned := plan(t, levels, x, width)
	if (planned["spans"] as Array).is_empty():
		return
	out["fill"] = planned["spans"]
	out["cost"] = int(out["cost"]) + int(planned["cost"])
	var units: int = int(planned["cost"]) / CatalogueScript.FLOOR_COST_PER_UNIT
	var note := "Fills %d floor unit%s" % [units, "" if units == 1 else "s"]
	out["hint"] = note if out.get("hint", "") == "" else "%s. %s" % [out["hint"], note]
	if out["cost"] > t.ledger.balance:
		out["valid"] = false
		out["text"] = "Not enough money"
		if out.has("code"):
			out["code"] = RoomsScript.SHORT_OF_FUNDS
