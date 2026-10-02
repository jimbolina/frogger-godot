/* Offline entity reaction oracle.  The collision and kill functions are the
 * unchanged frozen implementations; only display/audio factories are caught. */
#define main frozen_main_unused
#include "FROG.H"
#include "COLLIDE.H"
#include "ENTITY.H"
#include "FORM.H"
#include "GRID.H"
#include "MAPVIEW.H"
#include "LIBRARY.H"
#include "CAMERA.H"
#include "GAMESYS.H"
#include "froganim.h"
#undef main
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
extern void MRStub_GpuInit(void *, int);
static MR_OBJECT pgen_object;
static MR_PGEN pgen;
static int pgens, sounds;
MR_OBJECT* __wrap_MRCreatePgen(MR_PGEN_INIT *init, MR_FRAME *frame, MR_ULONG flags, MR_SVEC *offset) {
    (void)init; (void)frame; (void)flags; (void)offset;
    pgens++; pgen_object.ob_extra.ob_extra_pgen = &pgen; return &pgen_object;
}
void __wrap_GameAddObjectToViewports(MR_OBJECT *obj) { (void)obj; }
MR_LONG __wrap_MRSNDPlaySound(MR_USHORT s, SndVolume *v, MR_USHORT f, MR_LONG p) {
    (void)s; (void)v; (void)f; (void)p; sounds++; return -1;
}
#define MAX_ENTITIES 32
#define MAX_GROUPS 256
static ENTITY entities[MAX_ENTITIES], roots[MAX_GROUPS];
static LIVE_ENTITY lives[MAX_ENTITIES];
static FORM_BOOK books[MAX_ENTITIES];
static FORM *forms[MAX_ENTITIES];
static FORM_DATA form_data[MAX_ENTITIES];
static MR_USHORT square_flags[MAX_ENTITIES][64];
static MR_MAT entity_matrices[MAX_ENTITIES], frog_matrix;
static MAP_GROUP groups[MAX_GROUPS];
static int source_indices[MAX_ENTITIES];
static int entity_kinds[MAX_ENTITIES];
static int get(long *out) { return scanf("%ld", out) == 1; }
static int geti(int *out) { long value; if (!get(&value)) return 0; *out=(int)value; return 1; }
static int scalar[64];
int main(void) {
    MRStub_GpuInit(NULL, 0);
    puts("case\tmode\tflags\tdeath_animation\tvx16\tvy16\tvz16\tcamera_mode\tpgen_requests\tsound_requests\thit_indices");
    int cases; if (!geti(&cases) || cases<0 || cases>2048) return 2;
    for (int ci=0;ci<cases;ci++) {
        memset(entities,0,sizeof(entities)); memset(roots,0,sizeof(roots));
        memset(lives,0,sizeof(lives)); memset(groups,0,sizeof(groups));
        memset(Frogs,0,sizeof(FROG)*4); memset(Cameras,0,sizeof(CAMERA)*4);
        memset(&frog_matrix,0,sizeof(frog_matrix)); pgens=sounds=0;
        int n, base_x, base_z, nx, nz, sx, sz, mode, flags, death_height;
        int frog[3], velocity[3];
        if (!geti(&n)||!geti(&base_x)||!geti(&base_z)||!geti(&nx)||!geti(&nz)||!geti(&sx)||!geti(&sz)||
            !geti(&mode)||!geti(&flags)||!geti(&death_height)) return 2;
        if (n<0||n>MAX_ENTITIES||nx<1||nz<1||nx*nz>MAX_GROUPS||sx<1||sz<1) return 2;
        for(int j=0;j<3;j++) if(!geti(&frog[j])) return 2;
        for(int j=0;j<3;j++) if(!geti(&velocity[j])) return 2;
        Map_view_basepoint.vx=base_x; Map_view_basepoint.vz=base_z;
        Map_view_xnum=nx; Map_view_znum=nz; Map_view_xlen=sx; Map_view_zlen=sz;
        Map_groups=groups;
        for(int j=0;j<nx*nz;j++) groups[j].mg_entity_root_ptr=&roots[j];
        for(int i=0;i<n;i++) {
            int idx, kind, eflags, xofs,zofs,xdim,zdim,height,maxy,radius,death;
            if(!geti(&idx)||!geti(&kind)||!geti(&eflags)) return 2;
            if(kind<0||kind>1) return 2;
            source_indices[i]=idx;
            entity_kinds[i]=kind;
            MR_MAT *m=&entity_matrices[i]; memset(m,0,sizeof(*m));
            for(int j=0;j<12;j++) {
                int v; if(!geti(&v)) return 2;
                if(j<9) m->m[j/3][j%3]=(MR_SHORT)v; else m->t[j-9]=v;
            }
            if(!geti(&xofs)||!geti(&zofs)||!geti(&xdim)||!geti(&zdim)||!geti(&height)||!geti(&maxy)||!geti(&radius)||!geti(&death)) return 2;
            if(xdim<1||zdim<1||xdim*zdim>64) return 2;
            for(int j=0;j<xdim*zdim;j++) {int v;if(!geti(&v)) return 2;square_flags[i][j]=(MR_USHORT)v;}
            forms[i]=calloc(1,offsetof(FORM,fo_formdata_ptrs)+sizeof(FORM_DATA*)); if(!forms[i]) return 2;
            FORM *form=forms[i]; FORM_DATA *data=&form_data[i]; memset(data,0,sizeof(*data));
            data->fd_height_type=FORM_DATA_HEIGHT_TYPE_GRID; data->fd_height=(MR_SHORT)height;
            data->fd_grid_squares=square_flags[i];
            memcpy(&form->fo_formdata_ptrs,&data,sizeof(data));
            form->fo_numformdatas=1; form->fo_max_y=(MR_SHORT)maxy;
            form->fo_xnum=(MR_SHORT)xdim; form->fo_znum=(MR_SHORT)zdim;
            form->fo_xofs=(MR_SHORT)xofs; form->fo_zofs=(MR_SHORT)zofs;
            books[i].fb_radius2=radius; books[i].fb_type_of_death=death;
            Form_library_ptrs[0]=books;
            entities[i].en_form_book_id=i; entities[i].en_form_grid_id=i;
            entities[i].en_flags=(MR_USHORT)eflags; entities[i].en_live_entity=&lives[i];
            lives[i].le_entity=&entities[i]; lives[i].le_lwtrans=m; lives[i].le_api_item0=NULL;
        }
        /* Map load links STATIC records in authored order.  On each frame
         * the moving pass inserts MOVING records at the group head. */
        for(int i=0;i<n;i++) if(entity_kinds[i]==0)
            EntityLinkToMapGroup(&entities[i], (MR_VEC *)entity_matrices[i].t);
        for(int i=0;i<n;i++) if(entity_kinds[i]==1 && !(entities[i].en_flags & ENTITY_HIDDEN))
            EntityLinkToMapGroup(&entities[i], (MR_VEC *)entity_matrices[i].t);
        Map_form_ptrs=forms;
        MR_MAT *m=&frog_matrix; m->m[0][0]=m->m[1][1]=m->m[2][2]=4096;
        for(int j=0;j<3;j++) m->t[j]=frog[j];
        FROG *f=&Frogs[0]; f->fr_lwtrans=m; f->fr_api_item=m; f->fr_frog_id=0;
        f->fr_mode=mode; f->fr_flags=flags; f->fr_lives=3;
        f->fr_velocity.vx=velocity[0]; f->fr_velocity.vy=velocity[1]; f->fr_velocity.vz=velocity[2];
        Game_total_players=0; Game_map_theme=0; Game_map=0;
        Theme_library[0].tb_death_height=death_height;
        Cheat_collision_toggle=FALSE; Cheat_infinite_lives_toggle=FALSE;
        Fade_top_left_pos.vx=-32767; Fade_top_left_pos.vz=32767;
        Fade_bottom_right_pos.vx=32767; Fade_bottom_right_pos.vz=-32767;
        CollideFrog(f);
        printf("%d\t%ld\t%lu\t%lu\t%ld\t%ld\t%ld\t%lu\t%d\t%d\t",ci,f->fr_mode,f->fr_flags,f->fr_death_equate,
          f->fr_velocity.vx,f->fr_velocity.vy,f->fr_velocity.vz,Cameras[0].ca_mode,pgens,sounds);
        int first=1;
        for(int gz=0;gz<nz;gz++) for(int gx=0;gx<nx;gx++) {
            ENTITY *entity=roots[gz*nx+gx].en_next;
            while(entity) {
                int i=(int)(entity-entities);
                if(lives[i].le_flags & LIVE_ENTITY_HIT_FROG_0) {
                    if(!first) putchar(','); printf("%d",source_indices[i]);first=0;
                }
                entity=entity->en_next;
            }
        }
        puts(first?"-":"");
        for(int i=0;i<n;i++) free(forms[i]);
    }
    return 0;
}
