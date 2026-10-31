class_name MofPart
extends Resource
## One part of a model: a group of polygons that moves as one piece.
##
## Header, 44 bytes (FrogLord's [code]MRMofPart[/code], the original's
## [code]MR_PART[/code]). Pointers count from the start of the model:
## [codeblock]
## u16 flags (bit 0: has texture animation)   u16 partcels
## u16 vertices per partcel   u16 normals per partcel
## u16 polygons   u16 hilites
## u32 partcels at   u32 polygons at   u32 hilites at (0 = none)
## u32 zero (filled in by the game)
## u32 collision primitives at   u32 matrices at
## u32 texture animation at   u32 flipbook at        (0 = none)
## [/codeblock]
## A partcel is one pose of the part: a set of vertices and normals and a
## bounding box. Partcel 0 is the pose the part rests in; the others are the
## frames of flipbook animations. The vertices and normals of every part sit
## in one pool near the start of the model.
##
## Polygons come in blocks of one kind each ([code]u16 kind, u16 count[/code]
## then the polygons), repeated until the header's polygon count is reached.
##
## A part of an incomplete model holds only its header and polygons; the
## rest is borrowed from the same part of another model (see [MofStatic]).

## Part flag: some polygons have animated textures.
const FLAG_ANIMATED_TEXTURES: int = 1 << 0
## Size of the header.
const HEADER_SIZE: int = 44
## Collision primitive flag: last one of the list.
const COLLPRIM_LAST: int = 1 << 1
## Hilite attached to a vertex of partcel 0.
const ATTACH_VERTEX: int = 1
## Hilite attached to a polygon.
const ATTACH_POLYGON: int = 2
## Former inner class, now [MofFlipbookAction].
const FlipbookAction := preload("res://src/data/models/mof_flipbook_action.gd")
## Former inner class, now [MofTextureTarget].
const TextureTarget := preload("res://src/data/models/mof_texture_target.gd")
## Former inner class, now [MofTextureAnimation].
const TextureAnimation := preload("res://src/data/models/mof_texture_animation.gd")
## Former inner class, now [MofPartcel].
const Partcel := preload("res://src/data/models/mof_partcel.gd")
## Former inner class, now [MofHilite].
const Hilite := preload("res://src/data/models/mof_hilite.gd")
## Former inner class, now [MofCollprim].
const Collprim := preload("res://src/data/models/mof_collprim.gd")

## Position of the part in its model.
@export var index: int = 0
## Flags as stored.
@export var flags: int = 0
## Number of partcels the header states.
@export var partcel_count: int = 0
## Vertices per partcel the header states.
@export var vertex_count: int = 0
## Normals per partcel the header states.
@export var normal_count: int = 0
## Polygons the header states.
@export var polygon_count: int = 0
## Hilites the header states.
@export var hilite_count: int = 0
## True when everything but the polygons comes from another model's part.
@export var borrows: bool = false
## The poses. Borrowed when [member borrows] is set.
@export var partcels: Array[MofPartcel] = []
## How many different bounding boxes the partcels use.
@export var bounding_box_count: int = 0
## The marked points. Borrowed when [member borrows] is set.
@export var hilites: Array[MofHilite] = []
## The collision shapes. Borrowed when [member borrows] is set.
@export var collprims: Array[MofCollprim] = []
## Number of matrices stored for the collision shapes.
@export var matrix_count: int = 0
## Each stored 32-byte MR_MAT as 12 values: nine signed16 row-major rotation
## entries, then three signed32 translations; the pad short is dropped.
## Borrowed when [member borrows] is set.
@export var matrices: Array[PackedInt32Array] = []
## Number of flipbook animations.
@export var flipbook_action_count: int = 0
## Number of polygons with an animated texture.
@export var texture_animation_target_count: int = 0
## Number of texture animations.
@export var texture_animation_count: int = 0
## Texture ids the texture animations show, in stored order.
@export var texture_animation_image_ids := PackedInt32Array()
## Flipbook actions in effect, inherited for incomplete parts.
@export var flipbook_actions: Array[MofFlipbookAction] = []
## Texture animation targets in effect, inherited for incomplete parts.
@export var texture_targets: Array[MofTextureTarget] = []
## Texture animation lists in effect, inherited for incomplete parts.
@export var texture_lists: Array[MofTextureAnimation] = []
## The polygons, in stored order.
@export var polygons: Array[MofPolygon] = []
## Where the part's polygon data ends, from the start of the model.
@export var end_offset: int = 0


## The pose the part rests in, or null.
func static_partcel() -> MofPartcel:
	return partcels[0] if not partcels.is_empty() else null


## Takes the poses, hilites and collision shapes of [param other], as the
## game does for an incomplete model. The counts read from this part's own
## file stay as they were.
func borrow_from(other: MofPart) -> void:
	borrows = true
	partcels = other.partcels
	hilites = other.hilites
	collprims = other.collprims
	matrices = other.matrices
	flipbook_actions = other.flipbook_actions
	texture_lists = other.texture_lists
	texture_targets = []
	for original: MofTextureTarget in other.texture_targets:
		var target := MofTextureTarget.new()
		target.polygon_type = original.polygon_type
		target.polygon_index = original.polygon_index
		target.list_index = original.list_index
		target.error = original.error
		if target.polygon_index < 0 or target.polygon_index >= polygons.size():
			target.error = "borrowed texture target names unavailable polygon"
		elif polygons[target.polygon_index].type != target.polygon_type:
			target.error = "borrowed texture target names an incompatible polygon"
		texture_targets.append(target)


## Number of polygons of each kind, in the order of [MofPolygonType].
func polygons_by_type() -> PackedInt32Array:
	var counts := PackedInt32Array()
	counts.resize(MofPolygonType.COUNT)
	for polygon: MofPolygon in polygons:
		counts[polygon.type] += 1
	return counts
