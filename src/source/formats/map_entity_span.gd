class_name MapEntitySpan
extends RefCounted
## An entity identity with its bounded, uninterpreted payload.

## Stored source offset.
var source_offset: int = 0
## Stored end offset.
var end_offset: int = 0
## Stored form grid id.
var form_grid_id: int = 0
## Stored unique id.
var unique_id: int = 0
## Stored form id.
var form_id: int = 0
## Stored flags.
var flags: int = 0
## Stored payload.
var payload: PackedByteArray = PackedByteArray()
