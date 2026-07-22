extends Control
# Action breakdown (owner request 2026-07-20), shown on demand via DebugPanel's "Watch
# Summary" button — a bar chart comparing how many times each fighter executed each
# ActionType, EXCEPT movement (owner ruling, "everything bar movement": the ring view
# already shows footwork directly, this is for the things it can't hold still long enough
# to count). Built in code and attached programmatically from DebugPanel (the ended-label/
# punch-stats-label trick — no .tscn edit needed). "Back" (a child of this control) hides
# it again and returns to the ring view.
#
# FIX (2026-07-20, same day): the first draft showed one bare, unlabeled number per punch
# type (a THROWN count). Compared against the pre-existing sidebar's combined "landed/
# thrown" total for ALL punch types, an unlabeled "JAB: 153" next to "107/238 landed/
# thrown" reads as a contradiction even though both numbers were correct — nobody could
# tell what 153 even counted. Punch rows now draw and print landed/thrown explicitly, the
# same convention the sidebar already uses, so the two never need to be reconciled by eye.
# The backdrop is also now fully opaque (was 0.8 alpha) — the old value let the sidebar's
# text bleed straight through underneath, which is what made the numbers look like they
# were fighting each other; that was a rendering bug, not a math one.
#
# COMBO LENGTH section (owner request, same day): how many 1/2/3/4/5+-punch sequences each
# fighter threw. A separate labeled section, not more ActionType rows — a combo length is a
# property of a whole punch SEQUENCE, not of any single ActionType, so it does not belong
# mixed into the rows above.
#
# FIX (2026-07-20, later same day): the red column used to start a FIXED 40px after the
# blue bar. A "153/153"-style landed/thrown label is wider than that at font size 14, so
# the red bar's opaque background (drawn after, on top) painted straight over the tail of
# blue's text — a real overlap bug, not a rare one, since it only takes 3+ digit values to
# trigger. The red column now starts after the ACTUAL measured width of blue's label plus
# a fixed margin, so it can never collide regardless of how large the numbers get.

# Punch types get a landed/thrown pair; everything else (feint, clinch, defense, idle) is
# a plain "times executed" count — there is no landed/missed concept for those.
const PUNCH_TYPES := [
	"JAB", "CROSS", "LEAD_HOOK", "REAR_HOOK", "LEAD_UPPERCUT", "REAR_UPPERCUT",
	"LEAD_BODY_HOOK", "REAR_BODY_HOOK",
]
const ACTION_ORDER := [
	"JAB", "CROSS", "LEAD_HOOK", "REAR_HOOK", "LEAD_UPPERCUT", "REAR_UPPERCUT",
	"LEAD_BODY_HOOK", "REAR_BODY_HOOK",
	"FEINT", "CLINCH",
	"BLOCK", "SLIP_LEFT", "SLIP_RIGHT",
	"IDLE",
]
# Action rows that show even at a zero count. The rebuilt grab decision is worth pinning
# visible — it can be rare in a technical fight, and a hidden zero reads as "never implemented"
# rather than "didn't happen this bout."
const ALWAYS_SHOWN := ["CLINCH"]

# Bucket keys match DebugPanel._track_combo_length's own bucketing exactly ("5+" for
# anything longer than 4) — labels here are just the display text for each key.
const COMBO_LENGTH_ORDER := ["1", "2", "3", "4", "5+"]
const COMBO_LENGTH_LABELS := {"1": "1 (single)", "2": "2", "3": "3", "4": "4", "5+": "5+"}

const ROW_HEIGHT := 24.0
const BAR_MAX_WIDTH := 220.0
const LABEL_WIDTH := 130.0
const LABEL_FONT_SIZE := 14
# Gap after the ACTUAL measured width of blue's label, before the red column starts.
const COLUMN_MARGIN := 24.0
const BLUE_COLOR := Color(0.3, 0.55, 1.0)
const RED_COLOR := Color(1.0, 0.35, 0.35)
# Landed fill sits INSIDE the thrown bar, brighter than the thrown (dim) bar behind it —
# same "outline = thrown, solid = landed" convention real punch-stat graphics use.
const BLUE_LANDED_COLOR := Color(0.65, 0.8, 1.0)
const RED_LANDED_COLOR := Color(1.0, 0.65, 0.65)

var _blue_counts: Dictionary = {}
var _red_counts: Dictionary = {}
var _blue_landed: Dictionary = {}
var _red_landed: Dictionary = {}
var _blue_combo_lengths: Dictionary = {}
var _red_combo_lengths: Dictionary = {}

# Called every time "Watch Summary" is pressed — DebugPanel hands over whatever it has
# tallied so far, live mid-fight or final once the fight has ended.
func set_data(blue_counts: Dictionary, red_counts: Dictionary, blue_landed: Dictionary, red_landed: Dictionary,
		blue_combo_lengths: Dictionary, red_combo_lengths: Dictionary) -> void:
	_blue_counts = blue_counts
	_red_counts = red_counts
	_blue_landed = blue_landed
	_red_landed = red_landed
	_blue_combo_lengths = blue_combo_lengths
	_red_combo_lengths = red_combo_lengths
	queue_redraw()

func _draw() -> void:
	var viewport_size := get_viewport_rect().size
	# Fully opaque — a translucent backdrop let the sidebar bleed through underneath and
	# was the actual cause of the "numbers contradict each other" report, not bad math.
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.05, 0.05, 0.05, 1.0))

	var rows: Array = []
	for action in ACTION_ORDER:
		var blue: int = _blue_counts.get(action, 0)
		var red: int = _red_counts.get(action, 0)
		if blue > 0 or red > 0 or action in ALWAYS_SHOWN:
			rows.append(action)

	# Combo-length rows always show (0 included) — five fixed buckets, always meaningful
	# to compare, unlike a punch type that may simply never come up in a given bout.
	var combo_rows: Array = COMBO_LENGTH_ORDER

	var content_height := 90.0 + rows.size() * ROW_HEIGHT + 40.0 + combo_rows.size() * ROW_HEIGHT
	var origin := Vector2(viewport_size.x / 2.0 - 340.0, (viewport_size.y - content_height) / 2.0)

	draw_string(ThemeDB.fallback_font, origin + Vector2(0.0, 0.0), "FIGHT SUMMARY — ACTIONS EXECUTED",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
	draw_string(ThemeDB.fallback_font, origin + Vector2(0.0, 22.0),
			"punches show landed/thrown — everything else is total times executed",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.6, 0.6))
	draw_string(ThemeDB.fallback_font, origin + Vector2(LABEL_WIDTH + 10.0, 54.0), "BLUE",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, BLUE_COLOR)
	# ONE red column start for every row, based on the widest blue label this draw will
	# render — a straight aligned column, not a jagged one, and still guaranteed wide
	# enough for every row since it is the actual measured maximum, not a guess.
	var bar_x := origin.x + LABEL_WIDTH + 10.0
	var red_bar_x := bar_x + BAR_MAX_WIDTH + 8.0 + _widest_blue_label(rows, combo_rows) + COLUMN_MARGIN
	draw_string(ThemeDB.fallback_font, Vector2(red_bar_x, origin.y + 54.0), "RED",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, RED_COLOR)

	for i in range(rows.size()):
		var action: String = rows[i]
		var is_punch: bool = action in PUNCH_TYPES
		var blue: int = _blue_counts.get(action, 0)
		var red: int = _red_counts.get(action, 0)
		var y := origin.y + 70.0 + i * ROW_HEIGHT
		draw_string(ThemeDB.fallback_font, Vector2(origin.x, y + 14.0), action,
				HORIZONTAL_ALIGNMENT_LEFT, LABEL_WIDTH, 14, Color.WHITE_SMOKE)
		# BLUE and RED are compared against each other for THIS row only (by thrown count,
		# or the plain count for non-punches), so the larger always fills its full bar — a
		# stat-sheet "who did more of this" read, not a fraction of the fight's total.
		var max_count: int = maxi(maxi(blue, red), 1)
		var blue_landed: int = _blue_landed.get(action, 0) if is_punch else -1
		var red_landed: int = _red_landed.get(action, 0) if is_punch else -1
		_draw_bar(bar_x, y, blue, blue_landed, max_count, BLUE_COLOR, BLUE_LANDED_COLOR)
		_draw_bar(red_bar_x, y, red, red_landed, max_count, RED_COLOR, RED_LANDED_COLOR)

	# Combo-length section: a separate labeled block, since a sequence length is not an
	# ActionType and does not belong mixed into the rows above.
	var section_y := origin.y + 70.0 + rows.size() * ROW_HEIGHT + 16.0
	draw_string(ThemeDB.fallback_font, Vector2(origin.x, section_y), "COMBO LENGTH (punches per thrown sequence)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	for i in range(combo_rows.size()):
		var bucket: String = combo_rows[i]
		var blue: int = _blue_combo_lengths.get(bucket, 0)
		var red: int = _red_combo_lengths.get(bucket, 0)
		var y := section_y + 24.0 + i * ROW_HEIGHT
		draw_string(ThemeDB.fallback_font, Vector2(origin.x, y + 14.0), COMBO_LENGTH_LABELS[bucket],
				HORIZONTAL_ALIGNMENT_LEFT, LABEL_WIDTH, 14, Color.WHITE_SMOKE)
		var max_count: int = maxi(maxi(blue, red), 1)
		_draw_bar(bar_x, y, blue, -1, max_count, BLUE_COLOR, BLUE_LANDED_COLOR)
		_draw_bar(red_bar_x, y, red, -1, max_count, RED_COLOR, RED_LANDED_COLOR)

# The text a bar prints next to itself — "landed/thrown" for a punch row, a bare count
# otherwise. Shared between the drawing pass and the width measurement so the two can
# never disagree about what is actually being rendered.
func _bar_label(thrown: int, landed: int) -> String:
	return ("%d/%d" % [landed, thrown]) if landed >= 0 else str(thrown)

func _label_width(text: String) -> float:
	return ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE).x

# Widest blue label across every row this draw will render, action rows and combo-length
# rows together — the single shared offset every row's red column starts at, so the
# column reads as one straight aligned bar chart instead of drifting row to row while
# still being guaranteed wide enough for the actual longest label, not a guessed constant.
func _widest_blue_label(rows: Array, combo_rows: Array) -> float:
	var widest := 0.0
	for action in rows:
		var is_punch: bool = action in PUNCH_TYPES
		var blue: int = _blue_counts.get(action, 0)
		var landed: int = _blue_landed.get(action, 0) if is_punch else -1
		widest = maxf(widest, _label_width(_bar_label(blue, landed)))
	for bucket in combo_rows:
		widest = maxf(widest, _label_width(_bar_label(_blue_combo_lengths.get(bucket, 0), -1)))
	return widest

# landed == -1 means "no landed concept for this action" (draws a plain bar + bare count).
# landed >= 0 draws the dim thrown bar with a brighter landed fill inside it, and prints
# "landed/thrown" instead of a bare number.
func _draw_bar(x: float, y: float, thrown: int, landed: int, max_count: int, thrown_color: Color, landed_color: Color) -> void:
	draw_rect(Rect2(Vector2(x, y), Vector2(BAR_MAX_WIDTH, 14.0)), Color(0.15, 0.15, 0.15))
	var thrown_width := BAR_MAX_WIDTH * thrown / float(max_count)
	draw_rect(Rect2(Vector2(x, y), Vector2(thrown_width, 14.0)), thrown_color)
	var label_pos := Vector2(x + BAR_MAX_WIDTH + 8.0, y + 12.0)
	if landed < 0:
		draw_string(ThemeDB.fallback_font, label_pos, str(thrown), HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, thrown_color)
		return
	var landed_width := BAR_MAX_WIDTH * landed / float(max_count)
	draw_rect(Rect2(Vector2(x, y), Vector2(landed_width, 14.0)), landed_color)
	draw_string(ThemeDB.fallback_font, label_pos, "%d/%d" % [landed, thrown],
			HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, landed_color)
