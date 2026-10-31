"""Compare an attached-entity headless trace with 30, 60 and 144 Hz viewers."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys


def read_trace(path):
    rows = [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines()]
    if not rows or rows[0].get('schema') != 'entity-contact-v1':
        raise ValueError(f'Invalid entity trace: {path}')
    if len(rows) != rows[0]['tick_limit'] + 2:
        raise ValueError(f'Entity trace row count differs from tick limit: {path}')
    for tick, row in enumerate(rows[1:]):
        if row.get('tick_index') != tick:
            raise ValueError(f'Entity trace skips tick {tick}: {path}')
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT', 'godot'))
    parser.add_argument('--scenario', choices=('shared-path',), default='shared-path')
    parser.add_argument('--level')
    parser.add_argument('--tick-limit', type=int)
    parser.add_argument('--output-directory', type=Path, required=True)
    args = parser.parse_args()
    runner = Path(__file__).with_name('run_entities.py')
    shared = ['--godot', args.godot, '--output-directory', str(args.output_directory),
              '--scenario', args.scenario]
    if args.level:
        shared += ['--level', args.level]
    if args.tick_limit is not None:
        shared += ['--tick-limit', str(args.tick_limit)]

    def run(label, extra):
        startup = None
        if os.name == 'nt':
            startup = subprocess.STARTUPINFO()
            startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            startup.wShowWindow = 0
        process = subprocess.run([sys.executable, str(runner), *shared, *extra],
                                 capture_output=True, text=True, timeout=300,
                                 startupinfo=startup)
        if process.returncode:
            raise RuntimeError(f'{label} failed:\n{process.stdout}\n{process.stderr}')
        prefix = 'Entity run succeeded: '
        matches = [line[len(prefix):] for line in process.stdout.splitlines()
                   if line.startswith(prefix)]
        if len(matches) != 1:
            raise RuntimeError(f'{label} did not report one trace:\n{process.stdout}')
        trace = Path(matches[0])
        rows = read_trace(trace)
        print(f'{label}: {trace}', flush=True)
        return rows

    reference = run('headless', [])
    for rate in (30, 60, 144):
        candidate = run(f'viewer {rate} Hz', ['--viewer', '--render-rate', str(rate)])
        for index, (left, right) in enumerate(zip(reference, candidate)):
            if left != right:
                label = 'metadata' if index == 0 else f'tick {index - 1}'
                raise ValueError(f'Entity trace differs at {label} for {rate} Hz')
        if len(reference) != len(candidate):
            raise ValueError(f'Entity trace length differs for {rate} Hz')
    print('Entity schedules match exactly at 30, 60 and 144 Hz')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
