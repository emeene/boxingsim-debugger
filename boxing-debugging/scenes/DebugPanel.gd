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

# Punch stats, counted client-side from the per-tick offense verdicts (offense is non-null
# exactly once per punch, on its impact tick). [thrown, landed] per fighter.
var _punch_counts := {"f1": [0, 0], "f2": [0, 0]}
var _punch_stats_label: Label

func _ready() -> void:
	step_btn.pressed.connect(func(): WebSocketClient.send_command("step"))
	play_btn.pressed.connect(func(): WebSocketClient.send_command("play"))
	pause_btn.pressed.connect(func(): WebSocketClient.send_command("pause"))
	WebSocketClient.tick_received.connect(_on_tick)
	# Built in code so no .tscn edit is needed (same trick as Main's ended-label)
	_punch_stats_label = Label.new()
	_punch_stats_label.text = "BLUE 0/0 — RED 0/0 (landed/thrown)"
	$VBoxContainer.add_child(_punch_stats_label)
	$VBoxContainer.move_child(_punch_stats_label, 1) # right under the buttons

func _on_tick(payload: Dictionary) -> void:
	_count_punches("f1", payload["f1"])
	_count_punches("f2", payload["f2"])
	_punch_stats_label.text = "BLUE %d/%d — RED %d/%d (landed/thrown)" % [
		_punch_counts["f1"][1], _punch_counts["f1"][0],
		_punch_counts["f2"][1], _punch_counts["f2"][0]
	]
	_update_scores(blue_scores, payload["f1"]["scores"])
	_update_scores(red_scores,  payload["f2"]["scores"])
	_log_lines.insert(0, "[%d] F1: %s | F2: %s" % [
		payload["tick"],
		_fighter_entry(payload["f1"]),
		_fighter_entry(payload["f2"])
	])
	if _log_lines.size() > MAX_LOG_LINES:
		_log_lines.resize(MAX_LOG_LINES)
	tick_log.text = "\n".join(_log_lines)

func _count_punches(key: String, f: Dictionary) -> void:
	var offense = f.get("offense")
	if offense != null:
		_punch_counts[key][0] += 1
		if offense["landed"]:
			_punch_counts[key][1] += 1

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
		else:
			entry += " — MISSED"
	return entry

func _update_scores(label: RichTextLabel, scores: Array) -> void:
	label.clear()
	for entry in scores:
		label.append_text("%s: %.2f\n" % [entry["action"], entry["score"]])
