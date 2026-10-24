extends Node2D
## Crisp UI layer drawn above the pixelated world; all drawing logic lives in main.gd.

var main: Node2D


func _draw() -> void:
	if main != null:
		main.draw_overlay(self)
