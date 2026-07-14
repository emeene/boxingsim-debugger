extends Node2D

@onready var f1: Node2D = $BlueFighter/Fighter
@onready var f2: Node2D = $RedFighter/Fighter

const RING_SIZE := 600.0

func _draw() -> void:
	var origin := Vector2(MatchState.RING_OFFSET_X, MatchState.RING_OFFSET_Y)
	draw_rect(Rect2(origin, Vector2(RING_SIZE, RING_SIZE)), Color.WHITE, false, 2.0)

func update(snapshot: Dictionary) -> void:
	# guard is null unless a defense is committed (combat-timing §4); old payloads lack the key
	f1.update_from_snapshot(snapshot["f1"]["x"], snapshot["f1"]["y"], snapshot["f1"]["health"], snapshot["f1"]["stamina"], snapshot["f1"].get("phase", "READY"), snapshot["f1"].get("guard"))
	f2.update_from_snapshot(snapshot["f2"]["x"], snapshot["f2"]["y"], snapshot["f2"]["health"], snapshot["f2"]["stamina"], snapshot["f2"].get("phase", "READY"), snapshot["f2"].get("guard"))
