class_name SoundBankSetup
extends RefCounted
## Resolves one sound bank from the catalog into validated sound metadata.
##
## The header's present entries carry their [member SoundBankEntry.stream].

var header: SoundBankHeader = null
var error: String = ""

## Loads the bank whose sample body has resource id [param body_resource_id],
## constructing no playback objects.
static func from_catalog(data: AssetCatalog, body_resource_id: int) -> SoundBankSetup:
	var result := SoundBankSetup.new()
	if data == null or not data.is_valid():
		result.error = "Sound bank setup requires valid game data"
		return result
	var problems := PackedStringArray()
	result.header = data.read_sound_bank(body_resource_id, problems)
	if result.header == null:
		result.error = "; ".join(problems) if not problems.is_empty() else "Sound bank %d is unavailable" % body_resource_id
		return result
	result.error = result.header.error
	return result
