#!/usr/bin/env python3
"""Independent level-select stack layout and motion facts from the frozen C.

Layout transcribes SelectLevelInit, SelectCreateScene, SelectCreateMOF,
SelectLevelStartup's gold-frog points and SelectEnableSpinMOF over the
committed retail level-select rows. Motion replays SelectLevelUpdate,
SelectUpdateLevelSlide, SelectUpdateGlowyColours, SelectUpdate_MODE_SELECTING,
SelectFindTarget, SelectUpdate_MODE_SHOW_LEVEL_INFO, SelectUpdateInterpolation
and the fade arms for scripted inputs. See tests/golden/specs/frontend.md.
"""
import argparse
import difflib
import json
import os
from pathlib import Path
import re
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.golden import make_golden_frontend as frontend
from tools.golden import make_golden_paths as paths

ROOT = frontend.ROOT
GOLDEN = frontend.GOLDEN
LAYOUT_JSON = GOLDEN / 'synthetic' / 'frontend_stack_layout.json'
MOTION_JSON = GOLDEN / 'synthetic' / 'frontend_stack_motion.json'

BOX_X, BOX_Z = 0xf0, 0xf0
STACK = (-0xa00, 0, -0xa00)
INIT_CAMERA = (-0x1000, -0x1800, -0x1800)
ADJ_CAMERA = (0x700, 0x900, 0x700)
Y_AXIS = (0, 0x1000, 0)
PERSPECTIVE = 1000
DISPLAY = (640, 480)
SLIDE_INC = 0x40
SLIDE_DIST = (-BOX_Z) << 1
GOING_UP, GOING_DOWN, STATIONARY, STOPPING = 1, 2, 4, 8
MAX_VEL, ACC = 56, 4
SPIN_OUT, SPIN_IN, SPIN_HOLD = 1, 2, 4
SPIN_TIME = 10
SPIN_TARGET = (295, -181, 201)
SPIN_ROLL_ANGLE = 0x40
STATUS_START_X = DISPLAY[0] + 32
STATUS_END_X, STATUS_WIDTH = 400, 160
LEVEL_TITLE_Y, SCORE_LINE_Y, PROMPT_Y, TITLE_Y = 300, (320, 336, 352), 400, 24
SPRITE_DIM = 0x60
GLOWY_MIN, GLOWY_MAX, GLOWY_SPEED, DARK, LIGHT = 0x60, 0xa0, 16, 0x40, 0x80
FADE_TICKS = 0x20
LEVEL_TABLE = [4, 7, 2, 8, 0, 0, 6, 5, 1, 3]
AMBIENT = 0x202020
PARALLELS = [(-0x200, 0x606060), (0x200, 0x404040), (0, 0x303030)]
BG_TILES, BG_SPEED, BG_COLOUR = (8, 6), 24, 0x202020

VERTEX_SIGNS = [(-1, -1, -1), (1, -1, -1), (-1, 1, -1), (1, 1, -1),
                (-1, -1, 1), (1, -1, 1), (-1, 1, 1), (1, 1, 1)]
FACES = [((0, 1, 3, 2), (0, 0, 4096)), ((4, 0, 2, 6), (4096, 0, 0)), ((5, 4, 6, 7), (0, 0, -4096)),
         ((1, 5, 7, 3), (-4096, 0, 0)), ((4, 5, 1, 0), (0, 4096, 0)), ((6, 2, 3, 7), (0, -4096, 0))]
SPIN_IMAGE_CORNERS = [2, 0, 3, 1]
MODES = ['SELECTING', 'SHOW_LEVEL_INFO', 'START_FADE', 'UPDATE_FADE']
SPIN_NAMES = {SPIN_OUT: 'OUT', SPIN_IN: 'IN', SPIN_HOLD: 'HOLD'}


def s16(value):
    return paths.signed(value, 16)


def cdiv(a, b):
    """C integer division, truncating toward zero."""
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def rsin(angle):
    return paths.trig(angle)[1]


def rcos(angle):
    return paths.trig(angle)[0]


def outer12(a, b):
    """MROuterProduct12 with arithmetic shifts."""
    return [paths.signed(a[1] * b[2] - a[2] * b[1]) >> 12, paths.signed(a[2] * b[0] - a[0] * b[2]) >> 12,
            paths.signed(a[0] * b[1] - a[1] * b[0]) >> 12]


def apply(matrix, vector):
    """MRApplyMatrixVEC/SVEC: (row . vector) >> 12."""
    return [paths.signed(sum(matrix[r][k] * vector[k] for k in range(3))) >> 12 for r in range(3)]


def column(matrix, c):
    return [matrix[r][c] for r in range(3)]


def camera():
    """SelectCreateScene: MRPointMatrixAtVector at the stack origin, then the translation adjust."""
    position = [STACK[i] + INIT_CAMERA[i] for i in range(3)]
    z = paths.normalised([STACK[i] - position[i] for i in range(3)])
    nx = paths.normalised(outer12(Y_AXIS, z))
    ny = outer12(z, nx)
    matrix = [[s16(nx[r]), s16(ny[r]), s16(z[r])] for r in range(3)]
    translation = [position[i] + ADJ_CAMERA[i] for i in range(3)]
    return matrix, translation


CAMERA_MATRIX, CAMERA_T = camera()
CAMERA_Y_OFFSET = CAMERA_T[1]


def spin_vectors():
    """SelectEnableSpinMOF's destination Y and roll vectors (camera-only, level independent)."""
    cos, sin = rcos(SPIN_ROLL_ANGLE), rsin(SPIN_ROLL_ANGLE)
    rot_y = [[cos, 0, sin], [0, 0x1000, 0], [-sin, 0, cos]]
    dest_y = [s16(v) for v in apply(rot_y, [-v for v in column(CAMERA_MATRIX, 2)])]
    return dest_y, column(CAMERA_MATRIX, 1)


SPIN_DEST_Y, SPIN_DEST_ROLL = spin_vectors()


def lay_out(rows):
    """SelectLevelInit: tile edge to edge in list order, then shift so the last row is at y 0."""
    sizes = [BOX_X // r['levels_in_world'] for r in rows]
    positions, y = [], 0
    for i, size in enumerate(sizes):
        positions.append(y)
        y += size
        if i + 1 < len(sizes):
            y += sizes[i + 1]
    last = positions[-1]
    return sizes, [p - last for p in positions]


def vertices(size, position, current_z=0):
    """SelectCreateMOF with SelectUpdateLevelZ's z offset."""
    return [[sx * BOX_X, sy * size + position, sz * BOX_Z + current_z] for sx, sy, sz in VERTEX_SIGNS]


def spin_endpoints(size, position):
    """Start and end of the spin for a fully extended level with the camera stationary on it."""
    start = [STACK[0], position, STACK[2] + SLIDE_DIST]
    camera_t = [CAMERA_T[0], position + CAMERA_Y_OFFSET, CAMERA_T[2]]
    offset = apply(CAMERA_MATRIX, [SPIN_TARGET[0], SPIN_TARGET[1], SPIN_TARGET[2] + size])
    end = [s16(camera_t[i] + CAMERA_MATRIX[i][2] + offset[i]) for i in range(3)]
    return start, end


def colour(value):
    return [(value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff]


def gold_frog_slots(rows, sizes, positions):
    """SelectLevelStartup's Sel_golden_frog_points, grouped into the quad each slot draws."""
    firsts = [i for i, r in enumerate(rows) if i == 0 or r['world'] != rows[i - 1]['world']]
    points = []
    for i in firsts:
        verts = vertices(sizes[i], positions[i])
        points += [verts[4], verts[0]]
    verts = vertices(sizes[-1], positions[-1])
    points += [verts[6], verts[2]]
    points = [[p[0] + STACK[0], p[1], p[2] + STACK[2]] for p in points]
    slots = []
    for slot, i in enumerate(firsts):
        slots.append({'slot': slot, 'world': rows[i]['world'], 'theme': rows[i]['theme'],
                      'corners': points[2 * slot:2 * slot + 4]})
    return slots


def background():
    """SelectLevelCreateBG/UpdateBG sizes and per-counter offsets (high-score view stack)."""
    xlen = (((DISPLAY[0] // 384) + 1) * 384) // BG_TILES[0]
    ylen = (((DISPLAY[1] // 288) + 1) * 288) // BG_TILES[1]
    counters = list(range(1, BG_SPEED)) + [0]
    return {'tiles': [BG_TILES[0] + 1, BG_TILES[1] + 1], 'tile_size': [xlen, ylen], 'colour': colour(BG_COLOUR),
            'texture_pairs': [['im_jun_col', 'im_des_col'], ['im_cav_col', 'im_vol_col'],
                              ['im_sky_col', 'im_org_col'], ['im_for_col', 'im_sub_col']],
            'counter_period': BG_SPEED, 'counter_sequence': counters,
            'offset_left_or_up': [[(c * xlen) // BG_SPEED, (c * ylen) // BG_SPEED] for c in counters],
            'offset_right_or_down': [[xlen - (c * xlen) // BG_SPEED, ylen - (c * ylen) // BG_SPEED]
                                     for c in counters]}


def layout_document(stacks):
    rows = stacks['arcade']
    sizes, positions = lay_out(rows)
    out_rows = []
    for i, r in enumerate(rows):
        start, end = spin_endpoints(sizes[i], positions[i])
        out_rows.append({'position': i, 'level': r['level'], 'world': r['world'], 'theme': r['theme'],
                         'local_level': r['local'], 'levels_in_world': r['levels_in_world'],
                         'y_size': sizes[i], 'y_position': positions[i],
                         'camera_target_y': positions[i] + CAMERA_Y_OFFSET,
                         'slice_v_index': r['local'], 'slice_divisions': r['levels_in_world'],
                         'vertices': vertices(sizes[i], positions[i]),
                         'spin_start': start, 'spin_end': end})
    faces = []
    for index, (mof, normal) in enumerate(FACES):
        faces.append({'face': index, 'mof_vertices': list(mof),
                      'gpu_vertices': [mof[0], mof[1], mof[3], mof[2]], 'normal': list(normal),
                      'uv': 'world_slice' if index < 4 else 'world_full'})
    themes = [{'theme': loop + 1, 'bit': 1 << (loop + 1), 'slot': LEVEL_TABLE[loop]} for loop in range(10)]
    return {
        'constants': {
            'box_half_x': BOX_X, 'box_half_z': BOX_Z, 'stack_origin': list(STACK),
            'camera_init_offset': list(INIT_CAMERA), 'camera_adjust': list(ADJ_CAMERA),
            'camera_matrix': CAMERA_MATRIX, 'camera_translation': CAMERA_T,
            'camera_y_offset': CAMERA_Y_OFFSET, 'perspective': PERSPECTIVE, 'display': list(DISPLAY),
            'slide_inc': SLIDE_INC, 'slide_dist': SLIDE_DIST, 'camera_acc': ACC, 'camera_max_vel': MAX_VEL,
            'spin_time': SPIN_TIME, 'spin_target_offset': list(SPIN_TARGET), 'spin_dest_vec_y': SPIN_DEST_Y,
            'spin_dest_vec_roll': SPIN_DEST_ROLL, 'spin_start_vec_y': [0, 4096, 0],
            'spin_start_vec_roll': [0, 0, 4096], 'status_start_x': STATUS_START_X,
            'status_end_x': STATUS_END_X, 'status_width': STATUS_WIDTH, 'level_title_y': LEVEL_TITLE_Y,
            'score_line_y': list(SCORE_LINE_Y), 'prompt_y': PROMPT_Y, 'title_y': TITLE_Y,
            'sprite_dim_colour': SPRITE_DIM, 'glow_min': GLOWY_MIN, 'glow_max': GLOWY_MAX,
            'glow_speed': GLOWY_SPEED, 'dark_colour': DARK, 'light_colour': LIGHT, 'fade_ticks': FADE_TICKS},
        'lights': [{'type': 'ambient', 'colour': colour(AMBIENT)}] + [
            {'type': 'parallel', 'rotation_y': angle, 'colour': colour(value),
             'direction': [rsin(angle), 0, rcos(angle)]} for angle, value in PARALLELS],
        'vertex_signs': [list(v) for v in VERTEX_SIGNS],
        'faces': faces,
        'spin_image_face': {'face': 5, 'gpu_image_corners': SPIN_IMAGE_CORNERS, 'tint': LIGHT},
        'rows': out_rows,
        'gold_frogs': {'level_table': LEVEL_TABLE, 'themes': themes,
                       'slots': gold_frog_slots(rows, sizes, positions)},
        'high_score_background': background(),
    }


class Selector:
    """The level-select globals and per-tick update of the frozen C (arcade mode)."""

    def __init__(self, rows, start, first_time, name_width):
        self.rows = rows
        self.sizes, self.positions = lay_out(rows)
        self.z = [0] * len(rows)
        self.tint = [LIGHT if r['flags'] & frontend.COMPLETED else DARK for r in rows]
        self.mode = 0
        self.work = start
        self.glowy = start
        self.glow, self.glow_dir = GLOWY_MAX, -GLOWY_SPEED
        self.camera_y = self.positions[start] + CAMERA_Y_OFFSET
        self.frame_y = self.camera_y
        self.vel = self.acc = 0
        self.flag = STATIONARY
        self.target_y = self.camera_y
        self.first_time = first_time
        self.name_width = name_width
        self.spin = None
        self.status_x = STATUS_START_X
        self.title_x = STATUS_START_X
        self.fade = None
        self.count = 0
        self.done = False

    def slide(self):
        viewed = self.frame_y - CAMERA_Y_OFFSET
        self.glowy = self.work
        max_z = self.z[self.work]
        for i in range(len(self.rows)):
            if self.positions[i] - self.sizes[i] <= viewed <= self.positions[i] + self.sizes[i]:
                self.z[i] = max(self.z[i] - SLIDE_INC, SLIDE_DIST)
            else:
                self.z[i] = min(self.z[i] + SLIDE_INC, 0)
            if self.z[i] < max_z:
                self.glowy = i

    def glow_update(self):
        if self.flag != STATIONARY or self.mode == 3 or self.glow > GLOWY_MAX:
            self.glow_dir = -abs(self.glow_dir)
        elif self.glow < GLOWY_MIN:
            self.glow_dir = abs(self.glow_dir)
        if self.glow >= DARK or self.glow >= GLOWY_MIN:
            self.glow = (self.glow + self.glow_dir) & 0xff
        theme = self.rows[self.glowy]['theme']
        for i, r in enumerate(self.rows):
            flags = r['flags']
            if flags & frontend.SELECTABLE and not flags & frontend.COMPLETED and r['theme'] == theme:
                self.tint[i] = self.glow
            elif (flags & frontend.COMPLETED) | (not flags & frontend.ZONEACCESSIBLE):
                self.tint[i] = LIGHT
            else:
                self.tint[i] = DARK

    def find_target(self, step):
        i = self.work + step
        while 0 <= i < len(self.rows):
            if self.rows[i]['flags'] & frontend.SELECTABLE:
                self.work = i
                self.target_y = self.positions[i] + CAMERA_Y_OFFSET
                return True
            i += step
        return False

    def selecting(self, held, pressed, events):
        self.vel = max(-MAX_VEL, min(MAX_VEL, self.vel + self.acc))
        self.camera_y += self.vel
        reached = False
        if self.flag & GOING_DOWN:
            if self.frame_y <= self.target_y <= self.camera_y:
                reached, self.glow = True, DARK
        elif self.flag & GOING_UP:
            if self.frame_y >= self.target_y >= self.camera_y:
                reached, self.glow = True, DARK
        elif self.flag == STATIONARY:
            reached = True
        self.frame_y = self.camera_y
        if self.flag & STATIONARY:
            if 'down' in held:
                if self.find_target(1):
                    events.append('hop')
                    self.flag, self.acc, reached = GOING_DOWN, ACC, False
            elif 'up' in held:
                if self.find_target(-1):
                    events.append('hop')
                    self.flag, self.acc, reached = GOING_UP, -ACC, False
            elif 'go' in pressed:
                if self.z[self.work] == SLIDE_DIST:
                    events += ['hop', 'show_info']
                    self.mode = 1
                    self.enable_spin()
                    return
            elif self.first_time and 'back' in pressed:
                events.append('back')
                self.done = True
        for flag, key, step in ((GOING_DOWN, 'down', 1), (GOING_UP, 'up', -1)):
            if self.flag == flag:
                if key not in held:
                    self.flag |= STOPPING
                elif reached:
                    if self.find_target(step):
                        reached = False
                    else:
                        self.flag |= STOPPING
        if self.flag & STOPPING and reached:
            self.acc = self.vel = 0
            self.flag = STATIONARY
            self.camera_y = self.frame_y = self.target_y

    def enable_spin(self):
        start, end = spin_endpoints(self.sizes[self.work], self.positions[self.work])
        start[2] = STACK[2] + self.z[self.work]
        self.spin = {'mode': SPIN_OUT, 'time': 0, 'start': start, 'end': end, 'pos': list(start),
                     'vec_y': [0, 4096, 0], 'vec_roll': [0, 0, 4096],
                     'axes': [[4096, 0, 0], [0, 4096, 0], [0, 0, 4096]]}

    def interpolate(self):
        s, half = self.spin, SPIN_TIME >> 1
        if s['time'] < half:
            sin = -rsin(((half - s['time']) * 0x800) // SPIN_TIME)
        else:
            sin = rsin(((s['time'] - half) * 0x800) // SPIN_TIME)

        def lerp(a, b):
            return a + cdiv((sin + 0x1000) * (b - a), 0x2000)

        s['sin'] = sin
        s['pos'] = [lerp(a, b) for a, b in zip(s['start'], s['end'])]
        s['vec_y'] = [lerp(a, b) for a, b in zip([0, 4096, 0], SPIN_DEST_Y)]
        s['vec_roll'] = [lerp(a, b) for a, b in zip([0, 0, 4096], SPIN_DEST_ROLL)]
        self.status_x = lerp(STATUS_START_X, STATUS_END_X)

    def show_info(self, pressed, events):
        s = self.spin
        if s['mode'] in (SPIN_OUT, SPIN_IN):
            self.interpolate()
            if s['mode'] == SPIN_OUT:
                s['time'] += 1
                if s['time'] > SPIN_TIME:
                    s['time'], s['mode'] = SPIN_TIME, SPIN_HOLD
            else:
                s['time'] -= 1
                if s['time'] < 0:
                    self.mode = 0
                    events.append('hide_info')
            local_y = paths.normalised(s['vec_y'])
            local_x = paths.normalised(outer12(local_y, s['vec_roll']))
            local_z = outer12(local_x, local_y)
            s['axes'] = [[s16(v) for v in local_x], [s16(v) for v in local_y], [s16(v) for v in local_z]]
            self.title_x = self.status_x + (STATUS_WIDTH >> 1) - (self.name_width >> 1)
            if self.mode == 0:
                self.spin = None
        elif 'back' in pressed:
            events.append('hop')
            s['mode'] = SPIN_IN
        elif 'go' in pressed:
            events += ['croak', 'play']
            self.mode = 2
            self.count = 0
            self.first_time = False

    def fading(self, events):
        if self.mode == 2:
            self.fade = {'title_y': TITLE_Y, 'prompt_y': PROMPT_Y, 'name_x': self.title_x}
            self.count = 0
            self.mode = 3
        self.count += 1
        f = self.fade
        if self.count <= FADE_TICKS:
            f['screen'] = self.count * 8 - 1
            f['loading'] = self.count * 4
            f['title_y'] -= 8
            f['prompt_y'] += 8
            target = (DISPLAY[0] >> 1) - (self.name_width >> 1)
            f['name_x'] -= cdiv(f['name_x'] - target, 0x21 - self.count)
        else:
            f['screen'] = 0xff
            events.append('enter_game')
            self.done = True

    def step(self, held, pressed):
        events = []
        self.slide()
        if self.mode == 0:
            self.glow_update()
            self.selecting(held, pressed, events)
        elif self.mode == 1:
            self.glow_update()
            self.show_info(pressed, events)
        else:
            self.fading(events)
        return events

    def snapshot(self, tick, inputs, events):
        spin = None
        if self.spin is not None:
            s = self.spin
            spin = {'mode': SPIN_NAMES[s['mode']], 'time': s['time'], 'pos': s['pos'], 'vec_y': s['vec_y'],
                    'vec_roll': s['vec_roll'], 'axes': s['axes'], 'status_x': self.status_x,
                    'title_x': self.title_x}
        fade = None
        if self.fade is not None:
            fade = {'count': self.count, 'screen': self.fade.get('screen', 0),
                    'loading': self.fade.get('loading', 0), 'title_y': self.fade['title_y'],
                    'prompt_y': self.fade['prompt_y'], 'name_x': self.fade['name_x']}
        return {'tick': tick, 'input': inputs, 'mode': MODES[self.mode], 'camera_y': self.camera_y,
                'camera_vel': self.vel, 'camera_acc': self.acc, 'camera_flags': self.flag,
                'target_y': self.target_y, 'work_row': self.work, 'glowy_row': self.glowy, 'glow': self.glow,
                'glow_dir': self.glow_dir, 'current_z': list(self.z), 'tint': list(self.tint),
                'first_time': self.first_time, 'events': events, 'spin': spin, 'fade': fade}


def synthetic_rows(spec):
    rows = []
    for world, (theme, count, flags) in enumerate(spec):
        for local, f in enumerate(flags):
            rows.append({'world': world, 'theme': theme, 'local': local, 'levels_in_world': count, 'flags': f})
    return rows


C, S, Z = frontend.COMPLETED, frontend.SELECTABLE, frontend.ZONEACCESSIBLE
SMALL = [(5, 3, [C | S | Z, S | Z, Z]), (9, 2, [Z, 0]), (3, 1, [S | Z]), (8, 4, [S | Z, Z, S | Z, Z])]


def scenarios(stacks):
    fresh = frontend.Progress(stacks)
    retail_rows = [{'world': r['world'], 'theme': r['theme'], 'local': r['local'],
                    'levels_in_world': r['levels_in_world'], 'flags': p['flags'], 'level': r['level']}
                   for r, p in zip(stacks['arcade'], fresh.rows['arcade'])]
    small = synthetic_rows(SMALL)
    return [
        {'name': 'retail_fresh_chain_down_then_up',
         'description': 'Fresh retail stack from ORIGINAL1: settle, hold DOWN through every open level '
                        '(locked rows skipped) until no target remains, then tap UP once and let it stop.',
         'rows': retail_rows, 'start_row': 0, 'first_time': True, 'name_width': 128,
         'inputs': [[10, []], [40, ['down']], [10, []], [1, ['up']], [25, []]]},
        {'name': 'small_glow_cycle_and_tints',
         'description': 'Synthetic stack: completed, open, locked, inaccessible and other-theme open rows; '
                        'idle long enough for two glow cycles; BACK is ignored after the first play.',
         'rows': small, 'start_row': 1, 'first_time': False, 'name_width': 96,
         'inputs': [[30, []], [1, ['back']], [5, []]]},
        {'name': 'small_down_wins_and_release',
         'description': 'Hold DOWN and UP together (DOWN wins), release mid-leg (STOPPING then snap), re-press '
                        'during STOPPING (ignored), hold DOWN past the locked world to the last open row, '
                        'then hold UP back to the top.',
         'rows': small, 'start_row': 0, 'first_time': True, 'name_width': 96,
         'inputs': [[9, []], [4, ['down', 'up']], [1, []], [3, ['down']], [12, []],
                    [45, ['down']], [70, ['up']], [5, []]]},
        {'name': 'small_info_back_play_fade',
         'description': 'GO before the box is fully out (ignored), GO when out: spin out and hold; GO during '
                        'the spin (ignored); BACK spins in; GO again, GO on hold croaks and fades into the game.',
         'rows': small, 'start_row': 1, 'first_time': True, 'name_width': 96,
         'inputs': [[3, []], [1, ['go']], [4, []], [1, ['go']], [5, []], [1, ['go']], [8, []],
                    [1, ['back']], [14, []], [1, ['go']], [12, []], [1, ['go']], [40, []]]},
        {'name': 'small_back_first_time',
         'description': 'First visit: BACK while moving is ignored; BACK once stationary leaves for the main menu.',
         'rows': small, 'start_row': 0, 'first_time': True, 'name_width': 96,
         'inputs': [[2, ['down']], [1, ['down', 'back']], [20, []], [1, ['back']], [3, []]]},
    ]


def run(scenario):
    rows = scenario['rows']
    sel = Selector(rows, scenario['start_row'], scenario['first_time'], scenario['name_width'])
    trace = [sel.snapshot(0, [], [])]
    tick = 0
    for count, inputs in scenario['inputs']:
        for _ in range(count):
            if sel.done:
                break
            tick += 1
            held = [i for i in inputs if i in ('up', 'down')]
            pressed = [i for i in inputs if i in ('go', 'back')]
            events = sel.step(held, pressed)
            trace.append(sel.snapshot(tick, inputs, events))
    out = {k: scenario[k] for k in ('name', 'description', 'start_row', 'first_time', 'name_width', 'inputs')}
    out['rows'] = [{k: r[k] for k in ('world', 'theme', 'local', 'levels_in_world', 'flags')} for r in rows]
    out['y_size'], out['y_position'] = sel.sizes, sel.positions
    out['trace'] = trace
    return out


def motion_document(stacks):
    return {'tick_order': ['slide', 'glow (SELECTING and SHOW_LEVEL_INFO only)', 'mode update'],
            'scenarios': [run(s) for s in scenarios(stacks)]}


def flat(value):
    return not isinstance(value, (dict, list)) or (
        isinstance(value, list) and all(not isinstance(v, (dict, list)) or flat(v) for v in value))


def dump(value, indent=0):
    """JSON with scalar lists and leaf records on one line, everything else expanded."""
    pad, inner = ' ' * indent, ' ' * (indent + 1)
    if flat(value) or (isinstance(value, dict) and 'tick' in value):
        return json.dumps(value, separators=(', ', ': '))
    if isinstance(value, dict):
        items = [inner + json.dumps(k) + ': ' + dump(v, indent + 1) for k, v in value.items()]
        return '{\n' + ',\n'.join(items) + '\n' + pad + '}'
    return '[\n' + ',\n'.join(inner + dump(v, indent + 1) for v in value) + '\n' + pad + ']'


def read_rows():
    """The arcade rows of exe_level_select.tsv with local level and level count."""
    stacks = frontend.read_stacks(frontend.LEVEL_SELECT_TSV)
    extra = [row for row in frontend.read_tsv(frontend.LEVEL_SELECT_TSV) if row[0] == 'arcade' and row[2] != '-1']
    for row, raw in zip(stacks['arcade'], extra):
        row['local'], row['levels_in_world'] = int(raw[6]), int(raw[7])
    return stacks


def define(text, name):
    match = re.search(r'#define\s+%s\s+(.+)' % name, text)
    return re.sub(r'\s+', '', match.group(1).split('//')[0]) if match else None


def squash(text):
    return re.sub(r'\s+', '', text)


def check_c(c_root):
    """Compare the transcriptions above with the frozen C; returns problems."""
    problems = []
    h = (c_root / 'SELECT.H').read_text(encoding='latin-1')
    c = (c_root / 'SELECT.C').read_text(encoding='latin-1')
    sq = squash(c)
    expected_defines = {
        'SEL_STACK_X_POS': '-0xa00', 'SEL_STACK_Z_POS': '-0xa00', 'SEL_INIT_CAMERA_X': '(-0x1000)',
        'SEL_INIT_CAMERA_Y': '(-0x1800)', 'SEL_INIT_CAMERA_Z': '(-0x1800)', 'SEL_ADJ_CAMERA_X': '(0x700)',
        'SEL_ADJ_CAMERA_Y': '(0x900)', 'SEL_ADJ_CAMERA_Z': '(0x700)', 'SEL_BOX_X_SIZE': '(0xf0)',
        'SEL_BOX_Z_SIZE': '(0xf0)', 'SEL_LEVEL_SLIDE_INC': '(0x40)',
        'SEL_LEVEL_SLIDE_DIST': '((-SEL_BOX_Z_SIZE)<<1)', 'SEL_CAMERA_GOING_UP': '(1<<0)',
        'SEL_CAMERA_GOING_DOWN': '(1<<1)', 'SEL_CAMERA_STATIONARY': '(1<<2)', 'SEL_CAMERA_STOPPING': '(1<<3)',
        'SEL_CAMERA_MAX_VEL': '(56)', 'SEL_CAMERA_ACC': '(4)', 'SEL_SPIN_OUT': '(1<<0)', 'SEL_SPIN_IN': '(1<<1)',
        'SEL_SPIN_HOLD': '(1<<2)', 'SEL_SPIN_TIME': '(10)', 'SELECT_BG_ONSCREEN_TILES_X': '8',
        'SELECT_BG_ONSCREEN_TILES_Y': '6', 'SELECT_BG_TILE_MOVE_SPEED': '24'}
    for name, value in expected_defines.items():
        if define(h, name) != value:
            problems.append('SELECT.H %s is %s, transcribed %s' % (name, define(h, name), value))
    pc = h[h.index('#else', h.index('SEL_STATUS_END_X_POS')):]
    for name, value in (('SEL_STATUS_END_X_POS', '(400)'), ('SEL_STATUS_WIDTH', '(160)'),
                        ('SEL_LEVEL_TITLE_Y', '(300)'), ('SEL_LEVEL_SCORE_LINE_0_Y', '(320+(16*0))'),
                        ('SEL_PROMPT_SPRITE_Y', '(400)')):
        if define(pc, name) != value:
            problems.append('SELECT.H PC %s differs' % name)
    gamesys = (c_root / 'gamesys.H').read_text(encoding='latin-1')
    if not re.search(r'#else\s+#define\s+SYSTEM_DISPLAY_WIDTH\s+640\s+#define\s+SYSTEM_DISPLAY_HEIGHT\s+480', gamesys):
        problems.append('gamesys.H PC display size differs')
    for name, value in (('SEL_GLOWY_MIN', '0x60'), ('SEL_GLOWY_MAX', '0xa0'), ('SEL_GLOWY_SPEED', '16'),
                        ('SEL_DARK_COLOUR', '0x40'), ('SEL_LIGHT_COLOUR', '0x80')):
        if define(c, name) != value:
            problems.append('SELECT.C %s differs' % name)
    table = re.search(r'Level_table\[10\]=\s*\{([^}]*)\}', c)
    if not table or [int(v) for v in re.findall(r'\d+', table.group(1))] != LEVEL_TABLE:
        problems.append('SELECT.C Level_table differs')
    mof = c[c.index('MR_VOID\tSelectCreateMOF('):]
    mof = mof[:mof.index('SelectUpdate_MODE_SELECTING')]
    verts = re.findall(r'sm_verts\[(\d)\],\s*(-?)SEL_BOX_X_SIZE,\s*\(\s*(-?)y_size\)\+y_position,\s*(-?)SEL_BOX_Z_SIZE',
                       mof)
    signs = [tuple(-1 if s == '-' else 1 for s in v[1:]) for v in verts]
    if [int(v[0]) for v in verts] != list(range(8)) or signs != VERTEX_SIGNS:
        problems.append('SelectCreateMOF vertex signs differ')
    norms = [tuple(int(n) for n in m) for m in re.findall(r'sm_norms\[\d\],\s*(-?\d+),\s*(-?\d+),\s*(-?\d+)\)', mof)]
    prims = re.findall(r'sm_prims\[(\d)\]\.mp_p(\d) = (\d);', mof)
    faces = [tuple(int(v) for i, p, v in prims if int(i) == face) for face in range(6)]
    if norms != [f[1] for f in FACES] or faces != [f[0] for f in FACES]:
        problems.append('SelectCreateMOF face tables differ')
    for snippet in (
            'level_ptr->li_y_size=(SEL_BOX_X_SIZE/level_ptr->li_levels_in_world);',
            'level_y_pos+=(SEL_BOX_X_SIZE/next_level_ptr->li_levels_in_world);',
            'level_y_pos=(level_ptr-1)->li_y_position;', 'level_ptr->li_y_position-=level_y_pos;',
            'Option_viewport_ptr->vp_perspective=1000;', 'Sel_glowy_col.r=SEL_GLOWY_MAX;',
            'Sel_glowy_dir=-SEL_GLOWY_SPEED;', 'Sel_status_start_x=Game_display_width+32;',
            'MRPointMatrixAtVector(&Sel_camera_frame->fr_matrix,&vec_top,&Game_y_axis_pos);',
            'Sel_camera_y_offset=Sel_camera_frame->fr_matrix.t[1];',
            'MRCreateLight(MR_LIGHT_TYPE_AMBIENT,0x202020,',
            'MR_SET_SVEC(&svec,0,-0x200,0);', 'MRCreateLight(MR_LIGHT_TYPE_PARALLEL,0x606060,',
            'MR_SET_SVEC(&svec,0,0x200,0);', 'MRCreateLight(MR_LIGHT_TYPE_PARALLEL,0x404040,',
            'MR_SET_SVEC(&svec,0,0,0);', 'MRCreateLight(MR_LIGHT_TYPE_PARALLEL,0x303030,',
            'h=((tex_ptr->te_h)/level_ptr->li_levels_in_world);',
            'v=tex_ptr->te_v0+(level_ptr->li_level_within_world*h);',
            'if(level_ptr->li_flags&SEL_LF_ZONEACCESSIBLE)tex_ptr=level_ptr->li_world_image_selectable;'
            'elsetex_ptr=level_ptr->li_world_image_not_tried;',
            'if(Gold_frogs&(1<<(loop_counter+1)))', 'level_number=Level_table[loop_counter];',
            'Sel_golden_frog_points[0+(loop_counter*2)].vx=level_mof_ptr->sm_verts[4].vx+SEL_STACK_X_POS;',
            'Sel_golden_frog_points[1+(loop_counter*2)].vx=level_mof_ptr->sm_verts[0].vx+SEL_STACK_X_POS;',
            'Sel_golden_frog_points[0+(loop_counter*2)].vx=level_mof_ptr->sm_verts[6].vx+SEL_STACK_X_POS;',
            'Sel_golden_frog_points[1+(loop_counter*2)].vx=level_mof_ptr->sm_verts[2].vx+SEL_STACK_X_POS;',
            'HSUpdateWater();SelectUpdateLevelSlide();switch(Sel_game_mode)',
            'if(++Sel_count<=0x20)', 'poly_f4->r0=(Sel_count*8)-1;',
            'Sel_loading_sprite_ptr->sp_core.sc_base_colour.r=Sel_count*4;',
            'Sel_title->sp_pos.y-=8;', 'Sel_user_prompt->sp_pos.y+=8;',
            'Sel_level_title->sp_pos.x-=((Sel_level_title->sp_pos.x-x)/(0x21-Sel_count));',
            'Sel_count=0;Sel_game_mode=SEL_GAME_MODE_UPDATE_FADE;', 'Option_page_request=OPTIONS_PAGE_GAME;',
            'if((Sel_camera_flag!=SEL_CAMERA_STATIONARY)||(Sel_game_mode==SEL_GAME_MODE_UPDATE_FADE)||'
            '(Sel_glowy_col.r>SEL_GLOWY_MAX))Sel_glowy_dir=-abs(Sel_glowy_dir);'
            'elseif(Sel_glowy_col.r<SEL_GLOWY_MIN)Sel_glowy_dir=+abs(Sel_glowy_dir);',
            'if((Sel_glowy_col.r>=SEL_DARK_COLOUR)||(Sel_glowy_col.r>=SEL_GLOWY_MIN))',
            'elseif(level_ptr->li_flags&SEL_LF_COMPLETED|!(level_ptr->li_flags&SEL_LF_ZONEACCESSIBLE))',
            '&&(Sel_glowy_level_ptr->li_theme_no==level_ptr->li_theme_no))',
            'if(level_ptr->li_flags&SEL_LF_COMPLETED){mof_ptr->sm_prims[loop].mp_cvec.r=SEL_LIGHT_COLOUR;',
            'Sel_camera_vel+=Sel_camera_acc;', 'Sel_camera_y+=Sel_camera_vel;',
            'if((Sel_camera_frame->fr_matrix.t[1]<=Sel_target_y)&&(Sel_camera_y>=Sel_target_y))'
            '{reached_target=TRUE;Sel_glowy_col.r=SEL_DARK_COLOUR;',
            'if((Sel_camera_frame->fr_matrix.t[1]>=Sel_target_y)&&(Sel_camera_y<=Sel_target_y))'
            '{reached_target=TRUE;Sel_glowy_col.r=SEL_DARK_COLOUR;',
            'if(Sel_camera_flag==SEL_CAMERA_STATIONARY)reached_target=TRUE;',
            'if(MR_CHECK_PAD_HELD(Port_id,MRIP_DOWN)){//Resettimeout//Sel_time_out=0;'
            'if(SelectFindTarget(SEL_FIND_NEXT)==TRUE)',
            'if(level_ptr->li_current_z==SEL_LEVEL_SLIDE_DIST)',
            'if((Sel_mode==SEL_MODE_RACE)||(Sel_first_time==TRUE)){if(MR_CHECK_PAD_PRESSED(Port_id,FRR_TRIANGLE))',
            'if((Sel_camera_flag&SEL_CAMERA_STOPPING)&&(reached_target==TRUE)){Sel_camera_acc=0;Sel_camera_vel=0;'
            'Sel_camera_flag=SEL_CAMERA_STATIONARY;Sel_camera_y=Sel_target_y;',
            'viewed_y=Sel_camera_frame->fr_matrix.t[1]-Sel_camera_y_offset;',
            'Sel_glowy_level_ptr=Sel_work_level_ptr;max_z=Sel_glowy_level_ptr->li_current_z;',
            'if((viewed_y>=level_ptr->li_y_position-level_ptr->li_y_size)&&'
            '(viewed_y<=level_ptr->li_y_position+level_ptr->li_y_size))',
            'if(level_ptr->li_current_z<max_z)Sel_glowy_level_ptr=level_ptr;',
            'Sel_target_y=level_ptr->li_y_position+Sel_camera_y_offset;',
            'MR_SET_VEC(&target_offset,295,-181,201);target_offset.vz+=(level_ptr->li_y_size);',
            'MRApplyMatrixVEC(&Sel_camera_frame->fr_matrix,&target_offset,&target_offset);',
            'Sel_spin_level.li_frame->fr_matrix.t[2]=SEL_STACK_Z_POS+level_ptr->li_current_z;',
            'Sel_end_pos.vx=Sel_camera_frame->fr_matrix.t[0]+(Sel_camera_frame->fr_matrix.m[0][2])+target_offset.vx;',
            'Sel_dest_vec_y.vx=-(Sel_camera_frame->fr_matrix.m[0][2]);', 'cos=rcos(0x40);',
            'Sel_dest_vec_roll.vx=Sel_camera_frame->fr_matrix.m[0][1];',
            'dest_ptr->u0=level_image_ptr->te_u2;', 'dest_ptr->u1=level_image_ptr->te_u0;',
            'dest_ptr->u2=level_image_ptr->te_u3;', 'dest_ptr->u3=level_image_ptr->te_u1;',
            'sin=-(rsin((((Sel_spin_max_time>>1)-Sel_spin_time)*0x800)/Sel_spin_max_time));',
            'sin=rsin(((Sel_spin_time-(Sel_spin_max_time>>1))*0x800)/Sel_spin_max_time);',
            'Sel_temp_pos.vx=Sel_start_pos.vx+((sin+0x1000)*(Sel_end_pos.vx-Sel_start_pos.vx))/0x2000;',
            'Sel_status_temp_x=Sel_status_start_x+((sin+0x1000)*(Sel_status_end_x-Sel_status_start_x))/0x2000;',
            'MRNormaliseVEC(&Sel_temp_vec_y,&local_y);MROuterProduct12(&local_y,&Sel_temp_vec_roll,&local_x);'
            'MRNormaliseVEC(&local_x,&local_x);MROuterProduct12(&local_x,&local_y,&local_z);',
            'Sel_level_title->sp_pos.x=Sel_status_temp_x+(SEL_STATUS_WIDTH>>1)-(Sel_level_title->sp_image_buf[0]->te_w>>1);',
            'Sel_spin_time++;if(Sel_spin_time>Sel_spin_max_time){',
            'Sel_spin_time--;if(Sel_spin_time<0){',
            'elseif(MR_CHECK_PAD_PRESSED(Port_id,FRR_TRIANGLE)){//Resettimeout//Sel_time_out=0;',
            'MRSNDPlaySound(SFX_GEN_FROG_CROAK,NULL,0,0);',
            'Sel_game_mode=SEL_GAME_MODE_START_FADE;Sel_count=0;Sel_first_time=FALSE;',
            'Select_bg_xlen=(((Game_display_width/384)+1)*384)/Select_bg_xnum;',
            'Select_bg_ylen=(((Game_display_height/288)+1)*288)/Select_bg_ynum;',
            'x=Select_bg_xlen-((Select_bg_counter*Select_bg_xlen)/SELECT_BG_TILE_MOVE_SPEED);'):
        if squash(snippet) not in sq:
            problems.append('SELECT.C no longer contains: %s' % snippet[:90])
    frame = (c_root / 'API.SRC' / 'MR_MATH.C').read_text(encoding='latin-1')
    if squash('MROuterProduct12(y,z,&nx);') not in squash(frame) or \
            squash('MROuterProduct12(z,&nx,&ny);') not in squash(frame):
        problems.append('MRGenerateMatrixFromZAxisAndZYPlane differs')
    if 'Game_y_axis_pos 	= {0,  0x1000, 0};' not in (c_root / 'gamesys.C').read_text(encoding='latin-1'):
        problems.append('gamesys.C Game_y_axis_pos differs')
    hsview = squash((c_root / 'HSView.c').read_text(encoding='latin-1'))
    if 'SelectLevelCreateBG();' not in hsview or 'SelectLevelCreateBG();' in sq:
        problems.append('the checker background is no longer HSView-only')
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--c-reference', type=Path, default=frontend.DEFAULT_C,
                        help='frozen C source folder (default: ../froggy/engine/vendor/frogger-psx-src/source)')
    parser.add_argument('--check', action='store_true', help='compare with the committed files instead of writing')
    args = parser.parse_args()
    stacks = read_rows()
    if len(stacks['arcade']) != 33:
        sys.exit('unexpected arcade row count %d' % len(stacks['arcade']))
    if args.c_reference.is_dir():
        problems = check_c(args.c_reference)
        for problem in problems:
            print('C cross-check: ' + problem)
        if problems:
            sys.exit(1)
        print('C cross-check passed against %s' % args.c_reference)
    else:
        print('C source not found at %s; cross-checks skipped' % args.c_reference)
    outputs = {LAYOUT_JSON: dump(layout_document(stacks)) + '\n', MOTION_JSON: dump(motion_document(stacks)) + '\n'}
    failed = False
    for path, text in outputs.items():
        if args.check:
            old = path.read_text(encoding='utf-8') if path.exists() else ''
            if old != text:
                failed = True
                sys.stdout.writelines(difflib.unified_diff(old.splitlines(True), text.splitlines(True),
                                                           str(path), 'generated', n=0))
        else:
            path.write_text(text, encoding='utf-8')
            print('Wrote %s' % path.relative_to(ROOT))
    if args.check:
        print('Committed facts differ from the generator' if failed else 'Committed facts match the generator')
        sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
