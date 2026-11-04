#!/usr/bin/env python3
"""Compare complete JUN1 camera inspection traces and independent reference fields."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools import REPO_ROOT


def verify_reference(rows, golden):
    if len(rows) != 321 or rows[0].get('schema') != 'camera-zone-inspection-v1':
        raise ValueError('Incomplete or unknown camera inspection trace')
    entity_angle = 0
    for tick, row in enumerate(rows[1:]):
        if row['tick'] != tick: raise ValueError('Missing or reordered camera tick')
        case = golden['cases'][tick // 160]
        frame = case['frames'][tick % 160]
        if row['cell'] != frame['cell'] or row['world'] != frame['world']:
            raise ValueError(f'Camera stimulus differs at {tick}')
        if tick % 160 == 0: entity_angle = 0
        entity_angle = (entity_angle + row['camera']['entity_angle_delta']) & 3
        actual = dict(row['camera'], frog_zone=row['frog_zone'], frog_region=row['frog_region'],
                      entity_angle=entity_angle, mod_rotation=row['camera']['mod_matrix12'][:9])
        for key, value in case['expected'][tick % 160].items():
            if actual[key] != value: raise ValueError(f'Independent camera fact differs at {tick}: {key}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--output-directory', type=Path, required=True)
    args = parser.parse_args()
    repo = REPO_ROOT
    output = args.output_directory.resolve()
    for protected in (repo, (repo.parent/'froggy').resolve()):
        if output == protected or protected in output.parents:
            parser.error('Evidence must be outside both repositories')
    output.mkdir(parents=True, exist_ok=True)
    golden = json.loads((repo/'tests/golden/pc-retail-v3.0e/camera_zones.json').read_text())
    baseline = None
    for label, rate, viewer in [('headless',30,False),('render30',30,True),('render60',60,True),('render144',144,True)]:
        command = [sys.executable, '-B', str(repo/'tools/inspection/run_terrain.py'), '--godot', args.godot,
                   '--camera-inspection', 'jun1-camera-zones',
                   '--render-rate', str(rate), '--output-directory', str(output/label)]
        if viewer: command.append('--viewer')
        result = subprocess.run(command, cwd=repo, capture_output=True, text=True, timeout=1200)
        (output/(label+'.log')).write_text(result.stdout+result.stderr)
        if result.returncode: raise ValueError(f'{label} failed; see {output/(label+".log")}')
        line = next(line for line in result.stdout.splitlines() if line.startswith('Camera inspection succeeded: '))
        path = Path(line.removeprefix('Camera inspection succeeded: '))
        rows = [json.loads(line) for line in path.read_text().splitlines()]
        verify_reference(rows, golden)
        if baseline is None: baseline = rows
        elif rows != baseline: raise ValueError(f'Full camera snapshots differ for {label}')
        print(f'{label}: 320 complete ticks match independent facts; {path}', flush=True)
    print('Headless and rendered 30/60/144 Hz camera inspections agree exactly.')


if __name__ == '__main__':
    try: main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(error, file=sys.stderr); sys.exit(1)
