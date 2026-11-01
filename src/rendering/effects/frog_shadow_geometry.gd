class_name FrogShadowGeometry
extends RefCounted
## Source shadow phase, corner layout and grid-line split of EFFECTS.C and FROG.C.
##
## [method phase] follows UpdateFrogEffects (FROG.C:2444-2482) and the offset
## and texture tables of FROG.C:136-179. [method layout] follows the
## EFFECT_TYPE_SHADOW branch of UpdateEffects (EFFECTS.C:327-583): corners
## rotate by the owner's world-Y quadrant (or stay unrotated for
## EFFECT_NO_ROTATION), and a shadow whose corners 0 and 2 lie in different
## grid squares splits into two quads along the grid line, with split-edge
## heights interpolated across the map polygon under corner 0 or 2. Heights
## are resolved separately through [method heights], because they depend on
## the level grid; a failed height query hides the shadow.

## Source FROG_JUMP_TIME and FROG_SUPERJUMP_TIME.
const JUMP_TIME: int = 6
const SUPERJUMP_TIME: int = 15
## Source Frog_jump_shadow_offsets: four corner tables (0-based).
const OFFSET_TABLES: Array[Array] = [
	[Vector3i(-0x60, 0, 0x70), Vector3i(0x60, 0, 0x70), Vector3i(-0x60, 0, -0x60), Vector3i(0x60, 0, -0x60)],
	[Vector3i(-0x60, 0, 0x90), Vector3i(0x60, 0, 0x90), Vector3i(-0x60, 0, -0x60), Vector3i(0x60, 0, -0x60)],
	[Vector3i(-0x60, 0, 0xb0), Vector3i(0x60, 0, 0xb0), Vector3i(-0x60, 0, -0x80), Vector3i(0x60, 0, -0x80)],
	[Vector3i(-0x60, 0, 0xd0), Vector3i(0x60, 0, 0xd0), Vector3i(-0x60, 0, -0xb0), Vector3i(0x60, 0, -0xb0)],
]
## Offset table per jump phase 0-5.
const PHASE_TABLES: PackedInt32Array = [0, 1, 2, 3, 2, 1]
## Shadow image per jump phase 0-5.
const PHASE_TEXTURES: PackedStringArray = ["im_frog_shadow0", "im_frog_shadow1", "im_frog_shadow2", "im_frog_shadow2", "im_frog_shadow2", "im_frog_shadow1"]
## Image of the unrotated (EFFECT_NO_ROTATION) shadows.
const NO_ROTATION_TEXTURE: String = "im_gen_shadow"
## Source shadow polygon grey (setRGB0 0x30) and SHADOW_OT_OFFSET.
const GREY: int = 0x30
const OT_OFFSET: int = -4
## Grid line margin selecting the split alignment.
const ALIGN_MARGIN: int = 0x40

## One drawn corner: s16 XZ and how its height is found.
class Point extends RefCounted:
	## s16 world X and Z.
	var x: int = 0
	var z: int = 0
	## s32 corner the height query starts from (layer choice uses its Y).
	var query := Vector3i.ZERO
	## -1 for a grid query, otherwise the square under corner 0 (0) or corner 2 (1).
	var square: int = -1
	## Map polygon vertices interpolated from [member from_vertex] to [member to_vertex].
	var from_vertex: int = 0
	var to_vertex: int = 0
	## 0 interpolates by X, 2 by Z.
	var axis: int = 0

	## The golden height rule text: "grid" or the square interpolation.
	func height_rule() -> String:
		if square < 0:
			return "grid"
		return "square%d:v%d+((%s&0xff)*(v%d-v%d))>>8" % [square, from_vertex, "x" if axis == 0 else "z", to_vertex, from_vertex]

## Corners, split and texture coordinates of one shadow.
class Layout extends RefCounted:
	## World-Y quadrant, or -1 for an unrotated shadow.
	var quadrant: int = -1
	## Unrotated shadows only: whether the corner order rotated.
	var reordered: bool = false
	## s32 corners 0-3 after rotation or reordering.
	var corners: Array[Vector3i] = []
	var split: bool = false
	## "N", "E", "S" or "W" for a split shadow, otherwise "".
	var alignment: String = ""
	## One or two quads of four points in source corner order 0, 1, 2, 3.
	var polys: Array[Array] = []
	## Texture (u, v) bytes per quad corner.
	var uvs: Array[Array] = []
	## Split texture V byte, or -1.
	var split_v: int = -1

## Texture corner bytes of an image: u0..u3, v0..v3 and its height.
class TextureUv extends RefCounted:
	var u: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
	var v: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
	var h: int = 0

	## Corner bytes spanning a [param width] by [param height] image from (0, 0).
	static func spanning(width: int, height: int) -> TextureUv:
		var result := TextureUv.new()
		result.u = PackedInt32Array([0, width, 0, width])
		result.v = PackedInt32Array([0, 0, height, height])
		result.h = height
		return result


## Jump phase 0-5 from the frog's mode, flags and fr_count.
static func phase(mode: int, flags: int, remaining_ticks: int) -> int:
	if mode != FrogMode.JUMPING or flags & FrogFlags.JUMP_ON_SPOT:
		return 0
	var count: int = JUMP_TIME - remaining_ticks
	if flags & FrogFlags.SUPERJUMP:
		count = PlatformMath.divide((SUPERJUMP_TIME - remaining_ticks) * JUMP_TIME, SUPERJUMP_TIME)
	return clampi(count, 0, JUMP_TIME - 1)


## Corner offsets of jump phase [param jump_phase].
static func phase_offsets(jump_phase: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	result.assign(OFFSET_TABLES[PHASE_TABLES[jump_phase]])
	return result


## True while UpdateFrogEffects hides the frog shadow, or the committed state hides it.
static func hidden(state: GameplayState) -> bool:
	var frog: FrogState = state.frog
	if frog.shadow_hidden or state.attachment.current_entity_index >= 0 or not frog.flags & FrogFlags.ACTIVE:
		return true
	if frog.mode == FrogMode.DYING or frog.mode == FrogMode.CHECKPOINT_COLLECTED:
		return true
	if frog.mode == FrogMode.JUMPING and not frog.flags & FrogFlags.JUMP_TO_LAND:
		return true
	return state.completed and state.flow.phase == LevelFlowState.Phase.COMPLETE


## Source GetWorldYQuadrantFromMatrix (MISC.C:75-99) on m[2][2] against m[0][2].
static func quadrant(matrix12: PackedInt32Array) -> int:
	var m22: int = matrix12[8]
	var m02: int = matrix12[2]
	if absi(m22) > absi(m02):
		return 0 if m22 > 0 else 2
	return 1 if m02 > 0 else 3


## The corners, split and texture coordinates of a shadow with corner
## [param offsets] at [param translation], rotated by [param matrix12]'s
## quadrant unless [param no_rotation], against grid origin [param grid_base].
static func layout(offsets: Array[Vector3i], translation: Vector3i, matrix12: PackedInt32Array, no_rotation: bool, grid_base: Vector2i, uv: TextureUv) -> Layout:
	var result := Layout.new()
	var vec: Array[Vector3i] = []
	var x0: int = 0
	var z0: int = 0
	var x2: int = 0
	var z2: int = 0
	if no_rotation:
		for offset: Vector3i in offsets:
			vec.append(_s32(translation + offset))
		x0 = (vec[0].x - grid_base.x) >> 8
		z0 = (vec[0].z - grid_base.y) >> 8
		var x1: int = (vec[1].x - grid_base.x) >> 8
		x2 = (vec[2].x - grid_base.x) >> 8
		z2 = (vec[2].z - grid_base.y) >> 8
		result.reordered = x0 != x1
		if result.reordered:
			var temp: Vector3i = vec[2]
			vec[2] = vec[0]
			vec[0] = vec[1]
			vec[1] = vec[3]
			vec[3] = temp
			x2 = x0
			z2 = z0
			z0 = (vec[0].z - grid_base.y) >> 8
	else:
		result.quadrant = quadrant(matrix12)
		var angle: int = result.quadrant * 0x400
		var cosine: int = roundi(cos(float(angle) * TAU / 4096.0) * 4096.0)
		var sine: int = roundi(sin(float(angle) * TAU / 4096.0) * 4096.0)
		var rotation := PackedInt32Array([cosine, 0, sine, 0, 0x1000, 0, -sine, 0, cosine])
		for offset: Vector3i in offsets:
			vec.append(_s32(PlatformMath.apply(rotation, offset) + translation))
		x0 = (vec[0].x - grid_base.x) >> 8
		x2 = (vec[2].x - grid_base.x) >> 8
		z0 = (vec[0].z - grid_base.y) >> 8
		z2 = (vec[2].z - grid_base.y) >> 8
	result.corners = vec
	var full: Array[Vector2i] = [Vector2i(uv.u[0], uv.v[0]), Vector2i(uv.u[1], uv.v[1]), Vector2i(uv.u[2], uv.v[2]), Vector2i(uv.u[3], uv.v[3])]
	if x0 == x2 and z0 == z2:
		var points: Array[Point] = []
		for corner: Vector3i in vec:
			points.append(_grid(corner))
		result.polys = [points]
		result.uvs = [full]
		return result
	result.split = true
	var v0: Vector3i = vec[0]
	var v1: Vector3i = vec[1]
	var v2: Vector3i = vec[2]
	var v3: Vector3i = vec[3]
	var span: int = offsets[0].z - offsets[2].z
	var top: Array[Point] = []
	var bottom: Array[Point] = []
	var depth: int = 0
	if v0.z - v2.z > ALIGN_MARGIN:
		result.alignment = "N"
		top = [_edge(v0.x, v0.z & ~0xff, v0, 0, 2, 3, 0), _edge(v1.x, v1.z & ~0xff, v0, 0, 2, 3, 0)]
		bottom = [_edge(v2.x, v0.z & ~0xff, v2, 1, 0, 1, 0), _edge(v3.x, v1.z & ~0xff, v2, 1, 0, 1, 0)]
		depth = v0.z & 0xff
	elif v0.x - v2.x > ALIGN_MARGIN:
		result.alignment = "E"
		top = [_edge(v0.x & ~0xff, v0.z, v0, 0, 2, 0, 2), _edge(v1.x & ~0xff, v1.z, v0, 0, 2, 0, 2)]
		bottom = [_edge(v0.x & ~0xff, v2.z, v2, 1, 3, 1, 2), _edge(v1.x & ~0xff, v3.z, v2, 1, 3, 1, 2)]
		depth = v0.x & 0xff
	elif v0.z - v2.z < -ALIGN_MARGIN:
		result.alignment = "S"
		top = [_edge(v0.x, v2.z & ~0xff, v0, 0, 0, 1, 0), _edge(v1.x, v3.z & ~0xff, v0, 0, 0, 1, 0)]
		bottom = [_edge(v2.x, v2.z & ~0xff, v2, 1, 2, 3, 0), _edge(v3.x, v3.z & ~0xff, v2, 1, 2, 3, 0)]
		depth = 0x100 - (v0.z & 0xff)
	else:
		result.alignment = "W"
		top = [_edge(v2.x & ~0xff, v0.z, v0, 0, 3, 1, 2), _edge(v3.x & ~0xff, v1.z, v0, 0, 3, 1, 2)]
		bottom = [_edge(v2.x & ~0xff, v2.z, v2, 1, 2, 0, 2), _edge(v3.x & ~0xff, v3.z, v2, 1, 2, 0, 2)]
		depth = 0x100 - (v0.x & 0xff)
	result.split_v = (uv.v[0] + PlatformMath.divide(depth * uv.h, span)) & 0xff
	var first: Array[Point] = [_grid(v0), _grid(v1), top[0], top[1]]
	var second: Array[Point] = [bottom[0], bottom[1], _grid(v2), _grid(v3)]
	result.polys = [first, second]
	result.uvs = [
		[full[0], full[1], Vector2i(uv.u[2], result.split_v), Vector2i(uv.u[3], result.split_v)],
		[Vector2i(uv.u[0], result.split_v), Vector2i(uv.u[1], result.split_v), full[2], full[3]],
	]
	return result


## Heights of every point of [param shadow] in poly order through
## [param grid], or an empty array when a query fails (the source's
## GRID_RETURN_VALUE_ERROR, which hides the shadow).
static func heights(shadow: Layout, grid: GridDefinition) -> PackedInt32Array:
	var result := PackedInt32Array()
	if grid == null or shadow.corners.size() != 4:
		return result
	var squares: Array[GridSquareDefinition] = [null, null]
	if shadow.split:
		for slot: int in 2:
			var corner: Vector3i = shadow.corners[slot * 2]
			var info: GridSurfaceInfo = GridQueries.height_at(grid, corner.x, corner.y, corner.z)
			if info == null:
				return PackedInt32Array()
			squares[slot] = grid.squares[info.square_index]
	for poly: Array in shadow.polys:
		for point: Point in poly:
			if point.square < 0:
				var info: GridSurfaceInfo = GridQueries.height_at(grid, point.query.x, point.query.y, point.query.z)
				if info == null:
					return PackedInt32Array()
				result.append(info.height)
				continue
			var square: GridSquareDefinition = squares[point.square]
			var start: int = square.vertices[point.from_vertex].y
			var finish: int = square.vertices[point.to_vertex].y
			var along: int = (point.x if point.axis == 0 else point.z) & 0xff
			result.append(start + ((along * (finish - start)) >> 8))
	return result


static func _grid(corner: Vector3i) -> Point:
	var point := Point.new()
	point.x = PlatformMath.s16(corner.x)
	point.z = PlatformMath.s16(corner.z)
	point.query = corner
	return point


static func _edge(x: int, z: int, query: Vector3i, square: int, from_vertex: int, to_vertex: int, axis: int) -> Point:
	var point := Point.new()
	point.x = PlatformMath.s16(x)
	point.z = PlatformMath.s16(z)
	point.query = query
	point.square = square
	point.from_vertex = from_vertex
	point.to_vertex = to_vertex
	point.axis = axis
	return point


static func _s32(value: Vector3i) -> Vector3i:
	return Vector3i(PlatformMath.s32(value.x), PlatformMath.s32(value.y), PlatformMath.s32(value.z))
