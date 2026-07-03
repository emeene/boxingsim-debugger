extends Node2D

const RADIUS := 12.0
const BAR_WIDTH := 36.0
const BAR_HEIGHT := 5.0
const BAR_OFFSET_Y := -RADIUS - 12.0
@export var color: Color = Color.WHITE_SMOKE

var _target_position: Vector2 = Vector2.ZERO
var _health_fraction: float = 1.0
var _stamina_fraction: float = 1.0
var _phase: String = "READY"

func _draw() -> void:
	# Phase tint (combat-timing Phase 1): yellow while a punch winds up (STARTUP),
	# grey while recovering (RECOVERY), base color when READY
	var draw_color := color
	match _phase:
		"STARTUP":  draw_color = color.lerp(Color.YELLOW, 0.6)
		"RECOVERY": draw_color = color.lerp(Color.DIM_GRAY, 0.6)
	draw_circle(Vector2.ZERO, RADIUS, draw_color)
	# Health bar above the fighter: dark background, green→red fill as health drains
	var bar_origin := Vector2(-BAR_WIDTH / 2.0, BAR_OFFSET_Y)
	draw_rect(Rect2(bar_origin, Vector2(BAR_WIDTH, BAR_HEIGHT)), Color(0.15, 0.15, 0.15))
	var fill_color := Color.RED.lerp(Color.GREEN, _health_fraction)
	draw_rect(Rect2(bar_origin, Vector2(BAR_WIDTH * _health_fraction, BAR_HEIGHT)), fill_color)
	# Stamina bar right below it: cyan-blue so it never reads as health (green/red) or as
	# the STARTUP yellow tint. Pool is flat 100 (calibration §1), floor 5 — a near-empty
	# bar means a gassed boxer, never a dead one.
	var stamina_origin := bar_origin + Vector2(0.0, BAR_HEIGHT + 1.0)
	draw_rect(Rect2(stamina_origin, Vector2(BAR_WIDTH, BAR_HEIGHT)), Color(0.15, 0.15, 0.15))
	draw_rect(Rect2(stamina_origin, Vector2(BAR_WIDTH * _stamina_fraction, BAR_HEIGHT)), Color(0.25, 0.75, 1.0))

func _process(delta: float) -> void:
	position = position.lerp(_target_position, delta / 0.1)
	queue_redraw()

func update_from_snapshot(x: float, y: float, health: float, stamina: float, phase: String) -> void:
	_target_position = MatchState.to_screen(x, y)
	_health_fraction = clampf(health / 100.0, 0.0, 1.0)
	_stamina_fraction = clampf(stamina / 100.0, 0.0, 1.0)
	_phase = phase
