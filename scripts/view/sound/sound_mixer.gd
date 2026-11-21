class_name SoundMixer
extends RefCounted
## Pure mixing helpers for the sound system (#247): no nodes, no audio, so tests can run them.

const MAX_LOOPS := 4  ## At most this many ambience loops play at once.
const FULL_UNITS := 60  ## Floor-area units (grid columns) of one kind in view that reach full volume.
const MIN_LEVEL := 0.02  ## Below this a loop is dropped.


## How loud sound reads at a zoom: closer in is louder. Zoom 1 is a distant hum, the top zoom full.
static func zoom_factor(zoom: int) -> float:
	return clampf(0.3 + 0.15 * float(zoom), 0.3, 1.0)


## Volume 0..1 of a source with `units` of floor area in view at a zoom.
static func level_for(units: int, zoom: int) -> float:
	return clampf(float(units) / float(FULL_UNITS), 0.0, 1.0) * zoom_factor(zoom)


## Loop name -> volume (0..1) for the strongest max_loops of the wanted levels (loop name -> level).
## Ties go to the earlier name, so the choice never depends on dictionary order.
static func strongest(levels: Dictionary, max_loops: int = MAX_LOOPS) -> Dictionary:
	var names: Array = levels.keys()
	names.sort()
	var ranked: Array = []
	for loop_name: String in names:
		if float(levels[loop_name]) >= MIN_LEVEL:
			ranked.append(loop_name)
	ranked.sort_custom(func(a: String, b: String) -> bool: return float(levels[a]) > float(levels[b]))
	var result: Dictionary = {}
	for i in mini(max_loops, ranked.size()):
		result[ranked[i]] = float(levels[ranked[i]])
	return result


## One step of a fade: gain moves toward target by at most step.
static func approach(gain: float, target: float, step: float) -> float:
	if gain < target:
		return minf(gain + step, target)
	return maxf(gain - step, target)


## The messages not seen yet, as {"entries": [[tick, code, a, b], ...] oldest first, "tick", "count"}; pass
## the last two back next time. The cursor is the tick of the newest entry and how many entries share it,
## because the record is bounded (the oldest drop) so its length alone cannot say what is new. A record
## that went back in time (a load or a new tower) is not replayed: it yields no entries.
static func new_messages(messages: Messages, last_tick: int, last_count: int) -> Dictionary:
	var count := messages.count()
	var fresh: Array = []
	if count == 0:
		return {"entries": fresh, "tick": last_tick, "count": last_count}
	var newest_tick: int = messages.entry(count - 1)[0]
	if newest_tick >= last_tick:
		var skipped := 0
		for i in count:
			var entry := messages.entry(i)
			if entry[0] < last_tick:
				continue
			if entry[0] == last_tick and skipped < last_count:
				skipped += 1
				continue
			fresh.append(entry)
	return {"entries": fresh, "tick": newest_tick, "count": _entries_at(messages, newest_tick)}


static func _entries_at(messages: Messages, at_tick: int) -> int:
	var total := 0
	var i := messages.count() - 1
	while i >= 0 and messages.entry(i)[0] >= at_tick:
		if messages.entry(i)[0] == at_tick:
			total += 1
		i -= 1
	return total
