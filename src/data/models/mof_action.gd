class_name MofAction
extends Resource
## An authored animation action of an XAR model set, including virtual frames
## and transform indices.

## Unique cels the action stores.
@export var cel_count: int = 0
## Parts each cel transforms.
@export var part_count: int = 0
## Virtual frames the action plays.
@export var frame_count: int = 0
## Flags as stored: 1 for plain cels, 2 for interpolated triples.
@export var flags: int = 0
## The virtual frames: a cel number each, or first cel, second cel and amount.
@export var cel_numbers := PackedInt32Array()
## Shared transform index of each cel and part, cel major.
@export var transform_indices := PackedInt32Array()
## A semantic problem disables sampling but preserves the authored record.
@export var error: String = ""
