class_name TexturePageSet
extends Resource
## The fourteen PC texture pages a map samples, baked once from the two
## texture banks it loads, plus the sky-land atlas for a sky set.
##
## A retail set's pages are 256 x 256; an upscaled set stores the same layout
## at [method scale] times that size on each axis, sky atlas included.
##
## A set is named after its banks: the GENERAL theme's bank, then the map's
## theme bank, without extensions and joined by [code]+[/code] (for example
## [code]GEN_VRAM+CAV_VRAM_WIN95[/code]). The importer composes each page:
## black, every valid upload copied in bank
## upload order, then the page-wide colour key when a texture whose own page
## it is has [constant VloImage.FLAG_BLACK_IS_TRANSPARENT].

## Number of pages in a set.
const PAGE_COUNT: int = 14
## Width and height of a retail page in retail pixels.
const PAGE_SIZE: int = 256
## Height in retail pixels of one page slot in the sky atlas: the page plus a
## repeated row above and below.
const SKY_SLOT_HEIGHT: int = 258

## The set's name, the bank names joined by [code]+[/code].
@export var set_name: String = ""
## The bank names (MWI display names without extension) in upload order.
@export var bank_names: PackedStringArray = PackedStringArray()
## The pages 0-13; a page is null only when it could not be baked.
@export var pages: Array[Texture2D] = []
## Per page, true when the colour key applies (exact RGB 0,0,0 is transparent).
@export var colour_keyed: Array[bool] = []
## The sky-land atlas, or null for a set no sky level uses.
@export var sky_atlas: Texture2D
## The page in each atlas slot, in first-seen tile order; -1 for a missing image.
@export var sky_pages: PackedInt32Array = PackedInt32Array()


## The texture of page [param page_index], or null outside 0-13.
func page(page_index: int) -> Texture2D:
	if page_index < 0 or page_index >= pages.size():
		return null
	return pages[page_index]


## Stored pixels per retail pixel: the width of the first page present over
## [constant PAGE_SIZE], and 1 for a set without pages.
func scale() -> int:
	for texture: Texture2D in pages:
		if texture != null:
			@warning_ignore("integer_division")
			return maxi(1, texture.get_width() / PAGE_SIZE)
	return 1


## Stored rows of one sky atlas slot: [constant SKY_SLOT_HEIGHT] at the set's [method scale].
func sky_slot_height() -> int:
	return SKY_SLOT_HEIGHT * scale()


## The atlas slot holding page [param page_index], or -1 when the atlas has none.
func sky_slot(page_index: int) -> int:
	return sky_pages.find(page_index)


## The set name for banks [param bank_names] given as display names or bare names.
static func name_for(names: PackedStringArray) -> String:
	var bare := PackedStringArray()
	for bank_name: String in names:
		bare.append(bank_name.get_basename() if bank_name.to_upper().ends_with(".VLO") else bank_name)
	return "+".join(bare)
