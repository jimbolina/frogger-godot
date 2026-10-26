class_name DemoTrace
extends RefCounted
## Frozen-reference CSV projection with separately owned playback provenance.

var frog_rows := PackedStringArray(["call,page,map,frog,grid_x,grid_z,x,y,z,mode,flags,input"])
var entity_rows := PackedStringArray(["call,map,index,unique_id,form_book_id,entity_type,x,y,z"])
var entity_types: Dictionary[int, int] = {}
var form_ids: Dictionary[int, int] = {}

## Records source form identities before application records leave scope.
func configure(data: GameData, scene: MapSceneData) -> void:
	for index: int in scene.map.entities.size():
		var entity: MapEntitySpan = scene.map.entities[index]
		var form: FormBookEntry = data.tables.theme_book().get_form(scene.map.general.theme, entity.form_id)
		form_ids[index] = entity.form_id
		entity_types[index] = form.entity_type if form != null else -1

## Appends a committed logic tick; local call numbering starts at zero.
func append(state: GameplayState, consumed_byte: int, map_index: int) -> void:
	var call_index: int = frog_rows.size() - 1
	var frog: FrogState = state.frog
	frog_rows.append(_row([call_index, 7, map_index, 0, frog.cell.x, frog.cell.y,
		frog.matrix12[9], frog.matrix12[10], frog.matrix12[11], frog.mode, frog.flags, consumed_byte]))
	if state.entities == null:
		return
	var order: PackedInt32Array = state.entities.live_order
	var walk_index: int = 0
	for identity: int in order:
		for entity: EntitySnapshot in state.entities.entities:
			if entity.entity_index == identity and entity.live:
				entity_rows.append(_row([call_index, map_index, walk_index, entity.unique_id,
					form_ids.get(identity, -1), entity_types.get(identity, -1),
					entity.matrix12[9], entity.matrix12[10], entity.matrix12[11]]))
				walk_index += 1
				break

## Saves both CSVs and explicit completion/provenance JSON outside the checkout.
func save(folder: String, status: Dictionary) -> String:
	if not ViewerCapture.external_folder(folder):
		return "Demo trace requires an absolute external destination"
	var issue: String = ViewerCapture.prepare_folder(folder)
	if not issue.is_empty():
		return issue
	for name: String in ["frog.csv", "frog.csv.entities.csv", "playback.json"]:
		var file := FileAccess.open(folder.path_join(name), FileAccess.WRITE)
		if file == null:
			return "Cannot write demo evidence: " + folder.path_join(name)
		file.store_string(JSON.stringify(status, "  ") + "\n" if name == "playback.json" else "\n".join(frog_rows if name == "frog.csv" else entity_rows) + "\n")
		file.flush()
		var failure: Error = file.get_error()
		file.close()
		if failure != OK:
			return "Cannot finish demo evidence: " + folder.path_join(name)
	return ""

static func _row(values: Array) -> String:
	var words := PackedStringArray()
	for value: Variant in values:
		words.append(str(value))
	return ",".join(words)
