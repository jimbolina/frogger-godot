class_name Org1RouteFacts
extends RefCounted
## Observation transport only; expected facts come from independent Python/frozen C.

## Selects represented source phase fields without deriving expected behavior.
static func phase(state: RunSnapshot, tick: int, name: String, definition: EntityCollisionDefinition) -> Dictionary:
	var camera: GameplayCameraSnapshot = state.camera
	var diver: EntitySnapshot = state.entities.entities[0]
	var result: Dictionary = {"tick": tick, "phase": name,
		"x16": state.position_16.x, "y16": state.position_16.y, "z16": state.position_16.z,
		"flags": state.flags, "mode": state.mode, "attached": state.current_entity_index,
		"count": state.remaining_ticks, "old_y": state.old_y, "direction": state.direction,
		"action": state.animation.action, "cel": state.animation.cel, "rng": state.rng_state,
		"sounds": state.sound_requests, "diver_y": diver.script_state.deviation,
		"diver_timer": diver.script_state.timer, "diver_action": diver.animation.action,
		"scan": joined(EntityContactOrder.indices(definition, state.entities, state.world_position), ";")}
	for pair: Array in [["camera", camera.tracked_world], ["source", camera.source_world], ["target", camera.target_world]]:
		var point: Vector3i = pair[1]
		result[str(pair[0]) + "_x"] = point.x
		result[str(pair[0]) + "_y"] = point.y
		result[str(pair[0]) + "_z"] = point.z
	for index: int in 4:
		result["controller_%d" % index] = camera.controller_directions[index]
	for index: int in 9:
		@warning_ignore("integer_division")
		var row: int = index / 3
		result["camera_mod%d%d" % [row, index % 3]] = camera.mod_matrix12[index]
	return result

## Encodes one ordered visit in the independently specified field order.
static func entity(visit: EntityUpdateObservation, fly: EntityBackgroundState, tick: int) -> Dictionary:
	var pose: EntitySnapshot = visit.entity
	var state: EntityScriptState = pose.script_state
	var result: Dictionary = {"tick": tick, "index": pose.entity_index,
		"root": state.root_id if state != null else -1, "program": state.program_id if state != null else -1,
		"cursor": state.cursor if state != null else -1, "loop_start": state.loop_start if state != null else -1,
		"loop_end": state.loop_end if state != null else -1, "timer": state.timer if state != null else 0,
		"deviation": state.deviation if state != null else 0, "delta": state.delta if state != null else 0,
		"destination": state.destination if state != null else 0, "remaining": state.remaining if state != null else 0,
		"action": pose.animation.action, "cel": pose.animation.cel, "rng": visit.rng_state,
		"sounds": visit.sound_requests, "moving_sound": int(state != null and not state.moving_sound.is_empty()),
		"requests": ";".join(pose.requests) if not pose.requests.is_empty() else "-",
		"red": pose.colour_scale.x, "green": pose.colour_scale.y, "blue": pose.colour_scale.z,
		"ambient_red": pose.ambient.x, "ambient_green": pose.ambient.y, "ambient_blue": pose.ambient.z,
		"previous_flags": visit.previous_flags, "live_flags": pose.live_flags,
		"x": pose.matrix12[9], "y": pose.matrix12[10], "z": pose.matrix12[11],
		"fly_mode": fly.mode, "fly_timer": fly.timer, "fly_checkpoint": fly.checkpoint_index,
		"covered": visit.environment.covered}
	for slot: int in 2:
		result["callback%d" % slot] = joined(state.callbacks[slot], ":") if state != null else "-1:0:0:0"
	for index: int in 3:
		result[["sound_id", "sound_min", "sound_max"][index]] = state.moving_sound[index] if state != null and not state.moving_sound.is_empty() else -1
	return result

## Renders ordered decimal facts without JSON float conversion.
static func joined(values: PackedInt32Array, separator: String) -> String:
	var strings := PackedStringArray()
	for value: int in values:
		strings.append(str(value))
	return separator.join(strings)
