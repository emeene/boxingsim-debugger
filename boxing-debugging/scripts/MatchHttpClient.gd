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
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

func create_debug_match(rounds: int = 12, tier1: String = "GOOD", tier2: String = "GOOD", weight_class: String = "MIDDLEWEIGHT") -> void:
	var url := BASE_URL + "/api/match?debug=true&rounds=%d&tier1=%s&tier2=%s&weight=%s" % [rounds, tier1, tier2, weight_class]
	_http.request(url, [], HTTPClient.METHOD_POST, "")

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		match_creation_failed.emit("HTTP error: %d" % response_code)
		return
	var json := JSON.new()
	json.parse(body.get_string_from_utf8())
	var data: Dictionary = json.get_data()
	MatchState.match_id = data["matchId"]
	MatchState.ws_url = data["wsUrl"]
	WebSocketClient.connect_to_match(MatchState.ws_url)
	match_created.emit()
