#!/usr/bin/env python3
"""Independent cave omni-light shape facts.

The retail cave terrain (mapdisp.c) replaces Gouraud colours with a grey
from the squared distance t between vertex and frog, in game units: 128
inside the minimum squared radius, 0 beyond the maximum, and in between
128 - ((factor * (t - min)) >> 16) with factor = (128 << 16) // (max - min),
clamped to 0..128; equal radii cut off hard at the maximum. The terrain
multiplies its texel by that grey over 255, doubled and clamped at one, so
the ramp compared here is min(2 * grey / 255, 1).

Godot's omni light with attenuation exponent zero weights its light by the
window (1 - (d / R) ^ 4) ^ 2 inside range R and zero outside. Distances in
Godot units are game units over 256.

The fit compares energy * window against the ramp on FIT_RINGS rings evenly
spaced in squared distance (equal area each) over FIT_REACH times the
maximum squared radius: ring k sits at the integer t_k = (T * (2k + 1)) //
(2 * FIT_RINGS) with T = FIT_REACH * max. The least-squares energy is
sum(w * g) / sum(w * w), zero when the window is zero on every ring.

Mode EXACT_EDGE puts the range at the ramp's edge, sqrt(max) / 256.
Mode FITTED_RANGE scales that edge by the factor in [1, 2] that maximises
sum(w * g) ^ 2 / sum(w * w) for the ramp whose minimum lies the C band
(0x100000) inside the maximum (1 when that underflows), found by
SCALE_STEPS golden-section steps from the bracket [1, 2]; the energy is then
fitted against the given radii at that range. The inner radius is
sqrt(min) / 256.

Fixtures are initial radii (ENTSTRCavCreateFroggerLight: max = (r << 8)^2,
min = max - 0x100000 or 1 on underflow, 32-bit unsigned) for several
maximum radii in grid squares, plus croak samples where both radii have
grown by six steps of max // 6 (FrogUpdateCroak), wrapping at 32 bits.
"""
import argparse
import json
import math
from pathlib import Path

SCHEMA = 'cave-light-v1'
TOLERANCE = 1e-4
UNITS_PER_SQUARE = 256
BAND = 0x100000
UNSIGNED32 = 0xFFFFFFFF
FIT_RINGS = 512
FIT_REACH = 4
SCALE_LOW = 1.0
SCALE_HIGH = 2.0
SCALE_STEPS = 32
INFLATE_TIME = 6
MODES = ('exact_edge', 'fitted_range')
FRACTIONS = (0.25, 0.5, 0.75, 1.0, 1.1)
RADII = (1, 3, 4, 5, 8, 12, 255)
CROAK_RADII = (1, 4, 8, 12)


def initial_radii(radius):
    maximum = ((radius << 8) * (radius << 8)) & UNSIGNED32
    return band_minimum(maximum), maximum


def band_minimum(maximum):
    minimum = (maximum - BAND) & UNSIGNED32
    return 1 if minimum > maximum else minimum


def croaked(minimum, maximum):
    rate = maximum // INFLATE_TIME
    for _ in range(INFLATE_TIME):
        maximum = (maximum + rate) & UNSIGNED32
        minimum = (minimum + rate) & UNSIGNED32
    return minimum, maximum


def grey(t, minimum, maximum):
    value = 128
    if t > maximum:
        value = 0
    elif t >= minimum and maximum > minimum:
        factor = (128 << 16) // (maximum - minimum)
        value = 128 - ((factor * (t - minimum)) >> 16)
    return min(max(value, 0), 128)


def ramp(t, minimum, maximum):
    return min(2.0 * grey(t, minimum, maximum) / 255.0, 1.0)


def window(distance, reach):
    if reach <= 0.0 or distance >= reach:
        return 0.0
    ratio = distance / reach
    quartic = ratio * ratio
    quartic = quartic * quartic
    return (1.0 - quartic) * (1.0 - quartic)


def edge(maximum):
    return math.sqrt(maximum) / UNITS_PER_SQUARE


def sums(minimum, maximum, reach):
    total = FIT_REACH * maximum
    lit = 0.0
    weight = 0.0
    for ring in range(FIT_RINGS):
        t = (total * (2 * ring + 1)) // (2 * FIT_RINGS)
        w = window(math.sqrt(t) / UNITS_PER_SQUARE, reach)
        lit += w * ramp(t, minimum, maximum)
        weight += w * w
    return lit, weight


def fit_energy(minimum, maximum, reach):
    lit, weight = sums(minimum, maximum, reach)
    return lit / weight if weight > 0.0 else 0.0


def explained(minimum, maximum, reach):
    lit, weight = sums(minimum, maximum, reach)
    return lit * lit / weight if weight > 0.0 else 0.0


def fitted_scale(maximum):
    minimum = band_minimum(maximum)
    base = edge(maximum)
    ratio = (math.sqrt(5.0) - 1.0) / 2.0
    low, high = SCALE_LOW, SCALE_HIGH
    left = high - ratio * (high - low)
    right = low + ratio * (high - low)
    left_score = explained(minimum, maximum, base * left)
    right_score = explained(minimum, maximum, base * right)
    for _ in range(SCALE_STEPS):
        if left_score >= right_score:
            high = right
            right = left
            right_score = left_score
            left = high - ratio * (high - low)
            left_score = explained(minimum, maximum, base * left)
        else:
            low = left
            left = right
            left_score = right_score
            right = low + ratio * (high - low)
            right_score = explained(minimum, maximum, base * right)
    return (low + high) / 2.0


def range_of(maximum, mode):
    if maximum <= 0:
        return 0.0
    if mode == 'exact_edge':
        return edge(maximum)
    return edge(maximum) * fitted_scale(maximum)


def shape(minimum, maximum, mode):
    reach = range_of(maximum, mode)
    energy = fit_energy(minimum, maximum, reach) if maximum > 0 else 0.0
    samples = []
    for fraction in FRACTIONS:
        distance = fraction * reach
        t = math.floor((distance * UNITS_PER_SQUARE) ** 2)
        samples.append(dict(
            fraction=fraction,
            distance_r2=t,
            window=round(window(distance, reach), 9),
            lit=round(energy * window(distance, reach), 9),
            ramp=round(ramp(t, minimum, maximum), 9),
        ))
    return dict(range=round(reach, 9), energy=round(energy, 9), samples=samples)


def fixture(name, minimum, maximum):
    return dict(
        name=name,
        min_r2=minimum,
        max_r2=maximum,
        inner=round(math.sqrt(minimum) / UNITS_PER_SQUARE, 9),
        modes={mode: shape(minimum, maximum, mode) for mode in MODES},
    )


def fixtures():
    rows = []
    for radius in RADII:
        minimum, maximum = initial_radii(radius)
        rows.append(fixture(f'radius_{radius}', minimum, maximum))
    for radius in CROAK_RADII:
        minimum, maximum = croaked(*initial_radii(radius))
        rows.append(fixture(f'radius_{radius}_croaked', minimum, maximum))
    return rows


def facts():
    return dict(
        schema=SCHEMA,
        tolerance=TOLERANCE,
        fit_rings=FIT_RINGS,
        fit_reach=FIT_REACH,
        scale_steps=SCALE_STEPS,
        band=BAND,
        fixtures=fixtures(),
    )


def main():
    """Verify the committed facts by default; rewrite only with an explicit flag."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('output', type=Path)
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    text = json.dumps(facts(), indent=2) + '\n'
    if args.write:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding='utf-8')
        print(f'Cave light facts written to {args.output}')
        return
    if not args.output.exists() or args.output.read_text(encoding='utf-8') != text:
        raise SystemExit(f'Cave light facts in {args.output} differ; use --write only to deliberately regenerate')
    print('Cave light facts verified')


if __name__ == '__main__':
    main()
