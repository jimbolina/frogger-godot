"""Asset-free regressions for ORG1's bounded corridor evidence checker.

All programs, coordinates, model bytes and oracle responses below are invented.
These checks protect the independent evaluator and evidence rejection gates;
they do not replace agreement with the linked frozen-C oracle on owner assets.
Run directly with: python -B tools/golden/test_org1_corridor.py
"""

import copy
from pathlib import Path
import struct
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.inspection import verify_org1_corridor as corridor


ROOT = [34, 0, 0, 0, 0, 11, 13, 0, 6, 2, 4, 7, 0, 0, 0, 0, 10, 12, 5]
TARGET = [36, 0, 20, 9, 2, 256, 5]
POINTS = [[10 * n, -100 * n, 1000 + 10 * n] for n in range(5)]
ORIGIN = [7, 8, 9]


def background(ticks, traffic=(), seed=12345, reverse=False, collected=0,
               programs=None, points=None):
    facts = {'traffic': [{'entity_index': index, 'script_id': 1} for index in traffic]}
    return corridor.background_expected(facts, programs or {1: ROOT, 2: TARGET},
                                         points or POINTS, ORIGIN, ticks, seed,
                                         reverse, collected)


class DecoderTests(unittest.TestCase):
    def test_operand_words_are_not_interpreted_as_opcodes(self):
        self.assertEqual(corridor.commands({'stream': [7, 0, -1, 5]}),
                         [('SET_TIMER', [0, -1]), ('RESTART', [])])

    def test_zero_operand_command_at_end_is_complete(self):
        self.assertEqual(corridor.commands({'stream': [12]}), [('ENDLOOP', [])])

    def test_all_operand_truncations_are_rejected(self):
        for missing in range(1, 5):
            with self.subTest(missing=missing), self.assertRaises(ValueError):
                corridor.commands({'stream': [34, 0, 0, 0, 0][:-missing]})

    def test_opcode_must_be_in_unsigned_known_range(self):
        for opcode in (-1, -len(corridor.exe_tables.OPCODES),
                       len(corridor.exe_tables.OPCODES), 2**32 - 1,
                       True, 5.0, '5', None):
            with self.subTest(opcode=opcode), self.assertRaises(ValueError):
                corridor.commands({'stream': [opcode]})


class BackgroundClosureTests(unittest.TestCase):
    def setUp(self):
        packet = 64
        data = bytearray(4096)
        for index in range(56):
            at = 512 + index * 64
            struct.pack_into('<I', data, packet + 12 + index * 4, at)
            form_id = 0x8000 | index if index < 5 else int(index == 55)
            struct.pack_into('<H', data, at + 4, form_id)
            position = POINTS[index] if index < 5 else ORIGIN
            struct.pack_into('<3i', data, at + 44, *position)
        scripts, script_names, traffic = {}, {}, []
        for sid, name in enumerate(corridor.TRAFFIC.values(), start=1):
            root = ROOT[:]
            root[9] = sid + 10
            root[10] = 2 if name == 'SCRIPT_ORG_LORRY' else 4
            scripts[sid] = {'stream': root}
            scripts[sid + 10] = {'stream': TARGET[:]}
            script_names[sid], script_names[sid + 10] = name, name + '_SFX'
            traffic.append(dict(entity_index=23 + sid, script_id=sid))
        self.facts = dict(traffic=traffic, entity_count=56)
        self.context = dict(data=data, packet=packet, theme=1, scripts=scripts,
                            script_names=script_names,
                            callbacks=['SCRIPT_CB_FROG_TRAFFIC_SPLAT'],
                            names=[*(f'GEN_CHECKPOINT_{n}' for n in range(1, 6)),
                                   'ORG_FLY', 'ORG_LOG'],
                            forms={0: [{'global': n} for n in range(5)],
                                   1: [{'global': 6}, {'global': 5}]})

    def inputs(self):
        return corridor.background_inputs(self.facts, self.context)

    def test_complete_five_root_closure_decodes_source_checkpoint_and_fly_positions(self):
        programs, points, fly_position = self.inputs()
        self.assertEqual(list(programs), [1, 2, 3, 4, 5, 11, 12, 13, 14, 15])
        self.assertEqual(points, POINTS)
        self.assertEqual(fly_position, ORIGIN)
        self.assertEqual(programs[1], self.context['scripts'][1]['stream'])

    def test_changed_callback_slot_id_condition_or_type_is_rejected(self):
        for offset in (1, 2, 3, 4):
            root = self.context['scripts'][1]['stream']
            root[offset] = 1
            with self.subTest(offset=offset), self.assertRaises(ValueError):
                self.inputs()
            root[offset] = 0

    def test_changed_branch_mode_condition_or_divisor_is_rejected(self):
        for offset, changed in ((7, 1), (8, 0), (10, 0), (10, 3), (10, 2)):
            root = self.context['scripts'][1]['stream']
            original = root[offset]
            root[offset] = changed
            with self.subTest(offset=offset, changed=changed), self.assertRaises(ValueError):
                self.inputs()
            root[offset] = original

    def test_lorry_divisor_cannot_be_replaced_by_other_traffic_divisor(self):
        self.context['scripts'][2]['stream'][10] = 4
        with self.assertRaises(ValueError):
            self.inputs()

    def test_callback_symbol_mapping_must_still_name_traffic_splat(self):
        for callbacks in ([], ['SCRIPT_CB_INVENTED']):
            self.context['callbacks'] = callbacks
            with self.subTest(callbacks=callbacks), self.assertRaises(ValueError):
                self.inputs()

    def test_branch_must_resolve_to_its_own_named_sound_target(self):
        self.context['scripts'][1]['stream'][9] = 12
        with self.assertRaisesRegex(ValueError, 'target name'):
            self.inputs()

    def test_absent_or_negative_branch_target_is_rejected_deliberately(self):
        for target in (-1, 999, '11', 11.0, True, None):
            self.context['scripts'][1]['stream'][9] = target
            with self.subTest(target=target), self.assertRaises(ValueError):
                self.inputs()

    def test_branch_target_requires_both_program_and_name(self):
        target = self.context['scripts'].pop(11)
        with self.assertRaises(ValueError):
            self.inputs()
        self.context['scripts'][11] = target
        self.context['script_names'].pop(11)
        with self.assertRaises(ValueError):
            self.inputs()

    def test_sequence_tables_reject_negative_and_past_end_target_indices(self):
        for key in ('scripts', 'script_names'):
            source = self.context[key]
            self.context[key] = [source.get(index) for index in range(16)]
        self.assertEqual(len(self.inputs()[0]), 10)
        for target in (-1, 16):
            self.context['scripts'][1]['stream'][9] = target
            with self.subTest(target=target), self.assertRaises(ValueError):
                self.inputs()

    def test_changed_sound_target_instructions_or_operands_are_rejected(self):
        target = self.context['scripts'][11]['stream']
        for offset, changed in ((0, 37), (1, 1), (2, 21), (4, 1), (5, 257), (6, 6)):
            original = target[:]
            target[offset] = changed
            with self.subTest(offset=offset), self.assertRaises(ValueError):
                self.inputs()
            target[:] = original

    def test_missing_root_or_checkpoint_fails_complete_closure(self):
        omitted = self.facts['traffic'].pop()
        with self.assertRaisesRegex(ValueError, 'five roots'):
            self.inputs()
        self.facts['traffic'].append(omitted)
        self.context['names'][0] = 'ORG_LOG'
        with self.assertRaisesRegex(ValueError, 'checkpoint/fly'):
            self.inputs()


class BackgroundSemanticsTests(unittest.TestCase):
    def test_rng_fixed_vectors_include_unsigned_overflow_and_15_bit_output(self):
        seed = 1
        for expected in ((1103527590, 16838), (2524885223, 5758),
                         (662824084, 10113), (3295386429, 17515),
                         (4182499122, 31051), (2516284547, 5627)):
            self.assertEqual(corridor.random_step(seed), expected)
            seed = expected[0]
        self.assertEqual(corridor.random_step(0), (12345, 0))
        self.assertEqual(corridor.random_step(2**32), (12345, 0))

    def test_wait_and_endloop_each_yield_before_the_next_random_branch(self):
        with patch.object(corridor, 'random_step', return_value=(99, 0)) as rng:
            rows = background(12, traffic=[24])
        traffic = rows[::2]
        self.assertEqual([row[6] for row in traffic], list(range(1, 12)) + [1])
        self.assertEqual([row[3] for row in traffic], [14] * 10 + [6, 14])
        self.assertEqual(traffic[0][2:10], [1, 14, 6, 18, 1, 0, 0, 2])
        self.assertEqual(rng.call_count, 2)
        self.assertTrue(all(row[-1] == 0 for row in rows))

    def test_taken_target_restart_keeps_root_and_may_draw_again_same_update(self):
        with patch.object(corridor, 'random_step',
                          side_effect=[(11, 1), (22, 5), (33, 0)]) as rng:
            row = background(1, traffic=[24])[0]
        self.assertEqual(rng.call_count, 3)
        self.assertEqual(row[2:11], [1, 14, 6, 18, 1, 0, 0, 2, 33])
        self.assertEqual(row[-1], 0)

    def test_timer_increment_wraps_at_unsigned16_boundary(self):
        program = [7, 0, 65535, 0, 0, 65536, 5]
        rows = background(2, traffic=[24], programs={1: program})[::2]
        self.assertEqual([row[6] for row in rows], [0, 1])
        self.assertEqual([row[3] for row in rows], [3, 3])

    def test_fly_postdecrement_phases_and_rng_draws(self):
        rows = background(244)
        self.assertEqual(rows[59][10:19], [12345, 0, 0, -1, 0, 9, *ORIGIN])
        self.assertEqual(rows[60][10:19],
                         [3554416254, 1, 120, 3, 8, 0, 30, -556, 980])
        self.assertEqual(rows[180][11:16], [1, 0, 3, 8, 0])
        self.assertEqual(rows[181][10:16], [3554416254, 0, 60, -1, 0, 9])
        self.assertEqual(rows[181][16:19], [30, -556, 980])
        self.assertEqual(rows[242][10:16], [2802067423, 1, 120, 3, 8, 0])

    def test_collected_checkpoint_failure_still_draws_and_restarts_wait(self):
        rows = background(122, collected=8)
        self.assertEqual(rows[60][10:19], [3554416254, 0, 60, -1, 0, 9, *ORIGIN])
        self.assertEqual(rows[121][10:19], [2802067423, 0, 60, -1, 0, 9, *ORIGIN])

    def test_all_collected_never_appears_but_does_not_suppress_rng(self):
        rows = background(244, collected=31)
        self.assertTrue(all(row[11] == 0 and row[14] == 0 and row[15] == 9 for row in rows))
        self.assertEqual(rows[-1][10], 229283573)

    def test_checkpoint_offsets_wrap_like_signed16_source_fields(self):
        points = copy.deepcopy(POINTS)
        points[3] = [40000, -32760, -32740]
        row = background(61, points=points)[-1]
        self.assertEqual(row[16:19], [40000, 32520, 32746])

    def test_explicit_order_assigns_the_same_draws_to_different_entities(self):
        def run(reverse):
            draws = iter((n, 0) for n in range(1, 1000))
            root = ROOT[:]
            root[16] = 0
            with patch.object(corridor, 'random_step', side_effect=lambda _: next(draws)):
                return background(61, traffic=[24, 25], reverse=reverse,
                                  programs={1: root, 2: TARGET})
        forward, backward = run(False), run(True)
        self.assertEqual([row[1] for row in forward[:3]], [24, 25, 55])
        self.assertEqual([row[1] for row in backward[:3]], [55, 25, 24])
        self.assertEqual([row[10] for row in forward[-3:]], [121, 122, 123])
        self.assertEqual([row[10] for row in backward[-3:]], [121, 122, 123])
        self.assertEqual(forward[-1][11], 1)
        self.assertEqual(backward[-3][11], 1)
        self.assertEqual(forward[-3][11], 0)
        self.assertEqual(backward[-1][11], 1)

    def test_order_changes_shared_rng_in_a_longer_complete_script_run(self):
        forward = background(730, traffic=[24, 25])
        backward = background(730, traffic=[24, 25], reverse=True)
        self.assertEqual(len(forward), len(backward))
        self.assertNotEqual(forward[-1][10], backward[-1][10])

    def test_non_yielding_program_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'instruction budget'):
            background(1, traffic=[24], programs={1: [5]})


class MovingSoundEvidenceTests(unittest.TestCase):
    HEADER = 'case,allocated,count,min_radius,max_radius,owner_matches,rng'
    ROWS = [[0, 0, 0, -1, -1, 0, 12345],
            [1, 1, 1, 300, 900, 1, 12345],
            [2, 1, 1, 300, 900, 1, 12345],
            [3, 0, 0, -1, -1, 0, 12345],
            [4, 1, 1, 300, 900, 1, 12345]]

    def setUp(self):
        self.output = Path('invented-output')
        self.files = {}
        writer = patch.object(Path, 'write_text', autospec=True,
                              side_effect=lambda path, text, **_: self.files.__setitem__(path, text))
        writer.start()
        self.addCleanup(writer.stop)
        data = bytearray(640)
        inventory = []
        for number, index in enumerate((56, 57, 58, 59, 62, 63)):
            at = number * 96
            struct.pack_into('<2i', data, at + 56, 300, 900)
            inventory.append(dict(entity_index=index, entity_type='STATIC_NOISE',
                                  script_id=1, source_offset=at))
        self.context = dict(data=data, inventory=inventory,
                            scripts={1: {'stream': [31, 32, 2, 11, 37, 9, 1, 0, 1, 12, 5]}})

    def check_response(self, rows=None, header=None, returncode=0):
        text = (header or self.HEADER) + '\n'
        text += '\n'.join(','.join(map(str, row)) for row in (self.ROWS if rows is None else rows)) + '\n'
        response = SimpleNamespace(returncode=returncode, stdout=text, stderr='invented failure')
        with patch.object(corridor.subprocess, 'run', return_value=response):
            return corridor.check_moving_sound(Path('oracle'), Path('acos'), self.output, self.context)

    def test_real_allocation_reuse_owner_clear_and_recreation_evidence(self):
        proof = self.check_response()
        self.assertEqual(len(proof['cases']), 6)
        self.assertEqual(proof['cases'][0], dict(entity_index=56, sound_id=9, minimum=300, maximum=900))
        self.assertEqual(self.files[self.output / 'moving-sound-56.txt'], '9 300 900\n')

    def test_changed_allocation_owner_radius_or_rng_is_rejected(self):
        for case, field, replacement in ((0, 1, 1), (2, 2, 2), (3, 5, 1),
                                         (4, 3, 301), (4, 6, 12346)):
            rows = copy.deepcopy(self.ROWS)
            rows[case][field] = replacement
            with self.subTest(case=case, field=field), self.assertRaisesRegex(ValueError, 'mismatch'):
                self.check_response(rows)

    def test_missing_extra_reordered_or_mislabelled_evidence_is_rejected(self):
        for rows in (self.ROWS[:-1], self.ROWS + [self.ROWS[-1]], list(reversed(self.ROWS))):
            with self.subTest(rows=rows), self.assertRaises(ValueError):
                self.check_response(rows)
        for header in (self.HEADER + '\n' + self.HEADER, 'case,wrong'):
            with self.subTest(header=header), self.assertRaisesRegex(ValueError, 'header'):
                self.check_response(header=header)

    def test_oracle_failure_is_rejected_even_with_matching_stdout(self):
        with self.assertRaisesRegex(ValueError, 'allocation check failed'):
            self.check_response(returncode=3)

    def test_inventory_change_is_rejected_before_oracle(self):
        self.context['inventory'].pop()
        with patch.object(corridor.subprocess, 'run') as oracle:
            with self.assertRaisesRegex(ValueError, 'inventory changed'):
                corridor.check_moving_sound(Path('oracle'), Path('acos'), self.output, self.context)
            oracle.assert_not_called()

    def test_changed_register_binding_is_rejected_before_oracle(self):
        self.context['scripts'][1]['stream'][1] = 36
        with patch.object(corridor.subprocess, 'run') as oracle:
            with self.assertRaisesRegex(ValueError, 'register operands'):
                corridor.check_moving_sound(Path('oracle'), Path('acos'), self.output, self.context)
            oracle.assert_not_called()


class TrafficGeometryTests(unittest.TestCase):
    def setUp(self):
        self.data = bytearray(512)
        struct.pack_into('<I', self.data, 96, 256)
        struct.pack_into('<H', self.data, 132, 0)
        struct.pack_into('<6H', self.data, 152, 0, 0, 0, 8, 1, 0)
        struct.pack_into('<I', self.data, 264, 320)
        struct.pack_into('<2I', self.data, 324, 1, 384)
        struct.pack_into('<2i', self.data, 384, 2, 20)
        struct.pack_into('<3h', self.data, 392, -10, 0, -500)
        struct.pack_into('<3h', self.data, 400, 10, 0, -500)
        self.raw = bytearray(128)
        self.set_primitive()
        self.model = {'kind': 'static', 'statics': [{'parts': [{'collprims': 1, 'collprim_ptr': 32}]}]}
        self.context = dict(data=self.data, theme=1, forms={1: [{'id': 0}]},
                            level={'high_wad': 1}, wads={1: [(77,)]}, files={}, entries=[], mwd=b'',
                            inventory=[dict(entity_index=24, form_name='ORG_TRUCK_RED',
                                            source_offset=128, flags=0)])

    def set_primitive(self, kind=0, flags=2, offset=10, half_width=100, matrix=-1):
        struct.pack_into('<2H', self.raw, 32, kind, flags)
        struct.pack_into('<hhhhiHHHHi', self.raw, 44, offset, 0, 0, 0, 0, half_width, 40, 60, 0, matrix)

    def proof(self):
        with patch.object(corridor.platform, 'resource', return_value=self.raw), \
                patch.object(corridor.mof, 'parse_model', return_value=self.model):
            return corridor.traffic_geometry(self.context)

    def test_complete_integer_path_bound_keeps_route_support_explicitly_false(self):
        proof = self.proof()
        self.assertIs(proof['route_supported'], False)
        entity = proof['entities'][0]
        self.assertEqual(entity['integer_poses'], 21)
        self.assertEqual(entity['primitive_point_z'], [-609, -411])
        self.assertEqual(entity['model_resource_id'], 77)

    def test_reversing_path_changes_signed_local_primitive_offset(self):
        struct.pack_into('<h', self.data, 392, 10)
        struct.pack_into('<h', self.data, 400, -10)
        self.assertEqual(self.proof()['entities'][0]['primitive_point_z'], [-589, -391])

    def test_touching_candidate_boundary_is_rejected_but_one_unit_gap_passes(self):
        self.set_primitive(offset=0)
        for lane_z, accepted in ((-324, True), (-323, False)):
            struct.pack_into('<h', self.data, 396, lane_z)
            struct.pack_into('<h', self.data, 404, lane_z)
            if accepted:
                self.assertEqual(self.proof()['entities'][0]['primitive_point_z'][1], -225)
            else:
                with self.assertRaisesRegex(ValueError, 'intrudes'):
                    self.proof()

    def test_signed16_difference_overflow_invalidates_geometry_proof(self):
        struct.pack_into('<h', self.data, 392, 32750)
        struct.pack_into('<h', self.data, 400, 32760)
        with self.assertRaisesRegex(ValueError, 'source-width'):
            self.proof()

    def test_non_horizontal_lane_is_rejected(self):
        struct.pack_into('<h', self.data, 404, -499)
        with self.assertRaisesRegex(ValueError, 'horizontal lane'):
            self.proof()

    def test_changed_primitive_frame_shape_or_empty_width_is_rejected(self):
        for changed in ({'kind': 1}, {'flags': 0}, {'matrix': 0}, {'half_width': 0}):
            self.set_primitive(**changed)
            with self.subTest(changed=changed), self.assertRaisesRegex(ValueError, 'frame/type'):
                self.proof()

    def test_extra_primitive_or_nonstatic_topology_is_rejected(self):
        self.model['statics'][0]['parts'][0]['collprims'] = 2
        with self.assertRaisesRegex(ValueError, 'primitive count'):
            self.proof()
        self.model['kind'] = 'animated'
        with self.assertRaisesRegex(ValueError, 'topology'):
            self.proof()

    def test_changed_path_flags_segments_or_length_are_rejected(self):
        for offset, format_, value, message in ((158, '<H', 0, 'start flags'),
                                               (324, '<I', 2, 'segment count'),
                                               (388, '<i', 0, 'straight line')):
            original = self.data[:]
            struct.pack_into(format_, self.data, offset, value)
            with self.subTest(offset=offset), self.assertRaisesRegex(ValueError, message):
                self.proof()
            self.data[:] = original


if __name__ == '__main__':
    unittest.main()
