#define main frozen_game_main
#include "FROG.H"
#include "CAMERA.H"
#undef main
#include "gpu/mr_stub_gpu.h"
#include "backend/mr_stub_disp.h"
#include "harness/mr_stub_png.h"
#undef main
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
void __real_save_screenshot(const char* path);
void __wrap_save_screenshot(const char* path) {
    FROG* f=&Frogs[0];CAMERA* c=&Cameras[0];
    MR_ANIM_ENV* env=(MR_ANIM_ENV*)f->fr_api_item;
    MR_ANIM_ENV_SINGLE* single=env->ae_extra.ae_extra_env_single;
    printf("CAPTURE_FACTS path=%s frame=%lu frog_mode=%lu action=%d cel=%d frog=%ld,%ld,%ld camera_mode=%lu camera=%ld,%ld,%ld basis=",path,MRFrame_number,f->fr_mode,single->ae_action_number,single->ae_cel_number,f->fr_lwtrans->t[0],f->fr_lwtrans->t[1],f->fr_lwtrans->t[2],c->ca_mode,c->ca_matrix->t[0],c->ca_matrix->t[1],c->ca_matrix->t[2]);
    for(int a=0;a<3;a++)for(int b=0;b<3;b++)printf("%d%s",c->ca_matrix->m[a][b],a==2&&b==2?" frog_basis=":",");
    for(int a=0;a<3;a++)for(int b=0;b<3;b++)printf("%d%s",f->fr_lwtrans->m[a][b],a==2&&b==2?"\n":",");
    __real_save_screenshot(path);
    const char* foreground=getenv("GAMEPLAY_SOURCE_FOREGROUND");
    const char* match=getenv("GAMEPLAY_SOURCE_FOREGROUND_MATCH");
    if(foreground && *foreground && (!match || !*match || strstr(path,match))) {
        MR_VIEWPORT* original=Game_viewports[0];
        MR_VIEWPORT* vp=MRCreateViewport(NULL,NULL,MR_VP_SIZE_4096,0);
        MR_FRAME frame;memset(&frame,0,sizeof(frame));
        frame.fr_lw_transform=*c->ca_matrix;vp->vp_camera=&frame;
        vp->vp_perspective=original->vp_perspective;
        vp->vp_light_matrix=original->vp_light_matrix;
        vp->vp_colour_matrix=original->vp_colour_matrix;
        vp->vp_back_colour=original->vp_back_colour;
        vp->vp_flags &= ~(MR_VP_REBUILD_LIGHT_MATRIX|MR_VP_REBUILD_COLOUR_MATRIX);
        MRAnimAddEnvToViewport(env,vp,0);
        static MR_VIEWPORT root;
        root.vp_next_node=vp;vp->vp_next_node=NULL;vp->vp_prev_node=&root;
        MRViewport_root_ptr=&root;
        MRUpdateViewportRenderMatrices();
        MR_PART* parts=(MR_PART*)((unsigned char*)env->ae_header->ah_static_files[single->ae_model->am_static_model]+sizeof(MR_MOF));
        for(unsigned p=0;p<single->ae_model->am_no_of_parts;p++) {
            unsigned flags=single->ae_parts_flags?single->ae_parts_flags[p]:MR_ANIM_PART_DISPLAY;
            printf("PART_FLAGS %u %u %u %lu\n",p,flags,!(flags&MR_ANIM_PART_REDUNDANT)&&(!(env->ae_special_flags&MR_ANIM_ENV_DISPLAY_LIMITED_PARTS)||(flags&MR_ANIM_PART_DISPLAY)),env->ae_special_flags);
            MR_MAT local,world,view;MR_VEC moved;
            MRAnimEnvGetPartTransform(env,&local,0,p);
            MRMulMatrixABC(f->fr_lwtrans,&local,&world);
            MR_SVEC local_t={local.t[0],local.t[1],local.t[2],0};
            MRApplyMatrix(f->fr_lwtrans,&local_t,&moved);
            for(int a=0;a<3;a++)world.t[a]=f->fr_lwtrans->t[a]+((MR_LONG*)&moved)[a];
            MRMulMatrixABC(&vp->vp_render_matrix,&world,&view);
            MR_SVEC relative={world.t[0]-c->ca_matrix->t[0],world.t[1]-c->ca_matrix->t[1],world.t[2]-c->ca_matrix->t[2],0};
            MRApplyMatrix(&vp->vp_render_matrix,&relative,(MR_VEC*)view.t);
            for(unsigned v=0;v<parts[p].mp_verts;v++) {
                MR_SVEC* at=&parts[p].mp_partcel_ptr[0].mp_vert_ptr[v];MR_VEC projected;
                MRApplyMatrix(&view,at,&projected);
                projected.vx+=view.t[0];projected.vy+=view.t[1];projected.vz+=view.t[2];
                MR_LONG depth=projected.vz<128?128:projected.vz;
                printf("LANDMARK %u %u %d %d %d",p,v,at->vx,at->vy,at->vz);
                for(int a=0;a<3;a++)for(int b=0;b<3;b++)printf(" %d",world.m[a][b]);
                printf(" %ld %ld %ld %ld %ld %ld %ld %ld\n",world.t[0],world.t[1],world.t[2],projected.vx,projected.vy,projected.vz,320+projected.vx*256/depth,240+projected.vy*256/depth);
            }
        }
        MRStub_SetDispRasterization(TRUE);
        MRClearDisplay();MRStub_GpuClearFrame(0,0,0);
        MRRenderViewport(vp);MRSwapDisplay();
        unsigned char* pixels=malloc(640*480*4);int w=0,h=0;
        if(!pixels || !MRStub_ReadFramePixels(pixels,&w,&h) || !MRH_write_png(foreground,w,h,pixels))exit(3);
        printf("FOREGROUND path=%s width=%d height=%d action=%d cel=%d\n",foreground,w,h,single->ae_action_number,single->ae_cel_number);
        free(pixels);exit(0);
    }
}


extern int SDL_main(int argc,char** argv);
int main(int argc,char** argv) { return SDL_main(argc,argv); }
