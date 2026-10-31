"""Verify a whole-map ORG1 keyboard input route with external captures and exact rule parity."""
import argparse
import os
from pathlib import Path
import subprocess
import uuid
from godot_project import isolated_project


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT', 'godot'))
    parser.add_argument('--route', type=Path)
    parser.add_argument('--output-directory', type=Path, required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    output = args.output_directory.resolve()
    for protected in (repo, (repo.parent / 'froggy').resolve()):
        if output == protected or protected in output.parents:
            parser.error('Output must be outside the repository and frozen froggy')
    route = (args.route or repo / 'tests/golden/fixtures/org1_keyboard_playthrough.json').resolve()
    if not route.is_file():
        parser.error('Route file does not exist')
    evidence = output / ('keyboard-' + uuid.uuid4().hex)
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
    print('Keyboard evidence: ' + str(evidence), flush=True)
    stages = [('import', ['--import'], True),
              ('check', ['-s', 'res://tools/check_scripts.gd'], True),
              ('keyboard', ['-s', 'res://tools/probe_org1_playthrough.gd', '--',
                            '--level=ORG1',
                            '--route=' + str(route), '--output=' + str(evidence / 'captures')], False)]
    for name, arguments, headless in stages:
        log = evidence / (name + '.log')
        command = [args.godot, '--disable-crash-handler', '--path', str(project), '--log-file', str(log)]
        if headless:
            command.append('--headless')
        with (evidence / (name + '-process.log')).open('w', encoding='utf-8') as stream:
            result = subprocess.run(command + arguments, cwd=repo, env=env, startupinfo=startup,
                                    stdout=stream, stderr=subprocess.STDOUT, timeout=600)
        text = log.read_text(encoding='utf-8') if log.exists() else ''
        if result.returncode or not text or any(marker in text for marker in
                ('SCRIPT ERROR', 'Parse Error', 'Failed to load script', 'CHECK FAILED', 'org1_playthrough: FAIL')):
            raise RuntimeError(f'{name} failed ({result.returncode}); see {log}')
        if name == 'keyboard' and 'org1_playthrough: PASS' not in text:
            raise RuntimeError('Keyboard probe did not confirm completion')
    print('Keyboard playthrough passed', flush=True)


if __name__ == '__main__':
    main()
