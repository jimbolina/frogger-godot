#!/usr/bin/env python3
"""Asset-free edge checks for the independent ORG1 script oracle."""
import unittest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.golden.org1_script_state import Script,tables

IDENTITY=[4096,0,0,0,4096,0,0,0,4096,0,0,0]


def program(*instructions):
    names=[p[0] for p in tables.OPCODES]
    return [word for name,*args in instructions for word in [names.index(name),*args]]


class ScriptOracleTests(unittest.TestCase):
    def state(self,*instructions,registers=(),actions=(3,4)):
        return Script({1:program(*instructions)},1,list(registers),list(actions))

    def step(self,state,**kw):return state.update(1,IDENTITY,[0,0,0],**kw)

    def test_stop_keeps_timer_and_once_callback_eligible(self):
        s=self.state(('REGISTER_CALLBACK',0,1,0,0),('STOP',))
        self.assertEqual(self.step(s)[1],[])
        cursor=s.cursor;s.timer=65535
        self.assertEqual(self.step(s,hit=True)[1],[19])
        self.assertEqual((s.cursor,s.timer,s.callbacks[0][3]),(cursor,0,2))
        self.assertEqual(self.step(s,hit=True)[1],[19])

    def test_callback_slots_execute_in_slot_order(self):
        s=self.state(('REGISTER_CALLBACK',1,1,0,0),('REGISTER_CALLBACK',0,8,0,0),('STOP',))
        self.assertEqual(self.step(s,hit=True)[1],[14,15,19])

    def test_loop_boundary_yields_and_timer_still_increments(self):
        s=self.state(('SETLOOP',),('SET_TIMER',0,0),('ENDLOOP',),('RESTART',))
        for _ in range(3):
            self.step(s);self.assertEqual((s.cursor,s.timer),(1,1))

    def test_deviation_clamps_and_callback_kills_at_threshold(self):
        s=self.state(('REGISTER_CALLBACK',1,2,7,1),('DEVIATE',0,1,128,2048,-1),('WAIT_DEVIATED',),('STOP',))
        for i in range(16):
            result=self.step(s,carry=True)
            self.assertEqual(s.deviation,(i+1)*8)
            self.assertEqual(result[3],i==15)
        self.assertEqual((s.delta,s.remaining,s.colours,s.ambient),(0,0,[0,64,255],[64,64,192]))

    def test_fade_and_no_display_conditions(self):
        s=self.state(('REGISTER_CALLBACK',1,2,7,1),('STOP',))
        s.deviation=128
        self.assertFalse(self.step(s,carry=True,no_display=True)[3])
        self.assertEqual(s.colours,[0,0,0])
        self.assertTrue(self.step(s,carry=True,fade=[1,2,1,2])[3])
        self.assertFalse(s.no_fade);self.assertEqual(s.colours,[0,0,0])

    def test_action_restarts_and_real_lengths_wrap(self):
        s=self.state(('SETLOOP',),('SET_ACTION',1),('ENDLOOP',),('RESTART',))
        self.step(s);self.assertEqual(s.cel,-1)
        for _ in range(6):s.advance_animation()
        self.assertEqual(s.cel,1)
        self.step(s);self.assertEqual(s.cel,-1)

    def test_sound_owner_and_ordered_splash_parameters(self):
        s=self.state(('SETLOOP',),('PLAY_MOVING_SOUND',11,0,512,1024),('CREATE_3D_SPRITE',0),('ENDLOOP',),('RESTART',))
        self.step(s,form_id=21)
        self.assertEqual(s.requests,['moving:11:512:1024','sprite:0:-64:-256:1:-16','sprite:0:-64:0:1:-16','sprite:0:-64:256:1:-16'])
        self.step(s,form_id=21)
        self.assertEqual(len(s.requests),3)

    def test_timer_and_deviation_source_narrowing(self):
        s=self.state(('SET_TIMER',0,-1),('DEVIATE',0,1,0,65535,1),('STOP',))
        self.step(s);self.assertEqual((s.timer,s.deviation,s.delta,s.remaining),(0,-1,0,0))

    def test_unknown_invalid_and_non_yielding_programs_reject(self):
        cases=[(('REGISTER_CALLBACK',2,1,0,0),('STOP',)),(('REGISTER_CALLBACK',0,99,0,0),('STOP',)),
               (('SET_ACTION',9),('STOP',)),(('SETLOOP',),('STOP',)),(('ENDLOOP',),),
               (('SETLOOP',),('SETLOOP',),('ENDLOOP',)),(('RESTART',),),
               (('WAIT_UNTIL_TIMER',1,-1),), (('SCRIPT_IF',0,6,99,4),)]
        for instructions in cases:
            with self.subTest(instructions=instructions),self.assertRaises(ValueError):self.step(self.state(*instructions))
        with self.assertRaises(ValueError):self.step(Script({1:[999]},1,[],[]))


if __name__=='__main__':unittest.main()
