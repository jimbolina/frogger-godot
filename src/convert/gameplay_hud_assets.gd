class_name GameplayHudAssets
extends RefCounted
## Runtime single-player HUD textures resolved by FrogLord names from the catalog's texture banks.
##
## Textures come from the catalog's [TextureSet] and may be larger than their records; each
## keeps its record, so draws crop and size by retail pixels ([method retail_size]).

const PHRASES: PackedStringArray = ["hop_to_it", "go_frogger", "go", "go_get_em", "jump_to_it", "croak"]
var error: String = ""
## Texture by FrogLord name.
var textures: Dictionary[String, Texture2D] = {}
## Texture record by FrogLord name.
var images: Dictionary[String, VloImage] = {}

## Loads the HUD banks from [param data].
static func from_data(data: AssetCatalog) -> GameplayHudAssets:
	var result := GameplayHudAssets.new()
	if data == null or not data.is_valid() or data.names.images == null:
		result.error = "HUD requires valid player data and named images"
		return result
	var library := TextureLibrary.new()
	library.catalog = data
	var problems := PackedStringArray()
	for name: String in ["LS_ALL.VLO", "FIXE_VRAM.VLO", "GEN_VRAM.VLO"]:
		var entry: MwiEntry = data.find_resource(name)
		if entry == null:
			result.error = "HUD bank is missing: " + name
			return result
		var bank: VloFile = data.read_texture_bank(entry.index, problems)
		if bank == null or not problems.is_empty():
			result.error = "HUD bank %s: %s" % [name, "; ".join(problems)]
			return result
		library.add_bank(bank, name)
	var required := PackedStringArray(["newfont", "bonus", "opt_sec"])
	required.append_array(PHRASES)
	for digit: int in 10:
		required.append("32x32_%d" % digit)
		required.append("med_%d" % digit)
	for frame: int in 7:
		for checkpoint: int in 5:
			required.append("babyfrog%d_%d" % [checkpoint + 1, frame])
		required.append("babyfroggold_%d" % frame)
	for frame: int in 5:
		required.append("lifes%d" % (frame + 1))
		required.append("lives_bg%d" % (frame + 1))
	for name: String in required:
		var identity: int = data.names.images.index_of(name)
		var texture: Texture2D = library.texture_for_id(identity)
		if texture == null:
			result.error = "HUD image %s (texture %d) is missing from the supplied banks" % [name, identity]
			return result
		result.textures[name] = texture
		result.images[name] = library.image_for_id(identity)
	return result


## The size the texture called [param name] is drawn at on the 640x480 canvas (its record's
## padded size), or zero when it is not loaded.
func retail_size(name: String) -> Vector2:
	var image: VloImage = images.get(name, null)
	var texture: Texture2D = textures.get(name, null)
	return TextureBuilder.retail_size(image, texture) if image != null else Vector2.ZERO


## Pixels of the texture called [param name] per retail pixel, [constant Vector2.ONE] when it is
## not loaded.
func texture_scale(name: String) -> Vector2:
	var image: VloImage = images.get(name, null)
	var texture: Texture2D = textures.get(name, null)
	return TextureBuilder.texture_scale(image, texture) if image != null else Vector2.ONE
