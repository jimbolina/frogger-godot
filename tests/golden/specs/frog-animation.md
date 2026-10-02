# Frog animation component facts

`tools/make_golden_frog_animation.py` extracts the 35 named script programs,
request flags and 34 action names from frozen source. It checks this catalog
against the compiled C tables, then independently interprets those programs.
The C adapter calls the actual initialization, request, script update, action
setter and animation environment update functions. Expected values never come
from GDScript.

The synthetic model supplies 34 virtual cel counts: `3 + action_index % 3`.
These are authored fixture metadata, not retail counts. Five scenarios cover
ordinary hop queues, delayed falling requests, death locking and reinitializing,
idle random scripts including the fifth jungle idle selection, and slipping
requests that are binned while another animation plays.

`frog_animation_components.csv` has 320 ordered script/pose phase records.
Its 29 columns contain scenario, tick, phase, script IDs and word offsets,
queue/restore state, timers, action/cel/count, environment flags/update count,
input idle timer, shared idle counter, RNG state and loop/queue/restore cursors.
The header defines their exact order. Pointer identities are converted to
program IDs and offsets. `frog_animation_catalog.json` contains text facts only.

The pose phase temporarily clears `MR_ANIM_ENV_UPDATE` to omit renderer
transform construction, then restores it before recording. Actual cel stepping
still runs. This adapter uses no animation-rule or effect-factory wrappers.
It proves component behavior with supplied metadata, not renderer pose geometry
or whole-engine random draw ordering.

Regenerate with `tools/build_animation_oracle.ps1` into an external directory,
then run the Python generator with `--c-oracle PATH`; `--verify` checks existing
facts without rewriting them. `--runtime-catalog` also writes the named runtime
catalog. Source-link provenance and binary hashes are saved beside the adapter.
