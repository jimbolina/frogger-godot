/* Synthetic component trace. Real frozen ControlFrog/MoveFrog own every step.
 * Animation/audio/score calls are counted, not executed; no assets are loaded.
 * Flat safe ground, no entities/collision/camera tick, no special input powers. */
#define main frozen_main_unused
#include "FROG.H"
#include "CAMERA.H"
#include "gamesys.H"
#include "GRID.H"
#include "EFFECTS.H"
#include "froganim.h"
#include "score.h"
#undef main
#include "gpu/mr_stub_gpu.h"
#undef main
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
__declspec(dllimport) unsigned long __stdcall SetErrorMode(unsigned long);
extern FROG_CONTROL_METHOD Frog_control_methods[];
extern MR_BOOL Recording_demo;
static int animations,sounds,scores;
void __wrap_FrogRequestAnimation(FROG* f,MR_ULONG a,MR_ULONG b,MR_ULONG c) { (void)f;(void)a;(void)b;(void)c; animations++; }
MR_LONG __wrap_MRSNDPlaySound(MR_USHORT s,SndVolume* v,MR_USHORT f,MR_LONG p) { (void)s;(void)v;(void)f;(void)p; sounds++; return -1; }
SCORE_SPRITE* __wrap_AddFrogScore(FROG* f,MR_ULONG s,MR_MAT* m) { (void)f;(void)s;(void)m; scores++; return NULL; }
static MR_SVEC vertices[64];
static MAP_F4 polygons[16];
static GRID_SQUARE squares[16];
static GRID_STACK stacks[16];
static MR_MAT matrix;
static EFFECT trail_effect;
static TRAIL trail;
static ZONE_HEADER zone_header;
static GENERAL_HEADER general_header;
static void setup(int blocked) {
    memset(Frogs,0,sizeof(FROG)*4); memset(Cameras,0,sizeof(CAMERA)*4);
    memset(MRInput,0,sizeof(MR_INPUT)*1); memset(&matrix,0,sizeof(matrix));
    memset(&trail,0,sizeof(trail)); memset(&trail_effect,0,sizeof(trail_effect));
    srand(12345); animations=sounds=scores=0;
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
    printf("%d,%d,%s,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%lu,%ld,%ld,%ld,%d,%d,%d,%ld,%ld,%lu,%lu\n",scenario,tick,component,
        f->fr_pos.vx,f->fr_pos.vy,f->fr_pos.vz,f->fr_velocity.vx,f->fr_velocity.vy,f->fr_velocity.vz,
        f->fr_grid_x,f->fr_grid_z,f->fr_count,f->fr_flags,f->fr_mode,f->fr_current_key,f->fr_direction,animations,sounds,scores,
        f->fr_num_buffered_keys,f->fr_buffered_input_count,logical_down,logical_held);
}
static int camera_trace(void) {
    MR_MAT camera_matrix;
    MRStub_GpuInit(NULL,0); /* Frozen trig-table initialization, no display. */
    puts("scenario,tick,mode,move_timer,twist_counter,current_x,current_y,current_z,source_ofs_x,source_ofs_y,source_ofs_z,target_ofs_x,target_ofs_y,target_ofs_z,source_x,source_y,source_z,target_x,target_y,target_z,controller_up,current_ytheta,delta_ytheta,dest_ytheta,flags,shake_timer,shake_amp_x,shake_amp_y,shake_freq_x,shake_freq_y,rng_seed,shake_draw_1,shake_draw_2");
    for(int scenario=0;scenario<8;scenario++) {
        setup(0); matrix.t[0]=matrix.t[1]=matrix.t[2]=0;
        memset(&camera_matrix,0,sizeof(camera_matrix));
        CAMERA* camera=&Cameras[0];camera->ca_matrix=&camera_matrix;
        ResetCamera(camera);
        if(scenario) {
            camera->ca_mode=CAMERA_MODE_FOLLOW_FROG;camera->ca_move_timer=0;
            camera->ca_current_source_ofs.vx=0;camera->ca_current_source_ofs.vy=-500;camera->ca_current_source_ofs.vz=-500;
            camera->ca_current_target_ofs.vx=camera->ca_current_target_ofs.vy=camera->ca_current_target_ofs.vz=0;
        }
        if(scenario==2 || scenario==3) {camera->ca_twist_counter=scenario==2 ? 1 : -1;camera->ca_twist_quadrants=1;camera->ca_move_timer=CAMERA_TWIST_TIME;}
        if(scenario==4) {camera->ca_next_source_ofs.vx=0;camera->ca_next_source_ofs.vy=-1000;camera->ca_next_source_ofs.vz=-100;camera->ca_move_timer=45;}
        MR_LONG draw1=0,draw2=0;
        if(scenario==5) {matrix.t[0]=10;matrix.t[1]=-20;matrix.t[2]=30;UpdateCamera(camera);camera->ca_mode=CAMERA_MODE_FIXED;}
        if(scenario>=6) {
            if(scenario==7) {UpdateCamera(camera);camera->ca_mode=CAMERA_MODE_FIXED;}
            MRsrand(1);draw1=MRrand();draw2=MRrand();MRsrand(1);
            ShakeCamera(camera,MR_OBJ_STATIC,45,0x5000);
        }
        int ticks=scenario==0 ? 122 : scenario==4 || scenario>=6 ? 47 : 16;
        for(int tick=0;tick<ticks;tick++) {
            Game_start_timer=scenario==0 ? 90-tick : 0;
            if(Game_start_timer<0) Game_start_timer=0;
            if(scenario==1) {matrix.t[0]=tick ? 200 : 100;matrix.t[1]=tick ? -260 : -200;matrix.t[2]=tick ? 100 : 60;}
            UpdateCamera(camera);
            MR_VEC target;
            MR_VEC* origin=(camera->ca_mode==CAMERA_MODE_FOLLOW_FROG || camera->ca_mode==CAMERA_MODE_FIXED) ? &camera->ca_current : camera->ca_offset_origin;
            target.vx=origin->vx+camera->ca_current_target_ofs.vx;
            target.vy=origin->vy+camera->ca_current_target_ofs.vy;
            target.vz=origin->vz+camera->ca_current_target_ofs.vz;
            printf("%d,%d,%lu,%ld,%ld,%ld,%ld,%ld,%d,%d,%d,%d,%d,%d,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%lu,%ld,%ld,%ld,%ld,%ld,%lu,%ld,%ld\n",scenario,tick,
                camera->ca_mode,camera->ca_move_timer,camera->ca_twist_counter,
                camera->ca_current.vx,camera->ca_current.vy,camera->ca_current.vz,
                camera->ca_current_source_ofs.vx,camera->ca_current_source_ofs.vy,camera->ca_current_source_ofs.vz,
                camera->ca_current_target_ofs.vx,camera->ca_current_target_ofs.vy,camera->ca_current_target_ofs.vz,
                camera_matrix.t[0],camera_matrix.t[1],camera_matrix.t[2],target.vx,target.vy,target.vz,
                camera->ca_frog_controller_directions[0],camera->ca_mod_matrix_current_ytheta,
                camera->ca_mod_matrix_delta_ytheta,camera->ca_mod_matrix_dest_ytheta,
                camera->ca_flags,camera->ca_shake_timer,camera->ca_shake_amp_x,camera->ca_shake_amp_y,
                camera->ca_shake_freq_x,camera->ca_shake_freq_y,MRRnd_seed,draw1,draw2);
        }
    }
    return 0;
}
int main(int argc,char** argv) {
    setvbuf(stdout,NULL,_IONBF,0);
    SetErrorMode(1|2); /* Windows: suppress unattended critical-error/crash dialogs. */
    if(argc==2 && strcmp(argv[1],"--camera")==0) return camera_trace();
    puts("scenario,tick,component,x16,y16,z16,vx16,vy16,vz16,grid_x,grid_z,count,flags,mode,input,direction,animation_requests,sound_requests,score_requests,buffered_keys,buffered_input_count,pad_pressed,pad_held");
    for(int scenario=0;scenario<3;scenario++) {
        setup(scenario==1);
        for(int tick=0;tick<16;tick++) {
            MRInput[0].in_pad_down=tick==0 ? Frogs[0].fr_control_method->fc_up_control : 0;
            MRInput[0].in_pad_new=MRInput[0].in_pad_down;
            /* In-flight E press at tick 2, held through tick 8, release at 9. */
            if(scenario==2 && tick>=2 && tick<=8) {
                MRInput[0].in_pad_down=tick==2 ? Frogs[0].fr_control_method->fc_right_control : 0;
                MRInput[0].in_pad_new=Frogs[0].fr_control_method->fc_right_control;
            }
            MRFrame_number=tick;
            ControlFrog(&Frogs[0]);emit(scenario,tick,"control");
            MoveFrog(&Frogs[0]);emit(scenario,tick,"move");
            /* Hand-derived narrow positive controls, independent of trace output. */
            FROG* f=&Frogs[0];
            if(scenario==0 && tick==0 && (f->fr_count!=5 || f->fr_pos.vy!=-40*65536 || f->fr_velocity.vz!=2796202)) return 1;
            if(scenario==0 && tick>=5 && (f->fr_mode!=FROG_MODE_STATIONARY || f->fr_pos.vx!=-128*65536 || f->fr_pos.vy!=0 || f->fr_pos.vz!=128*65536)) return 1;
            if(scenario==1 && (f->fr_mode!=FROG_MODE_STATIONARY || f->fr_pos.vx!=-128*65536 || f->fr_pos.vy!=0 || f->fr_pos.vz!=-128*65536 || sounds || scores)) return 1;
            if(scenario==2 && tick==2 && f->fr_num_buffered_keys!=1) return 1;
            if(scenario==2 && tick==6 && (f->fr_count!=5 || f->fr_velocity.vx!=2796202 || f->fr_velocity.vz!=0 || f->fr_buffered_input_count!=1)) return 1;
            if(scenario==2 && tick>=11 && (f->fr_mode!=FROG_MODE_STATIONARY || f->fr_pos.vx!=128*65536 || f->fr_pos.vz!=128*65536)) return 1;
        }
    }
    return 0;
}
