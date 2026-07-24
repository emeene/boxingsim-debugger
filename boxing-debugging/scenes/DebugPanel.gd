extends CanvasLayer

const MAX_LOG_LINES := 300

@onready var step_btn:    Button        = $VBoxContainer/HBoxContainer/StepButton
@onready var play_btn:    Button        = $VBoxContainer/HBoxContainer/PlayButton
@onready var pause_btn:   Button        = $VBoxContainer/HBoxContainer/PauseButton
@onready var blue_scores: RichTextLabel = $VBoxContainer/ScoresRow/BlueColumn/BlueScores
@onready var red_scores:  RichTextLabel = $VBoxContainer/ScoresRow/RedColumn/RedScores
@onready var tick_log:    RichTextLabel = $VBoxContainer/TickLog

# Newest tick first — the log reads as a stack, capped so it can't grow unbounded
var _log_lines: PackedStringArray = []

# Punch-only log (owner request 2026-07-12): the tick log drowns punches in movement
# noise. This one gets a line ONLY on impact ticks — offense is non-null exactly once
# per punch — so a whole round reads as a compact punch-by-punch account.
var _punch_log_lines: PackedStringArray = []
var _punch_log: RichTextLabel

# Punch stats, counted client-side from the per-tick offense verdicts (offense is non-null
# exactly once per punch, on its impact tick). [thrown, landed] per fighter.
var _punch_counts := {"f1": [0, 0], "f2": [0, 0]}
var _punch_stats_label: Label

# Combo tracking (combat-timing §3): the payload's comboCount is the live chain depth —
# 0 on single shots, 1 at the second punch of a 1-2. When it drops back to 0 during
# active play, a chain of depth+1 punches just ended; the bell also resets it, so break
# and ended ticks are ignored (a combo cancelled by the bell was never finished).
var _combo_depth := {"f1": 0, "f2": 0}
var _combo_counts := {"f1": 0, "f2": 0}

# Combo-LENGTH breakdown (owner request 2026-07-20): how many 1/2/3/4/5+-punch sequences
# a fighter threw, for the summary. This is DELIBERATELY separate from the comboCount-drop
# tracking above, which only ever fires for chains of length >=2 — a solo, non-chained
# punch's comboCount never rises above 0 in the first place, so there is no "drop back to
# 0" for it to trigger on. The signal that fires for every completed punch sequence, solo
# or chained, and ONLY for punch sequences, is the phase machine's RECOVERY -> READY
# transition: the backend resets combo bookkeeping there unconditionally ("the chain is
# over"), and only an OFFENSIVE non-feint punch ever enters RECOVERY at all (movement,
# defense and CLINCH resolve instantly within READY; a feint's 1-tick STARTUP returns
# straight to READY, skipping RECOVERY entirely). Each impact along the way records its own
# comboCount (0-based position in whatever sequence is currently open); the RECOVERY->READY
# transition finalizes that sequence's length as the last recorded comboCount + 1.
var _combo_length_counts := {"f1": {}, "f2": {}}
var _chain_peak_combo := {"f1": -1, "f2": -1}
var _previous_phase := {"f1": "", "f2": ""}

# The judges' cards are rendered once, on the ENDED payload — guarded in case the final
# state ever gets delivered twice (e.g. a reconnect)
var _cards_rendered := false

# Action breakdown (owner request 2026-07-20): every ActionType a fighter executed across
# the whole bout EXCEPT movement (owner ruling: everything bar movement — the debugger's
# ring view already reads footwork directly off the fighters, this summary is for the
# actions the ring view can't hold still long enough to count), shown as a bar chart on
# demand. Two counting rules, because a single rule would misattribute a live feint: the
# backend deliberately disguises a fake's 1-tick windup as a JAB in the action field
# (combat-timing §5, MatchEngine.displayedAction) so a client reacting to it sees exactly
# what the in-engine sensor does. OFFENSIVE_TYPES counts on the IMPACT tick only (offense
# non-null — the existing punch-log precedent), so a feint, which never produces an offense
# verdict, can never inflate a punch count no matter how it displays; FEINT counts on the
# `feinted` reveal tick, also immune. IDLE, defense and CLINCH are never disguised, so they
# are edge-triggered on the raw action field: a new count only when the value changes from
# the fighter's previous ACTIVE tick, the same "how many times did he choose to do this"
# reading the punch counts already give. MOVEMENT_TYPES ticks are skipped outright — not
# counted, not even used to update the edge-detection state — so a movement stretch is
# transparent to it: BLOCK -> MOVE_FORWARD -> BLOCK still reads as one held guard, not two.
const OFFENSIVE_TYPES := [
	"JAB", "CROSS", "LEAD_HOOK", "REAR_HOOK", "LEAD_UPPERCUT", "REAR_UPPERCUT",
	"LEAD_BODY_HOOK", "REAR_BODY_HOOK",
]
const MOVEMENT_TYPES := ["MOVE_FORWARD", "MOVE_BACKWARD", "MOVE_LEFT", "MOVE_RIGHT"]
var _action_counts := {"f1": {}, "f2": {}}
# THROWN and LANDED are tracked separately for the offensive types only (feint/clinch/
# movement/defense have no landed concept) — 2026-07-20 fix: the summary originally showed
# one bare number per punch type with no label, which read as contradicting the sidebar's
# combined landed/thrown total once the two were compared side by side.
var _action_landed := {"f1": {}, "f2": {}}
var _previous_action := {"f1": "", "f2": ""}
var _was_active := false
# A tie-up suspends both brains and runs under its own CLINCH match status, so the action
# field can't edge-trigger a clinch the way it does the other held states. Instead we count one
# CLINCH for each man the moment the status FIRST turns CLINCH — one per tie-up, matching the
# gold tether the ring draws.
var _was_clinched := false
var _action_summary: Control

# Persist the tick log to a file alongside the on-screen log (which is capped): the file keeps
# the WHOLE fight so a watched bout can be read back afterward. Opened by start_logging with the
# path Main builds from the clock and the matchup.
var _log_file: FileAccess = null

func _ready() -> void:
	step_btn.pressed.connect(func(): WebSocketClient.send_command("step"))
	play_btn.pressed.connect(func(): WebSocketClient.send_command("play"))
	pause_btn.pressed.connect(func(): WebSocketClient.send_command("pause"))
	# Speed buttons, built in code so no .tscn edit is needed. Fast-forward only changes the
	# tick interval — the fight itself is identical at any speed. ×8 makes a full 12-rounder
	# (breaks included) a ~6-minute watch instead of ~47.
	for mult in [1, 2, 4, 8]:
		var b := Button.new()
		b.text = "×%d" % mult
		b.pressed.connect(func(): WebSocketClient.send_command("speed", mult))
		$VBoxContainer/HBoxContainer.add_child(b)
	WebSocketClient.tick_received.connect(_on_tick)
	# Built in code so no .tscn edit is needed (same trick as Main's ended-label)
	_punch_stats_label = Label.new()
	# Labels clip long text unless word-wrap is turned on
	_punch_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_punch_stats_label.text = "BLUE 0/0 — RED 0/0 (landed/thrown)\ncombos BLUE 0 — RED 0"
	$VBoxContainer.add_child(_punch_stats_label)
	$VBoxContainer.move_child(_punch_stats_label, 1) # right under the buttons
	# Punch log, right under the tick log (built in code, same trick)
	var punch_header := Label.new()
	punch_header.text = "Punches"
	# Fixed height on purpose: the score columns are the panel's only stretching part,
	# so the button row always keeps its place at the bottom instead of being pushed
	# off-screen when the window is short. Both logs scroll, they don't need to grow.
	_punch_log = RichTextLabel.new()
	_punch_log.custom_minimum_size = Vector2(0, 150)
	$VBoxContainer.add_child(punch_header)
	$VBoxContainer.add_child(_punch_log)
	var after_tick_log := $VBoxContainer/TickLog.get_index() + 1
	$VBoxContainer.move_child(punch_header, after_tick_log)
	$VBoxContainer.move_child(_punch_log, after_tick_log + 1)
	# Action summary, built in code and attached over the WHOLE window (ring included) — a
	# CanvasLayer's children are already screen-space, so this does not need its own layer.
	# Hidden until the "Watch Summary" button is pressed (2026-07-20: was auto-shown on
	# ENDED; now on-demand at any point in the fight, current running counts, with a way
	# back to the ring view).
	_action_summary = Control.new()
	_action_summary.set_script(load("res://scenes/ActionSummary.gd"))
	_action_summary.set_anchors_preset(Control.PRESET_FULL_RECT)
	_action_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_action_summary.visible = false
	add_child(_action_summary)
	# BACK lives ON the summary (a child of it), so hiding the summary hides the button
	# too — it can only ever be pressed while there is something to go back from.
	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.position = Vector2(20, 20)
	back_btn.pressed.connect(func(): _action_summary.visible = false)
	_action_summary.add_child(back_btn)
	# WATCH SUMMARY lives in the main button row, always available — populates the
	# overlay with whatever has been tallied so far (a live peek mid-fight, the final
	# tally once the fight has ended) and shows it over the ring view.
	var watch_btn := Button.new()
	watch_btn.text = "Watch Summary"
	watch_btn.pressed.connect(func():
		_action_summary.set_data(_action_counts["f1"], _action_counts["f2"], _action_landed["f1"], _action_landed["f2"],
				_combo_length_counts["f1"], _combo_length_counts["f2"])
		_action_summary.visible = true
	)
	$VBoxContainer/HBoxContainer.add_child(watch_btn)

func _on_tick(payload: Dictionary) -> void:
	_count_punches("f1", payload["f1"])
	_count_punches("f2", payload["f2"])
	_log_punch(payload, "BLUE", payload["f1"])
	_log_punch(payload, "RED",  payload["f2"])
	_tally_actions(payload)
	_tally_clinch(payload)
	_track_combo("f1", "BLUE", payload)
	_track_combo("f2", "RED",  payload)
	_track_combo_length("f1", payload)
	_track_combo_length("f2", payload)
	# .get() defaults so an older backend payload without round fields still parses.
	# Two lines on purpose: one long line does not fit the panel and gets clipped.
	_punch_stats_label.text = "R%s [%s]  BLUE %d/%d — RED %d/%d (landed/thrown)\ncombos BLUE %d — RED %d" % [
		str(payload.get("roundNumber", 0)), str(payload.get("status", "?")),
		_punch_counts["f1"][1], _punch_counts["f1"][0],
		_punch_counts["f2"][1], _punch_counts["f2"][0],
		_combo_counts["f1"], _combo_counts["f2"]
	]
	_update_scores(blue_scores, payload["f1"]["scores"])
	_update_scores(red_scores,  payload["f2"]["scores"])
	var tick_line := "[%d] F1: %s | F2: %s" % [
		payload["tick"],
		_fighter_entry(payload["f1"]),
		_fighter_entry(payload["f2"])
	]
	_log_lines.insert(0, tick_line)
	# The on-screen log is newest-first and capped; the file gets every line in fight order.
	_write_log(tick_line)
	# At the final bell the payload carries the three judges' cards (null on a stoppage —
	# a KO needs no scorecard). Newest-first log, so the block lands on top of everything.
	var decision = payload.get("decision")
	if payload.get("status", "") == "ENDED" and decision != null and not _cards_rendered:
		_cards_rendered = true
		var block := _scorecard_lines(decision)
		for i in range(block.size() - 1, -1, -1):
			_log_lines.insert(0, block[i])
		for card_line in block:
			_write_log(card_line)
	if payload.get("status", "") == "ENDED":
		_close_log()
	if _log_lines.size() > MAX_LOG_LINES:
		_log_lines.resize(MAX_LOG_LINES)
	tick_log.text = "\n".join(_log_lines)

# Count one CLINCH for each man the instant a tie-up begins — see _was_clinched.
func _tally_clinch(payload: Dictionary) -> void:
	var clinched: bool = payload.get("status", "") == "CLINCH"
	if clinched and not _was_clinched:
		_action_counts["f1"]["CLINCH"] = _action_counts["f1"].get("CLINCH", 0) + 1
		_action_counts["f2"]["CLINCH"] = _action_counts["f2"].get("CLINCH", 0) + 1
	_was_clinched = clinched

# Open the fight's log file. Main calls this with the timestamp-and-matchup path.
func start_logging(path: String, header: String) -> void:
	_log_file = FileAccess.open(path, FileAccess.WRITE)
	if _log_file != null:
		_log_file.store_line(header)
		_log_file.store_line("")

func _write_log(line: String) -> void:
	if _log_file != null:
		_log_file.store_line(line)

func _close_log() -> void:
	if _log_file != null:
		_log_file.flush()
		_log_file.close()
		_log_file = null

# Quitting mid-fight still leaves a complete file up to the last tick watched.
func _exit_tree() -> void:
	_close_log()

# Two counting rules live here — see the class-level comment on OFFENSIVE_TYPES for why.
func _tally_actions(payload: Dictionary) -> void:
	var active: bool = payload.get("status", "") == "ROUND_ACTIVE"
	if active and not _was_active:
		# A round just (re)started (or this is the fight's first active tick) — whatever
		# the action field showed before a break belongs to a different engagement, so
		# the first active tick after one always counts fresh instead of comparing
		# against stale pre-break state.
		_previous_action["f1"] = ""
		_previous_action["f2"] = ""
	_was_active = active
	if not active:
		return
	_tally_one("f1", payload["f1"])
	_tally_one("f2", payload["f2"])

func _tally_one(key: String, f: Dictionary) -> void:
	var offense = f.get("offense")
	if offense != null:
		var punch: String = str(f["action"])
		_action_counts[key][punch] = _action_counts[key].get(punch, 0) + 1
		if offense["landed"]:
			_action_landed[key][punch] = _action_landed[key].get(punch, 0) + 1
		return
	if f.get("feinted", false):
		_action_counts[key]["FEINT"] = _action_counts[key].get("FEINT", 0) + 1
		return
	var action: String = str(f["action"])
	# A live feint's disguised windup and a real punch's non-impact ticks both show an
	# OFFENSIVE type here — both are already owned by the two branches above (the fake's
	# own reveal tick, the punch's own impact tick). MOVEMENT_TYPES is excluded from this
	# summary entirely (owner ruling). Both skip without touching _previous_action, so a
	# movement stretch (or a punch/feint) sandwiched between two IDLE/defense/clinch reads
	# never breaks up what is really one held state into two counted instances.
	if action in OFFENSIVE_TYPES or action in MOVEMENT_TYPES:
		return
	if action != _previous_action[key]:
		_action_counts[key][action] = _action_counts[key].get(action, 0) + 1
	_previous_action[key] = action

func _count_punches(key: String, f: Dictionary) -> void:
	var offense = f.get("offense")
	if offense != null:
		_punch_counts[key][0] += 1
		if offense["landed"]:
			_punch_counts[key][1] += 1

# Announces a finished chain in the punch log the moment the depth drops back to zero.
# .get() default so an older backend payload without comboCount is a permanent no-op.
func _track_combo(key: String, corner: String, payload: Dictionary) -> void:
	var depth: int = payload[key].get("comboCount", 0)
	var previous: int = _combo_depth[key]
	_combo_depth[key] = depth
	if previous > 0 and depth == 0 and payload.get("status", "") == "ROUND_ACTIVE":
		_combo_counts[key] += 1
		_punch_log_lines.insert(0, "[R%s t%d] %s combo: %d punches" % [
			str(payload.get("roundNumber", 0)), payload["tick"], corner, previous + 1
		])
		if _punch_log_lines.size() > MAX_LOG_LINES:
			_punch_log_lines.resize(MAX_LOG_LINES)
		_punch_log.text = "\n".join(_punch_log_lines)

# See the class-level comment on _combo_length_counts for why this cannot reuse the
# comboCount-drop logic above: a solo punch never leaves comboCount at 0, so RECOVERY ->
# READY is the only signal that fires for every completed sequence, length 1 included.
func _track_combo_length(key: String, payload: Dictionary) -> void:
	var f: Dictionary = payload[key]
	var offense = f.get("offense")
	if offense != null:
		_chain_peak_combo[key] = f.get("comboCount", 0)
	var phase: String = f.get("phase", "READY")
	if _previous_phase[key] == "RECOVERY" and phase == "READY" \
			and payload.get("status", "") == "ROUND_ACTIVE" and _chain_peak_combo[key] >= 0:
		var length: int = _chain_peak_combo[key] + 1
		var bucket: String = str(length) if length <= 4 else "5+"
		_combo_length_counts[key][bucket] = _combo_length_counts[key].get(bucket, 0) + 1
		_chain_peak_combo[key] = -1
	_previous_phase[key] = phase

# One clean line per punch, on its impact tick only: round, tick, corner, punch, verdict.
# On the impact tick the snapshot's action IS the committed punch (the phase machine
# flips to RECOVERY the same tick the verdict fires).
func _log_punch(payload: Dictionary, corner: String, f: Dictionary) -> void:
	var offense = f.get("offense")
	if offense == null:
		return
	var verdict: String
	if offense["landed"]:
		verdict = "LANDED %.2f dmg" % offense["damage"]
		# .get() so an older backend payload without the field still parses
		if offense.get("knockdown", false):
			verdict += " — KNOCKDOWN"
	else:
		verdict = "missed"
	_punch_log_lines.insert(0, "[R%s t%d] %s %s — %s" % [
		str(payload.get("roundNumber", 0)), payload["tick"], corner, str(f["action"]), verdict
	])
	if _punch_log_lines.size() > MAX_LOG_LINES:
		_punch_log_lines.resize(MAX_LOG_LINES)
	_punch_log.text = "\n".join(_punch_log_lines)

# Committed action + phase, annotated with the punch verdict on the tick it resolved
# (offense is null otherwise — with the phase machine that is the IMPACT tick)
func _fighter_entry(f: Dictionary) -> String:
	var entry: String = str(f["action"])
	var phase = f.get("phase", "READY")
	if phase != "READY":
		entry += " (%s)" % phase
	var offense = f.get("offense")
	if offense != null:
		if offense["landed"]:
			entry += " — LANDED %.2f dmg" % offense["damage"]
			# .get() so an older backend payload without the field still parses
			if offense.get("knockdown", false):
				entry += " — KNOCKDOWN"
		else:
			entry += " — MISSED"
	return entry

func _update_scores(label: RichTextLabel, scores: Array) -> void:
	label.clear()
	for entry in scores:
		label.append_text("%s: %.2f\n" % [entry["action"], entry["score"]])

# One line per judge — total, who his card went to, then the round-by-round awards so the
# verdict can be argued with (10-8 rounds are where the knockdowns were).
func _scorecard_lines(decision: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = ["=== JUDGES' CARDS (%s) ===" % str(decision["type"])]
	var judge := 1
	for card in decision["cards"]:
		var rounds := ""
		for r in card["rounds"]:
			rounds += "%d-%d " % [r["f1"], r["f2"]]
		lines.append("J%d: %d-%d %s | %s" % [
			judge, card["f1Total"], card["f2Total"],
			_card_leader(card["f1Total"], card["f2Total"]), rounds.strip_edges()
		])
		judge += 1
	return lines

func _card_leader(f1_total: int, f2_total: int) -> String:
	if f1_total > f2_total: return "BLUE"
	if f2_total > f1_total: return "RED"
	return "EVEN"
