"""Measure real ORG1 host throughput; keep reports and isolated profiles external."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import uuid
from godot_profile import ProfileCapture


def meets_target(report):
    """Require the actual workload and display state, not just requested CLI flags."""
    return (report['accepted'] and report['window_size'] == [2560, 1440]
            and report['renderer'] == 'gl_compatibility' and report['vsync'] == 0
            and report['max_fps'] == 0 and report['draw_calls_max'] > 0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT', 'godot'))
    parser.add_argument('--data-dir', type=Path, required=True)
    parser.add_argument('--output-directory', type=Path, required=True)
    parser.add_argument('--resolution', choices=('640x480', '2560x1440'), default='2560x1440')
    parser.add_argument('--route', choices=('round-trip', 'diver', 'both'), default='both')
    parser.add_argument('--repetitions', type=int, default=3)
    parser.add_argument('--mode', choices=('full', 'paused', 'simulation', 'no-inspector'), default='full')
    parser.add_argument('--sync', choices=('default', 'uncapped'), default='uncapped')
    parser.add_argument('--smoothing', choices=('true', 'false'), default='true')
    parser.add_argument('--require-target', action='store_true')
    parser.add_argument('--profile', action='store_true', help='Separate diagnostic run with Godot script profiler')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    output = args.output_directory.resolve()
    for protected in (repo, (repo.parent / 'froggy').resolve()):
        if output == protected or protected in output.parents:
            parser.error('Output must be outside the repository and frozen froggy')
    if args.repetitions < 1:
        parser.error('Repetitions must be positive')
    if args.require_target and (args.mode != 'full' or args.sync != 'uncapped' or
                               args.smoothing != 'true' or args.resolution != '2560x1440' or
                               args.route != 'both' or args.repetitions < 3 or args.profile):
        parser.error('Acceptance requires both full routes, three repetitions, smooth uncapped 1440p, no profiler')
    evidence = output / ('performance-' + uuid.uuid4().hex)
    (evidence / 'profile').mkdir(parents=True)
    (evidence / 'temp').mkdir()
    env = os.environ.copy()
    env.update(APPDATA=str(evidence / 'profile'), XDG_DATA_HOME=str(evidence / 'profile'),
               TEMP=str(evidence / 'temp'), TMP=str(evidence / 'temp'))
    startup = None
    if os.name == 'nt':
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 0
    print('Performance evidence: ' + str(evidence), flush=True)

    def stage(name, arguments, headless=False):
        log = evidence / (name + '.log')
        command = [args.godot, '--disable-crash-handler', '--path', str(repo), '--log-file', str(log)]
        if headless:
            command.append('--headless')
        capture = ProfileCapture(evidence / (name + '-profile.json')) if args.profile and not headless else None
        if capture:
            command += ['--remote-debug', f'tcp://127.0.0.1:{capture.port}']
        command += arguments
        with (evidence / (name + '-process.log')).open('w', encoding='utf-8') as stream:
            result = subprocess.run(command, cwd=repo, env=env, startupinfo=startup,
                                    stdout=stream, stderr=subprocess.STDOUT, timeout=1200)
        if capture:
            capture.finish()
        text = log.read_text(encoding='utf-8') if log.exists() else ''
        if result.returncode or not text or any(marker in text for marker in
                ('SCRIPT ERROR', 'Parse Error', 'Failed to load script', 'CHECK FAILED', 'ERROR:')):
            raise RuntimeError(f'{name} failed ({result.returncode}); see {log}')
        for line in text.splitlines():
            if line.startswith('terrain_performance:'):
                print(line, flush=True)

    stage('import', ['--import'], True)
    stage('check', ['-s', 'res://tools/check_scripts.gd'], True)
    sources = [path for folder in ('src', 'tools', 'scenes') for path in (repo / folder).rglob('*')
               if path.suffix in ('.gd', '.gdshader', '.json', '.tscn', '.py')]
    sources.append(repo / 'project.godot')
    identities = {str(path.relative_to(repo)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}
    (evidence / 'provenance.json').write_text(json.dumps(dict(arguments=vars(args) | {
        'data_dir': str(args.data_dir), 'output_directory': str(output)}, sources=identities), indent=2))
    reports = []
    for route in (('round-trip', 'diver') if args.route == 'both' else (args.route,)):
        fixture = 'org1_turtle_log_bank.json' if route == 'round-trip' else 'org1_attached_diver.json'
        for repetition in range(args.repetitions):
            name = f'{route}-{repetition + 1}'
            flags = ['--resolution', args.resolution]
            if args.sync == 'uncapped':
                flags += ['--disable-vsync', '--max-fps', '0']
            stage(name, [*flags, '-s', 'res://tools/probe_terrain_performance.gd', '--',
                         '--level=ORG1', '--exploration=org1-turtle-log-bank',
                         '--data-dir=' + str(args.data_dir.resolve()),
                         '--scenario-file=' + str(repo / 'tests/golden/fixtures' / fixture),
                         '--performance-mode=' + args.mode, '--smoothing=' + args.smoothing,
                         '--performance-output=' + str(evidence / (name + '.json'))])
            report = json.loads((evidence / (name + '.json')).read_text())
            report.pop('frame_ms', None)
            report.pop('tick_frame_ms', None)
            reports.append(report)
    if identities != {str(path.relative_to(repo)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}:
        raise RuntimeError('Sources changed during measurement')
    accepted = all(meets_target(report) for report in reports)
    (evidence / 'summary.json').write_text(json.dumps(dict(accepted=accepted, runs=reports), indent=2))
    if args.require_target and not accepted:
        raise RuntimeError('Performance acceptance failed; see ' + str(evidence / 'summary.json'))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
