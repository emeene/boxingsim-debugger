extends Node
# Manages the WebSocket connection to the backend for one match.
# Autoloaded as "WebSocketClient" — call from anywhere.
#
# Data flow:
#   Godot → backend : send_command("step") / ("play") / ("pause")
#   backend → Godot : JSON text frames (MatchTickPayload)
#
# WebSocketPeer is NOT a Node. It has no scene tree presence and receives
# no automatic engine callbacks. poll() must be called every frame to:
#   1. Advance the internal state machine (CONNECTING → OPEN → CLOSING → CLOSED)
#   2. Drain the OS receive buffer into the internal packet queue
# Without poll(), the connection never opens and no packets are ever readable.

signal tick_received(payload: Dictionary)
signal connected()
signal disconnected()

var _peer: WebSocketPeer = WebSocketPeer.new()
var _state: WebSocketPeer.State = WebSocketPeer.STATE_CLOSED

func connect_to_match(url: String) -> void:
	_peer.connect_to_url(url)


func send_command(command: String) -> void:
	# TODO: send {"command": command} as a text frame upstream
	# Only valid when _state == WebSocketPeer.STATE_OPEN
	if _state == WebSocketPeer.STATE_OPEN:
		_peer.send_text('{"command":"' + command + '"}')
	return

func _process(_delta: float) -> void:
	_peer.poll()

	var new_state := _peer.get_ready_state()

	if _state != WebSocketPeer.STATE_OPEN and new_state == WebSocketPeer.STATE_OPEN:
		connected.emit()
	elif _state == WebSocketPeer.STATE_OPEN and new_state == WebSocketPeer.STATE_CLOSED:
		disconnected.emit()

	_state = new_state

	while _peer.get_available_packet_count() > 0:
		var json := JSON.new()
		json.parse(_peer.get_packet().get_string_from_utf8())
		tick_received.emit(json.get_data())
