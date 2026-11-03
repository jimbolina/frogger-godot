class_name FrogLordNotice
extends CanvasLayer
## A line of text along the bottom of the window that tells the player what
## FrogLord's watch is doing and hides itself after a few seconds. It never
## takes input, so play goes on underneath it.

## How long a notice stays, in seconds.
const SECONDS: float = 8.0
## The layer the notice draws on, above the game's own layers.
const LAYER: int = 120
## The colour of a progress line.
const INFO_COLOUR: Color = Color(0.85, 1.0, 0.85)
## The colour of a warning.
const WARNING_COLOUR: Color = Color(1.0, 0.85, 0.35)

var _panel: PanelContainer
var _label: Label
var _remaining: float = 0.0


func _init() -> void:
	layer = LAYER
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.7)
	style.set_content_margin_all(4.0)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 8.0
	_panel.offset_right = -8.0
	_panel.offset_top = -44.0
	_panel.offset_bottom = -8.0
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_panel)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 11)
	_panel.add_child(_label)
	_panel.hide()


## Shows [param text] for [constant SECONDS], in the warning colour when
## [param warning]; an empty text hides the notice.
func show_text(text: String, warning: bool = false) -> void:
	_label.text = text
	_label.add_theme_color_override("font_color", WARNING_COLOUR if warning else INFO_COLOUR)
	_remaining = SECONDS if not text.is_empty() else 0.0
	_panel.visible = not text.is_empty()


## The text shown, or "" when the notice is hidden.
func shown_text() -> String:
	return _label.text if _panel.visible else ""


func _process(delta: float) -> void:
	if _remaining <= 0.0:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		_panel.hide()
