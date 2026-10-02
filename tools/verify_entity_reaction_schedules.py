"""Compare integrated FORM-reaction traces at headless and three render schedules."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import uuid


PHASES = ('control', 'move', 'collision', 'camera', 'final')
RATES = (30, 60, 144)
CAPTURES = ('before-contact', 'hit', 'pop-animation', 'death-camera')


def read_trace(path):
    rows = [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines() if line.strip()]
    if not rows or rows[0].get('schema') != 'entity-pop-v1':
        raise ValueError(f'{path}: missing entity-pop-v1 metadata')
    if (len(rows) - 1) % len(PHASES):
        raise ValueError(f'{path}: incomplete phase sequence')
    limit = rows[0].get('tick_limit')
    if type(limit) is not int or not 0 <= limit <= 100000:
        raise ValueError(f'{path}: invalid tick limit')
    for index, row in enumerate(rows[1:]):
        expected = (index // len(PHASES), PHASES[index % len(PHASES)])
        if (row.get('tick'), row.get('phase')) != expected:
            raise ValueError(f'{path}: expected {expected}, got {(row.get("tick"), row.get("phase"))}')
        if row.get('error') or not isinstance(row.get('state'), dict):
            raise ValueError(f'{path}: invalid phase at {expected}')
        if row.get('phase') == 'final':
            state = row['state']
            entities = state.get('entities')
            if not isinstance(entities, dict) or entities.get('tick_index') != state.get('tick_index'):
                raise ValueError(f'{path}: entity and frog ticks differ at {expected}')
            if state.get('completed') and index != len(rows) - 2:
                raise ValueError(f'{path}: records continue after completion')
    if (len(rows) - 1) // len(PHASES) > limit:
        raise ValueError(f'{path}: trace exceeds tick limit')
    if not rows[-1]['state'].get('completed'):
        raise ValueError(f'{path}: run did not complete within its tick limit')
    accepted = [(row, contact) for row in rows[1:] if row.get('phase') == 'final'
                for contact in row.get('entity_contacts', [])
                if contact.get('status') == 'pop' and contact.get('hit') is True
                and contact.get('kill_animation') == 23]
    if not accepted:
        raise ValueError(f'{path}: no accepted POP reaction')
    if rows[0].get('source_id', '').endswith(':DES2'):
        row, contact = accepted[0]
        if row.get('tick') != 4 or contact.get('contact', {}).get('entity_index') != 46:
            raise ValueError(f'{path}: DES2 first POP must be command tick 4, entity 46')
        state = row['state']
        if state.get('world_position') != [-683, -1576, 2176] or state.get('death_entity_index') != 46:
            raise ValueError(f'{path}: DES2 first POP position/death identity differs')
    return rows


def check_png(path):
    with path.open('rb') as stream:
        header = stream.read(24)
    if len(header) != 24 or header[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError(f'{path}: invalid PNG')
    dimensions = struct.unpack('>II', header[16:24])
    if dimensions != (640, 480):
        raise ValueError(f'{path}: expected 640x480 capture, got {dimensions}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT', 'godot'))
    selection = parser.add_mutually_exclusive_group(required=True)
    selection.add_argument('--scenario-file', type=Path)
    selection.add_argument('--data-dir', type=Path)
    parser.add_argument('--case-index', type=int, default=0,
                        help='Case inside a scenario file with a cases array (default: 0)')
    parser.add_argument('--level', default='DES2', help='Retail level code (default: DES2)')
    parser.add_argument('--output-directory', type=Path, required=True)
    args = parser.parse_args()

    repo = Path(__file__).resolve().parents[1]

    def source_identities():
        paths = [path for path in (repo / 'src').rglob('*') if path.suffix in ('.gd', '.gdshader')]
        paths += [path for path in (repo / 'tools').glob('*') if path.suffix in ('.gd', '.py')]
        paths += list((repo / 'scenes').rglob('*.tscn')) + [repo / 'project.godot']
        return {str(path.relative_to(repo)): hashlib.sha256(path.read_bytes()).hexdigest()
                for path in sorted(paths)}
    output = args.output_directory.resolve()
    for protected in (repo, (repo.parent / 'froggy').resolve()):
        if output == protected or protected in output.parents:
            parser.error('Evidence must be outside this repository and froggy')
    evidence = output / ('entity-pop-schedules-' + uuid.uuid4().hex)
    profile = evidence / 'profile'
    temporary = evidence / 'temp'
    profile.mkdir(parents=True)
    temporary.mkdir()
    env = os.environ.copy()
    env.pop('FROGGER_DATA_DIR', None)
    env.update(APPDATA=str(profile), XDG_DATA_HOME=str(profile), TEMP=str(temporary), TMP=str(temporary))
    startup = None
    if os.name == 'nt':
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 0
    selected = ['--entity-reactions=pop']
    if args.scenario_file:
        authored = json.loads(args.scenario_file.read_text(encoding='utf-8'))
        if isinstance(authored, dict) and isinstance(authored.get('cases'), list):
            if not 0 <= args.case_index < len(authored['cases']):
                parser.error('case-index is outside the scenario cases array')
            authored = authored['cases'][args.case_index]
            if not isinstance(authored, dict):
                parser.error('Selected scenario case must be an object')
            authored.setdefault('name', f'integrated-entity-{args.case_index}')
            selected_path = evidence / 'selected-scenario.json'
            selected_path.write_text(json.dumps(authored, indent=2), encoding='utf-8')
        else:
            selected_path = args.scenario_file.resolve()
        selected.append('--scenario-file=' + str(selected_path))
    else:
        selected.extend(('--data-dir=' + str(args.data_dir.resolve()), '--level=' + args.level))
    identity = hashlib.sha256(args.scenario_file.read_bytes()).hexdigest() if args.scenario_file else None
    source_hashes = source_identities()
    (evidence / 'provenance.json').write_text(json.dumps({'source_sha256': source_hashes,
        'scenario_sha256': identity, 'retail_data_dir': str(args.data_dir.resolve()) if args.data_dir else None},
        indent=2), encoding='utf-8')
    print('Entity POP evidence: ' + str(evidence), flush=True)

    def stage(name, arguments, headless=True):
        log = evidence / (name + '.log')
        command = [args.godot, '--disable-crash-handler', '--path', str(repo), '--log-file', str(log)]
        if headless:
            command.append('--headless')
        command.extend(arguments)
        with (evidence / (name + '-process.log')).open('w', encoding='utf-8') as stream:
            result = subprocess.run(command, cwd=repo, env=env, startupinfo=startup,
                                    stdout=stream, stderr=subprocess.STDOUT, timeout=180)
        log_text = log.read_text(encoding='utf-8') if log.exists() else ''
        if result.returncode or not log_text or any(marker in log_text for marker in
                ('SCRIPT ERROR', 'Parse Error', 'Failed to load script', 'CHECK FAILED')):
            raise RuntimeError(f'{name} failed ({result.returncode}); see {log}')

    stage('import', ['--import'])
    stage('check', ['-s', 'res://tools/check_scripts.gd'])
    baseline = evidence / 'headless.jsonl'
    stage('headless', ['-s', 'res://tools/run_terrain_scenario.gd', '--',
                       '--trace-jsonl=' + str(baseline), *selected])
    reference = read_trace(baseline)
    for rate in RATES:
        rendered = evidence / f'rendered-{rate}.jsonl'
        captures = evidence / f'captures-{rate}'
        stage(f'rendered-{rate}', ['res://scenes/tools/terrain_viewer.tscn', '--', '--run-scenario',
              '--render-rate=' + str(rate), '--trace-jsonl=' + str(rendered),
              '--screenshot-dir=' + str(captures), *selected], headless=False)
        candidate = read_trace(rendered)
        if len(candidate) != len(reference):
            raise ValueError(f'{rate} Hz trace has {len(candidate)} rows; expected {len(reference)}')
        for index, (expected, actual) in enumerate(zip(reference, candidate)):
            if expected != actual:
                location = 'metadata' if index == 0 else f'tick {(index - 1) // 5} phase {PHASES[(index - 1) % 5]}'
                raise ValueError(f'{rate} Hz first difference at {location}')
        for name in CAPTURES:
            check_png(captures / f'entity-{name}.png')
        print(f'{rate} Hz exact trace and four 640x480 captures: {rendered}', flush=True)
    if source_identities() != source_hashes:
        raise RuntimeError('Candidate source changed during schedule verification')
    if args.scenario_file and hashlib.sha256(args.scenario_file.read_bytes()).hexdigest() != identity:
        raise RuntimeError('Scenario changed during schedule verification')
    (evidence / 'comparison.json').write_text(json.dumps({'schema': 'entity-pop-v1',
        'rates': list(RATES), 'phase_records': len(reference) - 1, 'completed': True,
        'scenario_sha256': identity, 'pass': True}, indent=2), encoding='utf-8')
    print('Entity POP schedules match exactly: ' + str(evidence), flush=True)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
