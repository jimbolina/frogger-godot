class_name SkyLandFile
extends RefCounted
## Bounded sky backdrop tile reader; high two bits store quarter-turn rotation.

## Dimensions and packed tile facts in row order.
var dimensions: Vector2i = Vector2i.ZERO
var texture_ids: PackedInt32Array = PackedInt32Array()
var rotations: PackedInt32Array = PackedInt32Array()
var packed_tiles: PackedInt32Array = PackedInt32Array()
## Failure reason, or empty on success.
var error: String = ""

## Reads a sky tile map without loading textures.
static func read(bytes: PackedByteArray) -> SkyLandFile:
	var sky := SkyLandFile.new()
	if bytes.size() < 4:
		sky.error = "Truncated sky tile header"
		return sky
	sky.dimensions = Vector2i(bytes.decode_u16(0), bytes.decode_u16(2))
	var count: int = sky.dimensions.x * sky.dimensions.y
	if count > ((bytes.size() - 4) >> 1) or bytes.size() != 4 + count * 2:
		sky.error = "Sky dimensions do not match bounded tile data"
		return sky
	for i: int in count:
		var value: int = bytes.decode_u16(4 + i * 2)
		sky.packed_tiles.append(value)
		sky.texture_ids.append(value & 0x3fff)
		sky.rotations.append(value >> 14)
	return sky
