#include "ZONE.H"
#include "MISC.H"
#include "ENTLIB.H"
#include "mapdisp.H"
#include "backend/mr_stub_pool.h"
extern LIVE_ENTITY *Live_entity_root_ptr;
static struct { ENTITY entity; ENTSTR_STATIC data; } zl_records[64];
static ENTITY *zl_entities[64];
static ENTITY_HEADER zl_header;
static FORM_BOOK zl_books[64];
static FORM *zl_forms[1];
static PATH_RUNNER zl_runners[64];
static int zl_ids[64],zl_generations[64],zl_count;
static MR_VIEWPORT zl_viewport;
static FILE *zl_input;
static int zl_read(void) {int v;if(fscanf(zl_input,"%d",&v)!=1)exit(2);return v;}
static void zl_vec(MR_SVEC *v) {v->vx=zl_read();v->vy=zl_read();v->vz=zl_read();}
static int zl_slot(ENTITY *e) {for(int i=0;i<zl_count;i++)if(zl_entities[i]==e)return i;exit(3);}
static int zl_zone(ZONE **zones,int count,ZONE *z) {if(!z)return -1;for(int i=0;i<count;i++)if(zones[i]==z)return i;exit(3);}
static void zl_vector(MR_VEC *v) {printf("[%ld,%ld,%ld]",v->vx,v->vy,v->vz);}
static void zl_svector(const char *key,MR_SVEC *v) {printf(",\"%s\":[%d,%d,%d]",key,v->vx,v->vy,v->vz);}

int main(int argc,char **argv) {
    if(argc!=2 || !(zl_input=fopen(argv[1],"r")))return 2;
    SetErrorMode(3);setvbuf(stdout,NULL,_IONBF,0);MRStub_GpuInit(NULL,0);
    void *raw=NULL,*pool=MRStub_PoolAlloc(8*1024*1024,&raw);if(!pool)return 2;
    MRInitMem((MR_ULONG*)pool,8*1024*1024);MRStub_SetMemArena(pool,8*1024*1024);
    setup(0);life_grid();animation_setup(0);
    int gameplay=zl_read(),ticks=zl_read(),yaw=zl_read();
    for(int a=0;a<3;a++)matrix.t[a]=zl_read();
    zl_vec(&general_header.gh_default_camera_source_ofs);zl_vec(&general_header.gh_default_camera_target_ofs);
    Map_view_basepoint.vx=zl_read();Map_view_basepoint.vy=zl_read();Map_view_basepoint.vz=zl_read();
    Map_view_xnum=zl_read();Map_view_znum=zl_read();Map_view_xlen=zl_read();Map_view_zlen=zl_read();
    if(Map_view_xnum*Map_view_znum>1024 || Map_view_znum>64)return 2;
    Game_total_viewports=1;Game_viewports[0]=&zl_viewport;Game_perspective=256;Game_map_theme=THEME_CAV;
    InitialisePathRunners();InitialiseLiveEntities();InitialiseMapView();
    zl_count=zl_read();if(zl_count<1 || zl_count>64)return 2;
    Map_entity_header=&zl_header;zl_header.eh_numentities=zl_count;Map_entity_ptrs=zl_entities;
    Form_library_ptrs[0]=zl_books;Map_form_ptrs=zl_forms;
    for(int i=0;i<zl_count;i++) {
        zl_ids[i]=zl_read();int moving=zl_read();int flags=zl_read();
        ENTITY *e=zl_entities[i]=&zl_records[i].entity;
        e->en_unique_id=77;e->en_form_book_id=i;e->en_flags=flags;
        zl_books[i].fb_entity_type=moving?1:0;zl_books[i].fb_flags=FORM_BOOK_FLAG_NO_MODEL;
        if(!moving) {
            MR_INIT_MAT(&zl_records[i].data.et_matrix);
            for(int a=0;a<3;a++)zl_records[i].data.et_matrix.t[a]=zl_read();
            EntityLinkToMapGroup(e,(MR_VEC*)zl_records[i].data.et_matrix.t);
            continue;
        }
        PATH_RUNNER *r=&zl_runners[i];e->en_path_runner=r;
        r->pr_numsegments=zl_read();r->pr_segment_index=zl_read();r->pr_segment_dist=zl_read();r->pr_speed=zl_read();r->pr_flags=zl_read();
        if(r->pr_numsegments<1 || r->pr_numsegments>256 || r->pr_segment_index>=r->pr_numsegments)return 2;
        r->pr_segments=calloc(r->pr_numsegments,sizeof(PATH_SEGMENT*));
        for(int j=0;j<r->pr_numsegments;j++) {
            int kind=zl_read(),length=zl_read();
            PATH_SEGMENT *s=calloc(1,offsetof(PATH_SEGMENT,ps_segment_ptr)+sizeof(PATH_SPLINE));
            r->pr_segments[j]=s;s->ps_type=kind;
            if(kind==2){PATH_LINE *line=(PATH_LINE*)&s->ps_segment_ptr;line->pl_length=length;zl_vec(&line->pl_start);zl_vec(&line->pl_end);}
            else if(kind==0){MR_LONG *words=(MR_LONG*)&s->ps_segment_ptr;words[0]=length;for(int k=1;k<29;k++)words[k]=zl_read();}
            else return 2;
        }
        PATH_SEGMENT *s=r->pr_segments[r->pr_segment_index];r->pr_segment_type=s->ps_type;r->pr_segment_ptr=&s->ps_segment_ptr;
        r->pr_segment_length=*((MR_LONG*)r->pr_segment_ptr);
        EvaluatePathRunnerPosition(r);EvaluatePathRunnerTotalDistance(r);
        r->pr_prev=Path_runner_root_ptr;r->pr_next=Path_runner_root_ptr->pr_next;
        if(r->pr_next)r->pr_next->pr_prev=r;Path_runner_root_ptr->pr_next=r;
        EntityLinkToMapGroup(e,&r->pr_position);
    }
    int count=zl_read();if(count<1 || count>128)return 2;
    ZONE **zones=calloc(count,sizeof(*zones));Map_zone_ptrs=zones;zone_header.zh_numzones=count;
    for(int i=0;i<count;i++) {
        ZONE *z=zones[i]=calloc(1,sizeof(ZONE)+sizeof(ZONE_CAMERA));
        z->zo_xmin=zl_read();z->zo_zmin=zl_read();z->zo_xmax=zl_read();z->zo_zmax=zl_read();z->zo_numregions=zl_read();
        if(z->zo_numregions>128)return 2;
        z->zo_regions=calloc(z->zo_numregions,sizeof(ZONE_REGION));
        for(int j=0;j<z->zo_numregions;j++){ZONE_REGION *r=z->zo_regions+j;r->zr_xmin=zl_read();r->zr_zmin=zl_read();r->zr_xmax=zl_read();r->zr_zmax=zl_read();}
        ZONE_CAMERA *c=(ZONE_CAMERA*)(z+1);c->zc_flags=zl_read();c->zc_direction=zl_read();
        for(int j=0;j<8;j++)zl_vec((&c->zc_source_ofs_n)+j);
    }
    CAMERA *cam=Cameras;cam->ca_matrix=&camera_matrix;ResetCamera(cam);
    cam->ca_mode=CAMERA_MODE_FOLLOW_FROG;cam->ca_move_timer=0;
    cam->ca_current_source_ofs=general_header.gh_default_camera_source_ofs;
    cam->ca_current_target_ofs=general_header.gh_default_camera_target_ofs;
    cam->ca_current.vx=matrix.t[0];cam->ca_current.vy=matrix.t[1];cam->ca_current.vz=matrix.t[2];
    cam->ca_mod_matrix.m[0][0]=cam->ca_mod_matrix.m[2][2]=rcos(yaw);
    cam->ca_mod_matrix.m[0][2]=rsin(yaw);cam->ca_mod_matrix.m[2][0]=-rsin(yaw);cam->ca_twist_quadrants=1;
    if(gameplay)UpdateCamera(cam);
    FROG *frog=Frogs;frog->fr_lives=3;Game_map=0;Cheat_collision_toggle=FALSE;Cheat_infinite_lives_toggle=FALSE;
    Fade_top_left_pos.vx=-32767;Fade_top_left_pos.vz=32767;Fade_bottom_right_pos.vx=32767;Fade_bottom_right_pos.vz=-32767;
    Theme_library[Game_map_theme].tb_death_height=30000;
    for(int t=0;t<ticks;t++) {
        int cx=zl_read(),cz=zl_read(),world[3];for(int a=0;a<3;a++)world[a]=zl_read();int key=zl_read();
        int previous[64],survived[64],destroyed[64],destroy_count=0,created[64],create_count=0;
        for(int i=0;i<zl_count;i++)previous[i]=zl_entities[i]->en_live_entity!=NULL;
        for(LIVE_ENTITY *l=Live_entity_root_ptr->le_next;l;l=l->le_next)if(l->le_flags&LIVE_ENTITY_DESTROY)destroyed[destroy_count++]=zl_slot(l->le_entity);
        UnlinkEntities();UpdatePathRunners();UpdateLiveEntities();LinkEntities();
        for(int i=0;i<zl_count;i++)survived[i]=zl_entities[i]->en_live_entity!=NULL;
        if(gameplay) {
            MR_ULONG button=key==2?frog->fr_control_method->fc_right_control:key==8?frog->fr_control_method->fc_left_control:0;
            MRInput[0].in_pad_down=MRInput[0].in_pad_new=button;MRFrame_number=t;
            ControlFrog(frog);MoveFrog(frog);CollideFrog(frog);
        } else {
            frog->fr_grid_x=cx;frog->fr_grid_z=cz;for(int a=0;a<3;a++)matrix.t[a]=world[a];UpdateFrogCameraZone(frog);
        }
        UpdateCamera(cam);
        if(gameplay){UpdateFrogAnimationScripts();MR_USHORT saved=env.ae_flags;env.ae_flags&=~MR_ANIM_ENV_UPDATE;MRAnimUpdateEnvironments();env.ae_flags=saved;}
        CreateMapViewList(0);CreateMapGroups(0);
        for(LIVE_ENTITY *l=Live_entity_root_ptr->le_next;l;l=l->le_next) {
            int i=zl_slot(l->le_entity);l->le_flags|=LIVE_ENTITY_NO_SCREEN_FADE;
            if(!survived[i]){zl_generations[i]++;created[create_count++]=i;}
        }
        int zi=zl_zone(zones,count,frog->fr_cam_zone),ri=-1;
        if(zi>=0 && zones[zi]->zo_numregions)ri=(int)(frog->fr_cam_zone_region-zones[zi]->zo_regions);
        printf("{\"tick\":%d,\"world\":[%ld,%ld,%ld],\"camera\":{\"frog_zone\":%d,\"frog_region\":%d,\"zone_index\":%d,\"move_timer\":%ld,\"twist_counter\":%ld,\"source_world\":[%ld,%ld,%ld]",t,matrix.t[0],matrix.t[1],matrix.t[2],zi,ri,zl_zone(zones,count,cam->ca_zone),cam->ca_move_timer,cam->ca_twist_counter,camera_matrix.t[0],camera_matrix.t[1],camera_matrix.t[2]);
        const char *axes[]={"axis_x_12","axis_y_12","axis_z_12"};
        for(int c=0;c<3;c++)printf(",\"%s\":[%d,%d,%d]",axes[c],camera_matrix.m[0][c],camera_matrix.m[1][c],camera_matrix.m[2][c]);
        printf(",\"mode\":%ld,\"twist_quadrants\":%ld,\"entity_angle\":%ld,\"tracked_world\":",cam->ca_mode,cam->ca_twist_quadrants,frog->fr_entity_angle);zl_vector(&cam->ca_current);
        zl_svector("source_offset",&cam->ca_current_source_ofs);zl_svector("target_offset",&cam->ca_current_target_ofs);
        zl_svector("next_source_offset",&cam->ca_next_source_ofs);zl_svector("next_target_offset",&cam->ca_next_target_ofs);
        printf(",\"controller_directions\":[%ld,%ld,%ld,%ld],\"mod_rotation\":[",cam->ca_frog_controller_directions[0],cam->ca_frog_controller_directions[1],cam->ca_frog_controller_directions[2],cam->ca_frog_controller_directions[3]);
        for(int j=0;j<9;j++){if(j)putchar(',');printf("%d",cam->ca_mod_matrix.m[j/3][j%3]);}putchar(']');
        printf("},\"selected_groups\":[");int first=1;
        for(MR_SHORT *p=Map_group_view_list[0];*p>=0;p++){if(!first)putchar(',');printf("%d",*p);first=0;}
        printf("],\"live_order\":[");first=1;
        for(LIVE_ENTITY *l=Live_entity_root_ptr->le_next;l;l=l->le_next){if(!first)putchar(',');printf("%d",zl_ids[zl_slot(l->le_entity)]);first=0;}
        printf("],\"events\":[");first=1;
        for(int j=0;j<destroy_count;j++){int i=destroyed[j];if(!first)putchar(',');printf("\"destroy:%d:%d\"",zl_ids[i],zl_generations[i]-(previous[i]&&!survived[i]&&zl_entities[i]->en_live_entity?1:0));first=0;}
        for(int j=create_count-1;j>=0;j--){int i=created[j];if(!first)putchar(',');printf("\"create:%d:%d\"",zl_ids[i],zl_generations[i]);first=0;}
        printf("],\"entities\":[");
        for(int i=0;i<zl_count;i++) {
            ENTITY *e=zl_entities[i];if(i)putchar(',');
            printf("{\"entity_index\":%d,\"live\":%s,\"destroy_pending\":%s,\"generation\":%d,\"position\":",zl_ids[i],e->en_live_entity?"true":"false",e->en_live_entity&&(e->en_live_entity->le_flags&LIVE_ENTITY_DESTROY)?"true":"false",zl_generations[i]);
            zl_vector(e->en_path_runner?&e->en_path_runner->pr_position:(MR_VEC*)zl_records[i].data.et_matrix.t);
            if(e->en_path_runner){PATH_RUNNER *r=e->en_path_runner;printf(",\"path\":[%d,%ld,%lu,%ld,%ld,%ld,%ld,%ld,%lu,%ld,%ld,%ld,%ld,%ld,%ld]",t+1,r->pr_segment_index,r->pr_segment_type,r->pr_segment_dist,r->pr_segment_length,r->pr_segment_param,r->pr_total_dist,r->pr_speed,r->pr_flags,r->pr_position.vx,r->pr_position.vy,r->pr_position.vz,r->pr_tangent.vx,r->pr_tangent.vy,r->pr_tangent.vz);}
            else printf(",\"path\":null");putchar('}');
        }
        puts("]}");
    }
    fclose(zl_input);return 0;
}
