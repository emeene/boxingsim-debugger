extends Node2D

@onready var f1: Node2D = $BlueFighter/Fighter
@onready var f2: Node2D = $RedFighter/Fighter

const RING_SIZE := 600.0

# Knockdown count (hurt cycle): the payload's `count` is the referee's current count and
# `downed` names who is on the canvas ("f1"/"f2"/"both", null when nobody). The number is
# drawn big over the ring while a count runs — 0 means the referee hasn't said "one" yet.
var _count: int = 0
var _downed = null

func _draw() -> void:
	var origin := Vector2(MatchState.RING_OFFSET_X, MatchState.RING_OFFSET_Y)
	draw_rect(Rect2(origin, Vector2(RING_SIZE, RING_SIZE)), Color.WHITE, false, 2.0)
	if _downed != null and _count > 0:
		var center_top := origin + Vector2(RING_SIZE / 2.0 - 14.0, 64.0)
		draw_string(ThemeDB.fallback_font, center_top, str(_count),
				HORIZONTAL_ALIGNMENT_CENTER, -1, 56, Color.WHITE)

func update(snapshot: Dictionary) -> void:
	# guard is null unless a defense is committed (combat-timing §4); old payloads lack the key.
	# feinted flashes true for the one tick a fake completed (§5) — .get() default keeps
	# older backend payloads a permanent no-op, the comboCount precedent. downed/count are
	# the hurt cycle's additions, same additive contract.
	_count = snapshot.get("count", 0)
	_downed = snapshot.get("downed")
	f1.update_from_snapshot(snapshot["f1"]["x"], snapshot["f1"]["y"], snapshot["f1"]["health"], snapshot["f1"]["stamina"], snapshot["f1"].get("phase", "READY"), snapshot["f1"].get("guard"), snapshot["f1"].get("feinted", false), _downed == "f1" or _downed == "both", snapshot["f1"].get("stagger", 0.0))
	f2.update_from_snapshot(snapshot["f2"]["x"], snapshot["f2"]["y"], snapshot["f2"]["health"], snapshot["f2"]["stamina"], snapshot["f2"].get("phase", "READY"), snapshot["f2"].get("guard"), snapshot["f2"].get("feinted", false), _downed == "f2" or _downed == "both", snapshot["f2"].get("stagger", 0.0))
	queue_redraw()
