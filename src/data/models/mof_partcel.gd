class_name MofPartcel
extends Resource
## One pose of a model part.

## x, y, z of each vertex, in the game's units.
@export var vertices := PackedInt32Array()
## x, y, z of each normal; 4096 is a length of one.
@export var normals := PackedInt32Array()
## x, y, z of the box's 8 corners, or empty when there is no box.
@export var bounding_box := PackedInt32Array()
