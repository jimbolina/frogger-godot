class_name EntitySwampCrusher
extends RefCounted
## Swamp wall crusher that waits its delay, then rams back and forth along one map axis.

## Source SWAMP_CRUSHER_IN and SWAMP_CRUSHER_OUT runtime directions.
const IN: int = 0
const OUT: int = 1
## Source SWAMP_CRUSHER_WAITING and SWAMP_CRUSHER_CRUSHING actions.
const WAITING: int = 4
const CRUSHING: int = 5
## Source authored SWAMP_CRUSHER_NORTH, EAST, SOUTH and WEST directions.
const NORTH: int = 0
const EAST: int = 1
const SOUTH: int = 2
const WEST: int = 3
## Source WORLD_SHIFT applied to the authored speed.
const WORLD_SHIFT: int = 8
## Source SFX_SWP_CRUSH_AMB and its PlayMovingSound radii.
const SOUND: int = 121
const SOUND_NEAR: int = 768
const SOUND_FAR: int = 1280

## Copies the authored matrix, loads the unsigned delay, clears the debounce count and starts the moving sound.
static func initialize(definition: EntityDefinition, entity: EntitySnapshot) -> void:
	entity.matrix12 = definition.matrix12.duplicate()
	var custom: EntityCustomState = entity.custom_state
	custom.direction = IN
	custom.timer = (definition.swamp.delay & 0xffff) if definition.swamp != null else 0
	custom.mode = WAITING
	custom.count = 0
	custom.moving_sound = PackedInt32Array([SOUND, SOUND_NEAR, SOUND_FAR])

## Advances one crusher step; custom.direction, custom.timer, custom.mode and custom.count are
## the unsigned 16-bit cr_direction, cr_time, cr_action and cr_count.
static func update(definition: EntityDefinition, result: EntityCustomResult) -> String:
	var swamp: EntitySwampDefinition = definition.swamp
	if swamp == null:
		return "Swamp crusher requires its speed, distance, direction and delay"
	var custom: EntityCustomState = result.entity.custom_state
	if custom.count != 0:
		custom.count = (custom.count - 1) & 0xffff
	if custom.mode == WAITING:
		var previous: int = custom.timer
		custom.timer = (previous - 1) & 0xffff
		if previous == 0:
			custom.mode = CRUSHING
		return ""
	match swamp.direction:
		NORTH:
			_ram(definition, result.entity, 11, 1)
		EAST:
			_ram(definition, result.entity, 9, 1)
		SOUTH:
			_ram(definition, result.entity, 11, -1)
		WEST:
			_ram(definition, result.entity, 9, -1)
	return ""

static func _ram(definition: EntityDefinition, entity: EntitySnapshot, slot: int, polarity: int) -> void:
	var swamp: EntitySwampDefinition = definition.swamp
	var custom: EntityCustomState = entity.custom_state
	var step: int = swamp.speed >> WORLD_SHIFT
	var origin: int = definition.matrix12[slot]
	if custom.direction == IN:
		entity.matrix12[slot] = PlatformMath.s32(entity.matrix12[slot] + polarity * step)
		var limit: int = origin + polarity * swamp.distance
		if (entity.matrix12[slot] > limit) if polarity > 0 else (entity.matrix12[slot] < limit):
			custom.direction = OUT
	else:
		entity.matrix12[slot] = PlatformMath.s32(entity.matrix12[slot] - polarity * step)
		if (entity.matrix12[slot] < origin) if polarity > 0 else (entity.matrix12[slot] > origin):
			custom.direction = IN
