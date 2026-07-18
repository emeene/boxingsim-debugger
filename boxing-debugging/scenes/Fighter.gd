extends Node2D

const RADIUS := 12.0
const BAR_WIDTH := 36.0
const BAR_HEIGHT := 5.0
const BAR_OFFSET_Y := -RADIUS - 12.0
@export var color: Color = Color.WHITE_SMOKE

# Cornered tint (fight-feel backlog item 1): computed CLIENT-side from the snapshot x/y —
# no backend payload change. Must match the backend's RopeProximity: ring is 0..860 on both
# axes, a fighter is cornered when TWO edges are within 100 world units at once.
const RING_MAX := 860.0
const ROPE_THRESHOLD := 100.0

var _target_position: Vector2 = Vector2.ZERO
var _health_fraction: float = 1.0
var _stamina_fraction: float = 1.0
var _phase: String = "READY"
var _guard: String = ""
var _cornered: bool = false

func _draw() -> void:
	# Phase tint (combat-timing Phase 1): yellow while a punch winds up (STARTUP),
	# grey while recovering (RECOVERY), base color when READY
	var draw_color := color
	match _phase:
		"STARTUP":  draw_color = color.lerp(Color.YELLOW, 0.6)
		"RECOVERY": draw_color = color.lerp(Color.DIM_GRAY, 0.6)
	draw_circle(Vector2.ZERO, RADIUS, draw_color)
	# Guard ring (combat-timing Phase 3, §4): a committed defense draws an outline —
	# solid cyan for BLOCK, a side arc for a slip on the side the head moves to. Guards
	# only appear during the rival's windup, so a flash of cyan against a yellow rival
	# reads as "he saw it coming".
	match _guard:
		"BLOCK":
			draw_arc(Vector2.ZERO, RADIUS + 3.0, 0.0, TAU, 32, Color.CYAN, 2.5)
		"SLIP_LEFT":
			draw_arc(Vector2.ZERO, RADIUS + 3.0, PI * 0.5, PI * 1.5, 16, Color.CYAN, 2.5)
		"SLIP_RIGHT":
			draw_arc(Vector2.ZERO, RADIUS + 3.0, -PI * 0.5, PI * 0.5, 16, Color.CYAN, 2.5)
	# Cornered ring: orange outline just outside the guard ring, so both can show at once —
	# a cornered man throwing up a guard is exactly the situation worth seeing.
	if _cornered:
		draw_arc(Vector2.ZERO, RADIUS + 6.0, 0.0, TAU, 32, Color.ORANGE, 2.5)
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

func update_from_snapshot(x: float, y: float, health: float, stamina: float, phase: String, guard = null) -> void:
	_target_position = MatchState.to_screen(x, y)
	_health_fraction = clampf(health / 100.0, 0.0, 1.0)
	_stamina_fraction = clampf(stamina / 100.0, 0.0, 1.0)
	_phase = phase
	_guard = guard if guard != null else ""
	_cornered = _near_edges(x, y) >= 2

# Same edge test as the backend's RopeProximity.nearbyEdges — near means within
# ROPE_THRESHOLD of an edge, counted per axis (a corner is close on both axes).
func _near_edges(x: float, y: float) -> int:
	var edges := 0
	if minf(x, RING_MAX - x) <= ROPE_THRESHOLD:
		edges += 1
	if minf(y, RING_MAX - y) <= ROPE_THRESHOLD:
		edges += 1
	return edges
