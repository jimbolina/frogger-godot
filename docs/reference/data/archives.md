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
