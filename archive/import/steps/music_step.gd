extends ImportStep
## Decodes the disc's audio tracks: to scratch WAVs for
## [code]encode_music.sh[/code], or in a runtime run to [AudioStreamWAV]
## resources.
##
## Each audio track of the disc image is read sector by sector as 16-bit
## stereo 44,100 Hz PCM and its digest is checked against
## [constant FACTS]. The editor run writes a WAV per track in the scratch
## folder, skipping a track whose Ogg is already committed unless the run
## forces music; the encoder script then turns the WAVs into
## [code]assets/audio/music/track_NN.ogg[/code]. A runtime run saves each
## track as [code]audio/music/track_NN.res[/code], not looped; without a disc
## image it notes that there is no music and writes none. Nothing else is
## saved, since the game finds a track by its number.

## The disc's audio tracks, one row each: number, name, sectors, frames and PCM digest.
const FACTS: String = "res://archive/import/disc_tracks.tsv"
const CHUNK_SECTORS: int = 1024


func step_name() -> String:
	return "music"


func phases() -> PackedStringArray:
	return PackedStringArray([PHASE_RAW])


func run(context: ImportContext, _phase: String) -> void:
	var expected: Dictionary[int, String] = _expected_digests(context)
	var pending: Array[int] = []
	for track: int in expected:
		if context.force_music or not FileAccess.file_exists(context.music_path(track)):
			pending.append(track)
	if pending.is_empty():
		return
	if context.disc.is_empty() and context.runtime:
		context.note("music: no disc image supplied, so the import has no music")
		return
	if context.scratch.is_empty() and not context.runtime:
		context.report("music: no scratch folder for decoded tracks")
		return
	if context.disc.is_empty():
		context.report("music: no disc image supplied (--disc or FROGGER_DISC)")
		return
	var disc: DiscAudio = DiscAudio.open(context.disc)
	if not disc.error.is_empty():
		context.report("music: %s" % disc.error)
		return
	if disc.tracks.size() - 1 != expected.size():
		context.report("music: the disc has %d audio tracks, the facts list %d" % [disc.tracks.size() - 1, expected.size()])
		return
	if not context.runtime:
		DirAccess.make_dir_recursive_absolute(context.scratch)
	for at: int in pending.size():
		if context.is_cancelled():
			return
		context.advance(at, pending.size())
		var track: int = pending[at]
		var row: DiscAudio.Track = disc.track(track)
		if row == null or row.mode != DiscAudio.MODE_AUDIO:
			context.report("music: disc track %d is not an audio track" % track)
			continue
		var digest: String = _save_stream(context, disc, row) if context.runtime else _decode(context, disc, row)
		if digest.is_empty():
			continue
		if digest != expected[track]:
			context.report("music: track %d PCM sha256 %s differs from the facts' %s" % [track, digest, expected[track]])


func _expected_digests(context: ImportContext) -> Dictionary[int, String]:
	var result: Dictionary[int, String] = {}
	var text: String = FileAccess.get_file_as_string(FACTS)
	if text.is_empty():
		context.report("music: cannot read %s" % FACTS)
		return result
	for line: String in text.split("\n", false):
		if line.begins_with("#"):
			continue
		var columns: PackedStringArray = line.split("\t")
		result[columns[0].to_int()] = columns[6]
	return result


## Track [param row] of [param disc] as an [AudioStreamWAV]: 16-bit stereo at
## [constant DiscAudio.SAMPLE_RATE], not looped. Returns null, with the reason
## in [param problems], when the image ends inside the track.
## [param digest_out] receives the SHA-256 of the PCM as hex.
static func track_stream(disc: DiscAudio, row: DiscAudio.Track, problems: PackedStringArray,
		digest_out: PackedStringArray = PackedStringArray()) -> AudioStreamWAV:
	var image: FileAccess = FileAccess.open(disc.mdf_path, FileAccess.READ)
	if image == null:
		problems.append("cannot read %s" % disc.mdf_path)
		return null
	var size: int = row.byte_length()
	var pcm := PackedByteArray()
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	image.seek(row.start_offset)
	while pcm.size() < size:
		var chunk: PackedByteArray = image.get_buffer(mini(size - pcm.size(), CHUNK_SECTORS * DiscAudio.SECTOR_BYTES))
		if chunk.is_empty():
			break
		hashing.update(chunk)
		pcm.append_array(chunk)
	image.close()
	if pcm.size() != size:
		problems.append("track %d read %d of %d bytes" % [row.number, pcm.size(), size])
		return null
	digest_out.append(hashing.finish().hex_encode())
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = DiscAudio.SAMPLE_RATE
	stream.stereo = true
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = pcm
	return stream


func _save_stream(context: ImportContext, disc: DiscAudio, row: DiscAudio.Track) -> String:
	var problems := PackedStringArray()
	var digest := PackedStringArray()
	var stream: AudioStreamWAV = track_stream(disc, row, problems, digest)
	if stream == null:
		context.report("music: %s" % "; ".join(problems))
		return ""
	stream.resource_name = "track_%02d" % row.number
	if not context.save_resource(stream, context.music_path(row.number)):
		return ""
	return digest[0]


func _decode(context: ImportContext, disc: DiscAudio, row: DiscAudio.Track) -> String:
	var path: String = context.music_scratch_wav(row.number)
	var image: FileAccess = FileAccess.open(disc.mdf_path, FileAccess.READ)
	var output: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if image == null or output == null:
		context.report("music: cannot decode track %d to %s" % [row.number, path])
		return ""
	var size: int = row.byte_length()
	var header := PackedByteArray()
	header.resize(44)
	header.encode_u32(0, 0x46464952)
	header.encode_u32(4, 36 + size)
	header.encode_u32(8, 0x45564157)
	header.encode_u32(12, 0x20746D66)
	header.encode_u32(16, 16)
	header.encode_u16(20, 1)
	header.encode_u16(22, 2)
	header.encode_u32(24, DiscAudio.SAMPLE_RATE)
	header.encode_u32(28, DiscAudio.SAMPLE_RATE * 4)
	header.encode_u16(32, 4)
	header.encode_u16(34, 16)
	header.encode_u32(36, 0x61746164)
	header.encode_u32(40, size)
	output.store_buffer(header)
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	image.seek(row.start_offset)
	var remaining: int = size
	while remaining > 0:
		var chunk: PackedByteArray = image.get_buffer(mini(remaining, CHUNK_SECTORS * DiscAudio.SECTOR_BYTES))
		if chunk.is_empty():
			break
		hashing.update(chunk)
		output.store_buffer(chunk)
		remaining -= chunk.size()
	image.close()
	output.close()
	if remaining != 0:
		context.report("music: track %d read %d of %d bytes" % [row.number, size - remaining, size])
		return ""
	return hashing.finish().hex_encode()
