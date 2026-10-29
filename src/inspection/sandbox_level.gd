class_name SandboxLevel
extends RefCounted
## Builds a flat, data-free test arena with labelled terrain zones for live play checks.

const SOURCE_ID: String = "synthetic:sandbox"
const CELL_SIZE: int = 256
const DIMENSIONS: Vector2i = Vector2i(32, 32)
const BASE: Vector2i = Vector2i(-4096, -4096)
const SPAWN_CELL: Vector2i = Vector2i(16, 2)
const SPAWN_DIRECTION: int = 0
const LEVEL_TIME: int = 2250
const CAMERA_ZONE_INDEX: int = 0
const CAMERA_SOURCE_OFFSET: Vector3i = Vector3i(0, -900, -600)
const STEP_HEIGHT: int = 128
const PLAIN: int = GridSquareFlags.USABLE | GridSquareFlags.SAFE

## One labelled rectangle of identical terrain flags; later zones override earlier ones.
class Zone extends RefCounted:
	var name: StringName = &""
	var cells: Rect2i = Rect2i()
	var flags: int = 0

	## Creates a zone covering `zone_cells` with source grid-square `zone_flags`.
	func _init(zone_name: StringName, zone_cells: Rect2i, zone_flags: int) -> void:
		name = zone_name
		cells = zone_cells
		flags = zone_flags

var level: LevelDefinition = null
var zones: Array[Zone] = []

## Returns the arena with every zone, a camera zone, spawn, rewards and empty entities.
static func build() -> SandboxLevel:
	var sandbox := SandboxLevel.new()
	sandbox.zones = default_zones()
	sandbox.level = LevelDefinition.new()
	var definition: LevelDefinition = sandbox.level
	definition.source_id = SOURCE_ID
	definition.map_index = -1
	definition.spawn_cell = SPAWN_CELL
	definition.spawn_direction = SPAWN_DIRECTION
	definition.level_time = LEVEL_TIME
	definition.flow_enabled = true
	definition.collision_enabled = true
	definition.rewards = GameplayRewards.component_definitions()
	definition.camera = GameplayCameraDefinition.new()
	definition.camera_zones.append(camera_zone(sandbox.zone_named(&"camera").cells))
	for action: int in FrogAnimationCatalog.ACTION_NAMES.size():
		definition.frog_action_lengths.append(3 + action % 3)
	definition.grid = sandbox._build_grid()
	definition.entity_collision = empty_entity_collision()
	return sandbox

## Lists the authored zone layout, starting with the plain safe floor.
static func default_zones() -> Array[Zone]:
	var result: Array[Zone] = []
	result.append(Zone.new(&"plain", Rect2i(Vector2i.ZERO, DIMENSIONS), PLAIN))
	result.append(Zone.new(&"water", Rect2i(3, 6, 6, 4), GridSquareFlags.USABLE | GridSquareFlags.WATER))
	result.append(Zone.new(&"ice", Rect2i(11, 6, 4, 6), GridSquareFlags.USABLE | GridSquareFlags.SLIPPY))
	result.append(Zone.new(&"freeform_ice", Rect2i(17, 6, 4, 6), GridSquareFlags.USABLE | GridSquareFlags.FREEFORM_SLIPPY))
	result.append(Zone.new(&"bouncy", Rect2i(23, 6, 4, 4), GridSquareFlags.USABLE | GridSquareFlags.BOUNCY))
	result.append(Zone.new(&"deadly", Rect2i(3, 14, 6, 3), GridSquareFlags.USABLE | GridSquareFlags.DEADLY))
	result.append(Zone.new(&"soft", Rect2i(11, 14, 4, 4), PLAIN | GridSquareFlags.SOFT))
	result.append(Zone.new(&"checkpoint", Rect2i(17, 14, 2, 2), PLAIN | GridSquareFlags.CHECKPOINT))
	result.append(Zone.new(&"cliff_steps", Rect2i(23, 14, 3, 3), PLAIN))
	result.append(Zone.new(&"cliff", Rect2i(23, 17, 3, 2), GridSquareFlags.USABLE | GridSquareFlags.CLIFF))
	result.append(Zone.new(&"camera", Rect2i(3, 22, 8, 6), PLAIN))
	return result

## Returns a camera zone over `cells` that raises and pulls back the view in every direction.
static func camera_zone(cells: Rect2i) -> ZoneDefinition:
	var zone := ZoneDefinition.new()
	zone.source_id = SOURCE_ID
	zone.zone_index = CAMERA_ZONE_INDEX
	zone.bounds = PackedInt32Array([cells.position.x, cells.position.y, cells.end.x - 1, cells.end.y - 1])
	for unused: int in 4:
		zone.camera_offsets.append(CAMERA_SOURCE_OFFSET)
		zone.camera_offsets.append(Vector3i.ZERO)
	return zone

## Returns an entity table with no entities whose collision groups cover the arena.
static func empty_entity_collision() -> EntityCollisionDefinition:
	var collision := EntityCollisionDefinition.new()
	collision.platforms_enabled = true
	collision.group_base = Vector3i(BASE.x, 0, BASE.y)
	collision.group_dimensions = DIMENSIONS
	collision.group_size = Vector2i(CELL_SIZE, CELL_SIZE)
	return collision

## Returns the normal level start used by the dedicated game scene.
static func run_start() -> RunStart:
	var start := RunStart.new()
	start.start_mode = RunStart.Mode.SINGLE_START
	start.camera_startup = true
	start.start_timer = 120
	return start

## Returns the zone with `zone_name`, or null when the layout has none.
func zone_named(zone_name: StringName) -> Zone:
	for zone: Zone in zones:
		if zone.name == zone_name:
			return zone
	return null

## Returns the topmost zone covering `cell`, or null outside the arena.
func zone_at(cell: Vector2i) -> Zone:
	for index: int in range(zones.size() - 1, -1, -1):
		if zones[index].cells.has_point(cell):
			return zones[index]
	return null

## Returns the built terrain flags at `cell`, or -1 outside the grid.
func flags_at(cell: Vector2i) -> int:
	if level == null or level.grid == null:
		return -1
	var stack: GridStackDefinition = level.grid.stack_at(cell)
	if stack == null:
		return -1
	return level.grid.squares[stack.first_square_index].flags

## Returns the authored (north, south) edge heights at `cell`; negative is up.
func edge_heights(cell: Vector2i) -> Vector2i:
	var zone: Zone = zone_at(cell)
	if zone == null:
		return Vector2i.ZERO
	var row: int = cell.y - zone.cells.position.y
	if zone.name == &"cliff_steps":
		var step: int = -STEP_HEIGHT * (row + 1)
		return Vector2i(step, step)
	if zone.name == &"cliff":
		var top: int = -STEP_HEIGHT * zone_named(&"cliff_steps").cells.size.y
		@warning_ignore("integer_division")
		var drop: int = -top / zone.cells.size.y
		return Vector2i(top + drop * (row + 1), top + drop * row)
	return Vector2i.ZERO

func _build_grid() -> GridDefinition:
	var grid := GridDefinition.new()
	grid.dimensions = DIMENSIONS
	grid.base = BASE
	for z: int in DIMENSIONS.y:
		for x: int in DIMENSIONS.x:
			var cell := Vector2i(x, z)
			var stack := GridStackDefinition.new()
			stack.first_square_index = grid.squares.size()
			stack.square_count = 1
			grid.stacks.append(stack)
			var square := GridSquareDefinition.new()
			square.flags = zone_at(cell).flags
			var heights: Vector2i = edge_heights(cell)
			var left: int = BASE.x + x * CELL_SIZE
			var bottom: int = BASE.y + z * CELL_SIZE
			square.vertices.assign([Vector3i(left, heights.x, bottom + CELL_SIZE), Vector3i(left + CELL_SIZE, heights.x, bottom + CELL_SIZE),
				Vector3i(left, heights.y, bottom), Vector3i(left + CELL_SIZE, heights.y, bottom)])
			grid.squares.append(square)
	return grid
