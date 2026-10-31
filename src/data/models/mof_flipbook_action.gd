class_name MofFlipbookAction
extends Resource
## An authored consecutive range of partcels to show as a flipbook action.

## First partcel of the range.
@export var start: int = 0
## Number of consecutive authored frames.
@export var frame_count: int = 0
## An unavailable authored range is preserved with this diagnostic.
@export var error: String = ""
