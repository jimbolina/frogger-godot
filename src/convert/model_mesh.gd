class_name ModelMesh
extends RefCounted
## A static model turned into Godot meshes: one mesh per part.
##
## Parts are kept apart because the game moves and hides them one by one: an
## animated model turns each part by its own transform, and some parts are
## never shown.

## One mesh per part, in part order; null for a part with nothing to draw.
var part_meshes: Array[ArrayMesh] = []
## Triangles in all meshes.
var triangle_count: int = 0
## Surfaces in all meshes.
var surface_count: int = 0
## Polygons left out because their kind is a line.
var skipped_polygons: int = 0
## Texture ids no loaded bank has, each once. Their polygons are drawn untextured.
var missing_image_ids := PackedInt32Array()
## The smallest box holding every vertex drawn.
var bounds := AABB()


## True when there is nothing to draw.
func is_empty() -> bool:
	return triangle_count == 0
