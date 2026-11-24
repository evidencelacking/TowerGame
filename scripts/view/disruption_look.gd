extends RefCounted
## The Disruptions view (#487): a view filter that tints each room by how much it suffers, from clear to strong
## red, marks the rooms that cause the harm, and, for the room under the cursor, links it to its causes with a
## short reason label. It brings three things together: noise (scripts/sim/noise.gd), the negative side of the
## synergies (scripts/sim/synergy.gd) and the room's complaint reasons (scripts/sim/complaints.gd).
## Modelled on the synergy overlay (synergy_look.gd): pure reading of the sim, nothing here writes to the tower,
## and it paints in world pixels so one path serves Classic and Detailed.
##
## Suffering is in points: each noise level counts NOISE_POINTS, each point of synergy harm counts one, and each
## complaint other than noise (distance, rent, ...) counts REASON_POINTS. FULL points or more is the strongest tint.

const NoiseScript := preload("res://scripts/sim/noise.gd")
const SynergyScript := preload("res://scripts/sim/synergy.gd")
const ComplaintsScript := preload("res://scripts/sim/complaints.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const GradeReader := preload("res://scripts/view/grade_reader.gd")
const SynergyLook := preload("res://scripts/view/synergy_look.gd")

const FULL := 20  ## This many points of suffering (or more) shows the strongest tint. UNVERIFIED tunable.
const NOISE_POINTS := 2  ## Points per noise level (a level runs 0 to 10).
const REASON_POINTS := 6  ## Points per complaint other than noise.
const MAX_ALPHA := 0.55
const HARM := Color(0.9, 0.2, 0.15)
const CAUSE_EDGE := Color(1.0, 0.6, 0.1, 0.95)  ## The outline of a room that causes harm.
const LINK := Color(1.0, 0.4, 0.35, 0.8)
const LABEL := Color(1.0, 0.92, 0.85)
const LABEL_SHADOW := Color(0.1, 0.0, 0.0, 0.9)
const FONT_SIZE := 9

## The view option: whether the view is shown. Session state only: never saved, in the tower or elsewhere.
static var on: bool = false


## The tint of a suffering score: clear at 0, red above, stronger with the size, capped at FULL points.
static func tint(points: int) -> Color:
	if points <= 0:
		return Color(0.0, 0.0, 0.0, 0.0)
	var strength := float(mini(points, FULL)) / float(FULL)
	return Color(HARM.r, HARM.g, HARM.b, MAX_ALPHA * strength)


## The words for a complaint reason on a hovered room, in the game's own voice, lower case.
static func reason_text(reason: int) -> String:
	match reason:
		ComplaintsScript.NOISE:
			return "noisy neighbours"
		ComplaintsScript.DISTANCE:
			return "too far to an elevator"
		ComplaintsScript.RENT:
			return "rent too high"
	return ComplaintsScript.label(reason).to_lower()


## What the layout offers: the synergy sources, and the noise sources by floor (with the roof ones apart).
## Built once per refresh; every other helper takes it.
static func context(tower: Object) -> Dictionary:
	var by_floor: Dictionary = {}
	var roof: Array = []
	for id: int in tower.rooms.room_ids():
		var kind: String = tower.rooms.kind_of(id)
		if not NoiseScript.is_source(kind) or not tower.grid.has_occupant(id):
			continue
		var pair := [kind, tower.grid.run_of(id)]
		if NoiseScript.REACH_BELOW.has(kind):
			roof.append(pair)
		else:
			var floor_number: int = pair[1][0]
			if not by_floor.has(floor_number):
				by_floor[floor_number] = []
			(by_floor[floor_number] as Array).append(pair)
	return {"others": SynergyScript.others_of(tower.grid, tower.rooms), "noise_floors": by_floor, "noise_roof": roof}


## The noise sources that reach a sensitive room of `kind` at `run`: [kind, run, loudness] each, loudness being
## what is left of the source's level at that distance.
static func noise_causes(kind: String, run: Array, ctx: Dictionary) -> Array:
	var found: Array = []
	if not NoiseScript.is_sensitive(kind):
		return found
	var near: Array = (ctx["noise_roof"] as Array).duplicate()
	var by_floor: Dictionary = ctx["noise_floors"]
	for f in range(int(run[0]) - NoiseScript.RANGE_FLOORS - 1, int(run[0]) + NoiseScript.RANGE_FLOORS + 2):
		near.append_array(by_floor.get(f, []))
	for other: Array in near:
		var other_kind: String = other[0]
		var there: Array = other[1]
		var reach := NoiseScript.RANGE_FLOORS
		if NoiseScript.REACH_BELOW.has(other_kind):
			if int(run[0]) >= int(there[0]):
				continue
			reach = NoiseScript.REACH_BELOW[other_kind]
		var d := NoiseScript.distance(run, there, reach)
		if d < 0:
			continue
		var loud: int = int(NoiseScript.SOURCES[other_kind]) - NoiseScript.FALLOFF_PER_STEP * d
		if loud > 0:
			found.append([other_kind, there, loud])
	return found


## The synergy sources that harm a room of `kind` at `run`: [kind, run, amount, effect] each, the amount (negative)
## being the sum of the harming rules that apply and the effect the largest of them. Noise is not repeated here.
static func harm_causes(kind: String, run: Array, ctx: Dictionary) -> Array:
	var found: Array = []
	for other: Array in ctx["others"]:
		var amount := 0
		var worst := 0
		var effect: int = SynergyScript.MOOD
		for rule: Array in SynergyScript.RULES:
			if rule[0] != other[0] or rule[1] != kind or int(rule[3]) >= 0 or int(rule[2]) == SynergyScript.NOISE:
				continue
			if SynergyScript.in_reach(run, other[1], rule[4], rule[5]):
				amount += int(rule[3])
				if int(rule[3]) < worst:
					worst = int(rule[3])
					effect = int(rule[2])
		if amount != 0:
			found.append([other[0], other[1], amount, effect])
	return found


## The complaints the tint counts besides noise, which has its own points. The cheap ones: complaint_reasons would
## also ask whether the tower lacks a grocery for every condo, which scans every room each time.
const TINT_REASONS: Array[int] = [ComplaintsScript.DISTANCE, ComplaintsScript.RENT]


## Suffering points of one placed room, and the complaint reasons behind them: {"points", "noise", "harm", "reasons"}.
## The reasons are TINT_REASONS only, unless `all_reasons` (the hovered room asks for every one).
static func suffering_of(tower: Object, id: int, ctx: Dictionary, all_reasons: bool = false) -> Dictionary:
	var kind: String = tower.rooms.kind_of(id)
	var run: Array[int] = tower.grid.run_of(id)
	var level: int = NoiseScript.noise_at(tower.grid, tower.rooms, id)
	var net := SynergyLook.net_of(kind, run, ctx["others"])
	var harm := maxi(-net, 0)
	var others: Array[int] = []
	if all_reasons:
		for reason: int in tower.complaint_reasons(id):
			if reason != ComplaintsScript.NOISE:
				others.append(reason)
	else:
		for reason: int in TINT_REASONS:
			if tower.complaints.has_reason(id, reason):
				others.append(reason)
	return {"points": level * NOISE_POINTS + harm + REASON_POINTS * others.size(), "noise": level, "harm": harm, "reasons": others}


## Every placed room that suffers: {"id", "rect", "points", "reasons"} in room id order.
static func suffering_rooms(tower: Object, ctx: Dictionary = {}) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if ctx.is_empty():
		ctx = context(tower)
	var batch: Variant = GradeReader.begin(tower)
	for id: int in tower.rooms.room_ids():
		if not tower.grid.has_occupant(id):
			continue
		var s := suffering_of(tower, id, ctx)
		if int(s["points"]) > 0:
			found.append({"id": id, "rect": SynergyLook.rect_of(tower.grid.run_of(id)), "points": s["points"], "reasons": s["reasons"]})
	GradeReader.end(tower, batch)
	return found


## What acts on room `id`, as {"rect", "label"} per cause (a noise source, a synergy harm), in that order. Causes
## without a room (distance, rent) are not here: they are the "reasons" of suffering_of.
static func links_to(tower: Object, id: int, ctx: Dictionary = {}) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if id <= 0 or not tower.grid.has_occupant(id):
		return found
	if ctx.is_empty():
		ctx = context(tower)
	var kind: String = tower.rooms.kind_of(id)
	var run: Array[int] = tower.grid.run_of(id)
	for cause: Array in noise_causes(kind, run, ctx):
		found.append({"rect": SynergyLook.rect_of(cause[1]), "label": "noise from the %s" % CatalogueScript.display_name(cause[0]).to_lower()})
	for cause: Array in harm_causes(kind, run, ctx):
		var entry := {"target": cause[0], "effect": cause[3], "amount": cause[2], "count": 0, "incoming": true}
		found.append({"rect": SynergyLook.rect_of(cause[1]), "label": SynergyScript.text_of(entry).to_lower()})
	return found


## The rooms that cause harm to a suffering room, as pixel rects in first-found order.
static func cause_rects(tower: Object, suffering: Array[Dictionary], ctx: Dictionary) -> Array[Rect2i]:
	var found: Array[Rect2i] = []
	var seen: Dictionary = {}
	for room: Dictionary in suffering:
		var kind: String = tower.rooms.kind_of(room["id"])
		var run: Array[int] = tower.grid.run_of(room["id"])
		var causes: Array = noise_causes(kind, run, ctx)
		causes.append_array(harm_causes(kind, run, ctx))
		for cause: Array in causes:
			var rect := SynergyLook.rect_of(cause[1])
			if not seen.has(rect):
				seen[rect] = true
				found.append(rect)
	return found


## Paints the view: a tint over every suffering room, an orange outline round each cause, and for the hovered
## room (hover_id, or -1 for none) a link to each cause with its label and its own reasons in words.
## `cache` (optional, owned by the caller) keeps the readings between paints: pass the same empty dictionary each
## time and clear it when the tower should be read afresh, so moving the cursor does not re-read the whole tower.
static func draw(canvas: Object, tower: Object, hover_id: int, cache: Dictionary = {}) -> void:
	if not cache.has("suffering"):
		var fresh := context(tower)
		var rooms := suffering_rooms(tower, fresh)
		cache["ctx"] = fresh
		cache["suffering"] = rooms
		cache["causes"] = cause_rects(tower, rooms, fresh)
	var ctx: Dictionary = cache["ctx"]
	var suffering: Array[Dictionary] = cache["suffering"]
	for room: Dictionary in suffering:
		canvas.draw_rect(Rect2(room["rect"]), tint(room["points"]))
	for rect: Rect2i in cache["causes"]:
		canvas.draw_rect(Rect2(rect).grow(-1.0), CAUSE_EDGE, false, 2.0)
	if hover_id <= 0 or not tower.grid.has_occupant(hover_id):
		return
	var here := Rect2(SynergyLook.rect_of(tower.grid.run_of(hover_id)))
	canvas.draw_rect(here.grow(-1.0), Color(1.0, 1.0, 1.0, 0.8), false, 1.0)
	var font: Font = ThemeDB.fallback_font
	for link: Dictionary in links_to(tower, hover_id, ctx):
		var there := Rect2(link["rect"])
		canvas.draw_line(here.get_center(), there.get_center(), LINK, 1.5)
		canvas.draw_rect(there.grow(-1.0), LINK, false, 1.0)
		_label(canvas, font, there.get_center() + Vector2(-float(FONT_SIZE), -2.0), link["label"])
	var line := 0
	for reason: int in suffering_of(tower, hover_id, ctx, true)["reasons"]:
		_label(canvas, font, here.get_center() + Vector2(-float(FONT_SIZE), float(FONT_SIZE * (line - 1)) + 2.0), reason_text(reason))
		line += 1


static func _label(canvas: Object, font: Font, at: Vector2, text: String) -> void:
	canvas.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 3, LABEL_SHADOW)
	canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, LABEL)
