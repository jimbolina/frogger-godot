class_name TerrainFrogAssets
extends RefCounted
## Loads high-detail frog render resources at setup; gameplay never receives these objects.

var error: String = ""
var model: MofFile
var mesh: ModelMesh
var player: ModelAnimationPlayer
var hidden_parts: PackedInt64Array = PackedInt64Array()
var action_lengths: PackedInt32Array = PackedInt32Array()

## Resolves the GENERAL high-detail frog, its texture bank and its hidden parts from [param data].
static func from_data(data: AssetCatalog) -> TerrainFrogAssets:
	var assets := TerrainFrogAssets.new()
	if data == null or not data.is_valid():
		assets.error = "Frog presentation requires valid game data"
		return assets
	var entry: MwiEntry = data.find_resource("GEN_FROG.XAR")
	var general: ThemeBookEntry = data.theme_book_entry(FroggerIds.THEME_GENERAL)
	if entry == null or general == null:
		assets.error = "High-detail frog or GENERAL theme is unavailable"
		return assets
	var problems := PackedStringArray()
	assets.model = data.read_model(entry.index, problems)
	var bank: VloFile = data.read_texture_bank(general.high_vlo_id, problems)
	if assets.model == null or bank == null:
		assets.error = "Cannot load frog resources: " + "; ".join(problems)
		return assets
	var library := TextureLibrary.new()
	library.add_bank(bank, "general")
	assets.mesh = ModelMeshLibrary.mesh_for(data, entry.index, library, bank)
	assets.player = ModelAnimationPlayer.new(assets.model)
	if not assets.player.error.is_empty():
		assets.error = assets.player.error
		return assets
	for action: int in assets.player.action_count():
		assets.action_lengths.append(assets.player.action_frame_count(action) if assets.player.action_error(action).is_empty() else 0)
	assets.hidden_parts = data.hidden_parts_of("GEN_FROG.XAR").duplicate()
	return assets


## A copy of these assets drawn with [param drawn_mesh] instead of [member mesh].
func with_mesh(drawn_mesh: ModelMesh) -> TerrainFrogAssets:
	var copy := TerrainFrogAssets.new()
	copy.error = error
	copy.model = model
	copy.mesh = drawn_mesh
	copy.player = player
	copy.hidden_parts = hidden_parts.duplicate()
	copy.action_lengths = action_lengths.duplicate()
	return copy
