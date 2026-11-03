class_name SetupPageView
extends VBoxContainer
## The controls of one setup page, built in code over its [SetupFlow].
##
## The screen shows one page view at a time. A view changes its page model in
## response to the player and emits [signal edited] so the screen refreshes
## its navigation; [method shown] runs each time the page appears.

## The page's state changed.
signal edited

## The flow whose page this view shows.
var flow: SetupFlow
## The screen holding the view, which owns the files and the process.
var screen: SetupScreen


## Builds the controls for [param over] inside [param host].
func setup(over: SetupFlow, host: SetupScreen) -> void:
	flow = over
	screen = host
	add_theme_constant_override("separation", 6)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	build()
	refresh()


## Adds the page's controls.
func build() -> void:
	pass


## Shows the page model's state in the controls.
func refresh() -> void:
	pass


## Runs when the page appears.
func shown() -> void:
	refresh()


## A label that wraps its text, added to [param parent].
static func add_text(parent: Control, text: String = "", muted: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.x = 120
	if muted:
		label.modulate = Color(1, 1, 1, 0.7)
	parent.add_child(label)
	return label


## A row with a path field and a Browse button, added to [param parent];
## returns the field. [param on_browse] runs when Browse is pressed and
## [param on_submit] when the field's text is entered or leaves focus.
static func add_path_row(parent: Control, placeholder: String, on_browse: Callable,
		on_submit: Callable) -> LineEdit:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.text_submitted.connect(func(text: String) -> void: on_submit.call(text))
	field.focus_exited.connect(func() -> void: on_submit.call(field.text))
	row.add_child(field)
	var browse := Button.new()
	browse.text = "Browse…"
	browse.pressed.connect(on_browse)
	row.add_child(browse)
	return field
