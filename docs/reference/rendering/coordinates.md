# Coordinates and projection

- A game position `(x, y, z)` is drawn at Godot `(x, -y, -z) / 256`. One grid square is one Godot unit. The game's y points down; this is a half turn about the x axis, not a mirror image, so polygons keep their stored corner order and Godot's back-face culling works as the original's did. `GameSpace` is the only place that converts.
- Terrain geometry and camera translations keep original whole units; frog
  positions and per-tick velocities use signed 16.16. `GameSpace.fixed_position`
  converts those values for drawing without dropping fractional game units.

Animation bases use `C * basis * C`, translations `C * translation / 256`, where `C = diag(1,-1,-1)`. Part transforms sit below model placement.

## Map projection

Gameplay C uses projection distance 256; map metadata's 192 is unused. The
committed `map_slice` pictures instead use the viewport default 1000, a fixed
bounds-midpoint camera and partial group selection. See the
[map reference preset](../data/maps.md#camera-and-reference-captures). At 640x480,
vertical FOV is `2 * atan(240 / effective_H)`. The frozen viewport aspect
matrix scales X by 640/320=2 and Y by 480/256=1.875 (`MR_VIEW.C`).
The frozen MR_VIEW translation unit does not include SYSTEM.H, so its
`MR_MODE_NTSC` is undefined (confirmed with its exact build include paths).
Nominal H=1000 therefore means effective X/Y projections 2000/1875.
The reference preset applies a 0.9375 clip-space Y scale after the H=2000
perspective projection. The default inspection preview
uses effective_H=256. Original retail gameplay projection has not been
independently verified. The standalone animation driver also has a different
calibration; see [animation captures](../data/animation.md#reference-capture-setup).
