extends Node
## Entry scene. For now it only shows a sky-colour background.

const SKY := Color(0.53, 0.78, 0.95)

var _tower := Tower.new()


func _ready() -> void:
	RenderingServer.set_default_clear_color(SKY)
	# Demo content until building commands exist (refs #6).
	for i in 20:
		_tower.grid.place(i + 1, 1 + i % 8, 10 + (i * 7) % 60, 4 + i % 5)
	_tower.grid.place(100, -2, 20, 12)
	var renderer: TowerRenderer = $TowerRenderer
	renderer.people = [[1, 240], [3, 800]]
	renderer.set_tower(_tower)
