class_name MofHilite
extends Resource
## A marked point of a model part, such as where a splash or a particle appears.

## What the point is for (the game's own numbering).
@export var type: int = 0
## [constant MofPart.ATTACH_VERTEX] or [constant MofPart.ATTACH_POLYGON].
@export var attach: int = 0
## The vertex or polygon it is attached to.
@export var index: int = 0
