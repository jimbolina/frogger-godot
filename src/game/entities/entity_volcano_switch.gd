class_name EntityVolcanoSwitch
extends RefCounted
## Frozen colour-switch update and contact transitions with ordered target effects.

enum Mode { ON_DOWN, ON_UP, OFF_DOWN, OFF_UP }

## Advances debounce, initial target movement and release animation.
static func update(definition: EntityDefinition, result: EntityCustomResult) -> String:
	if definition.volcano == null:
		return "Colour switch requires authored trigger operands"
	var custom: EntityCustomState = result.entity.custom_state
	if custom.timer != 0:
		custom.timer = (custom.timer - 1) & 0xffffffff
	if not custom.initialized:
		_targets(definition, result, EntityTargetEffect.Kind.INITIALIZE)
		custom.initialized = true
	if custom.timer == 0 and custom.no_frog_contact:
		if custom.mode in [Mode.ON_DOWN, Mode.OFF_DOWN]:
			result.entity.animation.select(1)
			custom.mode += 1
			custom.timer = 6
			result.entity.requests.append(TickEvent.sound(173))
	custom.no_frog_contact = true
	return ""

## Applies the primitive callback without changing targets until aggregate validation.
static func contact(definition: EntityDefinition, result: EntityCustomResult, frog: GameplayState) -> String:
	if definition.volcano == null or result.entity.custom_state == null:
		return "Colour-switch callback requires its initialized behavior"
	var custom: EntityCustomState = result.entity.custom_state
	custom.no_frog_contact = false
	if custom.timer != 0:
		return ""
	if custom.mode in [Mode.ON_DOWN, Mode.OFF_DOWN]:
		if frog != null:
			result.frog_matrix12 = frog.frog.matrix12.duplicate()
			result.frog_matrix12[10] = frog.frog.target_y - 32
		return ""
	result.entity.animation.select(0)
	result.entity.animation.stepping = true
	if custom.mode == Mode.ON_UP:
		custom.mode = Mode.OFF_DOWN
		custom.texture_animation_cel = 0
	else:
		custom.mode = Mode.ON_DOWN
		custom.texture_animation_cel = 1
	custom.timer = 4
	_targets(definition, result, EntityTargetEffect.Kind.REVERSE if definition.volcano.trigger_type == 1 else EntityTargetEffect.Kind.TOGGLE)
	return ""

static func _targets(definition: EntityDefinition, result: EntityCustomResult, operation: EntityTargetEffect.Kind) -> void:
	for identity: int in definition.volcano.target_ids:
		if identity != -1:
			result.target_effects.append(EntityTargetEffect.create(identity, operation))
