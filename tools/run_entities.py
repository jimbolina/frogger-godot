"""Inspect attached entities with isolated Godot state and external JSONL evidence."""

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
    parser.add_argument('--scenario', choices=('shared-path',), default='shared-path')
    parser.add_argument('--level', help='Map code from the imported assets; synthetic when omitted')
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
    if args.tick_limit is not None and not 0 <= args.tick_limit <= 100000:
        parser.error('--tick-limit must be in 0..100000')
    output.mkdir(parents=True, exist_ok=True)
    evidence = output / ('entity-' + uuid.uuid4().hex)
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
    print('Entity evidence: ' + str(evidence), flush=True)
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
    selected = ['--scenario=' + args.scenario,
                '--trace-jsonl=' + str(evidence / 'trace.jsonl'),
                '--render-rate=' + str(args.render_rate)]
    if args.level:
        selected += ['--level=' + args.level]
    if args.tick_limit is not None:
        selected += ['--tick-limit=' + str(args.tick_limit)]
    if args.viewer:
        stage('viewer', ['res://scenes/tools/map_viewer.tscn', '--', '--run-entity-scenario',
                         '--screenshot-dir=' + str(evidence), *selected], headless=False)
    else:
        stage('driver', ['-s', 'res://tools/run_entity_scenario.gd', '--', *selected])
    trace = evidence / 'trace.jsonl'
    if not trace.is_file():
        raise RuntimeError('Entity scenario did not produce its trace: ' + str(evidence))
    rows = trace.read_text(encoding='utf-8').splitlines()
    if not rows:
        raise RuntimeError('Entity scenario produced an empty trace: ' + str(evidence))
    metadata = json.loads(rows[0])
    if metadata.get('schema') != 'entity-contact-v1':
        raise RuntimeError('Entity trace has an unknown schema: ' + str(trace))
    if len(rows) != metadata['tick_limit'] + 2:
        raise RuntimeError('Entity trace has the wrong tick count: ' + str(trace))
    (evidence / 'run.json').write_text(json.dumps({
        'mode': 'viewer' if args.viewer else 'headless',
        'scenario': args.scenario,
        'level': args.level,
        'render_rate': args.render_rate if args.viewer else None,
        'stage_seconds': stage_durations,
        'snapshot_count': len(rows) - 1,
    }, indent=2) + '\n', encoding='utf-8')
    print('Entity run succeeded: ' + str(trace))


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
