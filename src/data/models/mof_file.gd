class_name MofFile
extends Resource
## A model file ("MOF"): a placeholder, a static model or an animated model.
##
## Every model lives inside a WAD. What a file is shows in its first bytes,
## never in its name (FrogLord's [code]MRModel[/code]):
## [br]- the four bytes [code]DUMY[/code] and nothing else: a placeholder. A
##   level's WAD has a slot for every model of its theme, and the ones the
##   level does not use are placeholders;
## [br]- bit 3 of the flags at byte 8 set: an animated model ([MofAnimated]),
##   which holds one or more static models;
## [br]- otherwise a static model ([MofStatic]).
##
## Whatever the kind, the shapes end up in [member static_models], so code
## that only draws a model does not care which it was.

## What a model file holds.
enum Kind {
	## Not a model.
	UNKNOWN,
	## A placeholder.
	DUMMY,
	## One static model.
	STATIC,
	## An animated model holding static models.
	ANIMATED,
}

## Names of [enum Kind], as the golden facts write them.
const KIND_NAMES: Array[String] = ["unknown", "dummy", "static", "animated"]
## The contents of a placeholder.
const DUMMY_SIGNATURE: String = "DUMY"

## What the file holds.
@export var kind: Kind = Kind.UNKNOWN
## The first four bytes, as hexadecimal.
@export var signature: String = ""
## Size of the file.
@export var size: int = 0
## Flags as stored (0 for a placeholder).
@export var flags: int = 0
## True when a static model in the file borrows its shape from another file.
@export var is_incomplete: bool = false
## The outside of an animated model, or null.
@export var animated: MofAnimated
## The static models: one for a static file, those inside an animated file,
## none for a placeholder.
@export var static_models: Array[MofStatic] = []
## Why parsing failed, or "".
@export var error: String = ""


## True when the file parsed cleanly.
func is_valid() -> bool:
	return error.is_empty()


## Name of the kind, e.g. "static".
func kind_name() -> String:
	return KIND_NAMES[kind]


## Parts of all static models.
func part_count() -> int:
	var total: int = 0
	for model: MofStatic in static_models:
		total += model.parts.size()
	return total


## Polygons of all static models.
func polygon_count() -> int:
	var total: int = 0
	for model: MofStatic in static_models:
		total += model.polygon_count()
	return total


## The texture ids the polygons use, each once, in rising order.
func image_ids() -> PackedInt32Array:
	var seen: Dictionary[int, bool] = {}
	for model: MofStatic in static_models:
		for id: int in model.image_ids():
			seen[id] = true
	var ids := PackedInt32Array(seen.keys())
	ids.sort()
	return ids
