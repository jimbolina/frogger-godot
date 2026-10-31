class_name ModelMesh
extends Resource
## A static model turned into Godot meshes: one mesh per part.
##
## Parts are kept apart because the game moves and hides them one by one: an
## animated model turns each part by its own transform, and some parts are
## never shown. The importer saves one per model as [code]mesh.res[/code].

## Former inner class, now [ModelTextureTrack].
const TextureTrack := preload("res://src/convert/model_texture_track.gd")

## One mesh per part, in part order; null for a part with nothing to draw.
@export var part_meshes: Array[ArrayMesh] = []
## Shared cel atlases and blend-free draw meshes for animated parts.
@export var morph_meshes: Array[ModelMorphMesh] = []
## Triangles in all meshes.
@export var triangle_count: int = 0
## Surfaces in all meshes.
@export var surface_count: int = 0
## Polygons left out because their kind is a line.
@export var skipped_polygons: int = 0
## Texture ids no loaded bank has, each once. Their polygons are drawn untextured.
@export var missing_image_ids := PackedInt32Array()
## Rendering fallbacks caused by incomplete image data, shown by inspection tools.
@export var diagnostics := PackedStringArray()
## Bounds covering the geometry and every sampled animation action.
@export var bounds := AABB()
## Local bounds of every part, including every flipbook cel.
@export var part_bounds: Array[AABB] = []
## Conservative bounds of each geometry action, for a fixed viewer camera.
@export var action_bounds: Array[AABB] = []
## Texture tracks per part ([ModelTextureTrack]). Their surfaces have their own immutable frame materials.
@export var texture_tracks: Array[Array] = []


## True when there is nothing to draw.
func is_empty() -> bool:
	return triangle_count == 0
