class_name MofCollprim
extends Resource
## A simple collision shape of a model part.

## 0 cuboid, 1 cylinder along x, 2 along y, 3 along z, 4 sphere.
@export var type: int = 0
## Flags as stored.
@export var flags: int = 0
## x, y, z of the centre, relative to the part.
@export var offset := Vector3i.ZERO
## Radius squared of a cylinder or sphere.
@export var radius_squared: int = 0
## Size along x, y and z.
@export var size := Vector3i.ZERO
## A value for the game's own use.
@export var user: int = 0
## Which of the part's matrices applies, or -1.
@export var matrix_index: int = -1
