class_name TongueTarget
extends RefCounted
## Source group traversal, range and landscape obstruction for tongue selection.

var error: String = ""
var entity_index: int = -1

## Chooses the strictly nearest eligible target, retaining source order for ties.
static func find(grid: GridDefinition, collision: EntityCollisionDefinition, state: GameplayState) -> TongueTarget:
	var result := TongueTarget.new()
	if collision == null or state.entities == null:
		return result
	var origin := Vector3i(state.frog.matrix12[9], state.frog.matrix12[10], state.frog.matrix12[11])
	var best: int = 1152 * 1152 if state.frog.powerup_flags & PowerupFlags.SUPER_TONGUE else 640 * 640
	for index: int in EntityContactOrder._indices_validated(collision, state.entities, origin):
		var slot: int = -1
		for candidate: int in collision.entities.size():
			if collision.entities[candidate].entity_index == index:
				slot = candidate
				break
		if slot < 0 or not collision.entities[slot].behavior.tongueable:
			continue
		var pose: EntitySnapshot = state.entities.entities[slot]
		if not pose.live or pose.live_flags & EntityLiveFlags.TARGETTED:
			continue
		var destination := Vector3i(pose.matrix12[9], pose.matrix12[10], pose.matrix12[11])
		var delta: Vector3i = GridLine._short(destination - origin)
		var distance: int = PlatformMath.s32(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z)
		if distance >= best:
			continue
		var sight: TongueTarget = line_of_sight(grid, origin, destination)
		if not sight.error.is_empty():
			return sight
		if sight.entity_index == 1:
			best = distance
			result.entity_index = index
	return result

## Returns one for visible, zero for obstructed, or an explicit unsafe lookup error.
static func line_of_sight(grid: GridDefinition, start: Vector3i, end: Vector3i) -> TongueTarget:
	var result := TongueTarget.new()
	result.entity_index = 0
	var line: GridLine = GridLine.create(grid, start, end)
	while true:
		var cell: Vector2i = line.advance()
		var stack: GridStackDefinition = grid.stack_at(cell)
		if stack == null:
			result.error = "Tongue line-of-sight cell %s lies outside authored storage" % cell
			return result
		for index: int in range(stack.first_square_index, stack.first_square_index + stack.square_count):
			for vertex: int in 3:
				if line.position.y - 200 > grid.squares[index].vertices[vertex].y:
					return result
		if line.mode == GridLine.Mode.DONE:
			result.entity_index = 1
			return result
	return result
