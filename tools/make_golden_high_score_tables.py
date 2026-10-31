#!/usr/bin/env python3
"""Independent high-score table rules from the frozen C, replayed over synthetic tables.

Transcribes HighScoreInitialiseData, HighScoreInputStartup's qualification,
HighScoreCheckScore, HighScoreCheckArcadeTime, HighScoreCheckAllArcadeTimes,
HighScoreEnterScore, HighScoreEnterArcadeTime and HighScoreAddAllArcadeTimes
(hsinput.c), the level-completion and jungle-statue recording (gamesys.C), the
checkpoint seconds (FROG.C) and HighScoreBuildArcadeTimeTable over the
SELECT.C score-line templates (HSView.c). Race tables are not covered. No
retail values are read. See tests/golden/specs/frontend.md.
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
TABLES_JSON = frontend.GOLDEN / 'synthetic' / 'frontend_high_score_tables.json'

MAIN_ROWS, LEVELS, RANKS, CHECKPOINTS, PLAYERS = 10, 60, 3, 5, 4
MARKER, RESET_INITIALS = 'Z', 'AAA'
TICKS_PER_SECOND, SECONDS_LIMIT_TICKS, SECONDS_LIMIT = 30, 2971, 99
JUNGLE1, JUNGLE2 = frontend.LEVEL['JUNGLE1'], frontend.LEVEL['JUNGLE2']
ORIGINAL1, SUBURBIA1, VOLCANO1 = frontend.LEVEL['ORIGINAL1'], frontend.LEVEL['SUBURBIA1'], frontend.LEVEL['VOLCANO1']
TEMPLATES = ['%jc1.DMA 0000000000:00s  ', '%jc2.DMA  1:11 22345678  ', '%jc3.DMA  1:11 32345678  ']
PREFIX = '%jc'
EMPTY = ['   ', 0, [0, 0, 0, 0, 0]]
U32 = 0xFFFFFFFF


def cdiv(a, b):
    return stack.cdiv(a, b)


def checkpoint_seconds(ticks):
    """FROG.C:2833-2842: round the timer up to a multiple of 30, then 99 from 2971 or value / 30."""
    value = ticks
    while value != 0 and value != cdiv(value, 30) * 30:
        value += 1
    if value >= SECONDS_LIMIT_TICKS:
        return SECONDS_LIMIT
    return cdiv(value, 30)


class Board:
    """Game_high_score, Level_high_scores and Frog_score_data[*][0] with the hsinput.c globals."""

    def __init__(self, main, levels):
        self.main = [[r[0], r[1], list(r[2])] for r in main]
        self.levels = {}
        for level in range(LEVELS):
            rows = levels.get(level, [EMPTY] * RANKS)
            self.levels[level] = [[r[0], r[1], list(r[2])] for r in rows]
        self.new_high_score = 0
        self.new_high_scores = [0] * LEVELS
        self.main_shown = bool(main)
        self.initialise_data()

    def initialise_data(self):
        """HighScoreInitialiseData: initials 'AAA', score 0, times 0."""
        self.score_data = [[RESET_INITIALS, 0, [0] * CHECKPOINTS] for _ in range(LEVELS)]

    def record(self, game_map, delta, times):
        """gamesys.C:2733-2766 for player 0."""
        entry = self.score_data[game_map]
        if entry[0][0] == MARKER:
            if (entry[1] & U32) < (delta & U32):
                entry[1] = delta
                entry[2] = list(times)
        else:
            entry[0] = MARKER + entry[0][1:]
            entry[1] = delta
            entry[2] = list(times)

    def statue(self, delta):
        """gamesys.C:3493-3513 with Game_map == LEVEL_JUNGLE2."""
        entry = self.score_data[JUNGLE1]
        if entry[0][0] == MARKER:
            if (entry[1] & U32) < (delta & U32):
                entry[1] = delta
                entry[2] = [0] * CHECKPOINTS
        else:
            entry[0] = MARKER + entry[0][1:]
            entry[2] = [0] * CHECKPOINTS
            entry[1] = delta

    def check_score(self, score):
        for k in range(10):
            if (self.main[k][1] & U32) < (score & U32):
                return True
        return False

    def check_arcade_time(self, table, time):
        if table == JUNGLE2:
            table = JUNGLE1
        for k in range(3):
            total_time = self.levels[table][k][1]
            if (total_time & U32) < (time & U32):
                return True
        return False

    def check_all_arcade_times(self):
        for level in range(60):
            if self.score_data[level][0][0] == MARKER:
                if self.check_arcade_time(level, self.score_data[level][1]):
                    return True
        return False

    def startup(self, score, quit_game):
        """HighScoreInputStartup's bails and flag reset for one arcade player."""
        if quit_game:
            return 'GAME_QUIT'
        any_high_score = self.check_score(score) or self.check_all_arcade_times()
        if not any_high_score:
            return 'NO_HIGH_SCORE'
        self.new_high_scores = [0] * LEVELS
        self.new_high_score = 0
        return 'ENTRY'

    def enter_score(self, initials, score):
        l1 = 0
        while l1 < 10:
            if (self.main[l1][1] & U32) < (score & U32):
                break
            l1 += 1
        if l1 == 10:
            return -1
        if l1 != 9:
            l2 = 9
            while True:
                l2 -= 1
                self.main[l2 + 1][0] = self.main[l2][0]
                self.main[l2 + 1][1] = self.main[l2][1]
                if l2 == l1:
                    break
        self.main[l1][0] = initials
        self.main[l1][1] = score
        self.new_high_score = 1
        return l1

    def enter_arcade_time(self, level, time, initials, entered):
        if level == JUNGLE2:
            level = JUNGLE1
        table = self.levels[level]
        l1 = 0
        while l1 < 3:
            if (table[l1][1] & U32) < (time & U32):
                break
            l1 += 1
        if l1 == 3:
            return
        if l1 != 2:
            l2 = 2
            while True:
                l2 -= 1
                table[l2 + 1] = [table[l2][0], table[l2][1], list(table[l2][2])]
                if l2 == l1:
                    break
        run = self.score_data[level]
        table[l1] = [initials, run[1], list(run[2])]
        self.new_high_scores[level] = 1
        entered.append(level)

    def add_all_arcade_times(self, initials):
        entered = []
        for level in range(60):
            if self.score_data[level][0][0] == MARKER:
                self.enter_arcade_time(level, self.score_data[level][1], initials, entered)
        return entered

    def state(self, shown):
        result = {}
        if self.main_shown:
            result['main'] = [list(r) for r in self.main]
        result['levels'] = {str(level): [list(r) for r in self.levels[level]] for level in shown}
        result['recorded'] = [level for level in range(LEVELS) if self.score_data[level][0][0] == MARKER]
        result['run'] = {str(level): [self.score_data[level][1], list(self.score_data[level][2])]
                         for level in result['recorded']}
        result['new_main'] = bool(self.new_high_score)
        result['new_levels'] = [level for level in range(LEVELS) if self.new_high_scores[level]]
        return result


def score_text(score):
    """HSView.c:1730-1757: eight digits of the unsigned score, leading zeros blanked except the last."""
    text = [' '] * 8
    value = score & U32
    count = 8
    while count:
        count -= 1
        text[count] = chr(value % 10 + 48)
        value //= 10
    for count in range(7):
        if text[count] == '0':
            text[count] = ' '
        else:
            break
    return ''.join(text)


def time_text(total_time):
    """HSView.c:1704-1725: MM:SSs with minutes above 99 shown as 99:59."""
    total_time &= U32
    seconds, minutes = total_time % 60, total_time // 60
    if minutes > 99:
        minutes, seconds = 99, 59
    return '%c%c:%c%cs' % (minutes // 10 + 48, minutes % 10 + 48, seconds // 10 + 48, seconds % 10 + 48)


def build_lines(rows):
    """HighScoreBuildArcadeTimeTable over the templates; the %jc prefix is dropped from the result."""
    lines = []
    for entry_count, row in enumerate(rows[:3]):
        text = list(TEMPLATES[entry_count])
        for count in range(3, 24):
            text[count] = ' '
        text[3] = chr(ord('1') + entry_count)
        text[4] = '.'
        text[5:8] = list(row[0])
        total = sum(row[2])
        text[18:24] = list(time_text(total))
        text[9:17] = list(score_text(row[1]))
        line = ''.join(text)
        if not line.startswith(PREFIX):
            sys.exit('template lost its prefix')
        lines.append(line[len(PREFIX):])
    return lines


def table(scores, initials='ABCDEFGHIJ', times=None):
    rows = []
    for index, score in enumerate(scores):
        rows.append([initials[index % len(initials)] * 3, score, list(times[index]) if times else [index] * 5])
    return rows


MAIN_DESCENDING = table([1000, 900, 800, 700, 600, 500, 400, 300, 200, 100])
LEVEL_ROWS = [['AAA', 3000, [10, 11, 12, 13, 14]], ['BBB', 2000, [20, 21, 22, 23, 24]],
              ['CCC', 1000, [30, 31, 32, 33, 34]]]
TICKS_A = [30, 31, 59, 60, 0]
TICKS_B = [2970, 2971, 5000, 1, 29]

SCENARIOS = [
    ('main_strict_and_tie_below', 'an equal score does not qualify; a tie enters below the equal row; the '
     'ten-row shift moves initials and score only and drops the last row',
     MAIN_DESCENDING, {},
     [('qualifies', [100]), ('qualifies', [101]), ('qualifies', [0]), ('enter', ['TIE', 500])]),
    ('main_top_bottom_and_miss', 'a miss leaves the flag clear; top insertion shifts all; bottom insertion '
     'replaces the last row without a shift',
     MAIN_DESCENDING, {},
     [('enter', ['LOW', 50]), ('enter', ['TOP', 2000]), ('enter', ['BOT', 250]), ('enter', ['MID', 850])]),
    ('level_record_and_better_overwrite', 'the first completion records score and seconds; a lower or equal '
     'score keeps them; a higher one replaces both',
     [], {ORIGINAL1: LEVEL_ROWS},
     [('record_level', [ORIGINAL1, 500, TICKS_A]), ('record_level', [ORIGINAL1, 400, TICKS_B]),
      ('record_level', [ORIGINAL1, 500, TICKS_B]), ('record_level', [ORIGINAL1, 600, TICKS_B]),
      ('record_level', [-1, 900, TICKS_A]), ('record_level', [LEVELS, 900, TICKS_A]), ('reset_run', []),
      ('qualifies_arcade', [])]),
    ('level_shift_moves_times', 'arcade qualification and insertion: a three-row shift moving times, a tie '
     'below, a top insertion, flags and the inserted levels in level order',
     [], {ORIGINAL1: LEVEL_ROWS, SUBURBIA1: LEVEL_ROWS, VOLCANO1: LEVEL_ROWS},
     [('qualifies_arcade', []), ('record_level', [SUBURBIA1, 1000, TICKS_A]), ('qualifies_arcade', []),
      ('record_level', [ORIGINAL1, 2500, TICKS_B]), ('qualifies_arcade', []),
      ('record_level', [VOLCANO1, 999999, TICKS_A]), ('enter_arcade_times', ['NEW'])]),
    ('jungle_redirect', 'a JUNGLE2 record is checked against and entered into the JUNGLE1 table, the new row '
     'taking the JUNGLE1 run data (here unrecorded, so score 0 and zero times)',
     [], {JUNGLE1: LEVEL_ROWS, JUNGLE2: table([9000, 9000, 9000])},
     [('record_level', [JUNGLE2, 1500, TICKS_A]), ('qualifies_arcade', []), ('enter_arcade_times', ['JUN'])]),
    ('jungle_statue', 'the statue records JUNGLE1 with zero times, keeping the better score; both jungle '
     'records insert into the JUNGLE1 table, each new row taking the JUNGLE1 run data',
     [], {JUNGLE1: LEVEL_ROWS, JUNGLE2: table([9000, 9000, 9000])},
     [('record_level', [JUNGLE2, 5000, TICKS_B]), ('record_jungle_statue', [2500]),
      ('record_jungle_statue', [2400]), ('record_jungle_statue', [2600]), ('enter_arcade_times', ['JUN'])]),
    ('startup_outcomes', 'a pause-menu quit bails before any check; no qualifier bails; a main or arcade '
     'qualifier opens the entry and clears the new-score flags',
     MAIN_DESCENDING, {ORIGINAL1: LEVEL_ROWS},
     [('enter', ['OLD', 5000]), ('input_startup', [5000, True]), ('input_startup', [50, False]),
      ('input_startup', [250, False]), ('qualifies_any', [50]), ('record_level', [ORIGINAL1, 1001, TICKS_A]),
      ('qualifies_any', [50]), ('enter_arcade_times', ['ARC']), ('input_startup', [50, False])]),
]

SECONDS_TICKS = [0, 1, 29, 30, 31, 59, 60, 2940, 2941, 2970, 2971, 2990, 5000]
SCORE_CASES = [0, 7, 1000, 10203, 99999999, 10000000, 100000000, 123456789]
TIME_CASES = [0, 59, 60, 61, 300, 5940, 5999, 6000, 99999]
LINE_CASES = [
    ('ordinary rows', [['KEV', 4000, [60, 60, 60, 60, 60]], ['SUE', 2000, [1, 2, 3, 4, 5]],
                       ['DAV', 1000, [0, 0, 0, 0, 0]]]),
    ('dot initials, zero score and the time cap', [['M[B', 0, [0, 0, 0, 0, 0]],
                                                   ['[[[', 10000000, [6000, 0, 0, 0, 0]],
                                                   ['A B', 123456789, [5999, 0, 0, 0, 0]]]),
    ('fewer rows', [['ONE', 5, [99, 99, 99, 99, 99]]]),
]


def replay(main, levels, steps):
    board = Board(main, levels)
    shown = sorted(levels)
    trace = []
    for op, args in steps:
        if op == 'qualifies':
            result = board.check_score(args[0])
        elif op == 'qualifies_arcade':
            result = board.check_all_arcade_times()
        elif op == 'qualifies_any':
            result = board.check_score(args[0]) or board.check_all_arcade_times()
        elif op == 'enter':
            result = board.enter_score(args[0], args[1])
        elif op == 'enter_arcade_times':
            result = board.add_all_arcade_times(args[0])
        elif op == 'record_level':
            if 0 <= args[0] < LEVELS:
                board.record(args[0], args[1], [checkpoint_seconds(t) for t in args[2]])
            result = None
        elif op == 'record_jungle_statue':
            board.statue(args[0])
            result = None
        elif op == 'reset_run':
            board.initialise_data()
            result = None
        elif op == 'input_startup':
            result = board.startup(args[0], args[1])
        else:
            sys.exit('unknown operation %s' % op)
        trace.append({'op': op, 'args': list(args), 'result': result, 'state': board.state(shown)})
    return trace


def document():
    scenarios = []
    for name, description, main, levels, steps in SCENARIOS:
        if main and len(main) != MAIN_ROWS:
            sys.exit('scenario %s main table is not ten rows' % name)
        scenarios.append({'name': name, 'description': description, 'main': main,
                          'levels': {str(k): v for k, v in sorted(levels.items())},
                          'steps': replay(main, levels, steps)})
    return {
        'constants': {
            'main_rows': MAIN_ROWS, 'levels': LEVELS, 'level_ranks': RANKS, 'checkpoints': CHECKPOINTS,
            'run_players': PLAYERS, 'run_marker': MARKER, 'reset_initials': RESET_INITIALS,
            'ticks_per_second': TICKS_PER_SECOND, 'seconds_limit_ticks': SECONDS_LIMIT_TICKS,
            'seconds_limit': SECONDS_LIMIT, 'level_jungle1': JUNGLE1, 'level_jungle2': JUNGLE2,
            'score_digits': 8, 'blanked_digits': 7, 'minutes_limit': 99, 'seconds_at_limit': 59,
            'level_row_index': 'level * 3 + rank', 'run_time_index': 'level * 5 + checkpoint'},
        'rules': {
            'qualify_main': 'a score qualifies when some main row score < score (hsinput.c:633-641)',
            'qualify_arcade': 'a level recorded this run qualifies when some row of its table, JUNGLE2 read as '
                              'JUNGLE1, has score < the recorded level score (hsinput.c:690-708, 1085-1110)',
            'startup': 'a pause-menu quit requests MAIN_OPTIONS before any check (hsinput.c:189-193); no '
                       'qualifier requests MAIN_OPTIONS (hsinput.c:222-226); otherwise the new-score flags are '
                       'cleared (hsinput.c:384-390) and the entry opens',
            'enter_main': 'the first row with score < score takes the entry; rows from there move down one '
                          'with initials and score only, the last row dropping (hsinput.c:799-842)',
            'enter_levels': 'every recorded level in level order is entered into its table, JUNGLE2 into '
                            'JUNGLE1; rows move down one with initials, score and times; the new row takes the '
                            'entered initials and the run score and times of the table level '
                            '(hsinput.c:871-955, 1186-1214)',
            'record': 'at level completion the first record this run marks the level and stores score and '
                      'checkpoint seconds; a later one replaces both only for a higher score; the level score '
                      'is fr_score - fr_prev_score (gamesys.C:2733-2766)',
            'statue': 'the jungle statue on JUNGLE2 records into JUNGLE1 with zero times by the same rule '
                      '(gamesys.C:3493-3513)',
            'reset': 'HighScoreInitialiseData resets every run row to AAA, 0, zero times when a game starts '
                     '(hsinput.c:129-156, tempopt.c:1801)',
            'seconds': 'the checkpoint timer, in 30 Hz ticks counting up from 0, is rounded up to a multiple of '
                       '30; 2971 and above give 99, otherwise value / 30 (FROG.C:2833-2842)',
            'line': 'columns 3-23 are blanked; rank digit and dot, initials verbatim, the eight-digit score at '
                    '9-16 with up to seven leading zeros blanked, MM:SSs at 18-23 from the checkpoint-time sum, '
                    'minutes above 99 shown as 99:59 (HSView.c:1690-1757)'},
        'templates': TEMPLATES,
        'display': {'prefix': PREFIX, 'prefix_meaning': 'MRBuildText centre justification, dropped from the '
                                                        'port lines', 'line_length': len(TEMPLATES[0]) - len(PREFIX),
                    'jungle2_table': JUNGLE1},
        'checkpoint_seconds': [[t, checkpoint_seconds(t)] for t in SECONDS_TICKS],
        'score_text': [[s, score_text(s)] for s in SCORE_CASES],
        'time_text': [[t, time_text(t)] for t in TIME_CASES],
        'lines': [{'name': n, 'rows': rows, 'lines': build_lines(rows)} for n, rows in LINE_CASES],
        'scenarios': scenarios,
    }


def check_c(c_root):
    """Compare the transcriptions above with the frozen C; returns problems."""
    problems = []
    library = (c_root / 'LIBRARY.H').read_text(encoding='latin-1')
    names = re.findall(r'^\s*LEVEL_(\w+),', library, re.M)
    if names[JUNGLE1] != 'JUNGLE1' or names[JUNGLE2] != 'JUNGLE2' or names[ORIGINAL1] != 'ORIGINAL1':
        problems.append('LIBRARY.H level ids differ from the transcription')
    h = stack.squash((c_root / 'HSView.h').read_text(encoding='latin-1'))
    for snippet in ('MR_UBYTEhe_initials[4];', 'MR_ULONGhe_score;', 'MR_USHORThe_time_to_checkpoint[5];',
                    'externHIGH_SCORE_ENTRYFrog_score_data[60][4];', 'externHIGH_SCORE_ENTRYGame_high_score[10];',
                    'externHIGH_SCORE_ENTRYLevel_high_scores[60][3];'):
        if snippet not in h:
            problems.append('HSView.h no longer contains: %s' % snippet[:90])
    hs = (c_root / 'hsinput.c').read_text(encoding='latin-1')
    sq = stack.squash(hs)
    for snippet in (
            "Frog_score_data[loop_counter_1][loop_counter_2].he_initials[0]='A';",
            'Frog_score_data[loop_counter_1][loop_counter_2].he_score=0;',
            'Frog_score_data[loop_counter_1][loop_counter_2].he_time_to_checkpoint[4]=0;',
            'if(Game_paused_selection==HIDDEN_MENU_QUIT_GAME){Option_page_request=OPTIONS_PAGE_MAIN_OPTIONS;return;}',
            'if(HighScoreCheckScore(frog->fr_score)==TRUE)',
            'if(HighScoreCheckAllArcadeTimes(i)==TRUE)',
            'if(Any_high_score==FALSE){Option_page_request=OPTIONS_PAGE_MAIN_OPTIONS;return;}',
            'New_high_scores[i]=0;', 'New_high_score=0;',
            'if(Frogs[i].fr_flags&FROG_ENTER_SCORE)HighScoreEnterScore(Frogs[i].fr_score);'
            'if(Frogs[i].fr_flags&FROG_ENTER_ARCADE_TIME)HighScoreAddAllArcadeTimes(i);',
            'for(loop_counter=0;loop_counter<10;loop_counter++){//Isscoregreaterthancurrententry?'
            'if(Game_high_score[loop_counter].he_score<score)',
            'if(high_score_table_number==LEVEL_JUNGLE2)high_score_table_number=LEVEL_JUNGLE1;',
            'total_time=Level_high_scores[high_score_table_number][loop_counter].he_score;'
            '//Istimegreaterthancurrententry?if(total_time<time)',
            'for(loop_counter_1=0;loop_counter_1<10;loop_counter_1++){//Isthisscorelessthanentrantsscore?'
            'if(Game_high_score[loop_counter_1].he_score<score)',
            'if(loop_counter_1==10)', 'if(loop_counter_1!=9)', 'loop_counter_2=9;do{//Deccountloop_counter_2--;',
            'Game_high_score[loop_counter_2+1].he_score=Game_high_score[loop_counter_2].he_score;'
            '}while(loop_counter_2!=loop_counter_1);',
            'Game_high_score[loop_counter_1].he_score=score;//FlagashavinganewhighscoreNew_high_score=1;',
            'if(level_number==LEVEL_JUNGLE2)level_number=LEVEL_JUNGLE1;',
            'total_time=Level_high_scores[level_number][loop_counter_1].he_score;'
            '//Isthistimegreaterthanentrantstime?if(total_time<time)',
            'if(loop_counter_1==3)', 'if(loop_counter_1!=2)', 'loop_counter_2=2;do{//Deccountloop_counter_2--;',
            'Level_high_scores[level_number][loop_counter_2+1].he_time_to_checkpoint[4]='
            'Level_high_scores[level_number][loop_counter_2].he_time_to_checkpoint[4];'
            '}while(loop_counter_2!=loop_counter_1);',
            'Level_high_scores[level_number][loop_counter_1].he_score=Frog_score_data[level_number][0].he_score;',
            'Level_high_scores[level_number][loop_counter_1].he_time_to_checkpoint[4]='
            'Frog_score_data[level_number][0].he_time_to_checkpoint[4];//Flaglevelashavinganewhighscore'
            'New_high_scores[level_number]=1;',
            "for(loop_counter=0;loop_counter<60;loop_counter++){//Havewerecordedatimeforthislevel?"
            "if(Frog_score_data[loop_counter][frog_num].he_initials[0]=='Z')",
            'total_time=Frog_score_data[loop_counter][frog_num].he_score;//Checkthislevel\'shighscore'
            'high_score=HighScoreCheckArcadeTime(loop_counter,total_time);',
            'HighScoreEnterArcadeTime(loop_counter,Frog_score_data[loop_counter][frog_num].he_score);'):
        if stack.squash(snippet) not in sq:
            problems.append('hsinput.c no longer contains: %s' % snippet[:90])
    if 'Game_high_score[loop_counter_2+1].he_time_to_checkpoint' in sq:
        problems.append('hsinput.c main-table shift now moves checkpoint times')
    lines = hs.splitlines()
    for line, text in ((191, 'OPTIONS_PAGE_MAIN_OPTIONS'), (224, 'OPTIONS_PAGE_MAIN_OPTIONS'),
                       (538, 'OPTIONS_PAGE_HIGH_SCORE_VIEW')):
        if text not in lines[line - 1] or lines[line - 1].lstrip().startswith('//'):
            problems.append('hsinput.c:%d no longer requests %s' % (line, text))
    gs = stack.squash((c_root / 'gamesys.C').read_text(encoding='latin-1'))
    for snippet in (
            "if(Frog_score_data[Game_map][0].he_initials[0]=='Z')",
            'if(Frog_score_data[Game_map][0].he_score<(Frogs[0].fr_score-Frogs[0].fr_prev_score))',
            'Frog_score_data[Game_map][0].he_score=Frogs[0].fr_score-Frogs[0].fr_prev_score;',
            "Frog_score_data[Game_map][0].he_initials[0]='Z';",
            'Frog_score_data[Game_map][0].he_time_to_checkpoint[4]=Frog_time_data[4];',
            'Frogs[0].fr_prev_score=Frogs[0].fr_score;',
            "if(Game_map==LEVEL_JUNGLE2){if(Frog_score_data[LEVEL_JUNGLE1][0].he_initials[0]=='Z'){"
            'if(Frog_score_data[LEVEL_JUNGLE1][0].he_score<Frogs[0].fr_score-Frogs[0].fr_prev_score){'
            'Frog_score_data[LEVEL_JUNGLE1][0].he_score=Frogs[0].fr_score-Frogs[0].fr_prev_score;'
            'Frog_score_data[LEVEL_JUNGLE1][0].he_time_to_checkpoint[0]=0;',
            "}else{Frog_score_data[LEVEL_JUNGLE1][0].he_initials[0]='Z';"
            'Frog_score_data[LEVEL_JUNGLE1][0].he_time_to_checkpoint[0]=0;',
            'Game_map_timer_decimalised+=(Game_map_timer_speed>>16);',
            'Game_map_timer_decimalised=0;'):
        if stack.squash(snippet) not in gs:
            problems.append('gamesys.C no longer contains: %s' % snippet[:90])
    frog = stack.squash((c_root / 'FROG.C').read_text(encoding='latin-1'))
    for snippet in (
            'checkpoint->cp_time=Game_map_timer_decimalised;',
            'if(Sel_mode==0){//Roundupwhile(Game_map_timer_decimalised!=0&&(Game_map_timer_decimalised!='
            '(Game_map_timer_decimalised/30)*30))Game_map_timer_decimalised++;'
            'if(Game_map_timer_decimalised>=2971){Frog_time_data[checkpoint_id]=99;}'
            'else{Frog_time_data[checkpoint_id]=(Game_map_timer_decimalised)/30;}}'):
        if stack.squash(snippet) not in frog:
            problems.append('FROG.C no longer contains: %s' % snippet[:90])
    select = (c_root / 'SELECT.C').read_text(encoding='latin-1')
    block = select[select.index('Sel_hiscore_text[3][25]'):]
    block = block[:block.index('};')]
    found = [m for m in re.findall(r'^\s*\{"([^"]*)",\s*NULL\}', block, re.M)]
    if found != TEMPLATES:
        problems.append('SELECT.C Sel_hiscore_text templates differ: %s' % found)
    view = stack.squash((c_root / 'HSView.c').read_text(encoding='latin-1'))
    for snippet in (
            'if(hiscore_table_number==LEVEL_JUNGLE2){//Yes...noitisn\'t!hiscore_table_number=LEVEL_JUNGLE1;}',
            'text_ptr=*Sel_hiscore_text[entry_count];',
            "for(count=3;count<24;count++)*(text_ptr+count)=' ';",
            "*(text_ptr+3)='1'+entry_count;*(text_ptr+4)='.';*(text_ptr+5)=hs_entry_ptr->he_initials[0];"
            '*(text_ptr+6)=hs_entry_ptr->he_initials[1];*(text_ptr+7)=hs_entry_ptr->he_initials[2];',
            'seconds=total_time%60;minutes=total_time/60;',
            'if(minutes>99){//Yes...settomaxminutes=99;seconds=59;}',
            "*(text_ptr+23)='s';*(text_ptr+22)=(seconds%10)+48;*(text_ptr+21)=(seconds/10)+48;"
            "*(text_ptr+20)=':';*(text_ptr+19)=(minutes%10)+48;*(text_ptr+18)=(minutes/10)+48;",
            'count=8;while(count--){',
            '*(text_ptr+9+count)=(score%10)+48;//Adjusttotalscorescore/=10;',
            "for(count=0;count<7;count++){//Leadingzero?//if(*(text_ptr+13+count)=='0')"
            "if(*(text_ptr+9+count)=='0'){//Yes...spaceoutzero//*(text_ptr+13+count)='';"
            "*(text_ptr+9+count)='';}else{//No...breakloopbreak;}}"):
        if stack.squash(snippet) not in view:
            problems.append('HSView.c no longer contains: %s' % snippet[:90])
    tempopt = (c_root / 'tempopt.c').read_text(encoding='latin-1').splitlines()
    if 'HighScoreInitialiseData();' not in tempopt[1800]:
        problems.append('tempopt.c:1801 no longer resets the run data')
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
        old = TABLES_JSON.read_text(encoding='utf-8') if TABLES_JSON.exists() else ''
        if old != text:
            sys.stdout.writelines(difflib.unified_diff(old.splitlines(True), text.splitlines(True),
                                                       str(TABLES_JSON), 'generated', n=0))
        print('Committed facts differ from the generator' if old != text else 'Committed facts match the generator')
        sys.exit(1 if old != text else 0)
    TABLES_JSON.write_text(text, encoding='utf-8')
    print('Wrote %s' % TABLES_JSON.relative_to(ROOT))


if __name__ == '__main__':
    main()
