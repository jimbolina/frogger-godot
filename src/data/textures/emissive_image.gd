class_name EmissiveImage
extends Resource
## One texture image that glows: map surfaces drawing it add the texel times
## [member colour] and [member strength] as emission, and may light their
## surroundings.

## The image's name in FrogLord's image name list, e.g. [code]vol_lava6[/code].
@export var image_name: String = ""
## Tint the texel is multiplied by before it is emitted, in stored (sRGB) colour.
@export var colour: Color = Color.WHITE
## Emission multiplier at the default lava emission setting; above about 1
## the bright texels exceed the bloom threshold.
@export var strength: float = 1.0
## True when surfaces drawing the image should also cast light on their
## surroundings.
@export var light: bool = false
## Relative energy of that light.
@export var light_energy: float = 0.0
