class_name MofPolygonType
extends RefCounted
## The sixteen kinds of polygon a model can hold, and what each one stores.
##
## The numbers are the ones written in a model file (FrogLord's
## [code]MRMofPolygonType[/code], the original's [code]MR_MPRIMID[/code]).
## "F" is flat (one normal), "G" is gouraud (a normal per corner), "T" is
## textured, "E" is environment mapped. Retail PC data only holds the first
## eight; the rest are read so that an edited file still loads.

## Flat triangle.
const F3: int = 0
## Flat quad.
const F4: int = 1
## Flat textured triangle.
const FT3: int = 2
## Flat textured quad.
const FT4: int = 3
## Gouraud triangle.
const G3: int = 4
## Gouraud quad.
const G4: int = 5
## Gouraud textured triangle.
const GT3: int = 6
## Gouraud textured quad.
const GT4: int = 7
## Number of kinds; a type number at or above this is an error.
const COUNT: int = 16

## Short name of each kind.
const NAMES: Array[String] = ["F3", "F4", "FT3", "FT4", "G3", "G4", "GT3", "GT4",
	"E3", "E4", "LF2", "LF3", "HLF3", "HLF4", "GE3", "GE4"]
## Corners of each kind.
const VERTICES: Array[int] = [3, 4, 3, 4, 3, 4, 3, 4, 3, 4, 2, 3, 3, 4, 3, 4]
## Environment normals of each kind.
const ENVIRONMENT_NORMALS: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 3, 4, 0, 0, 0, 0, 3, 4]
## Lighting normals of each kind.
const NORMALS: Array[int] = [1, 1, 1, 1, 3, 4, 3, 4, 1, 1, 0, 0, 0, 0, 3, 4]


## True if [param polygon_type] is a known kind.
static func is_valid(polygon_type: int) -> bool:
	return polygon_type >= 0 and polygon_type < COUNT


## Short name such as "GT4", or "" for an unknown kind.
static func type_name(polygon_type: int) -> String:
	return NAMES[polygon_type] if is_valid(polygon_type) else ""


## Number of corners.
static func vertex_count(polygon_type: int) -> int:
	return VERTICES[polygon_type] if is_valid(polygon_type) else 0


## Number of environment normals.
static func environment_normal_count(polygon_type: int) -> int:
	return ENVIRONMENT_NORMALS[polygon_type] if is_valid(polygon_type) else 0


## Number of lighting normals.
static func normal_count(polygon_type: int) -> int:
	return NORMALS[polygon_type] if is_valid(polygon_type) else 0


## True if polygons of this kind carry a texture.
static func is_textured(polygon_type: int) -> bool:
	return polygon_type == FT3 or polygon_type == FT4 or polygon_type == GT3 or polygon_type == GT4
