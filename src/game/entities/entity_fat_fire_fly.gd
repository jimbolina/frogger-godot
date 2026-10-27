class_name EntityFatFireFly
extends RefCounted
## Frozen fat fire fly pickup: authored pose, source bobbing and buzz requests.

## Source SFX_GEN_FLY_BUZZ sample and PlaySoundDistance range.
const BUZZ_SOUND: int = 0
const BUZZ_DISTANCE: int = 20

## Creates the identity pose at the authored translation.
static func initialize(definition: EntityDefinition, entity: EntitySnapshot) -> void:
	entity.matrix12 = EntityTransform.IDENTITY.duplicate()
	for axis: int in 3:
		entity.matrix12[9 + axis] = definition.matrix12[9 + axis]
	entity.animation = null

## Bobs on the source frame clock and draws one buzz chance per update.
static func update(definition: EntityDefinition, result: EntityCustomResult, frog: GameplayState, frame_number: int) -> String:
	var entity: EntitySnapshot = result.entity
	if entity.entity_flags & EntityDefinition.NO_MOVEMENT:
		return ""
	var angle: int = (((definition.unique_id & 7) << 7) + (frame_number << 8)) & 4095
	entity.matrix12[10] = definition.matrix12[10] + (EntityBonusFly.sine(angle) >> 5)
	if result.random.next_value("entity:%d:fat_fire_fly_buzz" % definition.entity_index) % 20 == 1:
		if EntityDistanceSound.within(Vector3i(entity.matrix12[9], entity.matrix12[10], entity.matrix12[11]), frog, BUZZ_DISTANCE):
			entity.requests.append(TickEvent.sound(BUZZ_SOUND))
	return ""
