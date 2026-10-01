class_name MapPacket
extends RefCounted
## A bounded packet retained without interpreting gameplay behavior.

## Stored identifier.
var identifier: String = ""
## Stored source offset.
var source_offset: int = 0
## Stored end offset.
var end_offset: int = 0
## Stored count.
var count: int = 0
## Stored offsets.
var offsets: PackedInt32Array = PackedInt32Array()
## Stored raw header.
var raw_header: PackedByteArray = PackedByteArray()
## Stored dimensions.
var dimensions: Vector2i = Vector2i.ZERO
## Stored cell size.
var cell_size: Vector2i = Vector2i.ZERO
## Stored grid square count.
var grid_square_count: int = 0
