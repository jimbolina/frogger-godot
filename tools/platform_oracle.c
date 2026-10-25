/* Invented SAFE platform trace. Frozen path, frog, collision, camera and
 * animation functions own each phase. Rendering/audio factories are counted
 * or omitted; no renderer geometry or whole-engine RNG parity is claimed. */
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
#include "ENTITY.H"
#include "ENTLIB.H"
#include "FORM.H"
#include "PATH.H"
#include "mapload.H"
#include "formlib.H"
#include "ZONE.H"
#include "froguser.h"
#include "scripter.h"
#include "scripts.h"
#include "tempopt.h"
#include "ent_org.h"
#include "ent_gen.h"
#include "sound.h"
#undef main
#include "gpu/mr_stub_gpu.h"
#include "gpu/mr_stub_acos.h"
#include "backend/mr_stub_pool.h"
#undef main
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stddef.h>
#include <stdarg.h>
__declspec(dllimport) unsigned long __stdcall SetErrorMode(unsigned long);
extern FROG_CONTROL_METHOD Frog_control_methods[];
extern MR_BOOL Recording_demo;
static int animations,sounds,scores,pgens;
static int decoded_model_factory;
static int request_capture;
static char captured_requests[8192];
static void capture_request(const char *format,...) {
    if(!request_capture)return;
    size_t used=strlen(captured_requests);if(used)captured_requests[used++]=';';
    va_list args;va_start(args,format);int written=vsnprintf(captured_requests+used,sizeof(captured_requests)-used,format,args);va_end(args);
    if(written<0 || (size_t)written>=sizeof(captured_requests)-used)exit(3);
}
extern MR_VOID __real_ENTSTRCreateMovingMOF(LIVE_ENTITY*);
extern MR_VOID __real_ENTSTRCreateDynamicMOF(LIVE_ENTITY*);
extern MR_VOID __real_ENTSTRCreateStationaryMOF(LIVE_ENTITY*);
/* Keep the real path-transform creation and custom creator. Decoded model
 * metadata is already installed by the ORG transport; omit renderer allocation
 * only, restoring the book before the custom creator resumes. */
MR_VOID __wrap_ENTSTRCreateMovingMOF(LIVE_ENTITY *live) {
    if(!decoded_model_factory) {__real_ENTSTRCreateMovingMOF(live);return;}
    FORM_BOOK *book=ENTITY_GET_FORM_BOOK(live->le_entity);MR_ULONG flags=book->fb_flags;
    book->fb_flags|=FORM_BOOK_FLAG_NO_MODEL;
    __real_ENTSTRCreateMovingMOF(live);book->fb_flags=flags;
}
MR_VOID __wrap_ENTSTRCreateDynamicMOF(LIVE_ENTITY *live) {
    if(!decoded_model_factory) {__real_ENTSTRCreateDynamicMOF(live);return;}
    FORM_BOOK *book=ENTITY_GET_FORM_BOOK(live->le_entity);MR_ULONG flags=book->fb_flags;
    book->fb_flags|=FORM_BOOK_FLAG_NO_MODEL;
    __real_ENTSTRCreateDynamicMOF(live);book->fb_flags=flags;
}
MR_VOID __wrap_ENTSTRCreateStationaryMOF(LIVE_ENTITY *live) {
    if(!decoded_model_factory) {__real_ENTSTRCreateStationaryMOF(live);return;}
    FORM_BOOK *book=ENTITY_GET_FORM_BOOK(live->le_entity);MR_ULONG flags=book->fb_flags;
    book->fb_flags|=FORM_BOOK_FLAG_NO_MODEL;
    __real_ENTSTRCreateStationaryMOF(live);book->fb_flags=flags;
}
/* Rendering-only factories provide writable result storage; no behavior is replaced.
 * Mainloop setup is explicitly omitted, while its requested mode remains observable. */
static MR_OBJECT pgen_object,particle_object;
static MR_PGEN pgen;
MR_OBJECT* __wrap_MRCreatePgen(MR_PGEN_INIT* init,MR_FRAME* frame,MR_ULONG flags,MR_SVEC* offset) { (void)init;(void)frame;(void)flags;(void)offset;pgens++;capture_request("death_pgen");pgen_object.ob_extra.ob_extra_pgen=&pgen;return &pgen_object; }
MR_OBJECT* __wrap_MRCreate3DSprite(MR_FRAME* frame,MR_ULONG flags,MR_VOID* anim) {
    (void)anim;MR_OBJECT *object=calloc(1,sizeof(MR_OBJECT));object->ob_type=MR_OBJTYPE_3DSPRITE;
    object->ob_flags=flags;object->ob_frame=frame;object->ob_extra.ob_extra_3dsprite=calloc(1,sizeof(MR_3DSPRITE));return object;
}
MR_OBJECT* __wrap_CreateParticleEffect(MR_VOID* owner,MR_ULONG type,MR_SVEC* offset) { (void)owner;(void)type;(void)offset;return &particle_object; }
void __wrap_GameAddObjectToViewports(MR_OBJECT* object) {
    if(object->ob_type==MR_OBJTYPE_3DSPRITE)capture_request("sprite:%d:%d:%d:%d:%d",object->ob_offset.vx,object->ob_offset.vy,object->ob_offset.vz,
        !!(object->ob_extra.ob_extra_sp_core->sc_flags&MR_SPF_IN_XZ_PLANE),object->ob_extra.ob_extra_sp_core->sc_ot_offset);
}
void __wrap_SetGameMainloopMode(MR_ULONG mode) { Game_mode=mode; }

MR_LONG __wrap_MRSNDPlaySound(MR_USHORT s,SndVolume* v,MR_USHORT f,MR_LONG p) { capture_request("sound:%u:%d:%u:%ld",s,v!=NULL,f,(long)p);sounds++; return -1; }
extern MR_VOID __real_PlayMovingSound(LIVE_ENTITY*,MR_LONG,MR_LONG,MR_LONG);
MR_VOID __wrap_PlayMovingSound(LIVE_ENTITY *live,MR_LONG sfx,MR_LONG min,MR_LONG max) {
    int existed=live->le_moving_sound!=NULL;__real_PlayMovingSound(live,sfx,min,max);
    if(!existed && live->le_moving_sound)capture_request("moving:%ld:%ld:%ld",(long)sfx,(long)min,(long)max);
}
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
static ENTITY entities[128], entity_roots[9];
static LIVE_ENTITY lives[128];
static FORM_BOOK books[2];
static FORM *forms[2];
static FORM_DATA form_data[2];
static MR_USHORT form_flags[2][64];
static MAP_GROUP groups[9];
static PATH_RUNNER moving_runner;
extern PATH_RUNNER *Path_runner_root_ptr;
static PATH_SEGMENT *moving_segment;
static PATH_SEGMENT *moving_segments[1];
static int entity_count;

/* Retail route input contains decoded numeric facts only. Keep the existing
 * synthetic corpus intact; this mode uses the same frozen gameplay functions. */
static GRID_STACK *route_stacks;
static GRID_SQUARE *route_squares;
static MAP_F4 *route_polygons;
static MR_SVEC *route_vertices;
static PATH_SEGMENT **route_segments;
static int route_width,route_depth,route_segment_count;
static int route_start_x,route_start_z,route_start_y;
static int route_candidate_count,route_selected_slot;
static int route_inventory_count;
static int route_reasons[128],route_inventory_uids[128],route_inventory_flags[128];
static int route_inventory_types[128];
static MR_VEC route_inventory_positions[60][128];
static int route_indices[128],route_uids[128],route_entity_flags[128];
static int route_distances[128],route_speeds[128],route_segment_indices[128];
static PATH_RUNNER route_runners[128];
static int route_form_x,route_form_z,route_xofs,route_zofs,route_height,route_max_y;
static int route_radius,route_book_flags;
static int route_form_cells[64];
static int route_base_x,route_base_z;
static int route_group_x,route_group_z,route_group_width,route_group_depth;
static int route_group_base_x,route_group_base_z,route_map_index,route_death_height;
static MAP_GROUP *route_groups;
static ENTITY *route_group_roots;
static MR_MAT camera_matrix;
static int route_int(FILE *stream);

/* Admission counterexample, not a script interpreter or route simulation.
 * Execute the actual frozen random-branch instruction with no hit/carry flags.
 * An invented target is only a pointer marker; it is never executed. */
static int script_rng_run(const char *fixture) {
    FILE *stream=fopen(fixture,"r");
    if(!stream) { perror(fixture); return 2; }
    int count=route_int(stream);
    if(count<1 || count>256) { fclose(stream); return 2; }
    MR_LONG target[]={ENTSCR_STOP};
    MR_LONG *saved_none=Scripts[SCRIPT_NONE];
    Scripts[SCRIPT_NONE]=target;
    puts("case,seed,divisor,sound_disabled,seed_after,branch_taken,continues");
    for(int index=0;index<count;index++) {
        int seed=route_int(stream),divisor=route_int(stream),muted=route_int(stream);
        if(seed<0 || (divisor!=2 && divisor!=4) || (muted!=0 && muted!=1)) {
            Scripts[SCRIPT_NONE]=saved_none;fclose(stream);return 2;
        }
        LIVE_ENTITY live={0};
        SCRIPT_INFO state={0};
        MR_LONG args[]={ENTSCR_NEW_SCRIPT,ENTSCR_RANDOM,SCRIPT_NONE,divisor};
        MRRnd_seed=(MR_ULONG)seed;
        Game_over_no_new_sound=muted;
        MR_LONG result=ENTSCR_SCRIPT_IF_command(&live,&state,args);
        int branched=state.si_script==target;
        if(!branched && state.si_script!=args+4) {
            Scripts[SCRIPT_NONE]=saved_none;fclose(stream);return 3;
        }
        printf("%d,%d,%d,%d,%lu,%d,%d\n",index,seed,divisor,muted,
            (unsigned long)MRRnd_seed,branched,result==ENTSCR_RETURN_CONTINUE);
    }
    Scripts[SCRIPT_NONE]=saved_none;
    fclose(stream);
    return 0;
}

/* Background behavior component, not a route oracle. Supplied programs are
 * decoded numeric transports outside the repo. No collision or sound playback
 * occurs: all frog slots are inactive and traffic hit/carry flags stay zero. */
static int org1_background_run(const char *fixture) {
    FILE *stream=fopen(fixture,"r");
    if(!stream) {perror(fixture);return 2;}
    int ticks=route_int(stream),seed=route_int(stream),reverse=route_int(stream);
    int program_count=route_int(stream);
    if(ticks<1 || ticks>100000 || program_count!=10 || (reverse!=0 && reverse!=1)) return 2;
    MR_LONG *programs[256]={0};int lengths[256]={0};
    for(int n=0;n<program_count;n++) {
        int id=route_int(stream),length=route_int(stream);
        if(id<1 || id>=256 || length<1 || length>256 || programs[id]) return 2;
        programs[id]=calloc(length,sizeof(MR_LONG));lengths[id]=length;
        for(int j=0;j<length;j++) programs[id][j]=route_int(stream);
        Scripts[id]=programs[id];
    }
    int count=route_int(stream);
    if(count!=24) return 2;
    ENTITY traffic_entities[24]={0};LIVE_ENTITY traffic_lives[24]={0};
    SCRIPT_INFO states[24]={0};MR_MAT poses[24]={0};int indices[24];
    for(int n=0;n<count;n++) {
        indices[n]=route_int(stream);int id=route_int(stream);
        if(id<1 || id>=256 || !programs[id]) return 2;
        traffic_lives[n].le_entity=&traffic_entities[n];
        traffic_lives[n].le_lwtrans=&poses[n];
        traffic_lives[n].le_script=&states[n];
        MR_INIT_MAT(&poses[n]);StartScript(&states[n],id,&traffic_lives[n]);
    }
    memset(Frogs,0,sizeof(FROG)*4);
    Checkpoints=route_int(stream);
    for(int n=0;n<5;n++) {
        Checkpoint_data[n].cp_flags=route_int(stream);
        Checkpoint_data[n].cp_position.vx=route_int(stream);
        Checkpoint_data[n].cp_position.vy=route_int(stream);
        Checkpoint_data[n].cp_position.vz=route_int(stream);
    }
    struct { ENTITY entity; ORG_BONUS_FLY payload; } fly_data={0};
    LIVE_ENTITY fly={0};ORG_RT_BONUS_FLY fly_state={0};
    fly.le_entity=&fly_data.entity;fly.le_specific=&fly_state;
    MR_INIT_MAT(&fly_data.payload.bf_matrix);
    for(int j=0;j<3;j++) fly_data.payload.bf_matrix.t[j]=route_int(stream);
    fclose(stream);Game_total_viewports=0;Game_over_no_new_sound=0;
    ENTSTROrgCreateBonusFly(&fly);
    MRRnd_seed=(MR_ULONG)seed;
    puts("tick,index,root_program,cursor,loop_start,loop_end,timer,callback_condition,callback_type,callback_called,rng,fly_mode,fly_timer,fly_checkpoint,covered,entity_flags,x,y,z,sounds");
    for(int tick=0;tick<ticks;tick++) {
        for(int visit=0;visit<25;visit++) {
            int n=reverse?24-visit:visit;sounds=0;
            if(n==24) ENTSTROrgUpdateBonusFly(&fly);
            else UpdateScriptInfo(&traffic_lives[n]);
            int covered=0;
            for(int j=0;j<5;j++) if(Checkpoint_data[j].cp_flags & GEN_CHECKPOINT_IS_COVERED) covered|=1<<j;
            int root=-1,cursor=-1,start=-1,end=-1,timer=-1,condition=-1,type=-1,called=-1;
            if(n!=24) {
                SCRIPT_INFO *s=&states[n];root=s->si_type;timer=s->si_timer;
                if(s->si_script<programs[root] || s->si_script>=programs[root]+lengths[root]) return 3;
                cursor=(int)(s->si_script-programs[root]);
                if(s->si_script_loop_start) start=(int)(s->si_script_loop_start-programs[root]);
                if(s->si_script_loop_end) end=(int)(s->si_script_loop_end-programs[root]);
                condition=s->si_script_callback_condition[0];type=s->si_script_callback_type[0];called=s->si_script_callback_called[0];
            }
            printf("%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%lu,%ld,%ld,%ld,%d,%u,%ld,%ld,%ld,%d\n",
                tick,n==24?55:indices[n],root,cursor,start,end,timer,condition,type,called,
                (unsigned long)MRRnd_seed,(long)fly_state.bf_mode,(long)fly_state.bf_timer,
                (long)fly_state.bf_checkpoint_id,covered,fly.le_entity->en_flags,
                (long)fly.le_lwtrans->t[0],(long)fly.le_lwtrans->t[1],(long)fly.le_lwtrans->t[2],sounds);
        }
    }
    for(int id=0;id<256;id++) free(programs[id]);
    return 0;
}

/* Execute real allocation/owner clearing without a voice/playback update. */
static int moving_sound_state_run(const char *fixture) {
    FILE *stream=fopen(fixture,"r");if(!stream) return 2;
    int sound=route_int(stream),minimum=route_int(stream),maximum=route_int(stream);
    fclose(stream);
    void *raw=NULL,*pool=MRStub_PoolAlloc(1024*1024,&raw);
    if(!pool) return 2;
    MRInitMem(pool,1024*1024);MRStub_SetMemArena(pool,1024*1024);
    extern MRSND_MOVING_SOUND MRSND_moving_sound_root;
    extern MRSND_MOVING_SOUND *MRSND_moving_sound_root_ptr;
    extern MR_ULONG MRSND_moving_sound_count;
    extern MR_USHORT MRSND_viewports;
    memset(&MRSND_moving_sound_root,0,sizeof(MRSND_moving_sound_root));
    MRSND_moving_sound_root_ptr=&MRSND_moving_sound_root;MRSND_moving_sound_count=0;MRSND_viewports=0;
    ENTITY entity={0};LIVE_ENTITY live={0};SCRIPT_INFO state={0};MR_MAT pose={0};
    live.le_entity=&entity;live.le_lwtrans=&pose;
    MR_LONG args[]={sound,ENTSCR_NO_REGISTERS,minimum,maximum};
    memset(Frogs,0,sizeof(FROG)*4);Game_total_players=1;MRRnd_seed=12345;
    puts("case,allocated,count,min_radius,max_radius,owner_matches,rng");
    for(int c=0;c<5;c++) {
        Game_over_no_new_sound=c==0;
        if(c==3) KillMovingSound(&live);
        else ENTSCR_PLAY_MOVING_SOUND_command(&live,&state,args);
        MRSND_MOVING_SOUND *snd=live.le_moving_sound;
        printf("%d,%d,%lu,%ld,%ld,%d,%lu\n",c,snd!=NULL,(unsigned long)MRSND_moving_sound_count,
          snd?(long)snd->ms_min_radius:-1,snd?(long)snd->ms_max_radius:-1,
          snd?snd->ms_owner==(MRSND_MOVING_SOUND**)&live.le_moving_sound:0,(unsigned long)MRRnd_seed);
    }
    if(live.le_moving_sound) KillMovingSound(&live);
    return 0;
}

static int zone_run(const char *fixture) {
    FILE *stream=fopen(fixture,"r");
    if(!stream) {perror(fixture);return 2;}
    int count=route_int(stream);
    if(count<1 || count>64) return 2;
    ZONE **zone_ptrs=calloc(count,sizeof(*zone_ptrs));
    zone_header.zh_numzones=count;
    Map_zone_header=&zone_header;Map_zone_ptrs=zone_ptrs;
    for(int index=0;index<count;index++) {
        ZONE *zone=calloc(1,sizeof(*zone));zone_ptrs[index]=zone;
        zone->zo_type=route_int(stream);zone->zo_numregions=route_int(stream);
        zone->zo_xmin=route_int(stream);zone->zo_zmin=route_int(stream);
        zone->zo_xmax=route_int(stream);zone->zo_zmax=route_int(stream);
        if(zone->zo_numregions>64) return 2;
        if(zone->zo_numregions) zone->zo_regions=calloc(zone->zo_numregions,sizeof(ZONE_REGION));
        for(int region=0;region<zone->zo_numregions;region++) {
            ZONE_REGION *part=&zone->zo_regions[region];
            part->zr_xmin=route_int(stream);part->zr_zmin=route_int(stream);
            part->zr_xmax=route_int(stream);part->zr_zmax=route_int(stream);
        }
    }
    int queries=route_int(stream);
    if(queries<1 || queries>100000) return 2;
    puts("query,x,z,type,found,zone_index,region_index");
    for(int query=0;query<queries;query++) {
        int x=route_int(stream),z=route_int(stream),type=route_int(stream);
        ZONE *hit=NULL;ZONE_REGION *region=NULL;
        int found=CheckCoordsInZones(x,z,type,&hit,&region);
        int zone_index=-1,region_index=-1;
        if(found) {
            for(int index=0;index<count;index++) if(zone_ptrs[index]==hit) zone_index=index;
            if(zone_index<0) return 3;
            if(hit->zo_numregions) region_index=(int)(region-hit->zo_regions);
        }
        printf("%d,%d,%d,%d,%d,%d,%d\n",query,x,z,type,found,zone_index,region_index);
    }
    fclose(stream);return 0;
}

static int route_int(FILE *stream) {
    int value;
    if (fscanf(stream,"%d",&value)!=1) { fputs("incomplete retail route fixture\n",stderr); exit(2); }
    return value;
}

/* Exact stored-part arithmetic used by MR_ANIM and MR_COLL. The transport
 * contains decoded integer transforms/vertices, never executable data. */
static int frog_probe_run(const char *file) {
    FILE *stream=fopen(file,"r"); if(!stream) return 2;
    int count=route_int(stream); if(count<1 || count>2000000) return 2;
    puts("probe,x,y,z");
    for(int n=0;n<count;n++) {
        MR_MAT owner={0},part={0},world={0};
        MR_SVEC translation={0},vertex={0},point={0}; MR_VEC moved={0};
        for(int r=0;r<3;r++) for(int c=0;c<3;c++) owner.m[r][c]=route_int(stream);
        for(int r=0;r<3;r++) for(int c=0;c<3;c++) part.m[r][c]=route_int(stream);
        translation.vx=route_int(stream);translation.vy=route_int(stream);translation.vz=route_int(stream);
        vertex.vx=route_int(stream);vertex.vy=route_int(stream);vertex.vz=route_int(stream);
        MRMulMatrixABC(&owner,&part,&world);
        MRApplyMatrix(&owner,&translation,&moved);
        world.t[0]=moved.vx;world.t[1]=moved.vy;world.t[2]=moved.vz;
        MRApplyMatrixSVEC(&world,&vertex,&point);
        point.vx+=world.t[0];point.vy+=world.t[1];point.vz+=world.t[2];
        printf("%d,%d,%d,%d\n",n,point.vx,point.vy,point.vz);
    }
    int extra; if(fscanf(stream,"%d",&extra)!=EOF) return 2;
    fclose(stream);return 0;
}

static void route_read(const char *file) {
    FILE *stream=fopen(file,"r");
    if(!stream) { perror(file); exit(2); }
    route_width=route_int(stream);route_depth=route_int(stream);
    route_base_x=route_int(stream);route_base_z=route_int(stream);
    route_start_x=route_int(stream);route_start_y=route_int(stream);route_start_z=route_int(stream);
    route_group_base_x=route_int(stream);route_group_base_z=route_int(stream);
    route_group_x=route_int(stream);route_group_z=route_int(stream);
    route_group_width=route_int(stream);route_group_depth=route_int(stream);
    route_map_index=route_int(stream);route_death_height=route_int(stream);
    if(route_width<1 || route_depth<1 || route_width*route_depth>4096) exit(2);
    int cells=route_width*route_depth;
    int total_squares=route_int(stream);
    if(total_squares<cells/2 || total_squares>8192) exit(2);
    route_stacks=calloc(cells,sizeof(*route_stacks));
    route_squares=calloc(total_squares,sizeof(*route_squares));
    route_polygons=calloc(total_squares,sizeof(*route_polygons));
    route_vertices=calloc(total_squares*4,sizeof(*route_vertices));
    int square_index=0;
    for(int i=0;i<cells;i++) {
        int count=route_int(stream),average=route_int(stream);
        if(count<0 || count>255 || square_index+count>total_squares) exit(2);
        route_stacks[i].gs_numsquares=count;route_stacks[i].gs_average_ht=average;
        route_stacks[i].gs_index=square_index;
        for(int layer=0;layer<count;layer++) {
            int current=square_index++;
            route_squares[current].gs_flags=route_int(stream);
            route_squares[current].gs_map_poly=&route_polygons[current];
            for(int j=0;j<4;j++) {
                MR_SVEC *v=&route_vertices[current*4+j];
                v->vx=route_int(stream);v->vy=route_int(stream);v->vz=route_int(stream);
                route_polygons[current].mp_vertices[j]=current*4+j;
            }
        }
    }
    if(square_index!=total_squares) exit(2);
    route_segment_count=route_int(stream);
    if(route_segment_count<1 || route_segment_count>64) exit(2);
    route_segments=calloc(route_segment_count,sizeof(*route_segments));
    for(int i=0;i<route_segment_count;i++) {
        int kind=route_int(stream),length=route_int(stream);
        int bytes=kind==0?sizeof(PATH_SPLINE):kind==1?sizeof(PATH_ARC):kind==2?sizeof(PATH_LINE):0;
        if(!bytes || length<=0) exit(2);
        route_segments[i]=calloc(1,offsetof(PATH_SEGMENT,ps_segment_ptr)+bytes);
        route_segments[i]->ps_type=kind;
        MR_LONG *dest=(MR_LONG*)&route_segments[i]->ps_segment_ptr;
        dest[0]=length;
        if(kind==0) for(int j=0;j<28;j++) dest[j+1]=route_int(stream);
        else if(kind==2) {
            PATH_LINE *line=(PATH_LINE*)dest;
            line->pl_start.vx=route_int(stream);line->pl_start.vy=route_int(stream);line->pl_start.vz=route_int(stream);
            line->pl_end.vx=route_int(stream);line->pl_end.vy=route_int(stream);line->pl_end.vz=route_int(stream);
        } else { fputs("route arc not yet supported\n",stderr); exit(2); }
    }
    route_candidate_count=route_int(stream);route_selected_slot=-1;
    if(route_candidate_count<1 || route_candidate_count>128) exit(2);
    for(int i=0;i<route_candidate_count;i++) {
        route_indices[i]=route_int(stream);route_uids[i]=route_int(stream);
        route_entity_flags[i]=route_int(stream);route_segment_indices[i]=route_int(stream);
        route_distances[i]=route_int(stream);route_speeds[i]=route_int(stream);
        if(route_indices[i]==24) route_selected_slot=i;
        if(i && route_indices[i]<=route_indices[i-1]) exit(2);
        if(route_segment_indices[i]<0 || route_segment_indices[i]>=route_segment_count) exit(2);
    }
    if(route_selected_slot<0) exit(2);
    route_form_x=route_int(stream);route_form_z=route_int(stream);
    route_xofs=route_int(stream);route_zofs=route_int(stream);
    route_height=route_int(stream);route_max_y=route_int(stream);
    route_radius=route_int(stream);route_book_flags=route_int(stream);
    if(route_form_x<1 || route_form_z<1 || route_form_x*route_form_z>64) exit(2);
    for(int i=0;i<route_form_x*route_form_z;i++) route_form_cells[i]=route_int(stream);
    route_inventory_count=route_int(stream);
    if(route_inventory_count!=115) exit(2);
    for(int index=0;index<route_inventory_count;index++) {
        if(route_int(stream)!=index) exit(2);
        route_inventory_uids[index]=route_int(stream);
        route_inventory_flags[index]=route_int(stream);
        route_inventory_types[index]=route_int(stream);
        route_reasons[index]=route_int(stream);
        if(route_inventory_types[index]<0 || route_inventory_types[index]>ENTITY_TYPE_SWP_STAT_WEIR) exit(2);
        if(route_reasons[index]<0 || route_reasons[index]>5) exit(2);
        for(int tick=0;tick<60;tick++) {
            route_inventory_positions[tick][index].vx=route_int(stream);
            route_inventory_positions[tick][index].vy=route_int(stream);
            route_inventory_positions[tick][index].vz=route_int(stream);
        }
    }
    fclose(stream);
}

static void print_contact_order(FROG *frog) {
    int fx=(frog->fr_lwtrans->t[0]-Map_view_basepoint.vx)/Map_view_xlen;
    int fz=(frog->fr_lwtrans->t[2]-Map_view_basepoint.vz)/Map_view_zlen;
    int xmin=fx-1<0?0:fx-1,xmax=fx+1>=Map_view_xnum?Map_view_xnum-1:fx+1;
    int zmin=fz-1<0?0:fz-1,zmax=fz+1>=Map_view_znum?Map_view_znum-1:fz+1;
    int first=1;
    for(int z=zmin;z<=zmax;z++) for(int x=xmin;x<=xmax;x++) {
        ENTITY *e=groups[z*Map_view_xnum+x].mg_entity_root_ptr->en_next;
        while(e) {
            if(!first)putchar(';');
            printf("%d",(int)(e-entities));first=0;
            e=e->en_next;
        }
    }
    if(first)putchar('-');
}

static void setup_entities(int scenario) {
    memset(entities,0,sizeof(entities)); memset(lives,0,sizeof(lives));
    memset(books,0,sizeof(books)); memset(groups,0,sizeof(groups));
    memset(entity_roots,0,sizeof(entity_roots));
    entity_count=1;
    Map_view_basepoint.vx=Map_view_basepoint.vz=-512;
    Map_view_xnum=Map_view_znum=3; Map_view_xlen=Map_view_zlen=768;
    Map_groups=groups;
    for(int g=0;g<9;g++) groups[g].mg_entity_root_ptr=&entity_roots[g];
    Form_library_ptrs[0]=books; Map_form_ptrs=forms;
    InitialisePathRunners();
    for(int i=0;i<entity_count;i++) {
        forms[i]=calloc(1,offsetof(FORM,fo_formdata_ptrs)+sizeof(FORM_DATA*));
        FORM *form=forms[i]; FORM_DATA *data=&form_data[i]; memset(data,0,sizeof(*data));
        data->fd_height_type=FORM_DATA_HEIGHT_TYPE_GRID; data->fd_height=0;
        form_flags[i][0]=GRID_SQUARE_USABLE|GRID_SQUARE_SAFE;
        form_flags[i][1]=scenario==12 ? GRID_SQUARE_USABLE : scenario==13 ? GRID_SQUARE_USABLE|GRID_SQUARE_POPDEATH : form_flags[i][0];
        data->fd_grid_squares=form_flags[i]; memcpy(&form->fo_formdata_ptrs,&data,sizeof(data));
        form->fo_numformdatas=1;form->fo_xnum=(scenario==4 || scenario==5 || scenario==9 || scenario==12 || scenario==13) ? 2 : 1;form->fo_znum=1;
        form->fo_xofs=(scenario==4 || scenario==9 || scenario==12 || scenario==13) ? -256 : -128;form->fo_zofs=-128;form->fo_max_y=1000;
        books[i].fb_radius2=1000000;
        books[i].fb_type_of_death=FORM_DEATH_POP;
        books[i].fb_flags=scenario==5 ? FORM_BOOK_FROG_NO_CENTRING_X :
                          scenario==6 ? FORM_BOOK_FROG_NO_ROTATION_SNAPPING|FORM_BOOK_FROG_NO_ENTITY_ANGLE :
                          (scenario==8 || scenario==15) ? FORM_BOOK_FROG_NO_ENTITY_ANGLE : 0;
        ENTITY *e=&entities[i]; LIVE_ENTITY *live=&lives[i];
        e->en_unique_id=(MR_USHORT)(40+i);e->en_form_book_id=(MR_USHORT)i;
        e->en_form_grid_id=(MR_USHORT)i;e->en_live_entity=live;
        live->le_entity=e;live->le_lwtrans=&live->le_matrix;
        MR_INIT_MAT(&live->le_matrix);
        live->le_matrix.t[0]=(scenario==4 || scenario==9 || scenario==12 || scenario==13) ? 0 : scenario==5 ? -149 : scenario==11 ? -158 : -128;
        live->le_matrix.t[2]=-128;
        if(scenario==6 || scenario==7) {
            live->le_matrix.m[0][0]=scenario==6 ? 0 : 3547;
            live->le_matrix.m[0][2]=scenario==6 ? 4096 : 2048;
            live->le_matrix.m[2][0]=scenario==6 ? -4096 : -2048;
            live->le_matrix.m[2][2]=scenario==6 ? 0 : 3547;
        }
        if(scenario==3) {
            e->en_flags=ENTITY_ALIGN_TO_WORLD;
            moving_segment=calloc(1,offsetof(PATH_SEGMENT,ps_segment_ptr)+sizeof(PATH_LINE));
            moving_segment->ps_type=PATH_SEGMENT_LINE;
            PATH_LINE *line=(PATH_LINE*)&moving_segment->ps_segment_ptr;
            line->pl_length=40;
            line->pl_start.vx=-150;line->pl_start.vz=-128;
            line->pl_end.vx=-110;line->pl_end.vz=-128;
            moving_segments[0]=moving_segment;memset(&moving_runner,0,sizeof(moving_runner));
            moving_runner.pr_flags=PATH_RUNNER_ACTIVE|PATH_RUNNER_REPEAT;
            moving_runner.pr_numsegments=1;moving_runner.pr_segments=moving_segments;
            moving_runner.pr_segment_type=PATH_SEGMENT_LINE;
            moving_runner.pr_segment_ptr=&moving_segment->ps_segment_ptr;
            moving_runner.pr_segment_length=line->pl_length;moving_runner.pr_speed=1;
            EvaluatePathRunnerPosition(&moving_runner);
            EvaluatePathRunnerTotalDistance(&moving_runner);
            e->en_path_runner=&moving_runner;
            moving_runner.pr_next=NULL;moving_runner.pr_prev=Path_runner_root_ptr;
            Path_runner_root_ptr->pr_next=&moving_runner;
            ENTSTRUpdateMovingMOF(live);
        }
        EntityLinkToMapGroup(e,(MR_VEC*)live->le_lwtrans->t);
    }
}
static void setup(void) {
    memset(Frogs,0,sizeof(FROG)*4); memset(Cameras,0,sizeof(CAMERA)*4);
    memset(MRInput,0,sizeof(MR_INPUT)*1); memset(&matrix,0,sizeof(matrix));
    memset(&trail,0,sizeof(trail)); memset(&trail_effect,0,sizeof(trail_effect));
    srand(12345); animations=sounds=scores=pgens=0;
    Grid_xnum=Grid_znum=4; Grid_xlen=Grid_zlen=256; Grid_base_x=Grid_base_z=-512;
    Grid_xshift=Grid_zshift=8; Grid_squares=squares; Grid_stacks=stacks; Map_vertices=vertices;
    for(int i=0;i<16;i++) {
        int x=-512+(i%4)*256,z=-512+(i/4)*256;
        int xs[4]={x,x+256,x,x+256},zs[4]={z+256,z+256,z,z};
        for(int j=0;j<4;j++) { vertices[i*4+j].vx=xs[j];vertices[i*4+j].vy=0;vertices[i*4+j].vz=zs[j];polygons[i].mp_vertices[j]=i*4+j; }
        squares[i].gs_map_poly=&polygons[i]; squares[i].gs_flags=GRID_SQUARE_USABLE|GRID_SQUARE_SAFE;
        stacks[i].gs_numsquares=1;stacks[i].gs_index=i;
    }
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

static void route_setup(void) {
    setup();animation_setup(1);
    Grid_xnum=route_width;Grid_znum=route_depth;
    Grid_xlen=Grid_zlen=256;Grid_xshift=Grid_zshift=8;
    Grid_base_x=route_base_x;Grid_base_z=route_base_z;
    Grid_squares=route_squares;Grid_stacks=route_stacks;Map_vertices=route_vertices;
    int cell_x=(route_start_x-route_base_x)>>8,cell_z=(route_start_z-route_base_z)>>8;
    if(cell_x<0 || cell_x>=route_width || cell_z<0 || cell_z>=route_depth) exit(2);
    FROG *frog=&Frogs[0];
    frog->fr_grid_x=cell_x;frog->fr_grid_z=cell_z;
    GRID_STACK *start_stack=&route_stacks[cell_z*route_width+cell_x];
    if(!start_stack->gs_numsquares) exit(2);
    frog->fr_grid_square=&route_squares[start_stack->gs_index+start_stack->gs_numsquares-1];
    frog->fr_pos.vx=route_start_x<<16;frog->fr_pos.vy=route_start_y<<16;frog->fr_pos.vz=route_start_z<<16;
    frog->fr_y=route_start_y;frog->fr_direction=3;
    UpdateFrogOldPositionalInfo(frog);
    matrix.t[0]=route_start_x;matrix.t[1]=route_start_y;matrix.t[2]=route_start_z;
    general_header.gh_default_camera_source_ofs.vx=0;
    general_header.gh_default_camera_source_ofs.vy=-1435;
    general_header.gh_default_camera_source_ofs.vz=-100;
    general_header.gh_default_camera_target_ofs.vx=0;
    general_header.gh_default_camera_target_ofs.vy=0;
    general_header.gh_default_camera_target_ofs.vz=0;
    Map_view_basepoint.vx=route_group_base_x;Map_view_basepoint.vz=route_group_base_z;
    Map_view_xnum=route_group_x;Map_view_znum=route_group_z;
    Map_view_xlen=route_group_width;Map_view_zlen=route_group_depth;
    if(route_group_x<1 || route_group_z<1 || route_group_x*route_group_z>1024) exit(2);
    route_groups=calloc(route_group_x*route_group_z,sizeof(*route_groups));
    route_group_roots=calloc(route_group_x*route_group_z,sizeof(*route_group_roots));
    Map_groups=route_groups;
    for(int i=0;i<route_group_x*route_group_z;i++) route_groups[i].mg_entity_root_ptr=&route_group_roots[i];
    memset(entities,0,sizeof(entities));memset(lives,0,sizeof(lives));
    memset(books,0,sizeof(books));memset(form_data,0,sizeof(form_data));
    Form_library_ptrs[0]=books;Map_form_ptrs=forms;
    forms[0]=calloc(1,offsetof(FORM,fo_formdata_ptrs)+sizeof(FORM_DATA*));
    FORM *form=forms[0];FORM_DATA *data=&form_data[0];
    data->fd_height_type=FORM_DATA_HEIGHT_TYPE_GRID;data->fd_height=route_height;
    for(int i=0;i<route_form_x*route_form_z;i++) form_flags[0][i]=route_form_cells[i];
    data->fd_grid_squares=form_flags[0];memcpy(&form->fo_formdata_ptrs,&data,sizeof(data));
    form->fo_numformdatas=1;form->fo_xnum=route_form_x;form->fo_znum=route_form_z;
    form->fo_xofs=route_xofs;form->fo_zofs=route_zofs;form->fo_max_y=route_max_y;
    books[0].fb_radius2=route_radius;books[0].fb_flags=route_book_flags;
    books[0].fb_entity_type=ENTITY_TYPE_MOVING;
    InitialisePathRunners();memset(route_runners,0,sizeof(route_runners));
    entity_count=route_inventory_count;
    for(int index=0;index<route_inventory_count;index++) {
        entities[index].en_unique_id=route_inventory_uids[index];
        entities[index].en_flags=route_inventory_flags[index];
    }
    for(int i=0;i<route_candidate_count;i++) {
        int index=route_indices[i];
        if(route_reasons[index]!=0 || route_inventory_uids[index]!=route_uids[i] ||
            route_inventory_flags[index]!=route_entity_flags[i]) exit(2);
        PATH_RUNNER *runner=&route_runners[index];
        int segment=route_segment_indices[i];
        runner->pr_flags=PATH_RUNNER_ACTIVE|PATH_RUNNER_REPEAT;
        runner->pr_numsegments=route_segment_count;runner->pr_segments=route_segments;
        runner->pr_segment_index=segment;
        runner->pr_segment_type=route_segments[segment]->ps_type;
        runner->pr_segment_ptr=&route_segments[segment]->ps_segment_ptr;
        runner->pr_segment_length=((PATH_SPLINE*)runner->pr_segment_ptr)->ps_length;
        runner->pr_segment_dist=route_distances[i];runner->pr_speed=route_speeds[i];
        EvaluatePathRunnerPosition(runner);EvaluatePathRunnerTotalDistance(runner);
        if((runner->pr_next=Path_runner_root_ptr->pr_next))
            Path_runner_root_ptr->pr_next->pr_prev=runner;
        Path_runner_root_ptr->pr_next=runner;runner->pr_prev=Path_runner_root_ptr;
        ENTITY *entity=&entities[index];LIVE_ENTITY *live=&lives[index];
        entity->en_form_book_id=0;entity->en_form_grid_id=0;
        entity->en_live_entity=live;entity->en_path_runner=runner;
        live->le_entity=entity;live->le_lwtrans=&live->le_matrix;
        MR_INIT_MAT(&live->le_matrix);ENTSTRUpdateMovingMOF(live);
    }
    for(int index=0;index<route_inventory_count;index++)
        if(Entity_library[route_inventory_types[index]].eb_flags & ENTITY_BOOK_STATIC)
            EntityLinkToMapGroup(&entities[index],&route_inventory_positions[0][index]);
    Game_total_viewports=0;frog->fr_lives=3;Game_map=route_map_index;
    Cheat_collision_toggle=FALSE;Cheat_infinite_lives_toggle=FALSE;
    Fade_top_left_pos.vx=-32767;Fade_top_left_pos.vz=32767;
    Fade_bottom_right_pos.vx=32767;Fade_bottom_right_pos.vz=-32767;
    if(Theme_library[Game_map_theme].tb_death_height!=route_death_height) exit(2);
    memset(&camera_matrix,0,sizeof(camera_matrix));Cameras[0].ca_matrix=&camera_matrix;
    ResetCamera(Cameras);Cameras[0].ca_mode=CAMERA_MODE_FOLLOW_FROG;Cameras[0].ca_move_timer=0;
    Cameras[0].ca_current_source_ofs=general_header.gh_default_camera_source_ofs;
    Cameras[0].ca_current_target_ofs=general_header.gh_default_camera_target_ofs;
    Cameras[0].ca_current.vx=route_start_x;Cameras[0].ca_current.vy=route_start_y;
    Cameras[0].ca_current.vz=route_start_z;UpdateCamera(Cameras);
}

static void route_emit(int tick,const char *phase) {
    FROG *f=&Frogs[0];CAMERA *c=&Cameras[0];
    int world_x=f->fr_pos.vx>>16,world_z=f->fr_pos.vz>>16;
    if(world_x<1900 || world_x>=2304 || world_z< -5376 || world_z>= -4864 ||
       f->fr_lwtrans->t[0]<1900 || f->fr_lwtrans->t[0]>=2304 ||
       f->fr_lwtrans->t[2]< -5376 || f->fr_lwtrans->t[2]>= -4864) {
        fprintf(stderr,"admission rectangle escaped at tick %d phase %s\n",tick,phase);exit(3);
    }
    int selected=route_indices[route_selected_slot];
    int attached=f->fr_entity?(int)(f->fr_entity-entities):-1;
    int forbidden=f->fr_forbid_entity?(int)(f->fr_forbid_entity-entities):-1;
    printf("%d,%s,%d,%d,%d,%d,%d,%d,%d,%d,%u,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%u,%u,%d,%d,",
      tick,phase,f->fr_pos.vx,f->fr_pos.vy,f->fr_pos.vz,
      f->fr_velocity.vx,f->fr_velocity.vy,f->fr_velocity.vz,
      f->fr_grid_x,f->fr_grid_z,f->fr_flags,f->fr_mode,
      attached,f->fr_count,f->fr_direction,f->fr_current_key,
      lives[selected].le_matrix.t[0],lives[selected].le_matrix.t[1],lives[selected].le_matrix.t[2],
      route_runners[selected].pr_segment_index,route_runners[selected].pr_segment_dist,
      c->ca_current.vx,c->ca_current.vy,c->ca_current.vz,
      c->ca_frog_controller_directions[0],c->ca_frog_controller_directions[1],
      c->ca_frog_controller_directions[2],c->ca_frog_controller_directions[3],
      f->fr_old_y,f->fr_entity_grid_x,f->fr_entity_grid_z,
      forbidden,lives[selected].le_flags,Game_mode,pgens,sounds);
    printf("%u,",MRInput[0].in_pad_new);
    int fx=(f->fr_lwtrans->t[0]-Map_view_basepoint.vx)/Map_view_xlen;
    int fz=(f->fr_lwtrans->t[2]-Map_view_basepoint.vz)/Map_view_zlen;
    int xmin=fx-1<0?0:fx-1,xmax=fx+1>=Map_view_xnum?Map_view_xnum-1:fx+1;
    int zmin=fz-1<0?0:fz-1,zmax=fz+1>=Map_view_znum?Map_view_znum-1:fz+1;
    int first=1;
    for(int z=zmin;z<=zmax;z++) for(int x=xmin;x<=xmax;x++) {
        ENTITY *e=route_groups[z*Map_view_xnum+x].mg_entity_root_ptr->en_next;
        while(e) {
            if(!first) putchar(';');
            printf("%d",(int)(e-entities));first=0;e=e->en_next;
        }
    }
    if(first) putchar('-');
    putchar(',');first=1;
    for(int i=route_inventory_count-1;i>=0;i--) if(lives[i].le_flags & LIVE_ENTITY_HIT_FROG_0) {
        if(!first)putchar(';');printf("%d",i);first=0;
    }
    if(first)putchar('-');
    putchar('\n');
}

static int route_run(const char *fixture) {
    route_read(fixture);route_setup();
    puts("tick,phase,x16,y16,z16,vx16,vy16,vz16,grid_x,grid_z,flags,mode,attached,count,direction,input,entity_x,entity_y,entity_z,segment,distance,camera_x,camera_y,camera_z,controller_n,controller_e,controller_s,controller_w,old_y,entity_cell_x,entity_cell_z,forbidden,entity_flags,game_mode,pgen_requests,sound_requests,pad_mask,contact_order,hit_indices");
    for(int tick=0;tick<60;tick++) {
        MR_ULONG key=0;
        int desired=tick==0?3:tick==12?1:-1;
        if(desired>=0) {
            for(int direction=0;direction<4;direction++) if(Cameras[0].ca_frog_controller_directions[direction]==desired) {
                key=direction==0?Frogs[0].fr_control_method->fc_up_control:
                    direction==1?Frogs[0].fr_control_method->fc_right_control:
                    direction==2?Frogs[0].fr_control_method->fc_down_control:
                    Frogs[0].fr_control_method->fc_left_control;
            }
            if(!key) { fprintf(stderr,"no input mapping for world direction %d at tick %d\n",desired,tick);return 1; }
        }
        MRInput[0].in_pad_down=key;MRInput[0].in_pad_new=key;
        for(int i=0;i<route_inventory_count;i++) {
            lives[i].le_flags &= ~LIVE_ENTITY_CLEAR_MASK;
            ENTITY *entity=&entities[i];
            if(!(Entity_library[route_inventory_types[i]].eb_flags & ENTITY_BOOK_STATIC) && entity->en_prev) {
                entity->en_prev->en_next=entity->en_next;
                if(entity->en_next) entity->en_next->en_prev=entity->en_prev;
                entity->en_prev=entity->en_next=NULL;
            }
        }
        UpdatePathRunners();
        for(int i=route_candidate_count-1;i>=0;i--)
            ENTSTRUpdateMovingMOF(&lives[route_indices[i]]);
        for(int index=0;index<route_inventory_count;index++) {
            MR_VEC *position=&route_inventory_positions[tick][index];
            if(route_reasons[index]==0) {
                MR_VEC *actual=&route_runners[index].pr_position;
                if(actual->vx!=position->vx || actual->vy!=position->vy || actual->vz!=position->vz) {
                    fprintf(stderr,"independent path mismatch at tick %d entity %d\n",tick,index);return 3;
                }
                position=actual;
            } else if(entities[index].en_live_entity) {
                fputs("excluded entity accidentally live\n",stderr);return 3;
            }
            if(!(Entity_library[route_inventory_types[index]].eb_flags & ENTITY_BOOK_STATIC))
                EntityLinkToMapGroup(&entities[index],position);
        }
        MRFrame_number=tick;
        ControlFrog(Frogs);route_emit(tick,"control");
        MoveFrog(Frogs);route_emit(tick,"move");
        CollideFrog(Frogs);route_emit(tick,"collision");
        UpdateCamera(Cameras);route_emit(tick,"camera");
        UpdateFrogAnimationScripts();route_emit(tick,"scripts");
        MR_USHORT saved=env.ae_flags;env.ae_flags&=~MR_ANIM_ENV_UPDATE;
        MRAnimUpdateEnvironments();env.ae_flags=saved;route_emit(tick,"pose");
        if(Game_mode!=GAME_MODE_LEVEL_PLAY) return 1;
    }
    return 0;
}

static void integrated_emit(int scenario,int tick,const char* phase) {
 FROG* f=Frogs; CAMERA* c=Cameras; FROG_ANIM_INFO* ai=&f->fr_anim_info;
 int program,offset;pointer(ai->fi_script,&program,&offset);
 printf("%d,%d,%s,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%lu,%ld,%ld,%ld,%ld,%ld,%lu,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%u,%u,%lu,%ld,%d,%d,%d,%d,%d,%u,%lu",
 scenario,tick,phase,f->fr_pos.vx,f->fr_pos.vy,f->fr_pos.vz,f->fr_velocity.vx,f->fr_velocity.vy,f->fr_velocity.vz,
 f->fr_grid_x,f->fr_grid_z,f->fr_count,f->fr_flags,f->fr_mode,f->fr_current_key,f->fr_direction,f->fr_no_input_timer,f->fr_death_count,
 c->ca_mode,c->ca_move_timer,c->ca_twist_counter,c->ca_current.vx,c->ca_current.vy,c->ca_current.vz,
 camera_matrix.t[0],camera_matrix.t[1],camera_matrix.t[2],c->ca_frog_controller_directions[0],c->ca_shake_timer,
 ai->fi_type,ai->fi_timer,ai->fi_flags,env.ae_flags,MRRnd_seed,Frog_script_if_counter,program,offset,
 single.ae_action_number,single.ae_cel_number,single.ae_total_cels,env.ae_update_count,Game_mode);
 for(int i=0;i<2;i++) {
  MR_MAT *m=&lives[i].le_matrix;
  printf(",%ld,%ld,%ld,%ld,%ld,%lu",i<entity_count ? m->t[0] : -1,i<entity_count ? m->t[1] : -1,i<entity_count ? m->t[2] : -1,
    i<entity_count && entities[i].en_path_runner ? entities[i].en_path_runner->pr_segment_dist : -1,
    i<entity_count && entities[i].en_path_runner ? entities[i].en_path_runner->pr_total_dist : -1,
    i<entity_count && entities[i].en_path_runner ? entities[i].en_path_runner->pr_flags : 0);
 }
 putchar(',');print_contact_order(f);putchar(',');
 int first=1;
 for(int i=entity_count-1;i>=0;i--) if(lives[i].le_flags & LIVE_ENTITY_HIT_FROG_0) {if(!first)putchar(';');printf("%d",i);first=0;}
 if(first) putchar('-');
 printf(",%d,%d",pgens,sounds);
 int attached=f->fr_entity ? (int)(f->fr_entity-entities) : -1;
 int forbidden=f->fr_forbid_entity ? (int)(f->fr_forbid_entity-entities) : -1;
 printf(",%d,%d,%ld,%ld,%ld,%ld,%ld,%ld,%ld",attached,forbidden,
  f->fr_entity_grid_x,f->fr_entity_grid_z,f->fr_entity_ofs.vx,f->fr_entity_ofs.vy,
  f->fr_entity_ofs.vz,f->fr_entity_angle,f->fr_old_y);
 for(int row=0;row<3;row++) for(int col=0;col<3;col++) printf(",%d",f->fr_entity_transform.m[row][col]);
 for(int axis=0;axis<3;axis++) printf(",%ld",f->fr_entity_transform.t[axis]);
 putchar(',');int carry_first=1;
 for(int i=0;i<entity_count;i++) if(lives[i].le_flags & LIVE_ENTITY_CARRIES_FROG_0) {
  if(!carry_first)putchar(';');printf("%d",i);carry_first=0;
 }
 if(carry_first)putchar('-');
 for(int row=0;row<3;row++) for(int col=0;col<3;col++) printf(",%d",c->ca_mod_matrix.m[row][col]);
 for(int axis=0;axis<3;axis++) printf(",%ld",c->ca_mod_matrix.t[axis]);
 printf(",%ld,%ld,%ld",c->ca_mod_matrix_current_ytheta,c->ca_mod_matrix_dest_ytheta,c->ca_mod_matrix_delta_ytheta);
 for(int dir=0;dir<4;dir++) for(int axis=0;axis<3;axis++) {
  MR_VEC *v=&c->ca_direction_vectors[dir];printf(",%ld",axis==0?v->vx:axis==1?v->vy:v->vz);
 }
 putchar('\n');
}
#include "org1_route_oracle.h"
#include "entity_script_oracle.h"

int main(int argc, char **argv) {
 if(argc!=2 && argc!=4) {fprintf(stderr,"usage: platform_oracle <absolute-acos-table-path> [--retail-route|--zones|--script-rng|--org1-background|--moving-sound-state <decoded-facts>]\n");return 2;}
 MRStub_LoadAcosTable(argv[1]);
 SetErrorMode(3);setvbuf(stdout,NULL,_IONBF,0);MRStub_GpuInit(NULL,0);
 if(argc==4) {
    if(!strcmp(argv[2],"--retail-route")) return route_run(argv[3]);
    if(!strcmp(argv[2],"--zones")) return zone_run(argv[3]);
    if(!strcmp(argv[2],"--script-rng")) return script_rng_run(argv[3]);
    if(!strcmp(argv[2],"--org1-background")) return org1_background_run(argv[3]);
    if(!strcmp(argv[2],"--moving-sound-state")) return moving_sound_state_run(argv[3]);
    if(!strcmp(argv[2],"--frog-probes")) return frog_probe_run(argv[3]);
    if(!strcmp(argv[2],"--org1-route")) return org1_route_run(argv[3]);
    if(!strcmp(argv[2],"--org1-road")) {org_road=1;return org1_route_run(argv[3]);}
    if(!strcmp(argv[2],"--entity-script")) return entity_script_run(argv[3]);
    if(!strcmp(argv[2],"--frog-roots")) return org1_roots_run(argv[3]);
    return 2;
 }
 puts("scenario,tick,phase,x16,y16,z16,vx16,vy16,vz16,grid_x,grid_z,count,flags,mode,input,direction,no_input_timer,death_count,camera_mode,camera_move_timer,camera_twist,camera_x,camera_y,camera_z,source_x,source_y,source_z,controller_up,shake_timer,animation_type,script_timer,animation_flags,env_flags,rng_seed,if_counter,program,offset,action,cel,total,update_count,game_mode,e0x,e0y,e0z,e0segment,e0total,e0flags,e1x,e1y,e1z,e1segment,e1total,e1flags,contact_order,hit_indices,pgen_requests,sound_requests,current_entity_index,forbidden_entity_index,entity_cell_x,entity_cell_z,entity_offset_x16,entity_offset_y16,entity_offset_z16,entity_angle,old_y,entity_transform00,entity_transform01,entity_transform02,entity_transform10,entity_transform11,entity_transform12,entity_transform20,entity_transform21,entity_transform22,entity_transform_t0,entity_transform_t1,entity_transform_t2,entity_carry_indices,camera_mod00,camera_mod01,camera_mod02,camera_mod10,camera_mod11,camera_mod12,camera_mod20,camera_mod21,camera_mod22,camera_mod_t0,camera_mod_t1,camera_mod_t2,camera_current_ytheta,camera_destination_ytheta,camera_delta_ytheta,camera_direction_n_x,camera_direction_n_y,camera_direction_n_z,camera_direction_e_x,camera_direction_e_y,camera_direction_e_z,camera_direction_s_x,camera_direction_s_y,camera_direction_s_z,camera_direction_w_x,camera_direction_w_y,camera_direction_w_z");
 for(int scenario=3;scenario<16;scenario++) {
  setup();animation_setup(0);
  if(scenario==14 || scenario==15) squares[9].gs_flags=GRID_SQUARE_USABLE|GRID_SQUARE_WATER;
  if(scenario==9) {Frogs[0].fr_powerup_flags=FROG_POWERUP_QUICK_JUMP;Frogs[0].fr_quick_jump_timer=240;}
  Game_total_viewports=0;Frogs[0].fr_lives=3;Game_map=0;
  Cheat_collision_toggle=FALSE;Cheat_infinite_lives_toggle=FALSE;
  Fade_top_left_pos.vx=-32767;Fade_top_left_pos.vz=32767;
  Fade_bottom_right_pos.vx=32767;Fade_bottom_right_pos.vz=-32767;
  Theme_library[Game_map_theme].tb_death_height=30000;
  memset(&camera_matrix,0,sizeof(camera_matrix));Cameras[0].ca_matrix=&camera_matrix;
  ResetCamera(Cameras);Cameras[0].ca_mode=CAMERA_MODE_FOLLOW_FROG;Cameras[0].ca_move_timer=0;
  Cameras[0].ca_current_source_ofs=general_header.gh_default_camera_source_ofs;
  Cameras[0].ca_current_target_ofs=general_header.gh_default_camera_target_ofs;
  /* Explicit follow component start, matching RunStart.camera_startup=false.
   * Original ResetCamera's level-start sweep is covered by the camera corpus. */
  Cameras[0].ca_current.vx=matrix.t[0];Cameras[0].ca_current.vy=matrix.t[1];Cameras[0].ca_current.vz=matrix.t[2];
  UpdateCamera(Cameras);
  setup_entities(scenario);
  int ticks=scenario==3 ? 20 : scenario==4 ? 12 : scenario==8 ? 10 : scenario==9 ? 9 : scenario==10 ? 20 : scenario==11 ? 5 : scenario==12 ? 12 : scenario==13 ? 8 : (scenario==14 || scenario==15) ? 9 : 1;
  for(int tick=0;tick<ticks;tick++) {
   MR_ULONG up=Frogs[0].fr_control_method->fc_up_control;
   MR_ULONG right=Frogs[0].fr_control_method->fc_right_control;
   MR_ULONG super=Frogs[0].fr_control_method->fc_superjump_control;
   MRInput[0].in_pad_down=((scenario==3 && tick==12) || ((scenario==8 || scenario==14 || scenario==15) && tick==3)) ? up :
                            ((scenario==4 || scenario==9 || scenario==12 || scenario==13) && tick==3 ? right : scenario==10 && tick==3 ? super : 0);
   MRInput[0].in_pad_new=MRInput[0].in_pad_down;
   /* Mirrors UpdateLiveEntities before UpdateFrogs: carry is reasserted by
    * MoveFrog only while ON_ENTITY, or by a fresh SAFE contact. */
   for(int i=0;i<entity_count;i++) lives[i].le_flags &= ~LIVE_ENTITY_CLEAR_MASK;
   UpdatePathRunners();
   if(scenario==3) ENTSTRUpdateMovingMOF(&lives[0]);
   MRFrame_number=tick;
   ControlFrog(Frogs);integrated_emit(scenario-3,tick,"control");
   MoveFrog(Frogs);integrated_emit(scenario-3,tick,"move");
   CollideFrog(Frogs);
   integrated_emit(scenario-3,tick,"collision");
   UpdateCamera(Cameras);integrated_emit(scenario-3,tick,"camera");
   UpdateFrogAnimationScripts();integrated_emit(scenario-3,tick,"scripts");
   MR_USHORT saved=env.ae_flags;env.ae_flags&=~MR_ANIM_ENV_UPDATE;MRAnimUpdateEnvironments();env.ae_flags=saved;
   integrated_emit(scenario-3,tick,"pose");
   if(Game_mode!=GAME_MODE_LEVEL_PLAY) break;
  }
 }
 return 0;
}
