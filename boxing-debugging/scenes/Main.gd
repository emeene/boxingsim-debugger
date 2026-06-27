extends Node2D

@onready var ring: Node2D = $Ring

func _ready() -> void:
	WebSocketClient.tick_received.connect(_on_tick)
	MatchHttpClient.create_debug_match()
	
# Every time WebSocketClient emits tick_received, _on_tick gets called with the payload.
func _on_tick(payload: Dictionary) -> void:
	ring.update(payload)
