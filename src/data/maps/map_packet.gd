class_name MapPacket
extends Resource
## A bounded packet retained without interpreting gameplay behavior.

## Stored identifier.
@export var identifier: String = ""
## Stored source offset.
@export var source_offset: int = 0
## Stored end offset.
@export var end_offset: int = 0
## Stored count.
@export var count: int = 0
## Stored offsets.
@export var offsets: PackedInt32Array = PackedInt32Array()
## Stored raw header.
@export var raw_header: PackedByteArray = PackedByteArray()
## Stored dimensions.
@export var dimensions: Vector2i = Vector2i.ZERO
## Stored cell size.
@export var cell_size: Vector2i = Vector2i.ZERO
## Stored grid square count.
@export var grid_square_count: int = 0
