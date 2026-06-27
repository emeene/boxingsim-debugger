extends Node2D

const RADIUS := 12.0
@export var color: Color = Color.WHITE_SMOKE

func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, color)
	
func update_from_snapshot(x: float, y: float) -> void:
	position = MatchState.to_screen(x,y)
	queue_redraw()
