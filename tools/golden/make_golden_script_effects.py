#!/usr/bin/env python3
"""Independent invented script-effect facts from frozen scripter.c bodies."""
import argparse
import json
import math
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools import REPO_ROOT

OUTPUT = REPO_ROOT / 'tests/golden/synthetic/script_effects.json'
IDENTITY = [4096, 0, 0, 0, 4096, 0, 0, 0, 4096, 0, 0, 0]


def narrow(value, bits):
    return (value + (1 << (bits - 1))) % (1 << bits) - (1 << (bits - 1))


def divide(value, divisor):
    return (-1 if value < 0 else 1) * (abs(value) // divisor)


def rounded(value):
    return math.floor(value + .5) if value >= 0 else math.ceil(value - .5)


def homing(matrix, frog, mode, speed, limit, literal):
    """Port the source YX construction independently, including vertical columns."""
    result = matrix[:]
    if mode in (2, 4, 264):
        return result
    direction = [narrow(frog[i] - matrix[9 + i], 32) for i in range(3)]
    distance = math.isqrt(max(0, narrow(sum(v*v for v in direction), 32)))
    if distance >= limit and distance >= literal:
        return result
    if distance <= 4:
        return result[:9] + [frog[0], narrow(frog[1] + 10, 32), frog[2]]
    length = math.sqrt(sum(v*v for v in direction))
    x, y, z = [rounded(v * 4096 / length) for v in direction]
    denominator = math.isqrt(x*x + z*z)
    if denominator:
        values = [divide(narrow(z << 18, 32), denominator) >> 6,
                  divide(narrow(-x*y << 6, 32), denominator) >> 6, x,
                  0, denominator, y,
                  divide(narrow(-x << 18, 32), denominator) >> 6,
                  divide(narrow(-y*z << 6, 32), denominator) >> 6, z]
    else:
        values = [0, -4096 if y > 0 else 4096, x, 0, 0, y, 4096 if y > 0 else -4096, 0, z]
    result[:9] = [narrow(v, 16) for v in values]
    result[9:] = [narrow(matrix[9+i] + (narrow(values[i*3+2] * (speed >> 8), 32) >> 12), 32) for i in range(3)]
    return result


def facts():
    """Source operand branches, strict distance limits, checkpoint RNG and flags."""
    rows = []
    for target in ([100, 200, -300], [0, 100, 0], [0, -100, 0], [4, 0, 0], [5, 0, 0], [500, 0, 0], [0, 0, 0]):
        for mode in (0, 2, 4, 264):
            rows.append(dict(kind='homing', target=target, mode=mode, speed=1792, limit=500, literal=500,
                             expected=homing(IDENTITY, target, mode, 1792, 500, 500)))
    rows.append(dict(kind='homing', target=[1, 0, 0], mode=0, speed=-256, limit=0, literal=2,
                     expected=homing(IDENTITY, [1, 0, 0], 0, -256, 0, 2)))
    for seed in (1, 5, 20, 99):
        for collected in (0, 1, 15, 30, 31):
            rng = seed
            draws = 0
            def rand():
                nonlocal rng, draws
                rng = (rng * 0x41c64e6d + 0x3039) & 0xffffffff
                draws += 1
                return (rng >> 16) & 32767
            point = [0, -20000, 0]
            selected = 0
            disabled = 0
            if rand() % 5 < 2:
                candidate = rand() % 5
                wraps = 0
                while True:
                    if not collected & (1 << candidate):
                        disabled |= 1 << candidate
                        selected = candidate
                        point = [candidate * 100, 20, 30]
                        break
                    candidate += 1
                    if candidate >= 5:
                        candidate = 0
                        wraps += 1
                    if wraps > 1:
                        break
            rows.append(dict(kind='checkpoint', seed=seed, collected=collected,
                             position=point, selected=selected, disabled=disabled, rng=rng, draws=draws))
    for height in (100, 0, -1, -511, -512, -8192):
        rows.append(dict(kind='colour', height=height,
                         colours=[(16 + (min(height, 0)*-16 >> 9)) & 255,
                                  (64 + (min(height, 0)*-32 >> 9)) & 255,
                                  (96 + (min(height, 0)*-32 >> 9)) & 255]))
    for mode in range(4):
        action = 2 if mode == 3 else 1 if mode == 2 else 0
        lengths = [4, 3, 5]
        for cel in (-1, 0, lengths[action] - 1):
            for distance in (0, 511, 512):
                for seed in (1, 11):
                    rng, draws = seed, 0
                    next_action, next_cel, next_mode = action, cel, mode
                    if mode == 0 and cel == 0 and distance * distance < 512 * 512:
                        rng = (rng * 0x41c64e6d + 0x3039) & 0xffffffff
                        draws = 1
                        if ((rng >> 16) & 32767) % 10 == 1:
                            next_action, next_cel, next_mode = 2, -1, 3
                    elif mode == 1 and cel == 0:
                        next_action, next_cel, next_mode = 1, -1, 2
                    elif mode in (2, 3) and cel >= lengths[action] - 1:
                        next_action, next_cel, next_mode = 0, -1, 0
                    rows.append(dict(kind='checkpoint_croak', mode=mode, action=action, cel=cel,
                                     distance=distance, seed=seed, next_action=next_action,
                                     next_cel=next_cel, next_mode=next_mode, rng=rng, draws=draws))
    for timer in (0, 1, 32, 63, 127, 65535):
        for registers in (False, True):
            low, high, speed, shift, midpoint = 32, 96, 5, 7, 64
            if registers:
                midpoint = shift
            sine = rounded(math.sin(((timer << speed) & 4095) * math.tau / 4096) * 4096)
            pitch = narrow(midpoint - (sine >> shift), 32)
            pitch = low if pitch < low else high if pitch > high else pitch
            rows.append(dict(kind='pitch', timer=timer, registers=registers, expected=pitch))
    for carry in (False, True):
        for duration in (0, 6, 12):
            rows.append(dict(kind='eject', carry=carry, delta=2, duration=duration,
                             expected=[2, duration] if carry else []))
    for allocated in (False, True):
        rows.append(dict(kind='pop', allocated=allocated, started=not allocated,
                         timers=[max(0, 32 - tick) for tick in range(1, 35)]))
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    text = json.dumps(facts(), indent=2) + '\n'
    if args.write:
        OUTPUT.write_text(text, encoding='utf-8')
    elif OUTPUT.read_text(encoding='utf-8') != text:
        raise ValueError('Script effect facts differ from independent source model')
    print('Script effect facts verified against independent Python source model.')


if __name__ == '__main__':
    main()
