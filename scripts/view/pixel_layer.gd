extends Node2D
## A canvas item that paints through a callable. The renderer puts one in each low-res SubViewport
## so its painter functions can stay plain methods taking a CanvasItem. Nothing is saved or read here.

var painter: Callable = Callable()


func _draw() -> void:
	if painter.is_valid():
		painter.call(self)
