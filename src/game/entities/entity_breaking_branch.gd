class_name EntityBreakingBranch
extends RefCounted
## Forest branch hit delay, passenger release and gravity-driven broken transform.

enum Mode { OK, BREAKING, BROKEN }

## Advances one branch against the first authored terrain layer.
static func update(_definition: EntityDefinition, result: EntityCustomResult, frog: GameplayState, hit: bool, grid: GridDefinition) -> String:
	var entity: EntitySnapshot = result.entity
	var custom: EntityCustomState = entity.custom_state
	match custom.mode:
		Mode.OK:
			if hit:
				custom.mode = Mode.BREAKING
				entity.requests.append(TickEvent.sound(66))
		Mode.BREAKING:
			var expired: bool = custom.timer == 0
			custom.timer = (custom.timer - 1) & 65535
			if expired:
				if grid == null:
					return "Breaking branch requires terrain"
				var cell: Vector2i = GridQueries.world_to_cell(grid, entity.matrix12[9], entity.matrix12[11])
				var stack: GridStackDefinition = grid.stack_at(cell)
				if stack == null or stack.first_square_index < 0 or stack.first_square_index >= grid.squares.size():
					return "Breaking branch has no valid first terrain square"
				custom.target.y = GridQueries.square_height(grid.squares[stack.first_square_index])
				custom.velocity_16.y = 0
				custom.mode = Mode.BROKEN
				entity.entity_flags |= EntityDefinition.NO_COLLISION
				entity.requests.append(TickEvent.sound(66))
				result.frog_fall_requested = frog != null and frog.attachment.current_entity_index == entity.entity_index
		Mode.BROKEN:
			if entity.matrix12[10] < custom.target.y:
				custom.velocity_16.y = PlatformMath.s32(custom.velocity_16.y + (Frog.GRAVITY_16 >> 2))
				entity.matrix12[10] = PlatformMath.s32(entity.matrix12[10] + (custom.velocity_16.y >> 16))
				var cosine: int = roundi(cos(TAU * 32.0 / 4096.0) * 4096.0)
				var sine: int = roundi(sin(TAU * 32.0 / 4096.0) * 4096.0)
				var rotation := PackedInt32Array([cosine, -sine, 0, sine, cosine, 0, 0, 0, 4096, 0, 0, 0])
				var matrix: PackedInt32Array = PlatformMath.multiply(entity.matrix12, rotation)
				for axis: int in 3:
					matrix[9 + axis] = entity.matrix12[9 + axis]
				entity.matrix12 = matrix
			else:
				entity.matrix12[10] = custom.target.y - 20
				if not entity.pop_allocated:
					entity.pop_allocated = true
					entity.pop_remaining = 32
					entity.requests.append(TickEvent.make(TickEvent.Kind.ENTITY_POP_EXPLOSION_REQUEST))
	return ""
