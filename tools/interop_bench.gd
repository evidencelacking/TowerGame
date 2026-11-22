extends SceneTree
## Spike (#422): GDScript to C# interop cost. Run with the .NET Godot:
##   Godot_console.exe --headless --path . --script res://tools/interop_bench.gd
## Reports ns per call and ms per tick for a bulk PackedInt32Array. Wall-clock timing, tools only.
## Every loop runs a fixed count, so the run ends; a wrong bulk size or a wrong accessor value exits 1.

const CALLS := 1000000
const BULK := 15000
const BULK_REPEAT := 300


class GdSide:
	extends RefCounted
	var data: PackedInt32Array = PackedInt32Array()

	func echo(x: int) -> int:
		return x

	func home_of(i: int) -> int:
		return data[i * 14 + 1]

	func bulk(n: int) -> PackedInt32Array:
		var r := data.duplicate()
		r.resize(n)
		return r


func _initialize() -> void:
	var cs := PeopleCore.new()
	var gd := GdSide.new()
	gd.data.resize(14 * 64)
	for i in 64:
		cs.AddRow(i, i, 0, 0, 0, i)
		gd.data[i * 14 + 1] = i
	if cs.Bulk(BULK).size() != BULK or cs.HomeOf(5) != 5 or gd.home_of(5) != 5:
		print("FAIL: the C# side does not answer as expected")
		quit(1)
		return
	var sink := 0
	var t0 := Time.get_ticks_usec()
	for i in CALLS:
		sink += gd.echo(i)
	var t1 := Time.get_ticks_usec()
	for i in CALLS:
		sink += cs.Echo(i)
	var t2 := Time.get_ticks_usec()
	for i in CALLS:
		sink += gd.home_of(i & 63)
	var t3 := Time.get_ticks_usec()
	for i in CALLS:
		sink += cs.HomeOf(i & 63)
	var t4 := Time.get_ticks_usec()
	var empty_us := _empty_loop()
	print("empty loop         %.0f ns/iter" % (empty_us * 1000.0 / CALLS))
	print("GD -> GD echo      %.0f ns/call (incl. loop)" % ((t1 - t0) * 1000.0 / CALLS))
	print("GD -> C# echo      %.0f ns/call (incl. loop)" % ((t2 - t1) * 1000.0 / CALLS))
	print("GD -> GD accessor  %.0f ns/call (incl. loop)" % ((t3 - t2) * 1000.0 / CALLS))
	print("GD -> C# accessor  %.0f ns/call (incl. loop)" % ((t4 - t3) * 1000.0 / CALLS))
	# Bulk: one call returning BULK ints, then GDScript reads every entry once (a per-tick snapshot).
	gd.data.resize(BULK)
	var a0 := Time.get_ticks_usec()
	for _r in BULK_REPEAT:
		var arr := cs.Bulk(BULK)
		sink += arr[BULK - 1]
	var a1 := Time.get_ticks_usec()
	for _r in BULK_REPEAT:
		var arr2 := cs.Bulk(BULK)
		for k in BULK:
			sink += arr2[k]
	var a2 := Time.get_ticks_usec()
	for _r in BULK_REPEAT:
		var arr3 := gd.bulk(BULK)
		for k in BULK:
			sink += arr3[k]
	var a3 := Time.get_ticks_usec()
	for _r in BULK_REPEAT:
		var arr4 := gd.bulk(BULK)
		sink += arr4[BULK - 1]
	var a4 := Time.get_ticks_usec()
	print("bulk %d ints from C# (call only)         %.3f ms/tick" % [BULK, (a1 - a0) / 1000.0 / BULK_REPEAT])
	print("bulk %d ints from C# + GDScript read all %.3f ms/tick" % [BULK, (a2 - a1) / 1000.0 / BULK_REPEAT])
	print("bulk %d ints in GDScript + read all      %.3f ms/tick" % [BULK, (a3 - a2) / 1000.0 / BULK_REPEAT])
	print("bulk %d ints in GDScript (call only)     %.3f ms/tick" % [BULK, (a4 - a3) / 1000.0 / BULK_REPEAT])
	print("sink %d" % sink)
	quit(0)


func _empty_loop() -> int:
	var s := 0
	var t0 := Time.get_ticks_usec()
	for i in CALLS:
		s += i
	return Time.get_ticks_usec() - t0
