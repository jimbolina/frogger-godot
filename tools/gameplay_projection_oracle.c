/* Asset-free scalar projection fixture using frozen camera/view/GTE functions.
 * No renderer, retail data or copied implementation is embedded here. */
#include "MR_ALL.H"
#include "gpu/mr_stub_gpu.h"
#include "gpu/mr_stub_gte.h"
#undef main
#include <stdio.h>
#include <string.h>
#include <stdint.h>
__declspec(dllimport) unsigned long __stdcall SetErrorMode(unsigned long);
int main(void) {
    static MR_DISPLAY display;
    static MR_VIEWPORT root, vp;
    static MR_FRAME frame;
    MR_RECT rect={0,0,640,480};
    MR_VEC up={0,4096,0,0};
    const int poses[][3]={{0,-500,-500},{-500,-500,0},{0,-1000,-100},{200,-400,400}};
    const int points[][3]={{0,0,0},{128,0,128},{-128,0,128},{128,0,-128},{-128,0,-128},{0,-64,0},{0,-128,0},{0,0,256},{256,0,0},{0,0,-256}};
    SetErrorMode(0x8003);
    MRStub_GpuInit(NULL,0);
    display.di_screen[0]=display.di_screen[1]=rect;
    MRDisplay_ptr=&display;
    root.vp_next_node=&vp; MRViewport_root_ptr=&root;
    vp.vp_camera=&frame;
    MRChangeViewport(&vp,&rect);
    vp.vp_perspective=256;
    printf("pose,point,width,height,h,aspect_x,aspect_y,source_x,source_y,source_z,vertex_x,vertex_y,vertex_z,r00,r01,r02,r10,r11,r12,r20,r21,r22,translation_x,translation_y,translation_z,view_x,view_y,view_z,clamped_z,screen_x,screen_y,ca00,ca01,ca02,ca10,ca11,ca12,ca20,ca21,ca22\n");
    for(int p=0;p<4;p++) {
        MR_VEC target={0,0,0,0};
        if(p==3)target.vy=100;
        memset(&frame.fr_lw_transform,0,sizeof(MR_MAT));
        for(int k=0;k<3;k++)frame.fr_lw_transform.t[k]=poses[p][k];
        MRPointMatrixAtVector(&frame.fr_lw_transform,&target,&up);
        MRUpdateViewportRenderMatrices();
        MR_MAT render=vp.vp_render_matrix;
        MR_SVEC neg={-poses[p][0],-poses[p][1],-poses[p][2],0};
        MR_VEC translation;
        MRApplyMatrix(&render,&neg,&translation);
        render.t[0]=translation.vx;render.t[1]=translation.vy;render.t[2]=translation.vz;
        gte_SetRotMatrix(&render);gte_SetTransMatrix(&render);
        gte_SetGeomOffset(vp.vp_geom_x,vp.vp_geom_y);gte_SetGeomScreen(vp.vp_perspective);
        for(int q=0;q<10;q++) {
            MR_SVEC vertex={points[q][0],points[q][1],points[q][2],0};
            MR_VEC view;
            int32_t sz;int16_t xy[2];
            MRApplyMatrix(&render,&vertex,&view);
            view.vx+=translation.vx;view.vy+=translation.vy;view.vz+=translation.vz;
            gte_ldv0(&vertex);gte_rtps();gte_stsxy(xy);gte_stsz(&sz);
            printf("%d,%d,640,480,256,%d,%d,%d,%d,%d,%d,%d,%d",p,q,vp.vp_aspect_matrix.m[0][0],vp.vp_aspect_matrix.m[1][1],poses[p][0],poses[p][1],poses[p][2],points[q][0],points[q][1],points[q][2]);
            for(int a=0;a<3;a++)for(int b=0;b<3;b++)printf(",%d",render.m[a][b]);
            printf(",%ld,%ld,%ld,%ld,%ld,%ld,%d,%d,%d",translation.vx,translation.vy,translation.vz,view.vx,view.vy,view.vz,sz,xy[0],xy[1]);
            for(int a=0;a<3;a++)for(int b=0;b<3;b++)printf(",%d",frame.fr_lw_transform.m[a][b]);
            printf("\n");
        }
    }
    return 0;
}
