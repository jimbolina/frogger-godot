"""Compare complete headless and 30/60/144 Hz viewer path JSONL traces."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys


META_KEYS = frozenset({
    'schema', 'scenario', 'source_id', 'resource_id', 'path_index',
    'source_offset', 'level_code', 'tick_limit', 'start', 'diagnostics',
})
STATE_KEYS = frozenset({
    'tick_index', 'segment_index', 'segment_type', 'segment_distance',
    'segment_length', 'segment_param', 'total_distance', 'speed', 'flags',
    'position', 'tangent',
})


def read_trace(path):
    """Read a complete trace and reject missing, extra or unordered state."""
    lines = Path(path).read_text(encoding='utf-8').splitlines()
    if not lines:
        raise ValueError(f'Empty path trace: {path}')
    try:
        rows = [json.loads(line) for line in lines]
    except json.JSONDecodeError as error:
        raise ValueError(f'Invalid path trace JSON: {path}: {error}') from error
    if not all(isinstance(row, dict) for row in rows):
        raise ValueError(f'Path trace rows must be objects: {path}')
    metadata, *states = rows
    if set(metadata) != META_KEYS or metadata['schema'] != 'path-run-v1':
        raise ValueError(f'Path trace metadata schema differs: {path}')
    limit = metadata['tick_limit']
    if type(limit) is not int or not 0 <= limit <= 100000:
        raise ValueError(f'Invalid path tick limit: {path}')
    if len(states) != limit + 1:
        raise ValueError(f'Path trace has {len(states)} snapshots; expected {limit + 1}: {path}')
    for expected_tick, row in enumerate(states):
        if set(row) != STATE_KEYS or type(row['tick_index']) is not int or row['tick_index'] != expected_tick:
            raise ValueError(f'Path trace state schema/order differs at tick {expected_tick}: {path}')
        for key in ('position', 'tangent'):
            value = row[key]
            if not isinstance(value, list) or len(value) != 3 or any(type(axis) is not int for axis in value):
                raise ValueError(f'Invalid {key} at tick {expected_tick}: {path}')
        for key in STATE_KEYS - {'position', 'tangent'}:
            if type(row[key]) is not int:
                raise ValueError(f'Invalid integer {key} at tick {expected_tick}: {path}')
    return rows


def compare_traces(reference, candidate):
    """Raise at the first exact metadata or state mismatch."""
    left = read_trace(reference)
    right = read_trace(candidate)
    if len(left) != len(right):
        raise ValueError(f'Path trace row count differs: {candidate}')
    for index, (a, b) in enumerate(zip(left, right)):
        if a != b:
            label = 'metadata' if index == 0 else f'tick {index - 1}'
            raise ValueError(f'Path trace differs at {label}: {candidate}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default='godot')
    parser.add_argument('--scenario', choices=('line', 'arc', 'spline'), default='line')
    parser.add_argument('--scenario-file', type=Path)
    parser.add_argument('--data-dir', type=Path)
    parser.add_argument('--level')
    parser.add_argument('--path-index', type=int)
    parser.add_argument('--tick-limit', type=int)
    parser.add_argument('--output-directory', type=Path, required=True)
    args = parser.parse_args()
    runner = Path(__file__).with_name('run_paths.py')
    selected = ['--scenario-file', str(args.scenario_file)] if args.scenario_file else ['--scenario', args.scenario]
    shared = ['--godot', args.godot, '--output-directory', str(args.output_directory), *selected]
    if args.data_dir:
        shared += ['--data-dir', str(args.data_dir)]
    if args.level:
        shared += ['--level', args.level]
    if args.path_index is not None:
        shared += ['--path-index', str(args.path_index)]
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
        prefix = 'Path run succeeded: '
        matches = [line[len(prefix):] for line in process.stdout.splitlines() if line.startswith(prefix)]
        if len(matches) != 1:
            raise RuntimeError(f'{label} did not report one trace:\n{process.stdout}')
        trace = Path(matches[0])
        read_trace(trace)
        print(f'{label}: {trace}', flush=True)
        return trace

    reference = run('headless', [])
    for rate in (30, 60, 144):
        candidate = run(f'viewer {rate} Hz', ['--viewer', '--render-rate', str(rate)])
        compare_traces(reference, candidate)
    print('Path schedules match exactly at 30, 60 and 144 Hz')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
