"""Write the invented 336-tick flat-terrain lifecycle inspection scenario."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'tests/golden/fixtures/lifecycle_integrated.json'


def build() -> dict:
    squares = []
    for z in range(4):
        for x in range(24):
            left, near = -512 + x * 256, -512 + z * 256
            squares.append({'flags': 3, 'vertices': [
                [left, 0, near + 256], [left + 256, 0, near + 256],
                [left, 0, near], [left + 256, 0, near]]})
    commands = []
    for tick in range(16, 144, 8):
        commands.append({'tick': tick, 'pressed': 2, 'held': 2})
    for tick in range(176, 304, 8):
        commands.append({'tick': tick, 'pressed': 8, 'held': 8})
    entities = [
        {'entity_index': 2, 'unique_id': 77, 'form_grid_id': 0,
         'form_id': 0, 'form_name': 'SYNTHETIC_STATIC', 'entity_name': 'STATIC',
         'flags': 8, 'matrix12': [4096,0,0,0,4096,0,0,0,4096,0,0,0]},
        {'entity_index': 9, 'unique_id': 77, 'form_grid_id': 0,
         'form_id': 0, 'form_name': 'SYNTHETIC_MOVING', 'entity_name': 'MOVING',
         'flags': 8,
         'path_definition': {'path_index': 0, 'segments': [
             {'segment_type': 2, 'length': 512, 'start': [-256,0,0],
              'end': [256,0,0]}]},
         'path_start': {'segment_index': 0, 'distance': 256,
                        'speed': 16, 'flags': 8}}
    ]
    contacts = []
    for entity in entities:
        contacts.append({
            'entity_index': entity['entity_index'], 'unique_id': entity['unique_id'],
            'form_grid_id': entity['form_grid_id'], 'form_id': entity['form_id'],
            'form_name': entity['form_name'], 'entity_flags': entity['flags'],
            'dimensions': [1,1], 'offsets': [-128,-128], 'height': 0,
            'max_y': 0, 'radius_squared': 0, 'grid_flags': [0],
            'death_type': 0, 'form_book_flags': 0,
            'unsupported_reason': 'Synthetic lifecycle entity collision disabled',
        })
    return {
        'name': 'flat_visibility_departure_return',
        'builtin': 'normal', 'tick_limit': 336,
        'grid': {'dimensions': [24,4], 'base': [-512,-512],
                 'stacks': [[i,1] for i in range(96)], 'squares': squares},
        'level': {
            'spawn_cell': [1,1], 'spawn_direction': 0,
            'collision_enabled': True,
            'collision_bounds': [-32767,-32767,65534,65534],
            'theme': 9, 'theme_name': 'SUB', 'theme_death_height': 30000,
            'camera': {'source_offset': [0,-512,-512],
                       'target_offset': [0,0,0]},
            'frog_action_lengths': [3,4,5] * 12,
            'entity_collision': {
                'platforms_enabled': True,
                'group_base': [-8192,0,-8192],
                'group_dimensions': [32,32], 'group_size': [512,512],
                'entities': entities, 'contacts': contacts,
                'lifecycle': {'polygon_counts': [1] * 1024},
            },
        },
        'start': {'seed': 1, 'camera_startup': False, 'start_timer': 0},
        'commands': commands,
    }


if __name__ == '__main__':
    OUTPUT.write_text(json.dumps(build(), indent=2) + '\n', encoding='utf-8')
    print(OUTPUT)
