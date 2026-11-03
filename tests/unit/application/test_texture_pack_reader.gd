extends GutTest
## TexturePackReader over synthetic packs in a scratch folder: listing reads
## each pack's pack.cfg and reports folders that are not packs (no pack.cfg,
## a malformed one, missing or mistyped keys, a newer format) and packs hidden
## by an earlier folder; a pack is found by folder name, then ignoring case;
## files map to texture ids by tNNNN name or FrogLord image name; and an image
## is accepted at any whole multiple from 1 to 16 of its retail padded size,
## with mipmaps above 1, or rejected with the sizes named.

const SCRATCH: String = "user://test_texture_pack_reader"
const FIRST: String = SCRATCH + "/first"
const SECOND: String = SCRATCH + "/second"
const PADDED: Vector2i = Vector2i(10, 6)


func before_each() -> void:
	_remove(SCRATCH)
	assert_eq(DirAccess.make_dir_recursive_absolute(FIRST), OK)
	assert_eq(DirAccess.make_dir_recursive_absolute(SECOND), OK)


func after_all() -> void:
	_remove(SCRATCH)


func _remove(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for child: String in DirAccess.get_directories_at(path):
		_remove(path.path_join(child))
	for child: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)


func _pack_folder(parent: String, name: String, config_text: String) -> String:
	var folder: String = parent.path_join(name)
	assert_eq(DirAccess.make_dir_recursive_absolute(folder), OK)
	if not config_text.is_empty():
		var file: FileAccess = FileAccess.open(folder.path_join(TexturePackReader.CONFIG_FILE), FileAccess.WRITE)
		file.store_string(config_text)
		file.close()
	return folder


func _config(name: String, extra: String = "") -> String:
	return "[pack]\nname=\"%s\"\nbase_build=\"pc-retail-v3.0e\"\n%s" % [name, extra]


func _png(path: String, size: Vector2i, colour: Color = Color(0.2, 0.4, 0.6, 1.0)) -> void:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(colour)
	assert_eq(image.save_png(path), OK)


func test_listing_reads_each_pack_and_reports_folders_that_are_not_packs() -> void:
	var crisp: String = _pack_folder(FIRST, "crisp", _config("Crisp Frogs",
		"author=\"A. Artist\"\nversion=\"1.2\"\ndescription=\"Sharper frogs.\"\nformat_version=1\n"))
	_png(crisp.path_join("t0012.png"), PADDED * 2)
	_png(crisp.path_join("HI_A.PNG"), PADDED)
	var notes: FileAccess = FileAccess.open(crisp.path_join("notes.txt"), FileAccess.WRITE)
	notes.store_string("not an image")
	notes.close()
	_pack_folder(FIRST, "plain", _config("Plain"))
	_pack_folder(FIRST, "no_config", "")
	_pack_folder(FIRST, "no_name", "[pack]\nbase_build=\"pc-retail-v3.0e\"\n")
	_pack_folder(FIRST, "number_name", "[pack]\nname=7\nbase_build=\"pc-retail-v3.0e\"\n")
	_pack_folder(FIRST, "empty_build", "[pack]\nname=\"Empty\"\nbase_build=\"  \"\n")
	_pack_folder(FIRST, "no_section", "[other]\nname=\"Other\"\n")
	_pack_folder(FIRST, "future", _config("Future", "format_version=2\n"))
	_pack_folder(FIRST, "number_author", _config("Author", "author=3\n"))
	var problems := PackedStringArray()
	var packs: Array[TexturePack] = TexturePackReader.list(PackedStringArray([FIRST, SCRATCH + "/absent"]), problems)
	assert_eq(packs.size(), 2, "\n".join(problems))
	assert_eq(packs[0].pack_name, "crisp")
	assert_eq(packs[0].title, "Crisp Frogs")
	assert_eq(packs[0].display_name(), "Crisp Frogs")
	assert_eq(packs[0].author, "A. Artist")
	assert_eq(packs[0].version, "1.2")
	assert_eq(packs[0].description, "Sharper frogs.")
	assert_eq(packs[0].base_build, "pc-retail-v3.0e")
	assert_eq(packs[0].folder, crisp)
	assert_eq(packs[0].files, PackedStringArray(["HI_A.PNG", "t0012.png"]), "only PNG files, sorted")
	assert_eq(packs[1].pack_name, "plain")
	assert_eq(packs[1].author, "")
	var reasons: String = "\n".join(problems)
	assert_eq(problems.size(), 7, reasons)
	assert_string_contains(reasons, "no_config has no pack.cfg; it is not a texture pack")
	assert_string_contains(reasons, "no_name/pack.cfg has no name")
	assert_string_contains(reasons, "number_name/pack.cfg has a non-text name")
	assert_string_contains(reasons, "empty_build/pack.cfg has an empty base_build")
	assert_string_contains(reasons, "no_section/pack.cfg has no [pack] section")
	assert_string_contains(reasons, "future/pack.cfg has format_version 2, expected 1")
	assert_string_contains(reasons, "number_author/pack.cfg has a non-text author")


func test_a_malformed_pack_cfg_is_not_a_pack() -> void:
	_pack_folder(FIRST, "broken", "[pack\nname=((((\n")
	var problems := PackedStringArray()
	assert_eq(TexturePackReader.list(PackedStringArray([FIRST]), problems).size(), 0)
	assert_eq(problems.size(), 1)
	assert_string_contains(problems[0], "broken/pack.cfg could not be read")
	assert_engine_error("ConfigFile parse error", "Godot reports the malformed file")


func test_an_earlier_folder_hides_a_pack_of_the_same_name() -> void:
	_pack_folder(FIRST, "crisp", _config("First crisp"))
	_pack_folder(SECOND, "crisp", _config("Second crisp"))
	_pack_folder(SECOND, "only_second", _config("Second only"))
	var problems := PackedStringArray()
	var packs: Array[TexturePack] = TexturePackReader.list(PackedStringArray([FIRST, SECOND]), problems)
	assert_eq(packs.size(), 2)
	assert_eq(packs[0].title, "First crisp")
	assert_eq(packs[1].pack_name, "only_second")
	assert_eq(problems.size(), 1)
	assert_string_contains(problems[0], "texture pack crisp in %s is hidden by the one in %s" % [SECOND, FIRST])


func test_a_pack_is_found_by_folder_name_then_ignoring_case() -> void:
	_pack_folder(SECOND, "Crisp", _config("Crisp"))
	_pack_folder(FIRST, "broken", "")
	var problems := PackedStringArray()
	var folders := PackedStringArray([FIRST, SECOND])
	assert_eq(TexturePackReader.find("Crisp", folders, problems).folder, SECOND.path_join("Crisp"))
	assert_eq(TexturePackReader.find("crisp", folders, problems).pack_name, "Crisp")
	assert_null(TexturePackReader.find("absent", folders, problems))
	assert_null(TexturePackReader.find("", folders, problems))
	assert_eq(problems, PackedStringArray())
	assert_null(TexturePackReader.find("broken", folders, problems), "a folder that is not a pack is not found")
	assert_eq(problems.size(), 1)
	assert_string_contains(problems[0], "has no pack.cfg")


func test_the_default_search_folder_is_under_user_data() -> void:
	var folders: PackedStringArray = TexturePackReader.search_folders()
	assert_eq(folders[0], "user://texture_packs")
	assert_eq(folders.size(), 2 if OS.has_feature("template") else 1, "beside the executable only in an exported game")


func test_files_map_to_texture_ids_by_number_or_froglord_name() -> void:
	var folder: String = _pack_folder(FIRST, "named", _config("Named"))
	for file: String in ["t0012.png", "HI_A.png", "hi_b.png", "t0263.png", "unknown.png", "t12.png"]:
		_png(folder.path_join(file), PADDED)
	var pack: TexturePack = TexturePackReader.read(folder)
	var names: NameBank = SyntheticNames.indexed("263=hi_a\n264=hi_b\n265=HI_B\n", "Image")
	var problems := PackedStringArray()
	var sources: Dictionary[int, String] = TexturePackReader.sources(pack, names, problems)
	assert_eq(sources.size(), 3, str(sources))
	assert_eq(sources[12], folder.path_join("t0012.png"))
	assert_eq(sources[263], folder.path_join("t0263.png"), "a tNNNN name wins over a FrogLord name")
	assert_eq(sources[264], folder.path_join("hi_b.png"), "FrogLord names match ignoring case, first id first")
	var reasons: String = "\n".join(problems)
	assert_eq(problems.size(), 3, reasons)
	assert_string_contains(reasons, "texture pack named: HI_A.png and t0263.png both replace texture 263; drawing t0263.png")
	assert_string_contains(reasons, "texture pack named: unknown.png names no texture; it is not drawn")
	assert_string_contains(reasons, "texture pack named: t12.png names no texture")
	var numbered_only: Dictionary[int, String] = TexturePackReader.sources(pack, null, PackedStringArray())
	assert_eq(numbered_only.keys(), [12, 263], "without image names only tNNNN files map")


func test_images_are_accepted_at_any_whole_scale_and_rejected_otherwise() -> void:
	var folder: String = _pack_folder(FIRST, "sizes", _config("Sizes"))
	var cases: Dictionary[String, Vector2i] = {
		"one.png": PADDED, "two.png": PADDED * 2, "four.png": PADDED * 4, "sixteen.png": PADDED * 16,
		"half.png": Vector2i(25, 15), "aspect.png": Vector2i(20, 18), "seventeen.png": PADDED * 17,
	}
	for file: String in cases:
		_png(folder.path_join(file), cases[file])
	var problems := PackedStringArray()
	var one: Texture2D = TexturePackReader.load_texture(folder.path_join("one.png"), PADDED, problems)
	assert_eq(one.get_size(), Vector2(PADDED))
	assert_false(one.get_image().has_mipmaps(), "a retail-size image stays without mipmaps")
	for file: String in ["two.png", "four.png", "sixteen.png"]:
		var scaled: Texture2D = TexturePackReader.load_texture(folder.path_join(file), PADDED, problems)
		assert_eq(Vector2i(scaled.get_size()), cases[file], file)
		assert_true(scaled.get_image().has_mipmaps(), "%s is mipmapped" % file)
		assert_eq(scaled.get_image().get_format(), Image.FORMAT_RGBA8)
	assert_eq(problems, PackedStringArray())
	for file: String in ["half.png", "aspect.png", "seventeen.png"]:
		assert_null(TexturePackReader.load_texture(folder.path_join(file), PADDED, problems), file)
	assert_eq(problems.size(), 3)
	assert_string_contains(problems[0], "half.png is 25x15, not a whole multiple from 1 to 16 of the retail padded size 10x6")
	assert_string_contains(problems[1], "aspect.png is 20x18")
	assert_string_contains(problems[2], "seventeen.png is 170x102")
	problems.clear()
	assert_null(TexturePackReader.load_texture(folder.path_join("absent.png"), PADDED, problems))
	assert_string_contains(problems[0], "absent.png is missing")


func test_a_loaded_texture_is_shared_while_held() -> void:
	var folder: String = _pack_folder(FIRST, "shared", _config("Shared"))
	_png(folder.path_join("t0012.png"), PADDED * 2)
	var first: Texture2D = TexturePackReader.load_texture(folder.path_join("t0012.png"), PADDED)
	assert_same(TexturePackReader.load_texture(folder.path_join("t0012.png"), PADDED), first)
	var image: Image = TexturePackReader.load_image(folder.path_join("t0012.png"), PADDED)
	assert_eq(image.get_size(), PADDED * 2)
	assert_false(image.has_mipmaps())
