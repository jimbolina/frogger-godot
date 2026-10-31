class_name GameplayHudAssets
extends RefCounted
## Runtime single-player HUD textures resolved by FrogLord names from the player's archive.

const PHRASES: PackedStringArray = ["hop_to_it", "go_frogger", "go", "go_get_em", "jump_to_it", "croak"]
var error: String = ""
var textures: Dictionary[String, Texture2D] = {}

## Loads the HUD banks from either catalog without retaining the archive or copying retail
## pixels to disk.
static func from_data(data: AssetCatalog) -> GameplayHudAssets:
	var result := GameplayHudAssets.new()
	if data == null or not data.is_valid() or data.names.images == null:
		result.error = "HUD requires valid player data and named images"
		return result
	var library := TextureLibrary.new()
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
	return result
