class_name MenuWater
extends RefCounted
## The front-end water surface and riverbed grids and their wave animation (HSView.c
## HSInitialiseWater and HSUpdateWater, HSView.h HIGH_SCORE_VIEW_*).
##
## Units are the source's integer world units with Y pointing down. Both grids are centred on the
## origin; vertex row j runs from Z +half at j 0 towards -Z, and vertex column i from X -half.
## Vertex index is j * (X_NUM + 1) + i. Quad (i, j) uses POLY_FT4 corners 0-3 at vertices
## v, v + 1, v + X_NUM + 1 and v + X_NUM + 2 with v the quad's first vertex.

const WATER_X_NUM: int = 14
const WATER_Z_NUM: int = 16
const WATER_X_LEN: int = 0x240
const WATER_Z_LEN: int = 0x240
const RIVERBED_X_NUM: int = 14
const RIVERBED_Z_NUM: int = 16
const RIVERBED_X_LEN: int = 0x240
const RIVERBED_Z_LEN: int = 0x240
const WAVE_AMP_X: int = 0x40
const WAVE_AMP_Z: int = 0x50
const WAVE_FREQ_X: int = 0x60
const WAVE_FREQ_Z: int = 0x80
const WAVE_PERIOD_X: int = 0x2000
const WAVE_PERIOD_Z: int = 0x2000
const PERSPECTIVE: int = 0x100
const WATER_PRIM_COLOUR: int = 0x00406060
const RIVERBED_PRIM_COLOUR: int = 0x00303030
const WATER_SEMI_TRANSPARENT: bool = true
const WATER_ABR: int = 1
const RIVERBED_OT_FROM_END: int = 1
const WATER_OT_FROM_END: int = 3
const RIVERBED_CORNERS_ODD_ROW: PackedInt32Array = [0, 1, 2, 3]
const RIVERBED_CORNERS_EVEN_ROW: PackedInt32Array = [2, 3, 0, 1]
const TICKS_PER_SECOND: int = 30

var frame_count: int = 0


## A water animation whose viewport frame count starts at [param start_frame].
static func create(start_frame: int = 0) -> MenuWater:
	var water := MenuWater.new()
	water.frame_count = start_frame
	return water


## Advances the frame count by one 30 Hz tick.
func advance() -> void:
	frame_count += 1


## Wave heights for the current frame count (see [method heights]).
func current_heights() -> PackedInt32Array:
	return heights(frame_count)


## Water vertex positions with Y 0, (WATER_X_NUM + 1) * (WATER_Z_NUM + 1) entries.
static func water_vertices() -> Array[Vector3i]:
	return _grid(WATER_X_NUM, WATER_Z_NUM, WATER_X_LEN, WATER_Z_LEN)


## Riverbed vertex positions with Y 0, (RIVERBED_X_NUM + 1) * (RIVERBED_Z_NUM + 1) entries.
static func riverbed_vertices() -> Array[Vector3i]:
	return _grid(RIVERBED_X_NUM, RIVERBED_Z_NUM, RIVERBED_X_LEN, RIVERBED_Z_LEN)


static func _grid(x_num: int, z_num: int, x_len: int, z_len: int) -> Array[Vector3i]:
	var points: Array[Vector3i] = []
	for j: int in z_num + 1:
		for i: int in x_num + 1:
			points.append(Vector3i(-((x_len * x_num) / 2) + i * x_len, 0, ((z_len * z_num) / 2) - j * z_len))
	return points


## Water vertex Y for viewport frame count [param frame]: the two summed sine waves shifted
## right by 12, in vertex order (HSUpdateWater).
static func heights(frame: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	result.resize((WATER_X_NUM + 1) * (WATER_Z_NUM + 1))
	var index: int = 0
	for j: int in WATER_Z_NUM + 1:
		var tz: int = StackLayout.s32((j * WAVE_PERIOD_Z) / WATER_Z_NUM + frame * WAVE_FREQ_Z)
		var z_wave: int = StackLayout.rsin(tz) * WAVE_AMP_Z
		for i: int in WATER_X_NUM + 1:
			var tx: int = StackLayout.s32((i * WAVE_PERIOD_X) / WATER_X_NUM + frame * WAVE_FREQ_X)
			result[index] = StackLayout.s16((StackLayout.rsin(tx) * WAVE_AMP_X + z_wave) >> 12)
			index += 1
	return result


## The four vertex indices of quad ([param i], [param j]) on a grid [param x_num] quads wide, in
## POLY_FT4 corner order.
static func quad_vertices(i: int, j: int, x_num: int) -> PackedInt32Array:
	var first: int = j * (x_num + 1) + i
	return PackedInt32Array([first, first + 1, first + x_num + 1, first + x_num + 2])


## Water quad ([param i], [param j]) texture coordinates in POLY_FT4 corner order as
## (u0, v0, u1, v1, u2, v2, u3, v3), for a texture at ([param u], [param v]) of size
## ([param width], [param height]) with the source's integer division.
static func water_quad_uvs(i: int, j: int, u: int, v: int, width: int, height: int) -> PackedInt32Array:
	var left: int = u + (width * i) / WATER_X_NUM
	var right: int = u + (width * (i + 1)) / WATER_X_NUM
	var top: int = v + (height * j) / WATER_Z_NUM
	var bottom: int = v + (height * (j + 1)) / WATER_Z_NUM
	return PackedInt32Array([left, top, right, top, left, bottom, right, bottom])


## Water quad ([param i], [param j]) texture fractions of the whole image in POLY_FT4 corner
## order, before the source's truncation to texels.
static func water_quad_fractions(i: int, j: int) -> Array[Vector2]:
	var left: float = float(i) / WATER_X_NUM
	var right: float = float(i + 1) / WATER_X_NUM
	var top: float = float(j) / WATER_Z_NUM
	var bottom: float = float(j + 1) / WATER_Z_NUM
	var corners: Array[Vector2] = [Vector2(left, top), Vector2(right, top), Vector2(left, bottom), Vector2(right, bottom)]
	return corners


## For riverbed quad row [param j], the texture corner each POLY_FT4 corner 0-3 takes: odd rows
## keep the texture's order and even rows swap its top and bottom halves.
static func riverbed_corners(j: int) -> PackedInt32Array:
	return RIVERBED_CORNERS_ODD_ROW if j & 1 != 0 else RIVERBED_CORNERS_EVEN_ROW


## [param colour] as stored in High_score_view_water_prim_colours, unpacked to (r, g, b) from its
## low to high bytes.
static func prim_rgb(colour: int) -> Vector3i:
	return Vector3i(colour & 0xff, (colour >> 8) & 0xff, (colour >> 16) & 0xff)
