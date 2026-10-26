"""Inspect one path with isolated Godot state and external JSONL evidence."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid

from godot_project import isolated_project


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT', 'godot'))
    parser.add_argument('--scenario', choices=('line', 'arc', 'spline'), default='line')
    parser.add_argument('--scenario-file', type=Path)
    parser.add_argument('--data-dir', type=Path)
    parser.add_argument('--level')
    parser.add_argument('--path-index', type=int)
    parser.add_argument('--tick-limit', type=int)
    parser.add_argument('--render-rate', type=int, choices=(30, 60, 144), default=60)
    parser.add_argument('--output-directory', type=Path, required=True)
    parser.add_argument('--viewer', action='store_true')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    output = args.output_directory.resolve()
    for protected in (repo, (repo.parent / 'froggy').resolve()):
        if output == protected or protected in output.parents:
            parser.error('Output must be outside this repository and frozen froggy')
    if args.path_index is not None and not args.level:
        parser.error('--path-index requires --level')
    if args.level and args.path_index is None:
        parser.error('--level requires --path-index')
    if args.tick_limit is not None and not 0 <= args.tick_limit <= 100000:
        parser.error('--tick-limit must be in 0..100000')
    output.mkdir(parents=True, exist_ok=True)
    evidence = output / ('path-' + uuid.uuid4().hex)
    profile = evidence / 'profile'
    temporary = evidence / 'temp'
    profile.mkdir(parents=True)
    temporary.mkdir()
    project = isolated_project(repo, profile)
    env = os.environ.copy()
    env.update(APPDATA=str(profile), XDG_DATA_HOME=str(profile), TEMP=str(temporary), TMP=str(temporary))
    startup = None
    if os.name == 'nt':
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 0
    print('Path evidence: ' + str(evidence), flush=True)
    stage_durations = {}

    def stage(name, arguments, headless=True):
        log = evidence / (name + '.log')
        command = [args.godot, '--disable-crash-handler', '--path', str(project), '--log-file', str(log)]
        if headless:
            command.append('--headless')
        command += arguments
        started = time.monotonic()
        with (evidence / (name + '-process.log')).open('w', encoding='utf-8') as stream:
            result = subprocess.run(command, cwd=repo, env=env, startupinfo=startup,
                                    stdout=stream, stderr=subprocess.STDOUT, timeout=120)
        stage_durations[name] = time.monotonic() - started
        log_text = log.read_text(encoding='utf-8') if log.exists() else ''
        if result.returncode or not log_text or any(marker in log_text for marker in (
                'SCRIPT ERROR', 'Parse Error', 'Failed to load script', 'CHECK FAILED',
                'ARCHITECTURE FAILED')):
            raise RuntimeError(f'{name} failed ({result.returncode}); see {log}')

    stage('import', ['--import'])
    stage('check', ['-s', 'res://tools/check_scripts.gd'])
    stage('architecture', ['-s', 'res://tools/check_architecture.gd'])
    selected = ['--scenario-file=' + str(args.scenario_file.resolve())] if args.scenario_file else [
        '--scenario=' + args.scenario]
    selected += ['--trace-jsonl=' + str(evidence / 'trace.jsonl')]
    selected += ['--render-rate=' + str(args.render_rate)]
    if args.data_dir:
        selected += ['--data-dir=' + str(args.data_dir.resolve())]
    if args.level:
        selected += ['--level=' + args.level, '--path-index=' + str(args.path_index)]
    if args.tick_limit is not None:
        selected += ['--tick-limit=' + str(args.tick_limit)]
    if args.viewer:
        stage('viewer', ['res://scenes/tools/map_viewer.tscn', '--', '--run-path-scenario',
                         '--screenshot-dir=' + str(evidence), *selected], headless=False)
    else:
        stage('driver', ['-s', 'res://tools/run_path_scenario.gd', '--', *selected])
    if not (evidence / 'trace.jsonl').is_file():
        raise RuntimeError('Path scenario did not produce its trace: ' + str(evidence))
    trace_rows = (evidence / 'trace.jsonl').read_text(encoding='utf-8').splitlines()
    if not trace_rows:
        raise RuntimeError('Path scenario produced an empty trace: ' + str(evidence))
    (evidence / 'run.json').write_text(json.dumps({
        'mode': 'viewer' if args.viewer else 'headless',
        'scenario': str(args.scenario_file.resolve()) if args.scenario_file else args.scenario,
        'level': args.level,
        'path_index': args.path_index,
        'render_rate': args.render_rate if args.viewer else None,
        'stage_seconds': stage_durations,
        'snapshot_count': len(trace_rows) - 1,
    }, indent=2) + '\n', encoding='utf-8')
    print('Path run succeeded: ' + str(evidence / 'trace.jsonl'))


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
