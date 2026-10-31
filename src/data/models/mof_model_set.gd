class_name MofModelSet
extends Resource
## A group of XAR models sharing one ordered list of authored actions.

## Flags as stored.
@export var flags: int = 0
## The models of the set.
@export var models: Array[MofModelInfo] = []
## The actions every model of the set shares.
@export var actions: Array[MofAction] = []
