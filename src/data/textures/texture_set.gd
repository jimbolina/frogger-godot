class_name TextureSet
extends RefCounted
## Which image the game draws for each retail texture: the base root's own
## image, or the image a [TexturePack] supplies in its place.
##
## Records and materials keep pointing at the retail files under
## [code]textures/images/[/code]. A set with a pack maps a texture id to the
## pack's file through [member sources]; each file may be any whole multiple
## from 1 to [constant MAX_SCALE] of the retail padded size, so the scale is
## per texture and is recorded in [member scales] once the image is accepted.
## A texture the pack does not supply, or whose image is rejected, draws the
## retail image. A texture drawn at a scale above 1 samples with linear
## filtering and mipmaps, and 2D draws scale it back to retail pixels.
##
## The lettering under [code]lettering/[/code] of the shippable root (a
## transparent image, [method lettering_path], or a tile composited from its
## mask, [method lettering_mask_path]) replaces the retail image it stands for
## unless the pack supplies that texture itself: the pack wins over the
## lettering, and the lettering over the retail image.

## The retail images folder under [code]textures/[/code].
const IMAGES_DIR: String = "images"
## The lettering folder under the shippable root.
const LETTERING_DIR: String = "lettering"
## The folder of the tile masks under [constant LETTERING_DIR], one
## sub-folder per tile background.
const MASKS_DIR: String = "masks"
## The largest scale a pack image may have over its retail padded size.
const MAX_SCALE: int = 16
## Vector fonts by name, with their paths under the shippable root.
const VECTOR_FONTS: Dictionary[String, String] = {
	"angular": "fonts/angular/frogger_angular.ttf",
}

## The pack whose images replace the retail ones, or null for the original textures.
var pack: TexturePack
## The pack's image file for each texture id it supplies.
var sources: Dictionary[int, String] = {}
## The scale of each pack image accepted so far, by texture id.
var scales: Dictionary[int, int] = {}


## The original textures, with no pack.
static func retail() -> TextureSet:
	return TextureSet.new()


## The set drawing [param texture_pack]'s images given in [param pack_sources]
## (texture id to file path) in place of the retail ones.
static func of_pack(texture_pack: TexturePack, pack_sources: Dictionary[int, String]) -> TextureSet:
	var made := TextureSet.new()
	made.pack = texture_pack
	made.sources = pack_sources.duplicate()
	return made


## True when no pack replaces any texture.
func is_retail() -> bool:
	return pack == null


## The pack's folder name, or "" for the original textures.
func pack_name() -> String:
	return pack.pack_name if pack != null else ""


## A key telling sets apart for caches: "" for the original textures,
## otherwise the pack's folder.
func key() -> String:
	return pack.folder if pack != null else ""


## True when the pack supplies an image for [param texture_id].
func has_source(texture_id: int) -> bool:
	return sources.has(texture_id)


## The pack's image file for [param texture_id], or "".
func source_of(texture_id: int) -> String:
	return sources.get(texture_id, "")


## The scale of the image drawn for [param texture_id] once accepted: the
## pack image's, or 1 for a retail image or one not loaded yet.
func scale_of(texture_id: int) -> int:
	return scales.get(texture_id, 1)


## Records that the pack image for [param texture_id] was accepted at [param scale].
func accept(texture_id: int, scale: int) -> void:
	scales[texture_id] = scale


## Drops the pack image for [param texture_id], so the texture draws its retail image.
func reject(texture_id: int) -> void:
	sources.erase(texture_id)
	scales.erase(texture_id)


## The scale of an image of [param image_size] over the padded size
## [param padded_size]: the same whole multiple from 1 to [constant MAX_SCALE]
## on both axes, or 0 when it is not one.
static func scale_for(image_size: Vector2i, padded_size: Vector2i) -> int:
	if padded_size.x <= 0 or padded_size.y <= 0 or image_size.x % padded_size.x != 0 or image_size.y % padded_size.y != 0:
		return 0
	@warning_ignore("integer_division")
	var scale: int = image_size.x / padded_size.x
	@warning_ignore("integer_division")
	var scale_y: int = image_size.y / padded_size.y
	if scale < 1 or scale > MAX_SCALE or scale_y != scale:
		return 0
	return scale


## The texture id of a retail image path such as [code].../textures/images/t0310.png[/code]
## (any extension), or -1 for a path outside the retail images folder.
static func texture_id_of(retail_path: String) -> int:
	if not retail_path.contains("/textures/%s/" % IMAGES_DIR):
		return -1
	return texture_id_of_file(retail_path.get_file())


## The texture id a file called [code]tNNNN[/code] with any extension stands
## for, or -1 for any other name.
static func texture_id_of_file(file_name: String) -> int:
	var stem: String = file_name.get_basename().to_lower()
	if stem.length() != 5 or not stem.begins_with("t"):
		return -1
	for digit: String in stem.substr(1):
		if not digit in "0123456789":
			return -1
	return stem.substr(1).to_int()


## The path under the shippable root of the lettering image that replaces
## the retail image at [param retail_path], or "" for a path outside the
## retail images folder. Lettering images are always [code].png[/code],
## whatever the retail image's extension.
static func lettering_path(retail_path: String) -> String:
	if not retail_path.contains("/textures/%s/" % IMAGES_DIR):
		return ""
	return "%s/%s.png" % [LETTERING_DIR, retail_path.get_file().get_basename()]


## The path under the shippable root of the mask of the lettering tile on
## [param background] that replaces the retail image at [param retail_path],
## or "" for a path outside the retail images folder.
static func lettering_mask_path(retail_path: String, background: String) -> String:
	if not retail_path.contains("/textures/%s/" % IMAGES_DIR):
		return ""
	return "%s/%s/%s/%s.png" % [LETTERING_DIR, MASKS_DIR, background, retail_path.get_file().get_basename()]


## True when [param path] is a lettering image under a shippable root.
static func is_lettering_path(path: String) -> bool:
	return path.contains("/%s/" % LETTERING_DIR)


## The path under the shippable root of the vector font called [param name]
## (one of the [constant VECTOR_FONTS]), or "" for any other name.
static func font_path(name: String) -> String:
	return VECTOR_FONTS.get(name, "")
