#!/usr/bin/env python3
"""Independent options page model placement facts from the frozen C.

Transcribes OptionsStartup, OptionsUpdate and OptionsUpdateFrog (tempopt.c),
HSGetWaterSurfaceInfoFromXZ and HSProjectMatricesOntoWaterSurface (HSView.c),
OptionsSetupVolumeLogAnimatedPolys with High_score_log_animated_poly_indices,
the frog jump shadow offsets (FROG.C) and the options viewport lights
(options.c), with the retail PC extras of froggy KEY_FACTS KF-110 and the
measured retail extras table. Scripted input runs are replayed through the
independent options page model of make_golden_options.py over the port's
rows, and every model matrix, the frog, its action and shadow are recorded
per tick. See tests/golden/specs/frontend.md#options-page-models.
"""
import argparse
import difflib
from pathlib import Path
import os
import re
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_golden_frontend as frontend
import make_golden_options as options
import make_golden_paths as paths
import make_golden_stack as stack

ROOT = frontend.ROOT
MODELS_JSON = frontend.GOLDEN / 'synthetic' / 'frontend_options_models.json'

ONE = 0x1000
LILY_SCALE, LOG_SCALE, FROG_SCALE, EXTRA_SCALE = 0x1600, 0x1300, 0x1400, 0x1800
TITLE_SCALE = (0x1000, 0x1400, 0x1000)
VOLUME_TILT, SPIN_SHIFT = 0x400, 8
LILY_X, LOG_X = -0x380, 0
TOP_Z, PITCH = 0x2c0, 0x200
TITLE_X_BASE, TITLE_X_STEP = -0x200, 8
SPRITE_SCALE = 10 << 16
TITLE_RAISE, REFLECTION_OFFSET, REFLECTION_COLOUR = -0x40, 0x48, 0x40
REFLECTION_OT, SPLASH_OT = 0x10, -0x8
PROMPT_START = 76
LOG_POLY_INDICES = [56, 48, 40, 8, 16, 24, 32, 0]

WATER_NUM = (14, 16)
WATER_LEN = (0x240, 0x240)
AMP = (0x40, 0x50)
FREQ = (0x60, 0x80)
PERIOD = (0x2000, 0x2000)
SLOPE_STEP = 0x100

VENDORED_EXTRAS = [('OPT_MUSIC', 0x400, -0x280), ('OPT_SFX', 0x400, -0x400), ('OPT_STAT_BULLRUSH', -0x680, 0x520),
                   ('OPT_STAT_LILLY', 0x180, 0x680), ('OPT_STAT_LILLY', 0x580, 0x440),
                   ('OPT_STAT_LILLY', -0x600, 0x100), ('OPT_STAT_BULLRUSH', 0x40, -0x580)]
RETAIL_EXTRAS = VENDORED_EXTRAS[1:]
RETAIL_LOG_Z = -0x340
STATICS = RETAIL_EXTRAS[1:]
VOLUME_MODEL_OFFSET = (RETAIL_EXTRAS[0][1], RETAIL_EXTRAS[0][2] - RETAIL_LOG_Z)

SHADOW_OFFSETS = [
    [(-0x60, 0, 0x70), (0x60, 0, 0x70), (-0x60, 0, -0x60), (0x60, 0, -0x60)],
    [(-0x60, 0, 0x90), (0x60, 0, 0x90), (-0x60, 0, -0x60), (0x60, 0, -0x60)],
    [(-0x60, 0, 0xb0), (0x60, 0, 0xb0), (-0x60, 0, -0x80), (0x60, 0, -0x80)],
    [(-0x60, 0, 0xd0), (0x60, 0, 0xd0), (-0x60, 0, -0xb0), (0x60, 0, -0xb0)],
]
SHADOW_PHASE_TABLE = [0, 1, 2, 3, 2, 1]
SHADOW_PHASE_IMAGE = ['frog_shadow0', 'frog_shadow1', 'frog_shadow2', 'frog_shadow2', 'frog_shadow2', 'frog_shadow1']
AMBIENT_LIGHT = 0x606060
PARALLEL_LIGHT = 0xa0a0c0
PARALLEL_FRAME = (0x800, -0x1000, -0x1000)
SPLASH_LIST = [['SETSPEED', 3], ['SETIMAGE', 'ripple_tim3'], ['SETIMAGE', 'ripple_tim4'], ['SETIMAGE', 'ripple_tim5'],
               ['SETSPEED', 2], ['SETIMAGE', 'ripple_tim6'], ['SETCOLOUR', 0x606060], ['SETIMAGE', 'ripple_tim6'],
               ['SETCOLOUR', 0x404040], ['SETIMAGE', 'ripple_tim6'], ['SETCOLOUR', 0x202020],
               ['SETIMAGE', 'ripple_tim6'], ['KILL', 0]]
ACTIONS = ['GEN_FROG_AUTOHOP', 'GEN_FROG_BACKFLIP', 'GEN_FROG_SQUISHED', 'GEN_FROG_WAIT1', 'GEN_FROG_TIMEOUT',
           'GEN_FROG_STRUGGLE', 'GEN_FROG_FALLING', 'GEN_FROG_TRIGGER', 'GEN_FROG_DROWN', 'GEN_FROG_COMPLETE',
           'GEN_FROG_BITTEN', 'GEN_FROG_FREEFALL', 'GEN_FROG_FLOP', 'GEN_FROG_OUCH', 'GEN_FROG_PANT',
           'GEN_FROG_ROLL', 'GEN_FROG_HOP', 'GEN_FROG_SUPERJUMP', 'GEN_FROG_PANT2', 'GEN_FROG_WAIT3',
           'GEN_FROG_SUPERHOP', 'GEN_FROG_WAIT2', 'GEN_FROG_SLIP', 'GEN_FROG_POP', 'GEN_FROG_SLIPRIGHT',
           'GEN_FROG_SLIPLEFT', 'GEN_FROG_CRASH', 'GEN_FROG_PHEW', 'GEN_FROG_LOOKDOWN', 'GEN_FROG_LOOKUP',
           'GEN_FROG_LOOKLEFT', 'GEN_FROG_LOOKRIGHT', 'GEN_FROG_DANCE', 'GEN_FROG_MOWN']
FRONT_ROWS = ('exit', 'view_scores', 'controls')
VOLUME_ROWS = ('music', 'effects')


def cdiv(a, b):
    return stack.cdiv(a, b)


def rsin(angle):
    return stack.rsin(angle)


def rcos(angle):
    return stack.rcos(angle)


def mul(a, b):
    """MulMatrix2 (MRMulMatrixABB/ABC): 3x3 product, each sum >> 12."""
    return [[(a[r][0] * b[0][c] + a[r][1] * b[1][c] + a[r][2] * b[2][c]) >> 12 for c in range(3)] for r in range(3)]


def diag(x, y, z):
    return [[x, 0, 0], [0, y, 0], [0, 0, z]]


def water_info(x, z, t):
    """HSGetWaterSurfaceInfoFromXZ: height, x slope and z slope."""
    origin_x = -cdiv(WATER_LEN[0] * WATER_NUM[0], 2)
    origin_z = cdiv(WATER_LEN[1] * WATER_NUM[1], 2)
    dx = x - origin_x
    dz = origin_z - z

    def phase_x(d):
        return paths.signed(cdiv(d * PERIOD[0], WATER_NUM[0] * WATER_LEN[0]) + t * FREQ[0])

    def phase_z(d):
        return paths.signed(cdiv(d * PERIOD[1], WATER_NUM[1] * WATER_LEN[1]) + t * FREQ[1])

    tx, tz = phase_x(dx), phase_z(dz)
    y = (rsin(tx) * AMP[0] + rsin(tz) * AMP[1]) >> 12
    y2 = (rsin(phase_x(dx + SLOPE_STEP)) * AMP[0] + rsin(tz) * AMP[1]) >> 12
    x_slope = paths.normalised([SLOPE_STEP, y2 - y, 0])
    y2 = (rsin(tx) * AMP[0] + rsin(phase_z(dz + SLOPE_STEP)) * AMP[1]) >> 12
    z_slope = paths.normalised([0, y2 - y, SLOPE_STEP])
    return y, x_slope, z_slope


class Mat:
    """MR_MAT: rotation m[3][3] and translation t[3]."""

    def __init__(self, x, z):
        self.m = diag(ONE, ONE, ONE)
        self.t = [x, options.FLYON_HEIGHT, z]

    def flat(self):
        return [v for row in self.m for v in row] + list(self.t)


def project(mats, transform, t, flyon, flyoff):
    """HSProjectMatricesOntoWaterSurface."""
    for mat in mats:
        h, vec_x, vec_z = water_info(mat.t[0], mat.t[2], t)
        if flyon:
            mat.t[1] += options.FLYON_SPEED
            if mat.t[1] >= h:
                mat.t[1] = h
        if flyoff:
            if mat.t[0] < 0:
                mat.t[0] -= options.FLYOFF_SPEED
            else:
                mat.t[0] += options.FLYOFF_SPEED
        if not flyon:
            mat.t[1] = h
        vec_y = paths.normalised(stack.outer12(vec_z, vec_x))
        vec_z = stack.outer12(vec_x, vec_y)
        axes = [[vec_x[r], vec_y[r], vec_z[r]] for r in range(3)]
        mat.m = mul(transform, axes)


def log_poly_cels(volume):
    """OptionsSetupVolumeLogAnimatedPolys: cel of animated polys 0-63."""
    cels = [None] * 64
    if volume == 0:
        i = 1
    else:
        i = 1
        while i <= 8:
            if volume == i:
                for k in range(8):
                    cels[LOG_POLY_INDICES[i - 1] + k] = options.LOG_CELS['half']
                i += 1
                break
            for k in range(8):
                cels[LOG_POLY_INDICES[i - 1] + k] = options.LOG_CELS['full']
            i += 1
    while i <= 8:
        for k in range(8):
            cels[LOG_POLY_INDICES[i - 1] + k] = options.LOG_CELS['blank']
        i += 1
    return cels


def lily_z(index):
    return TOP_Z - index * PITCH


class Scene:
    """OptionsStartup's matrices and the per-tick model, frog and shadow updates of OptionsUpdate."""

    def __init__(self, page, widths):
        self.page = page
        self.rows = page.rows
        self.lilies = [Mat(LILY_X, lily_z(i)) for i in range(len(self.rows))]
        self.title_rows = [i for i, r in enumerate(self.rows) if r in FRONT_ROWS]
        self.titles = [Mat(TITLE_X_BASE + (widths.get(self.rows[i], 0) >> 1) * TITLE_X_STEP, lily_z(i))
                       for i in self.title_rows]
        self.log_rows = [i for i, r in enumerate(self.rows) if r in VOLUME_ROWS]
        self.logs = [Mat(LOG_X, lily_z(i)) for i in self.log_rows]
        self.volume_models = [Mat(VOLUME_MODEL_OFFSET[0], lily_z(i) + VOLUME_MODEL_OFFSET[1]) for i in self.log_rows]
        self.extras = [Mat(x, z) for _name, x, z in STATICS]
        self.grid_z = page.row
        lily = self.lilies[self.grid_z]
        self.pos = [lily.t[0] << 16, lily.t[1] << 16, lily.t[2] << 16]
        self.frog = Mat(lily.t[0], lily.t[2])
        self.direction = 'S'
        self.mode = 'STATIONARY'
        self.count = 0
        self.target = [0, 0, 0]
        self.velocity = [0, 0]
        self.fr_y = 0
        self.action = 'GEN_FROG_WAIT2'
        self.one_shot = True
        self.prompt = PROMPT_START
        self.request = page.request
        self.volume = dict(page.volume)

    def set_action(self, name):
        self.action = name
        self.action_set = True

    def tick(self, inputs, events, t, flyon, flyoff):
        self.action_set = False
        self.splashes = []
        project(self.lilies, diag(LILY_SCALE, LILY_SCALE, LILY_SCALE), t, flyon, flyoff)
        rot_x = [[ONE, 0, 0], [0, -0x1000, 0], [0, 0, -0x1000]]
        project(self.logs, mul(diag(LOG_SCALE, LOG_SCALE, LOG_SCALE), rot_x), t, flyon, flyoff)
        project(self.titles, diag(*TITLE_SCALE), t, flyon, flyoff)
        project(self.extras, diag(EXTRA_SCALE, EXTRA_SCALE, EXTRA_SCALE), t, flyon, flyoff)
        c, s = rcos(VOLUME_TILT), rsin(VOLUME_TILT)
        rot_x = [[ONE, 0, 0], [0, c, -s], [0, s, c]]
        c, s = rcos(t << SPIN_SHIFT), rsin(t << SPIN_SHIFT)
        rot_y = [[c, 0, s], [0, ONE, 0], [-s, 0, c]]
        project(self.volume_models, mul(rot_y, rot_x), t, flyon, flyoff)
        if flyon:
            self.prompt -= options.PROMPT_STEP
        if flyoff:
            self.prompt += options.PROMPT_STEP
        self.update_frog(events, flyoff)
        self.shadow_visible = flyon == 0
        if self.mode == 'JUMPING':
            phase = max(0, min(5, ((options.FROG_JUMP_TIME - self.count) * 6) // options.FROG_JUMP_TIME))
        else:
            phase = 0
        self.shadow_phase = phase
        self.shadow_on_water = self.request is None
        corners = []
        for offset in SHADOW_OFFSETS[SHADOW_PHASE_TABLE[phase]]:
            corner = [((self.frog.m[r][0] * offset[0] + self.frog.m[r][1] * offset[1] + self.frog.m[r][2] * offset[2])
                       >> 12) + self.frog.t[r] for r in range(3)]
            if self.shadow_on_water:
                corner[1] = water_info(corner[0], corner[2], t)[0]
            corners.append(corner)
        self.shadow_corners = corners
        name = self.rows[self.page.row]
        if 'volume_step' in events and name in self.volume:
            if self.page.volume[name] == 1 and self.volume[name] == 0:
                self.set_action('GEN_FROG_PANT2' if name == 'effects' else 'GEN_FROG_DANCE')
                self.one_shot = False
            elif self.page.volume[name] == 0:
                self.one_shot = True
        self.volume = dict(self.page.volume)
        if 'croak' in events and 'back' not in inputs:
            self.set_action('GEN_FROG_OUCH')
        self.request = self.page.request

    def update_frog(self, events, flyoff):
        """OptionsUpdateFrog."""
        if self.mode == 'STATIONARY':
            self.pos[1] = self.lilies[self.grid_z].t[1] << 16
            if 'hop' in events:
                new = self.page.row
                self.direction = 'N' if new < self.grid_z else 'S'
                self.grid_z = new
                self.mode = 'JUMPING'
                self.count = options.FROG_JUMP_TIME
                self.target = list(self.lilies[self.grid_z].t)
                self.fr_y = self.pos[1]
                self.velocity = [cdiv((self.target[0] << 16) - self.pos[0], self.count),
                                 cdiv((self.target[2] << 16) - self.pos[2], self.count)]
                self.set_action('GEN_FROG_HOP')
            m = mul(diag(FROG_SCALE, FROG_SCALE, FROG_SCALE), self.lilies[self.grid_z].m)
            if self.direction == 'S':
                m = mul([[-ONE, 0, 0], [0, ONE, 0], [0, 0, -ONE]], m)
            self.frog.m = m
        else:
            self.target[1] = self.lilies[self.grid_z].t[1]
            self.fr_y += cdiv((self.target[1] << 16) - self.fr_y, self.count)
            half = options.FROG_JUMP_TIME >> 1
            dy = (-8 << 16) * (half * half - (self.count - half) * (self.count - half))
            self.pos[1] = self.fr_y + dy
            self.pos[0] += self.velocity[0]
            self.pos[2] += self.velocity[1]
            self.count -= 1
            if not self.count:
                self.pos = [v << 16 for v in self.target]
                self.mode = 'STATIONARY'
                self.set_action('GEN_FROG_WAIT1')
                self.splashes.append(self.grid_z)
                if self.rows[self.grid_z] == 'music' and self.page.volume['music'] > 0:
                    self.set_action('GEN_FROG_DANCE')
                    self.one_shot = False
        if flyoff:
            self.pos[0] -= options.FLYOFF_SPEED << 16
            self.target[0] -= options.FLYOFF_SPEED
        self.frog.t = [v >> 16 for v in self.pos]

    def state(self, tick, t, inputs, events):
        return {
            'tick': tick, 'frame': t, 'input': inputs, 'events': events,
            'lilies': [m.flat() for m in self.lilies], 'titles': [m.flat() for m in self.titles],
            'logs': [m.flat() for m in self.logs], 'volume_models': [m.flat() for m in self.volume_models],
            'extras': [m.flat() for m in self.extras], 'frog': self.frog.flat(),
            'frog_position': list(self.pos), 'frog_direction': self.direction,
            'action': self.action, 'action_set': getattr(self, 'action_set', True), 'looping': not self.one_shot,
            'splashes': list(getattr(self, 'splashes', [])), 'prompt_offset': self.prompt,
            'shadow': {'visible': getattr(self, 'shadow_visible', False), 'phase': getattr(self, 'shadow_phase', 0),
                       'on_water': getattr(self, 'shadow_on_water', False),
                       'corners': getattr(self, 'shadow_corners', [])}}


SCENARIOS = [
    ('fly_on_hop_and_music', 'fly-on to the water, three held DOWN hops to the music row (volume 0), Right '
     'starts DANCE looping, Left back to 0 sets one-shot, a hop to effects, Right starts PANT2, fire croaks OUCH, '
     'Up back to music lands into DANCE, then back flies everything off',
     False, 0, 0, 'exit', 40, {'exit': 46, 'controls': 170},
     [[10, []], [1, ['down']], [12, []], [1, ['down']], [12, []], [3, []], [1, ['right']], [2, []], [1, ['left']],
      [1, ['down']], [12, []], [1, ['right']], [3, []], [1, ['fire']], [2, []], [1, ['right']], [1, ['up']],
      [12, []], [2, []], [1, ['back']], [10, []]]),
    ('scores_row_and_controls_fly_off', 'the high-score row shown: three titles and logs below them at the same '
     'pitch; the controls row flies off sliding the frog left and the extras away from x 0',
     True, 3, 5, 'controls', 1000, {'exit': 46, 'view_scores': 169, 'controls': 170},
     [[12, []], [1, ['down']], [12, []], [1, ['up']], [12, []], [1, ['fire']], [10, []]]),
]


def replay(scores, music, effects, start_row, frame_start, widths, runs):
    page = options.Page(scores, music, effects, start_row)
    scene = Scene(page, widths)
    trace = [scene.state(0, None, [], [])]
    tick = 0
    for count, inputs in runs:
        for _ in range(count):
            if page.finished:
                return scene, trace
            tick += 1
            t = frame_start + tick - 1
            flyon, flyoff = max(0, page.fly_on - 1), max(0, page.fly_off - 1)
            events = page.tick(inputs, t)
            scene.tick(inputs, events, t, flyon, flyoff)
            trace.append(scene.state(tick, t, list(inputs), events))
    return scene, trace


def document():
    lights = {'ambient': AMBIENT_LIGHT, 'parallel': PARALLEL_LIGHT, 'parallel_frame': list(PARALLEL_FRAME),
              'parallel_direction': paths.normalised([-v for v in PARALLEL_FRAME])}
    surface = []
    for x, z, t in [(-0x380, 0x2c0, 0), (-0x380, -0x340, 37), (0, -0x140, 255), (0x400, -0x400, 1000),
                    (-0x680, 0x520, 4096), (0x580, 0x440, 65535), (-0xd80, 0x2c0, 9)]:
        h, xs, zs = water_info(x, z, t)
        surface.append({'x': x, 'z': z, 'frame': t, 'height': h, 'x_slope': xs, 'z_slope': zs})
    scenarios = []
    for name, description, scores, music, effects, start, frame_start, widths, runs in SCENARIOS:
        _scene, trace = replay(scores, music, effects, start, frame_start, widths, runs)
        if 'leave' not in trace[-1]['events']:
            sys.exit('scenario %s does not end by leaving the page' % name)
        scenarios.append({'name': name, 'description': description, 'scores_available': scores, 'music': music,
                          'effects': effects, 'start_row': start, 'frame_start': frame_start,
                          'title_widths': widths, 'inputs': runs, 'trace': trace})
    return {
        'constants': {
            'lily_scale': LILY_SCALE, 'log_scale': LOG_SCALE, 'title_scale': list(TITLE_SCALE),
            'extra_scale': EXTRA_SCALE, 'frog_scale': FROG_SCALE, 'volume_tilt': VOLUME_TILT,
            'volume_spin': 'vp_frame_count << %d' % SPIN_SHIFT, 'lily_x': LILY_X, 'log_x': LOG_X,
            'title_x': '%d + (te_w >> 1) * %d' % (TITLE_X_BASE, TITLE_X_STEP),
            'volume_model_offset': list(VOLUME_MODEL_OFFSET), 'sprite_scale': SPRITE_SCALE,
            'title_raise': TITLE_RAISE, 'reflection_offset': REFLECTION_OFFSET,
            'reflection_colour': REFLECTION_COLOUR, 'reflection_abr': 2, 'reflection_ot_offset': REFLECTION_OT,
            'splash_ot_offset': SPLASH_OT, 'prompt_start': PROMPT_START, 'slope_step': SLOPE_STEP,
            'frog_update_period': 2, 'frog_start_action': 'GEN_FROG_WAIT2', 'throat_scale': 0x200,
            'log_poly_indices': LOG_POLY_INDICES},
        'extras': {
            'vendored': [list(e) for e in VENDORED_EXTRAS], 'retail': [list(e) for e in RETAIL_EXTRAS],
            'retail_log_z': RETAIL_LOG_Z, 'port_statics': [list(e) for e in STATICS]},
        'lights': lights,
        'shadow': {'offsets': [[list(c) for c in table] for table in SHADOW_OFFSETS],
                   'phase_table': SHADOW_PHASE_TABLE, 'phase_images': SHADOW_PHASE_IMAGE},
        'splash_list': SPLASH_LIST,
        'actions': ACTIONS,
        'log_poly_cels': [log_poly_cels(v) for v in range(options.SOUND_STAGES + 1)],
        'surface': surface,
        'scenarios': scenarios,
    }


def hexed(value):
    return ('-0x%x' % -value) if value < 0 else ('0x%x' % value)


def check_c(c_root):
    """Compare the transcriptions above with the frozen C; returns problems."""
    problems = []
    tempopt_text = (c_root / 'tempopt.c').read_text(encoding='latin-1')
    tempopt = stack.squash(tempopt_text)
    uncommented = stack.squash(re.sub(r'//[^\n]*', '', tempopt_text))
    extras = ''.join('%s,%s,' % (hexed(x), hexed(z)) for _n, x, z in VENDORED_EXTRAS)
    coords = 'MR_LONGOptions_extras_coords[]={' + extras.replace(',0x40,', ',0x040,', 1) + '};'
    if coords not in uncommented:
        problems.append('tempopt.c Options_extras_coords differ from the transcription')
    snippets = [
        'MR_ULONGOptions_extras_resource_id[]={RES_OPT_MUSIC_XMU,RES_OPT_SFX_XMU,RES_OPT_STAT_BULLRUSH_XMR,'
        'RES_OPT_STAT_LILLY_XMR,RES_OPT_STAT_LILLY_XMR,RES_OPT_STAT_LILLY_XMR,RES_OPT_STAT_BULLRUSH_XMR,};',
        'Options_shadow_textures[i].te_tpage_id=setABR(Options_shadow_textures[i].te_tpage_id,2);',
        'High_score_view_initials_object_ptr[i]->ob_extra.ob_extra_3dsprite->sp_ofs_image.vy=-0x40;',
        'High_score_view_initials_object_ptr[k]->ob_extra.ob_extra_sp_core->sc_flags|=MR_SPF_IN_XZ_PLANE;'
        'High_score_view_initials_object_ptr[k]->ob_extra.ob_extra_sp_core->sc_ot_offset=0x10;'
        'High_score_view_initials_object_ptr[k]->ob_extra.ob_extra_sp_core->sc_base_colour.r=0x40;',
        'High_score_view_initials_object_ptr[k]->ob_extra.ob_extra_3dsprite->sp_ofs_image.vz=0x48;',
        'MRAnimEnvSingleSetAction(High_score_view_frog_anim_env_ptr,GEN_FROG_WAIT2);'
        'High_score_view_frog_anim_env_ptr->ae_update_period=2;',
        'High_score_view_frog_sack_scale_matrix.m[0][0]=FROG_CROAK_MIN_SCALE;',
        'frog->fr_direction=FROG_DIRECTION_S;',
        'frog->fr_shadow->ef_flags|=EFFECT_STATIC;',
        'Options_extras_user_prompt_ptr=MRCreate2DSprite((Game_display_width>>1)-(texture->te_w>>1),'
        '(Game_display_height-texture->te_h)+76,Option_viewport_ptr,texture,NULL);',
        'MRScale_matrix.m[0][0]=0x1600;MRScale_matrix.m[1][1]=0x1600;MRScale_matrix.m[2][2]=0x1600;'
        '//ApplywavedeltastolilliesHSProjectMatricesOntoWaterSurface(High_score_view_number_matrix_ptr[0],OPTIONS_NUM_OPTIONS,&MRScale_matrix);',
        'MRRot_matrix_X.m[1][1]=-0x1000;MRRot_matrix_X.m[1][2]=0;MRRot_matrix_X.m[2][1]=0;MRRot_matrix_X.m[2][2]=-0x1000;'
        'MRScale_matrix.m[0][0]=0x1300;MRScale_matrix.m[1][1]=0x1300;MRScale_matrix.m[2][2]=0x1300;'
        'MRMulMatrixABC(&MRScale_matrix,&MRRot_matrix_X,&transform);'
        'HSProjectMatricesOntoWaterSurface(High_score_view_log_matrix_ptr[0],2,&transform);',
        'HSProjectMatricesOntoWaterSurface(High_score_view_initials_matrix_ptr[0],OPTIONS_NUM_OPTIONS-2,&MRScale_matrix);',
        'MRScale_matrix.m[0][0]=0x1800;MRScale_matrix.m[1][1]=0x1800;MRScale_matrix.m[2][2]=0x1800;'
        'HSProjectMatricesOntoWaterSurface(Options_extras_matrix_ptr[2],OPTIONS_NUM_EXTRAS-2,&MRScale_matrix);',
        'cos=rcos(0x400);sin=rsin(0x400);MRRot_matrix_X.m[1][1]=cos;MRRot_matrix_X.m[1][2]=-sin;'
        'MRRot_matrix_X.m[2][1]=sin;MRRot_matrix_X.m[2][2]=cos;cos=rcos(Option_viewport_ptr->vp_frame_count<<8);'
        'sin=rsin(Option_viewport_ptr->vp_frame_count<<8);MRRot_matrix_Y.m[0][0]=cos;MRRot_matrix_Y.m[0][2]=sin;'
        'MRRot_matrix_Y.m[2][0]=-sin;MRRot_matrix_Y.m[2][2]=cos;MRMulMatrixABC(&MRRot_matrix_Y,&MRRot_matrix_X,&transform);'
        'HSProjectMatricesOntoWaterSurface(Options_extras_matrix_ptr[0],2,&transform);',
        'shadow->sh_corners[0][i].vy=HSGetWaterSurfaceInfoFromXZ(shadow->sh_corners[0][i].vx,'
        'shadow->sh_corners[0][i].vz,NULL,NULL);',
        'MRAnimEnvSingleSetAction(High_score_view_frog_anim_env_ptr,GEN_FROG_PANT2);'
        'High_score_view_frog_anim_env_ptr->ae_flags&=~MR_ANIM_ENV_ONE_SHOT;',
        'if(!Sound_volume){//Yes...stopcroakanimationHigh_score_view_frog_anim_env_ptr->ae_flags|=MR_ANIM_ENV_ONE_SHOT;',
        'MRAnimEnvSingleSetAction(High_score_view_frog_anim_env_ptr,GEN_FROG_DANCE);'
        'High_score_view_frog_anim_env_ptr->ae_flags&=~MR_ANIM_ENV_ONE_SHOT;',
        'if(!Music_volume){//Yes...stopcroakanimationHigh_score_view_frog_anim_env_ptr->ae_flags|=MR_ANIM_ENV_ONE_SHOT;',
        'MRSNDPlaySound(SFX_GEN_FROG_CROAK,NULL,0,0);MRAnimEnvSingleSetAction(High_score_view_frog_anim_env_ptr,GEN_FROG_OUCH);',
        '//MRAnimEnvSingleSetAction(High_score_view_frog_anim_env_ptr,GEN_FROG_OUCH);',
        'frog->fr_pos.vy=High_score_view_number_matrix_ptr[frog->fr_grid_z]->t[1]<<16;',
        'frog->fr_direction=FROG_DIRECTION_N;frog->fr_grid_z--;',
        'frog->fr_y=frog->fr_pos.vy;frog->fr_velocity.vx=((frog->fr_target_pos.vx<<16)-frog->fr_pos.vx)/frog->fr_count;'
        'frog->fr_velocity.vz=((frog->fr_target_pos.vz<<16)-frog->fr_pos.vz)/frog->fr_count;'
        'MRAnimEnvSingleSetAction(High_score_view_frog_anim_env_ptr,GEN_FROG_HOP);',
        'MR_COPY_MAT(frog->fr_lwtrans,High_score_view_number_matrix_ptr[frog->fr_grid_z]);'
        'MRScale_matrix.m[0][0]=0x1400;MRScale_matrix.m[1][1]=0x1400;MRScale_matrix.m[2][2]=0x1400;'
        'MRMulMatrixABB(&MRScale_matrix,frog->fr_lwtrans);if(frog->fr_direction==FROG_DIRECTION_S){'
        'MR_INIT_MAT(&matrix);matrix.m[0][0]=-0x1000;matrix.m[0][2]=0;matrix.m[2][0]=0;matrix.m[2][2]=-0x1000;'
        'MRMulMatrixABB(&matrix,frog->fr_lwtrans);}',
        'frog->fr_target_pos.vy=High_score_view_number_matrix_ptr[frog->fr_grid_z]->t[1];'
        'frog->fr_y+=((frog->fr_target_pos.vy<<16)-frog->fr_y)/frog->fr_count;',
        'frog->fr_pos.vy=frog->fr_y+dy;frog->fr_pos.vx+=frog->fr_velocity.vx;frog->fr_pos.vz+=frog->fr_velocity.vz;',
        'frog->fr_mode=FROG_MODE_STATIONARY;MRAnimEnvSingleSetAction(High_score_view_frog_anim_env_ptr,GEN_FROG_WAIT1);'
        '//Createsplashspriteobject_ptr=MRCreate3DSprite((MR_FRAME*)High_score_view_number_matrix_ptr[frog->fr_grid_z],'
        'MR_OBJ_STATIC,High_score_splash_animlist);',
        'object_ptr->ob_extra.ob_extra_sp_core->sc_flags|=MR_SPF_IN_XZ_PLANE;'
        'object_ptr->ob_extra.ob_extra_sp_core->sc_ot_offset=-0x8;object_ptr->ob_extra.ob_extra_sp_core->sc_scale=10<<16;',
        'if(Music_volume>0){//Yes...triggermusicanimationMRAnimEnvSingleSetAction(High_score_view_frog_anim_env_ptr,'
        'GEN_FROG_DANCE);High_score_view_frog_anim_env_ptr->ae_flags&=~MR_ANIM_ENV_ONE_SHOT;}',
        'frog->fr_pos.vx-=(OPTIONS_CAMERA_FLYOFF_SPEED<<16);frog->fr_target_pos.vx-=OPTIONS_CAMERA_FLYOFF_SPEED;}'
        '//Getfrogposition/rotationfrog->fr_lwtrans->t[0]=frog->fr_pos.vx>>16;'
        'frog->fr_lwtrans->t[1]=frog->fr_pos.vy>>16;frog->fr_lwtrans->t[2]=frog->fr_pos.vz>>16;',
        'if(High_score_view_flyon_counter)effect->ef_flags|=(EFFECT_NO_UPDATE|EFFECT_NO_DISPLAY);',
        'i=((HIGH_SCORE_VIEW_FROG_JUMP_TIME-frog->fr_count)*6)/HIGH_SCORE_VIEW_FROG_JUMP_TIME;i=MAX(0,MIN(5,i));',
    ]
    for snippet in snippets:
        if stack.squash(snippet) not in tempopt:
            problems.append('tempopt.c no longer contains: %s' % snippet[:90])
    hs = stack.squash((c_root / 'HSView.c').read_text(encoding='latin-1'))
    splash = ''.join('MR_SPRT_%s,%s,' % (op, ('(MR_ULONG)&im_' + str(v)) if op == 'SETIMAGE' else
                                          ('0x%x' % v if op == 'SETCOLOUR' else str(v)))
                     for op, v in SPLASH_LIST[:-1]) + 'MR_SPRT_KILL};'
    for snippet in (
            'MR_ULONGHigh_score_splash_animlist[]={' + splash,
            'MR_USHORTHigh_score_log_animated_poly_indices[]={%s};' % ','.join(str(v) for v in LOG_POLY_INDICES),
            'dx=x-High_score_view_water_points_ptr[0].vx;dz=High_score_view_water_points_ptr[0].vz-z;'
            't=Option_viewport_ptr->vp_frame_count;',
            'tx=((dx*HIGH_SCORE_VIEW_WAVE_PERIOD_X)/(HIGH_SCORE_VIEW_WATER_X_NUM*HIGH_SCORE_VIEW_WATER_X_LEN))'
            '+(t*HIGH_SCORE_VIEW_WAVE_FREQ_X);',
            'y=((rsin(tx)*HIGH_SCORE_VIEW_WAVE_AMP_X)+(rsin(tz)*HIGH_SCORE_VIEW_WAVE_AMP_Z))>>12;',
            'tx2=(((dx+0x100)*HIGH_SCORE_VIEW_WAVE_PERIOD_X)/(HIGH_SCORE_VIEW_WATER_X_NUM*HIGH_SCORE_VIEW_WATER_X_LEN))'
            '+(t*HIGH_SCORE_VIEW_WAVE_FREQ_X);',
            'x_slope->vx=0x100;x_slope->vy=y2-y;x_slope->vz=0;MRNormaliseVEC(x_slope,x_slope);',
            'z_slope->vz=0x100;z_slope->vy=y2-y;z_slope->vx=0;MRNormaliseVEC(z_slope,z_slope);',
            'MROuterProduct12(&vec_z,&vec_x,&vec_y);MRNormaliseVEC(&vec_y,&vec_y);MROuterProduct12(&vec_x,&vec_y,&vec_z);'
            'WriteAxesAsMatrix(matrix_ptr,&vec_x,&vec_y,&vec_z);if(transform)MRMulMatrixABB(transform,matrix_ptr);'):
        if stack.squash(snippet) not in hs:
            problems.append('HSView.c no longer contains: %s' % snippet[:90])
    h = (c_root / 'HSView.h').read_text(encoding='latin-1')
    for name, value in (('HIGH_SCORE_VIEW_WAVE_AMP_X', '0x40'), ('HIGH_SCORE_VIEW_WAVE_AMP_Z', '0x50'),
                        ('HIGH_SCORE_VIEW_WAVE_FREQ_X', '0x60'), ('HIGH_SCORE_VIEW_WAVE_FREQ_Z', '0x80'),
                        ('HIGH_SCORE_VIEW_WAVE_PERIOD_X', '0x2000'), ('HIGH_SCORE_VIEW_WAVE_PERIOD_Z', '0x2000'),
                        ('HIGH_SCORE_VIEW_WATER_X_NUM', '14'), ('HIGH_SCORE_VIEW_WATER_Z_NUM', '16'),
                        ('HIGH_SCORE_VIEW_WATER_X_LEN', '0x240'), ('HIGH_SCORE_VIEW_WATER_Z_LEN', '0x240')):
        if stack.define(h, name) != value:
            problems.append('HSView.h %s is %s, transcribed %s' % (name, stack.define(h, name), value))
    frog = stack.squash((c_root / 'FROG.C').read_text(encoding='latin-1'))
    for index, table in enumerate(SHADOW_OFFSETS):
        words = ''.join('{0x%04X,0x%04X,0x%04X},' % tuple(v & 0xffff for v in corner) for corner in table)
        if 'MR_SVECFrog_shadow_offsets%d[]={%s};' % (index + 1, words.rstrip(',')) not in frog:
            problems.append('FROG.C Frog_shadow_offsets%d differs' % (index + 1))
    phases = ''.join('&Frog_shadow_offsets%d[0],' % (t + 1) for t in SHADOW_PHASE_TABLE).rstrip(',')
    if 'MR_SVEC*Frog_jump_shadow_offsets[]={%s};' % phases not in frog:
        problems.append('FROG.C Frog_jump_shadow_offsets differs')
    images = ''.join('&im_%s,' % name for name in SHADOW_PHASE_IMAGE).rstrip(',')
    if 'MR_TEXTURE*Frog_jump_shadow_textures[]={%s};' % images not in frog:
        problems.append('FROG.C Frog_jump_shadow_textures differs')
    opts = stack.squash((c_root / 'options.c').read_text(encoding='latin-1'))
    for snippet in ('light0=MRCreateLight(MR_LIGHT_TYPE_AMBIENT,0x606060,NULL,MR_OBJ_STATIC);',
                    'MR_SET_VEC(&vec,0x800,-0x1000,-0x1000);frame1=MRCreateFrame(&vec,&Null_svector,0);'
                    'MRPointMatrixAtVector(&frame1->fr_matrix,&Null_vector,&Game_y_axis_pos);'
                    'light1=MRCreateLight(MR_LIGHT_TYPE_PARALLEL,0xa0a0c0,frame1,NULL);'):
        if stack.squash(snippet) not in opts:
            problems.append('options.c no longer contains: %s' % snippet[:90])
    anims = (ROOT / 'third_party' / 'froglord_cfg' / 'anims' / 'main-pc.cfg').read_text(encoding='latin-1')
    section = anims.split('[GEN_FROG]', 1)[1].split('[', 1)[0].split()
    if section != ACTIONS:
        problems.append('FrogLord main-pc.cfg GEN_FROG actions differ from the transcription')
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--c-reference', type=Path, default=frontend.DEFAULT_C,
                        help='frozen C source folder (default: ../froggy/engine/vendor/frogger-psx-src/source)')
    parser.add_argument('--check', action='store_true', help='compare with the committed file instead of writing')
    args = parser.parse_args()
    if args.c_reference.is_dir():
        problems = check_c(args.c_reference)
        for problem in problems:
            print('C cross-check: ' + problem)
        if problems:
            sys.exit(1)
        print('C cross-check passed against %s' % args.c_reference)
    else:
        print('C source not found at %s; cross-checks skipped' % args.c_reference)
    text = stack.dump(document()) + '\n'
    if args.check:
        old = MODELS_JSON.read_text(encoding='utf-8') if MODELS_JSON.exists() else ''
        if old != text:
            sys.stdout.writelines(difflib.unified_diff(old.splitlines(True), text.splitlines(True),
                                                       str(MODELS_JSON), 'generated', n=0))
        print('Committed facts differ from the generator' if old != text else 'Committed facts match the generator')
        sys.exit(1 if old != text else 0)
    MODELS_JSON.write_text(text, encoding='utf-8')
    print('Wrote %s' % MODELS_JSON.relative_to(ROOT))


if __name__ == '__main__':
    main()
