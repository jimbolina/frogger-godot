class_name HighScoreTableView
extends Control
## The high-score view page driven by a [HighScoreTour] at 30 Hz: the scrolly main table on the
## water through the page's static camera ([constant OptionsCamera.HS_STATIC]), or the level
## stack ([method LevelStackView.create_for_scores]) whose spun-out level shows its three best
## rows, with the prompt and, from the options page, the glowing side arrows.
##
## The shared water's frame count advances every tick in both views (the options viewport's frame
## count); only the table draws the water. A tick that switches the view rebuilds it from the
## tour's new table or stack. The table's prompt sits at [method HighScoreTour.prompt_x] on
## [constant StackLayout.PROMPT_Y]; the stack's prompt and title are the stack panel's. The
## arrows' colour is [method HighScoreTour.arrow_glow] of the frame count. Without
## [OptionsModels] the table draws only the water.
##
## Up/Down (held) and Left/Right (pressed) are player 1's bound keys read through [member input];
## Enter, keypad Enter or Space (fire) and Escape (back) are fixed, as [OptionsMenu.Buttons]. Each tick's [enum HighScoreTour.EventKind] values are raised through
## [signal page_event]; the page has ended once [member HighScoreTour.request] is not NONE.

## A [enum HighScoreTour.EventKind] raised by the last tick.
signal page_event(kind: int)

## Seconds per tick.
const PERIOD: float = GameplayHost.PERIOD
## Image of both side arrows (im_opt_arrow); the left one is drawn flipped horizontally
## (HSView.c:744-746).
const ARROW_IMAGE: String = "opt_arrow"

## The tour being drawn.
var tour: HighScoreTour
## The table's water and camera while the tour shows the table, otherwise null.
var water: MenuWaterView
## The table's models while the tour shows the table, otherwise null.
var table: HighScoreSceneView
## The level stack while the tour shows it, otherwise null.
var stack_view: LevelStackView
## Interpolate between the last two ticks; off draws each tick as committed.
var smoothing_enabled: bool = true
## Time since the last tick.
var elapsed: float = 0.0
## Player 1's bindings for the direction keys.
var input: BindingInput = BindingInput.new()

var _assets: FrontEndAssets
var _models: OptionsModels
var _water: MenuWater
var _stack: LevelStack
var _progress: LevelProgress
var _board: HighScoreBoard
var _overlay: Control
var _up_held: bool = false
var _down_held: bool = false
var _up_tapped: bool = false
var _down_tapped: bool = false
var _left: bool = false
var _right: bool = false
var _fire: bool = false
var _back: bool = false


## A page drawing [param page_tour] over [param water_animation], with [param stack] and
## [param progress] for the level stack, [param board] for its rows and [param with_models].
static func create(assets: FrontEndAssets, water_animation: MenuWater, page_tour: HighScoreTour, stack: LevelStack,
		progress: LevelProgress, board: HighScoreBoard, with_models: OptionsModels = null) -> HighScoreTableView:
	var view := HighScoreTableView.new()
	view._assets = assets
	view._models = with_models
	view._water = water_animation
	view._stack = stack
	view._progress = progress
	view._board = board
	view.tour = page_tour
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view._overlay = Control.new()
	view._overlay.name = "Overlay"
	view._overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view._overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view._overlay.draw.connect(view._draw_overlay)
	view.add_child(view._overlay)
	view._rebuild()
	return view


## Advances the tour one tick with [param buttons], redraws, raises the events and returns them.
func tick(buttons: OptionsMenu.Buttons) -> Array[int]:
	if tour.request != HighScoreTour.Request.NONE:
		return []
	if water != null:
		water.tick()
	else:
		_water.advance()
	var events: Array[int] = tour.tick(buttons, _water)
	if events.has(HighScoreTour.EventKind.SWITCHED):
		_rebuild()
	elif table != null:
		table.step()
	elif stack_view != null:
		stack_view.follow(String(tour.prompt), tour.title_visible, tour.shown_level, tour.background_counter)
	render(0.0 if smoothing_enabled else 1.0)
	for kind: int in events:
		page_event.emit(kind)
	return events


## Draws [param fraction] of the way from the previous tick to the last one.
func render(fraction: float) -> void:
	var weight: float = clampf(fraction, 0.0, 1.0) if smoothing_enabled else 1.0
	if water != null:
		water.render(weight)
	if table != null:
		table.draw(weight, HighScoreTour.STATIC_CAMERA_SOURCE, HighScoreTour.STATIC_CAMERA_TARGET)
	if stack_view != null:
		stack_view.render(weight)
	_overlay.queue_redraw()


## The buttons for the next tick from the keys since the last one.
func sample_buttons() -> OptionsMenu.Buttons:
	var held: int = 0
	if _up_held or _up_tapped:
		held |= OptionsMenu.Buttons.UP
	if _down_held or _down_tapped:
		held |= OptionsMenu.Buttons.DOWN
	var pressed: int = 0
	if _left:
		pressed |= OptionsMenu.Buttons.LEFT
	if _right:
		pressed |= OptionsMenu.Buttons.RIGHT
	if _fire:
		pressed |= OptionsMenu.Buttons.FIRE
	if _back:
		pressed |= OptionsMenu.Buttons.BACK
	_up_tapped = false
	_down_tapped = false
	_left = false
	_right = false
	_fire = false
	_back = false
	return OptionsMenu.Buttons.new(held, pressed)


func _ready() -> void:
	if water != null:
		water.set_process(false)


func _process(delta: float) -> void:
	if tour.request != HighScoreTour.Request.NONE:
		return
	elapsed += delta
	if elapsed >= PERIOD:
		elapsed = 0.0 if elapsed > PERIOD * 2.0 else elapsed - PERIOD
		tick(sample_buttons())
	if tour.request == HighScoreTour.Request.NONE:
		render(elapsed / PERIOD)


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or key.echo:
		return
	match input.action(key):
		KeyBindings.Action.UP:
			_up_held = key.pressed
			_up_tapped = _up_tapped or key.pressed
			_handled()
			return
		KeyBindings.Action.DOWN:
			_down_held = key.pressed
			_down_tapped = _down_tapped or key.pressed
			_handled()
			return
		KeyBindings.Action.LEFT:
			_left = _left or key.pressed
			_handled()
			return
		KeyBindings.Action.RIGHT:
			_right = _right or key.pressed
			_handled()
			return
	match key.physical_keycode:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_fire = _fire or key.pressed
		KEY_ESCAPE:
			_back = _back or key.pressed
		_:
			return
	_handled()


func _handled() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func _rebuild() -> void:
	for child: Node in [water, stack_view]:
		if child != null:
			remove_child(child)
			child.queue_free()
	water = null
	table = null
	stack_view = null
	if tour.operation == HighScoreTour.Operation.SCROLLY:
		water = MenuWaterView.create_with_camera(_water, _assets.texture("opt_env_sky"), _assets.texture("opt_bank3"))
		water.set_process(false)
		water.camera.transform = MenuWaterView.camera_transform(HighScoreTour.STATIC_CAMERA_SOURCE, HighScoreTour.STATIC_CAMERA_TARGET)
		add_child(water)
		if is_inside_tree():
			water.set_process(false)
		table = HighScoreSceneView.create_for(tour.scene, _models)
		table.smoothing_enabled = smoothing_enabled
		water.add_child(table)
	else:
		stack_view = LevelStackView.create_for_scores(_assets, _stack, _progress, tour.selector, _board)
		stack_view.smoothing_enabled = smoothing_enabled
		add_child(stack_view)
		stack_view.follow(String(tour.prompt), tour.title_visible, tour.shown_level, tour.background_counter)
	move_child(_overlay, get_child_count() - 1)
	render(1.0)


func _draw_overlay() -> void:
	if table != null:
		_sprite(String(tour.prompt), Vector2(tour.prompt_x(_width(String(tour.prompt))), StackLayout.PROMPT_Y), Color.WHITE)
	var glow: float = minf(float(HighScoreTour.arrow_glow(tour.frame)) / StackPanel.NEUTRAL_COLOUR, 1.0)
	var colour := Color(glow, glow, glow)
	if tour.left_arrow_visible:
		_sprite(ARROW_IMAGE, Vector2(HighScoreTour.ARROW_LEFT), colour, true)
	if tour.right_arrow_visible:
		_sprite(ARROW_IMAGE, Vector2(HighScoreTour.ARROW_RIGHT), colour)


func _width(image_name: String) -> int:
	var record: VloImage = _assets.image_record(image_name)
	return record.width if record != null else 0


func _sprite(image_name: String, at: Vector2, colour: Color, flipped: bool = false) -> void:
	var record: VloImage = _assets.image_record(image_name)
	var texture: Texture2D = _assets.texture(image_name)
	if record == null or texture == null:
		return
	var size := Vector2(record.width, record.height)
	var target := Rect2(at + Vector2(size.x, 0.0), Vector2(-size.x, size.y)) if flipped else Rect2(at, size)
	_overlay.draw_texture_rect_region(texture, target, Rect2(TextureBuilder.pixel_rect(record)), colour)
