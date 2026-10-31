class_name MofStatic
extends Resource
## A static model: parts made of polygons, with no skeleton.
##
## Layout (FrogLord's [code]MRStaticMof[/code]); pointers count from the
## first byte of the signature:
## [codeblock]
## 0x02 "FOM"   u32 length of the model   u32 flags   u32 part count
## part headers, 44 bytes each (see MofPart)
## u32 (purpose unknown)
## the vector pool: vertices and normals of every part, 8 bytes each
##     (s16 x, s16 y, s16 z, s16 unused)
## per part: partcels, bounding boxes, hilites, collision primitives,
##     matrices, texture animation, flipbook, polygons
## [/codeblock]
## Such a model is a file of its own (".XMR") or one of the models inside an
## animated file ([MofAnimated]). "Static" only means it has no skeleton: it
## can still hold flipbook animation (several poses per part) and animated
## textures.
##
## An [b]incomplete[/b] model saves memory: it stores its header and its
## polygons and takes everything else from another model with the same
## shape. The gold frogs of the five checkpoints are one model and four
## incomplete ones in other colours. It is recognised by the first part's
## partcel pointer being 0x40.

## Flag: the model has animated textures.
const FLAG_ANIMATED_TEXTURES: int = 1 << 4
## Flag: the model has flipbook animation.
const FLAG_FLIPBOOK: int = 1 << 5
## Size of the header, up to and including the part count.
const HEADER_SIZE: int = 16
## Where the test for an incomplete model looks.
const INCOMPLETE_TEST_OFFSET: int = 0x1C
## The value found there in an incomplete model.
const INCOMPLETE_TEST_VALUE: int = 0x40

## Length the model states for itself.
@export var length: int = 0
## Flags as stored.
@export var flags: int = 0
## True when the model borrows its shape from another.
@export var is_incomplete: bool = false
## The word after the part headers, whose purpose is unknown.
@export var unknown_word: int = 0
## The parts.
@export var parts: Array[MofPart] = []
## Why parsing failed, or "".
@export var error: String = ""


## True when the model parsed cleanly.
func is_valid() -> bool:
	return error.is_empty()


## Polygons of all parts.
func polygon_count() -> int:
	var total: int = 0
	for part: MofPart in parts:
		total += part.polygons.size()
	return total


## Flipbook animations of all parts.
func flipbook_action_count() -> int:
	var total: int = 0
	for part: MofPart in parts:
		total += part.flipbook_action_count
	return total


## Polygons with animated textures, over all parts.
func texture_animation_target_count() -> int:
	var total: int = 0
	for part: MofPart in parts:
		total += part.texture_animation_target_count
	return total


## The texture ids the polygons use, each once, in rising order.
func image_ids() -> PackedInt32Array:
	var seen: Dictionary[int, bool] = {}
	for part: MofPart in parts:
		for polygon: MofPolygon in part.polygons:
			if polygon.is_textured():
				seen[polygon.image_id] = true
	var ids := PackedInt32Array(seen.keys())
	ids.sort()
	return ids
