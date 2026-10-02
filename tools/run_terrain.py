"""Run one terrain scenario with an isolated Godot profile and external evidence."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import uuid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT', 'godot'))
    parser.add_argument('--scenario', choices=('normal', 'blocked', 'buffer'), default='normal')
    parser.add_argument('--scenario-file', type=Path)
    parser.add_argument('--data-dir', type=Path, help='Optional player data for the rendered frog')
    parser.add_argument('--seed', type=int)
    parser.add_argument('--tick-limit', type=int)
    parser.add_argument('--render-rate', type=int, choices=(30, 60, 144), default=60)
    parser.add_argument('--level', help='Optional single-player map code for terrain inspection')
    parser.add_argument('--entity-reactions', choices=('pop',), help='Enable integrated FORM reactions')
    parser.add_argument('--output-directory', type=Path, required=True)
    parser.add_argument('--viewer', action='store_true', help='Use the rendered scene and save a screenshot')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    output = args.output_directory.resolve()
    for protected in (repo, (repo.parent / 'froggy').resolve()):
        if output == protected or protected in output.parents:
            parser.error('Output must be outside this repository and frozen froggy')
    output.mkdir(parents=True, exist_ok=True)
    evidence = output / ('terrain-' + uuid.uuid4().hex)
    profile = evidence / 'profile'
    temporary = evidence / 'temp'
    profile.mkdir(parents=True)
    temporary.mkdir()
    env = os.environ.copy()
    env.update(APPDATA=str(profile), XDG_DATA_HOME=str(profile), TEMP=str(temporary), TMP=str(temporary))
    startup = None
    if os.name == 'nt':
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 0
    print('Terrain evidence: ' + str(evidence), flush=True)

    def stage(name, arguments, headless=True):
        log = evidence / (name + '.log')
        command = [args.godot, '--disable-crash-handler', '--path', str(repo), '--log-file', str(log)]
        if headless:
            command.append('--headless')
        command += arguments
        with (evidence / (name + '-process.log')).open('w', encoding='utf-8') as stream:
            result = subprocess.run(command, cwd=repo, env=env, startupinfo=startup,
                                    stdout=stream, stderr=subprocess.STDOUT, timeout=120)
        text = log.read_text(encoding='utf-8') if log.exists() else ''
        if result.returncode or not text or any(marker in text for marker in (
                'SCRIPT ERROR', 'Parse Error', 'Failed to load script', 'CHECK FAILED')):
            raise RuntimeError(f'{name} failed ({result.returncode}); see {log}')

    stage('import', ['--import'])
    stage('check', ['-s', 'res://tools/check_scripts.gd'])
    selected = ['--scenario-file=' + str(args.scenario_file.resolve())] if args.scenario_file else ['--scenario=' + args.scenario]
    selected += ['--trace-csv=' + str(evidence / 'trace.csv')]
    selected += ['--trace-jsonl=' + str(evidence / 'trace.jsonl')]
    for key, value in (('seed', args.seed), ('tick-limit', args.tick_limit)):
        if value is not None:
            selected.append('--' + key + '=' + str(value))
    selected.append('--render-rate=' + str(args.render_rate))
    if args.data_dir:
        selected += ['--data-dir=' + str(args.data_dir.resolve())]
    if args.level:
        selected += ['--level=' + args.level]
    if args.entity_reactions:
        selected += ['--entity-reactions=' + args.entity_reactions]
    if args.viewer:
        stage('viewer', ['res://scenes/tools/terrain_viewer.tscn', '--', '--run-scenario',
                         '--screenshot-dir=' + str(evidence), *selected], headless=False)
    else:
        stage('driver', ['-s', 'res://tools/run_terrain_scenario.gd', '--', *selected])
    if not (evidence / 'trace.csv').is_file():
        raise RuntimeError('Scenario did not produce its trace: ' + str(evidence))
    print('Terrain run succeeded: ' + str(evidence / 'trace.csv'))


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
