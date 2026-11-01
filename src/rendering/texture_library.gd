class_name TextureLibrary
extends RefCounted
## Looks textures up by global texture id across a set of loaded texture banks.
##
## The game has one global texture numbering. Loading a bank (VLO) fills in
## the texture record of every image's id, so an id means "the image with
## that id in the most recently loaded bank that has it"; this library works
## the same way ([method add_bank] later overrides earlier). A caller that
## knows which bank it wants (a map knows its theme's bank) can ask that bank
## first, as FrogLord does.
##
## Maps and models number their textures locally; a [TextureRemap] turns a
## local number into a global id ([method image_for_local]). Tables that point
## at texture records directly go through [BmpPointers] ([method image_for_pointer]).
## Each image brings its own [member VloImage.texture]; a [member catalog]
## that chose another [TextureSet] answers [method texture_for] with that
## set's counterpart instead.

## The catalog whose texture set the textures come from, or null for the
## records' own textures.
var catalog: AssetCatalog
var _banks: Array[VloFile] = []
var _bank_names: PackedStringArray = PackedStringArray()
var _by_texture_id: Dictionary[int, VloImage] = {}


## Adds [param bank] (called [param bank_name], e.g. "SUB_VRAM.VLO"); its
## images replace any earlier ones with the same texture ids.
func add_bank(bank: VloFile, bank_name: String = "") -> void:
	_banks.append(bank)
	_bank_names.append(bank_name)
	for image: VloImage in bank.images:
		_by_texture_id[image.texture_id] = image


## Number of banks added.
func bank_count() -> int:
	return _banks.size()


## Bank in upload order, or null outside the loaded list.
func bank_at(index: int) -> VloFile:
	return _banks[index] if index >= 0 and index < _banks.size() else null


## The bank added under [param bank_name], or null.
func find_bank(bank_name: String) -> VloFile:
	var at: int = _bank_names.find(bank_name)
	return _banks[at] if at >= 0 else null


## Number of distinct texture ids available.
func texture_id_count() -> int:
	return _by_texture_id.size()


## The image for global [param texture_id]: from [param preferred] when it has
## one, else from the most recently added bank that does; null if none.
func image_for_id(texture_id: int, preferred: VloFile = null) -> VloImage:
	if preferred != null:
		var own: VloImage = preferred.find_texture(texture_id)
		if own != null:
			return own
	return _by_texture_id[texture_id] if _by_texture_id.has(texture_id) else null


## The image for local texture [param local_index] of a file using [param remap].
func image_for_local(remap: TextureRemap, local_index: int, preferred: VloFile = null) -> VloImage:
	var texture_id: int = remap.global_id(local_index)
	return image_for_id(texture_id, preferred) if texture_id >= 0 else null


## The image whose texture record is at [param pointer] in [param pointers].
func image_for_pointer(pointers: BmpPointers, pointer: int, preferred: VloFile = null) -> VloImage:
	var texture_id: int = pointers.texture_id_for_pointer(pointer)
	return image_for_id(texture_id, preferred) if texture_id >= 0 else null


## The Godot texture of [param image] in the catalog's texture set (its
## [member VloImage.texture] without a catalog), or null.
func texture_for(image: VloImage) -> Texture2D:
	if image == null:
		return null
	return catalog.texture_of(image) if catalog != null else image.texture


## The texture set the textures come from.
func texture_set() -> TextureSet:
	return catalog.texture_set() if catalog != null else TextureSet.retail()


## True when the texture set samples with linear filtering and mipmaps in 3D.
func linear_filter() -> bool:
	return texture_set().linear_filter()


## The Godot texture for global [param texture_id], or null.
func texture_for_id(texture_id: int, preferred: VloFile = null) -> Texture2D:
	return texture_for(image_for_id(texture_id, preferred))
