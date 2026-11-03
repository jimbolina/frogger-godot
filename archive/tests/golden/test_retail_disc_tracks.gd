extends AssetTest
## Every audio track of archive/import/disc_tracks.tsv, the disc facts the
## importer checks each decoded track against, has its committed Ogg Vorbis
## file under assets/audio/music as long as the facts say. Vorbis is lossy, so
## only the length is compared; the PCM digest is checked when the importer
## decodes the disc.

const FAMILY: String = "disc_tracks"
const MusicStep := preload("res://archive/import/steps/music_step.gd")
const RATE: float = 44100.0
const TOLERANCE: float = 0.001


## The rows of the importer's disc facts, comment lines dropped.
static func track_rows() -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	for line: String in FileAccess.get_file_as_string(MusicStep.FACTS).split("\n", false):
		if not line.begins_with("#"):
			rows.append(line.split("\t"))
	return rows


func test_every_disc_track_is_an_ogg_of_its_length() -> void:
	var rows: Array[PackedStringArray] = track_rows()
	assert_eq(rows.size(), int(fact_values("asset_census.txt")["disc_audio_tracks"]))
	var failures := PackedStringArray()
	for row: PackedStringArray in rows:
		var path: String = "%s/audio/music/track_%02d.ogg" % [ASSETS, int(row[0])]
		var asset: String = path.trim_prefix("res://")
		var stream: AudioStreamOggVorbis = load(path) as AudioStreamOggVorbis if ResourceLoader.exists(path) else null
		if stream == null:
			failures.append("%s does not load" % asset)
			continue
		var seconds: float = float(int(expected(asset, FAMILY, "frames", row[4]))) / RATE
		if absf(stream.get_length() - seconds) > TOLERANCE:
			failures.append("%s lasts %.4f s, not %.4f" % [asset, stream.get_length(), seconds])
	assert_eq(failures, PackedStringArray())
