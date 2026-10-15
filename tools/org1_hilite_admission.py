#!/usr/bin/env python3
"""Independent, fail-closed ORG1 frog-probe reach diagnostic.

This module does not admit a route.  It scans every hilite in every part and
every discrete cel of both retail high-poly animation banks, including the
three alternate player meshes.  All transforms use integer source arithmetic;
the animation oracle's approximate quaternion interpolation is never used.

The general envelope allows every signed16 frog root coefficient (therefore
also tilted/scaled roots).  It is an over-approximation, not a reachability
claim.  Its overlap cannot establish that a collision is reachable.
"""
import hashlib
import re

import make_golden_animation as animation
import make_golden_mof as mof
import make_golden_retail_platform as platform


SHORT = (-32768, 32767)
CANDIDATE_X = (-512, 512)
CANDIDATE_Z = (-224, 480)
THROAT = 15  # frozen gen_frog.h GEN_FROG_PARTS; imported croak transform
ROOTS = (
    ('north', (4096, 0, 0, 0, 4096, 0, 0, 0, 4096)),
    ('east', (0, 0, 4096, 0, 4096, 0, -4096, 0, 0)),
    ('south', (-4096, 0, 0, 0, 4096, 0, 0, 0, -4096)),
    ('west', (0, 0, -4096, 0, 4096, 0, 4096, 0, 0)),
)


def short(value):
    """Narrow an integer as the frozen LLP64 short stores do."""
    return (value + 32768) % 65536 - 32768


def short_interval(bounds):
    """Conservatively enclose a short store, retaining possible wrap."""
    low, high = bounds
    return bounds if SHORT[0] <= low <= high <= SHORT[1] else SHORT


def dot_interval(coefficients, bounds=SHORT):
    """Bound a dot product of independent bounded integer coefficients."""
    products = [(min(c * bounds[0], c * bounds[1]),
                 max(c * bounds[0], c * bounds[1])) for c in coefficients]
    low, high = sum(p[0] for p in products), sum(p[1] for p in products)
    if low < -(1 << 31) or high >= (1 << 31):
        raise ValueError('affine accumulator may overflow frozen 32-bit long')
    return low >> 12, high >> 12


def transformed_probe(matrix, vertex, root):
    """MRMulMatrixABC + stored part translation + ApplyMatrixSVEC.

    Return the offset from the root origin, prior to the final short world
    store.  The root is rotation/scale only; the caller supplies its origin.
    Matrix-product and probe stores narrow separately, just as frozen C does.
    """
    product = [short(sum(root[3 * r + k] * matrix[3 * k + c]
                         for k in range(3)) >> 12)
               for r in range(3) for c in range(3)]
    translation = [sum(root[3 * r + k] * matrix[9 + k]
                       for k in range(3)) >> 12 for r in range(3)]
    return [short(sum(product[3 * r + k] * vertex[k]
                      for k in range(3)) >> 12) + translation[r]
            for r in range(3)]


def affine_probe_envelope(matrix, vertex):
    """Enclose each axis for ALL signed16 root matrix coefficients.

    Rows are independent and have the same enclosure.  Correlation lost at
    the composed-matrix store only widens the bound.  Imported transforms on
    a collision-bearing part must be rejected by the decoder.
    """
    columns = [short_interval(dot_interval(matrix[c:9:3])) for c in range(3)]
    terms = [(min(vertex[c] * columns[c][0], vertex[c] * columns[c][1]),
              max(vertex[c] * columns[c][0], vertex[c] * columns[c][1]))
             for c in range(3)]
    low, high = sum(p[0] for p in terms), sum(p[1] for p in terms)
    if low < -(1 << 31) or high >= (1 << 31):
        raise ValueError('probe accumulator may overflow frozen 32-bit long')
    rotated = short_interval((low >> 12, high >> 12))
    translated = dot_interval(matrix[9:12])
    return rotated[0] + translated[0], rotated[1] + translated[1]


def all_hilites(static):
    """Yield every vertex hilite/partcel; display flags never filter collisions."""
    if static['incomplete']:
        raise ValueError('incomplete frog geometry is not supported')
    for part_index, part in enumerate(static['parts']):
        if part['hilites'] != len(part['hilite_list']):
            raise ValueError('frog hilite count mismatch')
        for hilite_index, (_kind, attach, target) in enumerate(part['hilite_list']):
            if attach != 1:
                raise ValueError('collision hilite is not vertex-attached')
            if not isinstance(target, int) or isinstance(target, bool) or target < 0:
                raise ValueError('collision hilite target is not a nonnegative integer')
            if part_index == THROAT:
                raise ValueError('imported croak transform on a collision-bearing part')
            if not part['partcel_list']:
                raise ValueError('collision hilite has no partcel')
            for cel_index, cel in enumerate(part['partcel_list']):
                vertex = cel['vertices'][3 * target:3 * target + 3]
                if len(vertex) != 3:
                    raise ValueError('collision hilite target outside vertex pool')
                yield part_index, hilite_index, cel_index, vertex


def discrete_actions(xar, part_count):
    """Reject interpolation and topology beyond the audited retail bank."""
    if xar['code'] != 2 or len(xar['sets']) != 1 or xar['static_count'] != 1:
        raise ValueError('unsupported frog transform encoding/model-set topology')
    models, actions = xar['sets'][0]
    if len(models) != 1 or models[0][:3] != (0, part_count, 1):
        raise ValueError('frog model/part mapping changed')
    if len(actions) != 34:
        raise ValueError('frog action census changed')
    for action in actions:
        if not action['valid'] or action['flags'] != 1 or action['parts'] != part_count:
            raise ValueError('unsupported interpolated/invalid frog action or part count')
    return actions


def bounds(points):
    """Return integer XYZ bounds for a nonempty sequence of points."""
    return [[min(p[k] for p in points), max(p[k] for p in points)] for k in range(3)]


def model_reach(raw, mesh_raw, label):
    """Decode one animation bank with one player mesh into text facts only."""
    warnings = []
    bank = mof.parse_model(raw, label, None, warnings)
    mesh = bank if mesh_raw is None else mof.parse_model(mesh_raw, label, None, warnings)
    if (warnings or bank['kind'] != 'animated' or bank['incomplete'] or
            mesh['incomplete'] or len(mesh['statics']) != 1 or
            (mesh_raw is not None and mesh['kind'] != 'static')):
        raise ValueError('unsupported frog bank/mesh or decoder warnings')
    static = mesh['statics'][0]
    probes = list(all_hilites(static))
    if not probes:
        raise ValueError('frog model has no collision hilites')
    xar = animation.parse_xar(raw)
    actions = discrete_actions(xar, len(static['parts']))
    summaries, envelope = [], []
    for action_index, action in enumerate(actions):
        points, yaw_points = [], []
        minimum = None
        for frame in range(action['frames']):
            for part, hilite, partcel, vertex in probes:
                matrix = animation.sampled_matrix(xar, action, frame, part)
                # flags==1 has already been enforced: sampled_matrix only
                # selects the exact decoded integer transform in this branch.
                envelope.append(affine_probe_envelope(matrix, vertex))
                points.append(transformed_probe(matrix, vertex, ROOTS[0][1]))
                for direction, root in ROOTS:
                    point = transformed_probe(matrix, vertex, root)
                    yaw_points.append(point)
                    witness = dict(frame=frame, part=part, hilite=hilite,
                                   partcel=partcel, root=direction, offset=point)
                    if minimum is None or point[2] < minimum['offset'][2]:
                        minimum = witness
        summaries.append(dict(action=action_index, frames=action['frames'],
                              local_xyz=bounds(points), cardinal_xyz=bounds(yaw_points),
                              minimum_cardinal_z_pose=minimum))
    return dict(label=label, animation_sha256=hashlib.sha256(raw).hexdigest(),
                mesh_sha256=hashlib.sha256(raw if mesh_raw is None else mesh_raw).hexdigest(),
                parts=len(static['parts']), hilites=len(probes),
                collision_parts=sorted({p[0] for p in probes}),
                authored_frames=sum(a['frames'] for a in actions),
                actions=summaries,
                arbitrary_signed16_root_offset=[min(v[0] for v in envelope),
                                                 max(v[1] for v in envelope)])


def traffic_hilite_admission(context, geometry):
    """Consume verify_org1_admission context/traffic_geometry; never admit a route.

    Unsupported inputs raise ValueError.  A conservative overlap returns
    blocked, with per-action facts and obligations.  The origin rectangle is
    half-open, hence integer maxima are 511 and 479.  World short narrowing
    is accounted for after adding each root origin.
    """
    if geometry['candidate_x'] != list(CANDIDATE_X) or geometry['candidate_z'] != list(CANDIDATE_Z):
        raise ValueError('unsupported ORG1 candidate rectangle')
    names = {}
    for entry in context['entries']:
        name = mof.file_name(context['entries'], entry['index'])
        if re.fullmatch(r'GEN_FROG(?:[234])?(?:_WIN95)?\.(?:XAR|XMR)', name):
            if name in names:
                raise ValueError('duplicate frog resource name')
            names[name] = entry['index']
    expected = {f'GEN_FROG{player}{suffix}.{extension}'
                for suffix in ('', '_WIN95')
                for player, extension in (('', 'XAR'), ('2', 'XMR'), ('3', 'XMR'), ('4', 'XMR'))}
    if set(names) != expected:
        raise ValueError('retail high-poly frog resource census changed')
    def resource(name):
        return platform.resource(context['files'], context['entries'], context['mwd'], names[name])
    models = []
    for suffix in ('', '_WIN95'):
        bank_name = f'GEN_FROG{suffix}.XAR'
        raw = resource(bank_name)
        for player in ('', '2', '3', '4'):
            mesh_name = f'GEN_FROG{player}{suffix}.XMR' if player else bank_name
            facts = model_reach(raw, resource(mesh_name) if player else None, mesh_name)
            facts.update(animation_resource_id=names[bank_name], mesh_resource_id=names[mesh_name])
            models.append(facts)
    offset = [min(m['arbitrary_signed16_root_offset'][0] for m in models),
              max(m['arbitrary_signed16_root_offset'][1] for m in models)]
    world = {axis: list(short_interval((candidate[0] + offset[0], candidate[1] - 1 + offset[1])))
             for axis, candidate in (('x', CANDIDATE_X), ('z', CANDIDATE_Z))}
    traffic = geometry['entities']
    if len(traffic) != 24 or sorted(e['entity_index'] for e in traffic) != list(range(24, 48)):
        raise ValueError('traffic geometry census changed')
    for entity in traffic:
        low, high = entity['primitive_point_z']
        if not isinstance(low, int) or not isinstance(high, int) or low > high or high >= CANDIDATE_Z[0]:
            raise ValueError('traffic geometry no longer establishes the audited southern separation')
    overlaps = [e['entity_index'] for e in traffic
                if e['primitive_point_z'][1] >= world['z'][0]]
    # Even a disjoint enclosure here still requires proving that stored LW
    # transforms have this root-origin range at every collision scan.  No
    # route, update-phase or low-poly selection contract is supplied here.
    reasons = ['No route/update-phase contract proves that stored per-part LW origins '
               'remain inside the candidate at every collision scan.',
               'The high-poly selection prerequisite (single player) is not admitted by this diagnostic.']
    if overlaps:
        reasons.append('The complete signed16-root enclosure overlaps traffic Z intervals; '
                       'narrowing reachable actions/root transforms is required.')
    return dict(status='blocked', traffic_collision_exclusion_proved=False, route_admitted=False,
                candidate_x=list(CANDIDATE_X), candidate_z=list(CANDIDATE_Z),
                models=models, arbitrary_signed16_root_offset=offset,
                probe_world_short_bounds=world, unseparated_traffic=overlaps,
                reasons=reasons,
                source_evidence=['COLLIDE.H COLL_A_FLAGS: animated owner, all parts, hilites',
                                 'MR_COLL.C MRCollisionCheck: every part/hilite, stored part LW transform, short world point',
                                 'MR_COLL.C MRCheckCollPrimWithWorldPoint: strict abs(local_axis) < half_length',
                                 'FROG.C CreateFrog: stored LW transforms, imported THROAT transform',
                                 'MR_ANIM.C MRAnimEnvUpdateModelLWTransforms: root times part matrix and translation',
                                 'mr_stub_math.c ApplyMatrixSV/mat3_multiply: arithmetic shift and short stores'],
                limitations=['Authored/cardinal pose extrema are not route reachability or 3D collision witnesses.',
                             'Integer arithmetic follows the frozen stored-LW frame path; no new linked-C animated pose parity was executed.',
                             'All signed16 roots are an enclosure, not a claim that every matrix is reachable.',
                             'No low-poly/multiplayer, integrated timing, traffic callback, route or runtime parity is certified.',
                             'Traffic geometry input remains a separate dependency; its source-width proof must extend to expanded probes.'])
