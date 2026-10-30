#!/usr/bin/env python3
"""Independent synthetic effect facts from frozen PARTICLE.C/H, EFFECTS.C/H, FROG.C/H, MISC.C, COLLIDE.C, scripter.c, score.C/H, ent_des.c and MR_SPRT.C/H."""
import argparse
from pathlib import Path
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_golden_desert as desert
import make_golden_exe_tables as exe_tables
import make_golden_paths as paths
import make_golden_swamp as swamp

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'tests/golden/synthetic/effects.json'
U32 = 0xffffffff
s16, s32, c_div = desert.s16, desert.s32, desert.c_div

THEME_ORG, THEME_SWP, THEME_SUB, THEME_VOL, THEME_JUN = 5, 7, 9, 10, 4
FROG_JUMP_TIME, FROG_QUICK_JUMP_TIME, FROG_SUPERJUMP_TIME = 6, 3, 15
SHADOW_OT_OFFSET, SHADOW_RGB = -4, 0x303030
FROG_SHADOW_OFFSETS = (
    ((-0x60, 0, 0x70), (0x60, 0, 0x70), (-0x60, 0, -0x60), (0x60, 0, -0x60)),
    ((-0x60, 0, 0x90), (0x60, 0, 0x90), (-0x60, 0, -0x60), (0x60, 0, -0x60)),
    ((-0x60, 0, 0xb0), (0x60, 0, 0xb0), (-0x60, 0, -0x80), (0x60, 0, -0x80)),
    ((-0x60, 0, 0xd0), (0x60, 0, 0xd0), (-0x60, 0, -0xb0), (0x60, 0, -0xb0)))
FROG_JUMP_SHADOW_OFFSETS = (0, 1, 2, 3, 2, 1)
FROG_JUMP_SHADOW_TEXTURES = ('im_frog_shadow0', 'im_frog_shadow1', 'im_frog_shadow2', 'im_frog_shadow2',
                             'im_frog_shadow2', 'im_frog_shadow1')
DES_ROCK_SHADOW_OFFSETS = ((-0x70, 0, 0x70), (0x70, 0, 0x70), (-0x70, 0, -0x70), (0x70, 0, -0x70))
TRAIL_RGB_START, TRAIL_RGB_MAX = 0x202020, 0x606060
TRAIL_RGB_INCREASE = TRAIL_RGB_DECREASE = 0x080808
TRAIL_DECREASE_TIMER, TRAIL_SECTIONS = 12, 6
FROG_TRAIL_OFFSETS = ((-0x40, -0x10, -0x20), (0x40, -0x10, -0x20))
TRAIL_HOP_TIMER, TRAIL_SUPERJUMP_TIMER = 16, 26
FROG_POLY_PIECE_POP_DURATION, FROG_POPPING_FIXED_OT = 32, 2
WORLD_GRAVITY = 0x2d800
POLY_PIECE_POP_ANG_ACC = (0x08, 0x0c, 0x10)
MR_SP3D_DEFAULT_SCALE, MR_SPALIST_FORCE_NEXT, MR_SPALIST_DEFAULT_SPEED = 4 << 16, 1, 1
FROG_POP_EXPLOSION_DURATION, SYSTEM_PERSPECTIVE, GAME_PERSPECTIVE = 30, 192, 0x100
EXPLOSION_OUTER = ((0, -0x1000), (0xb50, -0xb50), (0x1000, 0), (0xb50, 0xb50),
                   (0, 0x1000), (-0xb50, 0xb50), (-0x1000, 0), (-0xb50, -0xb50))
EXPLOSION_INNER = ((0, -0x800), (0x5a8, -0x5a8), (0x800, 0), (0x5a8, 0x5a8),
                   (0, 0x800), (-0x5a8, 0x5a8), (-0x800, 0), (-0x5a8, -0x5a8))
FROG_POP_EXPLOSION_COLOURS = (0x000400, 0x040004, 0x000404, 0x040400, 0x000104)
SCORE_SPRITE_LIFETIME, SCORE_VELOCITY_Y = 45, -0x8000
CROAK_INFLATE, CROAK_HOLD, CROAK_DEFLATE = 6, 4, 6
CROAK_MIN_SCALE = 0x200
CROAK_MODES = ('NONE', 'INFLATE', 'HOLD', 'DEFLATE')
PICKUP_OT_OFFSET, GOLD_GLOW_OT_OFFSET = -0x10, -0x30
SPLASH_ANIMLIST = (('NOP',), ('NOP',), ('NOP',), ('NOP',), ('SETSPEED', 2), ('SETSCALE', 8 << 16),
                   ('SETIMAGE', 'im_ripple_tim1'), ('SETIMAGE', 'im_ripple_tim2'), ('SETIMAGE', 'im_ripple_tim3'),
                   ('SETIMAGE', 'im_ripple_tim4'), ('SETIMAGE', 'im_ripple_tim5'), ('SETIMAGE', 'im_ripple_tim6'),
                   ('SETCOLOUR', 0x606060), ('SETIMAGE', 'im_ripple_tim6'), ('SETCOLOUR', 0x404040),
                   ('SETIMAGE', 'im_ripple_tim6'), ('SETCOLOUR', 0x202020), ('SETIMAGE', 'im_ripple_tim6'), ('KILL',))
SPRITE_CONTINUES = {'NOP': False, 'SETIMAGE': False, 'SETSPEED': True, 'SETSCALE': True, 'SETCOLOUR': True,
                    'KILL': False}


def trig(angle):
    """rcos/rsin with the project's shared rounded 12-bit table."""
    return paths.trig(angle)


def rot_apply(matrix, vector):
    """MRApplyRotMatrix: MR_VEC components (row · vector) >> 12, arithmetic."""
    return [s32(sum(matrix[3 * row + k] * vector[k] for k in range(3)) >> 12) for row in range(3)]


def y_rotation(angle):
    """A rotation about world Y from the rounded table, laid out like MRTemp_matrix in UpdateEffects."""
    cos, sin = trig(angle)
    return [cos, 0, sin, 0, 0x1000, 0, -sin, 0, cos]


def rgb(value):
    """MR_SET32 on a CVEC: the low byte lands in r."""
    return [value & 0xff, (value >> 8) & 0xff, (value >> 16) & 0xff]


# ---------------------------------------------------------------- generator parameters

def generator_records():
    """The PARTICLE.C MR_PGEN_INIT initialisers, the callbacks they name and their PSX-source colour/OT/add rules."""
    slip_rule = dict(colour='grey=min(pt_lifetime<<2,255)', ot='otz+FROG_EFFECT_SLIP_OT_OFFSET, drawn when 0<otz<ot_size',
                     size='xofs=((te_w*user_data_1)/otz)>>8, drawn when xofs<0x60')
    return [
        dict(name='PGIN_frog_slip_effect', texture_source='user_data_2', line=332, type=2, flags=0, max_particles=50, generator_life=-1,
             particle_min_life=6, particle_max_life=12, gravity_16=-(1 << 16), user_data_1=96 << 10,
             user_data_1_text='96<<10', texture='im_frog_smoke1', semi_transparent=True, ot_offset=-0x10,
             prim_init='Particle_ft4_prim_init', move='FrogEffectSlippingMove', display='FrogEffectSlippingDisp',
             gravity_applied=True, add='one particle when rand()&1 and the frog velocity is non-zero; '
             'velocity=R*((rand()&7)-4,-0xf,-(rand()&7)-4)<<16; position=(t+R*((rand()&0x4f)-0x28,0x1f,0))<<16; '
             'lifetime=particle_max_life', **slip_rule),
        dict(name='PGIN_frog_water_bubble', texture_source='user_data_2', line=350, type=2, flags=0, max_particles=20, generator_life=90,
             particle_min_life=12, particle_max_life=12, gravity_16=-(1 << 16), user_data_1=64 << 9,
             user_data_1_text='64<<9', texture='im_wake2', semi_transparent=True, ot_offset=-0x10,
             prim_init='Particle_ft4_prim_init', move='FrogEffectBubbleMove', display='FrogEffectSlippingDisp',
             gravity_applied=False, add='one particle every move while active; max_particles-=1 when '
             'generator_life%10==0; velocity=R*((rand()&0x16)-8,-6,(rand()&0x16)-8)<<16; position=t<<16; '
             'lifetime=particle_max_life', **slip_rule),
        dict(name='PGIN_frog_on_fire', texture_source='user_data_2', line=370, type=2, flags=0, max_particles=150, generator_life=-1,
             particle_min_life=40, particle_max_life=50, gravity_16=-(1 << 16), user_data_1=120 << 9,
             user_data_1_text='120<<9', texture='im_frog_smoke1', semi_transparent=True, ot_offset=-0x10,
             prim_init='Particle_ft4_prim_init', move='FrogEffectFireMove', display='FrogEffectFireDisp',
             gravity_applied=False, colour='r=255, g=min(255,pt_user), b=0; pt_user-=4 per render, 0 when <=2',
             ot='otz+FROG_EFFECT_SLIP_OT_OFFSET, drawn when 0<otz<ot_size',
             size='xofs=(((te_w*user_data_1*pt_user)>>4)/otz)>>8, drawn when xofs<0x60',
             add='one particle when rand()&1; pt_user=particle_max_life+(rand()&32); velocity=(0,-(rand()&15)<<15,0); '
             'position=(t+R*((rand()&63)-32,-0x10,(rand()&63)-32))<<16; lifetime=particle_max_life'),
        dict(name='PGIN_hilite_exhaust', texture_source='user_data_2', line=123, type=2, flags=0, max_particles=25, generator_life=-1,
             particle_min_life=5, particle_max_life=8, gravity_16=-(1 << 16), user_data_1=64 << 9,
             user_data_1_text='64<<9', texture='im_tongue_tip', semi_transparent=True, ot_offset=0x10,
             prim_init='Particle_ft4_prim_init', move='Hilite_exhaust_move', display='Hilite_exhaust_disp',
             gravity_applied=True, colour='life=min(pt_lifetime<<4,255); rgb=min(life, owner mesh mi_colour_scale) '
             'per channel, 128 without a live entity', ot='otz+HILITE_EXHAUST_OT_OFFSET, drawn when 0<otz<ot_size',
             size='xofs=((te_w*user_data_1)/otz)>>8, drawn when xofs<0x60',
             add='one particle when active and rand()&1; velocity=es_lwtrans*((rand()&0xf)-8,(rand()&0xf)-8,-0x10)<<16; '
             'position=es_lwtrans.t<<16; pt_user=0; lifetime=particle_max_life'),
        dict(name='PGIN_hilite_dust', texture_source='user_data_2_list', line=154, type=2, flags=0, max_particles=14, generator_life=-1,
             particle_min_life=12, particle_max_life=12, gravity_16=-(1 << 16), user_data_1=64 << 11,
             user_data_1_text='64<<11', texture='Hilite_dust_textures',
             textures=['im_bison1', 'im_bison2', 'im_bison3', 'im_bison4', 'im_bison5', 'im_bison6'],
             semi_transparent=True, ot_offset=-0x10, prim_init='Particle_ft4_prim_list_init',
             move='Hilite_exhaust_move', display='Hilite_dust_disp', gravity_applied=True,
             colour='grey=min(pt_lifetime<<4,255); image=Hilite_dust_textures[pt_user], pt_user+=1 per render, '
             'lifetime=0 at the NULL terminator; WIN95 sets the image tpage ABR to 1',
             ot='otz+FROG_EFFECT_SLIP_OT_OFFSET, drawn when 0<otz<ot_size',
             size='xofs=((te_w*user_data_1)/otz)>>8, drawn when xofs<0x60',
             add='as PGIN_hilite_exhaust (Hilite_exhaust_add)'),
        dict(name='PGIN_hilite_fire', texture_source='user_data_2', line=173, type=2, flags=0, max_particles=40, generator_life=-1,
             particle_min_life=10, particle_max_life=20, gravity_16=-(1 << 16), user_data_1=70 << 10,
             user_data_1_text='70<<10', texture='im_frog_smoke1', semi_transparent=True, ot_offset=-0x10,
             prim_init='Particle_ft4_prim_init', move='Hilite_fire_move', display='Hilite_fire_disp',
             gravity_applied=False, colour='r=255, g=min(255,pt_user<<1), b=0; pt_user-=1 per move, 0 when <2',
             ot='max(1,otz+FROG_EFFECT_SLIP_OT_OFFSET), drawn when otz<ot_size',
             size='xofs=(((te_w*user_data_1*pt_user)>>4)/otz)>>8, drawn when xofs<0x60',
             add='one particle every move; pt_user=particle_max_life+(rand()&0x1f); '
             'velocity=(((rand()&0xf)-8)<<16 per axis, x then y then z); position=(es_lwtrans.t+es_lwtrans*(0,0,-100))<<16; '
             'lifetime=particle_max_life'),
        dict(name='PGIN_frog_pop_explosion', texture_source=None, line=104, type=2, flags=0x10, max_particles=8 + 2,
             generator_life=FROG_POP_EXPLOSION_DURATION, particle_min_life=0, particle_max_life=0, gravity_16=0,
             user_data_1=48 << 7, user_data_1_text='48<<7', texture=None, semi_transparent=True,
             ot_offset=FROG_POPPING_FIXED_OT, prim_init='Frog_pop_explosion_prim_init',
             move='Particle_no_geometry_move', display='Frog_pop_explosion_disp', gravity_applied=False,
             colour='outer vertices (life*8,0,0); inner vertices life*Frog_pop_explosion_colours[player]; ABR 1',
             ot='fixed FROG_POPPING_FIXED_OT', size='see pop_ring', add='none (no geometry)'),
        dict(name='PGIN_pickup_explosion', texture_source=None, line=86, type=2, flags=0x10, max_particles=8 + 2, generator_life=30,
             particle_min_life=0, particle_max_life=0, gravity_16=0, user_data_1=48 << 7, user_data_1_text='48<<7',
             texture=None, semi_transparent=True, ot_offset=20, prim_init='Frog_pop_explosion_prim_init',
             move='Particle_no_geometry_move', display='Pickup_explosion_disp', gravity_applied=False,
             colour='PSX only: life*0x080808 grey; the display body is inside #ifdef PSX, so PC draws nothing',
             ot='PSX only: max(0,otz+PICKUP_EXPLOSION_OT_OFFSET)', size='PSX only', add='none (no geometry)'),
        dict(name='PGIN_pickup', texture_source='code', line=67, type=2, flags=0, max_particles=2, generator_life=-1, particle_min_life=0,
             particle_max_life=0, gravity_16=0, user_data_1=0, user_data_1_text='Pickup_data[kind] written before creation',
             texture='im_tongue_tip', semi_transparent=True, ot_offset=PICKUP_OT_OFFSET, prim_init='Pickup_prim_init',
             move='Pickup_move', display='Pickup_disp', gravity_applied=False,
             colour='glow rgb=Pickup_data word 0 (low byte r), PC a0=0x80; image rgb 0x808080',
             ot='otz+PICKUP_OT_OFFSET, drawn when 0<otz<ot_size and |sy|<0x300',
             size='glow half=((te_w*((rsin(a)+0x3800)<<3))/otz)>>shift; image half=((te_w*Pickup_data word 1)/otz)>>shift; '
             'shift 9 with more than two viewports, else 8', add='none: particle 0 indexes the image list, particle 1 is the pulse angle'),
        dict(name='PGIN_gold_frog_glow', texture_source='code', line=429, type=2, flags=0, max_particles=1, generator_life=-1,
             particle_min_life=0, particle_max_life=0, gravity_16=0, user_data_1=0, user_data_1_text='0',
             texture='im_tongue_tip', semi_transparent=True, ot_offset=GOLD_GLOW_OT_OFFSET,
             prim_init='Gold_frog_glow_prim_init', move='Gold_frog_glow_move', display='Gold_frog_glow_disp',
             gravity_applied=False, colour='MR_SET32(r0,0xaaaaa): (170,170,10), PC a0=0x80',
             ot='otz-0x30, drawn when 0<otz<ot_size and |sy|<0x300; WIN95 z0..z3=otz',
             size='half=((im_tongue_tip.te_w*((rsin(a)+0x3800)<<3))/otz)>>8, >>9 with more than two viewports',
             add='none: particle 0 is the pulse angle'),
        dict(name='PGIN_for_swarm', texture_source='user_data_2', line=31, type=2, flags=0x10, max_particles=3, generator_life=-1,
             particle_min_life=0, particle_max_life=0, gravity_16=0, user_data_1=0, user_data_1_text='0',
             texture='im_for_swarm', semi_transparent=False, ot_offset=-0x20, prim_init='For_swarm_prim_init',
             move='Particle_no_geometry_move', display='For_swarm_disp', gravity_applied=False,
             colour='rgb 0x808080', ot='max(0,otz+FOR_SWARM_OT_OFFSET) of the swarm centre, drawn when otz<ot_size',
             size='quad corners (+-0x80,+-0x80,0) in a camera-facing frame per sw_positions entry', add='none (no geometry)'),
        dict(name='PGIN_for_swarm_multiplayer', texture_source='user_data_2', line=49, type=2, flags=0x10, max_particles=1, generator_life=-1,
             particle_min_life=0, particle_max_life=0, gravity_16=0, user_data_1=0, user_data_1_text='0',
             texture='im_for_swarm', semi_transparent=False, ot_offset=-0x20, prim_init='For_swarm_prim_init',
             move='Particle_no_geometry_move', display='For_swarm_disp', gravity_applied=False,
             colour='rgb 0x808080', ot='as PGIN_for_swarm', size='as PGIN_for_swarm', add='none (no geometry)'),
        dict(name='PGIN_stone_to_gold_frog', texture_source='user_data_2', line=411, type=2, flags=0, max_particles=100, generator_life=30,
             particle_min_life=15, particle_max_life=20, gravity_16=-(1 << 16), user_data_1=64 << 9,
             user_data_1_text='64<<9', texture='im_frog_smoke1', semi_transparent=True, ot_offset=-0x10,
             prim_init='Particle_ft4_prim_init', move='Gold_frog_particle_move', display='FrogEffectSlippingDisp',
             gravity_applied=True, add='one particle when active and rand()&1; pt_user=min(4096,particle_max_life*(rand()&31)); '
             'velocity=owner*((rand()&0x15)-7,-5,(rand()&0x15)-7)<<16; position=owner.t<<16; lifetime=particle_max_life',
             **slip_rule),
    ]


def generator_cases():
    cases = []
    for record in generator_records():
        expected = dict(record)
        name = expected.pop('name')
        cases.append(dict(input=dict(name=name), expected=expected))
    return cases


# ---------------------------------------------------------------- shadows

def shadow_phase(case):
    """UpdateFrogEffects: the jump phase that picks the shadow offsets and texture."""
    if case['mode'] != 'jumping' or case.get('on_spot'):
        count = 0
    else:
        if case['superjump']:
            count = c_div((FROG_SUPERJUMP_TIME - case['fr_count']) * FROG_JUMP_TIME, FROG_SUPERJUMP_TIME)
        else:
            count = FROG_JUMP_TIME - case['fr_count']
        count = max(0, min(FROG_JUMP_TIME - 1, count))
    return dict(count=count, offsets_table=FROG_JUMP_SHADOW_OFFSETS[count] + 1,
                offsets=[list(v) for v in FROG_SHADOW_OFFSETS[FROG_JUMP_SHADOW_OFFSETS[count]]],
                texture=FROG_JUMP_SHADOW_TEXTURES[count])


def quadrant(rotation):
    """MISC.C GetWorldYQuadrantFromMatrix on m[2][2] and m[0][2]."""
    m22, m02 = rotation[8], rotation[2]
    if abs(m22) > abs(m02):
        return 0 if m22 > 0 else 2
    return 1 if m02 > 0 else 3


def shadow_update(case):
    """UpdateEffects EFFECT_TYPE_SHADOW (not static): corner XZ, split decision, split polys and UVs; heights are named, not computed."""
    offsets, t = case['offsets'], case['translation']
    base_x, base_z = case['grid_base']
    tex = case['texture_uv']

    def gx(value):
        return (value - base_x) >> 8

    def gz(value):
        return (value - base_z) >> 8

    reordered, quad = None, None
    if case['no_rotation']:
        vec = [[s32(t[a] + off[a]) for a in range(3)] for off in offsets]
        x0, z0, x1 = gx(vec[0][0]), gz(vec[0][2]), gx(vec[1][0])
        x2, z2 = gx(vec[2][0]), gz(vec[2][2])
        reordered = x0 != x1
        if reordered:
            temp = vec[2]
            vec[2], vec[0], vec[1], vec[3] = vec[0], vec[1], vec[3], temp
            x2, z2 = x0, z0
            z0 = gz(vec[0][2])
    else:
        quad = quadrant(case['rotation'])
        matrix = y_rotation(quad * 0x400)
        vec = [[s32(a + b) for a, b in zip(rot_apply(matrix, off), t)] for off in offsets]
        x0, x2, z0, z2 = gx(vec[0][0]), gx(vec[2][0]), gz(vec[0][2]), gz(vec[2][2])
    y = offsets[0][2] - offsets[2][2]
    corners = [[s16(v[0]), s16(v[2])] for v in vec]
    uv_full = [[tex['u0'], tex['v0']], [tex['u1'], tex['v1']], [tex['u2'], tex['v2']], [tex['u3'], tex['v3']]]

    def corner(x, z, height):
        return dict(x=s16(x), z=s16(z), height=height)

    if not (x0 != x2 or z0 != z2):
        polys = [[corner(v[0], v[2], 'grid') for v in vec]]
        return dict(quadrant=quad, reordered=reordered, corners=corners, split=False, alignment=None,
                    polys=polys, uv=[uv_full])
    v0, v1, v2, v3 = vec

    def lerp(square, a, b, axis):
        return f'square{square}:{a}+(({axis}&0xff)*({b}-{a}))>>8'

    if v0[2] - v2[2] > 0x40:
        alignment = 'N'
        line = v0[2] & ~0xff
        p0 = [corner(v0[0], line, lerp(0, 'v2', 'v3', 'x')), corner(v1[0], v1[2] & ~0xff, lerp(0, 'v2', 'v3', 'x'))]
        p1 = [corner(v2[0], line, lerp(1, 'v0', 'v1', 'x')), corner(v3[0], v1[2] & ~0xff, lerp(1, 'v0', 'v1', 'x'))]
        split_v = c_div((v0[2] & 0xff) * tex['h'], y)
    elif v0[0] - v2[0] > 0x40:
        alignment = 'E'
        p0 = [corner(v0[0] & ~0xff, v0[2], lerp(0, 'v2', 'v0', 'z')), corner(v1[0] & ~0xff, v1[2], lerp(0, 'v2', 'v0', 'z'))]
        p1 = [corner(v0[0] & ~0xff, v2[2], lerp(1, 'v3', 'v1', 'z')), corner(v1[0] & ~0xff, v3[2], lerp(1, 'v3', 'v1', 'z'))]
        split_v = c_div((v0[0] & 0xff) * tex['h'], y)
    elif v0[2] - v2[2] < -0x40:
        alignment = 'S'
        p0 = [corner(v0[0], v2[2] & ~0xff, lerp(0, 'v0', 'v1', 'x')), corner(v1[0], v3[2] & ~0xff, lerp(0, 'v0', 'v1', 'x'))]
        p1 = [corner(v2[0], v2[2] & ~0xff, lerp(1, 'v2', 'v3', 'x')), corner(v3[0], v3[2] & ~0xff, lerp(1, 'v2', 'v3', 'x'))]
        split_v = c_div((0x100 - (v0[2] & 0xff)) * tex['h'], y)
    else:
        alignment = 'W'
        p0 = [corner(v2[0] & ~0xff, v0[2], lerp(0, 'v3', 'v1', 'z')), corner(v3[0] & ~0xff, v1[2], lerp(0, 'v3', 'v1', 'z'))]
        p1 = [corner(v2[0] & ~0xff, v2[2], lerp(1, 'v2', 'v0', 'z')), corner(v3[0] & ~0xff, v3[2], lerp(1, 'v2', 'v0', 'z'))]
        split_v = c_div((0x100 - (v0[0] & 0xff)) * tex['h'], y)
    split_v = (tex['v0'] + split_v) & 0xff
    poly0 = [corner(v0[0], v0[2], 'grid'), corner(v1[0], v1[2], 'grid')] + p0
    poly1 = p1 + [corner(v2[0], v2[2], 'grid'), corner(v3[0], v3[2], 'grid')]
    uv0 = [uv_full[0], uv_full[1], [tex['u2'], split_v], [tex['u3'], split_v]]
    uv1 = [[tex['u0'], split_v], [tex['u1'], split_v], uv_full[2], uv_full[3]]
    return dict(quadrant=quad, reordered=reordered, corners=corners, split=True, alignment=alignment,
                polys=[poly0, poly1], uv=[uv0, uv1], split_v=split_v)


TEXTURE_UV = dict(u0=8, v0=40, u1=39, v1=40, u2=8, v2=71, u3=39, v3=71, h=32)


def shadow_case(name, offsets, texture, translation, rotation=None, no_rotation=False, grid_base=(-0x2000, -0x2000)):
    case = dict(name=name, offsets=[list(v) for v in offsets], translation=list(translation),
                rotation=list(rotation) if rotation else None, no_rotation=no_rotation, grid_base=list(grid_base),
                texture_uv=dict(TEXTURE_UV))
    expected = shadow_update(case)
    expected.update(texture=texture, rgb=rgb(SHADOW_RGB), semi_transparent=True, ot_offset=SHADOW_OT_OFFSET)
    return dict(input=case, expected=expected)


def frog_shadow_phase_cases():
    sets = [dict(mode='stationary', superjump=False, fr_count=0)]
    sets += [dict(mode='jumping', superjump=False, fr_count=c) for c in range(FROG_JUMP_TIME, -1, -1)]
    sets += [dict(mode='jumping', superjump=False, fr_count=c) for c in (FROG_QUICK_JUMP_TIME, 2, 1)]
    sets += [dict(mode='jumping', superjump=True, fr_count=c) for c in range(FROG_SUPERJUMP_TIME, -1, -1)]
    sets += [dict(mode='jumping', superjump=True, fr_count=16), dict(mode='jumping', superjump=False, fr_count=3, on_spot=True)]
    return [dict(input=case, expected=shadow_phase(case)) for case in sets]


def frog_shadow_cases():
    out = []
    rotations = [y_rotation(a) for a in (0, 0x400, 0x800, 0xc00, 0x180, 0x380, 0x200)]
    for phase in range(FROG_JUMP_TIME):
        table = FROG_SHADOW_OFFSETS[FROG_JUMP_SHADOW_OFFSETS[phase]]
        for rotation in rotations[:4]:
            out.append(shadow_case(f'phase{phase}', table, FROG_JUMP_SHADOW_TEXTURES[phase], (0x80, -64, 0x80), rotation))
    for index, rotation in enumerate(rotations[4:]):
        out.append(shadow_case(f'oblique{index}', FROG_SHADOW_OFFSETS[0], FROG_JUMP_SHADOW_TEXTURES[0],
                               (0x80 - 0x1000, 32, 0x80 + 0x200), rotation))
    out.append(shadow_case('negative_world', FROG_SHADOW_OFFSETS[3], FROG_JUMP_SHADOW_TEXTURES[3],
                           (-0x2980, -0x300, -0x1d80), rotations[1]))
    out.append(shadow_case('desert_rock', DES_ROCK_SHADOW_OFFSETS, 'im_gen_shadow', (0x80, 0, 0x80), None, True))
    out.append(shadow_case('desert_rock_rotated_frame', DES_ROCK_SHADOW_OFFSETS, 'im_gen_shadow', (0x80, 0, 0x80),
                           rotations[1], True))
    out.append(shadow_case('tumbleweed_rotated', DES_ROCK_SHADOW_OFFSETS, 'im_gen_shadow', (0x80, 0, 0x80), rotations[3]))
    return out


def shadow_split_cases():
    """Corners straddling a 256-unit grid line in every alignment, plus the NO_ROTATION reorder that never splits."""
    out = []
    frog = FROG_SHADOW_OFFSETS[0]
    for quad in range(4):
        rotation = y_rotation(quad * 0x400)
        out.append(shadow_case(f'offcentre_q{quad}', frog, 'im_frog_shadow0', (0x80 + 0x10, -0x40, 0x80 + 0x20), rotation))
        out.append(shadow_case(f'split_q{quad}_line', frog, 'im_frog_shadow0', (0x100, -0x40, 0x100), rotation))
        out.append(shadow_case(f'split_q{quad}_negative', FROG_SHADOW_OFFSETS[2], 'im_frog_shadow2',
                               (-0x1f0, 0x40, -0x210), rotation))
    out.append(shadow_case('straddle_x_only_q0', frog, 'im_frog_shadow0', (0x100, 0, 0x80 + 0x8), y_rotation(0)))
    out.append(shadow_case('grid_base_offset', frog, 'im_frog_shadow0', (0x80, 0, 0x80), y_rotation(0), False, (-0x2040, -0x1fc0)))
    out.append(shadow_case('rock_z_line', DES_ROCK_SHADOW_OFFSETS, 'im_gen_shadow', (0x80, 0, 0x100), None, True))
    out.append(shadow_case('rock_x_line', DES_ROCK_SHADOW_OFFSETS, 'im_gen_shadow', (0x100, 0, 0x80), None, True))
    out.append(shadow_case('rock_both_lines', DES_ROCK_SHADOW_OFFSETS, 'im_gen_shadow', (0x100, 0, 0x100), None, True))
    return out


# ---------------------------------------------------------------- hop trail

def hop_trail(case):
    """FROG.C hop trigger, EFFECTS.C UpdateEffects/ResetTrail trail update and RenderEffects section colours."""
    rotation = case['rotation']
    hops = {hop['tick']: hop['super'] for hop in case['hops']}
    timer, colour, current, display, reset = 0, 0, TRAIL_SECTIONS - 2, 0, False
    pairs = None
    rows = []

    def head(translation):
        return [[s16(a + b) for a, b in zip(rot_apply(rotation, off), translation)] for off in FROG_TRAIL_OFFSETS]

    for tick, translation in enumerate(case['translations']):
        if tick in hops:
            reset = True
            colour = (TRAIL_RGB_START + TRAIL_RGB_MAX) >> 1
            timer = TRAIL_SUPERJUMP_TIMER if hops[tick] else TRAIL_HOP_TIMER
        if reset:
            current, display, reset = TRAIL_SECTIONS - 2, 0, False
            pairs = [head(translation) for _ in range(TRAIL_SECTIONS)]
        if timer:
            timer -= 1
            if timer <= TRAIL_DECREASE_TIMER:
                if colour:
                    colour = (colour - TRAIL_RGB_DECREASE) & U32
            elif colour < TRAIL_RGB_MAX:
                colour += TRAIL_RGB_INCREASE
            pairs[current] = head(translation)
            current = TRAIL_SECTIONS - 1 if current == 0 else current - 1
            display = min(TRAIL_SECTIONS - 1, display + 1)
        row = dict(tick=tick, timer=timer, rgb=rgb(colour), display_sections=display, current_section=current,
                   drawn=timer != 0)
        if timer:
            order = [(current + 1 + k) % TRAIL_SECTIONS for k in range(display + 1)]
            colours, value = [rgb(colour)], s32(colour)
            for _ in range(display):
                value = max(0, value - 0x101010)
                colours.append(rgb(value))
            row.update(section_rgb=colours, pairs=[pairs[i] for i in order])
        rows.append(row)
    return dict(sections=TRAIL_SECTIONS, offsets=[list(v) for v in FROG_TRAIL_OFFSETS], abr=1, rows=rows)


def hop_trail_cases():
    identity = [0x1000, 0, 0, 0, 0x1000, 0, 0, 0, 0x1000]
    sets = [
        dict(name='hop', rotation=identity, hops=[dict(tick=0, super=False)],
             translations=[[0x80, -0x40, 0x80 + min(t, 6) * 42] for t in range(20)]),
        dict(name='superjump', rotation=identity, hops=[dict(tick=0, super=True)],
             translations=[[0x80, -0x40 - min(t, 15) * 30, 0x80 + min(t, 15) * 34] for t in range(30)]),
        dict(name='hop_east_rotated', rotation=y_rotation(0x400), hops=[dict(tick=0, super=False)],
             translations=[[0x80 + min(t, 6) * 42, 0, -0x180] for t in range(18)]),
        dict(name='rehop', rotation=identity, hops=[dict(tick=0, super=False), dict(tick=7, super=False),
                                                    dict(tick=14, super=True)],
             translations=[[0, 0, t * 37] for t in range(44)]),
    ]
    return [dict(input=case, expected=hop_trail(case)) for case in sets]


# ---------------------------------------------------------------- poly piece pop

def poly_piece(vertices):
    """CreateMeshPolyPieces: tri origin is the C /3 mean, quad origin the >>2 mean; vertices become origin-relative."""
    if len(vertices) == 3:
        origin = [s16(c_div(sum(v[a] for v in vertices), 3)) for a in range(3)]
    else:
        origin = [s16(sum(v[a] for v in vertices) >> 2) for a in range(3)]
    return origin, [[s16(v[a] - origin[a]) for a in range(3)] for v in vertices]


def poly_piece_pop(case):
    """FrogStartPolyPiecePop / LiveEntityStartPolyPiecePop, then UpdatePolyPiecePop and the RenderPolyPiecePop scale."""
    rotation, translation = case['matrix'][:9], case['matrix'][9:]
    pieces, positions, velocities = [], [], []
    for vertices in case['polygons']:
        origin, relative = poly_piece(vertices)
        vec = rot_apply(rotation, origin)
        position = [s32((translation[a] + vec[a]) << 16) for a in range(3)]
        vec[1] = s32(vec[1] - 0x80)
        velocity = [s32(v << 10) for v in paths.normalised(vec)]
        pieces.append(dict(origin=origin, vertices=relative, position=list(position), velocity=list(velocity)))
        positions.append(position)
        velocities.append(velocity)
    timer, angle, angular = FROG_POLY_PIECE_POP_DURATION, [0, 0, 0], [0, 0, 0]
    rows = []
    for tick in range(1, case['ticks'] + 1):
        if timer:
            timer -= 1
            angle = [s16(a + b) for a, b in zip(angle, angular)]
            angular = [s16(a + b) for a, b in zip(angular, POLY_PIECE_POP_ANG_ACC)]
            for position, velocity in zip(positions, velocities):
                velocity[1] = s32(velocity[1] + (WORLD_GRAVITY << 1))
                for a in range(3):
                    position[a] = s32(position[a] + velocity[a])
        rows.append(dict(tick=tick, timer=timer, rotation=list(angle), angular_velocity=list(angular),
                         scale=min(0x1200, timer << 8), positions=[list(p) for p in positions],
                         velocities_y=[v[1] for v in velocities]))
    return dict(duration=FROG_POLY_PIECE_POP_DURATION, ot=FROG_POPPING_FIXED_OT, lit=False,
                gravity_per_tick=WORLD_GRAVITY << 1, angular_acceleration=list(POLY_PIECE_POP_ANG_ACC),
                pieces=pieces, rows=rows)


def poly_piece_pop_cases():
    quad = [[-0x40, -0x20, 0x30], [0x40, -0x20, 0x30], [-0x40, -0x60, 0x30], [0x40, -0x60, 0x30]]
    tri = [[0x10, -0x50, -0x31], [-0x23, -0x10, 0x05], [0x07, -0x7f, 0x11]]
    odd = [[-1, -1, -1], [-2, -2, -2], [-2, -1, 0]]
    flat = [[0, 0x80, 0], [1, 0x80, 0], [0, 0x80, 1], [1, 0x80, 1]]
    sets = [
        dict(name='identity', matrix=[0x1000, 0, 0, 0, 0x1000, 0, 0, 0, 0x1000, 0x180, -0x40, 0x380],
             polygons=[quad, tri, odd, flat], ticks=FROG_POLY_PIECE_POP_DURATION + 2),
        dict(name='turned', matrix=y_rotation(0x200) + [-0x1200, 0x100, 0x2300], polygons=[quad, tri],
             ticks=FROG_POLY_PIECE_POP_DURATION + 2),
    ]
    return [dict(input=case, expected=poly_piece_pop(case)) for case in sets]


# ---------------------------------------------------------------- sprites and popups

def splash_timeline(case):
    """MRCreate3DSprite defaults, then MRProcessSpriteAnim once per MRUpdateObjects over the splash animlist."""
    image, scale, colour, speed, count, pc = None, MR_SP3D_DEFAULT_SCALE, 0x808080, MR_SPALIST_DEFAULT_SPEED, \
        MR_SPALIST_FORCE_NEXT, 0
    rows, kill = [], None
    for tick in range(1, case['updates'] + 1):
        executed = []
        count -= 1
        if count == 0:
            while True:
                command = SPLASH_ANIMLIST[pc]
                name = command[0]
                executed.append(name)
                if name == 'SETSPEED':
                    speed = command[1]
                elif name == 'SETSCALE':
                    scale = command[1]
                elif name == 'SETCOLOUR':
                    colour = command[1]
                elif name == 'SETIMAGE':
                    image = command[1]
                if name != 'KILL':
                    pc += 1
                elif kill is None:
                    kill = tick
                count = speed
                if not SPRITE_CONTINUES[name]:
                    break
        rows.append(dict(tick=tick, executed=executed, image=image, scale=scale,
                         rgb=[(colour >> 16) & 0xff, (colour >> 8) & 0xff, colour & 0xff], speed=speed,
                         count=count, killed=kill is not None))
        if kill is not None:
            break
    return dict(animlist=[list(c) for c in SPLASH_ANIMLIST], initial_scale=MR_SP3D_DEFAULT_SCALE,
                initial_rgb=[0x80, 0x80, 0x80], kill_update=kill, rows=rows)


def splash_timeline_cases():
    return [dict(input=dict(list=name, updates=30), expected=splash_timeline(dict(updates=30)))
            for name in ('FrogSplashAnimList', 'TurtleSplashAnimList')]


def splash_offsets(case, org_forms):
    """scripter.c ENTSCR_CREATE_3D_SPRITE: ORG turtles get formid-18 ripples from (0,-0x40,-(formid-19)*128) stepping z by 0x100."""
    common = dict(animlist='TurtleSplashAnimList', in_xz_plane=True, ot_offset=-0x10)
    if case['theme'] != THEME_ORG:
        return dict(source_defined=True, sprites=[[0, 0, 0]], **common)
    formid = case['formid']
    name = org_forms[formid] if 0 <= formid < len(org_forms) else None
    count = (formid - 18) & U32
    if count > 16:
        return dict(source_defined=False, form_name=name, reason='unsigned count wraps below form 18')
    offset = [0, -0x40, s16(-((formid - 19) * 128))]
    sprites = []
    for _ in range(count):
        sprites.append(list(offset))
        offset[2] = s16(offset[2] + 0x100)
    return dict(source_defined=True, form_name=name, sprites=sprites, **common)


def splash_offset_cases(org_forms):
    sets = [dict(theme=THEME_ORG, formid=f) for f in (17, 18, 19, 20, 21)]
    sets += [dict(theme=THEME_JUN, formid=19), dict(theme=THEME_SUB, formid=20)]
    return [dict(input=case, expected=splash_offsets(case, org_forms)) for case in sets]


def pop_ring_row(life, game_timer, colour):
    """Frog_pop_explosion_disp: scale, rotation by Game_timer<<7, octagon offsets before projection, vertex colours."""
    scale = s16(((FROG_POP_EXPLOSION_DURATION - life) + 10) << 1)
    angle = (game_timer << 7) & 0xfff
    cos_t, sin_t = trig(angle)
    cos, sin = s16((cos_t * scale) >> 12), s16((sin_t * scale) >> 12)

    def point(offset):
        ox, oy = offset
        return [(cos * ox - sin * oy) >> 12, (sin * ox + cos * oy) >> 12]

    inner = (life * colour) & 0xffffff
    return dict(life=life, game_timer=game_timer, scale=scale, angle=angle, cos=cos, sin=sin,
                outer=[point(o) for o in EXPLOSION_OUTER], inner=[point(o) for o in EXPLOSION_INNER],
                outer_rgb=rgb((life * 8) & 0xffffff), inner_rgb=rgb(inner))


def pop_ring(case):
    rows = [pop_ring_row(life, timer, case['colour']) for life, timer in case['rows']]
    return dict(duration=FROG_POP_EXPLOSION_DURATION, ot=FROG_POPPING_FIXED_OT, abr=1,
                projection=dict(h=GAME_PERSPECTIVE, z=SYSTEM_PERSPECTIVE), drawn_when='generator_life>0', rows=rows)


def pop_ring_cases():
    out = []
    for player, colour in enumerate(FROG_POP_EXPLOSION_COLOURS):
        start = [0, 7, 0x1f, 0xffffffe0, 100][player]
        rows = [[life, (start + FROG_POP_EXPLOSION_DURATION - 1 - life) & U32]
                for life in range(FROG_POP_EXPLOSION_DURATION - 1, 0, -1)]
        case = dict(player=player, colour=colour, rows=rows)
        out.append(dict(input=case, expected=pop_ring(case)))
    return out


def score_popup(case):
    """CreateScoreSprite then UpdateScoreSprites: rise by -0x8000 (16.16) per update, fade up 3 updates, fade down, kill at 0."""
    y, timer, rows = s32(case['y'] << 16), SCORE_SPRITE_LIFETIME, []
    while True:
        timer -= 1
        if timer == 0:
            rows.append(dict(tick=SCORE_SPRITE_LIFETIME - timer, timer=0, killed=True))
            break
        y = s32(y + SCORE_VELOCITY_Y)
        if SCORE_SPRITE_LIFETIME - timer < 4:
            grey = (SCORE_SPRITE_LIFETIME - timer) * 0x20
        else:
            grey = (0x80 * timer) // SCORE_SPRITE_LIFETIME
        rows.append(dict(tick=SCORE_SPRITE_LIFETIME - timer, timer=timer, killed=False, y_16=y,
                         screen=[case['x'], y >> 16], rgb=[grey, grey, grey]))
    return dict(lifetime=SCORE_SPRITE_LIFETIME, start=[case['x'], case['y']], start_rgb=[0x80, 0x80, 0x80],
                kill_update=rows[-1]['tick'], rows=rows)


def score_popup_cases():
    return [dict(input=case, expected=score_popup(case)) for case in (dict(x=160, y=120), dict(x=-4, y=3))]


# ---------------------------------------------------------------- frog colours and croak

def drown_tint(case):
    """UpdateFrogBaseColour while dying by DROWN: scale bytes keep only the low 8 bits after a floor at 0."""
    dy = s32(case['dy'])
    red = max(s32(-s32(dy << 4)) >> 9, 0)
    if case['theme'] == THEME_SWP:
        green = max((s32(dy << 5) >> 9) + 128, 0)
        blue = max((s32(-s32(dy << 5)) >> 9) + 32, 0)
    else:
        green = max((s32(-s32(dy << 5)) >> 9) + 64, 0)
        blue = max((s32(-s32(dy << 5)) >> 9) + 192, 0)
    raw = [red, green, blue]
    return dict(unmasked=raw, colour_scale=[v & 0xff for v in raw], custom_ambient=[32, 64, 64])


def edge_fade(case):
    """UpdateFrogBaseColour outside cave-light maps: grey 0x80 minus the half sum of the X and Z overshoot."""
    if case['cave_light']:
        return dict(applied=False)
    x, z = case['position']
    tl, br = case['top_left'], case['bottom_right']
    x_offset = tl[0] - x if x < tl[0] else (x - br[0] if br[0] < x else 0)
    z_offset = br[1] - z if z < br[1] else (z - tl[1] if tl[1] < z else 0)
    fade = s32(((x_offset + z_offset) & U32) // 2)
    grey = max(0, 0x80 - fade)
    return dict(applied=True, x_offset=x_offset, z_offset=z_offset, grey=grey, colour_scale=rgb(s32(grey * 0x010101)))


def frog_tint_cases():
    drown = [dict(input=dict(theme=theme, dy=dy), expected=drown_tint(dict(theme=theme, dy=dy)))
             for theme in (THEME_SUB, THEME_SWP) for dy in (-64, -16, -1, 0, 1, 8, 32, 200, 1000, -10000, 20000)]
    edges = [
        dict(position=[0, 0], top_left=[-0x1000, 0x1000], bottom_right=[0x1000, -0x1000], cave_light=False),
        dict(position=[-0x1020, 0], top_left=[-0x1000, 0x1000], bottom_right=[0x1000, -0x1000], cave_light=False),
        dict(position=[0x1041, 0x1041], top_left=[-0x1000, 0x1000], bottom_right=[0x1000, -0x1000], cave_light=False),
        dict(position=[0, -0x1101], top_left=[-0x1000, 0x1000], bottom_right=[0x1000, -0x1000], cave_light=False),
        dict(position=[0x1000, 0x1000], top_left=[-0x1000, 0x1000], bottom_right=[0x1000, -0x1000], cave_light=False),
        dict(position=[0x1200, 0x1200], top_left=[-0x1000, 0x1000], bottom_right=[0x1000, -0x1000], cave_light=True),
    ]
    char = dict(custom_ambient=[24, 0, 0], colour_scale=[24, 0, 0], particle='PGIN_frog_on_fire',
                particle_offset=[0, -80, 40], animation='FROG_ANIMATION_DROWN', deaths=['DROWN', 'FLOP'],
                theme=THEME_VOL)
    return dict(drown=drown, edge_fade=[dict(input=c, expected=edge_fade(c)) for c in edges],
                volcano_char=dict(input=dict(theme=THEME_VOL), expected=char))


def croak_timeline(case):
    """FrogUpdateCroak from the press: inflate 6, hold 4, deflate 6, unsigned light radii, scale 0x200..0xc00."""
    max_r2, min_r2 = case['light_max_r2'] & U32, case['light_min_r2'] & U32
    saved_max, saved_min, rate = max_r2, min_r2, (max_r2 // CROAK_INFLATE) & U32
    mode, timer, scale = 0, 0, CROAK_MIN_SCALE
    if case['high_poly']:
        mode, timer = 1, CROAK_INFLATE
    rows = [dict(tick=0, mode=CROAK_MODES[mode], timer=timer, max_r2=max_r2, min_r2=min_r2, scale=scale)]
    restored = None
    for tick in range(1, case['ticks'] + 1):
        if mode == 1:
            timer -= 1
            max_r2, min_r2 = (max_r2 + rate) & U32, (min_r2 + rate) & U32
            scale = ((CROAK_INFLATE - timer) * 0xa00) // CROAK_INFLATE + CROAK_MIN_SCALE
            if timer == 0:
                mode, timer = 2, CROAK_HOLD
        elif mode == 2:
            timer -= 1
            if timer == 0:
                mode, timer = 3, CROAK_DEFLATE
        elif mode == 3:
            timer -= 1
            max_r2, min_r2 = (max_r2 - rate) & U32, (min_r2 - rate) & U32
            scale = (timer * 0xa00) // CROAK_DEFLATE + CROAK_MIN_SCALE
            if timer == 0:
                mode, max_r2, min_r2 = 0, saved_max, saved_min
                restored = tick
        rows.append(dict(tick=tick, mode=CROAK_MODES[mode], timer=timer, max_r2=max_r2, min_r2=min_r2, scale=scale))
    return dict(rate=rate, saved=[saved_max, saved_min], restored_tick=restored, rows=rows)


def croak_cases():
    sets = [
        dict(light_max_r2=0x40000000, light_min_r2=0x10000000, high_poly=True, ticks=18),
        dict(light_max_r2=1000003, light_min_r2=999, high_poly=True, ticks=18),
        dict(light_max_r2=0xfffffffb, light_min_r2=0xffffff00, high_poly=True, ticks=18),
        dict(light_max_r2=5, light_min_r2=0, high_poly=True, ticks=18),
        dict(light_max_r2=0x40000000, light_min_r2=0x10000000, high_poly=False, ticks=3),
    ]
    return [dict(input=case, expected=croak_timeline(case)) for case in sets]


# ---------------------------------------------------------------- glow pulses

def glow_magnitude(angle):
    """((rsin(angle)+0x3800)<<3), before the /otz>>shift projection."""
    return (trig(angle)[1] + 0x3800) << 3


def glow_rows(ticks):
    angle, rows = 0, []
    for tick in range(1, ticks + 1):
        angle = (angle + 0x100) & 0xfff
        rows.append(dict(tick=tick, angle=angle, magnitude=glow_magnitude(angle)))
    return rows


def glow_projection(case):
    """Half extents: ((te_w*mag)/otz)>>shift with shift 9 for more than two viewports, else 8, stored as MR_SHORT."""
    shift = 9 if case['viewports'] > 2 else 8
    mag = glow_magnitude(case['angle'])
    return dict(magnitude=mag, xofs=s16(c_div(case['w'] * mag, case['otz']) >> shift),
                yofs=s16(c_div(case['h'] * mag, case['otz']) >> shift))


def glow_family(kind):
    projections = [dict(w=30, h=30, otz=otz, angle=angle, viewports=vp)
                   for otz, angle, vp in ((40, 0, 1), (40, 0x400, 1), (40, 0xc00, 1), (300, 0x100, 1),
                                          (900, 0x700, 2), (40, 0x400, 4), (1, 0x400, 1))]
    constants = dict(pulse_step=0x100, angle_mask=0xfff, base=0x3800, magnitude_shift=3, semi_transparent=True,
                     pc_texture='glow_1727', c_texture='im_tongue_tip', drawn_when='0<otz<ot_size and |sy|<0x300')
    if kind == 'gold':
        constants.update(ot_offset=GOLD_GLOW_OT_OFFSET, c_rgb=rgb(0x0aaaaa), pc_rgb=[255, 255, 16], pulse_particle=0,
                         creation_offset=[0, -75, 30], created_inactive=True)
    else:
        constants.update(ot_offset=PICKUP_OT_OFFSET, rgb='Pickup_data[kind] word 0 (exe_pickups glow_colour)',
                         pulse_particle=1, image_half_size='((image te_w*Pickup_data[kind] word 1)/otz)>>shift')
    return [dict(input=dict(ticks=20), expected=dict(constants=constants, rows=glow_rows(20)))] + \
        [dict(input=p, expected=glow_projection(p)) for p in projections]


def cases():
    """Invent source-boundary inputs; no retail data or game outputs are consumed."""
    _, sections, _ = exe_tables.name_list('forms', '1997-09-12-psx-build57')
    return dict(generator_parameters=generator_cases(), frog_shadow_phase=frog_shadow_phase_cases(),
                frog_shadow=frog_shadow_cases(), shadow_split=shadow_split_cases(), hop_trail=hop_trail_cases(),
                poly_piece_pop=poly_piece_pop_cases(), splash_timeline=splash_timeline_cases(),
                splash_offsets=splash_offset_cases(sections['ORIGINAL']), pop_ring=pop_ring_cases(),
                score_popup=score_popup_cases(), frog_tint=frog_tint_cases(), croak_timeline=croak_cases(),
                gold_glow=glow_family('gold'), pickup_glow=glow_family('pickup'))


def main():
    """Verify reproducibility by default; rewrite only with an explicit flag."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    text = swamp.encode(cases()) + '\n'
    if args.write:
        OUTPUT.write_text(text)
    elif OUTPUT.read_text() != text:
        raise SystemExit('Effect facts differ; use --write only to deliberately regenerate')
    print('Effect facts verified')


if __name__ == '__main__':
    main()
