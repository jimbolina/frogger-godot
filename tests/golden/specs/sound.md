# Logical sound and pickup facts

Sound playback remains deferred. These families verify gameplay-visible
allocation, RNG and lifetime decisions without rendering audio.

- `synthetic/bonus_fly.json`: generic pickup reward IDs, source frame narrowing,
  bobbing, stopped movement, active/absent voice pitch gates and ordered RNG.
  Reproduce with `python3 tools/make_golden_bonus_fly.py`.
- `synthetic/sound_bank.json`: independent synthetic Windows header rows,
  present/absent spans, 8/16-bit sample counts and edited rates. Reproduce with
  `python3 tools/make_golden_sound_bank.py`.
- `synthetic/logical_sound.json`: independent frozen C/native single, repeat and
  looped voice lifetimes; first-update protection, pitch bend, allocation
  pressure, identifiers and RNG. Reproduce with
  `python3 tools/make_golden_logical_sound.py`.
- `pc-retail-v3.0e/sound_tables.json`: executable bank/group/sample/music-pitch
  metadata, initialization code SHA-256 and Windows bank duration facts.
  Reproduce with `python3 tools/make_golden_sound_tables.py --data-dir <retail>`.
  The independent Python reader uses supplied EXE/MWD bytes and writes only
  decoded facts and hashes. No retail bytes belong in the repository.

Focused checks use the prescribed test wrapper with `-gselect=bonus_fly`,
`-gselect=sound_bank`, `-gselect=logical_sound`, or `-gselect=retail_sound`.
For each family, change one expected scalar, require a failing assertion,
restore the original facts and rerun. Keep logs and saved assets external.

The generic fly's moving object initially has no voice. Voice allocation uses
source group order and available slots; proximity alone is insufficient to
permit pitch RNG. Logical moving owners are copied with the gameplay candidate,
so later failure cannot consume random draws or publish allocations. Additional
component checks cover latest-created moving-object priority, radius exit,
reallocation, stale voice-generation tags and detached mutation.
