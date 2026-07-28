extends Control
# Draws the summary AND renders it as text for the exported log (see summary_lines below), so
# the screen and the file are built from one set of row definitions and can never drift apart.
# Deliberately NOT given a `class_name`: DebugPanel attaches this script with load() at runtime,
# so a global name it also referenced at parse time is a cyclic dependency and fails to parse.
# It calls summary_lines() on the instance instead, which needs no global name.
#
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
# COMBO LENGTH section (owner request, same day): how many 1/2/3/4/5/6+-punch sequences each
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
	# FEINT is the loaded setup that sells a punch; FAKE is the empty probe that only reads
	# the other man. They are separate actions doing separate jobs, so they get separate rows
	# — and seeing FAKE run into the hundreds while FEINT stays in single figures is exactly
	# the split working.
	"FEINT", "FAKE", "CLINCH",
	"BLOCK", "SLIP_LEFT", "SLIP_RIGHT",
	"IDLE",
]
# Action rows that show even at a zero count. The rebuilt grab decision is worth pinning
# visible — it can be rare in a technical fight, and a hidden zero reads as "never implemented"
# rather than "didn't happen this bout."
#
# The three defensive rows are pinned for exactly that reason and it was not hypothetical: a
# fighter who never got his hands up produced no rows at all, so the summary looked identical
# whether the defence was working, switched off by a rounding bug, or never built. A zero has to
# be visible as a zero — it is the single most important number on this screen when something is
# wrong, and hiding it is how a fighter defending himself 0.00% of the time went unnoticed.
const ALWAYS_SHOWN := ["CLINCH", "BLOCK", "SLIP_LEFT", "SLIP_RIGHT"]
# The defence section's own rows — guard TIME, not decisions. See DebugPanel._guard_ticks.
const GUARD_ORDER := ["BLOCK", "SLIP_LEFT", "SLIP_RIGHT"]

# Bucket keys match DebugPanel._track_combo_length's own bucketing exactly ("6+" for
# anything longer than 5) — labels here are just the display text for each key.
# The top bucket moved from "5+" to "6+" when the length cap was re-cut (roadmap item 13
# sub-item 5): the old formula could not produce five punches at ANY tier, so the "5+" row
# was structurally incapable of being non-zero and said nothing. A Hall-of-Famer now caps at
# six, so five and six are separate rows worth telling apart.
const COMBO_LENGTH_ORDER := ["1", "2", "3", "4", "5", "6+"]
const COMBO_LENGTH_LABELS := {"1": "1 (single)", "2": "2", "3": "3", "4": "4", "5": "5", "6+": "6+"}

const ROW_HEIGHT := 24.0
# Gap kept above and below the content once it is tall enough to scroll.
const TOP_MARGIN := 24.0
# One wheel notch. Two rows at a time — enough to get through the list quickly, small enough
# that a row never jumps past you.
const SCROLL_STEP := 48.0
# One judge per line, plus a heading — kept tighter than a bar row since it is plain text.
const CARD_LINE_HEIGHT := 18.0
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
# The judges' running card (owner request): the three cards as they stand over the rounds
# finished so far, shown ALWAYS rather than only at the end. Null before the first bell, when
# there is genuinely nothing to score, and still populated after a knockout — where the fight
# has no official card but "where it stood on points" is exactly what you want to know.
var _cards = null
# Guard time, counters and the cover-up drive — see DebugPanel._defense_data. Empty until a
# backend that sends the fields has been connected, in which case the section is skipped
# entirely rather than drawn as a block of zeroes that would read as "the defence is dead".
var _defense: Dictionary = {}
# Scroll position in pixels from the top of the content, and how far it is allowed to go —
# recomputed every draw from the real content height, so adding a section can never leave the
# limit stale. Mouse wheel, arrow keys, page keys and home/end all drive it (see _input).
var _scroll: float = 0.0
var _max_scroll: float = 0.0

# Scrolling input. Handled in _input rather than _gui_input on purpose: this control is created
# in code with MOUSE_FILTER_IGNORE so it never steals clicks from the ring underneath, which also
# means it receives no GUI events at all. _input sees everything, so the guard on `visible` is
# what keeps the summary from eating the wheel while the fight is on screen. Events are only
# marked handled when they actually moved something.
func _input(event: InputEvent) -> void:
	if not visible or _max_scroll <= 0.0:
		return
	var before := _scroll
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:   _scroll -= SCROLL_STEP
			MOUSE_BUTTON_WHEEL_DOWN: _scroll += SCROLL_STEP
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_UP:       _scroll -= SCROLL_STEP
			KEY_DOWN:     _scroll += SCROLL_STEP
			KEY_PAGEUP:   _scroll -= get_viewport_rect().size.y * 0.8
			KEY_PAGEDOWN: _scroll += get_viewport_rect().size.y * 0.8
			KEY_HOME:     _scroll = 0.0
			KEY_END:      _scroll = _max_scroll
	_scroll = clampf(_scroll, 0.0, _max_scroll)
	if _scroll != before:
		get_viewport().set_input_as_handled()
		queue_redraw()

# A plain track and thumb down the right edge, drawn only when there is something to scroll to.
# Without it the summary looks complete at whatever row happens to reach the bottom of the window,
# which is the failure this whole change exists to fix — a section you cannot see reads as a
# section that was never built.
func _draw_scrollbar(viewport_size: Vector2, content_height: float) -> void:
	if _max_scroll <= 0.0:
		return
	var track_x := viewport_size.x - 14.0
	var track_h := viewport_size.y - 2.0 * TOP_MARGIN
	draw_rect(Rect2(Vector2(track_x, TOP_MARGIN), Vector2(6.0, track_h)), Color(0.18, 0.18, 0.18))
	var thumb_h := maxf(32.0, track_h * (viewport_size.y / content_height))
	var thumb_y := TOP_MARGIN + (track_h - thumb_h) * (_scroll / _max_scroll)
	draw_rect(Rect2(Vector2(track_x, thumb_y), Vector2(6.0, thumb_h)), Color(0.55, 0.55, 0.55))

# Called every time "Watch Summary" is pressed — DebugPanel hands over whatever it has
# tallied so far, live mid-fight or final once the fight has ended.
func set_data(blue_counts: Dictionary, red_counts: Dictionary, blue_landed: Dictionary, red_landed: Dictionary,
		blue_combo_lengths: Dictionary, red_combo_lengths: Dictionary, cards = null, defense: Dictionary = {}) -> void:
	_defense = defense
	_blue_counts = blue_counts
	_red_counts = red_counts
	_blue_landed = blue_landed
	_red_landed = red_landed
	_blue_combo_lengths = blue_combo_lengths
	_red_combo_lengths = red_combo_lengths
	_cards = cards
	queue_redraw()

# The three judges' card as text: a heading with where the fight stands, then one line per
# judge with his totals, who he has ahead, and his round-by-round awards. Empty before the
# first bell — there is nothing to score yet, and an empty block is better than a row of
# zeroes pretending a round happened.
func _card_lines() -> PackedStringArray:
	if _cards == null:
		return PackedStringArray()
	var lines := PackedStringArray(["JUDGES' CARDS — %s (%s)" % [
		_card_leader(_cards["winner"]), str(_cards["type"])
	]])
	var judge := 1
	for card in _cards["cards"]:
		var rounds := ""
		for r in card["rounds"]:
			rounds += "%d-%d " % [r["f1"], r["f2"]]
		lines.append("J%d  %d-%d  %s   %s" % [
			judge, card["f1Total"], card["f2Total"],
			_card_leader_from_totals(card["f1Total"], card["f2Total"]), rounds.strip_edges()
		])
		judge += 1
	return lines

# The backend names the leader as F1 / F2 / DRAW; the debugger speaks in corners.
func _card_leader(winner) -> String:
	match str(winner):
		"F1": return "BLUE AHEAD"
		"F2": return "RED AHEAD"
		_: return "EVEN"

func _card_leader_from_totals(f1_total: int, f2_total: int) -> String:
	if f1_total > f2_total: return "BLUE"
	if f2_total > f1_total: return "RED"
	return "EVEN"

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

	# Combo-length rows always show (0 included) — six fixed buckets, always meaningful
	# to compare, unlike a punch type that may simply never come up in a given bout.
	var combo_rows: Array = COMBO_LENGTH_ORDER

	# The judges' card sits at the TOP, above the action rows: it is the one thing a viewer
	# always wants to know, and burying it under twenty bars would defeat the point of showing
	# it at all times. Everything below it is shifted by the block's height, so the whole
	# summary re-centres instead of overflowing the window.
	var card_lines := _card_lines()
	var card_block_h := 0.0
	if not card_lines.is_empty():
		card_block_h = 12.0 + card_lines.size() * CARD_LINE_HEIGHT

	# Guard rows + the counter row + two cover-up text lines, plus the heading and its gap.
	var defense_block_h := 0.0
	if not _defense.is_empty():
		# Guard rows, the counter row, then three lines of cover-up: its heading and one per corner.
		defense_block_h = 44.0 + (GUARD_ORDER.size() + 1) * ROW_HEIGHT + 3.0 * CARD_LINE_HEIGHT

	var content_height := 90.0 + card_block_h + rows.size() * ROW_HEIGHT + 40.0 + combo_rows.size() * ROW_HEIGHT + defense_block_h

	# Scrolling. The summary outgrew the window once the defence section landed, and a block that
	# runs off the bottom of the screen is the same as a block that was never drawn. When it fits
	# it stays centred exactly as before; when it does not, it pins to the top and scrolls.
	_max_scroll = maxf(0.0, content_height + 2.0 * TOP_MARGIN - viewport_size.y)
	_scroll = clampf(_scroll, 0.0, _max_scroll)
	var origin_y := (viewport_size.y - content_height) / 2.0 if _max_scroll <= 0.0 else TOP_MARGIN - _scroll
	var origin := Vector2(viewport_size.x / 2.0 - 340.0, origin_y)
	# Drawn first, at the far right edge where nothing else reaches, so the early return further
	# down (no defence data) still leaves the bar on screen.
	_draw_scrollbar(viewport_size, content_height)

	draw_string(ThemeDB.fallback_font, origin + Vector2(0.0, 0.0), "FIGHT SUMMARY — ACTIONS EXECUTED",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
	var subtitle := "punches show landed/thrown — everything else is total times executed"
	if _max_scroll > 0.0:
		subtitle += "   ·   scroll: wheel / arrows / page / home-end"
	draw_string(ThemeDB.fallback_font, origin + Vector2(0.0, 22.0), subtitle,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.6, 0.6))
	for i in range(card_lines.size()):
		# First line is the heading, the three after it are the judges — heading a touch
		# brighter so the block reads as one thing rather than four loose strings.
		var card_color := Color.WHITE if i == 0 else Color(0.82, 0.82, 0.82)
		draw_string(ThemeDB.fallback_font, origin + Vector2(0.0, 44.0 + i * CARD_LINE_HEIGHT),
				card_lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, card_color)
	draw_string(ThemeDB.fallback_font, origin + Vector2(LABEL_WIDTH + 10.0, 54.0 + card_block_h), "BLUE",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, BLUE_COLOR)
	# ONE red column start for every row, based on the widest blue label this draw will
	# render — a straight aligned column, not a jagged one, and still guaranteed wide
	# enough for every row since it is the actual measured maximum, not a guess.
	var bar_x := origin.x + LABEL_WIDTH + 10.0
	var red_bar_x := bar_x + BAR_MAX_WIDTH + 8.0 + _widest_blue_label(rows, combo_rows) + COLUMN_MARGIN
	draw_string(ThemeDB.fallback_font, Vector2(red_bar_x, origin.y + 54.0 + card_block_h), "RED",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, RED_COLOR)

	for i in range(rows.size()):
		var action: String = rows[i]
		var is_punch: bool = action in PUNCH_TYPES
		var blue: int = _blue_counts.get(action, 0)
		var red: int = _red_counts.get(action, 0)
		var y := origin.y + 70.0 + card_block_h + i * ROW_HEIGHT
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
	var section_y := origin.y + 70.0 + card_block_h + rows.size() * ROW_HEIGHT + 16.0
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

	if _defense.is_empty():
		return
	# DEFENCE section. Everything above counts DECISIONS; this counts what actually happened —
	# how long the hands were up, how many counters came out of it, and how much the man wanted
	# to cover up in the first place. Kept apart from the action rows on purpose: mixing a tick
	# count into a list of decision counts is how the two get compared by eye and misread.
	var defense_y := section_y + 24.0 + combo_rows.size() * ROW_HEIGHT + 16.0
	draw_string(ThemeDB.fallback_font, Vector2(origin.x, defense_y), "DEFENCE (ticks with hands up)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	var guard_ticks: Dictionary = _defense.get("guard_ticks", {})
	for i in range(GUARD_ORDER.size()):
		var g: String = GUARD_ORDER[i]
		var blue: int = guard_ticks.get("f1", {}).get(g, 0)
		var red: int = guard_ticks.get("f2", {}).get(g, 0)
		var y := defense_y + 24.0 + i * ROW_HEIGHT
		draw_string(ThemeDB.fallback_font, Vector2(origin.x, y + 14.0), g,
				HORIZONTAL_ALIGNMENT_LEFT, LABEL_WIDTH, 14, Color.WHITE_SMOKE)
		var max_count: int = maxi(maxi(blue, red), 1)
		_draw_bar(bar_x, y, blue, -1, max_count, BLUE_COLOR, BLUE_LANDED_COLOR)
		_draw_bar(red_bar_x, y, red, -1, max_count, RED_COLOR, RED_LANDED_COLOR)

	# Counters get the punch treatment (landed/thrown) because that is what they are: a punch
	# thrown inside the opening a block or a slip just bought.
	var counters: Dictionary = _defense.get("counters", {"f1": [0, 0], "f2": [0, 0]})
	var counter_y := defense_y + 24.0 + GUARD_ORDER.size() * ROW_HEIGHT
	draw_string(ThemeDB.fallback_font, Vector2(origin.x, counter_y + 14.0), "COUNTERS",
			HORIZONTAL_ALIGNMENT_LEFT, LABEL_WIDTH, 14, Color.WHITE_SMOKE)
	var blue_counter: Array = counters["f1"]
	var red_counter: Array = counters["f2"]
	var counter_max: int = maxi(maxi(blue_counter[0], red_counter[0]), 1)
	_draw_bar(bar_x, counter_y, blue_counter[0], blue_counter[1], counter_max, BLUE_COLOR, BLUE_LANDED_COLOR)
	_draw_bar(red_bar_x, counter_y, red_counter[0], red_counter[1], counter_max, RED_COLOR, RED_LANDED_COLOR)

	# The drive itself, as text rather than a bar — it is a 0-to-1 average, not a count, and
	# putting it on the same bar scale as a tick total would invite exactly the wrong comparison.
	# It carries its own sentence of explanation because the bare number is unreadable: "0%" tells
	# a viewer nothing about what is being measured or which direction is bad.
	var mean: Dictionary = _defense.get("cover_up_mean", {"f1": 0.0, "f2": 0.0})
	var peak: Dictionary = _defense.get("cover_up_peak", {"f1": 0.0, "f2": 0.0})
	var drive_y := counter_y + ROW_HEIGHT + 14.0
	draw_string(ThemeDB.fallback_font, Vector2(origin.x, drive_y),
			"WANTS HIS HANDS UP — 0% = unhurt, 100% = a smart man in deep trouble",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(origin.x, drive_y + CARD_LINE_HEIGHT + 4.0),
			"BLUE  average over the fight %.0f%%   worst moment %.0f%%" % [mean["f1"] * 100.0, peak["f1"] * 100.0],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, BLUE_COLOR)
	draw_string(ThemeDB.fallback_font, Vector2(origin.x, drive_y + 2.0 * CARD_LINE_HEIGHT + 4.0),
			"RED   average over the fight %.0f%%   worst moment %.0f%%" % [mean["f2"] * 100.0, peak["f2"] * 100.0],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, RED_COLOR)

# The text a bar prints next to itself — "landed/thrown" for a punch row, a bare count
# otherwise. Shared between the drawing pass and the width measurement so the two can
# never disagree about what is actually being rendered.
func _bar_label(thrown: int, landed: int) -> String:
	return ("%d/%d" % [landed, thrown]) if landed >= 0 else str(thrown)

# The same summary as plain text, for the exported log file. It reads the same fields _draw
# reads and walks the same row orders, so a file read back later and the screen on the night
# cannot tell different stories. Call set_data first — this renders whatever was last handed in.
func summary_lines() -> PackedStringArray:
	var lines := PackedStringArray(["", "=== FIGHT SUMMARY — ACTIONS EXECUTED ===",
			"punches show landed/thrown — everything else is total times executed", ""])
	for line in _card_lines():
		lines.append(line)
	if not _card_lines().is_empty():
		lines.append("")
	for action in ACTION_ORDER:
		var blue: int = _blue_counts.get(action, 0)
		var red: int = _red_counts.get(action, 0)
		if blue == 0 and red == 0 and not action in ALWAYS_SHOWN:
			continue
		if action in PUNCH_TYPES:
			lines.append("%-16s BLUE %d/%d   RED %d/%d" % [action,
					_blue_landed.get(action, 0), blue, _red_landed.get(action, 0), red])
		else:
			lines.append("%-16s BLUE %d   RED %d" % [action, blue, red])
	lines.append("")
	lines.append("COMBO LENGTH (punches per thrown sequence)")
	for bucket in COMBO_LENGTH_ORDER:
		lines.append("%-16s BLUE %d   RED %d" % [COMBO_LENGTH_LABELS[bucket],
				_blue_combo_lengths.get(bucket, 0), _red_combo_lengths.get(bucket, 0)])
	if _defense.is_empty():
		return lines
	lines.append("")
	lines.append("DEFENCE (ticks with hands up, out of %d active ticks)" % _defense.get("active_ticks", 0))
	var guard_ticks: Dictionary = _defense.get("guard_ticks", {})
	for g in GUARD_ORDER:
		lines.append("%-16s BLUE %d   RED %d" % [g,
				guard_ticks.get("f1", {}).get(g, 0), guard_ticks.get("f2", {}).get(g, 0)])
	var counters: Dictionary = _defense.get("counters", {"f1": [0, 0], "f2": [0, 0]})
	lines.append("%-16s BLUE %d/%d   RED %d/%d" % ["COUNTERS",
			counters["f1"][1], counters["f1"][0], counters["f2"][1], counters["f2"][0]])
	var mean: Dictionary = _defense.get("cover_up_mean", {"f1": 0.0, "f2": 0.0})
	var peak: Dictionary = _defense.get("cover_up_peak", {"f1": 0.0, "f2": 0.0})
	lines.append("WANTS HIS HANDS UP — 0% = unhurt, 100% = a smart man in deep trouble")
	lines.append("%-16s BLUE average %.0f%% worst %.0f%%   RED average %.0f%% worst %.0f%%" % ["COVER-UP",
			mean["f1"] * 100.0, peak["f1"] * 100.0, mean["f2"] * 100.0, peak["f2"] * 100.0])
	return lines

func _label_width(text: String) -> float:
	return ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE).x

# Widest blue label across every row this draw will render — action rows, combo-length rows
# and the defence rows together — the single shared offset every row's red column starts at, so
# the column reads as one straight aligned bar chart instead of drifting row to row while
# still being guaranteed wide enough for the actual longest label, not a guessed constant.
# The defence rows MUST be in here: they hold guard-time tick counts, which run into four
# figures where a punch count stays in three, so leaving them out would put the widest label on
# the whole screen underneath the red column and repeat the overlap bug fixed in July.
func _widest_blue_label(rows: Array, combo_rows: Array) -> float:
	var widest := 0.0
	for action in rows:
		var is_punch: bool = action in PUNCH_TYPES
		var blue: int = _blue_counts.get(action, 0)
		var landed: int = _blue_landed.get(action, 0) if is_punch else -1
		widest = maxf(widest, _label_width(_bar_label(blue, landed)))
	for bucket in combo_rows:
		widest = maxf(widest, _label_width(_bar_label(_blue_combo_lengths.get(bucket, 0), -1)))
	if not _defense.is_empty():
		var guard_ticks: Dictionary = _defense.get("guard_ticks", {})
		for g in GUARD_ORDER:
			widest = maxf(widest, _label_width(_bar_label(guard_ticks.get("f1", {}).get(g, 0), -1)))
		var blue_counter: Array = _defense.get("counters", {"f1": [0, 0]})["f1"]
		widest = maxf(widest, _label_width(_bar_label(blue_counter[0], blue_counter[1])))
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
