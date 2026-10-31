class_name SoundBankSetup
extends RefCounted
## Resolves supplied archive resources into validated sound metadata and the retained PCM body.
##
## From an [ImportedAssets] catalog the header comes from the imported bank,
## whose present rows carry their [member SoundBankEntry.stream], and
## [member body] stays empty.

var header: SoundBankHeader = null
var body: PackedByteArray = PackedByteArray()
var error: String = ""

## Loads a caller-selected bank pair, keeping the body bytes for slicing and constructing no playback objects.
static func from_resources(data: AssetCatalog, header_resource_id: int, body_resource_id: int) -> SoundBankSetup:
	var result := SoundBankSetup.new()
	if data == null or not data.is_valid():
		result.error = "Sound bank setup requires valid supplied game data"
		return result
	if data is ImportedAssets:
		return _from_imported(data as ImportedAssets, body_resource_id)
	var header_entry: MwiEntry = data.mwi.get_entry(header_resource_id)
	var body_entry: MwiEntry = data.mwi.get_entry(body_resource_id)
	if header_entry == null or body_entry == null:
		result.error = "Sound bank setup requires existing header and body resource IDs"
		return result
	var problems := PackedStringArray()
	var header_bytes: PackedByteArray = data.read_resource(header_resource_id, problems)
	var body_bytes: PackedByteArray = data.read_resource(body_resource_id, problems)
	if not problems.is_empty():
		result.error = "; ".join(problems)
		return result
	result.header = SoundBankHeader.read(header_bytes, body_bytes.size(), header_entry.display_name())
	result.error = result.header.error
	if result.error.is_empty():
		result.body = body_bytes
	return result

static func _from_imported(data: ImportedAssets, body_resource_id: int) -> SoundBankSetup:
	var result := SoundBankSetup.new()
	var problems := PackedStringArray()
	result.header = data.read_sound_bank(body_resource_id, problems)
	if result.header == null:
		result.error = "; ".join(problems) if not problems.is_empty() else "Sound bank %d was not imported" % body_resource_id
		return result
	result.error = result.header.error
	return result
