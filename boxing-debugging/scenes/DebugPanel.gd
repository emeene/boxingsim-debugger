extends CanvasLayer

const MAX_LOG_LINES := 300

@onready var step_btn:    Button        = $VBoxContainer/HBoxContainer/StepButton
@onready var play_btn:    Button        = $VBoxContainer/HBoxContainer/PlayButton
@onready var pause_btn:   Button        = $VBoxContainer/HBoxContainer/PauseButton
@onready var blue_scores: RichTextLabel = $VBoxContainer/BlueScores
@onready var red_scores:  RichTextLabel = $VBoxContainer/RedScores
@onready var tick_log:    RichTextLabel = $VBoxContainer/TickLog

# Newest tick first — the log reads as a stack, capped so it can't grow unbounded
var _log_lines: PackedStringArray = []

func _ready() -> void:
	step_btn.pressed.connect(func(): WebSocketClient.send_command("step"))
	play_btn.pressed.connect(func(): WebSocketClient.send_command("play"))
	pause_btn.pressed.connect(func(): WebSocketClient.send_command("pause"))
	WebSocketClient.tick_received.connect(_on_tick)

func _on_tick(payload: Dictionary) -> void:
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

# Action, annotated with the punch verdict on the tick it resolved (offense is null otherwise)
func _fighter_entry(f: Dictionary) -> String:
	var entry: String = str(f["action"])
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
