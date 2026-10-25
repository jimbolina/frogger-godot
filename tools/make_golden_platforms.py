#!/usr/bin/env python3
"""Independent invented SAFE-platform trajectories checked against frozen C."""
import argparse
import csv
import hashlib
import io
import json
import math
import os
from pathlib import Path
import struct
import subprocess
import sys

sys.dont_write_bytecode = True
from make_golden_integrated_terrain import scenarios as terrain_scenarios
from make_golden_frog_animation import State, catalog

IDENTITY = (4096, 0, 0, 0, 4096, 0, 0, 0, 4096)
MATRIX = IDENTITY + (0, 0, 0)
QUARTER_INVERSE = (0, 0, -4096, 0, 4096, 0, 4096, 0, 0, 0, 0, 0)
ANGLED = (3547, 0, 2048, 0, 4096, 0, -2048, 0, 3547, -128, 0, -128)
ANGLED_INVERSE = (3547, 0, -2048, 0, 4096, 0, 2048, 0, 3547, 0, 0, 0)
DIRECTIONS = (0, 0, 4096, 4096, 0, 0, 0, 0, -4096, -4096, 0, 0)
FIELDS = ('scenario tick phase x16 y16 z16 vx16 vy16 vz16 count flags mode input direction '
          'camera_mode camera_x camera_y camera_z source_x source_y source_z rng_seed '
          'no_input_timer animation_type script_timer animation_flags env_flags if_counter '
          'program offset action cel total update_count '
          'e0x e0y e0z e0segment current_entity_index forbidden_entity_index '
          'entity_cell_x entity_cell_z entity_offset_x16 entity_offset_y16 entity_offset_z16 '
          'entity_angle old_y ' + ' '.join(f'entity_transform{r}{c}' for r in range(3) for c in range(3)) +
          ' entity_transform_t0 entity_transform_t1 entity_transform_t2 entity_carry_indices ' +
          ' '.join(f'camera_mod{r}{c}' for r in range(3) for c in range(3)) +
          ' camera_mod_t0 camera_mod_t1 camera_mod_t2 camera_current_ytheta '
          'camera_destination_ytheta camera_delta_ytheta ' +
          ' '.join(f'camera_direction_{direction}_{axis}' for direction in 'nesw' for axis in 'xyz') +
          ' pgen_requests sound_requests').split()


def cdiv(a, b):
    return abs(a) // b * (-1 if a < 0 else 1)


def damp(value, destination):
    delta = destination - value
    return destination if abs(delta) < 5 else value + (abs(delta) >> 1) * (-1 if delta < 0 else 1)


def rounded(value):
    return math.copysign(math.floor(abs(value) + 0.5), value).__int__()


def verify_acos(path):
    table = struct.unpack('<8193h', path.read_bytes())
    for i, actual in zip(range(-4096, 4097), table):
        formula = 1023 if i == 0 else min(2047, math.floor(math.acos(i / 4096) * 2048 / math.pi))
        if actual != formula:
            raise ValueError(f'frozen acos lookup differs at {i}: {actual} != {formula}')
    return hashlib.sha256(','.join(map(str, table)).encode('ascii')).hexdigest()


def authored_cases():
    base = terrain_scenarios()['integrated-0.json']
    cases = []
    for case_index, (name, ticks) in enumerate((('moving_landing_centre_carry_departure', 20),
        ('within_platform_hop', 12), ('no_centring_x_interior', 1),
        ('quarter_turn_no_rotation_snap', 1), ('angled_camera_attachment', 1),
        ('no_entity_angle_departure', 10), ('quick_within_platform_hop', 9),
        ('super_off_platform_hop', 20), ('thirty_unit_centring', 5),
        ('usable_only_within_platform_hop', 12), ('pop_within_platform_hop', 8),
        ('water_freefall_linked_departure', 9), ('water_freefall_no_angle_departure', 9))):
        case = json.loads(json.dumps(base))
        case['name'] = name
        case['tick_limit'] = ticks
        case['level']['theme'] = 9
        case['level']['theme_name'] = 'SUB'
        if case_index in (11, 12):
            case['grid']['squares'][9]['flags'] = 9
        identity = dict(entity_index=0, unique_id=40, form_grid_id=0,
                        form_id=0, form_name='SYNTHETIC_SAFE')
        if case_index == 0:
            entity = dict(identity, entity_name='MOVING', flags=16,
                path_definition=dict(path_index=0, segments=[dict(segment_type=2,
                    length=40, start=[-150, 0, -128], end=[-110, 0, -128])]),
                path_start=dict(segment_index=0, distance=0, speed=1, flags=8))
            dimensions, offsets, flags = [1, 1], [-128, -128], [3]
            case['commands'] = [dict(tick=12, pressed=1, held=1)]
        elif case_index in (1, 6, 9, 10):
            entity = dict(identity, entity_name='STATIC', flags=0,
                          matrix12=list(IDENTITY) + [0, 0, -128])
            dimensions, offsets, flags = [2, 1], [-256, -128], [3, 1 if case_index == 9 else 4097 if case_index == 10 else 3]
            case['commands'] = [dict(tick=3, pressed=2, held=2)]
            if case_index == 6:
                case['start']['powerup_flags'] = 2
                case['start']['quick_jump_timer'] = 240
        else:
            rotation = list(IDENTITY if case_index in (2, 5, 7, 8, 11, 12) else
                (0, 0, 4096, 0, 4096, 0, -4096, 0, 0) if case_index == 3 else ANGLED[:9])
            entity = dict(identity, entity_name='STATIC', flags=0,
                          matrix12=rotation + [-149 if case_index == 2 else -158 if case_index == 8 else -128, 0, -128])
            dimensions, offsets, flags = ([2, 1] if case_index == 2 else [1, 1],
                                          [-128, -128], [3, 3] if case_index == 2 else [3])
            case['commands'] = ([dict(tick=3, pressed=1, held=1)] if case_index in (5, 11, 12) else
                                [dict(tick=3, pressed=16, held=16)] if case_index == 7 else [])
        contact = dict(identity, entity_flags=entity['flags'], dimensions=dimensions,
            offsets=offsets, height=0, max_y=1000, radius_squared=1000000,
            grid_flags=flags, death_type=5,
            form_book_flags=64 if case_index == 2 else 6 if case_index == 3 else 4 if case_index in (5, 12) else 0)
        case['level']['entity_collision'] = dict(platforms_enabled=True,
            group_base=[-512, 0, -512], group_dimensions=[3, 3], group_size=[768, 768],
            entities=[entity], contacts=[contact])
        cases.append(case)
    return {'cases': cases}


def expected():
    """Compose attachment, local centring, carriage, hops and camera phases."""
    rows = []
    for scenario, ticks in enumerate((20, 12, 1, 1, 1, 10, 9, 20, 5, 12, 8, 9, 9)):
        x = z = -128 << 16
        y = vx = vy = vz = count = 0
        flags, mode, key, direction = 2049, 0, 0, 0
        attached, forbidden, cellx, cellz = -1, -1, 0, 0
        offset = [0, 0, 0]
        camera = [-128, 0, -128]
        animation = State(catalog())
        no_input = 0
        carry, old_y, sounds, pgens, camera_mode = '-', 0, 0, 0, 0
        entity_transform = (0,) * 12
        camera_mod = MATRIX
        camera_theta = camera_dest = camera_delta = 0
        directions = DIRECTIONS
        source_x_shift = 0
        for tick in range(ticks):
            carry = '-'
            entity_x = -149 + tick if scenario == 0 else 0 if scenario in (1, 6, 9, 10) else -149 if scenario == 2 else -158 if scenario == 8 else -128
            entity_z = -128

            def emit(phase):
                facts = dict(scenario=scenario, tick=tick, phase=phase, x16=x, y16=y,
                    z16=z, vx16=vx, vy16=vy, vz16=vz, count=count, flags=flags,
                    mode=mode, input=key, direction=direction, camera_mode=camera_mode,
                    camera_x=camera[0], camera_y=camera[1], camera_z=camera[2],
                    source_x=camera[0] + source_x_shift, source_y=camera[1] - 500, source_z=camera[2] - 500,
                    rng_seed=1, e0x=entity_x, e0y=0, e0z=entity_z,
                    no_input_timer=no_input, animation_type=animation.type,
                    script_timer=animation.timer, animation_flags=animation.flags,
                    env_flags=animation.env_flags, if_counter=animation.if_counter,
                    program=animation.program, offset=animation.offset,
                    action=animation.action, cel=animation.cel, total=animation.total,
                    update_count=animation.update_count,
                    e0segment=tick + 1 if scenario == 0 else -1,
                    current_entity_index=attached, forbidden_entity_index=forbidden,
                    entity_cell_x=cellx, entity_cell_z=cellz,
                    entity_offset_x16=offset[0], entity_offset_y16=offset[1],
                    entity_offset_z16=offset[2], entity_angle=0, old_y=old_y,
                    entity_carry_indices=carry, camera_current_ytheta=camera_theta,
                    camera_destination_ytheta=camera_dest, camera_delta_ytheta=camera_delta,
                    pgen_requests=pgens, sound_requests=sounds)
                for prefix, matrix in (('entity_transform', entity_transform), ('camera_mod', camera_mod)):
                    for row in range(3):
                        for col in range(3):
                            facts[f'{prefix}{row}{col}'] = matrix[row * 3 + col]
                    for axis in range(3):
                        facts[f'{prefix}_t{axis}'] = matrix[9 + axis]
                for index, direction_name in enumerate('nesw'):
                    for axis, name in enumerate('xyz'):
                        facts[f'camera_direction_{direction_name}_{name}'] = directions[index * 3 + axis]
                rows.append([facts[field] for field in FIELDS])

            if (scenario == 0 and tick == 12) or (scenario in (5, 7) and tick == 3):
                duration = 15 if scenario == 7 else 6
                key, direction, mode, count, flags = 0, 0, 1, duration, (2113 if scenario == 5 else 2161 if scenario == 7 else 2129)
                forbidden = 0
                if scenario in (0, 7):
                    cellz = 1
                vx = cdiv((-128 << 16) - x, duration)
                vy = -(1048576 * (duration + 1) // 2)
                vz = cdiv((128 << 16) - z, duration)
                sounds += 1
                no_input = 0
                animation.request(17 if scenario == 7 else 16)
            elif scenario in (11, 12) and tick == 3:
                key, direction, mode, count = 0, 0, 1, 6
                flags = 2065 if scenario == 11 else 2049
                forbidden = 0
                if scenario == 11:
                    cellz = 1
                else:
                    attached = -1
                vx = 0
                vy = -(1048576 * (count + 1) // 2)
                vz = cdiv((128 << 16) - z, count)
                sounds += 1
                no_input = 0
                animation.request(16)
            elif scenario in (1, 6, 9, 10) and tick == 3:
                duration = 3 if scenario == 6 else 6
                key, direction, mode, count, flags = 1, 1, 1, duration, 2067
                cellx = 1
                vx = cdiv((128 << 16) - offset[0], duration)
                vy = -(1048576 * (duration + 1) // 2)
                sounds += 1
                no_input = 0
                animation.request(20 if scenario == 6 else 16)
            elif mode == 0:
                key = 128
            if mode != 1:
                no_input += 1
            emit('control')

            if mode == 5:
                count -= 1
                if count == 0:
                    offset[0] = -128 << 16 if scenario in (1, 6, 9, 10) else 0
                    vx = vy = vz = 0
                    mode = 0
                    animation.request(14)
                else:
                    offset[0] += vx
                x = (entity_x + (offset[0] >> 16)) << 16
            elif mode == 0 and attached >= 0:
                x = (entity_x << 16) + offset[0]
            elif mode == 1:
                count -= 1
                if count == 0:
                    if scenario in (11, 12):
                        count = 134217727
                        flags = 10369
                        attached = -1
                        if scenario == 11:
                            vy += 1048576
                            offset[2] += vz
                            z = (-128 << 16) + offset[2]
                            y += vy
                        else:
                            z = 128 << 16
                        vx = vz = 0
                    else:
                        vx = vy = vz = 0
                        mode = 0
                        animation.request(14)
                    if scenario in (0, 5, 7):
                        x, y, z = -128 << 16, 0, 128 << 16
                        attached = -1
                        forbidden = -1
                        flags = 2049
                    elif scenario not in (11, 12):
                        offset[0] = 128 << 16
                        x, y, z = offset[0], 0, -128 << 16
                        flags = 2053
                        entity_transform = (0, 0, 4096, 0, 4096, 0, -4096, 0, 0, 0, 0, 0)
                else:
                    vy += 1048576
                    if scenario in (0, 5, 7, 12):
                        x, y, z = x + vx, y + vy, z + vz
                    else:
                        if scenario == 11:
                            offset[2] += vz
                            z = (-128 << 16) + offset[2]
                            y += vy
                        else:
                            offset[0] += vx
                            x, y = offset[0], y + vy
            if attached >= 0 and flags & 4:
                carry = '0'
            emit('move')

            if tick == 0:
                attached, carry, flags, mode = 0, '0', 2053, 5
                entity_transform = QUARTER_INVERSE if scenario == 3 else MATRIX
                camera_mod = QUARTER_INVERSE if scenario == 3 else MATRIX
                local_x = -128 if scenario in (1, 6, 9, 10) else 0 if scenario in (3, 4) else -128 - entity_x
                offset[0] = local_x << 16
                target_x = -128 if scenario in (1, 6, 9, 10) else local_x if scenario == 2 else 0
                distance = abs(local_x - target_x)
                count = distance // 15 + 1
                vx = cdiv((target_x - local_x) << 16, count)
                if scenario == 4:
                    camera_mod = ANGLED_INVERSE
                    theta = math.floor(math.acos(ANGLED[8] / 4096) * 2048 / math.pi)
                    camera_dest, camera_theta, camera_delta = 4096, 4096 - theta, 32
            if scenario == 10 and tick == 7:
                flags = 27
                vx = vy = vz = 0
                pgens += 1
                camera_mode = 4
                animation.request(23)
            emit('collision')

            if camera_mode == 0:
                camera[0] = damp(camera[0], x >> 16)
                camera[2] = damp(camera[2], z >> 16)
                if flags & 8192:
                    camera[1] += max(-24, min(24, min(y >> 16, 0) - camera[1]))
            if scenario == 4:
                camera_theta += camera_delta
                angle = camera_theta * 2 * math.pi / 4096
                cosine, sine = rounded(math.cos(angle) * 4096), rounded(math.sin(angle) * 4096)
                camera_mod = (cosine, 0, sine, 0, 4096, 0, -sine, 0, cosine, 0, 0, 0)
                projected_x = (cosine * ANGLED[2] + sine * ANGLED[8]) >> 12
                source_x_shift = (projected_x * -500) >> 12
                length = math.hypot(-source_x_shift, 500)
                north_x = rounded(-source_x_shift * 4096 / length)
                north_z = rounded(500 * 4096 / length)
                directions = (north_x, 0, north_z, north_z, 0, -north_x,
                              -north_x, 0, -north_z, -north_z, 0, north_x)
            emit('camera')
            animation.no_input_timer = no_input
            animation.scripts()
            no_input = animation.no_input_timer
            emit('scripts')
            animation.pose()
            emit('pose')
    return rows


def frozen_rows(executable, acos_path):
    process = subprocess.run([str(executable), str(acos_path)], text=True,
        capture_output=True, check=True, creationflags=0x08000000 if os.name == 'nt' else 0)
    output = process.stdout[process.stdout.index('scenario,tick,phase,'):]
    return list(csv.DictReader(io.StringIO(output)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--c-oracle', type=Path, required=True)
    parser.add_argument('--acos-table', type=Path, required=True)
    parser.add_argument('--fixture', type=Path, default=Path('tests/golden/fixtures/platforms.json'))
    parser.add_argument('--output', type=Path, default=Path('tests/golden/synthetic/platforms.tsv'))
    parser.add_argument('--digest-output', type=Path,
                        default=Path('tests/golden/synthetic/platform_acos_digest.txt'))
    parser.add_argument('--verify', action='store_true')
    args = parser.parse_args()
    acos_digest = verify_acos(args.acos_table) + '\n'
    wanted = expected()
    actual = frozen_rows(args.c_oracle, args.acos_table)
    if len(actual) != len(wanted):
        raise ValueError(f'C row count {len(actual)} != Python {len(wanted)}')
    for line, (c_row, row) in enumerate(zip(actual, wanted), 2):
        for field, value in zip(FIELDS, row):
            if c_row[field] != str(value):
                raise ValueError(f'line {line} {field}: C={c_row[field]} Python={value}')
    output = io.StringIO(newline='')
    writer = csv.writer(output, delimiter='\t', lineterminator='\n')
    writer.writerow(FIELDS)
    writer.writerows(wanted)
    fixture = json.dumps(authored_cases(), indent=2) + '\n'
    if args.verify:
        if (args.output.read_text() != output.getvalue() or args.fixture.read_text() != fixture or
            args.digest_output.read_text() != acos_digest):
            raise ValueError('platform golden/fixture differs')
    else:
        args.output.write_text(output.getvalue())
        args.fixture.write_text(fixture)
        args.digest_output.write_text(acos_digest)
    print(f'Independent Python matches frozen C: {len(wanted)} six-phase rows')


if __name__ == '__main__':
    main()
