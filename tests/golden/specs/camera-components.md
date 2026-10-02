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
The [terrain component contract](../../../docs/reference/terrain-trace-oracle.md)
documents frozen linkage/provenance and omitted broader systems. These camera
updates are separate component fixtures, not a coupled full gameplay step.
