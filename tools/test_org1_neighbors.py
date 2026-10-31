#!/usr/bin/env python3
"""Asset-free checks for source FORM boundaries and shared-write closure."""
import unittest
import struct
from unittest.mock import patch

import make_golden_form_contacts as contacts
import org1_neighbors as neighbors


class NeighborFactsTests(unittest.TestCase):
    def test_neighbor_scan_rejects_repointed_book_despite_stale_inventory(self):
        names = list(neighbors.BEHAVIOR_BINDINGS)
        entity_names = sorted({pair[0] for pair in neighbors.BEHAVIOR_BINDINGS.values()})
        script_names = sorted({pair[1] for pair in neighbors.BEHAVIOR_BINDINGS.values()})+['SCRIPT_X_DEVIATION']
        forms = [dict(global_=index,entity_type=entity_names.index(pair[0]),
                      script=script_names.index(pair[1]),id=0,flags=0,collision=0,radius2=1,bonus=0)
                 for index,pair in enumerate(neighbors.BEHAVIOR_BINDINGS.values())]
        for book in forms:
            book['global'] = book.pop('global_')
        medium = forms[names.index('ORG_LOG_MEDIUM')]
        data = bytearray(512+64*64)
        inventory = []
        for index,name in enumerate(neighbors.AUTHORED_FORMS):
            at = 512+index*64
            struct.pack_into('<I',data,12+index*4,at)
            struct.pack_into('<4H',data,at,0,index,names.index(name),0)
            inventory.append(dict(entity_index=index,source_offset=at,form_name=name))
        context = dict(data=data,packet=0,inventory=inventory,names=names,entity_names=entity_names,
                       script_names=script_names,forms={1:forms},theme=1,themes=[dict(high_wad=205)],
                       level=dict(high_wad=379),wads={205:[],379:[(10,3)]})
        model = dict(max_y_from_model=1,computed_radius_squared=1,primitive_count=0)
        mutations = [('script',len(script_names)-1,'entity/script binding'),
                     ('global',names.index('ORG_LOG_SMALL'),'audited form name'),
                     ('entity_type',entity_names.index('STATIC_NOISE'),'entity/script binding'),
                     ('collision',1234,'unaudited collision callback')]
        for key,value,message in mutations:
            original = medium[key]
            medium[key] = value
            with self.subTest(field=key), patch.object(neighbors.contacts,'parse_forms',
                    return_value=[(0,20,0,0,0,0,0,0,[])]), patch.object(neighbors,'decode_paths',return_value=[]), \
                    patch.object(neighbors,'geometry_script_closure',return_value=[]), \
                    patch.object(neighbors,'model_facts',return_value=model), \
                    self.assertRaisesRegex(ValueError,message):
                neighbors.neighbor_facts(dict(entity_count=64),context)
            medium[key] = original

    def test_audited_medium_log_behavior_binding(self):
        neighbors.validate_behavior_binding(17,'ORG_LOG_MEDIUM','MOVING','SCRIPT_LOG_SPLASH',0)

    def test_repointed_medium_log_script_is_rejected(self):
        with self.assertRaisesRegex(ValueError,'entity/script binding'):
            neighbors.validate_behavior_binding(17,'ORG_LOG_MEDIUM','MOVING','SCRIPT_X_DEVIATION',0)

    def test_changed_form_name_is_rejected(self):
        for name in ('UNKNOWN_FORM','ORG_LOG_SMALL'):
            with self.subTest(name=name), self.assertRaisesRegex(ValueError,'audited form name'):
                neighbors.validate_behavior_binding(17,name,'MOVING','SCRIPT_LOG_SPLASH',0)

    def test_changed_entity_type_is_rejected(self):
        with self.assertRaisesRegex(ValueError,'entity/script binding'):
            neighbors.validate_behavior_binding(17,'ORG_LOG_MEDIUM','STATIC','SCRIPT_LOG_SPLASH',0)

    def test_nonzero_collision_callback_is_rejected(self):
        with self.assertRaisesRegex(ValueError,'unaudited collision callback'):
            neighbors.validate_behavior_binding(17,'ORG_LOG_MEDIUM','MOVING','SCRIPT_LOG_SPLASH',1234)

    def test_thick_precedes_unit(self):
        self.assertEqual(neighbors.runtime_max_y(32 | 512, 19), 32767)
        self.assertEqual(neighbors.runtime_max_y(512, 19), 256)
        self.assertEqual(neighbors.runtime_max_y(0, 19), 19)

    def test_last_writer_wins_even_when_values_disagree(self):
        forms = [(0, 20, 0, 0, 0, 0, 0, 0, [])]
        writers = {0: [dict(entity_index=2, value=32767), dict(entity_index=7, value=256)]}
        actual = neighbors.resolve_form_writers(forms, writers)[0]
        self.assertEqual((actual['final_writer'], actual['final_max_y']), (7, 256))
        self.assertFalse(actual['all_writers_agree'])
        reverse = neighbors.resolve_form_writers(forms, {0: list(reversed(writers[0]))})[0]
        self.assertEqual((reverse['final_writer'], reverse['final_max_y']), (2, 32767))

    def test_empty_form_without_writer_preserves_stored_word(self):
        forms = [(0, 20, 0, -23, 0, 0, 0, 0, [])]
        actual = neighbors.resolve_form_writers(forms, {0: []})[0]
        self.assertIsNone(actual['final_writer'])
        self.assertEqual(actual['final_max_y'], -23)

    def test_half_open_candidate(self):
        self.assertFalse(neighbors.intersects([-600,-513,-224,479]))
        self.assertTrue(neighbors.intersects([-512,-512,-224,-224]))
        self.assertFalse(neighbors.intersects([512,512,-224,479]))
        self.assertFalse(neighbors.intersects([-512,511,480,480]))

    def test_sphere_width_closure_includes_signed32_sum(self):
        self.assertTrue(neighbors.sphere_width_closed([4224,0,-128]))
        self.assertFalse(neighbors.sphere_width_closed([32768,0,0]))
        self.assertFalse(neighbors.sphere_width_closed([24000,0,24000]))

    def test_geometry_closure_rejects_unknown_callback(self):
        opcodes = {v[0]:k for k,v in enumerate(neighbors.exe_tables.OPCODES)}
        context = dict(script_names=['SCRIPT_TURTLE','SCRIPT_TURTLE_NO_DIVE','SCRIPT_LOG_SPLASH'],
            scripts=[dict(stream=[opcodes['REGISTER_CALLBACK'],0,0,0,0])],callbacks=['UNKNOWN_CALLBACK'])
        with self.assertRaisesRegex(ValueError,'callback without XZ closure'):
            neighbors.geometry_script_closure(context)

    def test_geometry_closure_rejects_x_deviation(self):
        opcodes = {v[0]:k for k,v in enumerate(neighbors.exe_tables.OPCODES)}
        context = dict(script_names=['SCRIPT_TURTLE','SCRIPT_TURTLE_NO_DIVE','SCRIPT_LOG_SPLASH'],
            scripts=[dict(stream=[opcodes['DEVIATE'],0,0,128,2048,-1])],callbacks=[])
        with self.assertRaisesRegex(ValueError,'no longer immediate Y only'):
            neighbors.geometry_script_closure(context)

    def test_exact_inverse_contains_independent_source_gate(self):
        form = (0, 20, 1, 256, 1, 2, -10, -20,
                [(24, 0, -100, 30, 0, [3,3])])
        for yaw in ((4096,0), (0,4096), (2896,2896), (-4087,275)):
            a, b = yaw
            matrix = [a,0,b,0,4096,0,-b,0,a,11,0,-33]
            bounds = neighbors.form_xz_bounds(matrix,form)
            hits = 0
            for x in range(-600, 601, 7):
                for z in range(-600, 601, 7):
                    status, *_ = contacts.evaluate(dict(matrix12=matrix, frog=[x,0,z],
                        entity_flags=0, radius_squared=2**30, offsets=[-10,-20],
                        dimensions=[1,2],height=-100,max_y=256,grid_flags=[3,3]))
                    if status == 'contact':
                        hits += 1
                        self.assertTrue(bounds[0] <= x <= bounds[1] and bounds[2] <= z <= bounds[3])
            self.assertGreater(hits, 0)

    def test_identity_strict_form_boundary(self):
        form = (0,20,1,0,1,1,-10,-20,[(24,0,0,30,0,[3])])
        matrix = [4096,0,0,0,4096,0,0,0,4096,100,0,200]
        self.assertEqual(neighbors.form_xz_bounds(matrix,form),[91,345,181,435])


if __name__ == '__main__':
    unittest.main()
