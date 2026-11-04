"""Replay player demos with isolated Godot state and external comparison evidence."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools import REPO_ROOT
from tools.check.godot_project import isolated_project


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT', 'godot'))
    parser.add_argument('--scenario-file', type=Path)
    parser.add_argument('--demo-file', type=Path)
    parser.add_argument('--level', default='ORG1')
    parser.add_argument('--tick-limit', type=int)
    parser.add_argument('--render-rate', choices=('30', '60', '144', 'irregular'), default='60')
    parser.add_argument('--output-directory', type=Path, required=True)
    parser.add_argument('--viewer', action='store_true')
    args = parser.parse_args()
    repo = REPO_ROOT
    output = args.output_directory.resolve()
    for protected in (repo, (repo.parent / 'froggy').resolve()):
        if output == protected or protected in output.parents:
            parser.error('Output must be outside this repository and frozen froggy')
    if bool(args.scenario_file) != bool(args.demo_file):
        parser.error('Use the imported demo of --level or a paired external synthetic scenario/demo')
    if args.tick_limit is not None and not 0 <= args.tick_limit <= 100000:
        parser.error('--tick-limit must be in 0..100000')
    output.mkdir(parents=True, exist_ok=True)
    evidence = output / ('demo-' + uuid.uuid4().hex)
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
    print('Demo evidence: ' + str(evidence), flush=True)
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
    stage('check', ['-s', 'res://tools/check/check_scripts.gd'])
    stage('architecture', ['-s', 'res://tools/check/check_architecture.gd'])
    selected = ['--output-directory=' + str(evidence),
                '--render-rate=' + args.render_rate, '--level=' + args.level]
    if args.scenario_file:
        selected += ['--scenario-file=' + str(args.scenario_file.resolve()),
                     '--demo-file=' + str(args.demo_file.resolve())]
    if args.tick_limit is not None:
        selected += ['--tick-limit=' + str(args.tick_limit)]
    if args.viewer:
        selected.append('--viewer')
    stage('driver', ['-s', 'res://tools/inspection/run_demo_scenario.gd', '--', *selected],
          headless=not args.viewer)
    status_path = evidence / 'playback.json'
    status = json.loads(status_path.read_text(encoding='utf-8'))
    if status.get('schema') != 'demo-playback-v1' or status.get('status') not in ('complete', 'incomplete'):
        raise RuntimeError('Missing terminal demo playback status: ' + str(status_path))
    from tools.inspection.compare_demo_trace import read_csv, ENTITY_COLUMNS
    rows = read_csv(evidence / 'frog.csv', allow_empty=True)
    entities = read_csv(evidence / 'frog.csv.entities.csv', ENTITY_COLUMNS, allow_empty=True)
    if len(rows) != status['elapsed_ticks']:
        raise RuntimeError('Demo CSV disagrees with committed playback ticks')
    frog_calls = {row['call'] for row in rows}
    if any(row['call'] not in frog_calls for row in entities):
        raise RuntimeError('Entity CSV contains calls absent from frog CSV')
    (evidence / 'run.json').write_text(json.dumps({
        'mode': 'viewer' if args.viewer else 'headless', 'render_rate': args.render_rate,
        'stage_seconds': stage_durations, 'status': status['status'],
    }, indent=2) + '\n', encoding='utf-8')
    print('Demo ' + status['status'] + ': ' + status.get('reason', '') + '; ' + str(evidence))
    return 0 if status['status'] == 'complete' else 3


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
