class_name FrameStatsLabel
extends Label
## Frames per second, process time and draw calls, refreshed a few times a second while shown.

## Seconds between refreshes.
const INTERVAL: float = 0.25

var _elapsed: float = INTERVAL


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		_elapsed = INTERVAL
		return
	_elapsed += delta
	if _elapsed < INTERVAL:
		return
	_elapsed = 0.0
	refresh()


## Rewrites the text from the engine's current counters.
func refresh() -> void:
	var fps: float = Performance.get_monitor(Performance.TIME_FPS)
	var process_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var draws: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	text = "%d FPS  process %.2f ms  %d draws" % [roundi(fps), process_ms, draws]
