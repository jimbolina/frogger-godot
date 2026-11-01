class_name GraphicsPanel
extends CanvasLayer
## The debug graphics panel: loads, applies and saves the graphics settings, and the 0 key shows it.
##
## Registered as the GraphicsDebug autoload. Under the headless display server
## (tests and script checks) it builds, applies and writes nothing. Otherwise
## [method activate] loads the settings file into the live [GraphicsProfile],
## applies the engine-wide settings when the file exists (so a first run keeps
## any window or vsync options given on the command line) and builds the
## hidden view. The 0 key toggles the view unless it is bound to a game action.
## Edits apply at once and are saved after a short pause. It keeps working
## while the game is paused.

## Canvas layer above every game layer.
const LAYER: int = 100
## Key that shows and hides the panel.
const TOGGLE_KEY: Key = KEY_0
## Seconds after the last edit before the settings are saved.
const SAVE_DELAY: float = 0.5

## Where the settings are read and saved.
var store_path: String = GraphicsStore.DEFAULT_PATH
## The controls, or null until activated.
var view: GraphicsPanelView = null
## Why the last load or save failed, or "".
var last_error: String = ""

var _target: Viewport = null
var _applied: GraphicsSettings = null
var _save_timer: Timer = null


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		return
	activate(GraphicsStore.DEFAULT_PATH, get_viewport())


## Loads [param path] into the live profile, applies it to the engine and [param target] when the
## file exists, and builds the hidden view; later calls do nothing.
func activate(path: String, target: Viewport) -> void:
	if view != null:
		return
	store_path = path
	_target = target
	var store: GraphicsStore = GraphicsStore.load_from(path)
	_report(store.error)
	GraphicsProfile.replace(store.settings)
	if FileAccess.file_exists(path):
		GraphicsApplier.apply_all(target, store.settings)
	_applied = store.settings.copy()
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DELAY
	_save_timer.timeout.connect(save_now)
	add_child(_save_timer)
	view = GraphicsPanelView.new()
	view.build(store.settings)
	view.visible = false
	view.edited.connect(_on_edited)
	add_child(view)


## Whether the view is showing.
func is_open() -> bool:
	return view != null and view.visible


## Shows or hides the view, showing the live settings when it opens.
func toggle() -> void:
	if view == null:
		return
	view.visible = not view.visible
	if view.visible:
		view.settings.assign(GraphicsProfile.current())
		view.refresh()


## Writes the applied settings to [member store_path] now.
func save_now() -> void:
	if _save_timer != null:
		_save_timer.stop()
	if _applied != null:
		_report(GraphicsStore.save(_applied, store_path))


## Whether a save is waiting for the edit pause to end.
func save_pending() -> bool:
	return _save_timer != null and not _save_timer.is_stopped()


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if view == null or key == null or not key.pressed or key.echo:
		return
	var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	if code != TOGGLE_KEY:
		return
	if game_input().command(key) != 0:
		return
	toggle()
	get_viewport().set_input_as_handled()


## Player 1's key bindings as the game screen reads them, fresh on every call.
func game_input() -> BindingInput:
	return BindingInput.from_array(FrontEndSession.settings().key_bindings)


func _on_edited(values: GraphicsSettings) -> void:
	GraphicsProfile.replace(values)
	GraphicsApplier.apply_changed(_target, _applied, values)
	_applied.assign(values)
	_save_timer.start()


func _report(problem: String) -> void:
	last_error = problem
	if not problem.is_empty():
		push_warning(problem)
