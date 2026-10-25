/* ORG1 route research. Included by platform_oracle.c after its shared setup.
 * Input is an external decoded numeric transport. All 64 scan identities are
 * retained. The river mode makes ten candidate FORMs collision-live; the road
 * mode additionally executes all 24 decoded traffic cuboids and stored frog
 * probes. Independent neighbor/probe proof admits each preset separately. */
#include "ent_sub.h"
static ENTITY *org_entities[64];
static LIVE_ENTITY org_lives[64];
static SCRIPT_INFO org_scripts[64];
static FORM_BOOK org_books[256];
static FORM *org_forms[64];
static PATH_SEGMENT *org_paths[16][16];
static int org_path_counts[16],org_types[64],org_contact[64];
static PATH_RUNNER org_runners[64];
static MR_ANIM_ENV org_envs[64];
static MR_ANIM_ENV_FLIPBOOK org_flips[64];
static MR_MESH_INST org_mesh_instances[64];
static MR_MESH_INST *org_mesh_pointers[64];
static MR_ANIM_ENV_INST org_instances[64];
static ORG_RT_BONUS_FLY org_fly;
static ORG_RT_BABY_FROG org_baby;
static ENTITY_HEADER org_entity_header;
static MR_LONG *org_programs[256];
static int org_program_lengths[256];
static int org_road;
static int org_first_killer=-1;
static char org_primitive_contacts[2048];
extern MR_BOOL __real_MRCollisionCheck(MR_COLLCHECK*,MR_ULONG,MR_ULONG,MR_ULONG);
MR_BOOL __wrap_MRCollisionCheck(MR_COLLCHECK *check,MR_ULONG a,MR_ULONG b,MR_ULONG c) {
    MR_BOOL hit=__real_MRCollisionCheck(check,a,b,c);
    if(org_road && hit)for(int i=24;i<48;i++)if(check->mc_b_owner==org_lives[i].le_api_item0) {
        if(org_first_killer<0 && !(Frogs[0].fr_flags&FROG_MUST_DIE))org_first_killer=i;
        int part_id=-1,hilite_id=-1;MR_MOF *frog=env.ae_header->ah_static_files[0];
        for(int p=0;p<16;p++){MR_PART *part=(MR_PART*)(frog+1)+p;for(int h=0;h<part->mp_hilites;h++)if(check->mc_c_item_a==part->mp_hilite_ptr+h){part_id=p;hilite_id=h;}}
        char item[80];snprintf(item,sizeof(item),"%s%d:%d:%d:%d",*org_primitive_contacts?";":"",i,
            part_id,hilite_id,0);
        strncat(org_primitive_contacts,item,sizeof(org_primitive_contacts)-strlen(org_primitive_contacts)-1);
    }
    return hit;
}
static MR_MAT org_frog_stored[16];
static int org_stored_action,org_stored_cel;
static void org_read_matrix(FILE *in,MR_MAT *m);
/* Use unchanged frozen animation update, including its STATIC-owner cache.
 * Reset primes action 0/cel 0 explicitly; later refreshes follow the source
 * environment cel advance. Decoded quaternion records remain external facts. */
static void org_store_frog_pose(void) {
    if(org_road){MRAnimEnvUpdateLWTransforms(&env);org_stored_action=single.ae_last_action_number;org_stored_cel=single.ae_last_cel_number;}
}
static void org_read_road(FILE *in) {
    int count=route_int(in);if(count!=24)exit(2);
    for(int j=0;j<count;j++) {
        int i=route_int(in);if(i<24 || i>47)exit(2);
        LIVE_ENTITY *l=&org_lives[i];ENTITY *e=org_entities[i];
        MR_MOF *mof=calloc(1,sizeof(MR_MOF)+sizeof(MR_PART));mof->mm_extra=1;
        MR_PART *part=(MR_PART*)(mof+1);MR_COLLPRIM *cp=calloc(1,sizeof(MR_COLLPRIM));part->mp_collprim_ptr=cp;
        cp->cp_type=MR_COLLPRIM_CUBOID;cp->cp_flags=MR_COLL_LAST_IN_LIST;
        cp->cp_offset.vx=route_int(in);cp->cp_offset.vy=route_int(in);cp->cp_offset.vz=route_int(in);
        cp->cp_xlen=route_int(in);cp->cp_ylen=route_int(in);cp->cp_zlen=route_int(in);cp->cp_user=route_int(in);
        ENTITY_GET_FORM_BOOK(e)->fb_type_of_death=route_int(in);
        MR_OBJECT *object=calloc(1,sizeof(MR_OBJECT));MR_MESH *mesh=calloc(1,sizeof(MR_MESH));MR_STATIC_MESH *stat=calloc(1,sizeof(MR_STATIC_MESH));
        object->ob_flags=MR_OBJ_STATIC;object->ob_frame=(MR_FRAME*)l->le_lwtrans;object->ob_extra.ob_extra_mesh=mesh;
        mesh->me_extra.me_extra_static_mesh=stat;stat->sm_mof_ptr=mof;l->le_api_item0=object;
        e->en_live_entity=l;org_contact[i]=1;
    }
    MR_MOF *frog=calloc(1,sizeof(MR_MOF)+16*sizeof(MR_PART));frog->mm_extra=16;
    env.ae_header->ah_static_files[0]=frog;
    int n=route_int(in);if(n<1 || n>1024)exit(2);
    int counts[16]={0};MR_HILITE *hilites[16]={0};
    for(int i=0;i<16;i++)hilites[i]=calloc(n,sizeof(MR_HILITE));
    for(int j=0;j<n;j++) {
        int p=route_int(in);if(p<0 || p>=16)exit(2);
        MR_SVEC *v=calloc(1,sizeof(MR_SVEC));v->vx=route_int(in);v->vy=route_int(in);v->vz=route_int(in);
        MR_HILITE *h=&hilites[p][counts[p]++];h->mh_flags=MR_HILITE_VERTEX;h->mh_target_ptr=(MR_ULONG*)v;
    }
    for(int i=0;i<16;i++){MR_PART *p=(MR_PART*)(frog+1)+i;p->mp_hilites=counts[i];p->mp_hilite_ptr=hilites[i];}
    ((MR_UBYTE*)env.ae_header)[0]=route_int(in)?'1':'0';
    ((MR_UBYTE*)env.ae_header)[1]='2';
    int transforms=route_int(in);if(transforms<1 || transforms>32767)exit(2);
    MR_ANIM_COMMON_DATA *common=calloc(1,sizeof(MR_ANIM_COMMON_DATA));
    MR_QUATB_TRANS *data=calloc(transforms,sizeof(MR_QUATB_TRANS));
    common->ac_flags=9;common->ac_no_of_transforms=transforms;common->ac_transforms=(MR_MAT34*)data;env.ae_header->ah_common_data=common;
    for(int j=0;j<transforms;j++) {
        for(int k=0;k<4;k++)((MR_BYTE*)&data[j].q)[k]=route_int(in);
        for(int k=0;k<3;k++)data[j].t[k]=route_int(in);
    }
    if(route_int(in)!=34)exit(2);
    for(int a=0;a<34;a++) {
        int length=route_int(in),unique=route_int(in);if(length<1 || length>1000 || unique<1)exit(2);
        cels[a].ac_no_of_cels=unique;cels[a].ac_no_of_parts=16;cels[a].ac_flags=1;
        cels[a].ac_cel_numbers=calloc(length,sizeof(MR_USHORT));
        for(int j=0;j<length;j++)cels[a].ac_cel_numbers[j]=route_int(in);
        cels[a].ac_transforms.ac_indices=calloc(unique*16,sizeof(MR_SHORT));
        for(int j=0;j<unique*16;j++)cels[a].ac_transforms.ac_indices[j]=route_int(in);
    }
    model.am_no_of_parts=16;single.ae_last_action_number=-1;single.ae_last_cel_number=-1;
    env.ae_special_flags|=MR_ANIM_ENV_STORE_LW_TRANSFORMS;single.ae_lw_transforms=org_frog_stored;
    org_store_frog_pose();
}
static void org_cursor(MR_LONG *cursor,int *program,int *offset) {
    *program=*offset=-1;if(!cursor)return;
    for(int i=0;i<256;i++)if(org_programs[i] && (uintptr_t)cursor>=(uintptr_t)org_programs[i] &&
       (uintptr_t)cursor<(uintptr_t)(org_programs[i]+org_program_lengths[i])) {
        *program=i;*offset=(int)(cursor-org_programs[i]);return;
    }
}
static int org_index(ENTITY *entity) {
    if(!entity) return -1;
    for(int i=0;i<64;i++) if(org_entities[i]==entity) return i;
    return -2;
}
static void org_read_matrix(FILE *in,MR_MAT *m) {
    for(int r=0;r<3;r++) for(int c=0;c<3;c++) m->m[r][c]=route_int(in);
    for(int r=0;r<3;r++) m->t[r]=route_int(in);
}
/* Exact root transitions for the independent finite reachability closure. */
static int org1_roots_run(const char *file) {
    FILE *in=fopen(file,"r");if(!in)return 2;int count=route_int(in);
    if(count<1 || count>100000)return 2;puts("case,m00,m01,m02,m10,m11,m12,m20,m21,m22");
    for(int i=0;i<count;i++) {
        setup();FROG *f=Frogs;int kind=route_int(in);f->fr_direction=route_int(in);
        MR_MAT support={0},transpose={0};ENTITY entity={0};LIVE_ENTITY live={0};
        for(int r=0;r<3;r++)for(int c=0;c<3;c++)matrix.m[r][c]=route_int(in);
        for(int r=0;r<3;r++)for(int c=0;c<3;c++)support.m[r][c]=route_int(in);
        for(int j=0;j<4;j++){vertices[j].vx=route_int(in);vertices[j].vy=route_int(in);vertices[j].vz=route_int(in);polygons[0].mp_vertices[j]=j;}
        squares[0].gs_map_poly=&polygons[0];f->fr_grid_square=&squares[0];
        entity.en_live_entity=&live;live.le_lwtrans=&support;f->fr_entity=&entity;
        f->fr_flags=0;
        if(kind==1){f->fr_flags=FROG_JUMP_TO_ENTITY;f->fr_grid_square=NULL;}
        else if(kind==2)f->fr_flags=FROG_JUMP_FROM_ENTITY;
        else if(kind==3){
            MRTransposeMatrix(&support,&transpose);SnapFrogRotationToMatrix(f,&support,&transpose);
            MRMulMatrixABC(&matrix,&transpose,&f->fr_entity_transform);
            ProjectMatrixOntoWorldXZ(&f->fr_entity_transform,&f->fr_entity_transform);
            f->fr_flags=FROG_ON_ENTITY;
        } else if(kind!=0)return 2;
        UpdateFrogMatrix(f);printf("%d",i);
        for(int r=0;r<3;r++)for(int c=0;c<3;c++)printf(",%d",matrix.m[r][c]);putchar('\n');
    }
    fclose(in);return 0;
}
static void org_emit(int tick,const char *phase) {
    FROG *f=Frogs;
    printf("%d,%s,%ld,%ld,%ld,%lu,%lu,%d,%ld,%ld,%ld,%d,%d,%lu,%d,%d,%d,%d",
      tick,phase,(long)f->fr_pos.vx,(long)f->fr_pos.vy,(long)f->fr_pos.vz,
      (unsigned long)f->fr_flags,(unsigned long)f->fr_mode,org_index(f->fr_entity),
      (long)f->fr_count,(long)f->fr_direction,(long)f->fr_old_y,
      single.ae_action_number,single.ae_cel_number,(unsigned long)MRRnd_seed,
      org_scripts[0].si_dev_y,org_scripts[0].si_timer,org_flips[0].ae_action_number,sounds);
    for(int r=0;r<3;r++) for(int c=0;c<3;c++) printf(",%d",f->fr_lwtrans->m[r][c]);
    putchar(',');
    int fx=(f->fr_lwtrans->t[0]-Map_view_basepoint.vx)/Map_view_xlen;
    int fz=(f->fr_lwtrans->t[2]-Map_view_basepoint.vz)/Map_view_zlen,first=1;
    for(int z=MAX(0,fz-1);z<=MIN(Map_view_znum-1,fz+1);z++)
      for(int x=MAX(0,fx-1);x<=MIN(Map_view_xnum-1,fx+1);x++)
        for(ENTITY *e=Map_groups[z*Map_view_xnum+x].mg_entity_root_ptr->en_next;e;e=e->en_next) {
            if(!first) putchar(';'); first=0;printf("%d",org_index(e));
        }
    if(first) putchar('-');
    CAMERA *camera=Cameras;
    for(int j=0;j<3;j++)printf(",%ld",(long)(&camera->ca_current.vx)[j]);
    for(int j=0;j<3;j++)printf(",%ld",(long)camera_matrix.t[j]);
    /* The follow target is independently reconstructed from source fields. */
    MR_MAT projected,mod;MR_VEC target;MR_MAT *active=&camera->ca_mod_matrix;
    if(f->fr_entity){ProjectMatrixOntoWorldXZ(f->fr_entity->en_live_entity->le_lwtrans,&projected);MRMulMatrixABC(active,&projected,&mod);active=&mod;}
    MRApplyMatrix(active,&camera->ca_current_target_ofs,&target);
    for(int j=0;j<3;j++)printf(",%ld",(long)(&camera->ca_current.vx)[j]+(&target.vx)[j]);
    for(int j=0;j<4;j++)printf(",%ld",(long)camera->ca_frog_controller_directions[j]);
    for(int r=0;r<3;r++)for(int c=0;c<3;c++)printf(",%d",camera->ca_mod_matrix.m[r][c]);
    if(org_road) {
        printf(",%ld,%ld,%ld,%ld,%ld,%d,%d,%d,",(long)f->fr_velocity.vx,(long)f->fr_velocity.vy,(long)f->fr_velocity.vz,
            (long)f->fr_death_equate,(long)f->fr_lives,org_first_killer,org_stored_action,org_stored_cel);
        int found=0;for(int i=24;i<48;i++)if(org_lives[i].le_flags&LIVE_ENTITY_HIT_FROG_0){if(found++)putchar(';');printf("%d",i);}if(!found)putchar('-');
        printf(",%s",*org_primitive_contacts?org_primitive_contacts:"-");
    }
    putchar('\n');
}
static int org1_route_run(const char *file) {
    FILE *in=fopen(file,"r");if(!in) return 2;
    setup();animation_setup(0);Game_map_theme=THEME_ORG;
    int ticks=route_int(in); if(ticks<1 || ticks>100000) return 2;
    int *commands=calloc(ticks,sizeof(int));
    for(int i=0;i<ticks;i++) commands[i]=route_int(in);
    Grid_xnum=route_int(in);Grid_znum=route_int(in);
    Grid_base_x=route_int(in);Grid_base_z=route_int(in);
    for(int j=0;j<3;j++) matrix.t[j]=route_int(in);
    FROG *f=Frogs;f->fr_pos.vx=matrix.t[0]*65536;f->fr_pos.vy=matrix.t[1]*65536;f->fr_pos.vz=matrix.t[2]*65536;
    f->fr_y=matrix.t[1];f->fr_direction=0;
    Map_view_basepoint.vx=route_int(in);Map_view_basepoint.vz=route_int(in);
    Map_view_xnum=route_int(in);Map_view_znum=route_int(in);
    Map_view_xlen=route_int(in);Map_view_zlen=route_int(in);
    Game_map=route_int(in);
    int expected_death_height=route_int(in);
    if(Theme_library[Game_map_theme].tb_death_height!=expected_death_height) return 3;
    int total=route_int(in),cell_count=Grid_xnum*Grid_znum;
    if(cell_count<1 || cell_count>4096 || total<1 || total>8192) return 2;
    Grid_stacks=calloc(cell_count,sizeof(GRID_STACK));Grid_squares=calloc(total,sizeof(GRID_SQUARE));
    MAP_F4 *polys=calloc(total,sizeof(MAP_F4));Map_vertices=calloc(total*4,sizeof(MR_SVEC));
    int next=0;
    for(int i=0;i<cell_count;i++) {
        int count=route_int(in);Grid_stacks[i].gs_numsquares=count;
        Grid_stacks[i].gs_average_ht=route_int(in);Grid_stacks[i].gs_index=next;
        if(count<0 || count>255 || next+count>total) return 2;
        for(int j=0;j<count;j++,next++) {
            Grid_squares[next].gs_flags=route_int(in);Grid_squares[next].gs_map_poly=&polys[next];
            for(int k=0;k<4;k++) {
                int v=next*4+k;polys[next].mp_vertices[k]=v;
                Map_vertices[v].vx=route_int(in);Map_vertices[v].vy=route_int(in);Map_vertices[v].vz=route_int(in);
            }
        }
    }
    if(next!=total) return 2;
    f->fr_grid_x=(matrix.t[0]-Grid_base_x)>>8;f->fr_grid_z=(matrix.t[2]-Grid_base_z)>>8;
    GRID_STACK *start=&Grid_stacks[f->fr_grid_z*Grid_xnum+f->fr_grid_x];
    f->fr_grid_square=&Grid_squares[start->gs_index+start->gs_numsquares-1];
    UpdateFrogOldPositionalInfo(f);UpdateFrogMatrix(f);
    for(int i=0;i<34;i++) cels[i].ac_no_of_virtual_cels=route_int(in);
    FrogInitialiseAnimation(f,FROG_ANIMATION_PANT,0);
    /* Candidate models are independently checked primitive-free. Empty frog
     * mesh metadata permits the unchanged primitive precheck to traverse;
     * animated probe exclusion is a separate admission obligation. */
    static MR_ANIM_HEADER frog_header;static MR_ANIM_MODEL_SET frog_set;
    static MR_MOF frog_mof,*frog_statics[1];static MR_OBJECT frog_object;
    frog_statics[0]=&frog_mof;frog_header.ah_static_files=frog_statics;
    frog_set.am_models=&model;env.ae_header=&frog_header;env.ae_model_set=&frog_set;
    frog_object.ob_flags=MR_OBJ_STATIC;frog_object.ob_frame=(MR_FRAME*)&matrix;single.ae_object=&frog_object;
    for(int i=0;i<3;i++) (&general_header.gh_default_camera_source_ofs.vx)[i]=route_int(in);
    for(int i=0;i<3;i++) (&general_header.gh_default_camera_target_ofs.vx)[i]=route_int(in);
    int program_count=route_int(in);if(program_count<1 || program_count>64) return 2;
    for(int i=0;i<program_count;i++) {
        int id=route_int(in),length=route_int(in);if(id<1 || id>=256 || length<1 || length>256) return 2;
        MR_LONG *words=calloc(length,sizeof(MR_LONG));for(int j=0;j<length;j++) words[j]=route_int(in);
        Scripts[id]=words;org_programs[id]=words;org_program_lengths[id]=length;
    }
    int path_count=route_int(in);if(path_count<1 || path_count>16) return 2;
    for(int i=0;i<path_count;i++) {
        int count=org_path_counts[i]=route_int(in);if(count<1 || count>16) return 2;
        for(int j=0;j<count;j++) {
            int kind=route_int(in),length=route_int(in);
            if((kind!=0 && kind!=2) || length<=0) return 2;
            PATH_SEGMENT *s=calloc(1,offsetof(PATH_SEGMENT,ps_segment_ptr)+sizeof(PATH_SPLINE));
            org_paths[i][j]=s;s->ps_type=kind;MR_LONG *words=(MR_LONG*)&s->ps_segment_ptr;words[0]=length;
            if(kind==0) for(int k=0;k<28;k++) words[k+1]=route_int(in);
            else {
                PATH_LINE *line=(PATH_LINE*)words;
                line->pl_start.vx=route_int(in);line->pl_start.vy=route_int(in);line->pl_start.vz=route_int(in);
                line->pl_end.vx=route_int(in);line->pl_end.vy=route_int(in);line->pl_end.vz=route_int(in);
            }
        }
    }
    InitialisePathRunners();Form_library_ptrs[0]=org_books;Form_library_ptrs[1]=org_books+128;Map_form_ptrs=org_forms;
    Map_groups=calloc(Map_view_xnum*Map_view_znum,sizeof(MAP_GROUP));
    for(int i=0;i<Map_view_xnum*Map_view_znum;i++) Map_groups[i].mg_entity_root_ptr=calloc(1,sizeof(ENTITY));
    void *raw=NULL,*pool=MRStub_PoolAlloc(1024*1024,&raw);
    MRInitMem(pool,1024*1024);MRStub_SetMemArena(pool,1024*1024);
    extern MRSND_MOVING_SOUND MRSND_moving_sound_root;
    extern MRSND_MOVING_SOUND *MRSND_moving_sound_root_ptr;
    extern MR_USHORT MRSND_viewports;
    MRSND_moving_sound_root_ptr=&MRSND_moving_sound_root;MRSND_viewports=0;
    Game_total_viewports=0;Game_over_no_new_sound=0;Checkpoints=0;
    Fade_top_left_pos.vx=-32767;Fade_top_left_pos.vz=32767;
    Fade_bottom_right_pos.vx=32767;Fade_bottom_right_pos.vz=-32767;
    for(int i=0;i<64;i++) {
        if(route_int(in)!=i) return 2;
        ENTITY *e=org_entities[i]=calloc(1,sizeof(ENTITY)+128);LIVE_ENTITY *l=&org_lives[i];
        l->le_entity=e;l->le_lwtrans=&l->le_matrix;MR_INIT_MAT(l->le_lwtrans);
        e->en_unique_id=route_int(in);e->en_flags=route_int(in);e->en_form_book_id=route_int(in);
        int type=org_types[i]=route_int(in),script=route_int(in),effective=route_int(in);
        org_contact[i]=route_int(in);e->en_form_grid_id=i;
        FORM_BOOK *book=ENTITY_GET_FORM_BOOK(e);book->fb_entity_type=type;book->fb_script=script;
        book->fb_flags=route_int(in);book->fb_radius2=route_int(in);
        int nx=route_int(in),nz=route_int(in),ox=route_int(in),oz=route_int(in),height=route_int(in),maxy=route_int(in);
        FORM *form=org_forms[i]=calloc(1,offsetof(FORM,fo_formdata_ptrs)+sizeof(FORM_DATA*));
        form->fo_numformdatas=nx?1:0;form->fo_xnum=nx;form->fo_znum=nz;form->fo_xofs=ox;form->fo_zofs=oz;form->fo_max_y=maxy;
        if(nx) {
            FORM_DATA *data=calloc(1,sizeof(FORM_DATA));data->fd_height_type=FORM_DATA_HEIGHT_TYPE_GRID;data->fd_height=height;
            data->fd_grid_squares=calloc(nx*nz,sizeof(MR_USHORT));
            for(int j=0;j<nx*nz;j++) data->fd_grid_squares[j]=route_int(in);
            memcpy(&form->fo_formdata_ptrs,&data,sizeof(data));
        }
        int pid=route_int(in);
        if(pid>=0) {
            int seg=route_int(in),distance=route_int(in),speed=route_int(in);
            PATH_RUNNER *r=&org_runners[i];e->en_path_runner=r;
            r->pr_flags=PATH_RUNNER_ACTIVE|PATH_RUNNER_REPEAT;r->pr_numsegments=org_path_counts[pid];r->pr_segments=org_paths[pid];
            r->pr_segment_index=seg;r->pr_segment_type=org_paths[pid][seg]->ps_type;r->pr_segment_ptr=&org_paths[pid][seg]->ps_segment_ptr;
            r->pr_segment_length=*(MR_LONG*)r->pr_segment_ptr;r->pr_segment_dist=distance;r->pr_speed=speed;
            EvaluatePathRunnerPosition(r);EvaluatePathRunnerTotalDistance(r);
            if((r->pr_next=Path_runner_root_ptr->pr_next)) r->pr_next->pr_prev=r;
            Path_runner_root_ptr->pr_next=r;r->pr_prev=Path_runner_root_ptr;
            ENTSTRUpdateMovingMOF(l);
            MR_LONG *payload=(MR_LONG*)((char*)(e+1)+12);
            for(int j=0;j<3;j++) payload[j]=route_int(in);
        } else {
            org_read_matrix(in,(MR_MAT*)(e+1));l->le_matrix=*(MR_MAT*)(e+1);
            MR_LONG *payload=(MR_LONG*)((char*)(e+1)+sizeof(MR_MAT));
            int a=route_int(in),b=route_int(in);
            if(i==53) {ORG_BABY_FROG_DATA *baby=(ORG_BABY_FROG_DATA*)(e+1);baby->bf_unique_log_id=a;baby->bf_value=b;}
            else {payload[0]=a;payload[1]=b;}
        }
        int actions=route_int(in);
        if(actions) {
            MR_ANIM_ENV *ae=&org_envs[i];MR_MOF *mof=calloc(1,sizeof(MR_MOF)+sizeof(MR_PART));
            MR_PART *part=(MR_PART*)(mof+1);MR_PART_FLIPBOOK *flip=calloc(1,sizeof(MR_PART_FLIPBOOK)+actions*sizeof(MR_PART_FLIPBOOK_ACTION));
            part->mp_pad1=(MR_VOID*)flip;flip->mp_numactions=actions;
            for(int j=0;j<actions;j++) ((MR_PART_FLIPBOOK_ACTION*)(flip+1))[j].mp_numpartcels=route_int(in);
            ae->ae_header=(MR_ANIM_HEADER*)mof;ae->ae_extra.ae_extra_env_flipbook=&org_flips[i];
            MR_OBJECT *object=calloc(1,sizeof(MR_OBJECT));object->ob_flags=MR_OBJ_STATIC;object->ob_frame=(MR_FRAME*)l->le_lwtrans;org_flips[i].ae_object=object;
            MR_MESH *mesh=calloc(1,sizeof(MR_MESH));MR_STATIC_MESH *stat=calloc(1,sizeof(MR_STATIC_MESH));
            object->ob_extra.ob_extra_mesh=mesh;mesh->me_extra.me_extra_static_mesh=stat;stat->sm_mof_ptr=mof;
            ae->ae_flags=(MR_ANIM_ENV_DEFAULT_FLAGS&~MR_ANIM_ENV_UPDATE)|MR_ANIM_ENV_IS_FLIPBOOK;ae->ae_update_period=1;
            ae->ae_next_node=root.ae_next_node;root.ae_next_node=ae;
            l->le_api_item0=ae;l->le_flags|=LIVE_ENTITY_ANIMATED|LIVE_ENTITY_FLIPBOOK;MRAnimEnvFlipbookSetAction(ae,0);
            org_mesh_pointers[i]=&org_mesh_instances[i];org_instances[i].ae_mesh_insts=&org_mesh_pointers[i];org_instances[i].ae_models=1;
            l->le_api_insts[0]=&org_instances[i];
        }
        if(script) {
            l->le_script=&org_scripts[i];StartScript(l->le_script,script,l);
            if(type==ENTITY_TYPE_SUB_TURTLE) {
                decoded_model_factory=1;ENTSTRSubCreateTurtle(l);decoded_model_factory=0;
            }
            if(((SCRIPT_INFO*)l->le_script)->si_type!=effective) return 3;
        }
        if(i==55) {l->le_specific=&org_fly;ENTSTROrgCreateBonusFly(l);}
        if(i==53) {l->le_specific=&org_baby;decoded_model_factory=1;ENTSTROrgCreateBabyFrog(l);decoded_model_factory=0;}
        if(type==ENTITY_TYPE_GEN_TOP_LEFT) ENTSTRGenCreateTopLeft(l);
        if(type==ENTITY_TYPE_GEN_BOTTOM_RIGHT) ENTSTRGenCreateBottomRight(l);
        if(i==49 || i==50 || i==51 || i==52 || i==54) {
            int cp=i==54?0:i-48;
            MR_SET_SVEC(&Checkpoint_data[cp].cp_position,l->le_lwtrans->t[0],l->le_lwtrans->t[1],l->le_lwtrans->t[2]);
            Checkpoint_data[cp].cp_flags=0;
        }
        if(org_contact[i]) e->en_live_entity=l;
        if(Entity_library[type].eb_flags & ENTITY_BOOK_STATIC) EntityLinkToMapGroup(e,(MR_VEC*)l->le_lwtrans->t);
    }
    Map_entity_ptrs=org_entities;Map_entity_header=&org_entity_header;org_entity_header.eh_numentities=64;
    InitialiseCheckPoints();
    for(int i=0;i<64;i++)if(org_types[i]==ENTITY_TYPE_CHECKPOINT) {
        decoded_model_factory=1;Game_total_viewports=1;ENTSTRGenCreateCheckPoint(&org_lives[i]);Game_total_viewports=0;decoded_model_factory=0;
    }
    if(org_road)org_read_road(in);
    fclose(in);f->fr_lives=3;Cheat_collision_toggle=FALSE;Cheat_infinite_lives_toggle=FALSE;
    Cameras[0].ca_matrix=&camera_matrix;ResetCamera(Cameras);Cameras[0].ca_mode=CAMERA_MODE_FOLLOW_FROG;Cameras[0].ca_move_timer=0;
    Cameras[0].ca_current_source_ofs=general_header.gh_default_camera_source_ofs;Cameras[0].ca_current_target_ofs=general_header.gh_default_camera_target_ofs;
    Cameras[0].ca_current=*(MR_VEC*)matrix.t;UpdateCamera(Cameras);MRsrand(1);
    char side_path[4096];snprintf(side_path,sizeof(side_path),"%s.entities.csv",file);
    FILE *side=fopen(side_path,"w");if(!side)return 2;
    fputs("tick,index,root,program,cursor,loop_start,loop_end,timer,deviation,delta,destination,remaining,action,cel,rng,sounds,previous_flags,live_flags,moving_sound,red,green,blue,ambient_red,ambient_green,ambient_blue,requests,x,y,z,fly_mode,fly_timer,fly_checkpoint,covered,callback0,callback1,sound_id,sound_min,sound_max\n",side);
    fputs("tick,phase,x16,y16,z16,flags,mode,attached,count,direction,old_y,action,cel,rng,diver_y,diver_timer,diver_action,sounds,m00,m01,m02,m10,m11,m12,m20,m21,m22,scan,camera_x,camera_y,camera_z,source_x,source_y,source_z,target_x,target_y,target_z,controller_0,controller_1,controller_2,controller_3,camera_mod00,camera_mod01,camera_mod02,camera_mod10,camera_mod11,camera_mod12,camera_mod20,camera_mod21,camera_mod22",stdout);
    if(org_road)fputs(",vx16,vy16,vz16,death_equate,lives,first_killer,stored_action,stored_actual_cel,primitive_hit_indices,primitive_contacts",stdout);putchar('\n');
    for(int tick=0;tick<ticks;tick++) {
        org_primitive_contacts[0]=0;
        MR_ULONG key=0;int desired=commands[tick];
        if(desired>=0) for(int d=0;d<4;d++) if(Cameras[0].ca_frog_controller_directions[d]==desired)
            key=d==0?f->fr_control_method->fc_up_control:d==1?f->fr_control_method->fc_right_control:d==2?f->fr_control_method->fc_down_control:f->fr_control_method->fc_left_control;
        MRInput[0].in_pad_down=MRInput[0].in_pad_new=key;MRFrame_number=tick;
        UpdatePathRunners();
        for(int i=63;i>=0;i--) {
            LIVE_ENTITY *l=&org_lives[i];ENTITY *e=org_entities[i];
            MR_ULONG previous_flags=l->le_flags;
            request_capture=1;captured_requests[0]=0;
            if(e->en_path_runner) ENTSTRUpdateMovingMOF(l);
            if(i==55) ENTSTROrgUpdateBonusFly(l);
            if(org_types[i]==ENTITY_TYPE_CHECKPOINT) ENTSTRGenUpdateCheckPoint(l);
            if(i==53) {
                ENTSTROrgUpdateBabyFrog(l);
                if(org_baby.bf_mode!=ORG_BABY_FROG_WAIT_TO_SEARCH_AGAIN || org_baby.bf_search_count!=1 ||
                   org_baby.bf_entity || !(org_flips[i].ae_object->ob_flags&MR_OBJ_NO_DISPLAY)) return 3;
            }
            if(l->le_script) {Game_total_viewports=1;UpdateScriptInfo(l);Game_total_viewports=0;}
            SCRIPT_INFO *s=&org_scripts[i];int program,cursor,lp,ls,le;
            org_cursor(s->si_script,&program,&cursor);org_cursor(s->si_script_loop_start,&lp,&ls);org_cursor(s->si_script_loop_end,&lp,&le);
            fprintf(side,"%d,%d,%d,%d,%d,%d,%d,%u,%d,%d,%d,%d,%d,%d,%lu,%d,%lu,%lu,%d",
                tick,i,l->le_script?s->si_type:-1,program,cursor,ls,le,s->si_timer,s->si_dev_y,s->si_dev_dy,s->si_dev_dest_y,s->si_dev_dy_count,
                l->le_flags&LIVE_ENTITY_FLIPBOOK?org_flips[i].ae_action_number:-1,l->le_flags&LIVE_ENTITY_FLIPBOOK?org_flips[i].ae_cel_number:-1,
                (unsigned long)MRRnd_seed,sounds,(unsigned long)previous_flags,(unsigned long)l->le_flags,l->le_moving_sound!=NULL);
            MR_MESH_INST *mi=&org_mesh_instances[i];
            fprintf(side,",%d,%d,%d,%d,%d,%d,%s",mi->mi_colour_scale.r,mi->mi_colour_scale.g,mi->mi_colour_scale.b,
                mi->mi_custom_ambient.r,mi->mi_custom_ambient.g,mi->mi_custom_ambient.b,*captured_requests?captured_requests:"-");
            int covered=0;for(int cp=0;cp<5;cp++)if(Checkpoint_data[cp].cp_flags&GEN_CHECKPOINT_IS_COVERED)covered|=1<<cp;
            fprintf(side,",%ld,%ld,%ld,%d,%d,%d,%d",(long)l->le_lwtrans->t[0],(long)l->le_lwtrans->t[1],(long)l->le_lwtrans->t[2],org_fly.bf_mode,org_fly.bf_timer,org_fly.bf_checkpoint_id,covered);
            for(int cb=0;cb<2;cb++) {
                int id=-1;for(int j=0;j<9;j++)if(s->si_script_callback[cb]==script_callback_functions[j])id=j;
                fprintf(side,",%d:%ld:%d:%d",id,(long)s->si_script_callback_condition[cb],s->si_script_callback_type[cb],s->si_script_callback_called[cb]);
            }
            MRSND_MOVING_SOUND *sound=l->le_moving_sound;
            fprintf(side,",%d,%d,%d\n",sound?sound->ms_sound:-1,sound?sound->ms_min_radius:-1,sound?sound->ms_max_radius:-1);
            request_capture=0;
            l->le_flags &= ~LIVE_ENTITY_CLEAR_MASK;
        }
        for(int i=0;i<64;i++) if(!(Entity_library[org_types[i]].eb_flags & ENTITY_BOOK_STATIC)) {
            ENTITY *e=org_entities[i];if(e->en_prev) {e->en_prev->en_next=e->en_next;if(e->en_next)e->en_next->en_prev=e->en_prev;e->en_prev=e->en_next=NULL;}
            if(!(e->en_flags & ENTITY_HIDDEN)) EntityLinkToMapGroup(e,e->en_path_runner ? (MR_VEC*)&e->en_path_runner->pr_position : (MR_VEC*)org_lives[i].le_lwtrans->t);
        }
        ControlFrog(f);org_emit(tick,"control");MoveFrog(f);org_emit(tick,"move");
        CollideFrog(f);
        org_emit(tick,"collision");UpdateCamera(Cameras);org_emit(tick,"camera");
        UpdateFrogAnimationScripts();org_emit(tick,"scripts");
        MR_USHORT saved=env.ae_flags;env.ae_flags&=~MR_ANIM_ENV_UPDATE;MRAnimUpdateEnvironments();env.ae_flags=saved;org_store_frog_pose();org_emit(tick,"pose");
        if(Game_mode!=GAME_MODE_LEVEL_PLAY) break;
    }
    fclose(side);return 0;
}
