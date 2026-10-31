class_name MofModelInfo
extends Resource
## Animation metadata for one static model embedded in an XAR file.

## Animation type as stored.
@export var animation_type: int = 0
## Index of the embedded static model it describes.
@export var static_model_index: int = 0
## Parts of that model.
@export var part_count: int = 0
## Flags as stored; bit 0 means it has a global bounding box.
@export var flags: int = 0
## x, y, z of the global bounding box's 8 corners, or empty.
@export var bounding_box := PackedInt32Array()
