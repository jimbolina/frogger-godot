# Gameplay projection corpus

`synthetic/gameplay_projection.csv`:40 asset-free rows, independently generated
by `tools/golden/make_golden_gameplay_projection.py`, verified against the compiled
frozen camera/view/GTE functions using `tools/oracles/gameplay_projection_oracle.c`.
No Godot output is an input to the generator.

Rows 0-9,10-19,20-29,30-39 use camera source positions
(0,-500,-500),(-500,-500,0),(0,-1000,-100),(200,-400,400), respectively.
Target is origin except reset target (0,100,0). Each pose has ten points:
origin; four +/-128 terrain corners; frog-height points Y=-64/-128;
neighbor centers Z=256,X=256,Z=-256. Point IDs form the comparison mask.

First 40 columns are exact decimal scalar facts: pose/point IDs; viewport/H;
fixed12 aspects; source/vertex positions; row-major aspect-render matrix;
separately quantized translation; view coordinates; clamped depth; C integer
screen position; row-major unscaled camera basis. Next four are ideal-double
screen coordinates and independent X/Y pixel bounds. Source/world units are
whole integers; basis scale 4096; pixels use640x480 viewport coordinates.

The generator computes signed C truncation and arithmetic shifts explicitly.
Native camera basis normalization follows Godot4.5 Gram-Schmidt in Python;
bounds use per-point basis perturbation, a counted 128-operation float32
rounding budget and ratio perturbation with reduced denominator. Bounds are
for these fixtures, not a universal image similarity allowance. All source
scalar columns must match C exactly; candidate native projection falls within
its own row's X/Y bounds. See gameplay-projection reference for source anchors
and capture limitations. New family requires deliberate-break/restoration.
