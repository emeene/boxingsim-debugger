extends Node2D

# The fight's scheduled distance. Editable on the Main node in the Godot inspector, so a
# quick 4-rounder for a smoke test needs no code change.
@export_range(1, 15) var rounds: int = 12
# The matchup, off the calibration tier ladder (Phase 0 gate: distinct stat profiles must
# be watchable). Blue = tier1, red = tier2 — pick e.g. ELITE vs PRO from the inspector.
@export_enum("AMATEUR", "PRO", "GOOD", "ELITE", "WORLD_CLASS", "HALL_OF_FAMER") var tier1: String = "GOOD"
@export_enum("AMATEUR", "PRO", "GOOD", "ELITE", "WORLD_CLASS", "HALL_OF_FAMER") var tier2: String = "GOOD"
@export_enum("FLYWEIGHT", "BANTAMWEIGHT", "FEATHERWEIGHT", "LIGHTWEIGHT", "WELTERWEIGHT", "MIDDLEWEIGHT", "LIGHT_HEAVYWEIGHT", "HEAVYWEIGHT") var weight_class: String = "MIDDLEWEIGHT"

@onready var ring: Node2D = $Ring

var _ended_label: Label

func _ready() -> void:
	WebSocketClient.tick_received.connect(_on_tick)
	MatchHttpClient.create_debug_match(rounds, tier1, tier2, weight_class)
	_start_fight_log()
	# Built in code so no .tscn edit is needed — shown once the payload reports ENDED
	_ended_label = Label.new()
	_ended_label.add_theme_font_size_override("font_size", 40)
	_ended_label.position = Vector2(440.0, 20.0)
	_ended_label.visible = false
	add_child(_ended_label)

# Write this fight's tick log to a text file in the boxingsim-debugger repo root, named by the
# wall clock and the matchup: month-day-hour-minute-second-tier1-tier2.txt. The Godot project
# lives in boxing-debugging/, so the repo root is one directory up from res://.
func _start_fight_log() -> void:
	var t := Time.get_datetime_dict_from_system()
	var stamp := "%02d-%02d-%02d-%02d-%02d" % [t.month, t.day, t.hour, t.minute, t.second]
	var filename := "%s-%s-%s.txt" % [stamp, tier1, tier2]
	var repo_root := ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var path := repo_root.path_join(filename)
	var header := "%s vs %s · %s · %d rounds · started %s" % [tier1, tier2, weight_class, rounds, stamp]
	$DebugPanel.start_logging(path, header)

# Every time WebSocketClient emits tick_received, _on_tick gets called with the payload.
func _on_tick(payload: Dictionary) -> void:
	ring.update(payload)
	if payload.get("status", "") == "ENDED":
		_ended_label.text = _result_text(payload)
		_ended_label.visible = true

# The ring announcer's line: how the fight ended and for whom. The method field says KO/TKO/
# DECISION/DRAW; a decision also carries its type (unanimous/majority/split) in the decision
# object. .get() defaults so an older backend payload without these fields still shows the
# old KO-only banner.
func _result_text(payload: Dictionary) -> String:
	var winner = payload.get("winner")
	var who := "BLUE WINS" if winner == "f1" else "RED WINS"
	# The stoppage reason (hurt cycle §8) is the announcer's parenthetical: a counted-out
	# KO reads differently from an attrition one, and a wave-off TKO differently from the
	# three-knockdown rule. .get() default keeps older payloads on the bare method line.
	var reason := ""
	match payload.get("reason"):
		"COUNT_OUT":        reason = " (counted out)"
		"THREE_KNOCKDOWNS": reason = " (3 knockdowns)"
		"UNANSWERED":       reason = " (unanswered punches)"
	match payload.get("method"):
		"KO":
			return ("KO%s — %s" % [reason, who]) if winner != null else "DOUBLE KO — DRAW"
		"TKO":
			return "TKO%s — %s" % [reason, who]
		"DECISION":
			var type: String = str(payload["decision"]["type"]) # UNANIMOUS / MAJORITY / SPLIT
			return "%s DECISION — %s" % [type, who]
		"DRAW":
			return "DRAW — ON THE CARDS"
		_: # older backend payload without the method field
			match winner:
				"f1": return "KO — BLUE WINS"
				"f2": return "KO — RED WINS"
				_:    return "DOUBLE KO — DRAW"
