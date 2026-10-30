class_name StackLayout
extends RefCounted
## Geometry of the arcade level-select stack and its scene constants (SELECT.C, SELECT.H).
##
## Units are the source's integer world units with Y pointing down. Box vertices are local to
## the stack frame at [constant STACK_ORIGIN]; the first row is the most negative Y and the last
## row sits at Y 0, as SelectLevelInit tiles them (SELECT.C:606-626).

const BOX_HALF_SIZE: int = 0xf0
const STACK_ORIGIN: Vector3i = Vector3i(-0xa00, 0, -0xa00)
const INIT_CAMERA_OFFSET: Vector3i = Vector3i(-0x1000, -0x1800, -0x1800)
const ADJUST_CAMERA_OFFSET: Vector3i = Vector3i(0x700, 0x900, 0x700)
const CAMERA_EYE: Vector3i = STACK_ORIGIN + INIT_CAMERA_OFFSET
const CAMERA_Y_OFFSET: int = CAMERA_EYE.y + ADJUST_CAMERA_OFFSET.y
const Y_AXIS: Vector3i = Vector3i(0, 0x1000, 0)
const PERSPECTIVE: int = 1000
const AMBIENT_COLOUR: int = 0x202020
const LIGHT_COLOURS: PackedInt32Array = [0x606060, 0x404040, 0x303030]
const LIGHT_Y_ROTATIONS: PackedInt32Array = [-0x200, 0x200, 0]
const ANGLE_FULL_TURN: int = 4096
const LEVEL_TABLE: PackedInt32Array = [4, 7, 2, 8, 0, 0, 6, 5, 1, 3]
const GOLD_FROG_SLOTS: int = 10
const SIDE_FACES: int = 4
const FACE_COUNT: int = 6
const FACE_INDICES: PackedInt32Array = [0, 1, 3, 2, 4, 0, 2, 6, 5, 4, 6, 7, 1, 5, 7, 3, 4, 5, 1, 0, 6, 2, 3, 7]
const FACE_NORMALS: Array[Vector3i] = [
	Vector3i(0, 0, 4096), Vector3i(4096, 0, 0), Vector3i(0, 0, -4096),
	Vector3i(-4096, 0, 0), Vector3i(0, 4096, 0), Vector3i(0, -4096, 0),
]
const FACE_TEXTURE_CORNERS: PackedInt32Array = [0, 1, 2, 3]
const SPIN_IMAGE_FACE: int = 5
const SPIN_IMAGE_CORNERS: PackedInt32Array = [2, 0, 3, 1]
const SPIN_TARGET_OFFSET: Vector3i = Vector3i(295, -181, 201)
const SPIN_DEST_Y_TURN: int = 0x40
const SPIN_START_VEC_Y: Vector3i = Vector3i(0, 4096, 0)
const SPIN_START_VEC_ROLL: Vector3i = Vector3i(0, 0, 4096)
const DISPLAY_WIDTH: int = 640
const DISPLAY_HEIGHT: int = 480
const STATUS_START_X: int = DISPLAY_WIDTH + 32
const STATUS_END_X: int = 400
const STATUS_WIDTH: int = 160
const LEVEL_TITLE_Y: int = 300
const SCORE_LINE_Y: PackedInt32Array = [320, 336, 352]
const PROMPT_Y: int = 400
const TITLE_Y: int = 24
const SPRITE_DIM_COLOUR: int = 0x60

var _y_sizes: PackedInt32Array = PackedInt32Array()
var _y_positions: PackedInt32Array = PackedInt32Array()
var _block_starts: PackedInt32Array = PackedInt32Array()


## The layout of [param stack]'s arcade rows.
static func create(stack: LevelStack) -> StackLayout:
	var layout := StackLayout.new()
	var count: int = stack.arcade_count()
	var position: int = 0
	for index: int in count:
		var row: LevelStack.Row = stack.arcade_row(index)
		var size: int = _half_height(row.levels_in_world)
		layout._y_sizes.append(size)
		layout._y_positions.append(position)
		position += size
		if index + 1 < count:
			position += _half_height(stack.arcade_row(index + 1).levels_in_world)
		if index == 0 or stack.arcade_row(index - 1).world != row.world:
			layout._block_starts.append(index)
	if count > 0:
		var last: int = layout._y_positions[count - 1]
		for index: int in count:
			layout._y_positions[index] -= last
	return layout


static func _half_height(levels_in_world: int) -> int:
	return BOX_HALF_SIZE / levels_in_world if levels_in_world > 0 else 0


## Number of rows.
func row_count() -> int:
	return _y_sizes.size()


## Half height of row [param row] (li_y_size): the box half size over the world's level count.
func y_size(row: int) -> int:
	return _y_sizes[row]


## Centre Y of row [param row] (li_y_position).
func y_position(row: int) -> int:
	return _y_positions[row]


## Camera frame Y when row [param row] is in view (SelectFindTarget's Sel_target_y).
func camera_target_y(row: int) -> int:
	return _y_positions[row] + CAMERA_Y_OFFSET


## The camera frame translation for camera Y [param camera_y]; the orientation looks from
## [constant CAMERA_EYE] at [constant STACK_ORIGIN] with Y down (SelectCreateScene).
static func camera_translation(camera_y: int) -> Vector3i:
	return Vector3i(CAMERA_EYE.x + ADJUST_CAMERA_OFFSET.x, camera_y, CAMERA_EYE.z + ADJUST_CAMERA_OFFSET.z)


## The camera frame's rotation, row-major 4.12: MRPointMatrixAtVector from [constant CAMERA_EYE]
## at [constant STACK_ORIGIN] with [constant Y_AXIS] as up. Columns are the camera's X, Y and Z.
static func camera_matrix() -> PackedInt32Array:
	var z: Vector3i = normalise(STACK_ORIGIN - CAMERA_EYE)
	var x: Vector3i = normalise(outer12(Y_AXIS, z))
	var y: Vector3i = outer12(z, x)
	var matrix := PackedInt32Array()
	for row: int in 3:
		matrix.append_array([s16(x[row]), s16(y[row]), s16(z[row])])
	return matrix


## Column [param index] of a row-major 3x3 [param matrix].
static func matrix_column(matrix: PackedInt32Array, index: int) -> Vector3i:
	return Vector3i(matrix[index], matrix[3 + index], matrix[6 + index])


## Where the spinning box starts for row [param row] slid to [param current_z]
## (SelectEnableSpinMOF's spin frame position).
func spin_start(row: int, current_z: int = -(BOX_HALF_SIZE << 1)) -> Vector3i:
	return Vector3i(STACK_ORIGIN.x, _y_positions[row], STACK_ORIGIN.z + current_z)


## Where the spinning box ends for row [param row] with the camera resting on it: the camera
## position plus its Z axis plus [constant SPIN_TARGET_OFFSET] (Z grown by the row's half
## height) in camera space (SELECT.C:2533-2545).
func spin_end(row: int) -> Vector3i:
	var matrix: PackedInt32Array = camera_matrix()
	var offset: Vector3i = apply_matrix(matrix, SPIN_TARGET_OFFSET + Vector3i(0, 0, _y_sizes[row]))
	var camera: Vector3i = camera_translation(camera_target_y(row))
	var forward: Vector3i = matrix_column(matrix, 2)
	var end: Vector3i = camera + forward + offset
	return Vector3i(s16(end.x), s16(end.y), s16(end.z))


## The spinning box's destination Y axis: the camera's -Z turned by [constant SPIN_DEST_Y_TURN]
## about Y (SELECT.C:2552-2561).
static func spin_dest_vec_y() -> Vector3i:
	var cos_value: int = rcos(SPIN_DEST_Y_TURN)
	var sin_value: int = rsin(SPIN_DEST_Y_TURN)
	var turn: PackedInt32Array = [cos_value, 0, sin_value, 0, 0x1000, 0, -sin_value, 0, cos_value]
	var turned: Vector3i = apply_matrix(turn, -matrix_column(camera_matrix(), 2))
	return Vector3i(s16(turned.x), s16(turned.y), s16(turned.z))


## The spinning box's destination roll vector: the camera's Y axis.
static func spin_dest_vec_roll() -> Vector3i:
	return matrix_column(camera_matrix(), 1)


## Direction of parallel light [param index]: its frame's Z axis after the Y rotation.
static func light_direction(index: int) -> Vector3i:
	var angle: int = LIGHT_Y_ROTATIONS[index]
	return Vector3i(rsin(angle), 0, rcos(angle))


## The eight stack-frame vertices of row [param row] slid by [param current_z] (SelectCreateMOF,
## SelectUpdateLevelZ).
func row_vertices(row: int, current_z: int = 0) -> Array[Vector3i]:
	return box_vertices(_y_sizes[row], _y_positions[row], current_z)


## The eight vertices of a box of half height [param half_height] centred at [param centre_y],
## its Z offset by [param current_z], in SelectCreateMOF's order.
static func box_vertices(half_height: int, centre_y: int, current_z: int = 0) -> Array[Vector3i]:
	var top: int = centre_y - half_height
	var bottom: int = centre_y + half_height
	var near: int = -BOX_HALF_SIZE + current_z
	var far: int = BOX_HALF_SIZE + current_z
	var vertices: Array[Vector3i] = [
		Vector3i(-BOX_HALF_SIZE, top, near), Vector3i(BOX_HALF_SIZE, top, near),
		Vector3i(-BOX_HALF_SIZE, bottom, near), Vector3i(BOX_HALF_SIZE, bottom, near),
		Vector3i(-BOX_HALF_SIZE, top, far), Vector3i(BOX_HALF_SIZE, top, far),
		Vector3i(-BOX_HALF_SIZE, bottom, far), Vector3i(BOX_HALF_SIZE, bottom, far),
	]
	return vertices


## The four vertex indices of face [param face] in p0..p3 order; faces 0-3 are the sides and
## 4-5 the ends (SELECT.C:1716-1769).
static func face_indices(face: int) -> PackedInt32Array:
	return FACE_INDICES.slice(face * 4, face * 4 + 4)


## The four vertex indices of face [param face] in POLY_FT4 corner order, which the UV corners
## 0-3 follow: MOF p0, p1, p3, p2.
static func gpu_face_indices(face: int) -> PackedInt32Array:
	var mof: PackedInt32Array = face_indices(face)
	return PackedInt32Array([mof[0], mof[1], mof[3], mof[2]])


## The texture rows a side face of a box shows: x is the V offset into the world image and y the
## strip height, for an image [param texture_height] high (SELECT.C:1825-1828).
static func side_strip(texture_height: int, local_level: int, levels_in_world: int) -> Vector2i:
	var height: int = texture_height / levels_in_world if levels_in_world > 0 else 0
	return Vector2i(local_level * height, height)


## True when a row with [param flags] shows the world's unlocked image rather than the
## not-tried one (SELECT.C:1820-1823).
static func shows_unlocked_image(flags: int) -> bool:
	return flags & LevelProgress.ZONE_ACCESSIBLE != 0


## Number of world blocks: runs of consecutive rows of one world.
func block_count() -> int:
	return _block_starts.size()


## First row of block [param block].
func block_start(block: int) -> int:
	return _block_starts[block]


## The stack block that gold-frog slot [param slot] decorates (Level_table); the slot shows
## Gold_frogs bit slot + 1.
static func gold_frog_block(slot: int) -> int:
	return LEVEL_TABLE[slot]


## The four world-space corners of the gold-frog quad on the stack's -X side covering block
## [param block] (SELECT.C:1076-1111, 1455-1465), or an empty array for a missing block.
func gold_frog_quad(block: int) -> Array[Vector3i]:
	var points: Array[Vector3i] = []
	if block < 0 or block >= _block_starts.size():
		return points
	var first: Array[Vector3i] = row_vertices(_block_starts[block])
	points.append(first[4] + STACK_ORIGIN)
	points.append(first[0] + STACK_ORIGIN)
	if block + 1 < _block_starts.size():
		var next: Array[Vector3i] = row_vertices(_block_starts[block + 1])
		points.append(next[4] + STACK_ORIGIN)
		points.append(next[0] + STACK_ORIGIN)
	else:
		var last: Array[Vector3i] = row_vertices(row_count() - 1)
		points.append(last[6] + STACK_ORIGIN)
		points.append(last[2] + STACK_ORIGIN)
	return points


## The source's rounded 12-bit sine of a 4096-step angle (rsin).
static func rsin(angle: int) -> int:
	return roundi(sin(float(angle & 4095) * TAU / 4096.0) * 4096.0)


## The source's rounded 12-bit cosine of a 4096-step angle (rcos).
static func rcos(angle: int) -> int:
	return roundi(cos(float(angle & 4095) * TAU / 4096.0) * 4096.0)


## [param vector] scaled to length 4096, components rounded half away from zero (MRNormaliseVEC).
static func normalise(vector: Vector3i) -> Vector3i:
	var length: float = Vector3(vector).length()
	if length < 1e-6:
		return Vector3i.ZERO
	return Vector3i(s32(roundi(vector.x * 4096.0 / length)), s32(roundi(vector.y * 4096.0 / length)),
		s32(roundi(vector.z * 4096.0 / length)))


## 4.12 cross product with arithmetic shifts (MROuterProduct12).
static func outer12(a: Vector3i, b: Vector3i) -> Vector3i:
	return Vector3i(s32(a.y * b.z - a.z * b.y) >> 12, s32(a.z * b.x - a.x * b.z) >> 12, s32(a.x * b.y - a.y * b.x) >> 12)


## Row-major 4.12 [param matrix] applied to [param vector] (MRApplyMatrixVEC).
static func apply_matrix(matrix: PackedInt32Array, vector: Vector3i) -> Vector3i:
	var result := Vector3i.ZERO
	for row: int in 3:
		result[row] = s32(matrix[row * 3] * vector.x + matrix[row * 3 + 1] * vector.y + matrix[row * 3 + 2] * vector.z) >> 12
	return result


## [param value] wrapped to a signed 16-bit integer.
static func s16(value: int) -> int:
	var wrapped: int = value & 0xffff
	return wrapped - 0x10000 if wrapped >= 0x8000 else wrapped


## [param value] wrapped to a signed 32-bit integer.
static func s32(value: int) -> int:
	var wrapped: int = value & 0xffffffff
	return wrapped - 0x100000000 if wrapped >= 0x80000000 else wrapped
