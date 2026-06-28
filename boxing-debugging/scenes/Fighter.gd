extends Node2D

const RADIUS := 12.0
@export var color: Color = Color.WHITE_SMOKE

var _target_position: Vector2 = Vector2.ZERO

func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, color)

func _process(delta: float) -> void:
	position = position.lerp(_target_position, delta / 0.1)
	queue_redraw()

func update_from_snapshot(x: float, y: float) -> void:
	_target_position = MatchState.to_screen(x, y)
