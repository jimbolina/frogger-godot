class_name HighScoreEntryView
extends Control
## The high-score name-entry page: the front-end water seen through the page's static camera,
## with the 30 letter pads, the three initials pads, the six static extras, the frog, its jump
## shadow, the landing splashes and the frog's poly-piece pop, placed by a
## [HighScoreEntryScene] stepped with a [HighScoreEntry] at 30 Hz.
##
## The view drives its water: each tick advances the shared frame count, then the entry and
## scene step with that count. An initials pad swaps its model when the entry's pad letter
## changes, half-way through its flip. The frog is the flipbook GENM_FROG at update period 2, one
## shot; without it ([member OptionsModels.entry_frog] null) GEN_FROG plays GEN_FROG_WAIT1 for
## sitting and GEN_FROG_HOP for hopping. END hides the frog and its shadow and pops its polygons
## for [constant HighScoreEntry.POP_DURATION] ticks; the pop explosion's particles are not drawn.
## Without [OptionsModels] (tests without player data) no model or sprite is drawn.
##
## Player 1's bound UP, DOWN, LEFT and RIGHT keys ([BindingInput]) are held directions; Enter,
## keypad Enter or Space is fire, counted once per press. There is no cancel key. Each tick's
## events are raised through [signal page_event]; the page has ended once
## [member HighScoreEntry.finished]. Between ticks the water and models are interpolated.

## A [enum HighScoreEntry.EventKind] raised by the last tick.
signal page_event(kind: int)

## Seconds per tick.
const PERIOD: float = GameplayHost.PERIOD
## GEN_FROG actions standing in for the flipbook frog's when GENM_FROG is unavailable.
const FALLBACK_ACTIONS: Dictionary[StringName, StringName] = {
	HighScoreEntryScene.ACTION_SIT: &"GEN_FROG_WAIT1",
	HighScoreEntryScene.ACTION_HOP: &"GEN_FROG_HOP",
}

## The entry being drawn.
var entry: HighScoreEntry
## The placement stepped with the entry.
var scene: HighScoreEntryScene
## The water and the page's static camera.
var water: MenuWaterView
## The models, shadow and splashes.
var models: WaterModelSet
## Player 1's key bindings, read for the direction keys.
var input: BindingInput = BindingInput.new()
## Interpolate between the last two ticks; off draws each tick as committed.
var smoothing_enabled: bool = true
## Time since the last tick.
var elapsed: float = 0.0
## True when the flipbook GENM_FROG is drawn; false when GEN_FROG stands in.
var flipbook_frog: bool = false

var _pads: Array[AnimatedModelInstance] = []
var _initials: Array[AnimatedModelInstance] = []
var _initial_letters: PackedInt32Array = PackedInt32Array()
var _extras: Array[AnimatedModelInstance] = []
var _frog: AnimatedModelInstance
var _pop_root: Node3D
var _pop: PolyPiecePopState
var _pop_nodes: Array[MeshInstance3D] = []
var _held: int = 0
var _tapped: int = 0
var _fire: bool = false
var _previous: _Frame
var _current: _Frame


class _Frame:
	extends RefCounted
	var pads: Array[PackedInt32Array] = []
	var initials: Array[PackedInt32Array] = []
	var extras: Array[PackedInt32Array] = []
	var frog: PackedInt32Array = PackedInt32Array()
	var frog_visible: bool = true
	var shadow: Array[Vector3i] = []
	var shadow_phase: int = 0


## A page for [param page_entry] over [param water_animation], drawing [param with_models].
static func create(assets: FrontEndAssets, water_animation: MenuWater, page_entry: HighScoreEntry,
		with_models: OptionsModels = null) -> HighScoreEntryView:
	var view := HighScoreEntryView.new()
	view.entry = page_entry
	view.scene = HighScoreEntryScene.create(page_entry)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.water = MenuWaterView.create_with_camera(water_animation, assets.texture("opt_env_sky"), assets.texture("opt_bank3"))
	view.water.camera.transform = MenuWaterView.camera_transform(HighScoreEntry.CAMERA_SOURCE, HighScoreEntry.CAMERA_TARGET)
	view.add_child(view.water)
	view.models = WaterModelSet.create(with_models)
	view.water.add_child(view.models)
	view._pop_root = Node3D.new()
	view._pop_root.name = "Pop"
	view.water.add_child(view._pop_root)
	view._build()
	view._current = view._capture()
	view.render(1.0)
	return view


## The flipbook action [param action_name] (a GENM_FROG name) resolves to for the frog drawn, or -1.
func frog_action_index(action_name: StringName) -> int:
	if flipbook_frog:
		var index: int = models.models.entry_frog_actions.get(action_name, -1)
		return index
	var substitute: StringName = FALLBACK_ACTIONS.get(action_name, action_name)
	return OptionsScene.action_index(substitute)


## Advances the water, entry and scene one tick with [param buttons] (a [enum HighScoreEntry.Buttons]
## mask), raises the events and returns them.
func tick(buttons: int) -> Array[int]:
	if entry.finished:
		return []
	water.tick()
	var frame: int = water.water.frame_count
	var events: Array[int] = entry.tick(buttons)
	scene.step(entry, events, frame)
	_step_models()
	_previous = _current
	_current = _capture()
	render(0.0 if smoothing_enabled else 1.0)
	for kind: int in events:
		page_event.emit(kind)
	return events


## Draws [param fraction] of the way from the previous tick to the last one.
func render(fraction: float) -> void:
	var weight: float = clampf(fraction, 0.0, 1.0) if smoothing_enabled else 1.0
	var before: _Frame = _previous if _previous != null else _current
	water.render(weight)
	WaterModelSet.place(_pads, before.pads, _current.pads, weight)
	WaterModelSet.place(_initials, before.initials, _current.initials, weight)
	WaterModelSet.place(_extras, before.extras, _current.extras, weight)
	if _frog != null:
		_frog.transform = WaterModelSet.blend_transform(before.frog, _current.frog, weight)
		_frog.render(weight)
		_frog.visible = _frog.visible and _current.frog_visible
	models.draw_effects(before.shadow, _current.shadow, _current.shadow_phase, before.pads, _current.pads, weight,
		HighScoreEntry.CAMERA_SOURCE, HighScoreEntry.CAMERA_TARGET)


## The [enum HighScoreEntry.Buttons] mask for the next tick from the keys since the last one.
func sample_buttons() -> int:
	var buttons: int = _held | _tapped
	if _fire:
		buttons |= HighScoreEntry.Buttons.FIRE
	_tapped = 0
	_fire = false
	return buttons


## The model instances drawn for the letter pads, initials pads, extras and frog, in that order;
## empty without models.
func model_instances() -> Array[AnimatedModelInstance]:
	var result: Array[AnimatedModelInstance] = []
	for group: Array[AnimatedModelInstance] in [_pads, _initials, _extras]:
		for instance: AnimatedModelInstance in group:
			if instance != null:
				result.append(instance)
	if _frog != null:
		result.append(_frog)
	return result


## The pop's piece nodes still drawn.
func pop_pieces() -> Array[MeshInstance3D]:
	return _pop_nodes.duplicate()


func _ready() -> void:
	water.set_process(false)


func _process(delta: float) -> void:
	if entry.finished:
		return
	elapsed += delta
	if elapsed >= PERIOD:
		elapsed = 0.0 if elapsed > PERIOD * 2.0 else elapsed - PERIOD
		tick(sample_buttons())
	if not entry.finished:
		render(elapsed / PERIOD)


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or key.echo:
		return
	var direction: int = 0
	match input.action(key):
		KeyBindings.Action.UP:
			direction = HighScoreEntry.Buttons.UP
		KeyBindings.Action.DOWN:
			direction = HighScoreEntry.Buttons.DOWN
		KeyBindings.Action.LEFT:
			direction = HighScoreEntry.Buttons.LEFT
		KeyBindings.Action.RIGHT:
			direction = HighScoreEntry.Buttons.RIGHT
	if direction != 0:
		if key.pressed:
			_held |= direction
			_tapped |= direction
		else:
			_held &= ~direction
		_handled()
		return
	match key.physical_keycode:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_fire = _fire or key.pressed
			_handled()


func _handled() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func _build() -> void:
	if not models.available():
		return
	for index: int in HighScoreEntry.PAD_COUNT:
		_pads.append(models.add_model(HighScoreEntry.model_name(index)))
	var letters: PackedInt32Array = entry.pad_letter
	for index: int in HighScoreEntry.INITIALS_COUNT:
		_initials.append(models.add_model(HighScoreEntry.model_name(letters[index])))
		_initial_letters.append(letters[index])
	for model_name: String in HighScoreEntry.EXTRA_MODELS:
		_extras.append(models.add_model(model_name))
	var data: OptionsModels = models.models
	flipbook_frog = data.entry_frog != null and data.entry_frog_mesh != null \
		and data.entry_frog_actions.has(HighScoreEntryScene.ACTION_SIT) and data.entry_frog_actions.has(HighScoreEntryScene.ACTION_HOP)
	var action: int = frog_action_index(scene.frog_action)
	if flipbook_frog:
		_frog = models.add_frog(data.entry_frog, data.entry_frog_mesh, action, HighScoreEntryScene.FROG_UPDATE_PERIOD)
	else:
		_frog = models.add_frog(data.frog.model, data.frog.mesh, action, HighScoreEntryScene.FROG_UPDATE_PERIOD, true, data.frog.hidden_parts)


func _step_models() -> void:
	for splash: int in scene.splashes:
		models.start_splash(splash)
	models.step_splashes()
	if _frog == null:
		return
	var letters: PackedInt32Array = entry.pad_letter
	for index: int in _initials.size():
		if letters[index] != _initial_letters[index]:
			_initial_letters[index] = letters[index]
			_initials[index] = models.swap_model(_initials[index], HighScoreEntry.model_name(letters[index]))
	for instance: AnimatedModelInstance in model_instances():
		if instance != _frog:
			instance.advance_tick()
	if scene.frog_action_set:
		var action: int = frog_action_index(scene.frog_action)
		if action >= 0:
			_frog.player.set_action(action)
	_frog.advance_tick()
	if scene.explosion:
		_start_pop()
	if _pop != null:
		_pop.step()
	_place_pop()


func _start_pop() -> void:
	var data: OptionsModels = models.models
	var file: MofFile = data.entry_frog if flipbook_frog else data.frog.model
	var library: TextureLibrary = data.entry_frog_library if flipbook_frog else data.library
	var preferred: VloFile = data.entry_frog_bank if flipbook_frog else null
	var pieces: ModelPolyPieces = ModelPolyPieces.build(file.static_models[0], library, preferred)
	_pop = PolyPiecePopState.new()
	_pop.start(scene.frog, pieces.origins())
	var projection: Vector2 = GameplayProjection.clip_scale(MenuWaterView.DISPLAY_SIZE)
	var materials: Dictionary[String, ShaderMaterial] = {}
	for piece: ModelPolyPieces.Piece in pieces.pieces:
		if not materials.has(piece.material_key):
			var original: ShaderMaterial = pieces.materials.get(piece.material_key)
			materials[piece.material_key] = PolyPiecePopView.front_material(original, piece.blend, projection)
		var node := MeshInstance3D.new()
		node.mesh = piece.mesh
		node.material_override = materials[piece.material_key]
		_pop_root.add_child(node)
		_pop_nodes.append(node)


func _place_pop() -> void:
	if _pop == null:
		return
	if _pop.timer == 0:
		for node: MeshInstance3D in _pop_nodes:
			_pop_root.remove_child(node)
			node.queue_free()
		_pop_nodes.clear()
		_pop = null
		return
	for index: int in _pop_nodes.size():
		_pop_nodes[index].transform = _pop.transform_for(index)


func _capture() -> _Frame:
	var frame := _Frame.new()
	frame.pads = WaterModelSet.copies(scene.pads)
	frame.initials = WaterModelSet.copies(scene.initials)
	frame.extras = WaterModelSet.copies(scene.extras)
	frame.frog = scene.frog.duplicate()
	frame.frog_visible = scene.frog_visible
	frame.shadow_phase = scene.shadow_phase
	if scene.shadow_visible and models.available():
		frame.shadow = scene.shadow_corners(FrogShadowGeometry.phase_offsets(scene.shadow_phase))
	return frame
