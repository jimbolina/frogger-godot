"""Require identical committed demo evidence across headless and rendered schedules."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT', 'godot'))
    parser.add_argument('--data-dir', type=Path)
    parser.add_argument('--level', default='ORG1')
    parser.add_argument('--scenario-file', type=Path)
    parser.add_argument('--demo-file', type=Path)
    parser.add_argument('--tick-limit', type=int)
    parser.add_argument('--output-directory', type=Path, required=True)
    args = parser.parse_args()
    shared = ['--godot', args.godot, '--level', args.level,
              '--output-directory', str(args.output_directory)]
    for name in ('data_dir', 'scenario_file', 'demo_file', 'tick_limit'):
        value = getattr(args, name)
        if value is not None:
            shared += ['--' + name.replace('_', '-'), str(value)]
    results = []
    for label, extra in [('headless', [])] + [(rate, ['--viewer', '--render-rate', rate])
                                             for rate in ('30', '60', '144', 'irregular')]:
        startup = None
        if os.name == 'nt':
            startup = subprocess.STARTUPINFO()
            startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            startup.wShowWindow = 0
        process = subprocess.run([sys.executable, str(Path(__file__).with_name('run_demo.py')),
                                  *shared, *extra], capture_output=True, text=True,
                                 startupinfo=startup, timeout=600)
        if process.returncode not in (0, 3):
            raise RuntimeError(f'{label} failed: {process.stdout}\n{process.stderr}')
        matches = [line.removeprefix('Demo evidence: ') for line in process.stdout.splitlines()
                   if line.startswith('Demo evidence: ')]
        if len(matches) != 1:
            raise RuntimeError(f'{label}: missing evidence path: {process.stdout}')
        folder = Path(matches[0])
        evidence = tuple((folder / name).read_bytes() for name in
                         ('frog.csv', 'frog.csv.entities.csv', 'playback.json'))
        status = json.loads(evidence[-1])
        if status['elapsed_ticks'] <= 0:
            raise ValueError(f'{label}: zero committed ticks cannot establish schedule parity: {folder}')
        if results and results[0] != evidence:
            raise ValueError(f'{label}: committed playback evidence differs: {folder}')
        results.append(evidence)
        print(f'{label}: {folder}', flush=True)
    print('Demo evidence matches across headless, 30/60/144 Hz and irregular frames')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
