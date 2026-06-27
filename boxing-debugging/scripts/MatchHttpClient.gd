extends Node
# Handles match creation via REST. Single responsibility: one POST call.
# After a successful response, stores matchId + wsUrl in MatchState
# and tells WebSocketClient to open the connection.
#
# HTTPRequest is a Node — it must be added as a child so the engine drives it.
# The request_completed signal fires once with the full response when done.

signal match_created()
signal match_creation_failed(error: String)

const BASE_URL := "http://localhost:8080"

var _http: HTTPRequest

func _ready() -> void:
	# TODO: instantiate HTTPRequest, add_child it, connect request_completed signal
	pass

func create_debug_match() -> void:
	# TODO: call _http.request() with POST to BASE_URL + "/api/match?debug=true"
	# No body needed — the endpoint reads debug from the query param
	pass

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	# TODO: check result == HTTPRequest.RESULT_SUCCESS and response_code == 200
	# Parse body as JSON, store match_id and ws_url into MatchState
	# Call WebSocketClient.connect_to_match(MatchState.ws_url)
	# Emit match_created or match_creation_failed
	pass
