#!/usr/bin/env python3
"""Independent ORG1 FORM writers and conservative all-neighbor facts.

The input context comes from verify_org1_corridor.retail_counterexamples. This
module does not read GDScript output, support a route, or serialize retail bytes.
Bounds cover every integer path distance, rather than only authored starts.
"""
from fractions import Fraction
import hashlib
import struct

import make_golden_entities as entities
import make_golden_exe_tables as exe_tables
import make_golden_form_contacts as contacts
import make_golden_mof as mof
import make_golden_paths as paths
import make_golden_retail_platform as platform


CANDIDATE = (-512, 512, -224, 480)
BEHAVIOR_BINDINGS = {
    'ORG_TURTLE3': ('SUB_TURTLE','SCRIPT_TURTLE'),
    'ORG_TURTLE2': ('SUB_TURTLE','SCRIPT_TURTLE'),
    'ORG_LOG_LARGE': ('MOVING','SCRIPT_LOG_SPLASH'),
    'ORG_LOG_MEDIUM': ('MOVING','SCRIPT_LOG_SPLASH'),
    'ORG_LOG_SMALL': ('MOVING','SCRIPT_LOG_SPLASH'),
    'ORG_TRUCK_RED': ('MOVING','SCRIPT_ORG_TRUCK'),
    'ORG_LORRY': ('MOVING','SCRIPT_ORG_LORRY'),
    'ORG_CAR_PURPLE': ('MOVING','SCRIPT_ORG_CAR_PURPLE'),
    'ORG_BULL_DOZER': ('MOVING','SCRIPT_ORG_BULL_DOZER'),
    'ORG_CAR_BLUE': ('MOVING','SCRIPT_ORG_CAR_BLUE'),
    **{f'GEN_CHECKPOINT_{i}': ('CHECKPOINT','SCRIPT_NONE') for i in range(1,6)},
    'ORG_BABYFROG': ('ORG_BABY_FROG','SCRIPT_NONE'),
    'ORG_FLY': ('ORG_FLY','SCRIPT_NONE'),
    'ORG_ROADNOISE': ('STATIC_NOISE','SCRIPT_ORG_ROAD_NOISE'),
    'ORG_RIVERNOISE': ('STATIC_NOISE','SCRIPT_ORG_WATER_NOISE'),
    'GEN_BOTTOMRIGHT': ('GEN_BOTTOM_RIGHT','SCRIPT_NONE'),
    'GEN_TOPLEFT': ('GEN_TOP_LEFT','SCRIPT_NONE'),
}
AUTHORED_FORMS = (
    ['ORG_TURTLE3']*4 + ['ORG_TURTLE2']*5 + ['ORG_LOG_LARGE']*3 +
    ['ORG_LOG_SMALL']*5 + ['ORG_LOG_MEDIUM']*6 + ['ORG_LOG_SMALL'] +
    ['ORG_TRUCK_RED']*6 + ['ORG_LORRY']*4 + ['ORG_CAR_PURPLE']*6 +
    ['ORG_BULL_DOZER']*5 + ['ORG_CAR_BLUE']*2 + ['ORG_BULL_DOZER','ORG_TURTLE2'] +
    ['GEN_CHECKPOINT_2','GEN_CHECKPOINT_3','GEN_CHECKPOINT_4','GEN_CHECKPOINT_5',
     'ORG_BABYFROG','GEN_CHECKPOINT_1','ORG_FLY'] +
    ['ORG_ROADNOISE']*2 + ['ORG_RIVERNOISE']*2 +
    ['GEN_BOTTOMRIGHT','GEN_TOPLEFT','ORG_RIVERNOISE','ORG_ROADNOISE'])


def validate_behavior_binding(index, form_name, entity_type, script_name, collision_callback):
    """Bind each authored identity to its audited named behavior before bounds."""
    if (not 0 <= index < len(AUTHORED_FORMS) or form_name not in BEHAVIOR_BINDINGS
            or AUTHORED_FORMS[index] != form_name):
        raise ValueError(f'ORG1 entity {index} changed its audited form name: {form_name}')
    if BEHAVIOR_BINDINGS[form_name] != (entity_type,script_name):
        raise ValueError(f'ORG1 entity {index} changed its audited entity/script binding')
    if collision_callback:
        raise ValueError(f'ORG1 entity {index} has an unaudited collision callback')


def runtime_max_y(book_flags, model_y):
    """Frozen ResolveMapEntities precedence: THICK before UNIT before bbox."""
    return 32767 if book_flags & 32 else 256 if book_flags & 512 else model_y


def resolve_form_writers(forms, writers):
    """Resolve source-ordered shared writes independently of live update order."""
    return [dict(form_grid_id=i, source_offset=form[1], form_data_count=form[2],
                 dimensions=list(form[4:6]) if form[2] else [],
                 offsets=list(form[6:8]) if form[2] else [],
                 height=form[8][0][2] if form[2] else None,
                 flags=form[8][0][5] if form[2] else [],
                 writers=writers[i], final_writer=writers[i][-1]['entity_index'] if writers[i] else None,
                 final_max_y=writers[i][-1]['value'] if writers[i] else form[3],
                 all_writers_agree=len({w['value'] for w in writers[i]}) <= 1)
            for i, form in enumerate(forms)]


def decode_paths(data):
    """Decode the complete path library required by the authored neighbors."""
    packet = contacts.read(data, 96, '<I')
    result = []
    for index in range(contacts.read(data, packet + 4, '<I')):
        ptr = contacts.read(data, packet + 8 + index * 4, '<I')
        segments = []
        for si in range(contacts.read(data, ptr + 4, '<I')):
            at = contacts.read(data, ptr + 8 + si * 4, '<I')
            kind, length = struct.unpack_from('<2i', data, at)
            item = dict(segment_type=kind, length=length)
            if kind == 0:
                words = list(struct.unpack_from('<28i', data, at + 8))
                item.update(matrix=words[:12], smooth_t=words[12:16], smooth_c=words[16:])
            elif kind == 2:
                item.update(start=list(struct.unpack_from('<3h', data, at + 8)),
                            end=list(struct.unpack_from('<3h', data, at + 16)))
            else:
                raise ValueError(f'ORG1 neighbor path {index}/{si} has unaudited kind {kind}')
            if length <= 0:
                raise ValueError('ORG1 neighbor path has nonpositive length')
            segments.append(item)
        result.append(segments)
    return result


def model_facts(context, resource_id, cache):
    """Read runtime max-Y/radius inputs, including incomplete-model borrowing."""
    if resource_id in cache:
        return cache[resource_id]
    raw = platform.resource(context['files'], context['entries'], context['mwd'], resource_id)
    counterpart_id = -1
    counterpart = None
    if raw[:4] == b'\x02FOM' and contacts.read(raw, 28, '<I') == 0x40:
        candidates = sorted({rid for children in context['wads'].values()
                             for rid, kind in children if kind in (3, 4) and rid < resource_id}, reverse=True)
        for rid in candidates:
            candidate = platform.resource(context['files'], context['entries'], context['mwd'], rid)
            if candidate[:4] != b'\x02FOM' or contacts.read(candidate, 28, '<I') != 0x40:
                counterpart_id = rid
                counterpart = model_facts(context, rid, cache)['_model']
                break
        if counterpart is None:
            raise ValueError('incomplete ORG1 model has no complete counterpart')
    warnings = []
    model = mof.parse_model(raw, str(resource_id), counterpart, warnings)
    if warnings:
        raise ValueError(f'ORG1 model {resource_id} has unaudited reader warnings: {warnings}')
    if model['kind'] != 'static' or len(model['statics']) != 1 or len(model['statics'][0]['parts']) != 1:
        raise ValueError(f'ORG1 model {resource_id} left the audited single-part static/flipbook topology')
    parts = model['statics'][0]['parts']
    effective_parts = counterpart['statics'][0]['parts'] if model['incomplete'] else parts
    boxes = []
    primitives = []
    if model['kind'] == 'static':
        max_y = effective_parts[0]['partcel_list'][0]['box'][22]
        boxes = [cel['box'] for part in effective_parts for cel in part['partcel_list'] if cel['box']]
        primitive_raw = raw if not model['incomplete'] else platform.resource(
            context['files'], context['entries'], context['mwd'], counterpart_id)
        for part in effective_parts:
            for ci in range(part['collprims']):
                cp = part['collprim_ptr'] + ci * 40
                kind, flags = struct.unpack_from('<2H', primitive_raw, cp)
                ox, oy, oz, _pad, radius2, xlen, ylen, zlen, _user, matrix = struct.unpack_from(
                    '<hhhhiHHHHi', primitive_raw, cp + 12)
                if kind == 0:
                    shape2 = xlen*xlen + ylen*ylen + zlen*zlen
                elif kind in (1, 2, 3):
                    shape2 = (xlen, ylen, zlen)[kind - 1] ** 2 + radius2
                elif kind == 4:
                    shape2 = radius2
                else:
                    raise ValueError('ORG1 model primitive kind changed')
                primitives.append(dict(kind=kind, flags=flags, offset=[ox, oy, oz],
                                       half_lengths=[xlen, ylen, zlen], matrix=matrix,
                                       radius_contribution=ox*ox + oy*oy + oz*oz + shape2))
    radius = max([sum(box[i+j] ** 2 for j in range(3)) for box in boxes
                  for i in range(0, len(box), 3)] + [p['radius_contribution'] for p in primitives]) + 100
    result = dict(resource_id=resource_id, sha256=hashlib.sha256(raw).hexdigest(),
                  counterpart_resource_id=counterpart_id, kind=model['kind'],
                  max_y_from_model=max_y, computed_radius_squared=radius,
                  primitive_count=sum(part['collprims'] for part in effective_parts),
                  primitives=primitives, _model=model)
    cache[resource_id] = result
    return result


def form_xz_bounds(matrix, form):
    """Outward integer bounds for the exact source transpose/floor FORM gate.

    The horizontal 2x2 transpose is inverted exactly as rational numbers. This
    avoids assuming a rounded source rotation is orthonormal. Local integer
    limits become closed numerator inequalities before inversion.
    """
    if any(matrix[i] for i in (1, 3, 5, 7)) or matrix[4] != 4096:
        raise ValueError('ORG1 FORM pose is no longer horizontal')
    _idx, _at, count, _max_y, nx, nz, xo, zo, items = form
    if count != 1 or items[0][1] != 0:
        raise ValueError('ORG1 contact neighbor requires exactly one GRID FORM_DATA')
    a, b, c, d = matrix[0], matrix[6], matrix[2], matrix[8]
    determinant = a*d - b*c
    if not determinant:
        raise ValueError('ORG1 FORM pose has singular XZ transpose')
    xs = ((xo+1)*4096, (xo+nx*256)*4096-1)
    zs = ((zo+1)*4096, (zo+nz*256)*4096-1)
    corners = [(Fraction(d*x-b*z, determinant)+matrix[9],
                Fraction(a*z-c*x, determinant)+matrix[11]) for x in xs for z in zs]
    ceil = lambda value: -(-value.numerator // value.denominator)
    return [ceil(min(p[0] for p in corners)), max(p[0] for p in corners).__floor__(),
            ceil(min(p[1] for p in corners)), max(p[1] for p in corners).__floor__()]


def intersects(bounds, candidate=CANDIDATE):
    """Whether closed integer bounds overlap the half-open candidate."""
    return (bounds[0] < candidate[1] and bounds[1] >= candidate[0]
            and bounds[2] < candidate[3] and bounds[3] >= candidate[2])


def sphere_width_closed(position,candidate=CANDIDATE):
    """Prove unwrapped XZ subtraction and signed32 squared sum for every Y."""
    dx = max(abs(position[0]-candidate[0]),abs(position[0]-candidate[1]+1))
    dz = max(abs(position[2]-candidate[2]),abs(position[2]-candidate[3]+1))
    return max(dx,dz) < 32768 and dx*dx+dz*dz+32768**2 < 2**31


def terrain_facts(data,candidate=CANDIDATE):
    """Decode every terrain layer touched by the rectangle, including bank."""
    grap = contacts.read(data, 80, '<I')
    grid = contacts.read(data, grap + 20, '<I')
    vertices = contacts.read(data, grap + 16, '<I')
    width, depth = struct.unpack_from('<2H', data, grid + 4)
    result = []
    for cz in range(depth):
        for cx in range(width):
            x, z = -width*128+cx*256, -depth*128+cz*256
            if not intersects([x, x+255, z, z+255],candidate):
                continue
            count, _average, first = struct.unpack_from('<BBH', data, grid+12+(cz*width+cx)*4)
            layers = []
            for layer in range(count):
                at = grid+12+width*depth*4+(first+layer)*8
                flags, polygon = struct.unpack_from('<II', data, at)
                ids = struct.unpack_from('<4H', data, polygon)
                points = [list(struct.unpack_from('<3h', data, vertices+8+vi*8)) for vi in ids]
                layers.append(dict(flags=flags, vertices=points,
                                   mean_height=sum(p[1] for p in points) >> 2))
            result.append(dict(grid=[cx,cz], world_x=[x,x+256], world_z=[z,z+256], layers=layers))
    return result


def geometry_script_closure(context):
    """Reject turtle/log programs that can change their audited XZ poses."""
    accepted = {'PREPARE_REGISTERS', 'SET_ENTITY_TYPE', 'REGISTER_CALLBACK',
                'SETLOOP', 'SET_ACTION', 'SET_TIMER', 'WAIT_UNTIL_TIMER',
                'DEVIATE', 'PLAY_MOVING_SOUND', 'CREATE_3D_SPRITE',
                'WAIT_DEVIATED', 'PLAY_SOUND_DISTANCE', 'ENDLOOP', 'RESTART', 'STOP'}
    result = []
    for name in ('SCRIPT_TURTLE', 'SCRIPT_TURTLE_NO_DIVE', 'SCRIPT_LOG_SPLASH'):
        sid = context['script_names'].index(name)
        stream = context['scripts'][sid]['stream']
        cursor, ops, deviations = 0, [], []
        while cursor < len(stream):
            word = stream[cursor]
            if type(word) is not int or not 0 <= word < len(exe_tables.OPCODES):
                raise ValueError(f'{name} contains an invalid opcode')
            op, count = exe_tables.OPCODES[word]
            args = stream[cursor+1:cursor+count+1]
            if len(args) != count or op not in accepted:
                raise ValueError(f'{name} contains unaudited XZ behavior {op}')
            if op == 'DEVIATE':
                if args[:2] != [0,1]:
                    raise ValueError(f'{name} deviation is no longer immediate Y only')
                deviations.append(args[2:])
            if op == 'REGISTER_CALLBACK':
                if (not 0 <= args[1] < len(context['callbacks']) or context['callbacks'][args[1]] not in (
                        'SCRIPT_CB_HIT_TURTLE','SCRIPT_CB_LOG_SPLASH','SCRIPT_CB_DIVE_COLOUR_CHANGE')):
                    raise ValueError(f'{name} contains a callback without XZ closure')
            if op == 'SET_ENTITY_TYPE' and args != [0]:
                raise ValueError('ORG1 turtle no longer uses its path entity type')
            ops.append(op)
            cursor += count+1
        result.append(dict(name=name, script_id=sid, opcodes=ops, y_deviations=deviations,
                           condition='Frozen callbacks HIT_TURTLE, LOG_SPLASH and DIVE_COLOUR_CHANGE do not change XZ'))
    return result


def neighbor_facts(facts, context, candidate=CANDIDATE):
    """Close FORM writers and classify all authored identities without supporting a route."""
    data = context['data']
    if (facts['entity_count'] != len(AUTHORED_FORMS)
            or [item['entity_index'] for item in context['inventory']] != list(range(len(AUTHORED_FORMS)))):
        raise ValueError('ORG1 all-neighbor source-ordered identity closure changed')
    forms = contacts.parse_forms(data)
    definitions = decode_paths(data)
    geometry_programs = geometry_script_closure(context)
    cache, records, writers = {}, [], {i: [] for i in range(len(forms))}
    general_high_wad = context['themes'][0]['high_wad']
    if general_high_wad != 205 or general_high_wad not in context['wads']:
        raise ValueError('missing v3.0e GENERAL high WAD')
    for identity in context['inventory']:
        item = dict(identity)
        at = item['source_offset']
        if at != contacts.read(data,context['packet']+12+item['entity_index']*4,'<I'):
            raise ValueError('ORG1 neighbor source pointer provenance changed')
        grid_id, uid, form_id, flags = struct.unpack_from('<4H', data, at)
        owner = 0 if form_id & 0x8000 else context['theme']
        book = context['forms'][owner][form_id & 0x7fff]
        for value, names in ((book['global'],context['names']),
                             (book['entity_type'],context['entity_names']),
                             (book['script'],context['script_names'])):
            if not 0 <= value < len(names):
                raise ValueError('ORG1 behavior binding has an out-of-range name index')
        form_name = context['names'][book['global']]
        entity_type = context['entity_names'][book['entity_type']]
        script_name = context['script_names'][book['script']]
        validate_behavior_binding(item['entity_index'],form_name,entity_type,script_name,book['collision'])
        item.update(form_name=form_name,entity_type=entity_type,script_name=script_name,
                    script_id=book['script'],unique_id=uid,flags=flags)
        mid = (context['wads'][general_high_wad][book['id']-128][0] if book['id'] >= 128 else
               context['wads'][context['level']['high_wad']][book['id']][0])
        model = model_facts(context, mid, cache)
        max_y = runtime_max_y(book['flags'], model['max_y_from_model'])
        radius = book['radius2'] or model['computed_radius_squared']
        item.update(form_grid_id=grid_id, form_id=form_id, book_flags=book['flags'],
                    collision_callback=book['collision'], bonus_callback=book['bonus'],
                    model_resource_id=mid, radius_squared=radius,
                    primitive_count=model['primitive_count'], runtime_max_y_write=max_y)
        obligations = {'MOVING':'retain_path_and_script_state',
            'SUB_TURTLE':'retain_path_type_selected_script_and_Y_deviation',
            'CHECKPOINT':'retain_checkpoint_position_and_covered_state',
            'ORG_BABY_FROG':'retain_all_attached_search_state',
            'ORG_FLY':'retain_RNG_checkpoint_and_fly_state',
            'STATIC_NOISE':'retain_script_and_logical_moving_sound_owner',
            'GEN_BOTTOM_RIGHT':'retain_fade_world_bounds',
            'GEN_TOP_LEFT':'retain_fade_world_bounds'}
        if item['entity_type'] not in obligations:
            raise ValueError(f'ORG1 entity {item["entity_index"]} has unaudited behavior {item["entity_type"]}')
        item['noncontact_obligation'] = obligations[item['entity_type']]
        writers[grid_id].append(dict(entity_index=item['entity_index'], model_resource_id=mid,
                                    value=max_y, rule='THICK_FORM' if book['flags'] & 32 else
                                    'UNIT_FORM' if book['flags'] & 512 else 'model_bbox_vertex7_y'))
        records.append(item)
    grids = resolve_form_writers(forms, writers)
    pose_cache = {}
    unresolved = []
    for item in records:
        index, at = item['entity_index'], item['source_offset']
        form = forms[item['form_grid_id']]
        if item['entity_type'] in ('MOVING', 'SUB_TURTLE'):
            pid, si, start, motion, speed, padding = struct.unpack_from('<6H', data, at+24)
            if item['flags'] or motion != 8 or padding:
                raise ValueError(f'ORG1 moving identity {index} left audited flags')
            item['path'] = dict(index=pid, initial_segment=si, initial_distance=start, speed=speed,
                                motion_flags=motion)
            if item['entity_type'] == 'SUB_TURTLE':
                delay, rise, kind = struct.unpack_from('<3I', data, at+36)
                if kind not in (0,1):
                    raise ValueError('unknown ORG1 turtle type')
                item['turtle'] = dict(dive_delay=delay, rise_delay=rise, type=kind,
                                      effective_script='SCRIPT_TURTLE_NO_DIVE' if kind else 'SCRIPT_TURTLE')
            key = (pid, item['form_grid_id'], item['flags'])
            if key not in pose_cache:
                bounds, count, lane_witness = None, 0, None
                position_bounds = [[32767,-32768] for _ in range(3)]
                for segment in definitions[pid]:
                    for distance in range(segment['length']+1):
                        _param, position, tangent = paths.sample(segment, distance, False)
                        matrix = entities.moving_matrix([0]*9+position+tangent, item['flags'])
                        dx = max(abs(candidate[0]-position[0]), abs(candidate[1]-1-position[0]))
                        dz = max(abs(candidate[2]-position[2]), abs(candidate[3]-1-position[2]))
                        if max(dx,dz) >= 32768 or any(abs(matrix[k])*dx+abs(matrix[k+6])*dz >= 2**31
                                                     for k in (0,2)):
                            raise ValueError('ORG1 contact source-width closure failed')
                        for axis in range(3):
                            position_bounds[axis][0] = min(position_bounds[axis][0],position[axis])
                            position_bounds[axis][1] = max(position_bounds[axis][1],position[axis])
                        if form[2]:
                            current = form_xz_bounds(matrix, form)
                            bounds = current if bounds is None else [min(bounds[0],current[0]),
                                      max(bounds[1],current[1]),min(bounds[2],current[2]),max(bounds[3],current[3])]
                            if lane_witness is None and pid in (6,8):
                                frog = [128,position[1]+form[8][0][2],128 if pid == 6 else 384]
                                status, local, cell, height, cell_flags = contacts.evaluate(dict(
                                    matrix12=matrix,frog=frog,entity_flags=item['flags'],
                                    radius_squared=item['radius_squared'], offsets=list(form[6:8]),
                                    dimensions=list(form[4:6]),height=form[8][0][2],
                                    max_y=grids[item['form_grid_id']]['final_max_y'],grid_flags=form[8][0][5]))
                                if status == 'contact' and cell_flags & 3 == 3:
                                    lane_witness = dict(segment_index=definitions[pid].index(segment),
                                        integer_distance=distance,frog=frog,matrix12=matrix,local=local,
                                        cell=cell,cell_flags=cell_flags,
                                        scope='Independent spatial witness at base Y; not a timed route or diving state')
                        count += 1
                pose_cache[key] = dict(integer_poses=count, form_xz_bounds=bounds,
                                       position_bounds=position_bounds, lane_witness=lane_witness)
            item['geometry'] = dict(pose_cache[key])
            if item['primitive_count']:
                item['contact_status'] = 'primitive_exclusion_requires_frog_hilite_bound'
                unresolved.append(index)
            elif form[2] and intersects(item['geometry']['form_xz_bounds'],candidate):
                item['contact_status'] = 'include_possible_FORM_contact'
            else:
                item['contact_status'] = 'excluded_by_complete_path_FORM_bounds'
        else:
            if item['entity_type'] not in ('CHECKPOINT','ORG_BABY_FROG','ORG_FLY',
                                            'STATIC_NOISE','GEN_BOTTOM_RIGHT','GEN_TOP_LEFT'):
                raise ValueError(f'ORG1 entity {index} has unaudited custom matrix payload {item["entity_type"]}')
            raw_matrix = struct.unpack_from('<10h3i',data,at+24)
            matrix = list(raw_matrix[:9])+list(raw_matrix[10:])
            item['initial_position'] = matrix[9:]
            if item['flags'] & 8:
                item['contact_status'] = 'excluded_no_collision_authored_flag'
            elif item['entity_type'] == 'ORG_FLY':
                points = [other['source_offset'] for other in records if other['entity_type']=='CHECKPOINT']
                positions = [matrix[9:]] + [list(struct.unpack_from('<3i',data,p+44)) for p in points]
                for point in positions[1:]:
                    point[1] = contacts.s16(point[1]-256)
                    point[2] = contacts.s16(point[2]-50)
                z_positions = [p[2] for p in positions]
                gap = min(z-candidate[3]+1 for z in z_positions)
                item['all_cycle_positions'] = positions
                item['sphere_source_widths_closed'] = all(sphere_width_closed(p,candidate) for p in positions)
                item['minimum_candidate_xz_distance_squared'] = gap*gap if gap > 0 else 0
                item['contact_status'] = ('excluded_by_all_cycle_origin_sphere' if item['sphere_source_widths_closed'] and gap > 0 and gap*gap >= item['radius_squared']
                                          else 'unresolved_custom_contact')
            elif item['book_flags'] & 1 and not item['collision_callback']:
                item['contact_status'] = 'excluded_NO_MODEL_without_collision_callback'
            else:
                dx = max(candidate[0]-matrix[9], 0, matrix[9]-(candidate[1]-1))
                dz = max(candidate[2]-matrix[11], 0, matrix[11]-(candidate[3]-1))
                item['minimum_candidate_xz_distance_squared'] = dx*dx+dz*dz
                safe_width = sphere_width_closed(matrix[9:],candidate)
                item['sphere_source_widths_closed'] = safe_width
                item['contact_status'] = ('excluded_by_origin_sphere' if safe_width and dx*dx+dz*dz >= item['radius_squared']
                                          else 'unresolved_custom_contact')
                if item['entity_type'] == 'ORG_BABY_FROG':
                    parent_uid = contacts.read(data, at+56,'<h')
                    parents = [r['entity_index'] for r in records if r['unique_id']==parent_uid]
                    if len(parents) != 1:
                        raise ValueError('baby frog parent identity is not unique')
                    item['lifetime_condition'] = dict(parent_unique_id=parent_uid,parent_entity_index=parents[0],
                        invariant='all-attached uninterrupted parent lifetime; first search enters WAIT_TO_SEARCH_AGAIN')
            if item['contact_status'] == 'unresolved_custom_contact':
                unresolved.append(index)
        if item['bonus_callback'] and item['contact_status'] not in (
                'excluded_by_origin_sphere','excluded_by_all_cycle_origin_sphere'):
            raise ValueError(f'ORG1 entity {index} bonus callback is not excluded by a certified origin sphere')
    return dict(schema='org1-neighbors-v1', candidate_x=list(candidate[:2]),
                candidate_z=list(candidate[2:]), route_supported=False,
                build=facts['build'], map_sha256=facts['map_sha256'], executable_sha256=facts['executable_sha256'],
                authored_count=len(records), form_writer_closure_complete=True,
                behavior_binding_closure_complete=True,
                general_high_wad=general_high_wad,
                contact_scope='FORM/collision scan only. Spatial witnesses do not prove a timed route or frog input/effect closure.',
                form_grids=grids, neighbors=records,
                models=[{k:v for k,v in value.items() if k != '_model'} for _,value in sorted(cache.items())],
                zone_count=contacts.read(data,contacts.read(data,92,'<I')+4,'<I'),
                terrain=terrain_facts(data,candidate),
                included_FORM_indices=[r['entity_index'] for r in records if r['contact_status']=='include_possible_FORM_contact'],
                unresolved_contact_indices=unresolved,
                conditions=['Every authored identity participates in ResolveMapEntities FORM writes, in source order.',
                            'All attached lifetime; baby parent cannot retire. Turtle scripts may deviate Y only.',
                            'Source XZ widths checked; Y remains a route/oracle obligation.'],
                geometry_script_closure=geometry_programs,
                blocking_conditions=['Traffic primitive exclusion needs a certified retail animated frog-hilite bound.',
                    'Connected bank/turtle/small-log round trip requires linked frozen-C phase trace and boundary checks.',
                    'Turtle script state, animation and active-frog requests require their component/integrated gates.'],
                source_contracts=['mapload.C/ResolveMapEntities','COLLIDE.C/CollideFrog',
                                  'ent_sub.c/ENTSTRSubCreateTurtle','ent_org.c/ENTSTROrgUpdateBabyFrog',
                                  'ent_org.c/ENTSTROrgUpdateBonusFly'])
