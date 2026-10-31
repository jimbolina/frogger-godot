#!/usr/bin/env python3
"""Independent high-score name-entry page facts from the frozen C.

Transcribes HighScoreInputStartup, HighScoreInputUpdate, HSInputInitialiseCamera
and HSInputUpdateFrog (hsinput.c) with the HSINPUT.H defines, the poly-piece
pop timer (FROG.C, EFFECTS.C) and the retail PC sound ids of froggy KEY_FACTS
ruling R11. Scripted input runs are replayed through an independent model of
the page's 30 Hz update for player 0. See
tests/golden/specs/frontend.md#high-score-entry.
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
import make_golden_stack as stack

ROOT = frontend.ROOT
ENTRY_JSON = frontend.GOLDEN / 'synthetic' / 'frontend_high_score_entry.json'
FROGLORD_SOUNDS = ROOT / 'third_party' / 'froglord_cfg' / 'sounds' / '1997-11-19-pc-retail.cfg'
FROGLORD_ANIMS = ROOT / 'third_party' / 'froglord_cfg' / 'anims' / 'main-pc.cfg'

NUM_EXTRAS = 6
NUM_INITIALS = 3
FROG_JUMP_TIME = 6
LETTER_RUB, LETTER_END = 28, 29
LETTER_DOT, LETTER_SPACE = 26, 27
COLUMNS, ROWS = 10, 3
PAD_COUNT = COLUMNS * ROWS
FLIP_STEP, FLIP_SWAP, FLIP_RESUME = 0x100, 0x500, -0x300
POP_DURATION = 32
PAD_SCALE, FROG_SCALE = 0x1300, 0x1400
PERSPECTIVE = 0x100
CAMERA_SOURCE, CAMERA_TARGET = (0, -2400, -256), (0, 1024, 0)
DIRECTIONS = ['N', 'E', 'S', 'W']
FROG_ACTIONS = ['GENM_FROG_HOP', 'GENM_FROG_SIT']

PAD_RESOURCES = ['RES_HI_%s_XMR' % chr(ord('A') + i) for i in range(26)] + [
    'RES_HI_DOT_XMR', 'RES_OPT_LILLYPAD_BLANK_XMR', 'RES_HI_BACK_XMR', 'RES_HI_END_XMR']
EXTRA_RESOURCES = ['RES_OPT_STAT_BULLRUSH_XMR', 'RES_OPT_STAT_LILLY_XMR', 'RES_OPT_STAT_LILLY_XMR',
                   'RES_OPT_STAT_LILLY_XMR', 'RES_OPT_STAT_BULLRUSH_XMR', 'RES_OPT_STAT_BULLRUSH_XMR']
EXTRA_COORDS = [(-0x400, -0x040), (-0x280, -0x200), (0x480, -0x240), (0x400, -0x080), (0x240, -0x300),
                (-0x300, -0x380)]
BLANK_RESOURCE = 'RES_OPT_LILLYPAD_BLANK_XMR'

SOUNDS = {
    'hop': ('SFX_GEN_FROG_HOP', 6, 'GEN_FROG_HOP'),
    'splash': ('SFX_GEN_FROG_SPLASH1', 15, 'GEN_SPLASH01'),
    'letter': ('SFX_GEN_FROG_CROAK', 3, 'GEN_FROG_CROAK'),
    'rub': ('SFX_GEN_FROG_FLY_GULP', 5, 'GEN_FROG_FLY_GULP'),
    'end': ('SFX_GEN_FROG_EXPLODE', 17, 'GEN_FROG_EXPLODE'),
}

EVENTS = ['hop', 'splash', 'letter', 'rub', 'end', 'entered', 'no_high_score', 'game_quit']
INPUTS = ('up', 'down', 'left', 'right', 'fire')


def model_name(resource):
    """RES_HI_A_XMR -> HI_A.XMR, the FrogLord file name."""
    return resource[len('RES_'):-len('_XMR')] + '.XMR'


def pad_position(i):
    """HighScoreInputStartup: t[0] = ((i % 10) * 0x100) - 0x480, t[2] = (3 - (i / 10)) * 0x100."""
    return ((i % 10) * 0x100) - 0x480, (3 - (i // 10)) * 0x100


def initials_position(i, j):
    """HighScoreInputStartup: t[0] = (i * 0x100) - 0x100, t[2] = (j * -0x100) - 0x80."""
    return (i * 0x100) - 0x100, (j * -0x100) - 0x80


def character(letter):
    if letter < 26:
        return chr(letter + ord('A'))
    return {LETTER_DOT: '.', LETTER_SPACE: ' '}[letter]


def lift(count):
    """HSInputUpdateFrog: dy = (-8 << 16) * (3^2 - (count - 3)^2), count before the decrement."""
    half = FROG_JUMP_TIME >> 1
    return -8 * (half * half - (count - half) * (count - half))


class Page:
    """HighScoreInputStartup/Update for player 0; one call to tick() is one 30 Hz update."""

    def __init__(self, qualifies, quit_game, blocked):
        self.startup_events = []
        self.request = None
        self.grid_x, self.grid_z = 4 + (0 & 1), 1 + (0 >> 1)
        self.direction = (0 & 2) + 1
        self.mode = 'ACTIVE'
        self.count = 0
        self.lift = 0
        self.pos = 0
        self.initials = [' '] * NUM_INITIALS
        self.shown = [-1] * NUM_INITIALS
        self.angle = [0] * NUM_INITIALS
        self.turn = [0] * NUM_INITIALS
        self.new_mof = None
        self.flip_index = 0
        self.pop = 0
        self.blocked = set(blocked)
        if quit_game:
            self.request = 'MAIN_MENU'
            self.startup_events.append('game_quit')
        elif not qualifies:
            self.request = 'MAIN_MENU'
            self.startup_events.append('no_high_score')

    def letter(self):
        return self.grid_z * 10 + self.grid_x

    def state(self, tick, inputs, events):
        return {'tick': tick, 'input': inputs, 'cell': self.letter(), 'facing': DIRECTIONS[self.direction],
                'mode': self.mode, 'count': self.count, 'lift': self.lift, 'position': self.pos,
                'initials': ''.join(self.initials), 'pad_angle': list(self.angle), 'pad_turn': list(self.turn),
                'pad_letter': list(self.shown), 'pop_timer': self.pop, 'request': self.request, 'events': events}

    def tick(self, inputs):
        events = []
        self.turn = [self.angle[i] if self.new_mof is not None and self.flip_index == i else 0
                     for i in range(NUM_INITIALS)]
        if self.mode == 'ACTIVE':
            self._stationary(inputs, events)
        elif self.mode == 'JUMPING':
            self.lift = lift(self.count)
            self.count -= 1
            if self.count == 0:
                self.lift = 0
                self.mode = 'ACTIVE'
                events.append('splash')
        if self.pop:
            self.pop -= 1
        if self.new_mof is not None:
            i = self.flip_index
            self.angle[i] += FLIP_STEP
            if self.angle[i] == FLIP_SWAP:
                self.shown[i] = self.new_mof
                self.angle[i] = FLIP_RESUME
            elif self.angle[i] == 0:
                self.new_mof = None
        if self.mode == 'STUNNED' and self.pop <= 0:
            self.request = 'VIEW'
            events.append('entered')
        return events

    def _stationary(self, inputs, events):
        self.lift = 0
        jump = False
        old_x, old_z = self.grid_x, self.grid_z
        if 'up' in inputs and self.grid_z > 0:
            self.direction, self.grid_z, jump = 0, self.grid_z - 1, True
        elif 'down' in inputs and self.grid_z < 2:
            self.direction, self.grid_z, jump = 2, self.grid_z + 1, True
        elif 'left' in inputs and self.grid_x > 0:
            self.direction, self.grid_x, jump = 3, self.grid_x - 1, True
        elif 'right' in inputs and self.grid_x < 9:
            self.direction, self.grid_x, jump = 1, self.grid_x + 1, True
        elif self.new_mof is None and 'fire' in inputs:
            letter = self.letter()
            if letter == LETTER_RUB:
                if self.pos:
                    events.append('rub')
                    self.pos -= 1
                    self.initials[self.pos] = ' '
                    self.new_mof, self.flip_index, self.angle[self.pos] = -1, self.pos, 0
            elif letter == LETTER_END:
                events.append('end')
                self.pop = POP_DURATION
                self.mode = 'STUNNED'
            elif self.pos < 3:
                events.append('letter')
                self.initials[self.pos] = character(letter)
                self.new_mof, self.flip_index, self.angle[self.pos] = letter, self.pos, 0
                self.pos += 1
        if jump:
            if self.letter() in self.blocked:
                self.grid_x, self.grid_z = old_x, old_z
                return
            events.append('hop')
            self.mode = 'JUMPING'
            self.count = FROG_JUMP_TIME


SCENARIOS = [
    ('hop_timing_and_held_repeat', 'a held direction hops on the first tick and again on the tick after each '
     'landing (every 7 ticks); directions are ignored mid-hop; Up beats Down', True, False, [],
     [[1, []], [15, ['right']], [2, []], [7, ['down']], [4, []], [1, ['up', 'down']], [7, []],
     [1, ['left']], [6, ['up']], [1, []]]),
    ('blocked_edges_and_fall_through', 'a direction blocked by the grid edge falls through to the next test, so '
     'fire is read with Up held on the top row; END on the bottom-right pad after one letter; the view is '
     'requested when the 32-tick pop ends', True, False, [],
     [[8, ['up']], [6, ['up']], [28, ['left']], [3, ['left']], [1, ['up', 'left', 'fire']], [1, ['up', 'right']],
      [8, []], [1, ['down', 'up']], [6, []], [7, ['down']], [3, ['down']], [56, ['right']], [3, ['right']],
      [1, ['fire']], [31, []], [1, []]]),
    ('three_letters_with_flips', 'three letters including the dot, each flipping the next initials pad over 8 '
     'ticks with the model swapped at 0x500; a fourth letter is silently ignored; END with three letters',
     True, False, [],
     [[1, ['fire']], [7, []], [1, ['right']], [6, []], [1, ['fire']], [1, ['down']], [6, []], [1, ['right']],
      [6, []], [1, ['fire']], [8, []], [1, ['fire']], [1, []], [21, ['right']], [1, ['fire']], [31, []]]),
    ('back_at_zero_and_after_letters', 'BACK with nothing entered does nothing; a space is a letter showing the '
     'blank pad; BACK rubs it out and flips the pad back to blank; fire during that flip is ignored; END with '
     'no letters', True, False, [],
     [[1, ['down']], [6, []], [28, ['right']], [1, ['fire']], [1, ['left']], [6, []], [1, ['fire']], [8, []],
      [1, ['right']], [6, []], [1, ['fire']], [2, []], [1, ['fire']], [5, []], [1, ['fire']], [1, ['right']],
      [6, []], [1, ['fire']], [31, []]]),
    ('end_with_two_letters_and_fire_during_flip', 'fire during a flip is ignored while hops are not; END with '
     'two letters leaves the third a space', True, False, [],
     [[1, ['fire']], [2, []], [1, ['fire']], [1, ['up']], [10, []], [1, ['fire']], [1, []], [14, ['down']],
      [35, ['right']], [1, ['fire']], [31, []]]),
    ('occupied_pad_refused', 'a hop onto a pad another active frog holds (player 1 on P) is refused: the frog '
     'turns but stays and fire is not read that tick', True, False, [15],
     [[7, ['up']], [7, ['right']], [1, ['down', 'fire']], [1, ['fire']], [8, []], [7, ['right']],
      [14, ['down']], [21, ['right']], [1, ['fire']], [31, []]]),
    ('no_high_score', 'no qualifying score: startup requests the main options page and the update never runs',
     False, False, [], [[3, []], [1, ['fire']]]),
    ('game_quit', 'the game was quit from the pause menu: startup requests the main options page before '
     'testing scores', True, True, [], [[2, ['right']]]),
]


def replay(qualifies, quit_game, blocked, runs):
    page = Page(qualifies, quit_game, blocked)
    trace = [page.state(0, [], list(page.startup_events))]
    tick = 0
    for count, inputs in runs:
        for _ in range(count):
            if page.request is not None:
                return trace
            tick += 1
            events = page.tick(inputs)
            trace.append(page.state(tick, list(inputs), events))
    return trace


def document():
    scenarios = []
    for name, description, qualifies, quit_game, blocked, runs in SCENARIOS:
        for _count, inputs in runs:
            for item in inputs:
                if item not in INPUTS:
                    sys.exit('unknown input %s' % item)
            if 'fire' in inputs and _count != 1:
                sys.exit('scenario %s presses fire on consecutive ticks' % name)
        trace = replay(qualifies, quit_game, blocked, runs)
        scenarios.append({'name': name, 'description': description, 'qualifies': qualifies, 'quit': quit_game,
                          'blocked_cells': blocked, 'inputs': runs, 'trace': trace})
    pads = [[pad_position(i)[0], pad_position(i)[1], model_name(PAD_RESOURCES[i]),
             character(i) if i < LETTER_RUB else ('BACK' if i == LETTER_RUB else 'END')] for i in range(PAD_COUNT)]
    return {
        'constants': {
            'columns': COLUMNS, 'rows': ROWS, 'pads': PAD_COUNT, 'initials': NUM_INITIALS, 'extras': NUM_EXTRAS,
            'pad_dot': LETTER_DOT, 'pad_space': LETTER_SPACE, 'pad_rub': LETTER_RUB, 'pad_end': LETTER_END,
            'frog_jump_time': FROG_JUMP_TIME, 'flip_step': FLIP_STEP, 'flip_swap_angle': FLIP_SWAP,
            'flip_resume_angle': FLIP_RESUME, 'flip_ticks': (FLIP_SWAP + (0 - FLIP_RESUME)) // FLIP_STEP,
            'pop_duration': POP_DURATION, 'pad_scale': PAD_SCALE, 'frog_scale': FROG_SCALE,
            'blank_model': model_name(BLANK_RESOURCE),
            'sounds': {key: {'id': value[1], 'name': value[2], 'source': value[0]} for key, value in SOUNDS.items()},
            'frog_actions': {'start': 'GENM_FROG_SIT', 'hop': 'GENM_FROG_HOP', 'land': 'GENM_FROG_SIT',
                             'update_period': 2},
            'view_request': {'page': 'HIGH_SCORE_VIEW', 'automatic': True, 'operation_mode': 'LEVEL_SELECT',
                             'camera_mode': 'STATIC', 'from_options': False}},
        'jump_lift': [lift(c) for c in range(FROG_JUMP_TIME, 0, -1)],
        'layout': {
            'pads': pads,
            'initials_pads': [list(initials_position(i, j)) for j in range(4) for i in range(NUM_INITIALS)],
            'extras': [[x, z, model_name(r)] for (x, z), r in zip(EXTRA_COORDS, EXTRA_RESOURCES)],
            'camera': {'perspective': PERSPECTIVE, 'source': list(CAMERA_SOURCE), 'target': list(CAMERA_TARGET),
                       'move_timer': 0},
            'start': [{'player': i, 'cell': (1 + (i >> 1)) * 10 + 4 + (i & 1), 'facing': DIRECTIONS[(i & 2) + 1]}
                      for i in range(4)]},
        'events': EVENTS,
        'scenarios': scenarios,
    }


def c_enum(text, first):
    """Enumerator names of the C enum containing [first], comments removed, in order."""
    clean = re.sub(r'//[^\n]*', '', text)
    clean = re.sub(r'/\*.*?\*/', '', clean, flags=re.S)
    for body in re.findall(r'enum\s*\w*\s*\{([^}]*)\}', clean):
        names = [n.strip().split('=')[0].strip() for n in body.split(',') if n.strip()]
        if first in names:
            return names
    return []


def c_array(text, name):
    match = re.search(r'%s\[\]=\{([^}]*)\}' % re.escape(name), stack.squash(text))
    return [item for item in match.group(1).split(',') if item] if match else []


def froglord_section(path, section):
    names, active = [], False
    for line in path.read_text(encoding='utf-8').splitlines():
        line = line.split('#')[0].strip()
        if line.startswith('['):
            active = line == '[%s]' % section
        elif active and line:
            names.append(line)
    return names


def check_froglord():
    """FrogLord's retail sound list and flipbook action names agree with the ids used."""
    problems = []
    sounds = froglord_section(FROGLORD_SOUNDS, 'GENERIC')
    for key, (_source, number, name) in SOUNDS.items():
        if number >= len(sounds) or sounds[number] != name:
            problems.append('FrogLord sound %d is not %s' % (number, name))
    if froglord_section(FROGLORD_ANIMS, 'GENM_FROG')[:2] != FROG_ACTIONS:
        problems.append('FrogLord GENM_FROG actions differ from %s' % FROG_ACTIONS)
    return problems


def check_c(c_root):
    """Compare the transcriptions above with the frozen C; returns problems."""
    problems = []
    h = (c_root / 'HSINPUT.H').read_text(encoding='latin-1')
    for name, value in (('HIGH_SCORE_INPUT_NUM_EXTRAS', str(NUM_EXTRAS)), ('HIGH_SCORE_NUM_INITIALS', str(NUM_INITIALS)),
                        ('HIGH_SCORE_INPUT_FROG_JUMP_TIME', str(FROG_JUMP_TIME)),
                        ('HIGH_SCORE_INPUT_LETTER_RUB', str(LETTER_RUB)),
                        ('HIGH_SCORE_INPUT_LETTER_END', str(LETTER_END)),
                        ('HIGH_SCORE_INPUT_STATIC_SOURCE_OFS_X', str(CAMERA_SOURCE[0])),
                        ('HIGH_SCORE_INPUT_STATIC_SOURCE_OFS_Y', str(CAMERA_SOURCE[1])),
                        ('HIGH_SCORE_INPUT_STATIC_SOURCE_OFS_Z', str(CAMERA_SOURCE[2])),
                        ('HIGH_SCORE_INPUT_STATIC_TARGET_OFS_X', str(CAMERA_TARGET[0])),
                        ('HIGH_SCORE_INPUT_STATIC_TARGET_OFS_Y', str(CAMERA_TARGET[1])),
                        ('HIGH_SCORE_INPUT_STATIC_TARGET_OFS_Z', str(CAMERA_TARGET[2]))):
        if stack.define(h, name) != value:
            problems.append('HSINPUT.H %s is %s, transcribed %s' % (name, stack.define(h, name), value))
    if stack.define((c_root / 'HSView.h').read_text(encoding='latin-1'), 'HIGH_SCORE_VIEW_PERSPECTIVE') != hex(PERSPECTIVE):
        problems.append('HSView.h HIGH_SCORE_VIEW_PERSPECTIVE differs')
    frog_h = (c_root / 'FROG.H').read_text(encoding='latin-1')
    if stack.define(frog_h, 'FROG_POLY_PIECE_POP_DURATION') != str(POP_DURATION):
        problems.append('FROG.H FROG_POLY_PIECE_POP_DURATION differs')
    if c_enum(frog_h, 'FROG_DIRECTION_N')[:4] != ['FROG_DIRECTION_%s' % d for d in DIRECTIONS]:
        problems.append('FROG.H direction enum differs')
    sounds = c_enum((c_root / 'sound.h').read_text(encoding='latin-1'), 'SFX_GEN_FROG_CROAK')
    for key, (source, number, _name) in SOUNDS.items():
        if number >= len(sounds) or sounds[number] != source:
            problems.append('sound.h enumerator %d is not %s' % (number, source))
    if c_enum((c_root / 'gnm_frog.h').read_text(encoding='latin-1'), 'GENM_FROG_SIT')[:2] != FROG_ACTIONS:
        problems.append('gnm_frog.h GENM_FROG actions differ')
    if stack.define((c_root / 'PROJECT.H').read_text(encoding='latin-1'), 'FR_GO') != '(FRR_BLUE|FRR_START)':
        problems.append('PROJECT.H FR_GO differs')
    text = (c_root / 'hsinput.c').read_text(encoding='latin-1')
    if c_array(text, 'High_score_input_letters_resource_id') != PAD_RESOURCES:
        problems.append('hsinput.c letter resources differ from the transcription')
    if c_array(text, 'High_score_input_extras_resource_id') != EXTRA_RESOURCES:
        problems.append('hsinput.c extra resources differ from the transcription')
    coords = [int(v, 0) for v in c_array(text, 'High_score_input_extras_coords')]
    if coords != [v for pair in EXTRA_COORDS for v in pair]:
        problems.append('hsinput.c extra coordinates differ from the transcription')
    if stack.squash(text).count(stack.squash('#else\nMRSNDPlaySound(SFX_SEL_HI_SCORE_COUNT, NULL, 0, 0);')) != 3:
        problems.append('hsinput.c no longer has the three WIN95 SFX_SEL_HI_SCORE_COUNT arms of ruling R11')
    sq = stack.squash(text)
    for snippet in (
            'if (Game_paused_selection == HIDDEN_MENU_QUIT_GAME) { Option_page_request = OPTIONS_PAGE_MAIN_OPTIONS; '
            'return; }',
            'if (Any_high_score == FALSE) { Option_page_request = OPTIONS_PAGE_MAIN_OPTIONS; return; }',
            'High_score_input_letters_matrix_ptr[i]->t[0] = ((i % 10) * 0x100) - 0x480;'
            'High_score_input_letters_matrix_ptr[i]->t[2] = (3 - (i / 10)) * 0x100;',
            'MRAnimEnvFlipbookSetAction(High_score_input_frog_anim_env_ptr[i], GENM_FROG_SIT);',
            'High_score_input_frog_anim_env_ptr[i]->ae_update_period = 2;',
            'frog->fr_grid_x = 4 + (i & 1); frog->fr_grid_z = 1 + (i >> 1); frog->fr_direction = (i & 2) + 1;'
            'frog->fr_count = 0;',
            'frog->fr_mode = FROG_MODE_STATIONARY; else // Forbid frog to enter initials\n'
            'frog->fr_mode = FROG_MODE_STUNNED;',
            'High_score_input_initials_matrix_ptr[k]->t[0] = (i * 0x100) - 0x100;'
            'High_score_input_initials_matrix_ptr[k]->t[2] = (j * -0x100) - 0x80;',
            'High_score_input_initials_object_ptr[k] = MRCreateMesh(MR_GET_RESOURCE_ADDR(RES_OPT_LILLYPAD_BLANK_XMR),',
            'High_score_input_lily_infos[j].hs_angle = 0; High_score_input_lily_infos[j].hs_new_mof = NULL;',
            'High_score_input_initial_pos[0] = 0;',
            "i = 4 * HIGH_SCORE_NUM_INITIALS; while(i--) *long_ptr++ = ' ';",
            'if (Any_high_score == FALSE) // No ... exit now\nreturn;',
            'MRScale_matrix.m[0][0] = 0x1300;',
            'HSProjectMatricesOntoWaterSurface(High_score_input_letters_matrix_ptr[0], 30, &MRScale_matrix);',
            'MR_COPY_MAT(*matrix_pptr, &MRScale_matrix); (*matrix_pptr)->t[1] = HSGetWaterSurfaceInfoFromXZ('
            '(*matrix_pptr)->t[0], (*matrix_pptr)->t[2], NULL, NULL);',
            'if (lily_info->hs_new_mof) { // Rotate initials matrix about local Z\n'
            'cos = rcos(lily_info->hs_angle); sin = rsin(lily_info->hs_angle);'
            'MRRot_matrix_Z.m[0][0] = cos; MRRot_matrix_Z.m[0][1] = sin; MRRot_matrix_Z.m[1][0] = -sin;'
            'MRRot_matrix_Z.m[1][1] = cos; MRMulMatrixABB(&MRRot_matrix_Z, (MR_MAT*)lily_info->hs_object->ob_frame);',
            'HSProjectMatricesOntoWaterSurface(High_score_input_extras_matrix_ptr[0], HIGH_SCORE_INPUT_NUM_EXTRAS, '
            '&MRScale_matrix);',
            'for (i = 0; i < Game_total_players; i++) HSInputUpdateFrog(&Frogs[i]); UpdateEffects();',
            'if (effect = Frogs[i].fr_shadow) { shadow = effect->ef_extra; for (i = 0; i < 4; i++)',
            'if ( (Frogs[i].fr_mode != FROG_MODE_STUNNED) || (Frogs[i].fr_poly_piece_pop->pp_timer > 0) )',
            'Option_page_request = OPTIONS_PAGE_HIGH_SCORE_VIEW; // Operate in automatic mode\n'
            'HSView_automatic_flag = TRUE; High_score_operation_mode = HIGH_SCORE_OPERATION_MODE_LEVEL_SELECT;'
            'High_score_camera_operation_mode = HIGH_SCORE_CAMERA_OPERATION_MODE_STATIC; From_options = FALSE;',
            'Option_viewport_ptr->vp_perspective = HIGH_SCORE_VIEW_PERSPECTIVE;',
            'camera->ca_move_timer = 0;',
            'letter = (frog->fr_grid_z * 10) + frog->fr_grid_x; switch(frog->fr_mode)',
            'frog->fr_pos.vy = High_score_input_letters_matrix_ptr[letter]->t[1] << 16;',
            '(MR_CHECK_PAD_HELD(frog->fr_input_id, FRR_UP)) && (frog->fr_grid_z > 0) ) { // Jump up\n'
            'frog->fr_direction = FROG_DIRECTION_N; frog->fr_grid_z--; jump = TRUE; } else if (',
            '(MR_CHECK_PAD_HELD(frog->fr_input_id, FRR_DOWN)) && (frog->fr_grid_z < 2) ) { // Jump down\n'
            'frog->fr_direction = FROG_DIRECTION_S; frog->fr_grid_z++; jump = TRUE; } else if (',
            '(MR_CHECK_PAD_HELD(frog->fr_input_id, FRR_LEFT)) && (frog->fr_grid_x > 0) ) { // Jump left\n'
            'frog->fr_direction = FROG_DIRECTION_W; frog->fr_grid_x--; jump = TRUE; } else if (',
            '(MR_CHECK_PAD_HELD(frog->fr_input_id, FRR_RIGHT)) && (frog->fr_grid_x < 9) ) { // Jump right\n'
            'frog->fr_direction = FROG_DIRECTION_E; frog->fr_grid_x++; jump = TRUE; } else if (',
            '(High_score_input_lily_infos[frog->fr_frog_id].hs_new_mof == NULL) && '
            '(MR_CHECK_PAD_PRESSED(frog->fr_input_id, FR_GO))',
            'if (letter == HIGH_SCORE_INPUT_LETTER_RUB) { // Erase last character\n'
            'if (High_score_input_initial_pos[frog->fr_frog_id]) { #ifdef PSX\n'
            'MRSNDPlaySound(SFX_GEN_FROG_FLY_GULP, NULL, 0, 0);',
            'High_score_input_initial_pos[frog->fr_frog_id]--;',
            "High_score_input_initials[frog->fr_frog_id][High_score_input_initial_pos[frog->fr_frog_id]] = ' ';"
            'High_score_input_lily_infos[frog->fr_frog_id].hs_initial_index = (frog->fr_frog_id * 3) + '
            'High_score_input_initial_pos[frog->fr_frog_id];',
            'High_score_input_lily_infos[frog->fr_frog_id].hs_angle = 0;'
            'High_score_input_lily_infos[frog->fr_frog_id].hs_new_mof = MR_GET_RESOURCE_ADDR(RES_OPT_LILLYPAD_BLANK_XMR);',
            'if (letter == HIGH_SCORE_INPUT_LETTER_END) { // End hiscore input - explode frog\n#ifdef PSX\n'
            'MRSNDPlaySound(SFX_GEN_FROG_EXPLODE, NULL, 0, 0);',
            'FrogStartPolyPiecePop(frog); object = MRCreatePgen(&PGIN_frog_pop_explosion,',
            'frog->fr_mode = FROG_MODE_STUNNED; frog->fr_shadow->ef_flags |= (EFFECT_NO_UPDATE | EFFECT_NO_DISPLAY);',
            'if (High_score_input_initial_pos[frog->fr_frog_id] < 3) { #ifdef PSX\n'
            'MRSNDPlaySound(SFX_GEN_FROG_CROAK, NULL, 0, 0);',
            "if (letter < 26) // Letter\nHigh_score_input_initials[frog->fr_frog_id]"
            "[High_score_input_initial_pos[frog->fr_frog_id]] = letter + 'A';",
            "if (letter == 26) // Dot\nHigh_score_input_initials[frog->fr_frog_id]"
            "[High_score_input_initial_pos[frog->fr_frog_id]] = '.';",
            "if (letter == 27) // Space\nHigh_score_input_initials[frog->fr_frog_id]"
            "[High_score_input_initial_pos[frog->fr_frog_id]] = ' ';",
            'High_score_input_lily_infos[frog->fr_frog_id].hs_new_mof = MR_GET_RESOURCE_ADDR('
            'High_score_input_letters_resource_id[letter]);',
            'High_score_input_initial_pos[frog->fr_frog_id]++;',
            '(i != frog->fr_frog_id) && (Frogs[i].fr_mode != FROG_MODE_STUNNED) && '
            '(Frogs[i].fr_grid_x == frog->fr_grid_x) && (Frogs[i].fr_grid_z == frog->fr_grid_z) ) { // Forbid jump\n'
            'frog->fr_grid_x = old_x; frog->fr_grid_z = old_z; goto after_jump;',
            'MRSNDPlaySound(SFX_GEN_FROG_HOP, NULL, 0, 0); frog->fr_mode = FROG_MODE_JUMPING;'
            'frog->fr_count = HIGH_SCORE_INPUT_FROG_JUMP_TIME;',
            'frog->fr_y = frog->fr_pos.vy; frog->fr_velocity.vx = ((frog->fr_target_pos.vx << 16) - '
            'frog->fr_pos.vx) / frog->fr_count;',
            'MRAnimEnvFlipbookSetAction((MR_ANIM_ENV*)frog->fr_api_item, GENM_FROG_HOP);',
            'MR_COPY_MAT(frog->fr_lwtrans, High_score_input_letters_matrix_ptr[letter]);'
            'MRScale_matrix.m[0][0] = 0x1400;',
            'cos = rcos(frog->fr_direction * 0x400); sin = rsin(frog->fr_direction * 0x400);',
            'frog->fr_y += ((frog->fr_target_pos.vy << 16) - frog->fr_y) / frog->fr_count;',
            'dy = (-8 << 16) * (MR_SQR(HIGH_SCORE_INPUT_FROG_JUMP_TIME >> 1) - '
            'MR_SQR(frog->fr_count - (HIGH_SCORE_INPUT_FROG_JUMP_TIME >> 1)));',
            'if (!(--frog->fr_count)) { // Jump complete\n',
            'frog->fr_mode = FROG_MODE_STATIONARY; // Create splash sprite\n'
            'object_ptr = MRCreate3DSprite((MR_FRAME*)High_score_input_letters_matrix_ptr[letter], MR_OBJ_STATIC, '
            'High_score_splash_animlist);',
            'object_ptr->ob_extra.ob_extra_sp_core->sc_ot_offset = -0x8;'
            'object_ptr->ob_extra.ob_extra_sp_core->sc_scale = 10 << 16;',
            'MRAnimEnvFlipbookSetAction((MR_ANIM_ENV*)frog->fr_api_item, GENM_FROG_SIT);'
            'MRAnimEnvFlipbookSetCel((MR_ANIM_ENV*)frog->fr_api_item, 0); MRSNDPlaySound(SFX_GEN_FROG_SPLASH1, NULL, 0, 0);',
            'i = ((HIGH_SCORE_INPUT_FROG_JUMP_TIME - frog->fr_count) * 6) / HIGH_SCORE_INPUT_FROG_JUMP_TIME;'
            'i = MAX(0, MIN(5, i));',
            'if ( (frog->fr_poly_piece_pop) && (frog->fr_poly_piece_pop->pp_timer) ) { '
            'UpdatePolyPiecePop(frog->fr_poly_piece_pop);',
            'lily_info->hs_angle += 0x100; if (lily_info->hs_angle == 0x500) {',
            'lily_info->hs_angle = -0x300; } else if (lily_info->hs_angle == 0) { // Done - reset lily info\n'
            'lily_info->hs_new_mof = NULL;'):
        if stack.squash(snippet) not in sq:
            problems.append('hsinput.c no longer contains: %s' % snippet[:90])
    frog_c = stack.squash((c_root / 'FROG.C').read_text(encoding='latin-1'))
    if stack.squash('frog->fr_poly_piece_pop->pp_timer = FROG_POLY_PIECE_POP_DURATION;') not in frog_c:
        problems.append('FROG.C FrogStartPolyPiecePop no longer sets the pop timer')
    effects = stack.squash((c_root / 'EFFECTS.C').read_text(encoding='latin-1'))
    if stack.squash('if (poly_piece_pop->pp_timer) { poly_piece_pop->pp_timer--;') not in effects:
        problems.append('EFFECTS.C UpdatePolyPiecePop no longer decrements the timer')
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--c-reference', type=Path, default=frontend.DEFAULT_C,
                        help='frozen C source folder (default: ../froggy/engine/vendor/frogger-psx-src/source)')
    parser.add_argument('--check', action='store_true', help='compare with the committed file instead of writing')
    args = parser.parse_args()
    problems = check_froglord()
    if args.c_reference.is_dir():
        problems += check_c(args.c_reference)
        if not problems:
            print('C cross-check passed against %s' % args.c_reference)
    else:
        print('C source not found at %s; cross-checks skipped' % args.c_reference)
    for problem in problems:
        print('Cross-check: ' + problem)
    if problems:
        sys.exit(1)
    text = stack.dump(document()) + '\n'
    if args.check:
        old = ENTRY_JSON.read_text(encoding='utf-8') if ENTRY_JSON.exists() else ''
        if old != text:
            sys.stdout.writelines(difflib.unified_diff(old.splitlines(True), text.splitlines(True),
                                                       str(ENTRY_JSON), 'generated', n=0))
        print('Committed facts differ from the generator' if old != text else 'Committed facts match the generator')
        sys.exit(1 if old != text else 0)
    ENTRY_JSON.write_text(text, encoding='utf-8')
    print('Wrote %s' % ENTRY_JSON.relative_to(ROOT))


if __name__ == '__main__':
    main()
