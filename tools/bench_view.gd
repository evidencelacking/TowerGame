extends SceneTree
## View benchmark (10.2): the TowerRenderer drawing the 2,000-person benchmark tower while the sim
## steps 1.5 ticks a frame (top speed). Reports ms per frame spent outside the sim: the renderer's
## _process and the commands its _draw issues. Headless has no GPU, so this is the script-side cost
## of drawing (the part batching cuts), not fill rate. Wall-clock timing is fine here: this is a tool.
## Run: timeout 300 <godot console exe> --headless --path . --script res://tools/bench_view.gd -- frames=600 warmup=250
## The loop ends: _process returns true once warmup + frames frames have run. Frames are only
## counted after the first one, so every sample is the gap between two real frames.

const Bench := preload("res://tools/bench_tower.gd")
const RendererScript := preload("res://scripts/view/tower_renderer.gd")

var _tower: Tower = null
var _frames: int = 600
var _warmup: int = 250
var _n: int = 0
var _last_start: int = 0
var _sim_us: int = 0
var _costs: Array[int] = []
var _carry: float = 0.0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("frames="):
			_frames = maxi(int(arg.get_slice("=", 1)), 1)
		elif arg.begins_with("warmup="):
			_warmup = int(arg.get_slice("=", 1))
	_tower = Bench.build(42)
	var renderer: TowerRenderer = RendererScript.new()
	root.add_child(renderer)
	renderer.set_tower(_tower)
	_last_start = Time.get_ticks_usec()


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if _n > _warmup:
		_costs.append(now - _last_start - _sim_us)  # the previous frame, less its sim steps
	_last_start = now
	var t0 := Time.get_ticks_usec()
	_carry += 1.5
	while _carry >= 1.0:
		_tower.step()
		_carry -= 1.0
	_sim_us = Time.get_ticks_usec() - t0
	_n += 1
	if _n > _warmup + _frames:
		_report()
		return true
	return false


func _report() -> void:
	var total := 0
	for c in _costs:
		total += c
	_costs.sort()
	var n := _costs.size()
	print("view: %d frames, %d people, %d rooms" % [n, _tower.people.count(), _tower.rooms.room_ids().size()])
	print("  %.3f ms/frame avg (outside the sim), %.3f p95, %.3f p99, %.3f worst" % [total / 1000.0 / n, _costs[n * 95 / 100] / 1000.0, _costs[n * 99 / 100] / 1000.0, _costs[n - 1] / 1000.0])
