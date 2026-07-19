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

# The judges' cards are rendered once, on the ENDED payload — guarded in case the final
# state ever gets delivered twice (e.g. a reconnect)
var _cards_rendered := false

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

func _on_tick(payload: Dictionary) -> void:
	_count_punches("f1", payload["f1"])
	_count_punches("f2", payload["f2"])
	_log_punch(payload, "BLUE", payload["f1"])
	_log_punch(payload, "RED",  payload["f2"])
	_track_combo("f1", "BLUE", payload)
	_track_combo("f2", "RED",  payload)
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
	_log_lines.insert(0, "[%d] F1: %s | F2: %s" % [
		payload["tick"],
		_fighter_entry(payload["f1"]),
		_fighter_entry(payload["f2"])
	])
	# At the final bell the payload carries the three judges' cards (null on a stoppage —
	# a KO needs no scorecard). Newest-first log, so the block lands on top of everything.
	var decision = payload.get("decision")
	if payload.get("status", "") == "ENDED" and decision != null and not _cards_rendered:
		_cards_rendered = true
		var block := _scorecard_lines(decision)
		for i in range(block.size() - 1, -1, -1):
			_log_lines.insert(0, block[i])
	if _log_lines.size() > MAX_LOG_LINES:
		_log_lines.resize(MAX_LOG_LINES)
	tick_log.text = "\n".join(_log_lines)

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
