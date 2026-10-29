class_name EntityDesertTumbleWeed
extends RefCounted
## Desert tumbleweed path roll, random hops and map-edge shadow visibility.

## Source SFX_DES_TUMBLEWEED and its PlayMovingSound radii.
const SOUND: int = 61
const SOUND_NEAR: int = 512
const SOUND_FAR: int = 1024
## Source SYSTEM_GRAVITY in 16.16 units per update.
const GRAVITY_16: int = 0x100000
const ROLL_STEP: int = 0x60

## Clears roll, hop count and velocity, hides the shadow and starts the rolling moving sound.
static func initialize(_definition: EntityDefinition, entity: EntitySnapshot) -> void:
	var custom: EntityCustomState = entity.custom_state
	custom.direction = 0
	custom.count = 0
	custom.velocity_16 = Vector3i.ZERO
	custom.shadow_visible = false
	if custom.moving_sound.is_empty():
		custom.moving_sound = PackedInt32Array([SOUND, SOUND_NEAR, SOUND_FAR])

## Follows the path in X/Z, rolls about local X and hops; one MRrand draw starts each hop.
## direction holds the roll angle, count the hop count, velocity_16.y the 16.16 Y velocity
## and target.y the integer hop height.
static func update(definition: EntityDefinition, result: EntityCustomResult, grid: GridDefinition) -> String:
	var entity: EntitySnapshot = result.entity
	if entity.custom_state == null or entity.path == null:
		return "Desert tumbleweed requires its path"
	if grid == null:
		return "Desert tumbleweed requires the map grid for its shadow edge test"
	var custom: EntityCustomState = entity.custom_state
	var matrix: PackedInt32Array = EntityTransform.moving(entity.path, entity.entity_flags)
	var cell: Vector2i = GridQueries.world_to_cell(grid, matrix[9], matrix[11])
	custom.shadow_visible = not (cell.x < 1 or cell.x >= grid.dimensions.x - 1 or cell.y < 1 or cell.y >= grid.dimensions.y - 1)
	custom.direction = (custom.direction - ROLL_STEP) & 4095
	matrix = PlatformMath.rotate_x(matrix, custom.direction)
	var expired: bool = custom.count == 0
	custom.count = PlatformMath.s32(custom.count - 1)
	if expired:
		custom.count = result.random.next_value("entity:%d:tumble_weed_hop" % definition.entity_index) % 4 + 6
		custom.velocity_16.y = PlatformMath.s32(-((GRAVITY_16 * (custom.count + 1)) >> 1))
		custom.target.y = matrix[10]
	else:
		custom.velocity_16.y = PlatformMath.s32(custom.velocity_16.y + GRAVITY_16)
		custom.target.y = PlatformMath.s32(custom.target.y + (custom.velocity_16.y >> 16))
		matrix[10] = custom.target.y
	entity.matrix12 = matrix
	return ""
