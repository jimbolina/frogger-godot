class_name EntitySwampCrusherCallback
extends RefCounted
## Swamp branch of SwpCrusherCallback: debounced velocity-directed bounce and the deadly form-square squish.

## Source cr_count set by a Swamp hit to debounce repeated callbacks.
const HIT_COUNT: int = 5

## Applies the Swamp branch to a private copy of the crusher. A non-zero cr_count ignores the hit;
## otherwise a moving frog bounces opposite its dominant velocity axis from its world cell, a still
## frog takes the facing-reversal path from its stored cell, and the frog is squished when its
## crusher-local position lies on a deadly square of the crusher's first FORM grid.
static func apply(definition: EntityDefinition, entity: EntitySnapshot, frog: Frog, state: GameplayState, events: Array[TickEvent]) -> String:
	if entity.custom_state == null:
		return "Swamp crusher callback requires the crusher runtime"
	if frog.entity_collision == null:
		return "Swamp crusher callback requires the entity collision definition"
	var custom: EntityCustomState = entity.custom_state
	if custom.count != 0:
		return ""
	var velocity: Vector3i = state.frog.velocity_16
	var cell: Vector2i = state.frog.cell
	var step: Vector3i = FormCallback.crusher_step(state.frog.direction)
	if velocity.x != 0 or velocity.z != 0:
		if frog.grid == null:
			return "Swamp crusher callback requires the map grid"
		cell = GridQueries.world_to_cell(frog.grid, state.frog.matrix12[9], state.frog.matrix12[11])
		if absi(velocity.x) > absi(velocity.z):
			step = Vector3i(-1, 0, 3) if velocity.x > 0 else Vector3i(1, 0, 1)
		else:
			step = Vector3i(0, -1, 2) if velocity.z > 0 else Vector3i(0, 1, 0)
	custom.count = HIT_COUNT
	var issue: String = FormCallback.crusher_bounce_to(frog.grid, state, definition.entity_index, cell + Vector2i(step.x, step.y), step, custom)
	if not issue.is_empty():
		return issue
	var contact: FormContactDefinition = null
	for candidate: FormContactDefinition in frog.entity_collision.contacts:
		if candidate.entity_index == entity.entity_index:
			contact = candidate
			break
	if contact == null or not contact.has_form_data:
		return ""
	var delta := Vector3i.ZERO
	for axis: int in 3:
		delta[axis] = PlatformMath.s16(state.frog.matrix12[9 + axis] - entity.matrix12[9 + axis])
	var local: Vector3i = PlatformMath.apply(PlatformMath.transpose(entity.matrix12), delta)
	var x_max: int = contact.offsets.x + (contact.dimensions.x << 8)
	var z_max: int = contact.offsets.y + (contact.dimensions.y << 8)
	if local.x <= contact.offsets.x or local.x >= x_max or local.z <= contact.offsets.y or local.z >= z_max or local.y < contact.height or local.y > contact.max_y:
		return ""
	var square: int = ((local.z - contact.offsets.y) >> 8) * contact.dimensions.x + ((local.x - contact.offsets.x) >> 8)
	if square < 0 or square >= contact.grid_flags.size():
		return "Swamp crusher FORM square lies outside authored storage"
	if contact.grid_flags[square] & GridSquareFlags.DEADLY:
		frog.kill(state, FrogAnimationCatalog.SQUISHED, false, events)
	return ""
