class_name MapGroup
extends RefCounted
## A visible or invisible map group and resolved polygon identities.

## Stored source offset.
var source_offset: int = 0
## Stored coordinates.
var coordinates: Vector2i = Vector2i.ZERO
## Stored visible.
var visible: bool = true
## Stored counts.
var counts: PackedInt32Array = PackedInt32Array()
## Stored pointers.
var pointers: PackedInt32Array = PackedInt32Array()
## Stored polygon indices.
var polygon_indices: PackedInt32Array = PackedInt32Array()
## Stored static entity pointer.
var static_entity_pointer: int = 0
