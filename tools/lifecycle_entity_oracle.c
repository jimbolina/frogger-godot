/* Invented two-entity lifecycle through unchanged frozen path/entity/group C.
 * Models are marked NO_MODEL, and polygon payloads are empty: this transport
 * observes entity expansion and lifetime, not renderer allocation. */
#define main frozen_main_unused
#include "MR_ALL.H"
#include "gamesys.H"
#include "MAPVIEW.H"
#include "mapdisp.H"
#include "ENTITY.H"
#include "ENTLIB.H"
#include "FORM.H"
#include "PATH.H"
#include "CAMERA.H"
#include "mapload.H"
#include "PROJECT.H"
#include "FROG.H"
#include "gpu/mr_stub_gpu.h"
#include "backend/mr_stub_pool.h"
#undef main
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stddef.h>
__declspec(dllimport) unsigned long __stdcall SetErrorMode(unsigned long);
extern PATH_RUNNER *Path_runner_root_ptr;
extern LIVE_ENTITY *Live_entity_root_ptr;

static MAP_GROUP groups[1024];
static ENTITY roots[1024];
static struct { ENTITY entity; ENTSTR_STATIC data; } static_record;
static struct { ENTITY entity; ENTSTR_MOVING data; } moving_record;
static ENTITY *entities[2];
static ENTITY_HEADER entity_header;
static FORM_BOOK books[2];
static FORM *forms[1];
static MR_VIEWPORT viewport;
static MR_MAT camera;
static PATH_RUNNER runner;
static PATH_SEGMENT *segments[1];
static PATH_SEGMENT *segment_record;
static int generations[2];

static void setup(void) {
    memset(groups,0,sizeof(groups)); memset(roots,0,sizeof(roots));
    memset(&static_record,0,sizeof(static_record));
    memset(&moving_record,0,sizeof(moving_record));
    memset(books,0,sizeof(books)); memset(&runner,0,sizeof(runner));
    segment_record=calloc(1,offsetof(PATH_SEGMENT,ps_segment_ptr)+sizeof(PATH_LINE));
    Map_view_basepoint.vx=-8192; Map_view_basepoint.vz=-8192;
    Map_view_xnum=Map_view_znum=32; Map_view_xlen=Map_view_zlen=512;
    Map_groups=groups;
    for(int i=0;i<1024;i++) groups[i].mg_entity_root_ptr=&roots[i];
    Game_viewports[0]=&viewport; Game_total_viewports=1; Game_perspective=256;
    Game_map_theme=THEME_CAV;
    Cameras[0].ca_matrix=&camera;
    memset(Frogs,0,sizeof(FROG)*4);
    InitialisePathRunners(); InitialiseLiveEntities(); InitialiseMapView();
    books[0].fb_entity_type=0; books[1].fb_entity_type=1;
    books[0].fb_flags=books[1].fb_flags=FORM_BOOK_FLAG_NO_MODEL;
    Form_library_ptrs[0]=books;
    Map_form_ptrs=forms;
    entities[0]=&static_record.entity; entities[1]=&moving_record.entity;
    entity_header.eh_numentities=2; Map_entity_header=&entity_header;
    Map_entity_ptrs=entities;
    static_record.entity.en_unique_id=moving_record.entity.en_unique_id=77;
    static_record.entity.en_form_book_id=0;
    moving_record.entity.en_form_book_id=1;
    MR_INIT_MAT(&static_record.data.et_matrix);
    EntityLinkToMapGroup(&static_record.entity,(MR_VEC*)static_record.data.et_matrix.t);
    segment_record->ps_type=PATH_SEGMENT_LINE;
    PATH_LINE *line=(PATH_LINE*)&segment_record->ps_segment_ptr;
    line->pl_length=512;
    line->pl_start.vx=-256;
    line->pl_end.vx=256;
    segments[0]=segment_record;
    runner.pr_flags=PATH_RUNNER_ACTIVE|PATH_RUNNER_REPEAT;
    runner.pr_numsegments=1; runner.pr_segments=segments;
    runner.pr_segment_type=PATH_SEGMENT_LINE;
    runner.pr_segment_ptr=&segment_record->ps_segment_ptr;
    runner.pr_segment_length=512; runner.pr_segment_dist=256;
    runner.pr_speed=16;
    EvaluatePathRunnerPosition(&runner);
    EvaluatePathRunnerTotalDistance(&runner);
    runner.pr_prev=Path_runner_root_ptr;
    Path_runner_root_ptr->pr_next=&runner;
    moving_record.entity.en_path_runner=&runner;
    EntityLinkToMapGroup(&moving_record.entity,&runner.pr_position);
    memset(&camera,0,sizeof(camera));
    camera.m[0][0]=4096;
    camera.m[1][1]=2896; camera.m[1][2]=2896;
    camera.m[2][1]=-2896; camera.m[2][2]=2896;
    camera.t[1]=-512; camera.t[2]=-512;
}

static void print_row(int tick) {
    printf("%d,%d,%d,%d,%d,%d,%d,",tick,
        static_record.entity.en_live_entity!=NULL,
        static_record.entity.en_live_entity && !!(static_record.entity.en_live_entity->le_flags&LIVE_ENTITY_DESTROY),
        generations[0],moving_record.entity.en_live_entity!=NULL,
        moving_record.entity.en_live_entity && !!(moving_record.entity.en_live_entity->le_flags&LIVE_ENTITY_DESTROY),
        generations[1]);
    int first=1;
    for(LIVE_ENTITY *live=Live_entity_root_ptr->le_next;live;live=live->le_next) {
        if(!first)putchar(';');
        printf("%d",live->le_entity==&static_record.entity?2:9);
        first=0;
    }
    printf(",%ld\n",runner.pr_segment_dist);
}

int main(void) {
    SetErrorMode(3); setvbuf(stdout,NULL,_IONBF,0);
    MRStub_GpuInit(NULL,0);
    void *raw_pool=NULL;
    void *pool=MRStub_PoolAlloc(1024*1024,&raw_pool);
    if(!pool) return 2;
    MRInitMem((MR_ULONG*)pool,1024*1024);
    MRStub_SetMemArena(pool,1024*1024);
    setup();
    puts("tick,static_live,static_pending,static_generation,moving_live,moving_pending,moving_generation,live_order,moving_distance");
    print_row(0);
    for(int tick=1;tick<=6;tick++) {
        int prior_static=static_record.entity.en_live_entity!=NULL;
        int prior_moving=moving_record.entity.en_live_entity!=NULL;
        Frogs[0].fr_entity=(tick>=2&&tick<=4)?&moving_record.entity:NULL;
        UnlinkEntities(); UpdatePathRunners(); UpdateLiveEntities(); LinkEntities();
        camera.t[0]=(tick>=2&&tick<=5)?4096:0;
        CreateMapViewList(0); CreateMapGroups(0);
        if(static_record.entity.en_live_entity) static_record.entity.en_live_entity->le_flags|=LIVE_ENTITY_NO_SCREEN_FADE;
        if(moving_record.entity.en_live_entity) moving_record.entity.en_live_entity->le_flags|=LIVE_ENTITY_NO_SCREEN_FADE;
        if(!prior_static && static_record.entity.en_live_entity) generations[0]++;
        if(!prior_moving && moving_record.entity.en_live_entity) generations[1]++;
        print_row(tick);
    }
    return 0;
}
