"""Compare complete visibility lifecycle traces at headless, 30, 60 and 144 Hz."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import uuid
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools import REPO_ROOT, TOOLS_ROOT


PHASES = ('control', 'move', 'collision', 'camera', 'final')
RATES = (30, 60, 144)
CAPTURES = ('lifecycle-initial', 'lifecycle-create', 'lifecycle-pending',
            'lifecycle-destroy', 'lifecycle-recreate', 'lifecycle-absent',
            'lifecycle-return')


def read_trace(path: Path, tick_limit: int, safe_kind: str = '') -> list[dict]:
    rows = [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines()
            if line.strip()]
    if not rows or rows[0].get('schema') != 'entity-lifecycle-v1':
        raise ValueError(f'{path}: missing entity-lifecycle-v1 metadata')
    if rows[0].get('entity_lifetime') != 'visibility' or rows[0].get('tick_limit') != tick_limit:
        raise ValueError(f'{path}: incorrect lifecycle mode or tick limit')
    if len(rows) != 1 + 5 * tick_limit:
        raise ValueError(f'{path}: incomplete {tick_limit}-tick phase sequence')
    for index, row in enumerate(rows[1:]):
        expected = (index // 5, PHASES[index % 5])
        if (row.get('tick'), row.get('phase')) != expected:
            raise ValueError(f'{path}: expected {expected}, got {(row.get("tick"), row.get("phase"))}')
        if row.get('error') or not isinstance(row.get('state'), dict):
            raise ValueError(f'{path}: invalid phase at {expected}')
        state = row['state']
        entity_state = row.get('entity_lifecycle')
        if not isinstance(entity_state, dict) or not entity_state.get('lifecycle_enabled'):
            raise ValueError(f'{path}: missing committed lifecycle state at {expected}')
        entity_tick = entity_state.get('tick_index')
        frog_tick = state.get('tick_index')
        expected_entity_tick = frog_tick if row['phase'] == 'final' else frog_tick + 1
        if entity_tick != expected_entity_tick:
            raise ValueError(f'{path}: frog/entity tick mismatch at {expected}')
        if not isinstance(entity_state.get('selected_groups'), list):
            raise ValueError(f'{path}: missing ordered selected groups at {expected}')
        if not isinstance(entity_state.get('live_order'), list):
            raise ValueError(f'{path}: missing ordered live list at {expected}')
    finals = [row for row in rows[1:] if row['phase'] == 'final']
    if len(finals) != tick_limit:
        raise ValueError(f'{path}: scenario ended before its tick limit')
    if safe_kind:
        links = [row['state'].get('current_entity_index', -1) for row in finals]
        if not any(link >= 0 for link in links):
            raise ValueError(f'{path}: SAFE lifecycle never attached')
        if safe_kind == 'moving' and not any(before >= 0 and after < 0
                                             for before,after in zip(links,links[1:])):
            raise ValueError(f'{path}: moving SAFE lifecycle never departed')
    if tick_limit == 336:
        golden_path = REPO_ROOT / 'tests/golden/synthetic/lifecycle_integrated.tsv'
        golden = list(csv.DictReader(golden_path.open(encoding='utf-8'),delimiter='\t'))
        if len(golden) != len(finals):
            raise ValueError(f'{path}: independent integrated golden row count differs')
        for row,expected in zip(finals,golden):
            tick = row['tick']
            state = row['state']
            lifecycle = row['entity_lifecycle']
            observed = {entity['entity_index']:entity for entity in lifecycle['entities']}
            def joined(values):
                return ','.join(str(value) for value in values) or '-'
            claims = {
                'frog_x':state['world_position'][0],
                'frog_y':state['world_position'][1],
                'camera_x':state['camera']['source_world'][0],
                'camera_y':state['camera']['source_world'][1],
                'camera_z':state['camera']['source_world'][2],
                'selected_groups':joined(lifecycle['selected_groups']),
                'static_live':int(observed[2]['live']),
                'static_pending':int(observed[2]['destroy_pending']),
                'static_generation':observed[2]['generation'],
                'moving_live':int(observed[9]['live']),
                'moving_pending':int(observed[9]['destroy_pending']),
                'moving_generation':observed[9]['generation'],
                'live_order':joined(lifecycle['live_order']),
                'events':joined(lifecycle['lifecycle_events']),
                'moving_distance':observed[9]['path']['segment_distance'],
            }
            if tick != int(expected['tick']):
                raise ValueError(f'{path}: independent tick order differs at {tick}')
            for field,actual in claims.items():
                if str(actual) != expected[field]:
                    raise ValueError(f'{path}: tick {tick} {field}: {actual} != {expected[field]}')
        events = [(row['tick'], event) for row in finals
                  for event in row['entity_lifecycle']['lifecycle_events']]
        if not any(event.startswith('create:') for _,event in events):
            raise ValueError(f'{path}: no creation')
        if not any(event.startswith('destroy:') for _,event in events):
            raise ValueError(f'{path}: no destruction')
        if not any(event.endswith(':2') and event.startswith('create:') for _,event in events):
            raise ValueError(f'{path}: no generation-two recreation')
        moving = [(row['tick'], next((e for e in row['entity_lifecycle']['entities']
                                      if e['entity_index'] == 9), None)) for row in finals]
        dormant = [(tick, entity['path']['segment_distance']) for tick,entity in moving
                   if entity is not None and not entity['live']]
        if len(dormant) < 2 or len({distance for _,distance in dormant}) < 2:
            raise ValueError(f'{path}: dormant path did not continue')
    return rows


def check_png(path: Path) -> None:
    with path.open('rb') as stream:
        header = stream.read(24)
    if len(header) != 24 or header[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError(f'{path}: invalid PNG')
    if struct.unpack('>II', header[16:24]) != (640, 480):
        raise ValueError(f'{path}: expected 640x480 capture')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT', 'godot'))
    parser.add_argument('--scenario-file', type=Path,
                        default=Path('tests/golden/fixtures/lifecycle_integrated.json'))
    parser.add_argument('--output-directory', type=Path, required=True)
    args = parser.parse_args()
    repo = REPO_ROOT
    scenario = args.scenario_file.resolve()
    if not scenario.is_file():
        parser.error('scenario-file does not exist')
    authored = json.loads(scenario.read_text(encoding='utf-8'))
    tick_limit = authored.get('tick_limit')
    if type(tick_limit) is not int or not 1 <= tick_limit <= 100000:
        parser.error('scenario must have an integer tick_limit in 1..100000')
    output = args.output_directory.resolve()
    for protected in (repo, (repo.parent / 'froggy').resolve()):
        if output == protected or protected in output.parents:
            parser.error('Evidence must be outside this repository and froggy')
    evidence = output / ('entity-lifecycle-schedules-' + uuid.uuid4().hex)
    profile, temporary = evidence / 'profile', evidence / 'temp'
    profile.mkdir(parents=True)
    temporary.mkdir()
    environment = os.environ.copy()
    environment.pop('FROGGER_DATA_DIR', None)
    environment.update(APPDATA=str(profile), XDG_DATA_HOME=str(profile),
                       TEMP=str(temporary), TMP=str(temporary))
    startup = None
    if os.name == 'nt':
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 0
    def source_hashes() -> dict[str,str]:
        paths = [p for p in (repo / 'src').rglob('*.gd')]
        paths += [p for p in TOOLS_ROOT.rglob('*') if p.suffix in ('.gd','.py')]
        paths += list((repo / 'scenes').rglob('*.tscn')) + [repo / 'project.godot']
        return {str(p.relative_to(repo)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in sorted(paths)}
    before = source_hashes()
    scenario_hash = hashlib.sha256(scenario.read_bytes()).hexdigest()
    (evidence / 'provenance.json').write_text(json.dumps({
        'source_sha256': before, 'scenario_sha256': scenario_hash},indent=2),encoding='utf-8')
    print('Lifecycle evidence: ' + str(evidence), flush=True)
    selected = ['--scenario-file=' + str(scenario), '--entity-reactions=platforms',
                '--entity-lifecycle=visibility']
    def stage(name: str, arguments: list[str], headless: bool = True) -> None:
        log = evidence / (name + '.log')
        command = [args.godot, '--disable-crash-handler', '--path', str(repo),
                   '--log-file', str(log)]
        if headless:
            command.append('--headless')
        command.extend(arguments)
        with (evidence / (name + '-process.log')).open('w',encoding='utf-8') as stream:
            result = subprocess.run(command,cwd=repo,env=environment,startupinfo=startup,
                                    stdout=stream,stderr=subprocess.STDOUT,timeout=360)
        content = log.read_text(encoding='utf-8') if log.exists() else ''
        if result.returncode or not content or any(marker in content for marker in
                ('SCRIPT ERROR','Parse Error','Failed to load script','CHECK FAILED')):
            raise RuntimeError(f'{name} failed ({result.returncode}); see {log}')
    stage('import',['--import'])
    stage('check',['-s','res://tools/check/check_scripts.gd'])
    baseline = evidence / 'headless.jsonl'
    stage('headless',['-s','res://tools/inspection/run_terrain_scenario.gd','--',
                      '--trace-jsonl=' + str(baseline),*selected])
    safe_kind = 'moving' if 'lifecycle_safe_moving' in scenario.name else 'static' if 'lifecycle_safe_static' in scenario.name else ''
    reference = read_trace(baseline,tick_limit,safe_kind)
    for rate in RATES:
        rendered = evidence / f'rendered-{rate}.jsonl'
        captures = evidence / f'captures-{rate}'
        stage(f'rendered-{rate}',['res://scenes/tools/terrain_viewer.tscn','--',
              '--run-scenario','--render-rate=' + str(rate),
              '--trace-jsonl=' + str(rendered), '--screenshot-dir=' + str(captures),
              *selected],headless=False)
        candidate = read_trace(rendered,tick_limit,safe_kind)
        if candidate != reference:
            first = next(i for i,(left,right) in enumerate(zip(reference,candidate)) if left != right)
            raise ValueError(f'{rate} Hz first trace difference at record {first}')
        if tick_limit == 336:
            for name in CAPTURES:
                check_png(captures / f'entity-{name}.png')
        if safe_kind:
            check_png(captures / 'entity-platform-attachment.png')
            if safe_kind == 'moving':
                check_png(captures / 'entity-platform-departure.png')
        for capture in captures.glob('entity-lifecycle-*.png'):
            check_png(capture)
        print(f'{rate} Hz exact trace and captures: {rendered}',flush=True)
    if source_hashes() != before or hashlib.sha256(scenario.read_bytes()).hexdigest() != scenario_hash:
        raise RuntimeError('Source or scenario changed during verification')
    (evidence / 'comparison.json').write_text(json.dumps({
        'schema':'entity-lifecycle-v1','rates':list(RATES),
        'phase_records':len(reference)-1,'pass':True},indent=2),encoding='utf-8')
    print('Lifecycle schedules match exactly: ' + str(evidence),flush=True)


if __name__ == '__main__':
    main()
