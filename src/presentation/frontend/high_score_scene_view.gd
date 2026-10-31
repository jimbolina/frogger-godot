class_name HighScoreSceneView
extends WaterModelSet
## Draws a [HighScoreScene] on the menu water: the rank turtles showing their numbers, the
## initials pads, the score logs showing their digits, the extras, the frog with its shadow and
## the landing splashes.
##
## Each turtle plays its flipbook action 0 with its twelve animated polygons held on the rank cel
## and is first turned 0xc00 about Y, as LoadOptionsResources turns the turtle model's vertices;
## each log's 64 animated polygons hold its score digits. The frog is the high-detail GEN_FROG at
## update period 2, one shot, with the croak sack at its smallest; it and its shadow show only
## while the scene moves it. Call [method step] after every [method HighScoreScene.tick] and
## [method draw] each frame.

## Turtle flipbook action (MRAnimEnvFlipbookSetAction(..., 0)).
const TURTLE_ACTION: int = 0

## The scene drawn.
var scene: HighScoreScene
## One instance per turtle, pad, log and extra, in the scene's order; empty without models.
var turtles: Array[AnimatedModelInstance] = []
var pads: Array[AnimatedModelInstance] = []
var logs: Array[AnimatedModelInstance] = []
var extras: Array[AnimatedModelInstance] = []
## The frog, or null without models.
var frog: AnimatedModelInstance

var _previous: _Frame
var _current: _Frame


class _Frame:
	extends RefCounted
	var turtles: Array[PackedInt32Array] = []
	var pads: Array[PackedInt32Array] = []
	var logs: Array[PackedInt32Array] = []
	var extras: Array[PackedInt32Array] = []
	var frog: PackedInt32Array = PackedInt32Array()
	var frog_visible: bool = false
	var shadow: Array[Vector3i] = []
	var shadow_phase: int = 0


## The turtle model's own turn (TURTLE_MODEL_ROTATION_Y about Y), in Godot space.
static func turtle_turn() -> Transform3D:
	var cos_y: int = StackLayout.rcos(HighScoreScene.TURTLE_MODEL_ROTATION_Y)
	var sin_y: int = StackLayout.rsin(HighScoreScene.TURTLE_MODEL_ROTATION_Y)
	return GameSpace.transform(PackedInt32Array([cos_y, 0, sin_y, 0, HighScoreScene.ONE, 0, -sin_y, 0, cos_y, 0, 0, 0]))


## A view of [param drawn] with [param with_models].
static func create_for(drawn: HighScoreScene, with_models: OptionsModels) -> HighScoreSceneView:
	var view := HighScoreSceneView.new()
	view.setup(with_models)
	view.scene = drawn
	view._build()
	view._current = view._capture()
	return view


## The model instances in turtle, pad, log, extra and frog order; empty without models.
func model_instances() -> Array[AnimatedModelInstance]:
	var result: Array[AnimatedModelInstance] = []
	for group: Array[AnimatedModelInstance] in [turtles, pads, logs, extras]:
		for instance: AnimatedModelInstance in group:
			if instance != null:
				result.append(instance)
	if frog != null:
		result.append(frog)
	return result


## Takes the scene's last tick: advances the animations, starts its splashes and keeps its state
## for drawing.
func step() -> void:
	for group: Array[AnimatedModelInstance] in [turtles, pads, logs, extras]:
		for instance: AnimatedModelInstance in group:
			if instance != null:
				instance.advance_tick()
	if frog != null:
		if scene.frog_action_set and scene.frog_action >= 0:
			frog.player.set_action(scene.frog_action)
		frog.advance_tick()
	for turtle: int in scene.splashes:
		start_splash(turtle)
	step_splashes()
	_previous = _current
	_current = _capture()


## Draws [param weight] of the way from the previous tick to the last one, lit as seen from
## [param source] looking at [param target].
func draw(weight: float, source: Vector3i, target: Vector3i) -> void:
	var before: _Frame = _previous if _previous != null else _current
	place(turtles, before.turtles, _current.turtles, weight, turtle_turn())
	place(pads, before.pads, _current.pads, weight)
	place(logs, before.logs, _current.logs, weight)
	place(extras, before.extras, _current.extras, weight)
	if frog != null:
		var from: PackedInt32Array = before.frog if before.frog_visible else _current.frog
		frog.transform = blend_transform(from, _current.frog, weight)
		frog.render(weight)
		frog.visible = frog.visible and _current.frog_visible
	draw_effects(before.shadow, _current.shadow, _current.shadow_phase, before.turtles, _current.turtles, weight, source, target)


func _build() -> void:
	if not available():
		return
	for index: int in scene.turtles.size():
		var turtle: AnimatedModelInstance = add_model(HighScoreScene.TURTLE_MODEL)
		if turtle != null:
			turtle.player.set_action(TURTLE_ACTION)
			turtle.player.texture_animation_paused = true
			for poly: int in HighScoreScene.TURTLE_ANIMATED_POLYS:
				turtle.player.set_animated_poly_cel(poly, HighScoreScene.turtle_cel(index))
		turtles.append(turtle)
	for index: int in scene.pads.size():
		pads.append(add_model(HighScoreScene.LETTER_MODELS[scene.pad_letters[index]]))
	for index: int in scene.logs.size():
		var log_model: AnimatedModelInstance = add_model(HighScoreScene.LOG_MODEL)
		if log_model != null:
			log_model.player.texture_animation_paused = true
			var cels: PackedInt32Array = HighScoreScene.digit_poly_cels(scene.log_digits[index])
			for poly: int in cels.size():
				log_model.player.set_animated_poly_cel(poly, cels[poly])
		logs.append(log_model)
	for model_name: String in HighScoreScene.EXTRA_MODELS:
		extras.append(add_model(model_name))
	frog = add_frog(models.frog.model, models.frog.mesh, scene.frog_action, OptionsScene.FROG_UPDATE_PERIOD, true, models.frog.hidden_parts)


func _capture() -> _Frame:
	var frame := _Frame.new()
	frame.turtles = copies(scene.turtles)
	frame.pads = copies(scene.pads)
	frame.logs = copies(scene.logs)
	frame.extras = copies(scene.extras)
	frame.frog = scene.frog.duplicate()
	frame.frog_visible = scene.frog_visible
	frame.shadow_phase = scene.shadow_phase
	if scene.frog_visible and scene.shadow_visible:
		frame.shadow = shadow_corners(scene.frog, scene.shadow_phase, scene.frame)
	return frame

