#!/usr/bin/env python3
"""Independent front-end water and riverbed facts from the frozen C.

Transcribes HSInitialiseWater and HSUpdateWater (HSView.c), the options
camera presets of InitialiseOptionsCamera, OptionsCameraSnapTo*/MoveTo*,
HSInputInitialiseCamera and the static high-score view, and replays the
CAMERA_MODE_FIXED_SWEEP step that HSUpdateScrollyCamera drives. Wave heights
are replayed for a set of viewport frame counts. See
tests/golden/specs/frontend.md#front-end-water.
"""
import argparse
import difflib
import hashlib
from pathlib import Path
import re
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.golden import make_golden_frontend as frontend
from tools.golden import make_golden_paths as paths
from tools.golden import make_golden_stack as stack

ROOT = frontend.ROOT
WATER_JSON = frontend.GOLDEN / 'synthetic' / 'frontend_water.json'

PERSPECTIVE = 0x100
AMP_X, AMP_Z = 0x40, 0x50
FREQ_X, FREQ_Z = 0x60, 0x80
PERIOD_X, PERIOD_Z = 0x2000, 0x2000
WATER_NUM = (14, 16)
WATER_LEN = (0x240, 0x240)
RIVERBED_NUM = (14, 16)
RIVERBED_LEN = (0x240, 0x240)
PRIM_COLOURS = (0x00406060, 0x00303030)
COUNTER_BITS = 16
FRAMES = [0, 1, 2, 30, 127, 128, 255, 1000, 65535]
CORNER_STEPS = [[0, 0], [1, 0], [0, 1], [1, 1]]
RIVERBED_TEXTURE_CORNERS = {'odd_rows': [0, 1, 2, 3], 'even_rows': [2, 3, 0, 1]}
Y_AXIS = (0, 0x1000, 0)
CAMERA_PRESETS = {
    'MAIN': ((0, -2500, -1280), (0, 1024, -800)),
    'OPTIONS': ((-1200, -2000, -1800), (300, 1000, 500)),
    'HS_STATIC': ((0, -3200, -200), (0, 1024, 50)),
    'HS_INPUT': ((0, -2400, -256), (0, 1024, 0)),
}
FLYOFF_TIME, FLYON_TIME = 10, 10
MOVE_TIME = FLYOFF_TIME + FLYON_TIME
SCROLLY_Z_BIAS = 1152
LEVEL_SELECT_PERSPECTIVE = 1000

PAGES = [
    ('MAIN_OPTIONS', 'MainOptionsUpdate -> HSUpdateScrollyHighScores', 'options', 'HSView.c:2587',
     'high-score view status only; the menu snaps to MAIN and source/target z then follow the frog'),
    ('OPTIONS', 'OptionsUpdate', 'options', 'tempopt.c:4566', 'OPTIONS preset'),
    ('FROG_SELECTION', 'FrogSelectionUpdate', 'options', 'tempopt.c:2872', 'camera left as found'),
    ('LEVEL_SELECT', 'SelectLevelUpdate', 'level_select', 'SELECT.C:1304', 'stack camera, perspective 1000'),
    ('LANGUAGE_SELECTION', 'LanguageSelectionUpdate', 'options', 'tempopt.c:5190', 'camera left as found'),
    ('REDEFINE_PSX_BUTTONS', 'RedefinePSXButtonsUpdate', 'options', 'tempopt.c:5486', 'camera left as found'),
    ('SAVE', 'SaveUpdate', 'options', 'LoadSave.c:677', 'camera left as found'),
    ('LOAD', 'LoadUpdate', 'options', 'LoadSave.c:1536', 'camera left as found'),
    ('CHECK', 'CheckUpdate', 'options', 'LoadSave.c:2256', 'camera left as found'),
    ('HIGH_SCORE_INPUT', 'HighScoreInputUpdate', 'options', 'hsinput.c:453', 'HS_INPUT preset'),
    ('HIGH_SCORE_VIEW', 'HSViewUpdate -> HSUpdateScrollyHighScores', 'options', 'HSView.c:2587',
     'HS_STATIC preset when entered from the show-hiscores option, otherwise scrolly'),
    ('SHOW_WATER', 'ShowWaterUpdate', 'options', 'tempopt.c:6588', 'MAIN preset, pad-steered QA cheat'),
]


def cdiv(a, b):
    return stack.cdiv(a, b)


def rsin(angle):
    return stack.rsin(angle)


def digest(values):
    return hashlib.sha256(','.join(str(v) for v in values).encode()).hexdigest()


def axis_positions(num, length):
    """HSInitialiseWater: x = -(len*num)/2 + i*len, z = (len*num)/2 - j*len."""
    half = [cdiv(length[0] * num[0], 2), cdiv(length[1] * num[1], 2)]
    xs = [-half[0] + i * length[0] for i in range(num[0] + 1)]
    zs = [half[1] - j * length[1] for j in range(num[1] + 1)]
    return xs, zs


def wave_frame(t):
    """HSUpdateWater's vertex heights for viewport frame count t."""
    sin_x = [rsin(cdiv(i * PERIOD_X, WATER_NUM[0]) + t * FREQ_X) for i in range(WATER_NUM[0] + 1)]
    sin_z = [rsin(cdiv(j * PERIOD_Z, WATER_NUM[1]) + t * FREQ_Z) for j in range(WATER_NUM[1] + 1)]
    heights = [[(sx * AMP_X + sz * AMP_Z) >> 12 for sx in sin_x] for sz in sin_z]
    return sin_x, sin_z, heights


def wave_period():
    """Smallest frame step after which both phases return to the same angle (mod 4096)."""
    period = 1
    while (period * FREQ_X) % 4096 or (period * FREQ_Z) % 4096:
        period += 1
    return period


def colour(word):
    """MR_COPY32 into r0: the low byte is red."""
    return [word & 0xff, (word >> 8) & 0xff, (word >> 16) & 0xff]


def camera(source, target):
    """MRPointMatrixAtVector from the source offset to the target offset, origin Null_vector."""
    z = paths.normalised([target[i] - source[i] for i in range(3)])
    nx = paths.normalised(stack.outer12(Y_AXIS, z))
    ny = stack.outer12(z, nx)
    return [[stack.s16(nx[r]), stack.s16(ny[r]), stack.s16(z[r])] for r in range(3)]


def sweep(start, end, timer):
    """HSUpdateScrollyCamera calls: timer = MAX(1, timer); if --timer, step (next - cur) / timer."""
    source, target = list(start[0]), list(start[1])
    rows = []
    while True:
        timer = max(1, timer) - 1
        if timer:
            for i in range(3):
                source[i] += cdiv(end[0][i] - source[i], timer)
                target[i] += cdiv(end[1][i] - target[i], timer)
        rows.append({'tick': len(rows) + 1, 'timer': timer, 'source': list(source), 'target': list(target)})
        if not timer:
            return rows


def document():
    xs, zs = axis_positions(WATER_NUM, WATER_LEN)
    bed_xs, bed_zs = axis_positions(RIVERBED_NUM, RIVERBED_LEN)
    period = wave_period()
    if (1 << COUNTER_BITS) % period:
        sys.exit('wave period does not divide the counter range')
    frames = []
    for t in FRAMES:
        sin_x, sin_z, heights = wave_frame(t)
        if wave_frame(t + period)[2] != heights:
            sys.exit('wave period check failed at %d' % t)
        frames.append({'t': t, 'sin_x': sin_x, 'sin_z': sin_z,
                       'digest': digest([h for row in heights for h in row]), 'heights': heights})
    lows, highs = [], []
    for t in range(period):
        flat = [h for row in wave_frame(t)[2] for h in row]
        lows.append(min(flat))
        highs.append(max(flat))
    presets = {}
    for name, (source, target) in CAMERA_PRESETS.items():
        presets[name] = {'source': list(source), 'target': list(target),
                         'matrix': camera(source, target), 'translation': list(source)}
    return {
        'constants': {'water_num': list(WATER_NUM), 'water_len': list(WATER_LEN),
                      'riverbed_num': list(RIVERBED_NUM), 'riverbed_len': list(RIVERBED_LEN),
                      'wave_amp': [AMP_X, AMP_Z], 'wave_freq': [FREQ_X, FREQ_Z],
                      'wave_period': [PERIOD_X, PERIOD_Z], 'perspective': PERSPECTIVE,
                      'clear_colour': [0, 0, 0]},
        'grid': {'vertices': [WATER_NUM[0] + 1, WATER_NUM[1] + 1], 'quads': list(WATER_NUM),
                 'x': xs, 'z': zs, 'y': 0, 'vertex_order': 'row-major, j (z) outer, i (x) inner',
                 'corner_steps': CORNER_STEPS, 'riverbed_x': bed_xs, 'riverbed_z': bed_zs, 'riverbed_y': 0},
        'water': {'texture': 'im_opt_env_sky', 'colour_word': '0x%08x' % PRIM_COLOURS[0],
                  'colour': colour(PRIM_COLOURS[0]), 'semi_transparent': True, 'abr': 1,
                  'blend': 'one_one', 'ot_slot_from_back': 2,
                  'uv_divisions': list(WATER_NUM), 'uv_corner_steps': CORNER_STEPS},
        'riverbed': {'texture': 'im_opt_bank3', 'colour_word': '0x%08x' % PRIM_COLOURS[1],
                     'colour': colour(PRIM_COLOURS[1]), 'semi_transparent': False,
                     'ot_slot_from_back': 0, 'texture_corners': RIVERBED_TEXTURE_CORNERS},
        'draw_order': ['riverbed', 'water'],
        'wave': {'counter': 'Option_viewport_ptr->vp_frame_count', 'counter_bits': COUNTER_BITS,
                 'period_frames': period, 'height_min': min(lows), 'height_max': max(highs),
                 'frames': frames},
        'cameras': {
            'options': {'perspective': PERSPECTIVE, 'origin': [0, 0, 0], 'up': list(Y_AXIS),
                        'presets': presets,
                        'move_time': MOVE_TIME, 'flyoff_time': FLYOFF_TIME, 'flyon_time': FLYON_TIME,
                        'scrolly_z_bias': SCROLLY_Z_BIAS,
                        'sweep_main_to_options': sweep(CAMERA_PRESETS['MAIN'], CAMERA_PRESETS['OPTIONS'],
                                                       MOVE_TIME),
                        'sweep_options_to_main': sweep(CAMERA_PRESETS['OPTIONS'], CAMERA_PRESETS['MAIN'],
                                                       MOVE_TIME)},
            'level_select': {'perspective': LEVEL_SELECT_PERSPECTIVE,
                             'camera': 'frontend_stack_layout.json camera_matrix and camera_translation'}},
        'pages': [{'page': p, 'update': u, 'camera': c, 'source': s, 'note': n} for p, u, c, s, n in PAGES],
    }


def check_c(c_root):
    """Compare the transcriptions above with the frozen C; returns problems."""
    problems = []
    h = (c_root / 'HSView.h').read_text(encoding='latin-1')
    expected = {
        'HIGH_SCORE_VIEW_PERSPECTIVE': '0x100', 'HIGH_SCORE_VIEW_WAVE_AMP_X': '0x40',
        'HIGH_SCORE_VIEW_WAVE_AMP_Z': '0x50', 'HIGH_SCORE_VIEW_WAVE_FREQ_X': '0x60',
        'HIGH_SCORE_VIEW_WAVE_FREQ_Z': '0x80', 'HIGH_SCORE_VIEW_WAVE_PERIOD_X': '0x2000',
        'HIGH_SCORE_VIEW_WAVE_PERIOD_Z': '0x2000', 'HIGH_SCORE_VIEW_WATER_X_NUM': '14',
        'HIGH_SCORE_VIEW_WATER_Z_NUM': '16', 'HIGH_SCORE_VIEW_WATER_X_LEN': '0x240',
        'HIGH_SCORE_VIEW_WATER_Z_LEN': '0x240', 'HIGH_SCORE_VIEW_RIVERBED_X_NUM': '14',
        'HIGH_SCORE_VIEW_RIVERBED_Z_NUM': '16', 'HIGH_SCORE_VIEW_RIVERBED_X_LEN': '0x240',
        'HIGH_SCORE_VIEW_RIVERBED_Z_LEN': '0x240'}
    for name, value in expected.items():
        if stack.define(h, name) != value:
            problems.append('HSView.h %s is %s, transcribed %s' % (name, stack.define(h, name), value))
    t = (c_root / 'tempopt.h').read_text(encoding='latin-1')
    names = {'MAIN': 'MAIN', 'OPTIONS': 'OPTIONS', 'HS_STATIC': 'HS_STATIC'}
    for preset, key in names.items():
        source, target = CAMERA_PRESETS[preset]
        for part, values in (('SOURCE', source), ('TARGET', target)):
            for axis, value in zip('XYZ', values):
                name = 'OPTIONS_CAMERA_%s_%s_OFS_%s' % (key, part, axis)
                if stack.define(t, name) != str(value):
                    problems.append('tempopt.h %s is %s, transcribed %d' % (name, stack.define(t, name), value))
    for name, value in (('OPTIONS_CAMERA_FLYOFF_TIME', '10'), ('OPTIONS_CAMERA_FLYON_TIME', '10'),
                        ('OPTIONS_CAMERA_MOVE_TIME', '(OPTIONS_CAMERA_FLYOFF_TIME+OPTIONS_CAMERA_FLYON_TIME)')):
        if stack.define(t, name) != value:
            problems.append('tempopt.h %s differs' % name)
    hi = (c_root / 'hsinput.h').read_text(encoding='latin-1')
    source, target = CAMERA_PRESETS['HS_INPUT']
    for part, values in (('SOURCE', source), ('TARGET', target)):
        for axis, value in zip('XYZ', values):
            name = 'HIGH_SCORE_INPUT_STATIC_%s_OFS_%s' % (part, axis)
            if stack.define(hi, name) != str(value):
                problems.append('hsinput.h %s differs' % name)
    view = (c_root / 'API.SRC' / 'MR_VIEW.H').read_text(encoding='latin-1')
    if not re.search(r'MR_USHORT\s+vp_frame_count;', view):
        problems.append('MR_VIEW.H vp_frame_count is no longer MR_USHORT')
    hs = stack.squash((c_root / 'HSView.c').read_text(encoding='latin-1'))
    for snippet in (
            'High_score_view_water_prim_colours[2]={0x00406060,//surface0x00303030//riverbed};',
            'MRSetDisplayClearColour(0,0,0);',
            'texture->te_tpage_id|=(1<<8);',
            'MR_COPY32(poly_ft4->r0,High_score_view_water_prim_colours[0]);setPolyFT4(poly_ft4);'
            'setSemiTrans(poly_ft4,1);',
            'poly_ft4->u0=texture->te_u0+((texture->te_w*(i+0))/HIGH_SCORE_VIEW_WATER_X_NUM);',
            'poly_ft4->u1=texture->te_u0+((texture->te_w*(i+1))/HIGH_SCORE_VIEW_WATER_X_NUM);',
            'poly_ft4->u2=texture->te_u0+((texture->te_w*(i+0))/HIGH_SCORE_VIEW_WATER_X_NUM);',
            'poly_ft4->u3=texture->te_u0+((texture->te_w*(i+1))/HIGH_SCORE_VIEW_WATER_X_NUM);',
            'poly_ft4->v0=texture->te_v0+((texture->te_h*(j+0))/HIGH_SCORE_VIEW_WATER_Z_NUM);',
            'poly_ft4->v1=texture->te_v0+((texture->te_h*(j+0))/HIGH_SCORE_VIEW_WATER_Z_NUM);',
            'poly_ft4->v2=texture->te_v0+((texture->te_h*(j+1))/HIGH_SCORE_VIEW_WATER_Z_NUM);',
            'poly_ft4->v3=texture->te_v0+((texture->te_h*(j+1))/HIGH_SCORE_VIEW_WATER_Z_NUM);',
            'svec_ptr->vx=-((HIGH_SCORE_VIEW_WATER_X_LEN*HIGH_SCORE_VIEW_WATER_X_NUM)/2)+(i*HIGH_SCORE_VIEW_WATER_X_LEN);'
            'svec_ptr->vy=0;'
            'svec_ptr->vz=((HIGH_SCORE_VIEW_WATER_Z_LEN*HIGH_SCORE_VIEW_WATER_Z_NUM)/2)-(j*HIGH_SCORE_VIEW_WATER_Z_LEN);',
            'svec_ptr->vx=-((HIGH_SCORE_VIEW_RIVERBED_X_LEN*HIGH_SCORE_VIEW_RIVERBED_X_NUM)/2)+(i*HIGH_SCORE_VIEW_RIVERBED_X_LEN);'
            'svec_ptr->vy=0;'
            'svec_ptr->vz=((HIGH_SCORE_VIEW_RIVERBED_Z_LEN*HIGH_SCORE_VIEW_RIVERBED_Z_NUM)/2)-(j*HIGH_SCORE_VIEW_RIVERBED_Z_LEN);',
            'MR_COPY32(poly_ft4->r0,High_score_view_water_prim_colours[1]);setPolyFT4(poly_ft4);//Maptextureontoeachpoly'
            'if(j&1){MR_COPY16(poly_ft4->u0,texture->te_u0);MR_COPY16(poly_ft4->u1,texture->te_u1);'
            'MR_COPY16(poly_ft4->u2,texture->te_u2);MR_COPY16(poly_ft4->u3,texture->te_u3);}'
            'else{MR_COPY16(poly_ft4->u2,texture->te_u0);MR_COPY16(poly_ft4->u3,texture->te_u1);'
            'MR_COPY16(poly_ft4->u0,texture->te_u2);MR_COPY16(poly_ft4->u1,texture->te_u3);}',
            't=Option_viewport_ptr->vp_frame_count;',
            'tx=((i*HIGH_SCORE_VIEW_WAVE_PERIOD_X)/HIGH_SCORE_VIEW_WATER_X_NUM)+(t*HIGH_SCORE_VIEW_WAVE_FREQ_X);',
            'tz=((j*HIGH_SCORE_VIEW_WAVE_PERIOD_Z)/HIGH_SCORE_VIEW_WATER_Z_NUM)+(t*HIGH_SCORE_VIEW_WAVE_FREQ_Z);',
            'd=((rsin(tx)*HIGH_SCORE_VIEW_WAVE_AMP_X)+(rsin(tz)*HIGH_SCORE_VIEW_WAVE_AMP_Z))>>12;svec_ptr[0]->vy=d;',
            'svec_ptr[2]=&High_score_view_riverbed_points_ptr[HIGH_SCORE_VIEW_RIVERBED_X_NUM+1];',
            'svec_ptr[3]=&High_score_view_riverbed_points_ptr[HIGH_SCORE_VIEW_RIVERBED_X_NUM+2];',
            'addPrim(Option_viewport_ptr->vp_work_ot+Option_viewport_ptr->vp_ot_size-1,poly_ft4);',
            'svec_ptr[2]=&High_score_view_water_points_ptr[HIGH_SCORE_VIEW_WATER_X_NUM+1];',
            'svec_ptr[3]=&High_score_view_water_points_ptr[HIGH_SCORE_VIEW_WATER_X_NUM+2];',
            'addPrim(Option_viewport_ptr->vp_work_ot+Option_viewport_ptr->vp_ot_size-3,poly_ft4);',
            'camera->ca_mode=CAMERA_MODE_FIXED_SWEEP;camera->ca_move_timer=MAX(1,camera->ca_move_timer);'
            'UpdateCamera(camera);',
            'Cameras[0].ca_current_source_ofs.vz=(Frogs[0].fr_lwtrans->t[2]+1152)+OPTIONS_CAMERA_MAIN_SOURCE_OFS_Z;',
            'Cameras[0].ca_current_target_ofs.vz=(Frogs[0].fr_lwtrans->t[2]+1152)+OPTIONS_CAMERA_MAIN_TARGET_OFS_Z;',
            'HSUpdateScrollyCamera();//Riverbedandwater HSUpdateWater();'):
        if stack.squash(snippet) not in hs:
            problems.append('HSView.c no longer contains: %s' % snippet[:90])
    if hs.count('->vy=d;') != 1 or 'svec_ptr[0]=&High_score_view_water_points_ptr[0];t=' not in hs:
        problems.append('HSView.c riverbed heights are no longer fixed at 0')
    tempopt = stack.squash((c_root / 'tempopt.c').read_text(encoding='latin-1'))
    for snippet in (
            'HSInitialiseWater(&im_opt_env_sky,&im_opt_bank3);//Setupcurrentpositionofwatercamera'
            'InitialiseOptionsCamera();',
            'Option_viewport_ptr->vp_camera=Option_camera_ptr;'
            'Option_viewport_ptr->vp_perspective=HIGH_SCORE_VIEW_PERSPECTIVE;'
            'gte_SetGeomScreen(HIGH_SCORE_VIEW_PERSPECTIVE);camera=&Cameras[0];'
            'InitialiseCamera(camera,Option_viewport_ptr);camera->ca_offset_origin=&Null_vector;'
            'OptionsCameraSnapToMain();',
            'camera->ca_move_timer=OPTIONS_CAMERA_MOVE_TIME;'):
        if stack.squash(snippet) not in tempopt:
            problems.append('tempopt.c no longer contains: %s' % snippet[:90])
    cam = stack.squash((c_root / 'camera.c').read_text(encoding='latin-1'))
    for snippet in (
            'caseCAMERA_MODE_FIXED_SWEEP://Fixedsweepwithnocameramodificationmatrix////Evaluatecurrentoffsets'
            'if(!(--camera->ca_move_timer))',
            'd=(camera->ca_next_source_ofs.vx-camera->ca_current_source_ofs.vx)/camera->ca_move_timer;'
            'camera->ca_current_source_ofs.vx+=d;',
            'cam_matrix->t[0]=camera->ca_offset_origin->vx+camera->ca_current_source_ofs.vx;',
            'MRPointMatrixAtVector(matrix,target,&Game_y_axis_pos);'):
        if stack.squash(snippet) not in cam:
            problems.append('camera.c no longer contains: %s' % snippet[:90])
    hsinput = stack.squash((c_root / 'hsinput.c').read_text(encoding='latin-1'))
    if stack.squash('Option_viewport_ptr->vp_perspective = HIGH_SCORE_VIEW_PERSPECTIVE;') not in hsinput:
        problems.append('hsinput.c no longer sets the high-score perspective')
    select = stack.squash((c_root / 'SELECT.C').read_text(encoding='latin-1'))
    for snippet in ('Option_viewport_ptr->vp_perspective=1000;',
                    'Option_viewport_ptr->vp_camera=Sel_camera_frame;', 'HSUpdateWater();'):
        if snippet not in select:
            problems.append('SELECT.C no longer contains: %s' % snippet)
    mrview = stack.squash((c_root / 'API.SRC' / 'MR_VIEW.C').read_text(encoding='latin-1'))
    if 'viewport->vp_frame_count=0;' not in mrview or 'vp->vp_frame_count++;' not in mrview:
        problems.append('MR_VIEW.C frame counter reset or increment differs')
    options = stack.squash((c_root / 'OPTIONS.C').read_text(encoding='latin-1'))
    if 'MRRenderViewport(Option_viewport_ptr);' not in options or \
            'Option_viewport_ptr=MRCreateViewport(NULL,NULL,MR_VP_SIZE_4096,1);' not in options:
        problems.append('OPTIONS.C options viewport creation or render differs')
    sources = {}
    for page, update, _cam, source, _note in PAGES:
        name, line = source.split(':')
        if name not in sources:
            sources[name] = (c_root / name).read_text(encoding='latin-1').splitlines()
        lines = sources[name]
        if 'HSUpdateWater();' not in lines[int(line) - 1]:
            problems.append('%s does not call HSUpdateWater (%s)' % (source, page))
        function = update.split(' -> ')[-1]
        owner = [l for l in lines[:int(line)] if re.match(r'MR_VOID\s+\w+\s*\(', l)][-1]
        if function not in owner:
            problems.append('%s is in %s, not %s' % (source, owner.strip(), function))
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
        old = WATER_JSON.read_text(encoding='utf-8') if WATER_JSON.exists() else ''
        if old != text:
            sys.stdout.writelines(difflib.unified_diff(old.splitlines(True), text.splitlines(True),
                                                       str(WATER_JSON), 'generated', n=0))
        print('Committed facts differ from the generator' if old != text else 'Committed facts match the generator')
        sys.exit(1 if old != text else 0)
    WATER_JSON.write_text(text, encoding='utf-8')
    print('Wrote %s' % WATER_JSON.relative_to(ROOT))


if __name__ == '__main__':
    main()
