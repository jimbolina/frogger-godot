class_name ModelMesh
extends RefCounted
## A static model turned into Godot meshes: one mesh per part.
##
## Parts are kept apart because the game moves and hides them one by one: an
## animated model turns each part by its own transform, and some parts are
## never shown.

## One mesh per part, in part order; null for a part with nothing to draw.
var part_meshes: Array[ArrayMesh] = []
## Shared cel atlases and blend-free draw meshes for animated parts.
var morph_meshes: Array[ModelMorphMesh] = []
## Triangles in all meshes.
var triangle_count: int = 0
## Surfaces in all meshes.
var surface_count: int = 0
## Polygons left out because their kind is a line.
var skipped_polygons: int = 0
## Texture ids no loaded bank has, each once. Their polygons are drawn untextured.
var missing_image_ids := PackedInt32Array()
## Rendering fallbacks caused by incomplete image data, shown by inspection tools.
var diagnostics := PackedStringArray()
## Bounds covering the geometry and every sampled animation action.
var bounds := AABB()
## Local bounds of every part, including every flipbook cel.
var part_bounds: Array[AABB] = []
## Conservative bounds of each geometry action, for a fixed viewer camera.
var action_bounds: Array[AABB] = []
## Texture tracks per part. Their surfaces have their own immutable frame materials.
var texture_tracks: Array[Array] = []


## One animated polygon's materials, precomputed so playback allocates no resources.
class TextureTrack:
	extends RefCounted
	## Surface and target index in its part.
	var surface: int = 0
	var target: int = 0
	## The polygon's original image, used when animation is disabled.
	var original: ShaderMaterial
	## A material for every entry of the texture list, including missing-image fallbacks.
	var frames: Array[ShaderMaterial] = []


## True when there is nothing to draw.
func is_empty() -> bool:
	return triangle_count == 0
