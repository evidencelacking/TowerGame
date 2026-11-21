extends RefCounted
## Thought icons (12.6): a small code-drawn bubble over a person for a strong mood or need. Which person
## shows which icon is decided here from the sim alone, so it is the same on every machine and in both
## graphics styles; drawing is a separate layer (thought_layer.gd) on top of the tower.
##
## Only notable states count (the thresholds below), a person shows at most one icon, each person shows it
## for SHOW_TICKS out of every PERIOD_TICKS on a phase of their own id (so a crowd never flashes together),
## and at most MAX_ICONS show at once, the most urgent first.
## Reads the sim only.

const PeopleScript := preload("res://scripts/sim/people.gd")
const MoodScript := preload("res://scripts/sim/mood.gd")
const NoiseScript := preload("res://scripts/sim/noise.gd")
const VC := preload("res://scripts/view/view_consts.gd")

const NONE := 0
const CLOCK := 1  ## Waited too long: stress is in the angry band.
const NOISE := 2  ## A zigzag: noise costs the person's mood at least NOISE_COST.
const CLOUD := 3  ## Unhappy: mood below Mood.LOW_BELOW.
const FORK := 4  ## Hungry: on the way to lunch and not in a place that serves food yet.
const HEART := 5  ## Happy: mood at or above Mood.HIGH_FROM.
const KIND_COUNT := 6
const NAMES: Array[String] = ["none", "waiting", "noisy", "unhappy", "hungry", "happy"]

const NOISE_COST := 16  ## Mood points noise must cost (two levels of noise) before the zigzag shows.
const PERIOD_TICKS := 360  ## 12 seconds at the base rate of 30 ticks a second.
const SHOW_TICKS := 90  ## An icon stays up for 3 of them.
const PHASE_STEP := 53  ## Per id; coprime to PERIOD_TICKS so neighbours are spread across it.
const MAX_ICONS := 12

const FOOD_KINDS: Array[String] = ["fast_food", "restaurant"]

## Bubble size and the gap between the figure's head and the bubble's tip, native pixels.
const BUBBLE := 9
const TAIL := 2
const HEAD_GAP := 3

## 7x7 pictures: '#' the icon's main colour, 'o' its accent.
const PICTURES: Dictionary = {
	CLOCK: [".#####.", "#..o..#", "#..o..#", "#..oo.#", "#.....#", "#.....#", ".#####."],
	NOISE: ["....##.", "...##..", "..##...", ".#####.", "...##..", "..##...", ".##...."],
	CLOUD: ["..###..", ".#####.", "#######", "#######", ".......", ".o.o.o.", "..o.o.."],
	FORK: [".#.#.#.", ".#.#.#.", ".#.#.#.", "..###..", "...#...", "...#...", "...#..."],
	HEART: [".##.##.", "#######", "#######", "#######", ".#####.", "..###..", "...#..."],
}
const COLORS: Dictionary = {
	CLOCK: [Color("3a4a8a"), Color("d03030")],
	NOISE: [Color("e08a00"), Color("e08a00")],
	CLOUD: [Color("5a6a80"), Color("3a7ad0")],
	FORK: [Color("606060"), Color("606060")],
	HEART: [Color("d83060"), Color("d83060")],
}
const BORDER := Color("20202a")
const FILL := Color("fffff4")


## True when person `id` may show an icon at this tick: its own SHOW_TICKS of every PERIOD_TICKS.
static func is_showing(id: int, tick: int) -> bool:
	return posmod(tick + id * PHASE_STEP, PERIOD_TICKS) < SHOW_TICKS


## The icon the person at index i has earned now (NONE below every threshold), by priority: waiting, noise,
## unhappy, hungry, happy. _counts (Mood.floor_counts) is kept for callers; the noise test below reads
## the same figure Mood.factors would give but without computing every other factor. noise_cache
## (room id -> mood points noise costs) lets a whole crowd share one noise lookup per room (#399).
static func state_of(tower: Object, i: int, _counts: Dictionary = {}, noise_cache: Dictionary = {}) -> int:
	var people: PeopleScript = tower.people
	if people.stress_band(i) == PeopleScript.BAND_ANGRY:
		return CLOCK
	if noise_cost(tower, MoodScript.room_of(people, i), noise_cache) >= NOISE_COST:
		return NOISE
	var mood := people.mood_of(i)
	if mood < MoodScript.LOW_BELOW:
		return CLOUD
	if people.goal_of(i) == PeopleScript.DEST_LUNCH and not FOOD_KINDS.has(tower.rooms.kind_of(people.location_of(i))):
		return FORK
	if mood >= MoodScript.HIGH_FROM:
		return HEART
	return NONE


## The mood points noise costs the people of `room` (Mood.factors' noise change, sign dropped), 0 for no room.
static func noise_cost(tower: Object, room: int, cache: Dictionary) -> int:
	if room == PeopleScript.NONE or tower.rooms.kind_of(room) == "":
		return 0
	if not cache.has(room):
		cache[room] = mini(NoiseScript.noise_at(tower.grid, tower.rooms, room) * MoodScript.NOISE_PER_LEVEL, MoodScript.NOISE_MAX)
	return cache[room]


## The icons to draw now, from the figures the renderer drew: [{"id", "icon", "at"}] where at is the
## world point of the figure's head top (the bubble's tail points there). Deterministic for a tower and
## its tick. Cleaners and anyone not showing this tick are skipped; the cap keeps the most urgent.
## memo (id -> [icon, tick]) with memo_ticks > 0 lets a caller reuse a person's earned icon for that many
## ticks, so the mood lookups run a tenth as often while bubbles still follow the figures every tick (#399).
static func pick(tower: Object, figures: Array[Dictionary], respect_window: bool = true, memo: Dictionary = {}, memo_ticks: int = 0) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var noise_cache: Dictionary = {}
	for figure: Dictionary in figures:
		if figure.get("staff", false) or not figure.has("id") or (respect_window and not is_showing(figure["id"], tower.tick)):
			continue
		var i: int = tower.people.index_of(figure["id"])
		if i == -1:
			continue
		var icon: int
		var id: int = figure["id"]
		var age: int = tower.tick - memo[id][1] if memo_ticks > 0 and memo.has(id) else -1
		if age >= 0 and age < memo_ticks:
			icon = memo[id][0]
		else:
			icon = state_of(tower, i, {}, noise_cache)
			if memo_ticks > 0:
				memo[id] = [icon, tower.tick]
		if icon != NONE:
			found.append({"id": figure["id"], "icon": icon, "at": head_of(figure)})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["icon"] < b["icon"] or (a["icon"] == b["icon"] and a["id"] < b["id"]))
	return found.slice(0, MAX_ICONS)


## The world point at the top of a figure's head, in whole pixels.
static func head_of(figure: Dictionary) -> Vector2i:
	if figure.has("px"):  # resting on a spot of its room
		return Vector2i(figure["px"] + VC.FIGURE_W / 2, figure["pfeet"] - VC.FIGURE_H)
	var column: float = figure.get("fx", float(figure["x"]))
	var row: float = figure.get("frow", float(VC.floor_to_row(figure["floor"])))
	return Vector2i(roundi(column * VC.CELL_W) + VC.CELL_W / 2, roundi((row + 1.0) * VC.CELL_H) - 3 - VC.FIGURE_H)


## Draws one bubble whose tail tip is at `tip` (native pixels).
static func draw_icon(canvas: CanvasItem, icon: int, tip: Vector2i) -> void:
	if not PICTURES.has(icon):
		return
	var top := tip.y - HEAD_GAP - TAIL - BUBBLE
	var left := tip.x - BUBBLE / 2
	canvas.draw_rect(Rect2i(left + 1, top, BUBBLE - 2, BUBBLE), BORDER)  # a rounded box: edges, then corners
	canvas.draw_rect(Rect2i(left, top + 1, BUBBLE, BUBBLE - 2), BORDER)
	canvas.draw_rect(Rect2i(tip.x, top + BUBBLE, 1, TAIL), BORDER)  # the tail
	canvas.draw_rect(Rect2i(left + 1, top + 1, BUBBLE - 2, BUBBLE - 2), FILL)
	var rows: Array = PICTURES[icon]
	var colors: Array = COLORS[icon]
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var c := row[x]
			if c != ".":
				canvas.draw_rect(Rect2i(left + 1 + x, top + 1 + y, 1, 1), colors[0] if c == "#" else colors[1])
