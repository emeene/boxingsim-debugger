extends Node
# Global singleton — holds match identity after REST creation.
# Accessible from any script as MatchState.match_id, MatchState.ws_url.

var match_id: String = ""
var ws_url: String = ""

const RING_SCALE := 600.0 / 860.0
const RING_OFFSET_X := (1280.0 - 600.0) / 2.0
const RING_OFFSET_Y := (720.0 - 600.0) / 2.0

func to_screen(backend_x: float, backend_y: float) -> Vector2:
	return Vector2(
		RING_OFFSET_X + backend_x * RING_SCALE,
		RING_OFFSET_Y + backend_y * RING_SCALE
	)
