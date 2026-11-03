class_name TexturePackReader
extends RefCounted
## Finds the installed texture packs and loads their images at runtime.
##
## A pack is a folder under one of the [method search_folders], named for the
## pack, holding [constant CONFIG_FILE] and PNG images named by texture id
## ([code]t0310.png[/code]) or by FrogLord image name ([code]hi_a.png[/code]).
## [constant CONFIG_FILE] is a [ConfigFile] with one [code][pack][/code]
## section: [code]name[/code] and [code]base_build[/code] are required,
## [code]author[/code], [code]version[/code] and [code]description[/code] are
## optional text, and [code]format_version[/code], when present, must be
## [constant FORMAT_VERSION]. A folder without the file, or with a malformed
## one, is not a pack and is reported.
##
## Images are read with [method Image.load_from_file], with no editor import,
## so a packaged build loads them as well. Each must be the same whole
## multiple from 1 to [constant TextureSet.MAX_SCALE] of its retail padded
## size on both axes; any other image is rejected with a line naming the
## sizes. A scaled image gets its transparent edges fixed and mipmaps, for
## linear sampling. A loaded texture is shared while anything holds it, so
## catalogs opened one after another load each image once.

## The packs folder under the player's user data.
const USER_FOLDER: String = "user://texture_packs"
## The packs folder beside an exported game's executable.
const BESIDE_EXECUTABLE: String = "texture_packs"
## The pack's settings file.
const CONFIG_FILE: String = "pack.cfg"
## The section of [constant CONFIG_FILE].
const SECTION: String = "pack"
## The pack format this reader understands.
const FORMAT_VERSION: int = 1
## The image file extension a pack's images use.
const IMAGE_EXTENSION: String = "png"
const _REQUIRED: PackedStringArray = ["name", "base_build"]
const _OPTIONAL: PackedStringArray = ["author", "version", "description"]

static var _loaded: Dictionary[String, WeakRef] = {}


## The folders packs are looked for in, first match first: [constant USER_FOLDER],
## then, in an exported game, [constant BESIDE_EXECUTABLE] beside the executable.
static func search_folders() -> PackedStringArray:
	var folders := PackedStringArray([USER_FOLDER])
	if OS.has_feature("template"):
		folders.append(OS.get_executable_path().get_base_dir().path_join(BESIDE_EXECUTABLE))
	return folders


## The packs installed in [param folders], sorted by [member TexturePack.pack_name];
## a pack name found again in a later folder is hidden by the first. Each
## folder that is not a pack, and each hidden pack, adds a line to [param problems_out].
static func list(folders: PackedStringArray = search_folders(),
		problems_out: PackedStringArray = PackedStringArray()) -> Array[TexturePack]:
	var found: Dictionary[String, TexturePack] = {}
	for parent: String in folders:
		if not DirAccess.dir_exists_absolute(parent):
			continue
		var names: PackedStringArray = DirAccess.get_directories_at(parent)
		names.sort()
		for name: String in names:
			if found.has(name):
				problems_out.append("texture pack %s in %s is hidden by the one in %s"
					% [name, parent, found[name].folder.get_base_dir()])
				continue
			var pack: TexturePack = read(parent.path_join(name), problems_out)
			if pack != null:
				found[name] = pack
	var keys: Array[String] = found.keys()
	keys.sort()
	var packs: Array[TexturePack] = []
	for key: String in keys:
		packs.append(found[key])
	return packs


## The pack called [param pack_name] in [param folders]: the first folder of
## that name, or else of that name ignoring case; null when there is none or
## it is not a pack, with the reason in [param problems_out].
static func find(pack_name: String, folders: PackedStringArray = search_folders(),
		problems_out: PackedStringArray = PackedStringArray()) -> TexturePack:
	if pack_name.is_empty():
		return null
	for exact: bool in [true, false]:
		for parent: String in folders:
			if not DirAccess.dir_exists_absolute(parent):
				continue
			for name: String in DirAccess.get_directories_at(parent):
				if name == pack_name or (not exact and name.to_lower() == pack_name.to_lower()):
					return read(parent.path_join(name), problems_out)
	return null


## The pack in [param folder], or null with a line in [param problems_out]
## when it has no [constant CONFIG_FILE] or the file is malformed.
static func read(folder: String, problems_out: PackedStringArray = PackedStringArray()) -> TexturePack:
	var config_path: String = folder.path_join(CONFIG_FILE)
	if not FileAccess.file_exists(config_path):
		problems_out.append("%s has no %s; it is not a texture pack" % [folder, CONFIG_FILE])
		return null
	var config := ConfigFile.new()
	var status: Error = config.load(config_path)
	if status != OK:
		problems_out.append("%s could not be read (%s); it is not a texture pack" % [config_path, error_string(status)])
		return null
	var problem: String = _config_problem(config)
	if not problem.is_empty():
		problems_out.append("%s %s; it is not a texture pack" % [config_path, problem])
		return null
	var pack := TexturePack.new()
	pack.pack_name = folder.get_file()
	pack.folder = folder
	pack.title = config.get_value(SECTION, "name")
	pack.base_build = config.get_value(SECTION, "base_build")
	pack.author = config.get_value(SECTION, "author", "")
	pack.version = config.get_value(SECTION, "version", "")
	pack.description = config.get_value(SECTION, "description", "")
	var files := PackedStringArray()
	for file: String in DirAccess.get_files_at(folder):
		if file.get_extension().to_lower() == IMAGE_EXTENSION:
			files.append(file)
	files.sort()
	pack.files = files
	return pack


## The image file of [param pack] for each texture id it replaces. A file
## named [code]tNNNN[/code] names texture NNNN; any other name is looked up,
## ignoring case, in [param image_names] (FrogLord's image names, or null for
## none). A file naming no texture, and a second file for the same texture
## (a [code]tNNNN[/code] name wins over a FrogLord name, otherwise the first
## in sorted order), adds a line to [param problems_out].
static func sources(pack: TexturePack, image_names: NameBank,
		problems_out: PackedStringArray = PackedStringArray()) -> Dictionary[int, String]:
	var by_name: Dictionary[String, int] = _ids_by_name(image_names)
	var found: Dictionary[int, String] = {}
	var by_id: Dictionary[int, bool] = {}
	for file: String in pack.files:
		var texture_id: int = TextureSet.texture_id_of_file(file)
		var numbered: bool = texture_id >= 0
		if not numbered:
			texture_id = by_name.get(file.get_basename().to_lower(), -1)
		if texture_id < 0:
			problems_out.append("texture pack %s: %s names no texture; it is not drawn" % [pack.pack_name, file])
			continue
		if found.has(texture_id):
			var kept: String = found[texture_id].get_file()
			if numbered and not by_id[texture_id]:
				problems_out.append("texture pack %s: %s and %s both replace texture %d; drawing %s"
					% [pack.pack_name, kept, file, texture_id, file])
				found[texture_id] = pack.path_of(file)
				by_id[texture_id] = true
			else:
				problems_out.append("texture pack %s: %s and %s both replace texture %d; drawing %s"
					% [pack.pack_name, kept, file, texture_id, kept])
			continue
		found[texture_id] = pack.path_of(file)
		by_id[texture_id] = numbered
	return found


## The image at [param path] as RGBA8 when it is a whole multiple from 1 to
## [constant TextureSet.MAX_SCALE] of [param padded_size]; otherwise null with
## a line in [param problems_out].
static func load_image(path: String, padded_size: Vector2i,
		problems_out: PackedStringArray = PackedStringArray()) -> Image:
	if not FileAccess.file_exists(path):
		problems_out.append("%s is missing" % path)
		return null
	var image: Image = Image.load_from_file(path)
	if image == null or image.is_empty():
		problems_out.append("%s could not be read as an image" % path)
		return null
	if TextureSet.scale_for(image.get_size(), padded_size) == 0:
		problems_out.append("%s is %dx%d, not a whole multiple from 1 to %d of the retail padded size %dx%d"
			% [path, image.get_width(), image.get_height(), TextureSet.MAX_SCALE, padded_size.x, padded_size.y])
		return null
	if image.is_compressed():
		image.decompress()
	image.clear_mipmaps()
	image.convert(Image.FORMAT_RGBA8)
	return image


## The texture of the image at [param path], checked as [method load_image]
## checks it against [param padded_size]: nearest-ready without mipmaps at
## scale 1, otherwise with its transparent edges fixed and mipmaps. Null with
## a line in [param problems_out] when the image is rejected.
static func load_texture(path: String, padded_size: Vector2i,
		problems_out: PackedStringArray = PackedStringArray()) -> Texture2D:
	var key: String = "%s|%d|%dx%d" % [path, FileAccess.get_modified_time(path), padded_size.x, padded_size.y]
	if _loaded.has(key):
		var kept: Variant = _loaded[key].get_ref()
		if kept is Texture2D:
			return kept
	var image: Image = load_image(path, padded_size, problems_out)
	if image == null:
		return null
	if image.get_width() > padded_size.x:
		image.fix_alpha_edges()
		image.generate_mipmaps()
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_loaded[key] = weakref(texture)
	return texture


static func _config_problem(config: ConfigFile) -> String:
	if not config.has_section(SECTION):
		return "has no [%s] section" % SECTION
	if config.has_section_key(SECTION, "format_version"):
		var version: Variant = config.get_value(SECTION, "format_version")
		if typeof(version) != TYPE_INT:
			return "has a non-integer format_version"
		if version != FORMAT_VERSION:
			return "has format_version %d, expected %d" % [version, FORMAT_VERSION]
	for key: String in _REQUIRED:
		if not config.has_section_key(SECTION, key):
			return "has no %s" % key
		var value: Variant = config.get_value(SECTION, key)
		if typeof(value) != TYPE_STRING or str(value).strip_edges().is_empty():
			return "has a non-text %s" % key if typeof(value) != TYPE_STRING else "has an empty %s" % key
	for key: String in _OPTIONAL:
		if config.has_section_key(SECTION, key) and typeof(config.get_value(SECTION, key)) != TYPE_STRING:
			return "has a non-text %s" % key
	return ""


static func _ids_by_name(image_names: NameBank) -> Dictionary[String, int]:
	var by_name: Dictionary[String, int] = {}
	if image_names == null:
		return by_name
	if not image_names.names_by_id.is_empty():
		for texture_id: int in image_names.names_by_id:
			var name: String = image_names.names_by_id[texture_id].to_lower()
			if not by_name.has(name):
				by_name[name] = texture_id
		return by_name
	for texture_id: int in image_names.names.size():
		var name: String = image_names.names[texture_id].to_lower()
		if not name.is_empty() and not by_name.has(name):
			by_name[name] = texture_id
	return by_name
