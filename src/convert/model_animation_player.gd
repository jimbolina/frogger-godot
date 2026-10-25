class_name ModelAnimationPlayer
extends RefCounted
## Deterministic animation clocks for one instance of a parsed model.
## Geometry follows MRAnimUpdateEnvironments; texture targets follow
## MRUpdateMeshAnimatedPolys. Parsed model resources are never changed.

## What happens on the update after the last animation frame.
enum EndMode {
	## Return to frame zero.
	LOOP,
	## Keep drawing the final frame.
	HOLD,
	## Stop drawing this instance.
	HIDE,
}

## Shared, read-only source data.
var file: MofFile
## Which static model inside the file this instance uses.
var static_index: int = 0
## Selected action, or -1 when there is no valid geometry animation.
var action_index: int = -1
## Virtual geometry frame; -1 awaits the first update after set_action.
var frame: int = -1
## Viewer tick, with zero being the state after the first update.
var tick: int = -1
## Why the most recent request failed, or the first initialization problem.
var error: String = ""
## Geometry updates per frame. The first frame always updates immediately.
var update_period: int = 1
## Behaviour when a geometry action ends. Switching a finished action back
## to looping resumes it from the held final frame on the next update.
var end_mode: EndMode = EndMode.LOOP:
	set(value):
		if end_mode == value:
			return
		end_mode = value
		if value == EndMode.LOOP and (completed or not visible):
			completed = false
			visible = true
			wrapped = false
			revision += 1
## Whether animated textures display and advance. Disabling preserves clocks
## and draws the polygons' original textures until animation is enabled again.
var texture_animation_enabled: bool = true
## Whether a non-looping action has reached its end.
var completed: bool = false
## Whether this instance should be drawn.
var visible: bool = true
## True only on an update that loops geometry to its first frame.
var wrapped: bool = false
## Increases after action changes, restarts, seeks and resuming a finished loop.
var revision: int = 0
## Data problems that do not prevent other parts or texture targets playing.
var diagnostics := PackedStringArray()

var _model: MofStatic
var _actions: Array[MofAnimated.Action] = []
var _action_errors := PackedStringArray()
var _update_count: int = 0
var _texture_entries: Array[PackedInt32Array] = []
var _texture_durations: Array[PackedInt32Array] = []


## Creates an instance, selecting the first valid action and showing tick zero.
func _init(source: MofFile, model_index: int = 0) -> void:
	file = source
	static_index = model_index
	if file == null or static_index < 0 or static_index >= file.static_models.size():
		error = "static model %d is unavailable" % static_index
		visible = false
		return
	_model = file.static_models[static_index]
	if file.animated != null:
		_actions = file.animated.actions_for(static_index)
		diagnostics.append_array(file.animated.diagnostics)
	for index: int in action_count():
		_action_errors.append(_validate_action(index))
		if action_index < 0 and _action_errors[index].is_empty():
			action_index = index
		elif not _action_errors[index].is_empty():
			diagnostics.append("action %d: %s" % [index, _action_errors[index]])
	if action_index < 0 and action_count() > 0:
		error = "no valid geometry actions"
	_initialize_textures()
	restart()


## Number of geometry actions, including malformed actions shown for diagnosis.
func action_count() -> int:
	if file != null and file.animated != null:
		return _actions.size()
	if _model != null and not _model.parts.is_empty():
		return _model.parts[0].flipbook_actions.size()
	return 0


## Virtual frame count of an action, or zero for an unavailable action.
func action_frame_count(index: int) -> int:
	if index < 0 or index >= action_count():
		return 0
	if file.animated != null:
		return _actions[index].frame_count
	return _model.parts[0].flipbook_actions[index].frame_count


## Why an action cannot play, or an empty string when it is valid.
func action_error(index: int) -> String:
	if index < 0 or index >= action_count():
		return "action %d is unavailable" % index
	return _action_errors[index]


## Selects a valid action. Its first frame appears on the next update, as in C.
## Texture clocks and the update-period counter remain independent of actions.
func set_action(index: int) -> bool:
	var problem: String = action_error(index)
	if not problem.is_empty():
		error = problem
		return false
	action_index = index
	frame = -1
	completed = false
	visible = true
	wrapped = false
	error = ""
	revision += 1
	return true


## Advances exactly one game tick. Pausing means withholding this call.
func advance_tick() -> void:
	if _model == null:
		return
	tick += 1
	wrapped = false
	if action_index >= 0 and not completed:
		_update_count += 1
		if frame == -1 or _update_count >= update_period:
			_update_count = 0
			frame += 1
			if frame >= action_frame_count(action_index):
				match end_mode:
					EndMode.LOOP:
						frame = 0
						wrapped = true
					EndMode.HOLD, EndMode.HIDE:
						frame = action_frame_count(action_index) - 1
						completed = true
						visible = end_mode != EndMode.HIDE
	if texture_animation_enabled:
		_advance_textures()


## Resets all instance clocks and performs the first update, producing tick zero.
func restart() -> void:
	if _model == null:
		return
	frame = -1
	tick = -1
	_update_count = 0
	completed = false
	visible = true
	wrapped = false
	for part_index: int in _texture_entries.size():
		for target_index: int in _texture_entries[part_index].size():
			if _texture_entries[part_index][target_index] >= 0:
				_texture_entries[part_index][target_index] = 0
			_texture_durations[part_index][target_index] = 0
	revision += 1
	advance_tick()


## Replays from tick zero to a non-negative tick using the current settings.
func seek_tick(target: int) -> bool:
	if target < 0 or _model == null:
		error = "tick %d is unavailable" % target
		return false
	restart()
	for _step: int in target:
		advance_tick()
	error = ""
	return true


## Returns the current pose without advancing clocks or mutating source data.
func sample_pose() -> ModelPose:
	var pose := ModelPose.new()
	pose.visible = visible
	if _model == null:
		return pose
	var sampled_frame: int = maxi(frame, 0)
	var flipbook_partcel: int = 0
	if action_index >= 0 and file.animated == null:
		flipbook_partcel = _model.parts[0].flipbook_actions[action_index].start + sampled_frame
	for part_index: int in _model.parts.size():
		var transform := Transform3D.IDENTITY
		if action_index >= 0 and file.animated != null:
			var matrix: PackedInt32Array = file.animated.sample_matrix(static_index, action_index, sampled_frame, part_index)
			transform = GameSpace.transform(matrix)
		pose.transforms.append(transform)
		pose.partcels.append(flipbook_partcel)
		var entries: PackedInt32Array = _texture_entries[part_index].duplicate()
		if not texture_animation_enabled:
			entries.fill(-1)
		pose.texture_entries.append(entries)
	return pose


func _validate_action(index: int) -> String:
	var count: int = action_frame_count(index)
	if file.animated != null:
		var action: MofAnimated.Action = _actions[index]
		if not action.error.is_empty():
			return action.error
		if count <= 0 or action.cel_count <= 0:
			return "action has no frames"
		if action.part_count < _model.parts.size():
			return "action has %d parts, model has %d" % [action.part_count, _model.parts.size()]
		if action.flags != 1 and action.flags != 2:
			return "unsupported action flags %d" % action.flags
		var interpolated: bool = action.flags & 2 != 0
		var number_count: int = count * (3 if interpolated else 1)
		if action.cel_numbers.size() != number_count or action.transform_indices.size() != action.cel_count * action.part_count:
			return "action frame or transform table has the wrong length"
		for number_index: int in number_count:
			var number: int = action.cel_numbers[number_index]
			if interpolated and number_index % 3 == 2:
				if number < 0 or number > 4096:
					return "interpolation parameter is outside 0 to 4096"
			else:
				var cel: int = number - (0 if interpolated or file.animated.starts_at_frame_zero else 1)
				if cel < 0 or cel >= action.cel_count:
					return "virtual frame names unavailable cel %d" % cel
		for transform_index: int in action.transform_indices:
			if transform_index < 0 or transform_index >= file.animated.transforms.size():
				return "transform index %d is outside the shared pool" % transform_index
			var transform: MofTransform = file.animated.transforms[transform_index]
			if transform == null or transform.code < 0 or transform.code >= MofTransform.SIZES.size():
				return "transform encoding is unavailable"
			var value_count: int = 12 if transform.code <= 1 else (11 if transform.code >= 4 else 7)
			if transform.raw_values.size() != value_count or (interpolated and transform.code < 2):
				return "transform fields cannot sample this action"
		for frame_index: int in count:
			for part_index: int in _model.parts.size():
				if file.animated.sample_matrix(static_index, index, frame_index, part_index).size() != 12:
					return "frame %d part %d has no valid transform" % [frame_index, part_index]
	else:
		var action: MofPart.FlipbookAction = _model.parts[0].flipbook_actions[index]
		if not action.error.is_empty():
			return action.error
		if count <= 0 or action.start < 0:
			return "flipbook action has no valid partcel range"
		for part_index: int in _model.parts.size():
			var part: MofPart = _model.parts[part_index]
			if action.start + count > part.partcels.size():
				return "shared flipbook range exceeds part %d's partcels" % part_index
			if part_index > 0 and index < part.flipbook_actions.size():
				var other: MofPart.FlipbookAction = part.flipbook_actions[index]
				if other.start != action.start or other.frame_count != count:
					diagnostics.append("part %d action %d differs: using part zero's shared flipbook range" % [part_index, index])
	return ""


func _initialize_textures() -> void:
	for part_index: int in _model.parts.size():
		var part: MofPart = _model.parts[part_index]
		var entries := PackedInt32Array()
		var durations := PackedInt32Array()
		for target_index: int in part.texture_targets.size():
			var problem: String = _texture_error(part, part.texture_targets[target_index])
			entries.append(0 if problem.is_empty() else -1)
			durations.append(0)
			if not problem.is_empty():
				diagnostics.append("part %d texture target %d: %s" % [part_index, target_index, problem])
		_texture_entries.append(entries)
		_texture_durations.append(durations)


func _texture_error(part: MofPart, target: MofPart.TextureTarget) -> String:
	if not target.error.is_empty():
		return target.error
	if target.polygon_index < 0 or target.polygon_index >= part.polygons.size():
		return "polygon is unavailable"
	if part.polygons[target.polygon_index].type != target.polygon_type:
		return "polygon type does not match"
	if not MofPolygonType.is_textured(target.polygon_type):
		return "polygon is not textured"
	if target.list_index < 0 or target.list_index >= part.texture_lists.size():
		return "texture list is unavailable"
	var animation: MofPart.TextureAnimation = part.texture_lists[target.list_index]
	if not animation.error.is_empty():
		return animation.error
	if animation.image_ids.is_empty() or animation.image_ids.size() != animation.durations.size():
		return "texture list has no complete entries"
	for duration: int in animation.durations:
		if duration < 0:
			return "texture duration is negative"
	return ""


func _advance_textures() -> void:
	for part_index: int in _model.parts.size():
		var part: MofPart = _model.parts[part_index]
		for target_index: int in part.texture_targets.size():
			var entry: int = _texture_entries[part_index][target_index]
			if entry < 0:
				continue
			var animation: MofPart.TextureAnimation = part.texture_lists[part.texture_targets[target_index].list_index]
			_texture_durations[part_index][target_index] += 1
			if _texture_durations[part_index][target_index] >= animation.durations[entry]:
				_texture_durations[part_index][target_index] = 0
				_texture_entries[part_index][target_index] = (entry + 1) % animation.image_ids.size()
