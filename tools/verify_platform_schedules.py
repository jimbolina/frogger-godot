"""Compare platform landing traces at headless and three render schedules."""

import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import uuid


PHASES = ('control', 'move', 'collision', 'camera', 'final')
EXPLORATION_PHASES = ('control', 'move', 'collision', 'camera', 'scripts', 'final')
RATES = (30, 60, 144)
CAPTURES = ('approach', 'attachment', 'centred', 'carry', 'departure', 'camera')
PLATFORM_STATE = ('current_entity_index', 'forbidden_entity_index', 'entity_cell',
                  'entity_offset_16', 'entity_angle', 'entity_transform12',
                  'entity_carry_indices')


def check_exploration_source_trace(rows, golden_path):
    """Compare the represented JUN1 route fields with the frozen-C golden."""
    with golden_path.open('r', encoding='ascii', newline='') as stream:
        source_rows = list(csv.DictReader(stream, delimiter='\t'))
    if len(source_rows) != 360:
        raise ValueError(f'{golden_path}: expected 360 frozen-C route rows')
    source_by_key = {}
    for source in source_rows:
        key = (int(source['tick']), source['phase'])
        if key in source_by_key:
            raise ValueError(f'{golden_path}: duplicate frozen-C route phase {key}')
        source_by_key[key] = source
    for row in rows[1:]:
        phase = 'pose' if row['phase'] == 'final' else row['phase']
        key = (row['tick'], phase)
        source = source_by_key.get(key)
        if source is None:
            raise ValueError(f'{golden_path}: missing frozen-C route phase {key}')
        state = row['state']
        pose = next((entity for entity in state['entities']['entities']
                     if entity['entity_index'] == 24), None)
        if pose is None:
            raise ValueError(f'{key}: missing selected JUN1 log24 pose')
        expected = {
            'x16': state['position_16'][0], 'y16': state['position_16'][1],
            'z16': state['position_16'][2], 'vx16': state['velocity_16'][0],
            'vy16': state['velocity_16'][1], 'vz16': state['velocity_16'][2],
            'grid_x': state['cell'][0], 'grid_z': state['cell'][1],
            'flags': state['flags'], 'mode': state['mode'],
            'attached': state['current_entity_index'],
            'count': state['remaining_ticks'], 'direction': state['direction'],
            'input': state['current_input'],
            'entity_x': pose['matrix12'][9], 'entity_y': pose['matrix12'][10],
            'entity_z': pose['matrix12'][11],
            'segment': pose['path']['segment_index'],
            'distance': pose['path']['segment_distance'],
            'camera_x': state['camera']['tracked_world'][0],
            'camera_y': state['camera']['tracked_world'][1],
            'camera_z': state['camera']['tracked_world'][2],
            'controller_n': state['camera']['controller_directions'][0],
            'controller_e': state['camera']['controller_directions'][1],
            'controller_s': state['camera']['controller_directions'][2],
            'controller_w': state['camera']['controller_directions'][3],
            'old_y': state['old_y'],
            'entity_cell_x': state['entity_cell'][0],
            'entity_cell_z': state['entity_cell'][1],
            'forbidden': state['forbidden_entity_index'],
        }
        for field, actual in expected.items():
            if int(source[field]) != actual:
                raise ValueError(f'{key}: {field} frozen C {source[field]}, runtime {actual}')
        hit_indices = ';'.join(map(str, state['entity_hit_indices'])) or '-'
        if source['hit_indices'] != hit_indices:
            raise ValueError(f'{key}: hit_indices frozen C {source["hit_indices"]}, '
                             f'runtime {hit_indices}')
        if row['phase'] == 'final':
            observed_order = ';'.join(str(item['contact']['entity_index'])
                                      for item in row['entity_contacts']) or '-'
            if source['supported_order'] != observed_order:
                raise ValueError(f'{key}: supported_order frozen C '
                                 f'{source["supported_order"]}, runtime {observed_order}')


def read_trace(path, retail, exploration=False):
    rows = [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines()
            if line.strip()]
    schema = 'entity-exploration-v1' if exploration else 'entity-platform-v1'
    phases = EXPLORATION_PHASES if exploration else PHASES
    if not rows or rows[0].get('schema') != schema:
        raise ValueError(f'{path}: missing {schema} metadata')
    if (len(rows) - 1) % len(phases):
        raise ValueError(f'{path}: incomplete phase sequence')
    limit = rows[0].get('tick_limit')
    if type(limit) is not int or not 0 <= limit <= 100000:
        raise ValueError(f'{path}: invalid tick limit')
    if not isinstance(rows[0].get('entity_collision'), dict):
        raise ValueError(f'{path}: missing entity collision source facts')
    for index, row in enumerate(rows[1:]):
        expected = (index // len(phases), phases[index % len(phases)])
        if (row.get('tick'), row.get('phase')) != expected:
            raise ValueError(f'{path}: expected {expected}, got '
                             f'{(row.get("tick"), row.get("phase"))}')
        state = row.get('state')
        if row.get('error') or not isinstance(state, dict):
            raise ValueError(f'{path}: invalid phase at {expected}')
        missing = [key for key in PLATFORM_STATE if key not in state]
        if missing:
            raise ValueError(f'{path}: absent platform state {missing} at {expected}')
        if row.get('phase') == 'final':
            entities = state.get('entities')
            if not isinstance(entities, dict) or entities.get('tick_index') != state.get('tick_index'):
                raise ValueError(f'{path}: entity and frog ticks differ at {expected}')
            if not isinstance(row.get('entity_contacts'), list):
                raise ValueError(f'{path}: missing ordered contacts at {expected}')
            if state.get('completed') and index != len(rows) - 2:
                raise ValueError(f'{path}: records continue after completion')
    if (len(rows) - 1) // len(phases) > limit:
        raise ValueError(f'{path}: trace exceeds tick limit')
    tick_count = (len(rows) - 1) // len(phases)
    if not rows[-1]['state'].get('completed') and tick_count != limit:
        raise ValueError(f'{path}: run stopped early without completion')
    if exploration:
        metadata = rows[0]
        if tick_count != 60:
            raise ValueError(f'{path}: guarded route must run all 60 ticks')
        if (metadata.get('source_id') != 'pc-retail-v3.0e:JUN1'
                or metadata.get('resource_id') != 656 or metadata.get('map_index') != 18
                or metadata.get('exploration') != 'jun1-log-bank' or limit != 60):
            raise ValueError(f'{path}: expected audited 60-tick high-detail JUN1 exploration')
        guard = metadata.get('exploration_guard') or {}
        if guard.get('world_bounds') != [1900, -5376, 404, 512]:
            raise ValueError(f'{path}: audited exploration rectangle changed')
        finals = [row for row in rows[1:] if row['phase'] == 'final']
        attached = [(row['tick'], row['state']['current_entity_index']) for row in finals
                    if row['state']['current_entity_index'] >= 0]
        if attached != [(tick, 24) for tick in range(3, 17)]:
            raise ValueError(f'{path}: JUN1 log24 mount/carry interval changed')
        for row in rows[1:]:
            state = row['state']
            if state.get('completed') is not False or state.get('death_count') != 0:
                raise ValueError(f'{path}: guarded route must remain alive and incomplete')
            world = state.get('world_position')
            if not (isinstance(world, list) and len(world) == 3 and
                    1900 <= world[0] < 2304 and -5376 <= world[2] < -4864):
                raise ValueError(f'{path}: phase escaped audited rectangle at '
                                 f"{(row['tick'], row['phase'])}")
        if finals[17]['state']['cell'] != [22, 9] or any(
                row['state']['current_entity_index'] != -1 for row in finals[17:]):
            raise ValueError(f'{path}: return to ordinary safe bank changed')
    if retail and not exploration:
        metadata = rows[0]
        if (metadata.get('source_id') != 'pc-retail-v3.0e:JUN1'
                or metadata.get('resource_id') != 656 or metadata.get('map_index') != 18):
            raise ValueError(f'{path}: expected high-detail v3.0e JUN1 resource 656')
        collision = metadata['entity_collision']
        entities = {entity.get('entity_index'): entity for entity in collision.get('entities', [])}
        contacts = {contact.get('entity_index'): contact for contact in collision.get('contacts', [])}
        entity = entities.get(1)
        contact = contacts.get(1)
        expected_entity = {'unique_id': 166, 'source_offset': 12644, 'form_grid_id': 1,
                           'form_id': 45, 'form_name': 'JUN_LOG', 'entity_name': 'MOVING',
                           'script_id': 0, 'collision_callback': 0, 'bonus_callback': 0,
                           'flags': 0}
        expected_contact = {'dimensions': [1, 2], 'offsets': [-130, -258],
                            'height': -86, 'max_y': 83, 'radius_squared': 130279,
                            'form_book_flags': 24,
                            'grid_flags': [259, 259], 'unsupported_reason': '',
                            'reaction_unsupported_reason': ''}
        if not isinstance(entity, dict) or any(entity.get(key) != value
                                               for key, value in expected_entity.items()):
            raise ValueError(f'{path}: JUN1 entity 1 source facts differ')
        if not isinstance(contact, dict) or any(contact.get(key) != value
                                                for key, value in expected_contact.items()):
            raise ValueError(f'{path}: JUN1 FORM source facts differ')
        path_start = entity.get('path_start') or {}
        path = entity.get('path_definition') or {}
        if (path.get('path_index') != 1 or path_start.get('segment_index') != 2
                or path_start.get('distance') != 2197 or path_start.get('speed') != 16
                or path_start.get('flags') not in (8, 9)):
            raise ValueError(f'{path}: JUN1 path source facts differ')
        attached = [(row['tick'], row['state']['current_entity_index'])
                    for row in rows[1:] if row.get('phase') == 'final'
                    and row['state']['current_entity_index'] >= 0]
        if not attached or attached[0] != (3, 1):
            raise ValueError(f'{path}: JUN1 must first attach entity 1 at command tick 3')
        first = next((row for row in rows[1:] if row.get('phase') == 'final'
                      and row['tick'] == 3), None)
        if first is None or not any(contact.get('contact', {}).get('entity_index') == 1
                                    and contact.get('status') == 'safe'
                                    and contact.get('hit') is True
                                    for contact in first['entity_contacts']):
            raise ValueError(f'{path}: JUN1 tick 3 lacks entity 1 accepted contact')
        move = next(row for row in rows[1:] if row['tick'] == 3 and row['phase'] == 'move')
        frog = move['state']['world_position']
        pose = next(entity for entity in move['state']['entities']['entities']
                    if entity['entity_index'] == 1)
        position = pose['matrix12'][9:12]
        accepted = next(item['contact'] for item in first['entity_contacts']
                        if item['status'] == 'safe' and item['contact']['entity_index'] == 1)
        if (frog != [1152, 46, -6102] or position != [1109, 0, -6014]
                or pose['path']['tick_index'] != 4
                or accepted['local_position'] != [88, 46, 42]
                or accepted['cell'] != [0, 1] or accepted['cell_flags'] != 259
                or sum((a - b) ** 2 for a, b in zip(frog, position)) != 11709):
            raise ValueError(f'{path}: JUN1 complete-scan contact differs from independent prediction')
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
    parser.add_argument('--scenario-file', type=Path)
    parser.add_argument('--data-dir', type=Path)
    parser.add_argument('--exploration', choices=('jun1-log-bank', 'org1-turtle-log-bank', 'org1-road-river','org1-turtle-log-bank-visibility'))
    parser.add_argument('--case-index', type=int, default=0,
                        help='Case inside a scenario file with a cases array (default: 0)')
    parser.add_argument('--level', default='JUN1', help='Retail level code (default: JUN1)')
    parser.add_argument('--tick-limit', type=int,
                        help='Override selected scenario duration (retail default: 90)')
    parser.add_argument('--output-directory', type=Path, required=True)
    args = parser.parse_args()
    if args.exploration in ('org1-turtle-log-bank', 'org1-road-river','org1-turtle-log-bank-visibility'):
        if args.scenario_file is None or args.data_dir is None or args.level.upper() != 'ORG1':
            parser.error(args.exploration + ' requires --scenario-file, --data-dir and --level=ORG1')
        from org1_schedule_verification import run
        run(args)
        return
    if args.exploration and (args.scenario_file is None or args.data_dir is None or args.level.upper() != 'JUN1'):
        parser.error('jun1-log-bank requires both --scenario-file, --data-dir and --level=JUN1')
    if not args.exploration and bool(args.scenario_file) == bool(args.data_dir):
        parser.error('select exactly one of --scenario-file or --data-dir outside exploration')
    if args.tick_limit is not None and not 0 <= args.tick_limit <= 100000:
        parser.error('tick-limit must be in 0..100000')

    repo = Path(__file__).resolve().parents[1]
    output = args.output_directory.resolve()
    for protected in (repo, (repo.parent / 'froggy').resolve()):
        if output == protected or protected in output.parents:
            parser.error('Evidence must be outside this repository and froggy')
    if args.scenario_file and not args.scenario_file.is_file():
        parser.error('scenario-file does not exist')
    if args.data_dir and not args.data_dir.is_dir():
        parser.error('data-dir does not exist')

    def source_identities():
        paths = [path for path in (repo / 'src').rglob('*') if path.suffix in ('.gd', '.gdshader', '.json')]
        paths += [path for path in (repo / 'tools').glob('*') if path.suffix in ('.gd', '.py')]
        paths += list((repo / 'scenes').rglob('*.tscn')) + [repo / 'project.godot']
        return {str(path.relative_to(repo)): hashlib.sha256(path.read_bytes()).hexdigest()
                for path in sorted(paths)}

    evidence = output / ('entity-platform-schedules-' + uuid.uuid4().hex)
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

    selected = ['--entity-reactions=platforms']
    if args.exploration:
        selected.append('--exploration=' + args.exploration)
    if args.scenario_file:
        authored = json.loads(args.scenario_file.read_text(encoding='utf-8'))
        if isinstance(authored, dict) and isinstance(authored.get('cases'), list):
            if not 0 <= args.case_index < len(authored['cases']):
                parser.error('case-index is outside the scenario cases array')
            authored = authored['cases'][args.case_index]
            if not isinstance(authored, dict):
                parser.error('Selected scenario case must be an object')
            authored.setdefault('name', f'platform-{args.case_index}')
            selected_path = evidence / 'selected-scenario.json'
            selected_path.write_text(json.dumps(authored, indent=2), encoding='utf-8')
        else:
            selected_path = args.scenario_file.resolve()
        selected.append('--scenario-file=' + str(selected_path))
    else:
        selected.extend(('--data-dir=' + str(args.data_dir.resolve()), '--level=' + args.level))
        if args.tick_limit is None:
            selected.append('--tick-limit=90')
    if args.exploration:
        selected.extend(('--data-dir=' + str(args.data_dir.resolve()), '--level=JUN1'))
    if args.tick_limit is not None:
        selected.append('--tick-limit=' + str(args.tick_limit))
    identity = hashlib.sha256(args.scenario_file.read_bytes()).hexdigest() if args.scenario_file else None
    route_golden = repo / 'tests/golden/pc-retail-v3.0e/platform_jun1_route.tsv'
    route_golden_sha = hashlib.sha256(route_golden.read_bytes()).hexdigest() if args.exploration else None
    source_hashes = source_identities()
    (evidence / 'provenance.json').write_text(json.dumps({'source_sha256': source_hashes,
        'scenario_sha256': identity, 'retail_data_dir': str(args.data_dir.resolve()) if args.data_dir else None},
        indent=2), encoding='utf-8')
    print('Entity platform evidence: ' + str(evidence), flush=True)

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
    retail = bool(args.data_dir) and args.level.upper() == 'JUN1'
    reference = read_trace(baseline, retail, bool(args.exploration))
    if args.exploration:
        check_exploration_source_trace(reference, route_golden)
    for rate in RATES:
        rendered = evidence / f'rendered-{rate}.jsonl'
        captures = evidence / f'captures-{rate}'
        stage(f'rendered-{rate}', ['res://scenes/tools/terrain_viewer.tscn', '--', '--run-scenario',
              '--render-rate=' + str(rate), '--trace-jsonl=' + str(rendered),
              '--screenshot-dir=' + str(captures), *selected], headless=False)
        candidate = read_trace(rendered, retail, bool(args.exploration))
        if len(candidate) != len(reference):
            raise ValueError(f'{rate} Hz trace has {len(candidate)} rows; expected {len(reference)}')
        for index, (expected, actual) in enumerate(zip(reference, candidate)):
            if expected != actual:
                phases = EXPLORATION_PHASES if args.exploration else PHASES
                location = 'metadata' if index == 0 else f'tick {(index - 1) // len(phases)} phase {phases[(index - 1) % len(phases)]}'
                raise ValueError(f'{rate} Hz first difference at {location}')
        states = [row['state'] for row in candidate[1:] if row.get('phase') == 'final']
        mounted = any(state['current_entity_index'] >= 0 for state in states)
        departed = any(before['current_entity_index'] >= 0 and after['current_entity_index'] < 0
                       for before, after in zip(states, states[1:]))
        required = {'safe-start', 'approach', 'attachment', 'centring', 'centred',
                    'carry', 'camera', 'departure', 'safe-return'} if args.exploration else {'approach'}
        if mounted:
            required.add('attachment')
            attachment_tick = next(state['tick_index'] for state in states
                                   if state['current_entity_index'] >= 0)
            if any(state['tick_index'] >= attachment_tick + 1 for state in states):
                required.add('camera')
            centred = [state['tick_index'] for state in states
                       if state['current_entity_index'] >= 0 and state['mode'] == 0
                       and state['tick_index'] >= attachment_tick]
            if centred:
                required.add('centred')
                if any(tick >= centred[0] + 2 for tick in centred):
                    required.add('carry')
        if departed:
            required.add('departure')
        for name in required:
            check_png(captures / f'entity-platform-{name}.png')
        for capture in captures.glob('entity-platform-*.png'):
            check_png(capture)
        print(f'{rate} Hz exact trace and captures: {rendered}', flush=True)
    if source_identities() != source_hashes:
        raise RuntimeError('Candidate source changed during schedule verification')
    if args.scenario_file and hashlib.sha256(args.scenario_file.read_bytes()).hexdigest() != identity:
        raise RuntimeError('Scenario changed during schedule verification')
    if args.exploration and hashlib.sha256(route_golden.read_bytes()).hexdigest() != route_golden_sha:
        raise RuntimeError('Frozen-C route golden changed during schedule verification')
    (evidence / 'comparison.json').write_text(json.dumps({'schema': 'entity-exploration-v1' if args.exploration else 'entity-platform-v1',
        'rates': list(RATES), 'phase_records': len(reference) - 1, 'completed': True,
        'scenario_sha256': identity, 'route_golden_sha256': route_golden_sha,
        'pass': True}, indent=2), encoding='utf-8')
    print('Entity platform schedules match exactly: ' + str(evidence), flush=True)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
