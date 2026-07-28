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
# Morale (morale-design.md): tonight's live belief, 0..1 — the fight-long "do I still
# think I win" that bends pace, position and decision sharpness in the engine. Drawn as
# a thin amber bar under health/stamina so momentum swings are followable on the bars
# alone; -1 means an older backend payload without the field, and the bar is not drawn.
var _morale: float = -1.0
# Opponent read (feints-fakes-study-design.md): how well this man has read the one in front
# of him tonight, 0..1. It starts at 0 — he walks in a stranger — and climbs as he probes,
# fast in the first rounds and barely at all later. It is the ONLY thing in the engine that
# moves a fighter's accuracy, so watching this bar fill IS watching "he's got his timing
# now" arrive. -1 means an older backend payload without the field, and the bar is not drawn.
var _opponent_read: float = -1.0
# A live probe: the empty fake that sets up nothing and only reads the other man. Unlike a
# feint, the backend broadcasts this one as itself — nobody can be fooled by a probe, so
# there is nothing to hide. Drawn as a small open ring rather than a flash, because at
# twenty-odd a round a flash would strobe the whole fight.
var _probing: bool = false
# How much this man wants his hands up, 0..1 (CoverUpSensor.drive on the backend): 0 fresh,
# climbing as he is hurt and worn down, scaled by how smart he is. This is a POSTURE, not an
# action — it is the difference between a man boxing behind a high guard all round and one
# with his hands at his waist, and on two circles it was previously impossible to see at all.
# Drawn as a shell: a thick dim arc across the front that thickens as the drive climbs, held
# for as long as he is in trouble rather than flashing per tick. -1 on an older payload.
var _cover_up: float = -1.0
# The opening a clean piece of defence just bought, in ticks remaining (0 when closed). He made
# the other man miss and for a moment his own punch is the one that wants to come out. Drawn as
# a bright gold ring because it is RARE and short — four ticks — and it is the exact instant a
# counter is about to happen, so it must be loud enough to catch on screen.
var _counter_window: int = 0

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
	# The shell is drawn UNDER the committed guard, so a man who is turtling all round shows a
	# permanent thick band and his individual guards still flash cyan on top of it. Dim slate so
	# it never competes with the guard itself: the posture is the background, the guard is the
	# event. It only appears once he is meaningfully in trouble — a fresh fighter has a drive
	# near zero and drawing that would put a band on everybody all night and mean nothing.
	if _cover_up > 0.15:
		var shell_color := Color(0.45, 0.62, 0.72, clampf(_cover_up, 0.0, 1.0))
		draw_arc(Vector2.ZERO, RADIUS + 1.5, PI * 1.15, PI * 1.85, 16, shell_color, 2.0 + 4.0 * _cover_up)
	match _guard:
		"BLOCK":
			# Hands up: the full ring plus two short gloves across the front, so a block reads
			# as a shape a person recognises rather than one more coloured outline.
			draw_arc(Vector2.ZERO, RADIUS + 3.0, 0.0, TAU, 32, Color.CYAN, 2.5)
			draw_arc(Vector2.ZERO, RADIUS + 6.5, PI * 1.12, PI * 1.42, 8, Color.CYAN, 3.5)
			draw_arc(Vector2.ZERO, RADIUS + 6.5, PI * 1.58, PI * 1.88, 8, Color.CYAN, 3.5)
		"SLIP_LEFT":
			draw_arc(Vector2.ZERO, RADIUS + 3.0, PI * 0.5, PI * 1.5, 16, Color.CYAN, 2.5)
		"SLIP_RIGHT":
			draw_arc(Vector2.ZERO, RADIUS + 3.0, -PI * 0.5, PI * 0.5, 16, Color.CYAN, 2.5)
	# The counter opening: he just made the other man miss and has a few ticks in which his own
	# punch is favoured. Gold, outside every other ring, so "he slipped it — here it comes" is
	# one unmistakable read. Fades as the window runs down.
	if _counter_window > 0:
		var counter_color := Color(1.0, 0.84, 0.0)
		counter_color.a = clampf(_counter_window / 4.0, 0.25, 1.0)
		draw_arc(Vector2.ZERO, RADIUS + 12.0, 0.0, TAU, 32, counter_color, 2.0)
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
	# Probe mark: a small violet tick on the lead side while a fake is live. Deliberately
	# quiet — a probe happens twenty-odd times a round, so anything as loud as the feint's
	# magenta flash would strobe continuously and drown out the moments that matter. It
	# matches the read bar's colour on purpose: the probing is the cause, the bar is the
	# effect, and seeing them together is the whole point of watching a measuring round.
	if _probing:
		draw_arc(Vector2.ZERO, RADIUS + 4.0, -PI * 0.25, PI * 0.25, 8, Color(0.72, 0.45, 1.0), 2.0)
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
	# Belief bar (morale): thinner than the body bars because it is a mind read, amber so
	# it never reads as health (green/red), stamina (cyan-blue) or a windup (yellow tint
	# on the body). Watching it fall while health still holds IS the broken-on-points
	# story the morale feature exists to show.
	if _morale >= 0.0:
		var morale_origin := stamina_origin + Vector2(0.0, BAR_HEIGHT + 1.0)
		draw_rect(Rect2(morale_origin, Vector2(BAR_WIDTH, 3.0)), Color(0.15, 0.15, 0.15))
		draw_rect(Rect2(morale_origin, Vector2(BAR_WIDTH * _morale, 3.0)), Color(1.0, 0.72, 0.2))
	# Read bar (studying the rival): same thin shape as belief, sitting under it, in violet so
	# it reads as a third mind channel and never as health, stamina or belief. It only ever
	# goes UP during a fight, which is the tell to watch for — one man's bar pulling ahead of
	# the other's is him solving the fight first, and his punches starting to land better.
	if _opponent_read >= 0.0:
		var read_origin := stamina_origin + Vector2(0.0, (BAR_HEIGHT + 1.0) + 4.0)
		draw_rect(Rect2(read_origin, Vector2(BAR_WIDTH, 3.0)), Color(0.15, 0.15, 0.15))
		draw_rect(Rect2(read_origin, Vector2(BAR_WIDTH * _opponent_read, 3.0)), Color(0.72, 0.45, 1.0))
	# Cover-up bar: how much he wants his hands up. Same slate as the shell arc on the body, so
	# the bar and the posture are obviously the same channel. It is the only bar here that
	# should RISE as a man does worse, which is the read — health falling while this climbs is
	# a fighter going into his shell, and that is the whole behaviour in one picture.
	if _cover_up >= 0.0:
		var cover_origin := stamina_origin + Vector2(0.0, (BAR_HEIGHT + 1.0) + 8.0)
		draw_rect(Rect2(cover_origin, Vector2(BAR_WIDTH, 3.0)), Color(0.15, 0.15, 0.15))
		draw_rect(Rect2(cover_origin, Vector2(BAR_WIDTH * clampf(_cover_up, 0.0, 1.0), 3.0)), Color(0.45, 0.62, 0.72))

func _process(delta: float) -> void:
	position = position.lerp(_target_position, delta / 0.1)
	queue_redraw()

func update_from_snapshot(x: float, y: float, health: float, stamina: float, phase: String, guard = null, feinted: bool = false, downed: bool = false, stagger: float = 0.0, morale: float = -1.0, opponent_read: float = -1.0, action: String = "", cover_up: float = -1.0, counter_window: int = 0) -> void:
	_target_position = MatchState.to_screen(x, y)
	_health_fraction = clampf(health / 100.0, 0.0, 1.0)
	_stamina_fraction = clampf(stamina / 100.0, 0.0, 1.0)
	_phase = phase
	_guard = guard if guard != null else ""
	_cornered = _near_edges(x, y) >= 2
	_downed = downed
	_stagger = stagger
	_morale = morale
	_opponent_read = opponent_read
	# A probe is live only while its windup is running. One tick is all it lasts, which at
	# high speed is a few milliseconds — that is fine here precisely because the mark is
	# quiet: it reads as a flicker on the lead side, the way real probing looks.
	_probing = action == "FAKE" and phase == "STARTUP"
	_cover_up = cover_up
	_counter_window = counter_window
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
