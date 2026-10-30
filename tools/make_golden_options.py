#!/usr/bin/env python3
"""Independent front-end options page facts from the frozen C and retail measurements.

Transcribes OptionsStartup, OptionsUpdate, OptionsUpdateFrog and
OptionsSetupVolumeLogAnimatedPolys (tempopt.c), HSUpdateFlying and
HSProjectMatricesOntoWaterSurface (HSView.c) and the tempopt.h/HSView.h
defines, with the retail PC four-row layout from froggy KEY_FACTS KF-110.
Scripted input runs are replayed through an independent model of the page's
30 Hz update over the port's rows. See
tests/golden/specs/frontend.md#options-page.
"""
import argparse
import difflib
from pathlib import Path
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_golden_frontend as frontend
import make_golden_stack as stack

ROOT = frontend.ROOT
OPTIONS_JSON = frontend.GOLDEN / 'synthetic' / 'frontend_options.json'

SOUND_STAGES = 8
START_MUSIC, START_SOUND = 3, 5
VOLUME_SCALE = 127
FROG_JUMP_TIME = 12
FLYON_TIME, FLYOFF_TIME = 10, 10
FLYON_SPEED, FLYOFF_SPEED = 0xa0, 0x100
FLYON_HEIGHT = -(FLYON_TIME * FLYON_SPEED)
MOVE_TIME = FLYOFF_TIME + FLYON_TIME
PROMPT_STEP = 10
GLOW_IDLE = 0x20
LOG_CELS = {'blank': 10, 'full': 11, 'half': 12}
CONTROLS_CAMERA = ((1500, -2400, -1000), (0, 0, 0))

VENDORED_ROWS = ['EXIT', 'VIEW_HIGH_SCORES', 'LOAD_HS', 'SAVE_HS', 'CTRL_CONFIG', 'MUSIC', 'FX']
VENDORED_NUM_OPTIONS, VENDORED_NUM_EXTRAS, VENDORED_PITCH = 7, 7, 0x180
RETAIL_NUM_OPTIONS, RETAIL_NUM_EXTRAS, RETAIL_PITCH = 4, 6, 0x200
RETAIL_TITLES, RETAIL_LOGS_DRAWN, RETAIL_LOGS_ALLOCATED = 3, 1, 2
RETAIL_MEASURED = {'title_z': [0x2c0, 0x0c0, -0x140], 'log_z': [-0x340]}
LILY_X, LOG_X, TITLE_X_BASE = -0x380, 0, -0x200
Z_BASE = -7 * 0xc0
SCALES = {'lily': 0x1600, 'log': 0x1300, 'title': [0x1000, 0x1400, 0x1000], 'frog': 0x1400, 'extras': 0x1800,
          'title_sprite': 10 << 16, 'splash_sprite': 10 << 16}

PORT_ROWS = ['exit', 'view_scores', 'controls', 'music', 'effects']
EVENTS = ['hop', 'splash', 'volume_step', 'croak', 'volume_test_sound', 'stop_test_sound',
          'back', 'controls', 'view_scores', 'leave']
HELD, PRESSED = ('up', 'down'), ('left', 'right', 'fire', 'back')


def cdiv(a, b):
    return stack.cdiv(a, b)


def lily_z(rows, pitch, index):
    """OptionsStartup: z = (-7 * 0xc0) + ((rows - i) * pitch)."""
    return Z_BASE + (rows - index) * pitch


def volume_level(step):
    """MRSNDSetVolumeLevel argument: (127 * volume) / OPTIONS_SOUND_STAGES."""
    return cdiv(VOLUME_SCALE * step, SOUND_STAGES)


def log_cels(volume):
    """OptionsSetupVolumeLogAnimatedPolys: the cel of stages 1..8."""
    cels = []
    for stage in range(1, SOUND_STAGES + 1):
        if volume == 0 or stage > volume:
            cels.append(LOG_CELS['blank'])
        elif stage == volume:
            cels.append(LOG_CELS['half'])
        else:
            cels.append(LOG_CELS['full'])
    return cels


def jump_lift(count):
    """OptionsUpdateFrog: dy = (-8 << 16) * (6^2 - (count - 6)^2), count before the decrement."""
    half = FROG_JUMP_TIME >> 1
    return -8 * (half * half - (count - half) * (count - half))


def port_rows(scores_available):
    return [r for r in PORT_ROWS if scores_available or r != 'view_scores']


class Page:
    """OptionsUpdate over the port's rows; one call to tick() is one 30 Hz update."""

    def __init__(self, scores_available, music, effects, start_row):
        self.rows = port_rows(scores_available)
        self.row = self.rows.index(start_row)
        self.jumping = False
        self.count = 0
        self.lift = 0
        self.volume = {'music': music, 'effects': effects}
        self.fly_on, self.fly_off = FLYON_TIME, 0
        self.camera, self.camera_timer = 'OPTIONS', FLYON_TIME
        self.request = None
        self.finished = False
        self.test_sound = False
        self.glow = {'music': GLOW_IDLE, 'effects': GLOW_IDLE}

    def state(self, tick, inputs, events):
        return {'tick': tick, 'input': inputs, 'row': self.rows[self.row],
                'frog': 'JUMPING' if self.jumping else 'STATIONARY', 'count': self.count, 'lift': self.lift,
                'music': self.volume['music'], 'effects': self.volume['effects'],
                'glow': [self.glow['music'], self.glow['effects']], 'fly_on': self.fly_on, 'fly_off': self.fly_off,
                'camera': self.camera, 'camera_timer': self.camera_timer, 'test_sound': self.test_sound,
                'request': self.request, 'events': events}

    def _leave_via(self, request, camera, events):
        self.request = request
        self.fly_off = FLYOFF_TIME
        self.camera, self.camera_timer = camera, MOVE_TIME
        self.fly_on = 0
        events.append('back' if request == 'MAIN_MENU' else 'controls')

    def tick(self, inputs, frame):
        events = []
        self.camera_timer = max(1, self.camera_timer) - 1
        if self.fly_on:
            self.fly_on -= 1
        if self.fly_off:
            self.fly_off -= 1
            if not self.fly_off:
                self.finished = True
                events.append('leave')
        self.glow = {'music': GLOW_IDLE, 'effects': GLOW_IDLE}
        self._frog(inputs, events)
        if self.request is not None or self.finished:
            return events
        if 'back' in inputs and not self.fly_off and not self.fly_on:
            if self.test_sound:
                self.test_sound = False
                events.append('stop_test_sound')
            events.append('croak')
            self._leave_via('MAIN_MENU', 'MAIN', events)
            return events
        if self.jumping:
            return events
        name = self.rows[self.row]
        if name in self.volume:
            self.glow[name] = (frame & 7) << 5
            if 'right' in inputs:
                if self.volume[name] < SOUND_STAGES:
                    self.volume[name] += 1
                    events.append('volume_step')
            elif 'left' in inputs:
                if self.volume[name]:
                    self.volume[name] -= 1
                    events.append('volume_step')
        if 'fire' in inputs and not self.fly_off and not self.fly_on:
            events.append('croak')
            if name == 'exit':
                self._leave_via('MAIN_MENU', 'MAIN', events)
            elif name == 'controls':
                self._leave_via('CONTROLS', 'CONTROLS', events)
            elif name == 'view_scores':
                self.request = 'VIEW_SCORES'
                self.finished = True
                events.extend(['view_scores', 'leave'])
        return events

    def _frog(self, inputs, events):
        if not self.jumping:
            self.lift = 0
            old = self.row
            if 'up' in inputs and self.row > 0:
                self.row -= 1
            elif 'down' in inputs and self.row < len(self.rows) - 1:
                self.row += 1
            if self.row != old:
                self.jumping = True
                self.count = FROG_JUMP_TIME
                events.append('hop')
                if self.rows[old] == 'effects' and self.test_sound:
                    self.test_sound = False
                    events.append('stop_test_sound')
            return
        self.lift = jump_lift(self.count)
        self.count -= 1
        if not self.count:
            self.jumping = False
            self.lift = 0
            events.append('splash')
            if self.rows[self.row] == 'effects':
                self.test_sound = True
                events.append('volume_test_sound')


SCENARIOS = [
    ('walk_volumes_and_controls', 'hidden scores row; fire ignored during fly-on; held DOWN hops every 13 ticks; '
     'Right/Left edges with clamp at 8; fire on a volume row only croaks; leaving effects stops the test sound; '
     'fire on controls flies off to the controller page',
     False, 3, 5, 'exit', 5,
     [[4, []], [1, ['fire']], [5, []], [14, ['down']], [11, []], [1, ['right']], [1, []], [1, ['right']],
      [1, ['left']], [1, ['fire']], [1, ['down']], [12, []], [1, ['right']], [1, ['right']], [1, ['right']],
      [1, ['right']], [1, ['left', 'right']], [2, []], [1, ['up']], [13, ['up']], [1, ['fire']], [11, []],
      [1, ['fire']], [10, []]]),
    ('back_during_fly_and_hop_during_fly_off', 'starts on music; back ignored during fly-on but Right is not; '
     'back accepted after fly-on; Right ignored while leaving; the frog still hops during fly-off; the page '
     'leaves on the tenth fly-off tick',
     False, 3, 5, 'music', 1000,
     [[3, ['back']], [1, ['right']], [6, []], [1, ['back']], [2, ['right']], [1, ['up']], [7, []]]),
    ('exit_row_and_low_clamp', 'Left at 0 changes nothing; Right and Left on one tick takes Right; the exit row '
     'leaves to the main menu',
     False, 0, 0, 'exit', 0,
     [[10, []], [1, ['down']], [12, []], [1, ['down']], [12, []], [1, ['left']], [1, ['right', 'left']],
      [1, ['left']], [1, ['left']], [1, ['up']], [12, []], [1, ['up']], [12, []], [1, ['fire']], [10, []]]),
    ('scores_row_available', 'with the high-score row shown, fire on it requests the view at once without a '
     'fly-off',
     True, 3, 5, 'exit', 7,
     [[10, []], [1, ['down']], [11, []], [1, ['fire']], [1, []], [1, ['fire']]]),
]


def replay(scores_available, music, effects, start_row, frame_start, runs):
    page = Page(scores_available, music, effects, start_row)
    trace = [page.state(0, [], [])]
    tick = 0
    for count, inputs in runs:
        for _ in range(count):
            if page.finished:
                return trace
            tick += 1
            events = page.tick(inputs, frame_start + tick - 1)
            trace.append(page.state(tick, list(inputs), events))
    return trace


def document():
    retail_lily_z = [lily_z(RETAIL_NUM_OPTIONS, RETAIL_PITCH, i) for i in range(RETAIL_NUM_OPTIONS)]
    if retail_lily_z[:RETAIL_TITLES] != RETAIL_MEASURED['title_z'] or \
            retail_lily_z[RETAIL_TITLES:] != RETAIL_MEASURED['log_z']:
        sys.exit('the vendored z formula with the retail row count and pitch misses the measured positions')
    scenarios = []
    for name, description, scores, music, effects, start_row, frame_start, runs in SCENARIOS:
        for _count, inputs in runs:
            for item in inputs:
                if item not in HELD + PRESSED:
                    sys.exit('unknown input %s' % item)
        trace = replay(scores, music, effects, start_row, frame_start, runs)
        if not trace[-1]['events'] or trace[-1]['events'][-1] != 'leave':
            sys.exit('scenario %s does not end by leaving the page' % name)
        scenarios.append({'name': name, 'description': description, 'scores_available': scores,
                          'music': music, 'effects': effects, 'start_row': start_row, 'frame_start': frame_start,
                          'inputs': runs, 'trace': trace})
    return {
        'constants': {
            'sound_stages': SOUND_STAGES, 'start_music': START_MUSIC, 'start_sound': START_SOUND,
            'volume_scale': VOLUME_SCALE, 'frog_jump_time': FROG_JUMP_TIME,
            'fly_on_time': FLYON_TIME, 'fly_off_time': FLYOFF_TIME, 'fly_on_speed': FLYON_SPEED,
            'fly_off_speed': FLYOFF_SPEED, 'fly_on_height': FLYON_HEIGHT, 'camera_move_time': MOVE_TIME,
            'prompt_step': PROMPT_STEP, 'glow_idle': GLOW_IDLE, 'glow_rule': '(vp_frame_count & 7) << 5',
            'log_cels': LOG_CELS},
        'volume_levels': [volume_level(v) for v in range(SOUND_STAGES + 1)],
        'volume_log_cels': [log_cels(v) for v in range(SOUND_STAGES + 1)],
        'jump_lift': [jump_lift(c) for c in range(FROG_JUMP_TIME, 0, -1)],
        'cameras': {'CONTROLS': {'source': list(CONTROLS_CAMERA[0]), 'target': list(CONTROLS_CAMERA[1]),
                                 'timer': MOVE_TIME},
                    'MAIN': {'preset': 'MAIN', 'timer': MOVE_TIME}, 'OPTIONS': {'preset': 'OPTIONS',
                                                                                'timer_at_startup': FLYON_TIME}},
        'retail': {
            'rows': RETAIL_NUM_OPTIONS, 'extras': RETAIL_NUM_EXTRAS, 'row_pitch': RETAIL_PITCH,
            'titles': RETAIL_TITLES, 'logs_drawn': RETAIL_LOGS_DRAWN, 'logs_allocated': RETAIL_LOGS_ALLOCATED,
            'lily_x': LILY_X, 'lily_z': retail_lily_z, 'title_z': RETAIL_MEASURED['title_z'],
            'log_x': LOG_X, 'log_z': RETAIL_MEASURED['log_z'], 'title_x': '-0x200 + (te_w >> 1) * 8',
            'start_y': FLYON_HEIGHT, 'scales': SCALES, 'reference': 'KEY_FACTS KF-110'},
        'vendored': {'rows': VENDORED_ROWS, 'extras': VENDORED_NUM_EXTRAS, 'row_pitch': VENDORED_PITCH,
                     'logs': 2, 'lily_z': [lily_z(VENDORED_NUM_OPTIONS, VENDORED_PITCH, i)
                                           for i in range(VENDORED_NUM_OPTIONS)]},
        'undecoded': {
            'row_identities': 'retail OptionsUpdate was not disassembled; the port puts exit, view high scores and '
                              'controller config on the three titled lilies top to bottom, as the vendored enum '
                              'orders them with load/save removed',
            'volume_log': 'retail draws one log on the fourth lily with the effects model (OPT_SFX) beside it, so '
                          'its volume row is the effects volume; the port shows two volume rows, music then effects',
            'port_rows': port_rows(True),
            'port_rows_without_scores': port_rows(False),
            'port_lily_z': '0x2c0 - row * 0x200 over the shown rows; with the scores row hidden it is the retail '
                           'four-lily layout'},
        'events': EVENTS,
        'scenarios': scenarios,
    }


def check_c(c_root):
    """Compare the transcriptions above with the frozen C; returns problems."""
    problems = []
    t = (c_root / 'tempopt.h').read_text(encoding='latin-1')
    for name, value in (('OPTIONS_SOUND_STAGES', '8'), ('OPTION_START_MUSIC_VALUE', '3'),
                        ('OPTION_START_SOUND_VALUE', '5'), ('OPTIONS_NUM_OPTIONS', '7'),
                        ('OPTIONS_NUM_EXTRAS', '7'), ('OPTIONS_CAMERA_FLYOFF_TIME', '10'),
                        ('OPTIONS_CAMERA_FLYON_TIME', '10'), ('OPTIONS_CAMERA_FLYOFF_SPEED', '0x100'),
                        ('OPTIONS_CAMERA_FLYON_SPEED', '0xa0'),
                        ('OPTIONS_CAMERA_FLYON_HEIGHT', '-((OPTIONS_CAMERA_FLYON_TIME+0)*OPTIONS_CAMERA_FLYON_SPEED)'),
                        ('OPTIONS_CAMERA_MOVE_TIME', '(OPTIONS_CAMERA_FLYOFF_TIME+OPTIONS_CAMERA_FLYON_TIME)')):
        if stack.define(t, name) != value:
            problems.append('tempopt.h %s is %s, transcribed %s' % (name, stack.define(t, name), value))
    if 'enum{%s,};' % ','.join('OPTIONS_%s_OPTION' % r for r in VENDORED_ROWS) not in stack.squash(t):
        problems.append('tempopt.h option row enum differs from the transcription')
    h = (c_root / 'HSView.h').read_text(encoding='latin-1')
    if stack.define(h, 'HIGH_SCORE_VIEW_FROG_JUMP_TIME') != str(FROG_JUMP_TIME):
        problems.append('HSView.h HIGH_SCORE_VIEW_FROG_JUMP_TIME differs')
    tempopt = stack.squash((c_root / 'tempopt.c').read_text(encoding='latin-1'))
    for snippet in (
            'High_score_view_number_matrix_ptr[i]->t[0]=-0x380;'
            'High_score_view_number_matrix_ptr[i]->t[1]=OPTIONS_CAMERA_FLYON_HEIGHT;'
            'High_score_view_number_matrix_ptr[i]->t[2]=(-7*0xc0)+(((OPTIONS_NUM_OPTIONS-0)-i)*0x180);',
            'High_score_view_log_matrix_ptr[i]->t[0]=0;',
            'High_score_view_initials_matrix_ptr[i]->t[0]=-0x200+((Options_title_textures[Game_language][i]->te_w>>1)*0x8);',
            'High_score_view_initials_object_ptr[i]->ob_extra.ob_extra_sp_core->sc_scale=(10<<16);',
            'if(From_options==TRUE){From_options=FALSE;Options_current_selection=0;}',
            'frog->fr_grid_z=Options_current_selection;',
            'High_score_view_flyon_counter=OPTIONS_CAMERA_FLYON_TIME;High_score_view_flyoff_counter=0;'
            'High_score_view_delayed_request=NULL;Cameras[0].ca_move_timer=OPTIONS_CAMERA_FLYON_TIME;',
            'HSUpdateScrollyCamera();//RiverbedandwaterHSUpdateWater();HSUpdateFlying();',
            'MRScale_matrix.m[0][0]=0x1600;',
            'MRScale_matrix.m[0][0]=0x1300;',
            'MRScale_matrix.m[0][0]=0x1000;MRScale_matrix.m[1][1]=0x1400;MRScale_matrix.m[2][2]=0x1000;',
            'MRScale_matrix.m[0][0]=0x1800;',
            'Options_extras_mesh_inst_ptr[0]->mi_custom_ambient.r=0x20;',
            'Options_extras_mesh_inst_ptr[1]->mi_custom_ambient.r=0x20;',
            'if(High_score_view_flyon_counter!=0)Options_extras_user_prompt_ptr->sp_pos.y-=10;'
            'if(High_score_view_flyoff_counter!=0)Options_extras_user_prompt_ptr->sp_pos.y+=10;',
            '//MovefrogOptionsUpdateFrog();UpdateEffects();//Ifwe\'reexiting,skipthefollowing'
            'if(High_score_view_delayed_request!=0||Option_page_request!=0)return;',
            'if((MR_CHECK_PAD_PRESSED(Frog_input_ports[0],FRR_TRIANGLE|FRR_START))&&'
            '(High_score_view_flyoff_counter==0)&&(High_score_view_flyon_counter==0))',
            'High_score_view_delayed_request=OPTIONS_PAGE_MAIN_OPTIONS;High_score_view_flyoff_counter='
            'OPTIONS_CAMERA_FLYOFF_TIME;//StartmovingcameraNOWOptionsCameraMoveToMain();',
            'caseOPTION_UPDATE_MODE_MAIN://Accordingtocurrentlillydoupdateif(frog->fr_mode==FROG_MODE_STATIONARY)',
            'Options_extras_mesh_inst_ptr[1]->mi_custom_ambient.r=(Option_viewport_ptr->vp_frame_count&0x7)<<5;',
            'Options_extras_mesh_inst_ptr[0]->mi_custom_ambient.r=(Option_viewport_ptr->vp_frame_count&0x7)<<5;',
            'if(MR_CHECK_PAD_PRESSED(Frog_input_ports[0],FRR_RIGHT)){if(Sound_volume<OPTIONS_SOUND_STAGES)'
            '{Sound_volume++;MRSNDPlaySound(SFX_GEN_FROG_HOP,NULL,0,0);',
            'elseif(MR_CHECK_PAD_PRESSED(Frog_input_ports[0],FRR_LEFT)){if(Sound_volume){Sound_volume--;'
            'MRSNDPlaySound(SFX_GEN_FROG_HOP,NULL,0,0);',
            'if(MR_CHECK_PAD_PRESSED(Frog_input_ports[0],FRR_RIGHT)){if(Music_volume<OPTIONS_SOUND_STAGES)'
            '{Music_volume++;MRSNDPlaySound(SFX_GEN_FROG_HOP,NULL,0,0);',
            'elseif(MR_CHECK_PAD_PRESSED(Frog_input_ports[0],FRR_LEFT)){if(Music_volume){Music_volume--;'
            'MRSNDPlaySound(SFX_GEN_FROG_HOP,NULL,0,0);',
            'MRSNDSetVolumeLevel(MRSND_FX_VOLUME,(127*Sound_volume)/OPTIONS_SOUND_STAGES);',
            'MRSNDSetVolumeLevel(MRSND_CD_VOLUME,(127*Music_volume)/OPTIONS_SOUND_STAGES);',
            'if(MR_CHECK_PAD_PRESSED(Frog_input_ports[0],FRR_CROSS)&&High_score_view_flyoff_counter==0&&'
            'High_score_view_flyon_counter==0){MRSNDPlaySound(SFX_GEN_FROG_CROAK,NULL,0,0);',
            'Option_page_request=OPTIONS_PAGE_HIGH_SCORE_VIEW;',
            'High_score_view_delayed_request=OPTIONS_PAGE_CHOOSE_WIN_CONTROLLER;#endif//StartmovingcameraNOW'
            'MR_SET_SVEC(&Cameras[0].ca_next_source_ofs,1500,-2400,-1000);'
            'MR_SET_SVEC(&Cameras[0].ca_next_target_ofs,0,0,0);Cameras[0].ca_move_timer=OPTIONS_CAMERA_MOVE_TIME;'
            'High_score_view_flyoff_counter=OPTIONS_CAMERA_FLYOFF_TIME;High_score_view_flyon_counter=0;',
            '(MR_CHECK_PAD_HELD(Frog_input_ports[0],FRR_UP))&&(frog->fr_grid_z>0)',
            'elseif((MR_CHECK_PAD_HELD(Frog_input_ports[0],FRR_DOWN))&&'
            '(frog->fr_grid_z<(OPTIONS_NUM_OPTIONS-1)))',
            'frog->fr_mode=FROG_MODE_JUMPING;frog->fr_count=HIGH_SCORE_VIEW_FROG_JUMP_TIME;',
            'caseOPTIONS_FX_OPTION:MRSNDKillSound(Sound_voice);Sound_voice=-1;break;',
            'dy=(-8<<16)*(MR_SQR(HIGH_SCORE_VIEW_FROG_JUMP_TIME>>1)-MR_SQR(frog->fr_count-'
            '(HIGH_SCORE_VIEW_FROG_JUMP_TIME>>1)));',
            'if(!(--frog->fr_count)){//Jumpcomplete',
            'caseOPTIONS_FX_OPTION:Sound_voice=MRSNDPlaySound(SFX_GEN_FROG_CROAK_REPEAT,NULL,0,0);',
            'Options_current_selection=frog->fr_grid_z;if(High_score_view_flyoff_counter)'
            '{frog->fr_pos.vx-=(OPTIONS_CAMERA_FLYOFF_SPEED<<16);',
            'if(volume==0){i=1;}',
            'MRMeshAnimatedPolySetCel(mesh_ptr,High_score_log_animated_poly_indices[(i-1)]+k,12);i++;break;',
            'MRMeshAnimatedPolySetCel(mesh_ptr,High_score_log_animated_poly_indices[(i-1)]+k,11);',
            'MRMeshAnimatedPolySetCel(mesh_ptr,High_score_log_animated_poly_indices[(i-1)]+k,10);',
            'From_options=TRUE;OptionKill3DSprites();'):
        if stack.squash(snippet) not in tempopt:
            problems.append('tempopt.c no longer contains: %s' % snippet[:90])
    hs = stack.squash((c_root / 'HSView.c').read_text(encoding='latin-1'))
    for snippet in (
            'if(High_score_view_flyon_counter)High_score_view_flyon_counter--;'
            'if(High_score_view_flyoff_counter){if(!(--High_score_view_flyoff_counter))'
            'Option_page_request=High_score_view_delayed_request;}',
            'matrix_ptr->t[1]+=OPTIONS_CAMERA_FLYON_SPEED;if(matrix_ptr->t[1]>=h){//Hitwatermatrix_ptr->t[1]=h;}',
            'if(matrix_ptr->t[0]<0)matrix_ptr->t[0]-=OPTIONS_CAMERA_FLYOFF_SPEED;'
            'elsematrix_ptr->t[0]+=OPTIONS_CAMERA_FLYOFF_SPEED;',
            'if(!High_score_view_flyon_counter)matrix_ptr->t[1]=h;'):
        if stack.squash(snippet) not in hs:
            problems.append('HSView.c no longer contains: %s' % snippet[:90])
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
        old = OPTIONS_JSON.read_text(encoding='utf-8') if OPTIONS_JSON.exists() else ''
        if old != text:
            sys.stdout.writelines(difflib.unified_diff(old.splitlines(True), text.splitlines(True),
                                                       str(OPTIONS_JSON), 'generated', n=0))
        print('Committed facts differ from the generator' if old != text else 'Committed facts match the generator')
        sys.exit(1 if old != text else 0)
    OPTIONS_JSON.write_text(text, encoding='utf-8')
    print('Wrote %s' % OPTIONS_JSON.relative_to(ROOT))


if __name__ == '__main__':
    main()
