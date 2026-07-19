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
# Feint flash (combat-timing §5): the payload's `feinted` flag is true for exactly one
# tick — the tick the fake COMPLETED. The backend deliberately never says "feint" while
# the windup is live (it reads as a jab windup, like the in-ring defender experiences),
# so this flash is strictly after-the-fact viewer information. One tick is ~6 ms at ×16,
# so the flash is held for a short wall-clock window to stay visible at any speed.
const FEINT_FLASH_MS := 300.0
var _feint_flash_until_ms: float = -1.0
# Knockdown count (hurt cycle): true while this fighter is on the canvas — the payload's
# `downed` tag names him for the whole count, and keeps naming him after a count-out so
# the final frame still shows the fallen man.
var _downed: bool = false
# Stagger (hurt cycle, visual-only): how hurt this man LOOKS. The backend already folds
# toughness AND balance into the number — a great-balance fighter hides his wobble, which
# is deliberate scouting fog, so the client just renders the amplitude it is given.
var _stagger: float = 0.0

func _draw() -> void:
	# Fallen pose (hurt cycle): a downed man draws as a darkened, squashed shape lying on
	# the canvas — no guard, corner or feint decorations can apply to a man on the floor,
	# so only the bars are drawn with him. The count number itself is drawn by Ring.gd.
	if _downed:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.6, 0.45))
		draw_circle(Vector2.ZERO, RADIUS, color.lerp(Color.DIM_GRAY, 0.5))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_draw_bars()
		return
	# Stagger sway (hurt cycle, visual-only): a hurt man's body and rings rock side to
	# side with an amplitude the backend computed; the bars stay steady so they remain
	# readable. Purely cosmetic — position and every gameplay read are untouched.
	if _stagger > 0.01:
		var t := Time.get_ticks_msec() / 130.0
		draw_set_transform(Vector2(sin(t) * _stagger * 6.0, 0.0), sin(t * 0.7) * _stagger * 0.18, Vector2.ONE)
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
	# Feint flash: a magenta ring that pops when a fake just completed and fades over the
	# flash window — magenta so it never reads as guard (cyan), cornered (orange) or
	# windup (yellow). A flash followed by the rival's cyan guard = he bit on nothing.
	var flash_left := _feint_flash_until_ms - Time.get_ticks_msec()
	if flash_left > 0.0:
		var flash_color := Color.MAGENTA
		flash_color.a = flash_left / FEINT_FLASH_MS
		draw_arc(Vector2.ZERO, RADIUS + 9.0, 0.0, TAU, 32, flash_color, 3.0)
	# The sway must not reach the bars — reset the transform so they stay readable
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_bars()

# Health bar above the fighter: dark background, green→red fill as health drains.
# Stamina bar right below it: cyan-blue so it never reads as health (green/red) or as
# the STARTUP yellow tint. Pool is flat 100 (calibration §1), floor 5 — a near-empty
# bar means a gassed boxer, never a dead one. Split out so the fallen pose keeps them.
func _draw_bars() -> void:
	var bar_origin := Vector2(-BAR_WIDTH / 2.0, BAR_OFFSET_Y)
	draw_rect(Rect2(bar_origin, Vector2(BAR_WIDTH, BAR_HEIGHT)), Color(0.15, 0.15, 0.15))
	var fill_color := Color.RED.lerp(Color.GREEN, _health_fraction)
	draw_rect(Rect2(bar_origin, Vector2(BAR_WIDTH * _health_fraction, BAR_HEIGHT)), fill_color)
	var stamina_origin := bar_origin + Vector2(0.0, BAR_HEIGHT + 1.0)
	draw_rect(Rect2(stamina_origin, Vector2(BAR_WIDTH, BAR_HEIGHT)), Color(0.15, 0.15, 0.15))
	draw_rect(Rect2(stamina_origin, Vector2(BAR_WIDTH * _stamina_fraction, BAR_HEIGHT)), Color(0.25, 0.75, 1.0))

func _process(delta: float) -> void:
	position = position.lerp(_target_position, delta / 0.1)
	queue_redraw()

func update_from_snapshot(x: float, y: float, health: float, stamina: float, phase: String, guard = null, feinted: bool = false, downed: bool = false, stagger: float = 0.0) -> void:
	_target_position = MatchState.to_screen(x, y)
	_health_fraction = clampf(health / 100.0, 0.0, 1.0)
	_stamina_fraction = clampf(stamina / 100.0, 0.0, 1.0)
	_phase = phase
	_guard = guard if guard != null else ""
	_cornered = _near_edges(x, y) >= 2
	_downed = downed
	_stagger = stagger
	if feinted:
		_feint_flash_until_ms = Time.get_ticks_msec() + FEINT_FLASH_MS

# Same edge test as the backend's RopeProximity.nearbyEdges — near means within
# ROPE_THRESHOLD of an edge, counted per axis (a corner is close on both axes).
func _near_edges(x: float, y: float) -> int:
	var edges := 0
	if minf(x, RING_MAX - x) <= ROPE_THRESHOLD:
		edges += 1
	if minf(y, RING_MAX - y) <= ROPE_THRESHOLD:
		edges += 1
	return edges
