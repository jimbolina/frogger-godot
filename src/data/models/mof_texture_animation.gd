class_name MofTextureAnimation
extends Resource
## Authored texture image ids and their game-frame durations.

## Global texture id of each step.
@export var image_ids := PackedInt32Array()
## Game frames each step lasts.
@export var durations := PackedInt32Array()
## Empty lists are retained but unavailable; a duration of zero is legal.
@export var error: String = ""
