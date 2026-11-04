#!/usr/bin/env python3
"""Independent synthetic facts from frozen ent_cav.c/.h, score.C/.H, ENTITY.C and MR_SPRT.C."""
import argparse
import itertools
import json
import math
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools import REPO_ROOT

OUTPUT = REPO_ROOT / 'tests/golden/synthetic/cave.json'
U32 = 0xffffffff
BAND = 0x100000
SOURCES = {'firefly': (8, 250), 'light_5': (5 << 16, 0), 'light_8': (8 << 16, 0), 'super_light': (16 << 16, 0)}


def s32(value):
    """Narrow to MR_LONG with two's-complement wrap."""
    value &= U32
    return value - 0x100000000 if value & 0x80000000 else value


def c_div(numerator, denominator):
    """Signed C division truncating toward zero."""
    quotient = abs(numerator) // abs(denominator)
    return quotient if (numerator < 0) == (denominator < 0) else -quotient


def sine(angle):
    """rsin over 4096 units per turn, rounded half away from zero."""
    value = math.sin((angle % 4096) * math.tau / 4096) * 4096
    return math.floor(value + 0.5) if value >= 0 else math.ceil(value - 0.5)


def clamp_band(maximum):
    """Map_light_min_r2 follows maximum minus the band, reset to 1 when it wraps above."""
    minimum = (maximum - BAND) & U32
    return 1 if minimum > maximum else minimum


def light_create(case):
    """ENTSTRCavCreateFroggerLight's MR_ULONG precalculation and global seeding."""
    min_r2 = (((case['min_radius'] << 8) & U32) ** 2) & U32
    max_r2 = (((case['max_radius'] << 8) & U32) ** 2) & U32
    die = ((case['die_speed'] << 8) & U32) // 30
    die = ((die * die) & U32) >> 8
    return dict(min_r2=min_r2, max_r2=max_r2, die=die, map_max=max_r2, map_min=clamp_band(max_r2),
                debug_valid=case['min_radius'] > 1 and case['min_radius'] < case['max_radius'])


def light_decay(case):
    """ENTSTRCavUpdateFroggerLight with the light switch on and no special movement."""
    maximum, minimum = case['map_max'], case['map_min']
    if maximum > case['fl_max']:
        maximum = case['fl_max']
        minimum = clamp_band(maximum)
    if maximum > case['fl_min']:
        maximum = (maximum - case['die']) & U32
        minimum = clamp_band(maximum)
    return dict(map_max=maximum, map_min=minimum)


def light_add(case):
    """ADD_FROG_LIGHT (value << 16) and CavFireFlyCallBack's raw CAVE_FIRE_FLY_LIGHT."""
    step, score = SOURCES[case['source']]
    maximum, minimum = case['map_max'], case['map_min']
    for _ in range(case['repeats']):
        maximum = (maximum + step) & U32
        minimum = (minimum + step) & U32
    return dict(map_max=maximum, map_min=minimum, score_delta=score * case['repeats'])


def entity_fade(case):
    """FadeLiveEntity's cave branch followed by SetLiveEntityScaleColours for one viewport."""
    dx = s32(case['frog_x'] - case['entity_x'])
    dz = s32(case['frog_z'] - case['entity_z'])
    distance = ((dx * dx) & U32) + ((dz * dz) & U32) & U32
    low, high = case['map_min'], case['map_max']
    if distance <= low:
        colour = 0x80
    elif distance >= high:
        colour = 0
    else:
        offset = s32(distance - low)
        fall = c_div(0x80 << 16, s32(high - low))
        colour = max(0, 0x80 - (s32(offset * fall) >> 16))
    scaled, scale, sprite = False, [0, 0, 0], -1
    if not case['no_display']:
        if case['no_model']:
            if case['dont_fade'] == 0:
                sprite = min(128, colour << 2)
                scaled, scale = True, [sprite] * 3
        else:
            packed = ((colour << 16) + (colour << 8) + colour) & U32
            scaled, scale = True, [packed & 255, (packed >> 8) & 255, (packed >> 16) & 255]
    return dict(distance=distance, colour=colour, sprite=sprite, scaled=scaled, scale=scale)


def fat_fire_fly_bob(case):
    """ENTSTRCavUpdateFatFireFly bob on MRFrame_number and its single rand() call."""
    if case['stopped']:
        return dict(y=case['base_y'], draws=0)
    angle = (((case['uid'] & 7) << 7) + ((case['frame'] << 8) & U32)) & 0xfff
    return dict(y=s32(case['base_y'] + (sine(angle) >> 5)), draws=1)


def firefly_frame(updates):
    """Animlist_fire_fly through MRProcessSpriteAnim; age is the zero-based update index."""
    pc, count, speed, image, loop_pc = 0, 1, 1, -1, 0
    program = [('SETSPEED', 2), ('SETCOUNT', 0), ('SETIMAGE', 0), ('SETIMAGE', 1), ('LOOPBACK', None)]
    loop_count = 0
    for _ in range(updates + 1):
        count -= 1
        if count == 0:
            while True:
                opcode, operand = program[pc]
                more = True
                if opcode == 'SETSPEED':
                    speed, pc = operand, pc + 1
                elif opcode == 'SETCOUNT':
                    loop_count, pc = operand - 1, pc + 1
                    loop_pc = pc
                elif opcode == 'SETIMAGE':
                    image, pc, more = operand, pc + 1, False
                elif loop_count < 0:
                    pc = loop_pc
                elif loop_count:
                    loop_count, pc = loop_count - 1, loop_pc
                else:
                    pc += 1
                count = speed
                if not more:
                    break
    return image


def light_params():
    """Retail CAV1/CAV3/CAV4 operands plus synthetic band and wrap edges."""
    rows = [light_create(dict(min_radius=a, max_radius=b, die_speed=c)) for a, b, c in ((2, 4, 90), (5, 10, 100), (2, 6, 95))]
    params = [(row['max_r2'], row['min_r2'], row['die']) for row in rows]
    return params + [(BAND, 0, 0), (BAND - 1, 5, 2304), (5000, 4000, U32), (1000, 2000, 7)]


def cases():
    """Invent source-boundary inputs; no retail data or game outputs are consumed."""
    out = dict(light_create=[], light_decay=[], light_add=[], entity_fade=[], fat_fire_fly_bob=[], firefly_frames=[])
    radii = (1, 2, 4, 5, 16, 128, 255, 256, 65535)
    dies = (0, 1, 29, 30, 31, 90, 95, 100, 255, 4096, 0xFFFFFF, 0xFFFFFFFF)
    for low, high in itertools.product(radii, repeat=2):
        case = dict(min_radius=low, max_radius=high, die_speed=90)
        out['light_create'].append(dict(input=case, expected=light_create(case)))
    for die in dies:
        case = dict(min_radius=2, max_radius=4, die_speed=die)
        out['light_create'].append(dict(input=case, expected=light_create(case)))
    for fl_max, fl_min, die in light_params():
        for maximum in sorted({0, 1, fl_min - 1, fl_min, fl_min + 1, fl_max - 1, fl_max, fl_max + 1, die - 1, U32} - {-1}):
            case = dict(map_max=maximum & U32, map_min=12345, fl_max=fl_max, fl_min=fl_min, die=die)
            out['light_decay'].append(dict(input=case, expected=light_decay(case)))
    for (maximum, minimum), source, repeats in itertools.product(
            ((1048576, 0), (2304, 1), (0xFFFFFFF8, 0xFFEFFFF8), (0xFFFF0000, 0xFFEF0000), (0, 0)), SOURCES, (1, 3)):
        case = dict(map_max=maximum, map_min=minimum, source=source, repeats=repeats)
        out['light_add'].append(dict(input=case, expected=light_add(case)))
    for case in fade_inputs():
        out['entity_fade'].append(dict(input=case, expected=entity_fade(case)))
    for uid, frame, base_y, stopped in itertools.product((-32768, -1, 0, 7, 32767), (0, 1, 15, 16, 65535, 65536),
                                                         (-200, 2147483647), (False, True)):
        case = dict(uid=uid, frame=frame, base_y=base_y, stopped=stopped)
        out['fat_fire_fly_bob'].append(dict(input=case, expected=fat_fire_fly_bob(case)))
    for age in (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 15, 16, 17, 32767, 32768, 65535, 65536):
        out['firefly_frames'].append(dict(input=dict(age=age), expected=dict(image=firefly_frame(age))))
    return out


def fade_case(frog_x, frog_z, entity_x, entity_z, low, high, no_model=False, dont_fade=0, no_display=False):
    return dict(frog_x=frog_x, frog_z=frog_z, entity_x=entity_x, entity_z=entity_z, map_min=low & U32,
                map_max=high & U32, no_model=no_model, dont_fade=dont_fade, no_display=no_display)


def fade_inputs():
    """Distance thresholds, 32-bit square wrap, negative signed width and flag gating."""
    result = []
    d = 360000
    for low, high in ((d, d + BAND), (d - 1, d - 1 + BAND), (d + 1, d + 1 + BAND), (d - BAND + 1, d + 1),
                      (d - BAND, d), (d - BAND - 1, d - 1), (d - 0x80000, d + 0x80000)):
        result.append(fade_case(100, 200, 700, 200, low, high))
        result.append(fade_case(100, 200, 100, -400, low, high))
    for frog_x, frog_z in ((0, 0), (1, 0), (1, 1), (2, 0)):
        result.append(fade_case(frog_x, frog_z, 0, 0, 1, 2))
    for dx, dz in ((32767, 0), (65536, 0), (70000, 0), (46341, 0), (46341, 46341)):
        for low, high in ((0x10000, 0x110000), (0x80000000, 0x80100000), (0x3FF00000, 0x40000000)):
            result.append(fade_case(dx, dz, 0, 0, low, high))
    result.append(fade_case(2147483647, 0, -2147483648, 0, 0, 2))
    result.append(fade_case(-2147483648, 0, 2147483647, 0, 0, 2))
    for high in (0xFFFFFFFF, 0xFFFFFFFE, 0xFFFFFFFD, 0x80000001, 0x80000000, 0x7FFFFFFF):
        for distance_x in (3, 10, 46341, 60000):
            result.append(fade_case(distance_x, 0, 0, 0, 1, high))
    result.append(fade_case(1000, 0, 0, 0, 1, 0xFFFFFFFE))
    for colour in (31, 32, 33, 0):
        offset = (128 - colour) * 8192 if colour else BAND
        result.append(fade_case(1000, 0, 0, 0, 1000000 - offset, 1000000 - offset + BAND, True))
    for low, high in ((0, 1), (1000000 - 0x80000, 1000000 + 0x80000), (1000000 - 96 * 8192, 1000000 - 96 * 8192 + BAND),
                      (2000000, 3000000), (1, 0xFFFFFFFE)):
        for no_model, dont_fade, no_display in itertools.product((False, True), (0, 1, 2), (False, True)):
            result.append(fade_case(1000, 0, 0, 0, low, high, no_model, dont_fade, no_display))
    return result


def main():
    """Verify reproducibility by default; rewrite only with an explicit flag."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    text = json.dumps(cases(), indent=2) + '\n'
    if args.write:
        OUTPUT.write_text(text)
    elif OUTPUT.read_text() != text:
        raise SystemExit('Cave facts differ; use --write only to deliberately regenerate')
    print('Cave facts verified')


if __name__ == '__main__':
    main()
