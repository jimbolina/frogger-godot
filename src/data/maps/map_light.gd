class_name MapLight
extends Resource
## Stored light fields; inactive fields may contain allocator garbage.

## Stored source offset.
@export var source_offset: int = 0
## Stored category.
@export var category: int = 0
## Stored light type.
@export var light_type: int = 0
## Stored priority.
@export var priority: int = 0
## Stored parent id.
@export var parent_id: int = 0
## Stored color.
@export var color: Color = Color.BLACK
## Stored color word.
@export var color_word: int = 0
## Stored position.
@export var position: Vector3i = Vector3i.ZERO
## Stored direction.
@export var direction: Vector3i = Vector3i.ZERO
## Stored attribute 0.
@export var attribute_0: int = 0
## Stored attribute 1.
@export var attribute_1: int = 0
## Stored enabled.
@export var enabled: bool = false
