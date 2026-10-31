class_name VloImage
extends Resource
## One texture in a PC texture bank ([VloFile]): its header and decoded pixels.
##
## Header (24 bytes, FrogLord's [code]VloImage[/code]):
## [codeblock]
## s16 VRAM x   s16 VRAM y   s16 padded width   s16 padded height
## s32 pixel data offset (from the start of the file)
## s16 texture id   u16 texture page word   u16 flags   s16 (unused on PC)
## u8 u   u8 v   u8 width   u8 height   (0 means 256)
## [/codeblock]
## The PC game packs textures into 256 x 256 "pages" stacked vertically, so a
## texture's page is [code]vram_y / 256[/code]. Each image is stored with a
## border of padding (the same on every side on PC) that repeats its edge
## pixels, so filtering at polygon edges never samples a neighbour; [member u]
## and [member v] are where the real ("in-game") image starts inside its page.
## The texture page word holds the page in its low byte and the blend mode used
## for translucent drawing in bits 8-9.
##
## Pixels are decoded to RGBA8 by [VloFileReader] (see [VloFile] for the exact rule).

## Bit 0: drawn translucent (blended with what is behind it).
const FLAG_TRANSLUCENT: int = 1 << 0
## Bit 2: FrogLord's "hit X" bit (the image touches the right edge of its page).
const FLAG_HIT_X: int = 1 << 2
## Bit 3: FrogLord's "hit Y" bit (the image touches the bottom of its page).
const FLAG_HIT_Y: int = 1 << 3
## Bit 4: the texture has a fixed record the game refers to by name ([BmpPointers]).
const FLAG_REFERENCED_BY_NAME: int = 1 << 4
## Bit 5: black pixels are transparent. In the PC game this applies to the
## whole texture page (it becomes a DirectDraw colour key), and the tools that
## built the banks set it on every texture of such a page.
const FLAG_BLACK_IS_TRANSPARENT: int = 1 << 5
## Bit 15: set on (nearly) every Frogger texture; marks it usable as a 2D sprite.
const FLAG_2D_SPRITE: int = 1 << 15
## Width and height of a texture page.
const PAGE_SIZE: int = 256

## Position in its bank.
@export var index: int = 0
## X position in the game's texture memory.
@export var vram_x: int = 0
## Y position in the game's texture memory (the page is vram_y / 256).
@export var vram_y: int = 0
## Stored width including padding.
@export var padded_width: int = 0
## Stored height including padding.
@export var padded_height: int = 0
## Offset of the pixel data in the file.
@export var data_offset: int = 0
## Global texture id (what remaps and texture pointers refer to).
@export var texture_id: int = 0
## The texture page word as stored.
@export var texture_page_word: int = 0
## Flag bits as stored (the FLAG_ constants).
@export var flags: int = 0
## Unused on PC; kept as read.
@export var clut_id: int = 0
## Horizontal start of the in-game image inside its page.
@export var u: int = 0
## Vertical start of the in-game image inside its page.
@export var v: int = 0
## In-game width (without padding).
@export var width: int = 0
## In-game height (without padding).
@export var height: int = 0
## Name given by FrogLord when a modder renamed the texture, or "".
@export var custom_name: String = ""
## Decoded pixels of the whole stored image, RGBA8, padded_width x padded_height.
@export var pixels: PackedByteArray = PackedByteArray()
## The imported texture for this image, or null until an importer supplies one.
@export var texture: Texture2D


## The texture page (0-13 in the PC game).
func page() -> int:
	return vram_y / PAGE_SIZE


## The blend mode for translucent drawing (bits 8-9 of the page word):
## 0 = average, 1 = add, 2 = subtract, 3 = add a quarter.
func blend_mode() -> int:
	return (texture_page_word >> 8) & 3


## True if flag bit(s) [param flag] are set.
func has_flag(flag: int) -> bool:
	return flags & flag == flag


## Padding columns on the left of the in-game image.
func left_padding() -> int:
	return (padded_width - width) / 2


## Padding rows above the in-game image.
func top_padding() -> int:
	return (padded_height - height) / 2


## The in-game region without padding, RGBA8, width x height. This is what
## FrogLord's image export writes.
func unpadded_pixels() -> PackedByteArray:
	if width == padded_width and height == padded_height:
		return pixels
	var out := PackedByteArray()
	var left: int = left_padding()
	for y: int in range(top_padding(), top_padding() + height):
		var start: int = (y * padded_width + left) * 4
		out.append_array(pixels.slice(start, start + width * 4))
	return out
