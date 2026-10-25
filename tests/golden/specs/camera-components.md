# Default camera components

`synthetic/camera_components.csv` contains 327 independent text fact records.
Eight scenarios call the frozen engine's actual `ResetCamera`/`UpdateCamera`
without rendering or loading assets. Python independently derives every field
and requires exact C overlap before generating or verifying this family.

The first 21 fields are scenario, tick, mode, offset move timer, twist counter,
tracked XYZ origin, current source XYZ offset, current target XYZ offset,
world source XYZ, world target XYZ and controller-up quadrant. The final three
fields retain C's entity-dismount Y-theta current/delta/destination scalars;
they remain zero because these fixtures contain no entities. A gameplay API
test covering the first 21 fields makes no claim about those dismount scalars.
The last nine fields are camera flags, shake timer, X/Y shake amplitudes,
X/Y shake frequencies, source RNG seed and the two shake draws. Gameplay
camera tests compare shake state and applied positions; the source seed/draw
facts support setup's explicit shared RNG boundary.

Fixtures use authored GENE default offsets `(0,-500,-500)` and `(0,0,0)`:

* Scenario 0: 122 updates after reset, frog origin zero and external start timer
  `max(90-tick,0)`. Covers hold, 30-call fixed sweep and follow transition.
* Scenario 1: 16 follow updates with tracked origin initially zero, frog origin
  `(100,-200,60)` at tick 0 and `(200,-260,100)` thereafter. Covers signed XYZ
  damping, minimum XZ snap threshold and 24-unit Y rate.
* Scenarios 2/3: 16 follow updates from zero origin, one clockwise or
  anticlockwise quadrant, with the real input path's eight-call offset timer.
  Covers intermediate integer rotations, completion and controller-up ties.
* Scenario 4: 47 follow updates, death destination offset `(0,-1000,-100)` and
  zero target offset with the source's 45-call transition timer.
* Scenario 5: 16 fixed updates after one follow update from tracked zero toward
  frog `(10,-20,30)`. Tracked `(5,-20,15)` and the matrix remain frozen.
* Scenarios 6/7: 47 follow/fixed updates with actual `ShakeCamera`, amplitude
  `MR_OBJ_STATIC` (128), duration 45, frequency 0x5000 and source seed 1.
  Independent 32-bit LCG draws 16838/5758 leave seed 2524885223. These fixtures
  compare shake decay and fixed-camera accumulation as separate source rules.

World source comes from the actual C camera matrix translation. World target
is reconstructed from the exact component inputs: startup/sweep origin plus
stored target offset, or follow tracked origin (all follow target offsets are
zero); fixed cameras retain their initial tracked target. No general rotated
target, zone or entity reconstruction is claimed. Shake source translation is
actual C output, with Python independently deriving its integer matrix offsets.
Frozen `MRStub_GpuInit(NULL,0)` initializes the actual 4096-entry trig
table without creating a display. Python uses the documented libm `lround`
equivalent and integer fixed12 rotation, truncating division and source damping.

```powershell
tools/build_terrain_oracle.ps1 -OutputDirectory <external-folder> -Run -Camera
python tools/make_golden_camera.py --c-oracle <external-folder>/terrain_oracle.exe --verify
```

For deliberate-break validation, increment a committed source-X fact, require
generation verification or its Godot comparison to fail, restore and pass.
The [terrain component contract](../../../docs/reference/testing/terrain-trace-oracle.md)
documents frozen linkage/provenance and omitted broader systems. These camera
updates are separate component fixtures, not a coupled full gameplay step.

## Active camera zones

`synthetic/camera_zones.json` and `pc-retail-v3.0e/camera_zones.json` use
`camera-zones-v1`: ordered cases contain source/target defaults, initial yaw,
startup mode, ordered zone records, prescribed per-tick cell/world inputs and
expected camera/selection facts. The fixtures contain decoded numbers only.
Frames supply freeze-selection, manual-turn, fixed-mode and start-timer stimuli.
Expected fields include frog zone/region, consumed camera zone, timers/twist,
entity angle, tracked/source world positions, current/next offsets, fixed12 basis,
controller directions and modification rotation. No rendered transform supplies
expected values.

`make_golden_camera_zones.py` independently implements frozen zone retention,
integer camera transitions, absolute Y and manual controls. It compares every
represented field with `camera_zone_oracle.h`, linked through the existing
terrain adapter to unchanged frozen `UpdateFrogCameraZone`, `ControlFrog` and
`UpdateCamera`. The adapter starts with no prior controller mapping during START;
FOLLOW fixtures initialize cardinal mappings. Manual-turn fixtures exercise all
four offset pairs through real control, including the frozen build's pointer-
stride compatibility fix described in the [camera contract](../../../docs/reference/gameplay/gameplay-camera.md#frozen-build-compatibility).

Synthetic cases cover overlap/region retention, gaps and signed/inverted bounds,
absolute transfer/exit, forced turns, startup, frozen selection, fixed mode,
manual and semiforced controls. Retail generation independently reads the
player's archive and JUN1 GENE/ZONE records. Its two probe sequences use Y=0,
40 ticks per cell, and a fresh camera per sequence. The second starts with a
180-degree modification matrix. These are camera stimuli, not admitted frog routes.

```powershell
tools/build_terrain_oracle.ps1 -OutputDirectory <external-oracle>
python -B tools/make_golden_camera_zones.py --c-oracle <external-oracle>/terrain_oracle.exe --evidence <external-evidence> --verify
python -B tools/make_golden_camera_zones.py --c-oracle <external-oracle>/terrain_oracle.exe --evidence <external-evidence> --data-dir <game-folder> --output tests/golden/pc-retail-v3.0e/camera_zones.json --verify
```

Omit `--verify` to regenerate. For each file, increment an expected source-world
X fact, require verification to fail, restore the original and verify again.
Both text corpora run asset-free; a separately named retail test also compares
supplied setup and the complete inspection against the retail facts.
