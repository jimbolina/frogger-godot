class_name EntityScriptCallbacks
extends RefCounted
## Named script callbacks; executable FORM callback addresses are unrelated.

const SOUNDS: Dictionary[EntityScriptDefinition.CallbackKind, Array] = {
	EntityScriptDefinition.CallbackKind.FROG_TRAFFIC_SPLAT: [13],
	EntityScriptDefinition.CallbackKind.LOG_SPLASH: [19],
	EntityScriptDefinition.CallbackKind.HIT_TURTLE: [14, 15],
	EntityScriptDefinition.CallbackKind.SWP_OIL_DRUM: [108],
	EntityScriptDefinition.CallbackKind.SWP_PALLET: [15],
	EntityScriptDefinition.CallbackKind.SWP_SUNKCAR: [14],
	EntityScriptDefinition.CallbackKind.SWP_STAT_PIPE: [108],
	EntityScriptDefinition.CallbackKind.SWP_STAT_PIPE_BIG_STR: [108],
	EntityScriptDefinition.CallbackKind.SKY_BIRD1_CALL: [128],
	EntityScriptDefinition.CallbackKind.SKY_BIRD2_CALL: [132],
	EntityScriptDefinition.CallbackKind.SKY_BIRD3_CALL: [134],
	EntityScriptDefinition.CallbackKind.SKY_BIRD4_CALL: [147],
	EntityScriptDefinition.CallbackKind.SKY_FROG_HELICOPTER: [141],
	EntityScriptDefinition.CallbackKind.SUB_LILLY_PAD: [15],
	EntityScriptDefinition.CallbackKind.JUN_HIPPO_HIT: [],
	EntityScriptDefinition.CallbackKind.SWP_RACCOON: [109, 19],
	EntityScriptDefinition.CallbackKind.SWP_PELICAN_CALL: [120],
	EntityScriptDefinition.CallbackKind.SKY_HOMING_BIRD: [139],
	EntityScriptDefinition.CallbackKind.SKY_BALLOON: [149],
}

## Applies slots in source order using the previous tick's HIT/CARRY flags.
static func apply(definition: EntityScriptDefinition, context: EntityUpdateContext, result: EntityUpdateResult) -> void:
	var state: EntityScriptState = result.script_state
	var carries_frog: bool = context.previous_carry
	for slot: PackedInt32Array in state.callbacks:
		if slot[0] < 0 or (slot[2] != 1 and slot[3] == 3):
			continue
		if slot[1] == 0 and not context.previous_hit:
			continue
		var callback: EntityScriptDefinition.CallbackKind = definition.callbacks[slot[0]]
		if SOUNDS.has(callback):
			for sound: int in SOUNDS[callback]:
				result.add_request(TickEvent.sound(sound))
			continue
		match callback:
			EntityScriptDefinition.CallbackKind.SKY_HELIUM_BALLOON:
				state.program_id = definition.callback_programs[slot[0]]
				state.cursor = 0
				state.loop_start = -1
				state.loop_end = -1
			EntityScriptDefinition.CallbackKind.VOL_MECHANISM:
				if not context.no_display and carries_frog and absi(result.matrix12[10] - context.authored_matrix[10]) < 32:
					result.add_death(FrogAnimationCatalog.SQUISHED)
			EntityScriptDefinition.CallbackKind.JUN_HIPPO_DIVE:
				if context.no_display:
					continue
				var fade: PackedInt32Array = context.fade_bounds
				state.no_screen_fade = fade.is_empty() or (result.matrix12[9] >= fade[0] and result.matrix12[9] <= fade[1] and result.matrix12[11] >= fade[2] and result.matrix12[11] <= fade[3])
				var height: int = context.base_matrix[10] - result.matrix12[10]
				if state.no_screen_fade:
					var packed: int = (mini(191 - height, 255) << 16) + (mini(192 + height, 255) << 8) + mini(192 + height, 255)
					state.colours = Vector3i(packed & 255, (packed >> 8) & 255, (packed >> 16) & 255)
					state.ambient = Vector3i(64, 64, 192)
				if carries_frog and height <= -128:
					result.drown = true
					result.add_death(FrogAnimationCatalog.DROWN)
					carries_frog = false
			EntityScriptDefinition.CallbackKind.JUN_PIRANAHA, EntityScriptDefinition.CallbackKind.SWP_MUTANT_FISH:
				if context.no_display:
					continue
				if callback == EntityScriptDefinition.CallbackKind.JUN_PIRANAHA:
					state.colours = Vector3i(64, 96, 160) if context.base_matrix[10] == 0 else Vector3i(128, 128, 128)
					state.ambient = Vector3i(64, 64, 208) if context.base_matrix[10] == 0 else Vector3i(64, 64, 64)
				else:
					state.colours = Vector3i(64, 160, 96) if context.base_matrix[10] == 0 else Vector3i(128, 128, 128)
					state.ambient = Vector3i(64, 64, 64) if context.base_matrix[10] == 0 else Vector3i(64, 208, 64)
			EntityScriptDefinition.CallbackKind.DIVE_COLOUR_CHANGE:
				if context.no_display:
					continue
				if not context.has_path:
					var height: int = PlatformMath.s32(result.matrix12[10] - context.authored_matrix[10]) >> 2
					var red: int = maxi(0, 64 - height)
					var blue: int = maxi(0, 96 - height)
					var packed: int = (blue << 16) + (red << 8) + red
					state.colours = Vector3i(packed & 255, (packed >> 8) & 255, (packed >> 16) & 255)
					state.ambient = Vector3i(32, 240, 160)
					state.no_screen_fade = true
					continue
				var fade: PackedInt32Array = context.fade_bounds
				state.no_screen_fade = fade.is_empty() or (result.matrix12[9] >= fade[0] and result.matrix12[9] <= fade[1] and result.matrix12[11] >= fade[2] and result.matrix12[11] <= fade[3])
				if state.no_screen_fade:
					var packed: int = ((127 + result.matrix12[10] - context.base_matrix[10]) << 16) + ((128 + ((context.base_matrix[10] - result.matrix12[10]) >> 1)) << 8) + 128 + context.base_matrix[10] - result.matrix12[10]
					state.colours = Vector3i(packed & 255, (packed >> 8) & 255, (packed >> 16) & 255)
					state.ambient = Vector3i(64, 64, 192)
				if carries_frog and result.matrix12[10] - context.base_matrix[10] >= 128:
					result.drown = true
					result.add_death(FrogAnimationCatalog.DROWN)
					carries_frog = false
