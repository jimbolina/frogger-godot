extends ImportStep
## Writes the options page's models under [code]models/options/<NAME>/[/code].
##
## These are [OptionsModels]' models built the way it builds them: the
## OPTIONSH.WAD models with the GENERAL high bank and the options bank, the
## options bank first, and the name-entry frog GENM_FROG.XMR with the GENERAL
## high bank and GENERAL's high multiplayer bank, that bank first. Each folder
## holds the file set the models step writes ([code]model.res[/code],
## [code]part_NN.res[/code], [code]mesh.res[/code], [code]model.tscn[/code]).
## Lighting is not baked: the page lights the models in their shader.

const ModelsStep := preload("res://archive/import/steps/models_step.gd")
## The folder under [code]models/[/code] holding the options page's models.
const FOLDER: String = "options"


func step_name() -> String:
	return "options_models"


func phases() -> PackedStringArray:
	return PackedStringArray([PHASE_RESOURCES])


func run(context: ImportContext, phase: String) -> void:
	if phase != PHASE_RESOURCES:
		return
	ModelsStep.imported_banks(context)
	var data: GameData = context.data
	var wad: MwiEntry = data.find_resource(OptionsModels.WAD_NAME)
	var general: ThemeBookEntry = data.theme_book_entry(FroggerIds.THEME_GENERAL)
	if wad == null or general == null:
		context.report("options_models: %s or the GENERAL theme is missing" % OptionsModels.WAD_NAME)
		return
	var general_bank: VloFile = ModelsStep.bank_by_id(context, general.high_vlo_id)
	var own: VloFile = ModelsStep.bank_by_id(context, data.texture_bank_for_wad(wad.index))
	var multiplayer: VloFile = ModelsStep.bank_by_id(context, data.texture_bank_for_wad(general.high_multiplayer_wad_id))
	if general_bank == null or own == null or multiplayer == null:
		context.report("options_models: a texture bank of the options page is missing")
		return
	var materials: Dictionary[String, ShaderMaterial] = {}
	var library := TextureLibrary.new()
	library.add_bank(general_bank, "general")
	library.add_bank(own, "options")
	var file_names := PackedStringArray(OptionsModels.FILE_NAMES)
	for file_name: String in file_names:
		_write(context, file_name, ModelMeshBuilder.new(library, own), materials)
	var entry_library := TextureLibrary.new()
	entry_library.add_bank(general_bank, "general")
	entry_library.add_bank(multiplayer, "multiplayer")
	_write(context, OptionsModels.ENTRY_FROG_NAME, ModelMeshBuilder.new(entry_library, multiplayer), materials)


func _write(context: ImportContext, file_name: String, builder: ModelMeshBuilder,
		materials: Dictionary[String, ShaderMaterial]) -> void:
	var entry: MwiEntry = context.data.find_resource(file_name)
	var problems := PackedStringArray()
	var file: MofFile = context.data.read_model(entry.index, problems) if entry != null else null
	if file == null:
		context.report("options_models: %s cannot be read: %s" % [file_name, "; ".join(problems)])
		return
	var model_name: String = file_name.get_basename()
	ModelsStep.write_model(context, context.model_dir(FOLDER.path_join(model_name)), model_name, file, builder, materials)
