"""Compare frozen-reference demo CSV segments without assuming hook calls are ticks."""

import argparse
import csv
import json
from pathlib import Path
import sys

FROG_COLUMNS = ('call', 'page', 'map', 'frog', 'grid_x', 'grid_z', 'x', 'y', 'z', 'mode', 'flags', 'input')
ENTITY_COLUMNS = ('call', 'map', 'index', 'unique_id', 'form_book_id', 'entity_type', 'x', 'y', 'z')
STATE_COLUMNS = ('grid_x', 'grid_z', 'x', 'y', 'z', 'mode', 'flags')


def read_csv(path, columns=FROG_COLUMNS, allow_empty=False):
    """Reject truncated, malformed, reordered and duplicate CSV observations."""
    path = Path(path)
    raw = path.read_bytes()
    if not raw.endswith(b'\n') or b'\r' in raw:
        raise ValueError(f'{path}: CSV must end with LF and contain no CR')
    reader = csv.reader(raw.decode('utf-8').splitlines())
    if tuple(next(reader, ())) != columns:
        raise ValueError(f'{path}: unexpected CSV header')
    rows = []
    previous_call = -1
    identities = set()
    expected_index = 0
    for line, values in enumerate(reader, 2):
        if len(values) != len(columns):
            raise ValueError(f'{path}:{line}: wrong field count')
        try:
            row = dict(zip(columns, map(int, values)))
        except ValueError as error:
            raise ValueError(f'{path}:{line}: expected integers') from error
        call = row['call']
        if call < previous_call or call < 0:
            raise ValueError(f'{path}:{line}: call order')
        key = (call, row.get('frog', row.get('index')))
        if key in identities:
            raise ValueError(f'{path}:{line}: duplicate observation')
        identities.add(key)
        if call != previous_call:
            expected_index = 0
        index = row.get('frog', row.get('index'))
        if index != expected_index:
            raise ValueError(f'{path}:{line}: noncontiguous per-call identity')
        expected_index += 1
        if 'input' in row and not -1 <= row['input'] <= 255:
            raise ValueError(f'{path}:{line}: invalid demo input')
        previous_call = call
        rows.append(row)
    if not rows and not allow_empty:
        raise ValueError(f'{path}: empty CSV')
    return rows


def segments(rows, map_id, frog=0):
    """Select contiguous map visits, retaining global reference call identities."""
    result = []
    active = None
    for row in rows:
        if row.get('frog', frog) != frog:
            continue
        if row['map'] != map_id:
            active = None
            continue
        if active is None:
            active = []
            result.append(active)
        active.append(row)
    return result


def compare(reference, actual, status, map_id, segment=0):
    """Report exact diagnostics and require declared completion for acceptance."""
    expected_segments = segments(reference, map_id)
    actual_segments = segments(actual, map_id)
    if segment < 0 or segment >= len(expected_segments) or len(actual_segments) != 1:
        raise ValueError('Requested map segment absent or actual contains multiple visits')
    expected = expected_segments[segment]
    observed = actual_segments[0]
    end_differences = {key: {'reference': expected[-1][key], 'actual': observed[-1][key]}
                       for key in STATE_COLUMNS if expected[-1][key] != observed[-1][key]}
    expected_inputs = [row['input'] for row in expected if row['input'] >= 0]
    actual_inputs = [row['input'] for row in observed if row['input'] >= 0]
    first_input = next((i for i, pair in enumerate(zip(expected_inputs, actual_inputs))
                        if pair[0] != pair[1]), None)
    if first_input is None and len(expected_inputs) != len(actual_inputs):
        first_input = min(len(expected_inputs), len(actual_inputs))
    route = lambda rows: [(row['grid_x'], row['grid_z']) for row in rows]
    def compress(values):
        return [value for i, value in enumerate(values) if i == 0 or value != values[i - 1]]
    expected_route, actual_route = compress(route(expected)), compress(route(observed))
    route_equal = expected_route == actual_route
    duration = status.get('duration')
    if not isinstance(duration, int) or isinstance(duration, bool) or duration < 0:
        raise ValueError('Playback status requires a nonnegative duration')
    if status.get('status') == 'complete' and status.get('elapsed_ticks') != duration:
        raise ValueError('Complete playback has not elapsed its declared duration')
    complete = status.get('schema') == 'demo-playback-v1' and status.get('status') == 'complete'
    if not isinstance(status.get('elapsed_ticks'), int) or status['elapsed_ticks'] != len(observed):
        raise ValueError('Playback status elapsed_ticks does not match actual CSV rows')
    if status.get('consumed_inputs') != len(actual_inputs):
        raise ValueError('Playback status consumed_inputs does not match actual CSV')
    return {'schema': 'demo-comparison-v1', 'map': map_id, 'reference_segment': segment,
            'complete': complete, 'termination_reason': status.get('reason', ''),
            'accepted': complete and not end_differences,
            'terminal_differences': end_differences,
            'input_equal': first_input is None, 'first_input_divergence': first_input,
            'reference_input_count': len(expected_inputs), 'actual_input_count': len(actual_inputs),
            'route_equal': route_equal, 'reference_route': expected_route, 'actual_route': actual_route,
            'reference_rows': len(expected), 'actual_ticks': len(observed),
            'alignment': 'map visit and consumed-input sequence; reference hook calls may contain multiple logic ticks'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('reference', type=Path)
    parser.add_argument('actual', type=Path)
    parser.add_argument('--status', required=True, type=Path)
    parser.add_argument('--map', required=True, type=int)
    parser.add_argument('--segment', default=0, type=int)
    args = parser.parse_args()
    report = compare(read_csv(args.reference), read_csv(args.actual),
                     json.loads(args.status.read_text()), args.map, args.segment)
    print(json.dumps(report, indent=2))
    return 0 if report['accepted'] else 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        sys.exit(2)
