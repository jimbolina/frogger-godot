extends AssetTest
## Every sound-bank sample is a mono 16-bit 11,025 Hz WAV under
## assets/audio/sfx whose PCM matches sound_samples.tsv, and each bank's
## resource points its present rows at those WAVs without holding PCM.

const FAMILY: String = "sound_samples"

var _rows: Array[PackedStringArray] = []


func before_all() -> void:
	_rows = fact_rows("sound_samples.tsv")


## The committed WAV of the sample in [param row]: the bank folder named after
## its body file, then the sound id and name.
static func wav_path(row: PackedStringArray) -> String:
	var label: String = row[3] if not row[3].is_empty() else "sample"
	return "%s/audio/sfx/%s/%03d_%s.wav" % [ASSETS, row[2].get_basename(), int(row[0]), label]


func test_every_sample_is_a_wav_with_the_retail_pcm() -> void:
	assert_eq(_rows.size(), 174)
	var failures := PackedStringArray()
	for row: PackedStringArray in _rows:
		var path: String = wav_path(row)
		var asset: String = path.trim_prefix("res://")
		var stream: AudioStreamWAV = load(path) as AudioStreamWAV if ResourceLoader.exists(path) else null
		if stream == null:
			failures.append("%s does not load" % asset)
			continue
		var frames: int = int(expected(asset, FAMILY, "frames", row[6]))
		var rate: int = int(expected(asset, FAMILY, "rate", row[7]))
		var digest: String = expected(asset, FAMILY, "pcm16_sha256", row[8])
		if stream.format != AudioStreamWAV.FORMAT_16_BITS or stream.stereo:
			failures.append("%s is not mono 16-bit" % asset)
		if stream.mix_rate != rate:
			failures.append("%s plays at %d Hz, not %d" % [asset, stream.mix_rate, rate])
		if stream.loop_mode != AudioStreamWAV.LOOP_DISABLED:
			failures.append("%s has a baked loop" % asset)
		if stream.data.size() / 2 != frames:
			failures.append("%s has %d frames, not %d" % [asset, stream.data.size() / 2, frames])
		if sha256_hex(stream.data) != digest:
			failures.append("%s PCM sha256 differs from %s" % [asset, digest])
	assert_eq(failures, PackedStringArray())


func test_every_bank_resource_points_at_its_wavs() -> void:
	var banks: Dictionary[String, bool] = {}
	var failures := PackedStringArray()
	for row: PackedStringArray in _rows:
		banks[row[2]] = true
		var entry: MwiEntry = catalog().find_resource(row[2])
		var header: SoundBankHeader = catalog().read_sound_bank(entry.index) if entry != null else null
		var sound_id: int = int(row[0])
		if header == null or sound_id >= header.entries.size():
			failures.append("bank %s has no row %d" % [row[2], sound_id])
			continue
		var stream: AudioStream = header.entries[sound_id].stream
		if stream == null or stream.resource_path != wav_path(row):
			failures.append("bank %s row %d streams %s" % [row[2], sound_id,
				stream.resource_path if stream != null else "nothing"])
		if not header.entries[sound_id].audio_present:
			failures.append("bank %s row %d is not present" % [row[2], sound_id])
	assert_eq(failures, PackedStringArray())
	assert_eq(banks.size(), 10)
	var resources: PackedStringArray = files_under(ASSETS.path_join("audio/sfx"), ".tres")
	assert_eq(resources.size(), banks.size(), "one resource per bank")
	for path: String in resources:
		assert_false(FileAccess.get_file_as_string(path).contains("PackedByteArray"), "%s holds no PCM" % path)
	assert_eq(files_under(ASSETS.path_join("audio/sfx"), ".wav").size(), _rows.size(), "one WAV per sample")
