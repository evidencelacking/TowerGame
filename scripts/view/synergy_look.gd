extends RefCounted
## The synergy overlay (#294): a view filter that tints each room by its net synergy, green for a boost to red
## for a harm, and, for the room under the cursor, draws faint links to the rooms that boost or harm it.
## Pure reading of the sim (scripts/sim/synergy.gd) and the grid: nothing here writes to the tower, and the
## same helpers serve Classic and Detailed, since the overlay paints in world pixels over either style's rooms.
##
## Net synergy of a room is the sum of what its neighbours do to it, in points: mood points, plus percent of a
## condo's sale price, plus percent of a shop's takings. Noise has its own rule (noise.gd) and is not folded in.

const SynergyScript := preload("res://scripts/sim/synergy.gd")
const VC := preload("res://scripts/view/view_consts.gd")

const FULL := 20  ## A net of this many points (or more, either way) shows the strongest tint.
const MAX_ALPHA := 0.5
const GOOD := Color(0.25, 0.85, 0.35)
const BAD := Color(0.9, 0.25, 0.2)
const SOURCE_EDGE := Color(1.0, 0.95, 0.6, 0.9)  ## The outline of a room that is a synergy source.
const LINK_GOOD := Color(0.5, 1.0, 0.55, 0.55)
const LINK_BAD := Color(1.0, 0.45, 0.4, 0.55)

## The view option: whether the overlay is shown. Session state only: never saved, in the tower or elsewhere.
static var on: bool = false


## Net synergy points of a room of `kind` at `run` among `others` ([kind, run] source pairs).
static func net_of(kind: String, run: Array, others: Array) -> int:
	var net := SynergyScript.mood_delta(kind, run, others)
	if kind == "condo":
		net += SynergyScript.demand_percent(run, others)
	net += SynergyScript.sales_percent(kind, run, others)
	return net


## The tint of a net value: clear at 0, green above, red below, stronger with the size, capped at FULL points.
static func tint(net: int) -> Color:
	if net == 0:
		return Color(0.0, 0.0, 0.0, 0.0)
	var strength := float(mini(absi(net), FULL)) / float(FULL)
	var base := GOOD if net > 0 else BAD
	return Color(base.r, base.g, base.b, MAX_ALPHA * strength)


## The world pixel rect of a run [floor, column, length].
static func rect_of(run: Array) -> Rect2i:
	return Rect2i(int(run[1]) * VC.CELL_W, VC.floor_to_row(int(run[0])) * VC.CELL_H, int(run[2]) * VC.CELL_W, VC.CELL_H)


## Every placed room with a nonzero net: {"id", "rect", "net"}, in room id order.
static func tinted_rooms(tower: Object) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var others := SynergyScript.others_of(tower.grid, tower.rooms)
	if others.is_empty():
		return found
	for id: int in tower.rooms.room_ids():
		if not tower.grid.has_occupant(id):
			continue
		var run: Array[int] = tower.grid.run_of(id)
		var net := net_of(tower.rooms.kind_of(id), run, others)
		if net != 0:
			found.append({"id": id, "rect": rect_of(run), "net": net})
	return found


## The rooms that act on room `id`: {"rect", "amount"} per source in reach, amount summed over the rules that
## apply (positive boosts, negative harms). Tower-wide rules on people (the clinic's recovery) have no room as
## their target and so give no link.
static func links_to(tower: Object, id: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if id <= 0 or not tower.grid.has_occupant(id):
		return found
	var kind: String = tower.rooms.kind_of(id)
	var run: Array[int] = tower.grid.run_of(id)
	for other: Array in SynergyScript.others_of(tower.grid, tower.rooms):
		var amount := 0
		for rule: Array in SynergyScript.RULES:
			if rule[0] == other[0] and rule[1] == kind and SynergyScript.in_reach(run, other[1], rule[4], rule[5]):
				amount += int(rule[3])
		if amount != 0:
			found.append({"rect": rect_of(other[1]), "amount": amount})
	return found


## Paints the overlay: a tint over every room with a net, a pale outline round each source, and a link from
## the hovered room (hover_id, or -1 for none) to every room acting on it.
static func draw(canvas: Object, tower: Object, hover_id: int) -> void:
	for id: int in tower.rooms.room_ids():
		if tower.grid.has_occupant(id) and SynergyScript.is_source(tower.rooms.kind_of(id)):
			canvas.draw_rect(Rect2(rect_of(tower.grid.run_of(id))).grow(-1.0), SOURCE_EDGE, false, 1.0)
	for room: Dictionary in tinted_rooms(tower):
		canvas.draw_rect(Rect2(room["rect"]), tint(room["net"]))
	if hover_id <= 0 or not tower.grid.has_occupant(hover_id):
		return
	var here := Rect2(rect_of(tower.grid.run_of(hover_id)))
	canvas.draw_rect(here.grow(-1.0), Color(1.0, 1.0, 1.0, 0.8), false, 1.0)
	for link: Dictionary in links_to(tower, hover_id):
		var there := Rect2(link["rect"])
		var colour := LINK_GOOD if link["amount"] > 0 else LINK_BAD
		canvas.draw_line(here.get_center(), there.get_center(), colour, 1.0)
		canvas.draw_rect(there.grow(-1.0), colour, false, 1.0)
