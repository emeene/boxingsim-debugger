extends CanvasLayer

@onready var step_btn:    Button        = $VBoxContainer/HBoxContainer/StepButton
@onready var play_btn:    Button        = $VBoxContainer/HBoxContainer/PlayButton
@onready var pause_btn:   Button        = $VBoxContainer/HBoxContainer/PauseButton
@onready var blue_scores: RichTextLabel = $VBoxContainer/BlueScores
@onready var red_scores:  RichTextLabel = $VBoxContainer/RedScores
@onready var tick_log:    RichTextLabel = $VBoxContainer/TickLog

func _ready() -> void:
	step_btn.pressed.connect(func(): WebSocketClient.send_command("step"))
	play_btn.pressed.connect(func(): WebSocketClient.send_command("play"))
	pause_btn.pressed.connect(func(): WebSocketClient.send_command("pause"))
	WebSocketClient.tick_received.connect(_on_tick)

func _on_tick(payload: Dictionary) -> void:
	_update_scores(blue_scores, payload["f1"]["scores"])
	_update_scores(red_scores,  payload["f2"]["scores"])
	tick_log.append_text("[%d] F1: %s | F2: %s\n" % [
		payload["tick"],
		payload["f1"]["action"],
		payload["f2"]["action"]
	])

func _update_scores(label: RichTextLabel, scores: Array) -> void:
	label.clear()
	for entry in scores:
		label.append_text("%s: %.2f\n" % [entry["action"], entry["score"]])
