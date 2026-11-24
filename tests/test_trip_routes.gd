extends RefCounted
## Trips keeps the routes it finds between steps (#455): the cache must never change a result. The mixed fixture stepped
## from the morning arrivals through the first rush ends on the state_hash recorded on main before the cache, and the
## cache and the hall-queue index (Rooms._queue_ids) agree with what they stand for at the end.

const Mixed := preload("res://tools/bench_mixed.gd")

const TICKS := 1000  ## From 8:48: the morning arrivals, the day and the first lunch.
const PINNED := -4785856311058287540  ## state_hash after TICKS on bench_mixed seed 42, recorded on main at c3d16cc.


static func run(check: Callable) -> void:
	var t := Mixed.build(42)
	for _i in TICKS:
		t.step()
	check.call(t.people.count() > 0, "the mixed fixture has people")
	check.call(t.trips._cache.size() > 0, "trips cached the routes it found")
	var got := t.state_hash()
	check.call(got == PINNED, "state_hash after the morning rush matches the pinned value (got %d)" % got)
	var queued: Array[int] = t.rooms.queued_ids()
	var index_ok: bool = t.rooms._queue_ids.size() == queued.size()
	for id: int in queued:
		index_ok = index_ok and t.rooms._queue_ids.has(id)
	check.call(index_ok, "the hall-queue index holds exactly the queued people (%d)" % queued.size())
	var again := Tower.new()
	var loaded := again.load_state(t.save())
	check.call(loaded and again.rooms._queue_ids.size() == again.rooms.queued_ids().size(), "a loaded tower rebuilds the hall-queue index")
