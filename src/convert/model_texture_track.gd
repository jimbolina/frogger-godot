class_name ModelTextureTrack
extends Resource
## One animated polygon's materials, precomputed so playback allocates no resources.

## Surface of the polygon in its part mesh.
@export var surface: int = 0
## Texture-animation target index in its part.
@export var target: int = 0
## The polygon's original image, used when animation is disabled.
@export var original: ShaderMaterial
## A material for every entry of the texture list, including missing-image fallbacks.
@export var frames: Array[ShaderMaterial] = []
