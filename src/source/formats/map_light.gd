class_name MapLight
extends RefCounted
## Stored light fields; inactive fields may contain allocator garbage.

## Stored source offset.
var source_offset: int = 0
## Stored category.
var category: int = 0
## Stored light type.
var light_type: int = 0
## Stored priority.
var priority: int = 0
## Stored parent id.
var parent_id: int = 0
## Stored color.
var color: Color = Color.BLACK
## Stored color word.
var color_word: int = 0
## Stored position.
var position: Vector3i = Vector3i.ZERO
## Stored direction.
var direction: Vector3i = Vector3i.ZERO
## Stored attribute 0.
var attribute_0: int = 0
## Stored attribute 1.
var attribute_1: int = 0
## Stored enabled.
var enabled: bool = false
