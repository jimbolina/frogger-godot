class_name LogicalSoundSetup
extends RefCounted
## Binds the executable's sample definitions to the durations of the selected Windows banks.

var music_pitches: Array[Vector2i] = []
var definitions: Array[LogicalSoundDefinition] = []
var error: String = ""

## Loads only the requested banks and resolves their original source voice groups.
static func from_data(data: AssetCatalog, bank_ids: PackedInt32Array) -> LogicalSoundSetup:
	var result := LogicalSoundSetup.new()
	if data == null or not data.is_valid():
		result.error = "Logical sound setup requires valid supplied data"
		return result
	var tables: SoundTables = data.tables.sound_tables()
	if not tables.error.is_empty():
		result.error = tables.error
		return result
	result.music_pitches.assign(tables.music_pitches)
	var headers: Dictionary[int, SoundBankHeader] = {}
	for bank_id: int in bank_ids:
		if bank_id < 0 or bank_id >= tables.banks.size():
			result.error = "Unknown sound bank %d" % bank_id
			return result
		var bank: SoundBankSetup = SoundBankSetup.from_catalog(data, tables.banks[bank_id].y)
		if not bank.error.is_empty():
			result.error = bank.error
			return result
		headers[bank_id] = bank.header
	for sample: SoundSampleEntry in tables.samples:
		if not headers.has(sample.bank_id):
			continue
		var header: SoundBankHeader = headers[sample.bank_id]
		if sample.sound_id >= header.entries.size() or not header.entries[sample.sound_id].audio_present:
			result.error = "Sound %d is absent from its supplied bank %d" % [sample.sound_id, sample.bank_id]
			return result
		var entry: SoundBankEntry = header.entries[sample.sound_id]
		if entry.sample_bits != 16:
			result.error = "Logical sound %d requires the verified 16-bit native sample clock" % sample.sound_id
			return result
		var definition := LogicalSoundDefinition.new()
		definition.sound_id = sample.sound_id
		definition.flags = sample.flags
		definition.first_voice = tables.groups[sample.group_id].x
		definition.last_voice = tables.groups[sample.group_id].y
		definition.note = sample.note
		definition.pitch_mod = sample.pitch_mod
		definition.frame_count = entry.frame_count()
		definition.minimum_volume = sample.minimum_volume
		definition.maximum_volume = sample.maximum_volume
		result.error = definition.validate()
		if not result.error.is_empty():
			return result
		result.definitions.append(definition)
	return result
