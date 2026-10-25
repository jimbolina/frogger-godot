/* Decoded numeric stimuli only. Link unchanged frozen zone, control and camera code. */
#include "ZONE.H"
#include "MISC.H"
#include <stddef.h>

static int cz_read(FILE *stream) {
    int value;
    if(fscanf(stream,"%d",&value)!=1) {fputs("Invalid camera-zone fixture\n",stderr);exit(2);}
    return value;
}
static void cz_vec(FILE *stream,MR_SVEC *v) {
    v->vx=cz_read(stream);v->vy=cz_read(stream);v->vz=cz_read(stream);v->pad=0;
}
static int cz_id(ZONE **zones,int count,ZONE *zone) {
    if(!zone)return -1;
    for(int i=0;i<count;i++)if(zones[i]==zone)return i;
    fputs("Unknown camera-zone pointer\n",stderr);exit(3);
}
static void cz_print_svec(MR_SVEC *v) {printf(",%d,%d,%d",v->vx,v->vy,v->vz);}
static int camera_zone_trace(const char *path) {
    FILE *stream=fopen(path,"r");if(!stream)return 2;
    /* Frozen sanitized FROG.C repairs the vendor expression's sizeof(ZONE) stride. */
    if(sizeof(ZONE)!=24 || sizeof(MR_SVEC)!=8 || sizeof(ZONE_CAMERA)!=68)return 3;
    setup(0);MRStub_GpuInit(NULL,0);
    int startup=cz_read(stream),yaw=cz_read(stream),count=cz_read(stream),ticks=cz_read(stream);
    if(count<1 || count>128 || ticks<1 || ticks>10000)return 2;
    cz_vec(stream,&general_header.gh_default_camera_source_ofs);
    cz_vec(stream,&general_header.gh_default_camera_target_ofs);
    ZONE **zones=calloc(count,sizeof(*zones));
    for(int i=0;i<count;i++) {
        zones[i]=calloc(1,sizeof(ZONE)+sizeof(ZONE_CAMERA));ZONE *z=zones[i];
        z->zo_type=0;z->zo_xmin=cz_read(stream);z->zo_zmin=cz_read(stream);
        z->zo_xmax=cz_read(stream);z->zo_zmax=cz_read(stream);z->zo_numregions=cz_read(stream);
        if(z->zo_numregions>128)return 2;
        if(z->zo_numregions)z->zo_regions=calloc(z->zo_numregions,sizeof(ZONE_REGION));
        for(int j=0;j<z->zo_numregions;j++) {
            ZONE_REGION *r=z->zo_regions+j;
            r->zr_xmin=cz_read(stream);r->zr_zmin=cz_read(stream);r->zr_xmax=cz_read(stream);r->zr_zmax=cz_read(stream);
        }
        ZONE_CAMERA *c=(ZONE_CAMERA*)(z+1);c->zc_flags=cz_read(stream);c->zc_direction=cz_read(stream);
        for(int j=0;j<8;j++)cz_vec(stream,(&c->zc_source_ofs_n)+j);
    }
    Map_zone_ptrs=zones;zone_header.zh_numzones=count;
    CAMERA *camera=&Cameras[0];MR_MAT cm={0};camera->ca_matrix=&cm;
    FROG *frog=&Frogs[0];matrix.t[0]=matrix.t[1]=matrix.t[2]=0;
    ResetCamera(camera);
    if(startup)memset(camera->ca_frog_controller_directions,0,sizeof(camera->ca_frog_controller_directions));
    if(!startup) {
        camera->ca_mode=CAMERA_MODE_FOLLOW_FROG;camera->ca_move_timer=0;
        camera->ca_current_source_ofs=general_header.gh_default_camera_source_ofs;
        camera->ca_current_target_ofs=general_header.gh_default_camera_target_ofs;
        cm.t[0]=camera->ca_current_source_ofs.vx;cm.t[1]=camera->ca_current_source_ofs.vy;cm.t[2]=camera->ca_current_source_ofs.vz;
    }
    camera->ca_mod_matrix.m[0][0]=camera->ca_mod_matrix.m[2][2]=rcos(yaw);
    camera->ca_mod_matrix.m[0][2]=rsin(yaw);camera->ca_mod_matrix.m[2][0]=-rsin(yaw);
    camera->ca_twist_quadrants=1;
    for(int t=0;t<ticks;t++) {
        frog->fr_grid_x=cz_read(stream);frog->fr_grid_z=cz_read(stream);
        for(int axis=0;axis<3;axis++)matrix.t[axis]=cz_read(stream);
        int freeze=cz_read(stream),turn=cz_read(stream),fixed=cz_read(stream);
        Game_start_timer=cz_read(stream);
        if(freeze)frog->fr_flags|=FROG_DO_NOT_UPDATE_CAMERA_ZONES;
        else frog->fr_flags&=~FROG_DO_NOT_UPDATE_CAMERA_ZONES;
        UpdateFrogCameraZone(frog);
        if(turn) {
            if(frog->fr_cam_zone && !camera->ca_zone)return 3;
            frog->fr_mode=FROG_MODE_STATIONARY;
            MRInput[0].in_pad_down=turn>0 ? frog->fr_control_method->fc_camera_clockwise_control : frog->fr_control_method->fc_camera_anticlockwise_control;
            MRInput[0].in_pad_new=MRInput[0].in_pad_down;
            ControlFrog(frog);
        }
        if(fixed)camera->ca_mode=CAMERA_MODE_FIXED;
        UpdateCamera(camera);
        int zi=cz_id(zones,count,frog->fr_cam_zone),ri=-1;
        if(zi>=0 && zones[zi]->zo_numregions)ri=(int)(frog->fr_cam_zone_region-zones[zi]->zo_regions);
        printf("zone,%d,%d,%d,%ld,%ld,%ld,%ld,%ld",zi,ri,cz_id(zones,count,camera->ca_zone),
            (long)camera->ca_mode,(long)camera->ca_move_timer,(long)camera->ca_twist_counter,
            (long)camera->ca_twist_quadrants,(long)frog->fr_entity_angle);
        printf(",%ld,%ld,%ld",(long)camera->ca_current.vx,(long)camera->ca_current.vy,(long)camera->ca_current.vz);
        cz_print_svec(&camera->ca_current_source_ofs);cz_print_svec(&camera->ca_current_target_ofs);
        cz_print_svec(&camera->ca_next_source_ofs);cz_print_svec(&camera->ca_next_target_ofs);
        for(int i=0;i<3;i++)printf(",%ld",(long)cm.t[i]);
        for(int col=0;col<3;col++)for(int row=0;row<3;row++)printf(",%d",cm.m[row][col]);
        for(int i=0;i<4;i++)printf(",%ld",(long)camera->ca_frog_controller_directions[i]);
        for(int row=0;row<3;row++)for(int col=0;col<3;col++)printf(",%d",camera->ca_mod_matrix.m[row][col]);
        puts("");
    }
    fclose(stream);
    for(int i=0;i<count;i++){free(zones[i]->zo_regions);free(zones[i]);}free(zones);
    return 0;
}
