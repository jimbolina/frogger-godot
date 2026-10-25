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
static int animations,sounds,scores;
static MR_OBJECT pgen_object,sprite_object,particle_object;
static MR_PGEN pgen;
static MR_3DSPRITE sprite;
MR_OBJECT* __wrap_MRCreatePgen(MR_PGEN_INIT* init,MR_FRAME* frame,MR_ULONG flags,MR_SVEC* offset) { (void)init;(void)frame;(void)flags;(void)offset;pgen_object.ob_extra.ob_extra_pgen=&pgen;return &pgen_object; }
MR_OBJECT* __wrap_MRCreate3DSprite(MR_FRAME* frame,MR_ULONG flags,MR_VOID* anim) { (void)frame;(void)flags;(void)anim;sprite_object.ob_extra.ob_extra_3dsprite=&sprite;return &sprite_object; }
MR_OBJECT* __wrap_CreateParticleEffect(MR_VOID* owner,MR_ULONG type,MR_SVEC* offset) { (void)owner;(void)type;(void)offset;return &particle_object; }
void __wrap_GameAddObjectToViewports(MR_OBJECT* object) { (void)object; }
void __wrap_SetGameMainloopMode(MR_ULONG mode) { Game_mode=mode; }

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
extern FROG_ANIM FrogAnimScripts[];
extern MR_LONG Frog_script_if_counter;
extern MR_ULONG Frog_animation_script_command_lengths[];
static MR_ANIM_ENV root,env;
static MR_ANIM_ENV_SINGLE single;
static MR_ANIM_MODEL model;
static MR_ANIM_CEL_SET cel_set;
static MR_ANIM_CELS cels[34];
static int words(MR_LONG* script) {
    if(!script) return 0;
    int at=0;
    while(at<128) {int token=script[at];at+=Frog_animation_script_command_lengths[token];if(token==FROGSCR_END || token==FROGSCR_HOLD) return at;}
    return -1;
}
static void pointer(MR_LONG* ptr,int* program,int* offset) {
    *program=*offset=-1;if(!ptr) return;
    for(int i=0;i<FROG_ANIMATION_MAX;i++) {
        MR_LONG* script=FrogAnimScripts[i].fa_script;
        uintptr_t p=(uintptr_t)ptr,start=(uintptr_t)script;
        int n=words(script);
        if(p>=start && p<start+n*sizeof(MR_LONG)) {*program=i;*offset=(p-start)/sizeof(MR_LONG);return;}
    }
}
static void animation_setup(int jungle) {
    memset(&root,0,sizeof(root));memset(&env,0,sizeof(env));memset(&single,0,sizeof(single));
    Game_total_players=1;Game_is_network=0;Game_map_theme=jungle ? THEME_JUN : THEME_SUB;
    Frog_script_if_counter=0;MRsrand(1);
    root.ae_next_node=&env;MRAnim_env_root_ptr=&root;env.ae_extra.ae_extra_env_single=&single;env.ae_update_period=1;env.ae_flags=MR_ANIM_ENV_DEFAULT_FLAGS;
    single.ae_model=&model;model.am_cel_set=&cel_set;cel_set.ac_cels.ac_cels=cels;cel_set.ac_no_of_cels_structures=34;
    for(int i=0;i<34;i++) cels[i].ac_no_of_virtual_cels=3+i%3;
    MRAnimEnvSingleSetAction(&env,0);MRAnimEnvSingleSetCel(&env,0);
    Frogs[0].fr_api_item=&env;FrogInitialiseAnimation(&Frogs[0],FROG_ANIMATION_PANT,0);
}

static MR_MAT camera_matrix;
static void integrated_emit(int scenario,int tick,const char* phase) {
 FROG* f=Frogs; CAMERA* c=Cameras; FROG_ANIM_INFO* ai=&f->fr_anim_info;
 int program,offset;pointer(ai->fi_script,&program,&offset);
 printf("%d,%d,%s,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%lu,%ld,%ld,%ld,%ld,%ld,%lu,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%u,%u,%lu,%ld,%d,%d,%d,%d,%d,%u,%lu\n",
 scenario,tick,phase,f->fr_pos.vx,f->fr_pos.vy,f->fr_pos.vz,f->fr_velocity.vx,f->fr_velocity.vy,f->fr_velocity.vz,
 f->fr_grid_x,f->fr_grid_z,f->fr_count,f->fr_flags,f->fr_mode,f->fr_current_key,f->fr_direction,f->fr_no_input_timer,f->fr_death_count,
 c->ca_mode,c->ca_move_timer,c->ca_twist_counter,c->ca_current.vx,c->ca_current.vy,c->ca_current.vz,
 camera_matrix.t[0],camera_matrix.t[1],camera_matrix.t[2],c->ca_frog_controller_directions[0],c->ca_shake_timer,
 ai->fi_type,ai->fi_timer,ai->fi_flags,env.ae_flags,MRRnd_seed,Frog_script_if_counter,program,offset,
 single.ae_action_number,single.ae_cel_number,single.ae_total_cels,env.ae_update_count,Game_mode);
}
int main(void) {
 SetErrorMode(3);setvbuf(stdout,NULL,_IONBF,0);MRStub_GpuInit(NULL,0);
 puts("scenario,tick,phase,x16,y16,z16,vx16,vy16,vz16,grid_x,grid_z,count,flags,mode,input,direction,no_input_timer,death_count,camera_mode,camera_move_timer,camera_twist,camera_x,camera_y,camera_z,source_x,source_y,source_z,controller_up,shake_timer,animation_type,script_timer,animation_flags,env_flags,rng_seed,if_counter,program,offset,action,cel,total,update_count,game_mode");
 for(int scenario=0;scenario<4;scenario++) {
  setup(0);animation_setup(scenario==2);
  Game_total_viewports=0;Frogs[0].fr_lives=3;Game_map=0;
  Cheat_collision_toggle=FALSE;Cheat_infinite_lives_toggle=FALSE;
  Fade_top_left_pos.vx=-32767;Fade_top_left_pos.vz=32767;
  Fade_bottom_right_pos.vx=32767;Fade_bottom_right_pos.vz=-32767;
  Map_view_xnum=Map_view_znum=0;Map_view_xlen=Map_view_zlen=768;
  Theme_library[Game_map_theme].tb_death_height=30000;
  memset(&camera_matrix,0,sizeof(camera_matrix));Cameras[0].ca_matrix=&camera_matrix;
  ResetCamera(Cameras);Cameras[0].ca_mode=CAMERA_MODE_FOLLOW_FROG;Cameras[0].ca_move_timer=0;
  Cameras[0].ca_current_source_ofs=general_header.gh_default_camera_source_ofs;
  Cameras[0].ca_current_target_ofs=general_header.gh_default_camera_target_ofs;
  Cameras[0].ca_current.vx=matrix.t[0];Cameras[0].ca_current.vy=matrix.t[1];Cameras[0].ca_current.vz=matrix.t[2];
  UpdateCamera(Cameras);
  if(scenario==2) for(int j=0;j<4;j++) vertices[36+j].vy=513;
  if(scenario==3) squares[9].gs_flags=GRID_SQUARE_USABLE|GRID_SQUARE_WATER;
  int ticks=scenario<2 ? 24 : scenario==2 ? 120 : 80;
  for(int tick=0;tick<ticks;tick++) {
   MR_ULONG up=Frogs[0].fr_control_method->fc_up_control;
   MRInput[0].in_pad_down=tick==0 ? up : 0;MRInput[0].in_pad_new=MRInput[0].in_pad_down;
   if(scenario==0 && tick==0) MRInput[0].in_pad_down|=Frogs[0].fr_control_method->fc_right_control;
   if(scenario==1) {
    MRInput[0].in_pad_down=tick==0 ? Frogs[0].fr_control_method->fc_camera_clockwise_control : 0;
    MRInput[0].in_pad_new=tick>=1 && tick<=12 ? up : MRInput[0].in_pad_down;
   }
   MRFrame_number=tick;
   ControlFrog(Frogs);integrated_emit(scenario,tick,"control");
   MoveFrog(Frogs);integrated_emit(scenario,tick,"move");
   CollideFrog(Frogs);integrated_emit(scenario,tick,"collision");
   UpdateCamera(Cameras);integrated_emit(scenario,tick,"camera");
   UpdateFrogAnimationScripts();integrated_emit(scenario,tick,"scripts");
   MR_USHORT saved=env.ae_flags;env.ae_flags&=~MR_ANIM_ENV_UPDATE;MRAnimUpdateEnvironments();env.ae_flags=saved;
   integrated_emit(scenario,tick,"pose");
   if(Game_mode!=GAME_MODE_LEVEL_PLAY) break;
  }
 }
 return 0;
}
