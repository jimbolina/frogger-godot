class_name TerrainFrogAssets
extends RefCounted
## Loads high-detail frog render resources at setup; gameplay never receives these objects.

var error: String = ""
var model: MofFile
var mesh: ModelMesh
var player: ModelAnimationPlayer
var hidden_parts: PackedInt64Array = PackedInt64Array()
var action_lengths: PackedInt32Array = PackedInt32Array()

## Resolves the GENERAL high-detail frog and texture bank through the existing data APIs.
static func from_data(data: GameData) -> TerrainFrogAssets:
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
	var builder := ModelMeshBuilder.new(library, bank)
	assets.mesh = builder.build_animated(assets.model)
	assets.player = ModelAnimationPlayer.new(assets.model)
	if not assets.player.error.is_empty():
		assets.error = assets.player.error
		return assets
	for action: int in assets.player.action_count():
		assets.action_lengths.append(assets.player.action_frame_count(action) if assets.player.action_error(action).is_empty() else 0)
	if data.version.hidden_parts.has("GEN_FROG.XAR"):
		var hidden: PackedInt64Array = data.version.hidden_parts["GEN_FROG.XAR"]
		assets.hidden_parts = hidden.duplicate()
	return assets
