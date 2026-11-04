#!/usr/bin/env python3
"""Independent modern scene lighting from synthetic C map light records.

The C viewport recipe (API.SRC/MR_LIGHT.C, MR_VIEW.C, mapload.C) reduces a
map's light records to one ambient colour and up to three parallel slots:
records are visited last to first because viewport registration prepends
them; only enabled (category 1) ambient (type 1) and parallel (type 2)
records count; ambient bytes accumulate times 16 and narrow to a wrapping
byte after the shift by four; parallel colours are bytes times 16 and their
directions are normalised to 4.12 fixed point. Game space (x right, y down,
z away) turns into Godot space as (x, -y, -z).

The scene mapping turns stored fractions a = A/4096 and p = P/4096 into
linear light: ambient gamma(a), each parallel slot gamma(a + p) - gamma(a)
floored at zero, with gamma(x) = clamp(x, 0, 1) ** 2.2. A slot's energy is
its largest channel times LAMBERT_SCALE, and its colour is the slot divided
by that channel in sRGB (white when the slot is black). With shadows on,
the slot of largest Rec. 709 luminance casts, the lowest index on ties.
"""
import argparse
import json
import math
from pathlib import Path

SCHEMA = 'scene-lighting-v1'
GAMMA = 2.2
LAMBERT_SCALE = 1.0
STORED_ONE = 4096
TOLERANCE = 1e-4
LUMINANCE = (0.2126, 0.7152, 0.0722)
AMBIENT, PARALLEL, POINT = 1, 2, 3
ENABLED, DISABLED = 1, 0
SLOTS = 3


def record(light_type, category, colour, direction=(0, 0, 0)):
    return dict(light_type=light_type, category=category, colour=list(colour), direction=list(direction))


FIXTURES = [
    dict(name='org1_like', shadows=True, lights=[
        record(AMBIENT, ENABLED, (73, 73, 73)),
        record(PARALLEL, ENABLED, (255, 255, 255), (-2246, 3335, 781)),
    ]),
    dict(name='org1_like_without_shadows', shadows=False, lights=[
        record(AMBIENT, ENABLED, (73, 73, 73)),
        record(PARALLEL, ENABLED, (255, 255, 255), (-2246, 3335, 781)),
    ]),
    dict(name='later_record_takes_first_slot', shadows=True, lights=[
        record(AMBIENT, ENABLED, (64, 64, 64)),
        record(PARALLEL, ENABLED, (200, 180, 40), (0, 4096, -1000)),
        record(PARALLEL, ENABLED, (40, 80, 160), (1000, 2000, 3000)),
    ]),
    dict(name='four_parallel_three_slots', shadows=True, lights=[
        record(AMBIENT, ENABLED, (32, 32, 48)),
        record(PARALLEL, ENABLED, (255, 0, 0), (100, 4000, 100)),
        record(PARALLEL, ENABLED, (0, 120, 0), (-3000, 1000, 0)),
        record(PARALLEL, ENABLED, (0, 0, 200), (0, 1000, 3000)),
        record(PARALLEL, ENABLED, (90, 90, 90), (2000, 2000, -2000)),
    ]),
    dict(name='disabled_records_skipped', shadows=True, lights=[
        record(AMBIENT, ENABLED, (64, 64, 64)),
        record(AMBIENT, DISABLED, (100, 0, 0)),
        record(PARALLEL, ENABLED, (128, 160, 192), (500, 3000, 1500)),
        record(PARALLEL, DISABLED, (255, 255, 255), (0, 4096, 0)),
    ]),
    dict(name='point_light_ignored', shadows=True, lights=[
        record(AMBIENT, ENABLED, (48, 48, 48)),
        record(POINT, ENABLED, (255, 255, 0), (0, 4096, 0)),
        record(PARALLEL, ENABLED, (160, 160, 160), (-1000, 3500, -800)),
    ]),
    dict(name='ambient_byte_wrap', shadows=True, lights=[
        record(AMBIENT, ENABLED, (200, 10, 128)),
        record(AMBIENT, ENABLED, (100, 10, 128)),
        record(PARALLEL, ENABLED, (64, 64, 64), (0, 3000, 2000)),
    ]),
    dict(name='saturation', shadows=True, lights=[
        record(AMBIENT, ENABLED, (192, 192, 192)),
        record(PARALLEL, ENABLED, (128, 255, 32), (1200, 3600, -900)),
    ]),
    dict(name='straight_down', shadows=True, lights=[
        record(AMBIENT, ENABLED, (64, 64, 64)),
        record(PARALLEL, ENABLED, (255, 255, 255), (0, 4096, 0)),
    ]),
    dict(name='no_lights', shadows=True, lights=[]),
]


def round_half_away(value):
    """C-style rounding of a non-integer quotient, refusing near-half ambiguity."""
    fraction = abs(value) - math.floor(abs(value))
    if abs(fraction - 0.5) < 1e-3:
        raise SystemExit(f'Fixture direction component {value} is too close to a rounding half')
    return int(math.copysign(math.floor(abs(value) + 0.5), value))


def fixed_direction(direction):
    """Direction normalised to 4.12 fixed point; zero stays zero."""
    length = math.sqrt(sum(c * c for c in direction))
    if length == 0.0:
        return (0, 0, 0)
    return tuple(round_half_away(c * STORED_ONE / length) for c in direction)


def godot_forward(fixed):
    """Godot-space unit travel direction of a 4.12 game-space normal."""
    x, y, z = (fixed[0] / STORED_ONE, -fixed[1] / STORED_ONE, -fixed[2] / STORED_ONE)
    length = math.sqrt(x * x + y * y + z * z)
    return (x / length, y / length, z / length)


def viewport(lights):
    """Stored ambient and parallel slots, as the C viewport registers them."""
    ambient = [0, 0, 0]
    slots = []
    for light in reversed(lights):
        if light['category'] != ENABLED:
            continue
        if light['light_type'] == AMBIENT:
            ambient = [a + c * 16 for a, c in zip(ambient, light['colour'])]
        elif light['light_type'] == PARALLEL and len(slots) < SLOTS:
            slots.append((fixed_direction(light['direction']), [c * 16 for c in light['colour']]))
    ambient = [((a >> 4) & 255) * 16 for a in ambient]
    return ambient, slots


def gamma(x):
    return min(max(x, 0.0), 1.0) ** GAMMA


def linear_to_srgb(c):
    return 12.92 * c if c < 0.0031308 else 1.055 * c ** (1.0 / 2.4) - 0.055


def scene(fixture):
    stored_ambient, slots = viewport(fixture['lights'])
    a = [v / STORED_ONE for v in stored_ambient]
    ambient = [gamma(v) for v in a]
    expected_slots = []
    caster = -1
    brightest = -1.0
    for index, (fixed, colour) in enumerate(slots):
        parallel = [max(gamma(av + c / STORED_ONE) - g, 0.0) for av, c, g in zip(a, colour, ambient)]
        peak = max(parallel)
        light_colour = [linear_to_srgb(c / peak) for c in parallel] if peak > 0.0 else [1.0, 1.0, 1.0]
        luminance = sum(w * c for w, c in zip(LUMINANCE, parallel))
        if fixture['shadows'] and luminance > brightest:
            brightest = luminance
            caster = index
        expected_slots.append(dict(
            forward=[round(v, 9) for v in godot_forward(fixed)],
            colour=[round(v, 9) for v in light_colour],
            energy=round(peak * LAMBERT_SCALE, 9),
        ))
    return dict(ambient=[round(v, 9) for v in ambient], slots=expected_slots, caster=caster)


def facts():
    return dict(
        schema=SCHEMA,
        gamma=GAMMA,
        lambert_scale=LAMBERT_SCALE,
        tolerance=TOLERANCE,
        fixtures=[dict(name=f['name'], shadows=f['shadows'], lights=f['lights'], expected=scene(f)) for f in FIXTURES],
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
        print(f'Scene lighting facts written to {args.output}')
        return
    if not args.output.exists() or args.output.read_text(encoding='utf-8') != text:
        raise SystemExit(f'Scene lighting facts in {args.output} differ; use --write only to deliberately regenerate')
    print('Scene lighting facts verified')


if __name__ == '__main__':
    main()
