extends ImportStep
## Writes every present sound-bank row as a WAV and each bank as a [SoundBankHeader].
##
## The raw phase writes one mono 16-bit 11,025 Hz WAV per present row of each
## bank the executable's sound tables name (unsigned 8-bit rows are widened as
## [method SoundBankPcm.to_signed_16] does). The resources phase saves the
## bank's header rows with each present row's [member SoundBankEntry.stream]
## pointing at its imported WAV; the resource holds no PCM.

const MIX_RATE: int = 11025


func step_name() -> String:
	return "sfx"


func phases() -> PackedStringArray:
	return PackedStringArray([PHASE_RAW, PHASE_RESOURCES])


func run(context: ImportContext, phase: String) -> void:
	var tables: SoundTables = context.data.tables.sound_tables()
	if not tables.error.is_empty():
		context.report("sound tables: %s" % tables.error)
		return
	for bank: Vector2i in tables.banks:
		if bank.x < 0 or bank.y < 0:
			continue
		var bank_name: String = context.entry_name(bank.y)
		var problems := PackedStringArray()
		var header_bytes: PackedByteArray = context.data.read_resource(bank.x, problems)
		var body: PackedByteArray = context.data.read_resource(bank.y, problems)
		if not problems.is_empty():
			context.report("sound bank %s: %s" % [bank_name, "; ".join(problems)])
			continue
		var header: SoundBankHeader = SoundBankReader.read(header_bytes, body.size(), context.entry_name(bank.x))
		if not header.error.is_empty():
			context.report("sound bank %s: %s" % [bank_name, header.error])
			continue
		if phase == PHASE_RAW:
			_write_samples(context, bank_name, header, body)
		else:
			_save_bank(context, bank_name, header)


## The WAV file bytes of mono signed 16-bit little-endian [param pcm] at [param rate].
static func wav_bytes(pcm: PackedByteArray, rate: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(44)
	bytes.encode_u32(0, 0x46464952)
	bytes.encode_u32(4, 36 + pcm.size())
	bytes.encode_u32(8, 0x45564157)
	bytes.encode_u32(12, 0x20746D66)
	bytes.encode_u32(16, 16)
	bytes.encode_u16(20, 1)
	bytes.encode_u16(22, 1)
	bytes.encode_u32(24, rate)
	bytes.encode_u32(28, rate * 2)
	bytes.encode_u16(32, 2)
	bytes.encode_u16(34, 16)
	bytes.encode_u32(36, 0x61746164)
	bytes.encode_u32(40, pcm.size())
	bytes.append_array(pcm)
	return bytes


func _sample_name(context: ImportContext, sound_id: int) -> String:
	var names: NameBank = context.data.names.sounds
	return names.name_of(sound_id) if names != null and names.has_name(sound_id) else ""


func _write_samples(context: ImportContext, bank_name: String, header: SoundBankHeader, body: PackedByteArray) -> void:
	for entry: SoundBankEntry in header.entries:
		if not entry.audio_present:
			continue
		var pcm: SoundBankPcm = SoundBankPcm.slice(entry, body)
		if not pcm.error.is_empty():
			context.report("sound bank %s: %s" % [bank_name, pcm.error])
			continue
		var path: String = context.sfx_path(bank_name, entry.sound_id, _sample_name(context, entry.sound_id))
		context.write_if_changed(path, wav_bytes(pcm.to_signed_16(), MIX_RATE))


func _save_bank(context: ImportContext, bank_name: String, header: SoundBankHeader) -> void:
	header.resource_name = bank_name
	for entry: SoundBankEntry in header.entries:
		var sample_name: String = _sample_name(context, entry.sound_id)
		entry.resource_name = sample_name
		entry.resource_scene_unique_id = "entry_%03d" % entry.sound_id
		if not entry.audio_present:
			continue
		var path: String = context.sfx_path(bank_name, entry.sound_id, sample_name)
		var stream: AudioStreamWAV = load(path) as AudioStreamWAV
		if stream == null:
			context.report("sound bank %s: %s did not import" % [bank_name, path])
			continue
		entry.stream = stream
	context.save_resource(header, context.sound_bank_path(bank_name))
