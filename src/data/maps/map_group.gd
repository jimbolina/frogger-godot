class_name MapGroup
extends Resource
## A visible or invisible map group and resolved polygon identities.

## Stored source offset.
@export var source_offset: int = 0
## Stored coordinates.
@export var coordinates: Vector2i = Vector2i.ZERO
## Stored visible.
@export var visible: bool = true
## Stored counts.
@export var counts: PackedInt32Array = PackedInt32Array()
## Stored pointers.
@export var pointers: PackedInt32Array = PackedInt32Array()
## Stored polygon indices.
@export var polygon_indices: PackedInt32Array = PackedInt32Array()
## Stored static entity pointer.
@export var static_entity_pointer: int = 0
