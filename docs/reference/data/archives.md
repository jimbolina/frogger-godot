# Archives

Retail counts below refer to `pc-retail-v3.0e`. See [source locations](../sources.md).

| Fact | Value |
|---|---|
| Index entries | 746 |
| WADs | 84 |
| Compressed resources | 210 |
| Resources stored directly in the archive | 312 |
| WAD children | 2,890, of which 434 are distinct |

- No WAD child is compressed on its own.
- The index inside the executable is the authoritative one. FrogLord writes the index back into the executable; the standalone `.MWI` file is a copy.
- Always resolve archive offsets through the loaded index. FrogLord moves and resizes files when it saves.

Schemas and regeneration: [archive golden specification](../../../tests/golden/specs/archives.md).

## Windows sound-bank metadata

`SoundBankHeader` follows FrogLord's `SCWindowsSoundBankHeader`: a signed count
followed by 28-byte rows containing presence, PCM body offset and size, two
required values of one, sample rate and bit depth. Presence means exactly one.
The reader retains global sound IDs, validates present spans against the supplied
body, and supports mono 8-bit and 16-bit metadata. `SoundBankSetup` loads the
selected archive header/body pair and retains no PCM or playback objects.

Logical duration setup requires the frozen reference's verified 16-bit format.
It derives sample frames from body size, while preserving the supplied rate as
metadata. The frozen native cursor uses a fixed 11025 Hz reference at note 60,
a 44100 Hz output rate, and 735 output samples per stepped frame; it does not use
the header rate to advance voices. This explicit reference choice also applies
to the six retail generic samples whose headers say 22050 Hz. It is independent
of device availability, rendering rate and presentation completion.

## Sound playback

Presentation plays the committed logical voices; playback never feeds back into
gameplay or the random stream. `SoundBankSetup` keeps the PCM body and
`AudioResources` slices each present sample (8-bit becomes signed 16-bit) into a
mono 11025 Hz stream, looped for LOOPED and REPEAT samples. `SoundVoiceView`
diffs consecutive states: a new voice identifier starts a sample at
`AudioResources.pitch_scale`, a pitch change bends it, and a killed voice or a
looping voice that is no longer playing stops. One-shot samples finish their tail
rather than being cut at the logical end. Fixed voices play at the sample's
maximum volume. Moving voices take left/right levels from the frozen
`MRSNDUpdateMovingSounds` fade and soft pan using the frog's matrix; doppler is
the committed voice pitch. Godot players have no pan, so each of the 24 voices
has a runtime bus with a panner that feeds `Sfx`. The default effect volume is
79 of 127. Buses are Master, Sfx and Music.

Music is the Redbook track named by the level's `MusicTable` entry. `DiscAudio`
parses the `.mds` table (as the frozen stub does) and reads one audio track from
the `.mdf` at a time as raw 16-bit stereo 44100 Hz; the disc is located by
`--disc=` or `FROGGER_DISC`. `MusicFiles` is the fallback for loose
`track_NN` files. Frozen C and retail differ in no recorded sound rule here, but
the panner gain curve and the REPEAT retrigger gap (not reproduced) are
unmeasured against the original. Golden facts are in the
[sound specification](../../../tests/golden/specs/sound.md#sound-playback).
