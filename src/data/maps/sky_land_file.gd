class_name SkyLandFile
extends Resource
## Sky backdrop tile map; high two bits of each packed tile store quarter-turn rotation.

## Dimensions and packed tile facts in row order.
@export var dimensions: Vector2i = Vector2i.ZERO
@export var texture_ids: PackedInt32Array = PackedInt32Array()
@export var rotations: PackedInt32Array = PackedInt32Array()
@export var packed_tiles: PackedInt32Array = PackedInt32Array()
## Failure reason, or empty on success.
@export var error: String = ""

## Reads a sky tile map without loading textures.
static func read(bytes: PackedByteArray) -> SkyLandFile:
	return SkyLandReader.read(bytes)
