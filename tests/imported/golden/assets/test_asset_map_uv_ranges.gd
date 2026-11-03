extends AssetTest
## The premise behind per-image terrain sampling holds
## for the committed maps and banks: every map's static corners land inside
## their padded image, the animated scrolls leave it only where
## map_uv_ranges.tsv says, the ENVMAP images keep their placement and padded
## PNG size, and every image a map uses has padding on each side. The counts
## are measured through [MapAnimationPlayer] with the banks and remap the game
## loads for each map.

const FACTS: String = "map_uv_ranges.tsv"
const TEXTURED_TYPES: Array[int] = [2, 3, 6, 7]
const POLY_ENVMAP: int = 2
const ANIM_UV: int = 1
const ANIM_TEXTURE: int = 2
const MAP_COLUMNS: Array[String] = ["kind", "name", "textured_polygons", "static_polygons", "outside_static",
	"max_static_reach", "animated_instances", "outside_scroll", "max_scroll_reach", "scroll_textures", "env_polygons",
	"env_textures"]
const ENV_COLUMNS: Array[String] = ["u", "v", "width", "height", "padded_width", "padded_height", "vram_x", "vram_y",
	"vram_page"]

var _map_rows: Dictionary[String, PackedStringArray] = {}
var _env_rows: Array[PackedStringArray] = []
var _padding_rows: Array[PackedStringArray] = []
var _measured: Dictionary[String, PackedStringArray] = {}
var _env_images: Dictionary[String, VloImage] = {}
var _minimum_padding: int = 256
var _bank_names: Dictionary[VloFile, String] = {}
var _problems := PackedStringArray()


func before_all() -> void:
	for row: PackedStringArray in imported_rows(FACTS):
		match row[0]:
			"map":
				_map_rows[row[1]] = row
			"env":
				_env_rows.append(row)
			"padding":
				_padding_rows.append(row)
	for entry: MwiEntry in catalog().map_entries():
		_measure(entry)


func test_every_map_has_one_row() -> void:
	var names: Array[String] = []
	names.assign(_measured.keys())
	names.sort()
	var facts: Array[String] = []
	facts.assign(_map_rows.keys())
	facts.sort()
	assert_eq(names.size(), 78, "the archive has 78 maps")
	assert_eq(names, facts, "one map row per committed map")
	assert_eq(_problems.size(), 0, "\n".join(_problems.slice(0, 12)))


func test_map_ranges_match_the_facts() -> void:
	var mismatches := PackedStringArray()
	for map_name: String in _map_rows:
		var want: PackedStringArray = _map_rows[map_name]
		var got: PackedStringArray = _measured.get(map_name, PackedStringArray())
		if got.size() != want.size():
			mismatches.append("%s: measured %s" % [map_name, got])
			continue
		for column: int in range(2, want.size()):
			if got[column] != want[column]:
				mismatches.append("%s %s: measured %s, golden %s" % [map_name, MAP_COLUMNS[column], got[column], want[column]])
	assert_eq(mismatches.size(), 0, "\n".join(mismatches.slice(0, 12)))


func test_env_images_match_the_facts() -> void:
	var mismatches := PackedStringArray()
	var keys: Array[String] = []
	keys.assign(_env_images.keys())
	keys.sort()
	var facts: Array[String] = []
	for row: PackedStringArray in _env_rows:
		var key: String = "%s/%s" % [row[1], row[2]]
		facts.append(key)
		var image: VloImage = _env_images.get(key, null)
		if image == null:
			mismatches.append("env %s: no ENVMAP polygon uses it" % key)
			continue
		var got: Array[int] = [image.u, image.v, image.width, image.height, image.padded_width,
			image.padded_height, image.vram_x, image.vram_y, image.page()]
		for column: int in got.size():
			if got[column] != int(row[3 + column]):
				mismatches.append("env %s %s: measured %d, golden %s" % [key, ENV_COLUMNS[column], got[column], row[3 + column]])
		var texture: Texture2D = catalog().texture_of(image)
		var size: Vector2i = Vector2i(texture.get_size()) if texture != null else Vector2i.ZERO
		if size != Vector2i(int(row[7]), int(row[8])):
			mismatches.append("env %s: PNG is %s, padded size %sx%s" % [key, size, row[7], row[8]])
	facts.sort()
	assert_eq(keys, facts, "one env row per ENVMAP image")
	assert_eq(mismatches.size(), 0, "\n".join(mismatches.slice(0, 12)))


func test_minimum_padding_matches_the_facts() -> void:
	assert_eq(_padding_rows.size(), 1, "one padding row")
	if _padding_rows.size() == 1:
		assert_eq(str(_minimum_padding), _padding_rows[0][2], "smallest padding of a map image")


func _measure(entry: MwiEntry) -> void:
	var map_name: String = entry.display_name().get_basename()
	var book: MapBookEntry = catalog().tables.map_book().find_by_map(entry.index)
	var map: MapFile = catalog().read_map(entry.index, _problems)
	var remap: TextureRemap = catalog().remap_for_resource(entry.index)
	if book == null or map == null or remap == null:
		_problems.append("%s: no map book row, map or remap" % map_name)
		return
	var low_poly: bool = book.low_map_id == entry.index
	var multiplayer: bool = AssetCatalog.is_multiplayer_level(book.level)
	var general: VloFile = _bank(FroggerIds.THEME_GENERAL, multiplayer, low_poly)
	var theme: VloFile = _bank(map.general.theme, multiplayer, low_poly)
	if general == null or theme == null:
		_problems.append("%s: a texture bank is missing" % map_name)
		return
	var library := TextureLibrary.new()
	library.add_bank(general)
	library.add_bank(theme)
	var player := MapAnimationPlayer.new()
	player.configure(map.polygons, map.animations, remap, library, theme)
	var targeted: Dictionary[int, bool] = {}
	for animation: MapAnimation in map.animations:
		for target: int in animation.target_polygon_indices:
			targeted[target] = true
	var textured: int = 0
	var static_count: int = 0
	var outside_static: int = 0
	var static_reach: int = 0
	var env_count: int = 0
	var env_ids: Array[int] = []
	for index: int in map.polygons.size():
		var polygon: MapPolygon = map.polygons[index]
		if not polygon.type_index in TEXTURED_TYPES:
			continue
		textured += 1
		var texture_id: int = remap.global_id(polygon.texture_id)
		var image: VloImage = library.image_for_id(texture_id, theme)
		if image == null:
			_problems.append("%s: polygon %d has no image for texture %d" % [map_name, index, texture_id])
			continue
		_note_padding(image)
		if polygon.flags & POLY_ENVMAP:
			env_count += 1
			if not texture_id in env_ids:
				env_ids.append(texture_id)
			var bank: VloFile = theme if theme.find_texture(texture_id) == image else general
			_env_images["%d/%s" % [texture_id, _bank_names.get(bank, "?")]] = image
			continue
		if targeted.has(index):
			continue
		static_count += 1
		var reach: int = _base_reach(player.base_pixel_uvs(index), image)
		static_reach = maxi(static_reach, reach)
		if reach > 0:
			outside_static += 1
	env_ids.sort()
	var row := PackedStringArray(["map", map_name, str(textured), str(static_count), str(outside_static), str(static_reach)])
	row.append_array(_scroll(map, player, library, theme))
	row.append_array(PackedStringArray([str(env_count), _ids(env_ids)]))
	_measured[map_name] = row


func _scroll(map: MapFile, player: MapAnimationPlayer, library: TextureLibrary, theme: VloFile) -> PackedStringArray:
	var ticks: int = 1
	for animation: MapAnimation in map.animations:
		ticks = maxi(ticks, _period(animation))
	var worst: Dictionary[int, int] = {}
	var textures: Array[int] = []
	for _tick: int in ticks:
		player.step()
		for animation: MapAnimation in map.animations:
			for target: int in animation.target_polygon_indices:
				if map.polygons[target].flags & POLY_ENVMAP:
					continue
				var image: VloImage = library.image_for_id(player.image_id(target), theme)
				if image == null:
					_problems.append("animation image %d is in no bank" % player.image_id(target))
					continue
				_note_padding(image)
				var reach: int = _relative_reach(player.pixel_uvs(target), image)
				worst[target] = maxi(worst[target], reach) if worst.has(target) else reach
				if reach > 0 and not player.image_id(target) in textures:
					textures.append(player.image_id(target))
	var outside: int = 0
	var most: int = 0
	for target: int in worst:
		most = maxi(most, worst[target])
		if worst[target] > 0:
			outside += 1
	textures.sort()
	return PackedStringArray([str(worst.size()), str(outside), str(most), _ids(textures)])


func _period(animation: MapAnimation) -> int:
	var uv: int = (animation.uv_frame_count if animation.uv_frame_count > 0 else 65536) if animation.type & ANIM_UV else 1
	var cels: int = maxi(1, animation.frames_per_texture) * maxi(1, animation.texture_ids.size()) if animation.type & ANIM_TEXTURE else 1
	@warning_ignore("integer_division")
	return uv * cels / _gcd(uv, cels)


func _gcd(a: int, b: int) -> int:
	return a if b == 0 else _gcd(b, a % b)


func _base_reach(points: PackedVector2Array, image: VloImage) -> int:
	var relative := PackedVector2Array()
	for point: Vector2 in points:
		relative.append(Vector2(((int(point.x) + image.u) & 255) - image.u, ((int(point.y) + image.v) & 255) - image.v))
	return _relative_reach(relative, image)


func _relative_reach(points: PackedVector2Array, image: VloImage) -> int:
	var worst: int = 0
	for point: Vector2 in points:
		var x: int = int(point.x)
		var y: int = int(point.y)
		worst = maxi(worst, maxi(maxi(-x, x - image.width), maxi(-y, y - image.height)))
	return worst


func _note_padding(image: VloImage) -> void:
	_minimum_padding = mini(_minimum_padding, mini(image.left_padding(), image.top_padding()))


func _bank(theme_number: int, multiplayer: bool, low_poly: bool) -> VloFile:
	var theme: ThemeBookEntry = catalog().theme_book_entry(theme_number)
	if theme == null:
		return null
	var id: int = theme.vlo_id(multiplayer, low_poly)
	if id == 0:
		id = theme.vlo_id(false, low_poly)
	var bank: VloFile = catalog().read_texture_bank(id, _problems)
	var entry: MwiEntry = catalog().mwi.get_entry(id)
	if bank != null and entry != null:
		_bank_names[bank] = entry.display_name().get_basename()
	return bank


func _ids(values: Array) -> String:
	if values.is_empty():
		return "-"
	var parts := PackedStringArray()
	for value: int in values:
		parts.append(str(value))
	return ",".join(parts)
