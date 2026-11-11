extends Node
## Entry scene. For now it only shows a sky-colour background.

const SKY := Color(0.53, 0.78, 0.95)


func _ready() -> void:
	RenderingServer.set_default_clear_color(SKY)
