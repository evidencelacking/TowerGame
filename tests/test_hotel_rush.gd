extends RefCounted
## Hotel check-in and check-out must not change a result when their cost is cut (#467): check-outs remove their guests
## from People in one pass and the arrival count is one tight loop. The mixed fixture (it has hotel rooms) stepped across
## the evening check-in, the night and the check-out morning ends on the state_hash recorded on main before the change.

const Mixed := preload("res://tools/bench_mixed.gd")
const HotelScript := preload("res://scripts/sim/hotel.gd")

const WARMUP := 400
const EVENING_AT := 1900  ## Clock ticks into the day: about 17:30, before the 18:00 check-in window opens.
const TICKS := 1600  ## Through the evening check-in, the night and the check-out morning.
const PINNED := 5340082615822323413  ## state_hash after the run below on bench_mixed seed 42, recorded on main at 7dcedc2.


static func run(check: Callable) -> void:
	var t := Mixed.build(42)
	for _i in WARMUP:
		t.step()
	t.clock.set_to_tick(EVENING_AT)
	var most_busy := 0
	var checkouts := 0
	var last_busy := 0
	for _i in TICKS:
		t.step()
		var busy := 0
		for id in t.rooms.room_ids():
			if t.hotel.is_hotel(id) and t.hotel.state_of(id) != HotelScript.VACANT:
				busy += 1
		most_busy = maxi(most_busy, busy)
		checkouts += maxi(last_busy - busy, 0)  # rooms that went back to vacant (a give-up counts too)
		last_busy = busy
	check.call(most_busy > 0, "hotel rooms were booked in the evening (%d at most)" % most_busy)
	check.call(checkouts > 0, "guests left again in the morning (%d rooms)" % checkouts)
	var got := t.state_hash()
	check.call(got == PINNED, "state_hash after an evening check-in and a morning check-out matches the pinned value (got %d)" % got)
