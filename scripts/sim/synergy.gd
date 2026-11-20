extends RefCounted
## Synergies (M13, #293): each kind boosts or harms the kinds around it within a reach. A pure function of
## the grid and the room kinds: it keeps no state, so a reload with the same tower gives the same answer, and
## nothing here is saved. Integers only; see CLAUDE.md. Our own design: every number is an unverified tunable.
##
## A rule is [source kind, target kind, effect, amount, reach in floors, reach in columns]. A reach of ANY is
## tower-wide; a column reach is the number of empty units allowed between two rooms sideways, as in noise.gd.
## Several sources add up, then the total is capped per effect (CAPS), so a crowd of one kind cannot run away.
##
##   MOOD         added to the mood target of the people who live or work in the target room (mood.gd).
##   CONDO_DEMAND percent added to a condo's sale price when it sells (tenancy.gd): the demand for it.
##   RECOVERY     added to how far a mood may rise in one day, tower-wide, target "*" (mood.gd).
##   SALES        percent added to a shop's daily takings when they are positive (commerce.gd).
##   RENT         percent added to the rent an office pays (rent.gd), tower-wide: the metro station (#325, own
##                design: a connected tower means a shorter commute, so offices and condos fetch more).
##   NOISE        shown in the preview only: noise.gd owns the rule, and the preview folds it in so the ghost
##                tells the whole story of a placement.
## The observation deck (#318, own design) is the tower's pride: its mood rules are the reputation word of mouth
## spreads, a lift for restaurants and happier hotel guests nearby. A closed deck (not on the top floor) is no source.
## Rooms of kinds not built yet (the garden and the nightclub arrive with #292) simply have no sources.
## The placement ghost reads preview_at() and shows text_of() for each entry; both are pure.

const NoiseScript := preload("res://scripts/sim/noise.gd")
const GridScript := preload("res://scripts/sim/grid.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")

const MOOD := 0
const CONDO_DEMAND := 1
const RECOVERY := 2
const SALES := 3
const NOISE := 4
const RENT := 5
const EFFECT_NAMES: Array[String] = ["mood", "% sale price", "mood recovery a day", "% sales", "noise", "% rent"]

const LINKED_KIND := "metro"  ## Its rules apply only while the tower is linked to it (Tenancy.transit_linked).
const ANY := -1  ## Reach: the whole tower.
const EVERYONE := "*"  ## Target of a tower-wide effect on people rather than on a kind of room.

## Most one effect can add up to, either way (a total beyond this is cut).
const CAPS: Array[int] = [20, 30, 12, 30, 10, 30]

## [source, target, effect, amount, floors, columns]
const RULES: Array = [
	["daycare", "condo", CONDO_DEMAND, 10, 5, ANY],
	["daycare", "condo", MOOD, 4, 5, ANY],
	["gym", "office", MOOD, 4, 3, ANY],
	["clinic", "condo", MOOD, 3, 5, ANY],
	["clinic", "office", MOOD, 3, 5, ANY],
	["clinic", EVERYONE, RECOVERY, 4, ANY, ANY],
	["garden", "restaurant", SALES, 8, ANY, ANY],
	["metro", "office", RENT, 15, ANY, ANY],
	["metro", "condo", CONDO_DEMAND, 10, ANY, ANY],
	["observation_deck", "office", MOOD, 2, ANY, ANY],
	["observation_deck", "condo", MOOD, 2, ANY, ANY],
	["observation_deck", "restaurant", SALES, 10, 10, ANY],
	["observation_deck", "hotel_single", MOOD, 3, 10, ANY],
	["observation_deck", "hotel_twin", MOOD, 3, 10, ANY],
	["observation_deck", "hotel_suite", MOOD, 3, 10, ANY],
	["grocery", "condo", MOOD, 3, 6, ANY],
	["nightclub", "condo", MOOD, -6, 2, ANY],
	["nightclub", "hotel_single", MOOD, -6, 2, ANY],
	["nightclub", "hotel_twin", MOOD, -6, 2, ANY],
	["nightclub", "hotel_suite", MOOD, -6, 2, ANY],
]


## True for a kind that is the source of some rule.
static func is_source(kind: String) -> bool:
	for rule: Array in RULES:
		if rule[0] == kind:
			return true
	return false


## Floors between two runs [floor, column, length]; floors above and below ground are one apart across it.
static func floors_apart(a: Array, b: Array) -> int:
	var apart: int = absi(int(a[0]) - int(b[0]))
	if (int(a[0]) > 0) != (int(b[0]) > 0):
		apart -= 1
	return apart


## Empty units between two runs sideways (0 when they touch or overlap).
static func column_gap(a: Array, b: Array) -> int:
	return maxi(maxi(int(a[1]) - (int(b[1]) + int(b[2])), int(b[1]) - (int(a[1]) + int(a[2]))), 0)


static func in_reach(a: Array, b: Array, floors: int, columns: int) -> bool:
	if floors != ANY and floors_apart(a, b) > floors:
		return false
	return columns == ANY or column_gap(a, b) <= columns


## The sum of one effect on a room of `target_kind` at `run` from `others` ([kind, run] pairs), capped.
static func total(effect: int, target_kind: String, run: Array, others: Array) -> int:
	var sum := 0
	for other: Array in others:
		for rule: Array in RULES:
			if rule[2] == effect and rule[0] == other[0] and rule[1] == target_kind and in_reach(run, other[1], rule[4], rule[5]):
				sum += int(rule[3])
	return clampi(sum, -CAPS[effect], CAPS[effect])


## Mood added to the people of a room by its neighbours (negative is a harm).
static func mood_delta(target_kind: String, run: Array, others: Array) -> int:
	return total(MOOD, target_kind, run, others)


## Percent added to a condo's sale price by the daycares in reach.
static func demand_percent(run: Array, others: Array) -> int:
	return total(CONDO_DEMAND, "condo", run, others)


## Mood a person may regain beyond the usual daily step, from the clinics in the tower.
static func recovery_bonus(others: Array) -> int:
	return total(RECOVERY, EVERYONE, [1, 0, 0], others)


## Percent added to office rents by the metro station, tower-wide.
static func rent_percent(others: Array) -> int:
	return total(RENT, "office", [1, 0, 0], others)


## Percent added to a shop's positive daily takings by the gardens in the tower.
static func sales_percent(kind: String, run: Array, others: Array) -> int:
	return total(SALES, kind, run, others)


## Every placed room that is a source of some rule, as [kind, run] pairs in room id order. Cheap for a tower
## without such rooms: the answer is empty and every total is 0.
static func others_of(grid: GridScript, rooms: RoomsScript, linked: bool = true) -> Array:
	var list := []
	for id in rooms.room_ids():
		var kind := rooms.kind_of(id)
		if kind == LINKED_KIND and not linked:
			continue  # a station nobody can reach from the lobby gives nothing
		if rooms.is_closed_up(grid, id):
			continue  # a deck the tower has grown past is closed (#318)
		if is_source(kind) and grid.has_occupant(id):
			list.append([kind, grid.run_of(id)])
	return list


## All placed rooms as [kind, run] pairs (for the preview, which also reads noise).
static func rooms_of(grid: GridScript, rooms: RoomsScript) -> Array:
	var list := []
	for id in rooms.room_ids():
		if grid.has_occupant(id):
			list.append([rooms.kind_of(id), grid.run_of(id)])
	return list


## The pure core of the ghost preview: what a room of `kind` at `run` would do to `others` ([kind, run] pairs,
## every placed room) and what they would do to it. Entries, in rule order, outgoing then incoming then noise:
## {"target": kind, "effect": e, "amount": n, "count": rooms affected, "incoming": bool}. A tower-wide effect on
## people has target EVERYONE and count 0. Amounts add up per rule and are not capped here.
static func preview(kind: String, run: Array, others: Array) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for rule: Array in RULES:
		if rule[0] != kind:
			continue
		if rule[1] == EVERYONE:
			found.append({"target": EVERYONE, "effect": rule[2], "amount": rule[3], "count": 0, "incoming": false})
			continue
		var count := 0
		for other: Array in others:
			if other[0] == rule[1] and in_reach(run, other[1], rule[4], rule[5]):
				count += 1
		if count > 0:
			found.append({"target": rule[1], "effect": rule[2], "amount": rule[3], "count": count, "incoming": false})
	var incoming := {}  # "source:effect" -> amount, in the order first met
	for rule: Array in RULES:
		if rule[1] != kind:
			continue
		for other: Array in others:
			if other[0] == rule[0] and in_reach(run, other[1], rule[4], rule[5]):
				var key := "%s:%d" % [rule[0], rule[2]]
				incoming[key] = int(incoming.get(key, 0)) + int(rule[3])
	for key: String in incoming:
		found.append({"target": key.get_slice(":", 0), "effect": int(key.get_slice(":", 1)), "amount": incoming[key], "count": 0, "incoming": true})
	_add_noise(found, kind, run, others)
	return found


static func _add_noise(found: Array[Dictionary], kind: String, run: Array, others: Array) -> void:
	if NoiseScript.is_source(kind) or NoiseScript.BUFFERS.has(kind):
		var raised := {}  # sensitive kind -> [rooms changed, total change]
		for n in others.size():
			var other: Array = others[n]
			if not NoiseScript.is_sensitive(other[0]):
				continue
			var rest := _without(others, n)
			var before := NoiseScript.level_among(other[0], other[1], rest)
			var after := NoiseScript.level_among(other[0], other[1], rest + [[kind, run]])
			if after != before:
				var seen: Array = raised.get(other[0], [0, 0])
				raised[other[0]] = [int(seen[0]) + 1, int(seen[1]) + after - before]
		for target: String in raised:
			var totals: Array = raised[target]
			found.append({"target": target, "effect": NOISE, "amount": totals[1], "count": totals[0], "incoming": false})
	if NoiseScript.is_sensitive(kind):
		var level := NoiseScript.level_among(kind, run, others)
		if level > 0:
			found.append({"target": "", "effect": NOISE, "amount": level, "count": 0, "incoming": true})


static func _without(list: Array, index: int) -> Array:
	var out := list.duplicate()
	out.remove_at(index)
	return out


## The preview for placing `kind` with its left edge at column x on a floor, read from a tower's grid and rooms.
static func preview_at(grid: GridScript, rooms: RoomsScript, kind: String, floor_number: int, x: int) -> Array[Dictionary]:
	if not CatalogueScript.has(kind):
		return []
	var run: Array = [floor_number, x, int(CatalogueScript.field(kind, "width"))]
	return preview(kind, run, rooms_of(grid, rooms))


## One line for an entry, e.g. "+4 mood on 3 Office", "-6 mood from Nightclub", "+4 mood recovery a day tower-wide".
static func text_of(entry: Dictionary) -> String:
	var effect: int = entry["effect"]
	var amount: int = entry["amount"]
	var what: String = EFFECT_NAMES[effect]
	var number := "%+d" % amount
	if what.begins_with("%"):
		number += "%"
		what = what.substr(2)
	var target: String = entry["target"]
	if bool(entry["incoming"]):
		var source := CatalogueScript.display_name(target) if target != "" else "neighbours"
		return "%s %s from %s" % [number, what, source]
	if target == EVERYONE:
		return "%s %s tower-wide" % [number, what]
	return "%s %s on %d %s" % [number, what, entry["count"], CatalogueScript.display_name(target)]
