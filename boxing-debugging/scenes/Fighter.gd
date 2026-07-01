extends Node2D

const RADIUS := 12.0
const BAR_WIDTH := 36.0
const BAR_HEIGHT := 5.0
const BAR_OFFSET_Y := -RADIUS - 12.0
@export var color: Color = Color.WHITE_SMOKE

var _target_position: Vector2 = Vector2.ZERO
var _health_fraction: float = 1.0

func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, color)
	# Health bar above the fighter: dark background, green→red fill as health drains
	var bar_origin := Vector2(-BAR_WIDTH / 2.0, BAR_OFFSET_Y)
	draw_rect(Rect2(bar_origin, Vector2(BAR_WIDTH, BAR_HEIGHT)), Color(0.15, 0.15, 0.15))
	var fill_color := Color.RED.lerp(Color.GREEN, _health_fraction)
	draw_rect(Rect2(bar_origin, Vector2(BAR_WIDTH * _health_fraction, BAR_HEIGHT)), fill_color)

func _process(delta: float) -> void:
	position = position.lerp(_target_position, delta / 0.1)
	queue_redraw()

func update_from_snapshot(x: float, y: float, health: float) -> void:
	_target_position = MatchState.to_screen(x, y)
	_health_fraction = clampf(health / 100.0, 0.0, 1.0)
