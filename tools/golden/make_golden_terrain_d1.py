#!/usr/bin/env python3
"""Independent FROG.C D1a component facts; cross-check every field with frozen C."""
import argparse
import csv
import io
from pathlib import Path
import subprocess

FIELDS = 'scenario,tick,component,x16,y16,z16,vx16,vy16,vz16,grid_x,grid_z,count,flags,mode,input,direction,animation_requests,sound_requests,score_requests,buffered_keys,buffered_input_count,pad_pressed,pad_held'.split(',')


def trunc(n, d):
    return abs(n) // abs(d) * (-1 if (n < 0) != (d < 0) else 1)


def expected():
    rows = []
    for scenario in range(8):
        pos = [-128 << 16, 0, -128 << 16]
        velocity = [0, 0, 0]
        cell = [1, 1]
        count = mode = key = direction = animations = sounds = scores = 0
        flags = 2049
        target = [0, 0, 0]
        destination_height = [0, 0, 0, -200, -201, 256, 257, 0][scenario]
        for tick in range(20):
            pressed = (16 if scenario == 0 else 1) if tick == 0 else 0
            held = 1 if scenario == 2 and tick < 7 else pressed
            if mode == 0:
                key = 0 if pressed or scenario == 2 and held else 128
                if key != 128:
                    height = destination_height if cell[1] == 1 else 0
                    allowed_up = 448 if scenario == 0 else 200
                    smooth = height >= -allowed_up and height <= 256 and scenario != 7
                    blocked = height < -allowed_up
                    if blocked:
                        animations += 1
                    else:
                        mode = 1
                        cell[1] += 1
                        flags = flags | 64 if smooth else flags & ~64
                        if scenario == 0:
                            flags |= 32
                        count = 15 if scenario == 0 else 3 if scenario == 1 else 6
                        target = [pos[0], (height if smooth else 0) << 16, (-512 + cell[1]*256 + 128) << 16]
                        velocity = [0, trunc(target[1] - pos[1], count + 1) - (0x100000 * (count + 1) >> 1), trunc(target[2] - pos[2], count)]
                        animations += 1
                        sounds += 1
                        scores += scenario != 2
            rows.append([scenario,tick,'control'] + pos + velocity + cell + [count,flags,mode,key,direction,animations,sounds,scores,0,0,pressed,held])
            if mode == 1:
                count -= 1
                if count == 0:
                    if flags & 64:
                        pos = target[:]
                        velocity = [0,0,0]
                        flags &= ~(32|64|128)
                        mode = 0
                        animations += 1
                    else:
                        pos[0] = target[0]
                        pos[2] = target[2]
                        flags |= 128|8192
                        count = 0x7ffffff
                        velocity[0] = velocity[2] = 0
                else:
                    velocity[1] += 0x100000
                    if flags & (128|8192) == (128|8192) and (pos[1] >> 16) >= 0:
                        animations += 1
                        flags &= ~8192
                    pos = [a+b for a,b in zip(pos,velocity)]
                cell = [((pos[0] >> 16)+512) >> 8, ((pos[2] >> 16)+512) >> 8]
            rows.append([scenario,tick,'move'] + pos + velocity + cell + [count,flags,mode,key,direction,animations,sounds,scores,0,0,pressed,held])
    return rows


def serialize(rows):
    stream = io.StringIO(newline='')
    writer = csv.writer(stream, lineterminator='\n')
    writer.writerow(FIELDS)
    writer.writerows(rows)
    return stream.getvalue()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--c-oracle', required=True)
    parser.add_argument('--output', default='tests/golden/synthetic/terrain_d1.csv')
    parser.add_argument('--verify', action='store_true')
    args = parser.parse_args()
    process = subprocess.run([args.c_oracle], text=True, capture_output=True, check=True)
    lines = process.stdout.splitlines()
    start = next(i for i,line in enumerate(lines) if line.startswith('scenario,tick,component,'))
    c_rows = list(csv.reader(lines[start:]))
    facts = list(csv.reader(serialize(expected()).splitlines()))
    if c_rows != facts:
        for index,(a,b) in enumerate(zip(c_rows,facts)):
            if a != b:
                raise ValueError(f'Frozen C row {index}: {a} != independent Python {b}')
        raise ValueError('Frozen C row count differs')
    target = Path(args.output)
    text = serialize(expected())
    if args.verify:
        if target.read_text(encoding='utf-8-sig') != text:
            raise ValueError('Golden facts differ')
    else:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding='utf-8')
    print(f'Independent Python matched all {len(facts)-1} frozen C records.')


if __name__ == '__main__':
    main()
