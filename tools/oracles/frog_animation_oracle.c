#define main frozen_main_unused
#include "FROG.H"
#include "froganim.h"
#include "gamesys.H"
#include "gen_frog.h"
#undef main
#include <stdio.h>
#include <stdint.h>
#include <string.h>
__declspec(dllimport) unsigned long __stdcall SetErrorMode(unsigned long);
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
static void setup(int jungle) {
    memset(Frogs,0,sizeof(FROG)*4);memset(&root,0,sizeof(root));memset(&env,0,sizeof(env));memset(&single,0,sizeof(single));
    Game_total_players=1;Game_is_network=0;Game_map_theme=jungle ? THEME_JUN : THEME_SUB;
    Frog_script_if_counter=0;MRsrand(1);
    root.ae_next_node=&env;MRAnim_env_root_ptr=&root;env.ae_extra.ae_extra_env_single=&single;env.ae_update_period=1;env.ae_flags=MR_ANIM_ENV_DEFAULT_FLAGS;
    single.ae_model=&model;model.am_cel_set=&cel_set;cel_set.ac_cels.ac_cels=cels;cel_set.ac_no_of_cels_structures=34;
    for(int i=0;i<34;i++) cels[i].ac_no_of_virtual_cels=3+i%3;
    MRAnimEnvSingleSetAction(&env,0);MRAnimEnvSingleSetCel(&env,0);
    Frogs[0].fr_api_item=&env;FrogInitialiseAnimation(&Frogs[0],FROG_ANIMATION_PANT,0);
}
static void emit(int scenario,int tick,const char* phase) {
    FROG_ANIM_INFO* info=&Frogs[0].fr_anim_info;int program,offset,ls,lo,le,eo,qp,qo,pp,po;
    pointer(info->fi_script,&program,&offset);pointer(info->fi_script_loop_start,&ls,&lo);pointer(info->fi_script_loop_end,&le,&eo);
    pointer(info->fi_queue_script,&qp,&qo);pointer(info->fi_previous_script,&pp,&po);
    printf("%d,%d,%s,%ld,%ld,%d,%d,%ld,%ld,%ld,%ld,%ld,%ld,%d,%d,%d,%u,%d,%ld,%ld,%lu,%d,%d,%d,%d,%d,%d,%d,%d\n",scenario,tick,phase,
        info->fi_type,info->fi_flags,program,offset,info->fi_queue_type,info->fi_queue_flags,info->fi_previous_type,info->fi_previous_flags,
        info->fi_timer,info->fi_anim_timer,single.ae_action_number,single.ae_cel_number,single.ae_total_cels,env.ae_flags,env.ae_update_count,
        Frogs[0].fr_no_input_timer,Frog_script_if_counter,MRRnd_seed,ls,lo,le,eo,qp,qo,pp,po);
}
int main(int argc,char** argv) {
    SetErrorMode(1|2);setvbuf(stdout,NULL,_IONBF,0);
    if(argc==2 && strcmp(argv[1],"--catalog")==0) {
        for(int i=0;i<FROG_ANIMATION_MAX;i++) {
            int n=words(FrogAnimScripts[i].fa_script);printf("T,%d,%u,%d",i,FrogAnimScripts[i].fa_flags,n);
            for(int j=0;j<n;j++) printf(",%ld",FrogAnimScripts[i].fa_script[j]);puts("");
        }return 0;
    }
    puts("scenario,tick,phase,type,flags,program,offset,queue_type,queue_flags,previous_type,previous_flags,script_timer,anim_timer,action,cel,total,env_flags,update_count,no_input_timer,if_counter,rng_seed,loop_start_program,loop_start_offset,loop_end_program,loop_end_offset,queue_program,queue_offset,previous_program,previous_offset");
    for(int scenario=0;scenario<5;scenario++) {
        setup(scenario==3);int ticks=scenario==3 ? 64 : 24;
        for(int tick=0;tick<ticks;tick++) {
            if(scenario==0) {if(tick==0 || tick==7) FrogRequestAnimation(Frogs,FROG_ANIMATION_HOP,0,0);if(tick==1 || tick==8) FrogRequestAnimation(Frogs,FROG_ANIMATION_PANT,0,0);}
            if(scenario==1) {if(tick==0) FrogRequestAnimation(Frogs,FROG_ANIMATION_FREEFALL,0,0);if(tick==2 || tick==7) FrogRequestAnimation(Frogs,FROG_ANIMATION_PANT,0,0);if(tick==6) FrogRequestAnimation(Frogs,FROG_ANIMATION_HOP,0,0);}
            if(scenario==2) {if(tick==0) FrogRequestAnimation(Frogs,FROG_ANIMATION_DROWN,0,0);if(tick==3) FrogRequestAnimation(Frogs,FROG_ANIMATION_HOP,0,0);if(tick==8) FrogInitialiseAnimation(Frogs,FROG_ANIMATION_PANT,0);}
            if(scenario==4) {if(tick==0) FrogRequestAnimation(Frogs,FROG_ANIMATION_SLIPLEFT,0,0);if(tick==2) FrogRequestAnimation(Frogs,FROG_ANIMATION_SLIPRIGHT,0,0);}
            Frogs[0].fr_no_input_timer=scenario==3 ? 30 : 0;
            UpdateFrogAnimationScripts();emit(scenario,tick,"scripts");
            MR_USHORT flags=env.ae_flags;env.ae_flags&=~MR_ANIM_ENV_UPDATE;MRAnimUpdateEnvironments();env.ae_flags=flags;
            emit(scenario,tick,"pose");
        }
    }return 0;
}
