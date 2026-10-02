"""Compare authored headless and rendered terrain traces with an independent C corpus."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import uuid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--scenario-directory', type=Path, required=True)
    parser.add_argument('--reference', type=Path, required=True)
    parser.add_argument('--output-directory', type=Path, required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    output = args.output_directory.resolve()
    for protected in (repo, (repo.parent / 'froggy').resolve()):
        if output == protected or protected in output.parents:
            parser.error('Evidence must be outside both repositories')
    evidence = output / ('terrain-schedules-' + uuid.uuid4().hex)
    (evidence / 'profile').mkdir(parents=True)
    (evidence / 'temp').mkdir()
    env = os.environ.copy()
    env.pop('FROGGER_DATA_DIR', None)
    env.update(APPDATA=str(evidence / 'profile'), XDG_DATA_HOME=str(evidence / 'profile'),
               TEMP=str(evidence / 'temp'), TMP=str(evidence / 'temp'))
    startup = None
    if os.name == 'nt':
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 0
    def identities():
        paths = [path for path in (repo / 'src').rglob('*') if path.suffix in ('.gd', '.gdshader')]
        paths += [path for path in (repo / 'tools').glob('*') if path.suffix in ('.gd', '.py')]
        paths += list((repo / 'scenes').rglob('*.tscn')) + [repo / 'project.godot']
        return {str(path.relative_to(repo)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(paths)}
    def input_identities():
        return {'reference_sha256': hashlib.sha256(args.reference.read_bytes()).hexdigest(),
            'scenario_sha256': {str(index): hashlib.sha256((args.scenario_directory / f'integrated-{index}.json').read_bytes()).hexdigest() for index in range(4)}}
    source_identities = identities()
    input_hashes = input_identities()
    provenance = {'source_sha256': source_identities, **input_hashes}
    (evidence / 'provenance.json').write_text(json.dumps(provenance, indent=2))

    print(evidence, flush=True)

    def stage(name, arguments, headless=True):
        log = evidence / (name + '.log')
        command = [args.godot, '--disable-crash-handler', '--path', str(repo), '--log-file', str(log)]
        if headless:
            command.append('--headless')
        with (evidence / (name + '-process.log')).open('w', encoding='utf-8') as stream:
            result = subprocess.run(command + arguments, cwd=repo, env=env, startupinfo=startup,
                                    stdout=stream, stderr=subprocess.STDOUT, timeout=120)
        text = log.read_text(encoding='utf-8') if log.exists() else ''
        if result.returncode or not text or any(marker in text for marker in
                ('SCRIPT ERROR', 'Parse Error', 'Failed to load script', 'CHECK FAILED')):
            raise RuntimeError(f'{name} failed: {log}')

    stage('import', ['--import'])
    stage('check', ['-s', 'res://tools/check_scripts.gd'])
    print('Strict compilation complete', flush=True)
    comparisons = []
    for scenario in range(4):
        authored = args.scenario_directory / f'integrated-{scenario}.json'
        baseline = evidence / f'headless-{scenario}.jsonl'
        selected = ['--scenario-file=' + str(authored.resolve())]
        stage(f'headless-{scenario}', ['-s', 'res://tools/run_terrain_scenario.gd', '--',
                                     '--trace-jsonl=' + str(baseline), *selected])
        subprocess.run([sys.executable, str(repo / 'tools/compare_integrated_terrain.py'),
                        str(args.reference.resolve()), str(baseline), '--scenario', str(scenario)], check=True)
        for rate in (30, 60, 144):
            candidate = evidence / f'rendered-{scenario}-{rate}.jsonl'
            folder = evidence / f'capture-{scenario}-{rate}'
            stage(f'rendered-{scenario}-{rate}', ['res://scenes/tools/terrain_viewer.tscn', '--',
                  '--run-scenario', '--render-rate=' + str(rate), '--trace-jsonl=' + str(candidate),
                  '--screenshot-dir=' + str(folder), *selected], headless=False)
            subprocess.run([sys.executable, str(repo / 'tools/compare_run_trace.py'),
                            str(baseline), str(candidate)], check=True)
            subprocess.run([sys.executable, str(repo / 'tools/compare_integrated_terrain.py'),
                            str(args.reference.resolve()), str(candidate), '--scenario', str(scenario)], check=True)
            comparisons.append({'scenario': scenario, 'scheduled_render_rate': rate, 'pass': True})
    if identities() != source_identities or input_identities() != input_hashes:
        raise RuntimeError('Candidate code or reference/scenario inputs changed during the serialized batch')
    (evidence / 'comparison.json').write_text(json.dumps({'comparisons': comparisons,
        'scope': 'Explicit scheduled frame deltas; not measured host FPS', 'pass': True}, indent=2))
    print('All 12 full-trace schedule comparisons passed: ' + str(evidence), flush=True)


if __name__ == '__main__':
    main()
