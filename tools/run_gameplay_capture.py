"""Capture dedicated gameplay with optional keyboard stimuli and exact rule parity."""
import argparse
import os
import re
from pathlib import Path
import subprocess
import uuid
from godot_project import isolated_project

LEVELS = ('ORG1', 'ORG2', 'ORG3', 'ORG4', 'ORG5', 'SUB1', 'FOR1', 'FOR2', 'VOL1', 'VOL2', 'VOL3', 'CAV1', 'CAV3', 'CAV4', 'DES1', 'DES2', 'DES3', 'DES4', 'DES5', 'JUN1', 'SWP1', 'SWP2', 'SWP3', 'SWP4', 'SWP5', 'SKY1', 'SKY2', 'SKY3', 'SKY4')
RENDERING_PROFILES = ('retail', 'modern')
RENDERING_METHODS = ('forward_plus', 'gl_compatibility')
PROFILE_METHODS = {'modern': 'forward_plus'}
FAILURE_MARKERS = ('SCRIPT ERROR', 'Parse Error', 'Failed to load script', 'CHECK FAILED', 'gameplay_capture: FAIL')


def add_rendering_arguments(parser):
    """Add the rendering profile and the explicit engine rendering method override."""
    parser.add_argument('--rendering', choices=RENDERING_PROFILES, default='retail',
                        help='Rendering profile forwarded to the game as --rendering=<profile>')
    parser.add_argument('--rendering-method', choices=RENDERING_METHODS,
                        help='Engine rendering method; overrides the one the profile selects')


def rendering_method(profile, override=None):
    """The engine rendering method to request, or None for the project default."""
    return override or PROFILE_METHODS.get(profile)


def engine_arguments(method):
    """Engine options that select a rendering method before the scene or script."""
    return ['--rendering-method', method] if method else []


def shader_error(text):
    """The first log line reporting a shader compilation error, or None."""
    for line in text.splitlines():
        if 'SHADER ERROR' in line:
            return line.strip()
    return None


def log_failure(text):
    """Why a Godot log fails the capture, or None when it passes these markers."""
    line = shader_error(text)
    if line:
        return 'shader error: ' + line
    for marker in FAILURE_MARKERS:
        if marker in text:
            return marker
    return None


def keyboard_arguments(level, route, ticks, flow_check, output, rendering, game_arguments=()):
    """Script and user arguments of the windowed keyboard capture stage; game arguments follow."""
    return ['-s', 'res://tools/probe_gameplay_capture.gd', '--',
            '--level=' + level, '--route=' + (str(route) if route else ''),
            '--ticks=' + str(ticks), '--flow-check=' + str(flow_check).lower(),
            '--output=' + str(output), '--rendering=' + rendering] + list(game_arguments)


def stage_command(godot, project, log, headless, resolution, method, arguments):
    """The Godot command line of one capture stage."""
    command = [godot, '--disable-crash-handler', '--path', str(project), '--log-file', str(log)]
    if headless:
        command.append('--headless')
    else:
        command += ['--resolution', resolution] + engine_arguments(method)
    return command + arguments


def capture_stages(args, route, evidence):
    """Name, arguments and headless flag of every stage, in order."""
    return [('import', ['--import'], True),
            ('check', ['-s', 'res://tools/check_scripts.gd'], True),
            ('architecture', ['-s', 'res://tools/check_architecture.gd'], True),
            ('keyboard', keyboard_arguments(args.level, route, args.ticks, args.flow_check,
                                            evidence / 'captures', args.rendering,
                                            args.game_argument), False)]


def parse_arguments(argv=None):
    """Parse and validate the command line."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT', 'godot'))
    parser.add_argument('--route', type=Path)
    parser.add_argument('--level', choices=LEVELS, default='ORG1')
    parser.add_argument('--ticks', type=int, default=240)
    parser.add_argument('--flow-check', action='store_true', help='Idle through timeout, respawn, game over and keyboard restart')
    parser.add_argument('--resolution', default='640x480', help='Window size for aspect-ratio verification')
    parser.add_argument('--output-directory', type=Path, required=True)
    parser.add_argument('--game-argument', action='append', default=[], metavar='ARGUMENT',
                        help='Extra user argument for the game, given as --game-argument=--effect-shadows=retail; repeatable')
    add_rendering_arguments(parser)
    args = parser.parse_args(argv)
    if args.flow_check and args.route:
        parser.error('--flow-check excludes --route')
    if not 1 <= args.ticks <= 10000:
        parser.error('--ticks must be 1..10000')
    if not re.fullmatch(r'[1-9][0-9]{1,4}x[1-9][0-9]{1,4}', args.resolution):
        parser.error('--resolution must be WIDTHxHEIGHT')
    return parser, args


def main():
    parser, args = parse_arguments()
    repo = Path(__file__).resolve().parents[1]
    output = args.output_directory.resolve()
    for protected in (repo, (repo.parent / 'froggy').resolve()):
        if output == protected or protected in output.parents:
            parser.error('Output must be outside the repository and frozen froggy')
    route = args.route.resolve() if args.route else None
    if route and not route.is_file():
        parser.error('Route file does not exist')
    method = rendering_method(args.rendering, args.rendering_method)
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
    for name, arguments, headless in capture_stages(args, route, evidence):
        log = evidence / (name + '.log')
        command = stage_command(args.godot, project, log, headless, args.resolution, method, arguments)
        with (evidence / (name + '-process.log')).open('w', encoding='utf-8') as stream:
            result = subprocess.run(command, cwd=repo, env=env, startupinfo=startup,
                                    stdout=stream, stderr=subprocess.STDOUT, timeout=1800)
        text = log.read_text(encoding='utf-8') if log.exists() else ''
        failure = log_failure(text)
        if result.returncode or not text or failure:
            raise RuntimeError(f'{name} failed ({result.returncode}{", " + failure if failure else ""}); see {log}')
        if name == 'keyboard' and 'gameplay_capture: PASS' not in text:
            raise RuntimeError('Keyboard probe did not confirm completion')
    print('Gameplay capture passed', flush=True)


if __name__ == '__main__':
    main()
