extends AssetTest
## Every audio track of the disc is an Ogg Vorbis file under assets/audio/music
## as long as disc_tracks.tsv says (Vorbis is lossy, so only the length is
## checked), and every track the executable's music list plays is present.

const FAMILY: String = "disc_tracks"
const RATE: float = 44100.0
const TOLERANCE: float = 0.001


## The committed Ogg of disc track [param track].
static func ogg_path(track: int) -> String:
	return "%s/audio/music/track_%02d.ogg" % [ASSETS, track]


func test_every_disc_track_is_an_ogg_of_its_length() -> void:
	var rows: Array[PackedStringArray] = fact_rows("disc_tracks.tsv")
	assert_eq(rows.size(), 31)
	var failures := PackedStringArray()
	for row: PackedStringArray in rows:
		var path: String = ogg_path(int(row[0]))
		var asset: String = path.trim_prefix("res://")
		var stream: AudioStreamOggVorbis = load(path) as AudioStreamOggVorbis if ResourceLoader.exists(path) else null
		if stream == null:
			failures.append("%s does not load" % asset)
			continue
		var seconds: float = float(int(expected(asset, FAMILY, "frames", row[4]))) / RATE
		if absf(stream.get_length() - seconds) > TOLERANCE:
			failures.append("%s lasts %.4f s, not %.4f" % [asset, stream.get_length(), seconds])
		if stream.loop:
			failures.append("%s has a baked loop" % asset)
	assert_eq(failures, PackedStringArray())
	assert_eq(files_under(ASSETS.path_join("audio/music"), ".ogg").size(), rows.size(), "one Ogg per track")


func test_every_music_list_track_is_present() -> void:
	var missing := PackedStringArray()
	for row: PackedStringArray in fact_rows("exe_music.tsv"):
		if not ResourceLoader.exists(ogg_path(int(row[2]))):
			missing.append("%s plays track %s" % [row[1], row[2]])
	assert_eq(missing, PackedStringArray())
