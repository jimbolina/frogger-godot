class_name MapEntitySpan
extends Resource
## An entity identity with its bounded, uninterpreted payload.

## Stored source offset.
@export var source_offset: int = 0
## Stored end offset.
@export var end_offset: int = 0
## Stored form grid id.
@export var form_grid_id: int = 0
## Stored unique id.
@export var unique_id: int = 0
## Stored form id.
@export var form_id: int = 0
## Stored flags.
@export var flags: int = 0
## Stored payload.
@export var payload: PackedByteArray = PackedByteArray()
