# Coordinates and projection

- Fixed in P4: a game position `(x, y, z)` is drawn at Godot `(x, -y, -z) / 256`. One grid square is one Godot unit. The game's y points down; this is a half turn about the x axis, not a mirror image, so polygons keep their stored corner order and Godot's back-face culling works as the original's did. `GameSpace` is the only place that converts.
- Game logic keeps the original whole units. Only what is drawn is converted.

Animation bases use `C * basis * C`, translations `C * translation / 256`, where `C = diag(1,-1,-1)`. Part transforms sit below model placement.

## Map projection: unresolved for P6

The C source and reference map pictures use projection distance 256. It has not been independently checked against the retail game. The standalone animation driver has a different calibration; see [animation reference captures](animation.md#reference-capture-setup).
