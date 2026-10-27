"""Capture dedicated gameplay with optional keyboard stimuli and exact rule parity."""
import argparse
import os
import re
from pathlib import Path
import subprocess
import uuid
from godot_project import isolated_project


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT', 'godot'))
    parser.add_argument('--data-dir', type=Path, required=True)
    parser.add_argument('--route', type=Path)
    parser.add_argument('--level', choices=('ORG1', 'ORG2', 'ORG3', 'ORG4', 'ORG5', 'SUB1', 'FOR1', 'FOR2'), default='ORG1')
    parser.add_argument('--ticks', type=int, default=240)
    parser.add_argument('--flow-check', action='store_true', help='Idle through timeout, respawn, game over and keyboard restart')
    parser.add_argument('--resolution', default='640x480', help='Window size for aspect-ratio verification')
    parser.add_argument('--output-directory', type=Path, required=True)
    args = parser.parse_args()
    if args.flow_check and args.route:
        parser.error('--flow-check excludes --route')
    if not 1 <= args.ticks <= 10000:
        parser.error('--ticks must be 1..10000')
    if not re.fullmatch(r'[1-9][0-9]{1,4}x[1-9][0-9]{1,4}', args.resolution):
        parser.error('--resolution must be WIDTHxHEIGHT')
    repo = Path(__file__).resolve().parents[1]
    output = args.output_directory.resolve()
    for protected in (repo, (repo.parent / 'froggy').resolve()):
        if output == protected or protected in output.parents:
            parser.error('Output must be outside the repository and frozen froggy')
    route = args.route.resolve() if args.route else None
    if route and not route.is_file():
        parser.error('Route file does not exist')
    evidence = output / ('gameplay-' + uuid.uuid4().hex)
    evidence.mkdir(parents=True)
    profile = evidence / 'profile'
    profile.mkdir()
    temporary = evidence / 'temp'
    temporary.mkdir()
    project = isolated_project(repo, profile)
    env = os.environ.copy()
    env.update(APPDATA=str(profile), XDG_DATA_HOME=str(profile), TEMP=str(temporary), TMP=str(temporary))
    startup = None
    if os.name == 'nt':
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 0
    print('Gameplay evidence: ' + str(evidence), flush=True)
    stages = [('import', ['--import'], True),
              ('check', ['-s', 'res://tools/check_scripts.gd'], True),
              ('architecture', ['-s', 'res://tools/check_architecture.gd'], True),
              ('keyboard', ['-s', 'res://tools/probe_gameplay_capture.gd', '--',
                            '--data-dir=' + str(args.data_dir.resolve()), '--level=' + args.level,
                            '--route=' + (str(route) if route else ''), '--ticks=' + str(args.ticks), '--flow-check=' + str(args.flow_check).lower(), '--output=' + str(evidence / 'captures')], False)]
    for name, arguments, headless in stages:
        log = evidence / (name + '.log')
        command = [args.godot, '--disable-crash-handler', '--path', str(project), '--log-file', str(log)]
        if headless:
            command.append('--headless')
        else:
            command += ['--resolution', args.resolution]
        with (evidence / (name + '-process.log')).open('w', encoding='utf-8') as stream:
            result = subprocess.run(command + arguments, cwd=repo, env=env, startupinfo=startup,
                                    stdout=stream, stderr=subprocess.STDOUT, timeout=1800)
        text = log.read_text(encoding='utf-8') if log.exists() else ''
        if result.returncode or not text or any(marker in text for marker in
                ('SCRIPT ERROR', 'Parse Error', 'Failed to load script', 'CHECK FAILED', 'gameplay_capture: FAIL')):
            raise RuntimeError(f'{name} failed ({result.returncode}); see {log}')
        if name == 'keyboard' and 'gameplay_capture: PASS' not in text:
            raise RuntimeError('Keyboard probe did not confirm completion')
    print('Gameplay capture passed', flush=True)


if __name__ == '__main__':
    main()
