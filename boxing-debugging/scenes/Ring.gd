extends Node2D

@onready var f1: Node2D = $BlueFighter/Fighter
@onready var f2: Node2D = $RedFighter/Fighter

const RING_SIZE := 600.0

# Knockdown count (hurt cycle): the payload's `count` is the referee's current count and
# `downed` names who is on the canvas ("f1"/"f2"/"both", null when nobody). The number is
# drawn big over the ring while a count runs — 0 means the referee hasn't said "one" yet.
var _count: int = 0
var _downed = null
# The clinch (hurt cycle survival): while the payload's status says CLINCH the two men are
# tied up — a rope between the circles plus the word over the ring, so a hold can never be
# mistaken for two fighters idling at close range.
var _clinched: bool = false

func _draw() -> void:
	var origin := Vector2(MatchState.RING_OFFSET_X, MatchState.RING_OFFSET_Y)
	draw_rect(Rect2(origin, Vector2(RING_SIZE, RING_SIZE)), Color.WHITE, false, 2.0)
	if _downed != null and _count > 0:
		var center_top := origin + Vector2(RING_SIZE / 2.0 - 14.0, 64.0)
		draw_string(ThemeDB.fallback_font, center_top, str(_count),
				HORIZONTAL_ALIGNMENT_CENTER, -1, 56, Color.WHITE)
	if _clinched:
		# The fighters are direct children of origin-anchored wrappers, so their node
		# positions are in this ring's own space — the tether follows the same lerp the
		# circles do and never detaches from them.
		draw_line(f1.position, f2.position, Color.GOLD, 3.0)
		var label_pos := origin + Vector2(RING_SIZE / 2.0 - 44.0, 64.0)
		draw_string(ThemeDB.fallback_font, label_pos, "CLINCH",
				HORIZONTAL_ALIGNMENT_CENTER, -1, 32, Color.GOLD)

func update(snapshot: Dictionary) -> void:
	# guard is null unless a defense is committed (combat-timing §4); old payloads lack the key.
	# feinted flashes true for the one tick a fake completed (§5) — .get() default keeps
	# older backend payloads a permanent no-op, the comboCount precedent. downed/count are
	# the hurt cycle's additions, same additive contract.
	_count = snapshot.get("count", 0)
	_downed = snapshot.get("downed")
	_clinched = snapshot.get("status", "") == "CLINCH"
	f1.update_from_snapshot(snapshot["f1"]["x"], snapshot["f1"]["y"], snapshot["f1"]["health"], snapshot["f1"]["stamina"], snapshot["f1"].get("phase", "READY"), snapshot["f1"].get("guard"), snapshot["f1"].get("feinted", false), _downed == "f1" or _downed == "both", snapshot["f1"].get("stagger", 0.0), snapshot["f1"].get("morale", -1.0))
	f2.update_from_snapshot(snapshot["f2"]["x"], snapshot["f2"]["y"], snapshot["f2"]["health"], snapshot["f2"]["stamina"], snapshot["f2"].get("phase", "READY"), snapshot["f2"].get("guard"), snapshot["f2"].get("feinted", false), _downed == "f2" or _downed == "both", snapshot["f2"].get("stagger", 0.0), snapshot["f2"].get("morale", -1.0))
	queue_redraw()
