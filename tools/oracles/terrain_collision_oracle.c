#define main frozen_main_unused
#include "FROG.H"
#include "CAMERA.H"
#include "gamesys.H"
#include "GRID.H"
#include "EFFECTS.H"
#include "froganim.h"
#include "score.h"
#include "COLLIDE.H"
#include "LIBRARY.H"
#include "MAPVIEW.H"
#include "froguser.h"
#undef main
#include "gpu/mr_stub_gpu.h"
#undef main
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
__declspec(dllimport) unsigned long __stdcall SetErrorMode(unsigned long);
extern FROG_CONTROL_METHOD Frog_control_methods[];
extern MR_BOOL Recording_demo;
static int animations,sounds,scores,last_animation;
static MR_OBJECT pgen_object,sprite_object,particle_object;
static MR_PGEN pgen;
static MR_3DSPRITE sprite;
MR_OBJECT* __wrap_MRCreatePgen(MR_PGEN_INIT* init,MR_FRAME* frame,MR_ULONG flags,MR_SVEC* offset) { (void)init;(void)frame;(void)flags;(void)offset;pgen_object.ob_extra.ob_extra_pgen=&pgen;return &pgen_object; }
MR_OBJECT* __wrap_MRCreate3DSprite(MR_FRAME* frame,MR_ULONG flags,MR_VOID* anim) { (void)frame;(void)flags;(void)anim;sprite_object.ob_extra.ob_extra_3dsprite=&sprite;return &sprite_object; }
MR_OBJECT* __wrap_CreateParticleEffect(MR_VOID* owner,MR_ULONG type,MR_SVEC* offset) { (void)owner;(void)type;(void)offset;return &particle_object; }
void __wrap_GameAddObjectToViewports(MR_OBJECT* object) { (void)object; }
void __wrap_SetGameMainloopMode(MR_ULONG mode) { Game_mode=mode; }
void __wrap_FrogRequestAnimation(FROG* f,MR_ULONG a,MR_ULONG b,MR_ULONG c) { (void)f;(void)b;(void)c;last_animation=(int)a; animations++; }
MR_LONG __wrap_MRSNDPlaySound(MR_USHORT s,SndVolume* v,MR_USHORT f,MR_LONG p) { (void)s;(void)v;(void)f;(void)p; sounds++; return -1; }
SCORE_SPRITE* __wrap_AddFrogScore(FROG* f,MR_ULONG s,MR_MAT* m) { (void)f;(void)s;(void)m; scores++; return NULL; }
static MR_SVEC vertices[1024];
static MAP_F4 polygons[256];
static GRID_SQUARE squares[256];
static GRID_STACK stacks[256];
static MR_MAT matrix;
static EFFECT trail_effect;
static EFFECT shadow_effect;
static TRAIL trail;
static ZONE_HEADER zone_header;
static GENERAL_HEADER general_header;
static MR_ANIM_ENV steering_env;
static MR_ANIM_ENV_SINGLE steering_single;
static void setup(int blocked) {
    memset(Frogs,0,sizeof(FROG)*4); memset(Cameras,0,sizeof(CAMERA)*4);
    memset(MRInput,0,sizeof(MR_INPUT)*1); memset(&matrix,0,sizeof(matrix));
    memset(&trail,0,sizeof(trail)); memset(&trail_effect,0,sizeof(trail_effect));
    memset(&shadow_effect,0,sizeof(shadow_effect));
    srand(12345); animations=sounds=scores=0;last_animation=-1;
    Grid_xnum=Grid_znum=4; Grid_xlen=Grid_zlen=256; Grid_base_x=Grid_base_z=-512;
    Grid_xshift=Grid_zshift=8; Grid_squares=squares; Grid_stacks=stacks; Map_vertices=vertices;
    for(int i=0;i<16;i++) {
        int x=-512+(i%4)*256,z=-512+(i/4)*256;
        int xs[4]={x,x+256,x,x+256},zs[4]={z+256,z+256,z,z};
        for(int j=0;j<4;j++) { vertices[i*4+j].vx=xs[j];vertices[i*4+j].vy=0;vertices[i*4+j].vz=zs[j];polygons[i].mp_vertices[j]=i*4+j; }
        squares[i].gs_map_poly=&polygons[i]; squares[i].gs_flags=GRID_SQUARE_USABLE|GRID_SQUARE_SAFE;
        stacks[i].gs_numsquares=1;stacks[i].gs_index=i;
    }
    if(blocked) squares[9].gs_flags=0;
    matrix.m[0][0]=matrix.m[1][1]=matrix.m[2][2]=4096;
    matrix.t[0]=matrix.t[2]=-128;
    FROG* f=&Frogs[0]; f->fr_lwtrans=&matrix;f->fr_control_method=&Frog_control_methods[0];
    f->fr_grid_x=f->fr_grid_z=1;f->fr_grid_square=&squares[5]; f->fr_flags=FROG_ACTIVE|FROG_CONTROL_ACTIVE;
    f->fr_pos.vx=f->fr_pos.vz=-128*65536; f->fr_trail=&trail_effect;trail_effect.ef_extra=&trail;
    f->fr_shadow=&shadow_effect;
    Game_total_players=1;Game_start_timer=0;Game_flags=0;
    Recording_demo=FALSE;Cheat_control_toggle=FALSE;Game_mode=GAME_MODE_LEVEL_PLAY;
    Map_zone_header=&zone_header;
    Map_general_header=&general_header;
    general_header.gh_default_camera_source_ofs.vx=0;general_header.gh_default_camera_source_ofs.vy=-500;general_header.gh_default_camera_source_ofs.vz=-500;
    general_header.gh_default_camera_target_ofs.vx=general_header.gh_default_camera_target_ofs.vy=general_header.gh_default_camera_target_ofs.vz=0;
    Cameras[0].ca_mod_matrix.m[0][0]=Cameras[0].ca_mod_matrix.m[1][1]=Cameras[0].ca_mod_matrix.m[2][2]=4096;
    for(int i=0;i<4;i++) Cameras[0].ca_frog_controller_directions[i]=i;
}
static void emit(int scenario,int tick,const char* component) {
    FROG* f=&Frogs[0];
    MR_ULONG down=MRInput[0].in_pad_down,held=MRInput[0].in_pad_new;
    MR_ULONG masks[4]={f->fr_control_method->fc_up_control,f->fr_control_method->fc_right_control,
                      f->fr_control_method->fc_down_control,f->fr_control_method->fc_left_control};
    MR_ULONG logical_down=0,logical_held=0;
    for(int i=0;i<4;i++) { if(down&masks[i]) logical_down|=1<<i; if(held&masks[i]) logical_held|=1<<i; }
    if(down&f->fr_control_method->fc_superjump_control) logical_down|=16;
    if(held&f->fr_control_method->fc_superjump_control) logical_held|=16;
    printf("%d,%d,%s,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%lu,%ld,%ld,%ld,%d,%d,%d,%ld,%ld,%lu,%lu\n",scenario,tick,component,
        f->fr_pos.vx,f->fr_pos.vy,f->fr_pos.vz,f->fr_velocity.vx,f->fr_velocity.vy,f->fr_velocity.vz,
        f->fr_grid_x,f->fr_grid_z,f->fr_count,f->fr_flags,f->fr_mode,f->fr_current_key,f->fr_direction,animations,sounds,scores,
        f->fr_num_buffered_keys,f->fr_buffered_input_count,logical_down,logical_held);
}
static void emit_collision(int scenario,int tick,const char* phase) {
    FROG* f=&Frogs[0];
    printf("%d,%d,%s,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%lu,%ld,%ld,%ld,%d,%d,%d,%ld,%ld,%ld,%ld,%ld,%ld,%lu\n",scenario,tick,phase,
      f->fr_pos.vx,f->fr_pos.vy,f->fr_pos.vz,f->fr_velocity.vx,f->fr_velocity.vy,f->fr_velocity.vz,
      f->fr_grid_x,f->fr_grid_z,f->fr_count,f->fr_flags,f->fr_mode,f->fr_current_key,f->fr_direction,animations,sounds,scores,
      f->fr_old_y,f->fr_y,f->fr_lives,f->fr_death_count,f->fr_death_equate,f->fr_lwtrans->t[1],Game_mode);
}
static int collision_trace(void) {
    puts("scenario,tick,component,x16,y16,z16,vx16,vy16,vz16,grid_x,grid_z,count,flags,mode,input,direction,animation_requests,sound_requests,score_requests,old_y,target_y,lives,death_count,death_equate,matrix_y,game_mode");
    int heights[12]={512,513,1024,1025,1025,0,0,0,0,0,0,0};
    int flags[12]={3,3,3,3,259,7,5,4097,9,3,3,5};
    for(int scenario=0;scenario<12;scenario++) {
        setup(0);Game_total_viewports=0;Frogs[0].fr_lives=3;
        Game_map_theme=scenario==11 ? THEME_FOR : THEME_SUB;
        Game_map=0;Cheat_collision_toggle=FALSE;Cheat_infinite_lives_toggle=FALSE;
        Fade_top_left_pos.vx=-32767;Fade_top_left_pos.vz=32767;
        Fade_bottom_right_pos.vx=32767;Fade_bottom_right_pos.vz=-32767;
        Map_view_xnum=Map_view_znum=0;Map_view_xlen=Map_view_zlen=768;
        Theme_library[Game_map_theme].tb_death_height=30000;
        squares[9].gs_flags=flags[scenario];
        for(int j=0;j<4;j++) vertices[9*4+j].vy=heights[scenario];
        if(scenario==9) Fade_top_left_pos.vx=-127;
        if(scenario==10) { stacks[9].gs_numsquares=0;Theme_library[Game_map_theme].tb_death_height=100; }
        for(int tick=0;tick<90;tick++) {
            MRInput[0].in_pad_down=tick==0 ? Frogs[0].fr_control_method->fc_up_control : 0;
            MRInput[0].in_pad_new=MRInput[0].in_pad_down;MRFrame_number=tick;
            ControlFrog(&Frogs[0]);emit_collision(scenario,tick,"control");
            MoveFrog(&Frogs[0]);emit_collision(scenario,tick,"move");
            CollideFrog(&Frogs[0]);emit_collision(scenario,tick,"collision");
        }
    }
    return 0;
}
static int matrix_trace(void) {
    puts("scenario,direction,flags,square,m00,m01,m02,m10,m11,m12,m20,m21,m22,tx,ty,tz");
    int heights[5][4]={{0,0,0,0},{0,256,0,256},{-3,257,-131,121},{100,120,80,80},{300,-200,-100,400}};
    for(int scenario=0;scenario<7;scenario++) for(int direction=0;direction<4;direction++) {
        setup(0);FROG* f=&Frogs[0];f->fr_direction=direction;
        for(int j=0;j<4;j++) vertices[20+j].vy=heights[scenario<5?scenario:0][j];
        if(scenario==3) polygons[5].mp_vertices[3]=polygons[5].mp_vertices[2];
        if(scenario>=5) {
            matrix.m[0][0]=3000;matrix.m[0][1]=1000;matrix.m[0][2]=0;
            matrix.m[1][0]=0;matrix.m[1][1]=3500;matrix.m[1][2]=-1000;
            matrix.m[2][0]=100;matrix.m[2][1]=0;matrix.m[2][2]=3500;
            if(scenario==5) f->fr_grid_square=NULL;
            else f->fr_flags|=FROG_FREEFALL;
        }
        UpdateFrogMatrix(f);
        printf("%d,%d,%lu,%d",scenario,direction,f->fr_flags,f->fr_grid_square?5:-1);
        for(int i=0;i<3;i++) for(int j=0;j<3;j++) printf(",%d",matrix.m[i][j]);
        printf(",%ld,%ld,%ld\n",matrix.t[0],matrix.t[1],matrix.t[2]);
    }
    return 0;
}
static void emit_special(int scenario,int tick) {
    FROG* f=&Frogs[0];
    printf("%d,%d,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%lu,%ld,%ld,%ld,%ld,%ld,%ld,%d,%d,%d",scenario,tick,
      f->fr_pos.vx,f->fr_pos.vy,f->fr_pos.vz,f->fr_velocity.vx,f->fr_velocity.vy,f->fr_velocity.vz,
      f->fr_grid_x,f->fr_grid_z,f->fr_count,f->fr_flags,f->fr_mode,f->fr_direction,
      f->fr_grid_square ? (long)(f->fr_grid_square-squares):-1,
      (long)f->fr_target_pos.vx,(long)f->fr_target_pos.vy,(long)f->fr_target_pos.vz,animations,sounds,scores);
    for(int i=0;i<3;i++) for(int j=0;j<3;j++) printf(",%d",matrix.m[i][j]);
    printf(",%ld,%ld,%ld\n",matrix.t[0],matrix.t[1],matrix.t[2]);
}
static int special_trace(void) {
    puts("scenario,tick,x16,y16,z16,vx16,vy16,vz16,grid_x,grid_z,count,flags,mode,direction,square,target_x,target_y,target_z,animation_requests,sound_requests,score_requests,m00,m01,m02,m10,m11,m12,m20,m21,m22,tx,ty,tz");
    for(int scenario=0;scenario<8;scenario++) {
        setup(0);Game_map_theme=THEME_SUB;
        int simple=scenario>=4;int kind=scenario%4;
        squares[5].gs_flags=GRID_SQUARE_USABLE|(simple?GRID_SQUARE_SIMPLE_SLIPPY:GRID_SQUARE_SLIPPY);
        if(kind==1) { vertices[20].vy=vertices[21].vy=128;vertices[22].vy=vertices[23].vy=-128; }
        if(kind==2) squares[9].gs_flags=0;
        if(kind==3) { for(int j=0;j<4;j++) vertices[9*4+j].vy=-449; }
        ReactFrogWithGridFlags(&Frogs[0],squares[5].gs_flags);emit_special(scenario,-1);
        for(int tick=0;tick<15;tick++) { MoveFrog(&Frogs[0]);emit_special(scenario,tick); }
    }
    return 0;
}
static int modifier_trace(void) {
    puts("scenario,tick,flags,auto_timer,tongue_timer,quick_timer");
    for(int scenario=0;scenario<4;scenario++) {
        setup(0);FROG* f=&Frogs[0];f->fr_powerup_flags=7;
        f->fr_auto_hop_timer=scenario;f->fr_super_tongue_timer=scenario+1;f->fr_quick_jump_timer=scenario+2;
        for(int tick=0;tick<7;tick++) {
            UpdateFrogPowerUps(f);
            printf("%d,%d,%lu,%u,%u,%u\n",scenario,tick,f->fr_powerup_flags,f->fr_auto_hop_timer,f->fr_super_tongue_timer,f->fr_quick_jump_timer);
        }
    }
    return 0;
}
static int roll_trace(void) {
    puts("scenario,tick,x16,y16,z16,vx16,vy16,vz16,grid_x,grid_z,count,flags,mode,direction,square,target_x,target_y,target_z,animation_requests,sound_requests,score_requests,m00,m01,m02,m10,m11,m12,m20,m21,m22,tx,ty,tz");
    for(int scenario=0;scenario<5;scenario++) {
        setup(0);FROG* f=&Frogs[0];Game_map_theme=THEME_SUB;f->fr_lives=3;
        if(scenario==0) { squares[5].gs_flags=GRID_SQUARE_USABLE|GRID_SQUARE_BOUNCY; }
        else {
            squares[5].gs_flags=GRID_SQUARE_USABLE|GRID_SQUARE_CLIFF;
            if(scenario!=1) { vertices[20].vy=vertices[21].vy=128;vertices[22].vy=vertices[23].vy=-128; }
            if(scenario==2) { for(int j=0;j<4;j++) vertices[36+j].vy=128; }
            if(scenario==3) { stacks[9].gs_numsquares=0; }
            if(scenario==4) { squares[9].gs_flags=GRID_SQUARE_USABLE; }
        }
        ReactFrogWithGridFlags(f,squares[5].gs_flags);emit_special(scenario,-1);
        for(int tick=0;tick<24;tick++) { MoveFrog(f);emit_special(scenario,tick); }
    }
    return 0;
}
static int freeform_trace(void) {
    puts("scenario,tick,x16,y16,z16,vx16,vy16,vz16,grid_x,grid_z,count,flags,mode,direction,square,target_x,target_y,target_z,animation_requests,sound_requests,score_requests,m00,m01,m02,m10,m11,m12,m20,m21,m22,tx,ty,tz");
    for(int scenario=0;scenario<5;scenario++) {
        setup(0);FROG* f=&Frogs[0];Game_map_theme=THEME_SUB;f->fr_lives=3;
        squares[5].gs_flags=GRID_SQUARE_USABLE|GRID_SQUARE_FREEFORM_SLIPPY;
        f->fr_old_pos=f->fr_pos;f->fr_old_pos.vz-=8<<16;
        if(scenario==1) { vertices[20].vy=vertices[21].vy=128;vertices[22].vy=vertices[23].vy=-128; }
        if(scenario==2) { squares[5].gs_flags=GRID_SQUARE_USABLE|GRID_SQUARE_SAFE; }
        if(scenario==3) { stacks[5].gs_numsquares=0; }
        if(scenario==4) { squares[5].gs_flags=GRID_SQUARE_USABLE|GRID_SQUARE_POPDEATH; }
        SetFrogUserMode(f,FROGUSER_MODE_SLIPPING_LAND_NONGRID);emit_special(scenario,-1);
        for(int tick=0;tick<8;tick++) { MoveFrog(f);emit_special(scenario,tick); }
    }
    return 0;
}
static int startup_trace(void) {
    puts("scenario,tick,x16,y16,z16,vx16,vy16,vz16,grid_x,grid_z,count,flags,mode,direction,square,target_x,target_y,target_z,animation_requests,sound_requests,score_requests,m00,m01,m02,m10,m11,m12,m20,m21,m22,tx,ty,tz");
    setup(0);FROG* f=&Frogs[0];f->fr_target_y=0;f->fr_pos.vy=-(FROG_COLLIDE_RADIUS2<<12);
    matrix.t[1]=f->fr_pos.vy>>16;
    SetFrogUserMode(f,FROGUSER_MODE_LEVEL_START_BOUNCE);emit_special(0,-1);
    for(int tick=0;tick<80;tick++) { MoveFrog(f);emit_special(0,tick); }
    return 0;
}
static int wall_trace(void) {
    puts("scenario,tick,x16,y16,z16,vx16,vy16,vz16,grid_x,grid_z,count,flags,mode,direction,square,target_x,target_y,target_z,animation_requests,sound_requests,score_requests,m00,m01,m02,m10,m11,m12,m20,m21,m22,tx,ty,tz");
    for(int scenario=0;scenario<5;scenario++) {
        setup(0);FROG* f=&Frogs[0];Game_map_theme=THEME_SUB;
        int direction=scenario==4?0:scenario;
        if(scenario==0) squares[5].gs_flags|=GRID_SQUARE_BOUNCE_WALL_N;
        if(scenario==1) squares[5].gs_flags|=GRID_SQUARE_BOUNCE_WALL_E;
        if(scenario==2) squares[1].gs_flags|=GRID_SQUARE_BOUNCE_WALL_N;
        if(scenario==3) squares[4].gs_flags|=GRID_SQUARE_BOUNCE_WALL_E;
        if(scenario==4) squares[9].gs_flags=GRID_SQUARE_USABLE|GRID_SQUARE_CLIFF;
        JumpFrog(f,direction,0,1,6);emit_special(scenario,-1);
        for(int tick=0;tick<8;tick++) { MoveFrog(f);emit_special(scenario,tick); }
    }
    return 0;
}
static int steering_trace(void) {
    puts("scenario,tick,x16,y16,z16,vx16,vy16,vz16,grid_x,grid_z,count,flags,mode,direction,square,target_x,target_y,target_z,animation_requests,sound_requests,score_requests,m00,m01,m02,m10,m11,m12,m20,m21,m22,tx,ty,tz");
    for(int scenario=0;scenario<4;scenario++) {
        setup(0);FROG* f=&Frogs[0];Game_map_theme=THEME_SUB;
        memset(&steering_env,0,sizeof(steering_env));memset(&steering_single,0,sizeof(steering_single));
        steering_env.ae_extra.ae_extra_env_single=&steering_single;f->fr_api_item=(MR_VOID*)&steering_env;
        squares[5].gs_flags=GRID_SQUARE_USABLE|GRID_SQUARE_FREEFORM_SLIPPY;
        f->fr_old_pos=f->fr_pos;f->fr_old_pos.vz-=8<<16;
        SetFrogUserMode(f,FROGUSER_MODE_SLIPPING_LAND_NONGRID);emit_special(scenario,-1);
        MR_ULONG masks[4]={f->fr_control_method->fc_up_control,f->fr_control_method->fc_right_control,f->fr_control_method->fc_down_control,f->fr_control_method->fc_left_control};
        for(int tick=0;tick<8;tick++) {
            MRInput[0].in_pad_down=0;MRInput[0].in_pad_new=masks[scenario];
            ControlFrog(f);emit_special(scenario,tick*2);
            MoveFrog(f);emit_special(scenario,tick*2+1);
        }
    }
    return 0;
}
static int bounds_trace(void) {
    puts("scenario,tick,x16,y16,z16,vx16,vy16,vz16,grid_x,grid_z,count,flags,mode,direction,square,target_x,target_y,target_z,animation_requests,sound_requests,score_requests,m00,m01,m02,m10,m11,m12,m20,m21,m22,tx,ty,tz");
    int indices[4]={13,7,1,4};
    for(int scenario=0;scenario<4;scenario++) {
        setup(0);FROG* f=&Frogs[0];int i=indices[scenario];
        f->fr_grid_x=i%4;f->fr_grid_z=i/4;f->fr_grid_square=&squares[i];
        f->fr_pos.vx=((i%4)*256-384)<<16;f->fr_pos.vz=((i/4)*256-384)<<16;
        matrix.t[0]=f->fr_pos.vx>>16;matrix.t[2]=f->fr_pos.vz>>16;
        JumpFrog(f,scenario,0,1,6);emit_special(scenario,-1);
        for(int tick=0;tick<5;tick++) { MoveFrog(f);emit_special(scenario,tick); }
    }
    return 0;
}
static int priority_trace(void) {
    puts("scenario,tick,x16,y16,z16,vx16,vy16,vz16,grid_x,grid_z,count,flags,mode,direction,square,target_x,target_y,target_z,animation_requests,sound_requests,score_requests,m00,m01,m02,m10,m11,m12,m20,m21,m22,tx,ty,tz");
    int authored[10]={2051,19,149,4105,25,1201,1185,161,8195,0x80043};
    for(int scenario=0;scenario<10;scenario++) {
        setup(0);FROG* f=&Frogs[0];f->fr_old_pos=f->fr_pos;f->fr_lives=3;Game_map_theme=THEME_SUB;
        squares[5].gs_flags=authored[scenario];ReactFrogWithGridFlags(f,authored[scenario]);emit_special(scenario,-1);
    }
    return 0;
}
static int slope_trace(void) {
    puts("scenario,tick,x16,y16,z16,vx16,vy16,vz16,grid_x,grid_z,count,flags,mode,direction,square,target_x,target_y,target_z,animation_requests,sound_requests,score_requests,m00,m01,m02,m10,m11,m12,m20,m21,m22,tx,ty,tz");
    int rise[4]={16,17,-16,-17};
    for(int scenario=0;scenario<4;scenario++) {
        setup(0);Game_map_theme=THEME_SUB;squares[5].gs_flags=GRID_SQUARE_USABLE|GRID_SQUARE_FREEFORM_SLIPPY;
        vertices[20].vy=vertices[21].vy=rise[scenario];
        ReactFrogWithGridFlags(&Frogs[0],squares[5].gs_flags);emit_special(scenario,-1);
    }
    return 0;
}
static int odd_trace(void) {
    puts("scenario,tick,x16,y16,z16,vx16,vy16,vz16,grid_x,grid_z,count,flags,mode,direction,square,target_x,target_y,target_z,animation_requests,sound_requests,score_requests,m00,m01,m02,m10,m11,m12,m20,m21,m22,tx,ty,tz");
    setup(0);Game_map_theme=THEME_SUB;
    Grid_xnum=Grid_znum=3;Grid_base_x=Grid_base_z=-384;
    for(int i=0;i<9;i++) {
        int x=-384+(i%3)*256,z=-384+(i/3)*256;
        int xs[4]={x,x+256,x,x+256},zs[4]={z+256,z+256,z,z};
        for(int j=0;j<4;j++) { vertices[i*4+j].vx=xs[j];vertices[i*4+j].vz=zs[j]; }
    }
    FROG* f=&Frogs[0];f->fr_grid_square=&squares[4];
    f->fr_pos.vx=f->fr_pos.vz=matrix.t[0]=matrix.t[2]=0;
    JumpFrog(f,0,0,1,6);emit_special(0,-1);
    for(int tick=0;tick<8;tick++) { MoveFrog(f);emit_special(0,tick); }
    return 0;
}
static int map_branch_trace(void) {
    puts("scenario,tick,x16,y16,z16,vx16,vy16,vz16,count,flags,mode,animation_requests,last_animation,death_equate,death_count");
    int maps[6]={LEVEL_SWAMP_MULTI_PLAYER,LEVEL_SKY1,LEVEL_SKY_MULTI_PLAYER,LEVEL_SUBURBIA1,LEVEL_CAVES1,LEVEL_CAVES3};
    for(int scenario=0;scenario<12;scenario++) {
        setup(0);FROG* f=&Frogs[0];Game_map_theme=THEME_SUB;Game_map=scenario<6?maps[scenario]:LEVEL_SUBURBIA1;
        if(scenario<4) { f->fr_mode=FROG_MODE_JUMPING;f->fr_flags|=FROG_FREEFALL|FROG_FREEFALL_NO_ANIMATION;f->fr_count=30; }
        else if(scenario<6) { f->fr_mode=FROG_MODE_DYING;f->fr_count=0;f->fr_death_count=50;f->fr_death_equate=FROG_ANIMATION_SQUISHED;f->fr_velocity.vx=131073;f->fr_velocity.vy=-65537;f->fr_velocity.vz=400000001; }
        else if(scenario<10) { f->fr_lives=3;Game_map_theme=scenario>=8?THEME_VOL:THEME_SUB;FrogKill(f,scenario%2==0?FROG_ANIMATION_DROWN:FROG_ANIMATION_FLOP,NULL); }
        if(scenario>=10) { f->fr_mode=FROG_MODE_WAIT_FOR_CAMERA;f->fr_lives=3;Cameras[0].ca_twist_counter=scenario-10;Fade_top_left_pos.vx=-127;Fade_bottom_right_pos.vx=32767;Fade_top_left_pos.vz=32767;Fade_bottom_right_pos.vz=-32767; }
        for(int tick=0;tick<3;tick++) {
            if(scenario<6) MoveFrog(f);
            if(scenario>=10) CollideFrog(f);
            printf("%d,%d,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%lu,%ld,%d,%d,%ld,%ld\n",scenario,tick,f->fr_pos.vx,f->fr_pos.vy,f->fr_pos.vz,f->fr_velocity.vx,f->fr_velocity.vy,f->fr_velocity.vz,f->fr_count,f->fr_flags,f->fr_mode,animations,last_animation,f->fr_death_equate,f->fr_death_count);
        }
    }
    return 0;
}
static int narrow_trace(void) {
    puts("scenario,tick,x16,y16,z16,vx16,vy16,vz16,grid_x,grid_z,count,flags,mode,direction,square,target_x,target_y,target_z,animation_requests,sound_requests,score_requests,m00,m01,m02,m10,m11,m12,m20,m21,m22,tx,ty,tz");
    for(int scenario=0;scenario<4;scenario++) {
        setup(0);Game_map_theme=THEME_SUB;FROG* f=&Frogs[0];
        if(scenario==0) {
            Grid_xnum=1;Grid_znum=255;Grid_base_x=-128;Grid_base_z=-32640;
            for(int i=0;i<255;i++) {
                int z=-32640+i*256;int xs[4]={-128,128,-128,128},zs[4]={z+256,z+256,z,z};
                for(int j=0;j<4;j++) { vertices[i*4+j].vx=xs[j];vertices[i*4+j].vy=0;vertices[i*4+j].vz=zs[j];polygons[i].mp_vertices[j]=i*4+j; }
                squares[i].gs_map_poly=&polygons[i];squares[i].gs_flags=GRID_SQUARE_USABLE|GRID_SQUARE_SAFE;stacks[i].gs_numsquares=1;stacks[i].gs_index=i;
            }
            f->fr_grid_x=0;f->fr_grid_z=254;f->fr_grid_square=&squares[254];f->fr_pos.vx=matrix.t[0]=0;f->fr_pos.vz=32512*65536;matrix.t[2]=32512;
            JumpFrog(f,0,0,1,6);
        } else if(scenario==1) {
            for(int j=0;j<4;j++) { vertices[5*4+j].vy=32767;vertices[13*4+j].vy=-32768; }
            f->fr_pos.vy=32767*65536;matrix.t[1]=f->fr_y=f->fr_old_y=32767;
            JumpFrog(f,0,FROG_JUMP_FORCED,2,15);
        } else if(scenario==2) {
            for(int j=0;j<4;j++) vertices[5*4+j].vy=32767;
            f->fr_pos.vy=(-32768)*65536;matrix.t[1]=f->fr_y=f->fr_old_y=-32768;
            f->fr_user_data1=(MR_VOID*)1;f->fr_user_data2=(MR_VOID*)2;
            SetFrogUserMode(f,FROGUSER_MODE_BOUNCY_COBWEB);
        } else {
            for(int j=0;j<4;j++) vertices[5*4+j].vy=j==0?32767:-32768;
            squares[5].gs_flags=GRID_SQUARE_USABLE|GRID_SQUARE_FREEFORM_SLIPPY;
            f->fr_pos.vy=(-32768)*65536;matrix.t[1]=f->fr_y=f->fr_old_y=-32768;
            f->fr_old_pos=f->fr_pos;f->fr_old_pos.vz-=8*65536;
            SetFrogUserMode(f,FROGUSER_MODE_SLIPPING_LAND_NONGRID);
        }
        emit_special(scenario,-1);
        for(int tick=0;tick<5;tick++) { MoveFrog(f);emit_special(scenario,tick); }
    }
    return 0;
}
int main(int argc,char** argv) {
    SetErrorMode(1|2);
    if(argc>1 && strcmp(argv[1],"--collision")==0) return collision_trace();
    if(argc>1 && strcmp(argv[1],"--matrix")==0) return matrix_trace();
    if(argc>1 && strcmp(argv[1],"--special")==0) return special_trace();
    if(argc>1 && strcmp(argv[1],"--modifiers")==0) return modifier_trace();
    if(argc>1 && strcmp(argv[1],"--roll")==0) return roll_trace();
    if(argc>1 && strcmp(argv[1],"--freeform")==0) return freeform_trace();
    if(argc>1 && strcmp(argv[1],"--startup")==0) return startup_trace();
    if(argc>1 && strcmp(argv[1],"--wall")==0) return wall_trace();
    if(argc>1 && strcmp(argv[1],"--steering")==0) return steering_trace();
    if(argc>1 && strcmp(argv[1],"--bounds")==0) return bounds_trace();
    if(argc>1 && strcmp(argv[1],"--priority")==0) return priority_trace();
    if(argc>1 && strcmp(argv[1],"--slope")==0) return slope_trace();
    if(argc>1 && strcmp(argv[1],"--odd")==0) return odd_trace();
    if(argc>1 && strcmp(argv[1],"--map-branches")==0) return map_branch_trace();
    if(argc>1 && strcmp(argv[1],"--narrow")==0) return narrow_trace();
    puts("scenario,tick,component,x16,y16,z16,vx16,vy16,vz16,grid_x,grid_z,count,flags,mode,input,direction,animation_requests,sound_requests,score_requests,buffered_keys,buffered_input_count,pad_pressed,pad_held");
    for(int scenario=0;scenario<8;scenario++) {
        setup(0);
        if(scenario==1) Frogs[0].fr_powerup_flags=FROG_POWERUP_QUICK_JUMP;
        if(scenario==2) Frogs[0].fr_powerup_flags=FROG_POWERUP_AUTO_HOP;
        int heights[8]={0,0,0,-200,-201,256,257,0};
        for(int j=0;j<4;j++) vertices[9*4+j].vy=heights[scenario];
        if(scenario==7) stacks[9].gs_numsquares=0;
        for(int tick=0;tick<20;tick++) {
            MRInput[0].in_pad_down=tick==0 ? Frogs[0].fr_control_method->fc_up_control : 0;
            MRInput[0].in_pad_new=MRInput[0].in_pad_down;
            if(scenario==0) { MRInput[0].in_pad_down=tick==0 ? Frogs[0].fr_control_method->fc_superjump_control : 0;MRInput[0].in_pad_new=MRInput[0].in_pad_down; }
            if(scenario==2 && tick<7) MRInput[0].in_pad_new=Frogs[0].fr_control_method->fc_up_control;
            MRFrame_number=tick;
            ControlFrog(&Frogs[0]);emit(scenario,tick,"control");
            MoveFrog(&Frogs[0]);emit(scenario,tick,"move");
        }
    }
    return 0;
}
