class_name ModelPose
extends RefCounted
## A sampled model pose, independent of scenes, meshes and materials.
## Each sample owns its arrays so callers can keep or edit it safely.

## One local transform for each part, identity for static and flipbook parts.
var transforms: Array[Transform3D] = []
## The selected partcel for each part.
var partcels := PackedInt32Array()
## Per part, an entry index for each texture target; -1 disables that target.
var texture_entries: Array[PackedInt32Array] = []
## Whether the pose should be drawn.
var visible: bool = true
