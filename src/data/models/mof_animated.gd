class_name MofAnimated
extends Resource
## The model sets, authored actions and shared transforms of an XAR file.

## Flag identifying an animated model file.
const FLAG_ANIMATED: int = 1 << 3
## Indexed whole transforms and animation data flags used by PC Frogger.
const EXPECTED_FLAGS: int = (1 << 20) | (1 << 16) | FLAG_ANIMATED
## Header size before the model set table.
const HEADER_SIZE: int = 28

## Former inner class, now [MofAction].
const Action := preload("res://src/data/models/mof_action.gd")
## Former inner class, now [MofModelInfo].
const ModelInfo := preload("res://src/data/models/mof_model_info.gd")
## Former inner class, now [MofModelSet].
const ModelSet := preload("res://src/data/models/mof_model_set.gd")

## File length as stored.
@export var length: int = 0
## Flags as stored.
@export var flags: int = 0
## Number of model sets in the header.
@export var model_set_count: int = 0
## True when ordinary virtual cel references start at zero rather than one.
@export var starts_at_frame_zero: bool = false
## Transform encoding in the signature (0 through 5).
@export var transform_code: int = 0
## Offset and size of each embedded static model.
@export var static_ranges: Array[Vector2i] = []
## Authored model sets.
@export var model_sets: Array[MofModelSet] = []
## The shared transform pool.
@export var transforms: Array[MofTransform] = []
## Stored shared-data flags, for inspection without inferred facts.
@export var shared_flags: int = 0
## Stored transform count, for inspection without inferred facts.
@export var transform_count: int = 0
## Shared bounding boxes, when present.
@export var bounding_boxes: Array[PackedInt32Array] = []
## Structural parse error; semantic action errors are kept on each action.
@export var error: String = ""
## Preserved format bits whose meaning is unknown; sampling follows C's fallback.
@export var diagnostics := PackedStringArray()


## True when all structures were bounded and read safely.
func is_valid() -> bool:
	return error.is_empty()


## Returns the action list for an embedded static model, or an empty list.
func actions_for(static_index: int) -> Array[MofAction]:
	for model_set: MofModelSet in model_sets:
		for model: MofModelInfo in model_set.models:
			if model.static_model_index == static_index:
				return model_set.actions
	return []


## Checks action part counts after embedded static models have been read.
## Unsafe references disable an action, rather than rejecting useful geometry.
func validate_models(models: Array[MofStatic]) -> void:
	for model_set: MofModelSet in model_sets:
		for model: MofModelInfo in model_set.models:
			for action: MofAction in model_set.actions:
				if model.static_model_index >= models.size():
					action.error = "static model index %d is unavailable" % model.static_model_index
				elif model.part_count != models[model.static_model_index].parts.size() or action.part_count < model.part_count:
					action.error = "action part count does not match its static model"


## Samples one authored integer frame and part; unavailable samples are empty.
## Interpolation triples use zero-based cel indices even on older signatures.
func sample_matrix(static_index: int, action_index: int, frame: int, part: int) -> PackedInt32Array:
	var actions: Array[MofAction] = actions_for(static_index)
	if not is_valid() or action_index < 0 or action_index >= actions.size():
		return PackedInt32Array()
	var action: MofAction = actions[action_index]
	if not action.error.is_empty() or frame < 0 or frame >= action.frame_count or part < 0 or part >= action.part_count:
		return PackedInt32Array()
	for model_set: MofModelSet in model_sets:
		for model: MofModelInfo in model_set.models:
			if model.static_model_index == static_index and part >= model.part_count:
				return PackedInt32Array()
	if action.flags & 2 != 0:
		var first: int = action.cel_numbers[frame * 3]
		var second: int = action.cel_numbers[frame * 3 + 1]
		var amount: int = action.cel_numbers[frame * 3 + 2]
		return transforms[action.transform_indices[first * action.part_count + part]].interpolate(transforms[action.transform_indices[second * action.part_count + part]], amount)
	var cel: int = action.cel_numbers[frame] - (0 if starts_at_frame_zero else 1)
	return transforms[action.transform_indices[cel * action.part_count + part]].matrix_values()
