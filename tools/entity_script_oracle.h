/* Invented asset-free programs, executed by unchanged frozen functions. */
static int entity_script_run(const char *file) {
    FILE *in=fopen(file,"r");if(!in)return 2;
    setup();animation_setup(0);Game_map_theme=THEME_ORG;
    void *raw=NULL,*pool=MRStub_PoolAlloc(1024*1024,&raw);
    MRInitMem(pool,1024*1024);MRStub_SetMemArena(pool,1024*1024);
    extern MRSND_MOVING_SOUND MRSND_moving_sound_root;
    extern MRSND_MOVING_SOUND *MRSND_moving_sound_root_ptr;
    extern MR_USHORT MRSND_viewports;
    MRSND_moving_sound_root_ptr=&MRSND_moving_sound_root;MRSND_viewports=0;
    int ticks=route_int(in),root_id=route_int(in),seed=route_int(in),program_count=route_int(in);
    if(ticks<1 || ticks>1000 || program_count<1 || program_count>16)return 2;
    for(int i=0;i<program_count;i++) {
        int id=route_int(in),length=route_int(in);
        if(id<1 || id>=256 || length<1 || length>256)return 2;
        org_programs[id]=calloc(length,sizeof(MR_LONG));org_program_lengths[id]=length;
        for(int j=0;j<length;j++)org_programs[id][j]=route_int(in);
        Scripts[id]=org_programs[id];
    }
    ENTITY *e=calloc(1,sizeof(ENTITY)+128);LIVE_ENTITY l={0};SCRIPT_INFO s={0};PATH_RUNNER path={0};
    l.le_entity=e;l.le_lwtrans=&l.le_matrix;l.le_script=&s;MR_INIT_MAT(l.le_lwtrans);e->en_path_runner=&path;
    e->en_form_book_id=route_int(in);
    int payload_offset=route_int(in),registers=route_int(in);
    for(int j=0;j<registers;j++)((MR_LONG*)((char*)(e+1)+payload_offset))[j]=route_int(in);
    int actions=route_int(in);MR_ANIM_ENV ae={0};MR_ANIM_ENV_FLIPBOOK flip_state={0};
    MR_MOF *mof=calloc(1,sizeof(MR_MOF)+sizeof(MR_PART));MR_PART *part=(MR_PART*)(mof+1);
    MR_PART_FLIPBOOK *flip=calloc(1,sizeof(MR_PART_FLIPBOOK)+actions*sizeof(MR_PART_FLIPBOOK_ACTION));
    part->mp_pad1=(MR_VOID*)flip;flip->mp_numactions=actions;
    for(int j=0;j<actions;j++)((MR_PART_FLIPBOOK_ACTION*)(flip+1))[j].mp_numpartcels=route_int(in);
    ae.ae_header=(MR_ANIM_HEADER*)mof;ae.ae_extra.ae_extra_env_flipbook=&flip_state;
    MR_OBJECT *object=calloc(1,sizeof(MR_OBJECT));object->ob_flags=MR_OBJ_STATIC;object->ob_frame=(MR_FRAME*)l.le_lwtrans;flip_state.ae_object=object;
    MR_MESH *mesh=calloc(1,sizeof(MR_MESH));MR_STATIC_MESH *stat=calloc(1,sizeof(MR_STATIC_MESH));
    object->ob_extra.ob_extra_mesh=mesh;mesh->me_extra.me_extra_static_mesh=stat;stat->sm_mof_ptr=mof;
    ae.ae_flags=(MR_ANIM_ENV_DEFAULT_FLAGS&~MR_ANIM_ENV_UPDATE)|MR_ANIM_ENV_IS_FLIPBOOK;ae.ae_update_period=1;
    ae.ae_next_node=root.ae_next_node;root.ae_next_node=&ae;
    l.le_api_item0=&ae;l.le_flags=LIVE_ENTITY_ANIMATED|LIVE_ENTITY_FLIPBOOK;MRAnimEnvFlipbookSetAction(&ae,0);
    MR_MESH_INST mi={0};MR_MESH_INST *mi_ptr=&mi;MR_ANIM_ENV_INST instance={0};
    instance.ae_mesh_insts=&mi_ptr;instance.ae_models=1;l.le_api_insts[0]=&instance;
    StartScript(&s,root_id,&l);s.si_timer=route_int(in);s.si_dev_y=route_int(in);MRRnd_seed=seed;
    puts("tick,program,cursor,loop_start,loop_end,timer,deviation,delta,destination,remaining,action,cel,rng,red,green,blue,ambient_red,ambient_green,ambient_blue,no_fade,drown,requests,callback0,callback1,sound_id,sound_min,sound_max");
    for(int tick=0;tick<ticks;tick++) {
        int hit=route_int(in),carry=route_int(in),hidden=route_int(in),outside=route_int(in),allocation=route_int(in),clear_owner=route_int(in);
        Game_over_no_new_sound=!allocation;if(clear_owner && l.le_moving_sound)KillMovingSound(&l);
        e->en_flags=hidden?ENTITY_NO_DISPLAY:0;
        l.le_flags=(l.le_flags&~LIVE_ENTITY_CLEAR_MASK)|(hit?LIVE_ENTITY_HIT_FROG_0:0)|(carry?LIVE_ENTITY_CARRIES_FROG_0:0);
        Fade_top_left_pos.vx=outside?1:-32767;Fade_top_left_pos.vz=32767;
        Fade_bottom_right_pos.vx=32767;Fade_bottom_right_pos.vz=-32767;
        Frogs[0].fr_flags=FROG_ACTIVE;Frogs[0].fr_mode=FROG_MODE_STATIONARY;Frogs[0].fr_lives=3;
        Frogs[0].fr_lwtrans->t[0]=Frogs[0].fr_lwtrans->t[1]=Frogs[0].fr_lwtrans->t[2]=0;
        l.le_matrix.t[0]=l.le_matrix.t[1]=l.le_matrix.t[2]=0;
        request_capture=1;captured_requests[0]=0;Game_total_viewports=1;UpdateScriptInfo(&l);Game_total_viewports=0;
        int program,cursor,lp,start,end;org_cursor(s.si_script,&program,&cursor);
        org_cursor(s.si_script_loop_start,&lp,&start);org_cursor(s.si_script_loop_end,&lp,&end);
        int drown=(Frogs[0].fr_flags&FROG_MUST_DIE)!=0;
        /* Particle creation belongs to the aggregate FrogKill reaction. */
        char *death=strstr(captured_requests,";death_pgen");if(death)*death=0;
        if(!strcmp(captured_requests,"death_pgen"))captured_requests[0]=0;
        MR_USHORT saved=env.ae_flags;env.ae_flags&=~MR_ANIM_ENV_UPDATE;MRAnimUpdateEnvironments();env.ae_flags=saved;
        printf("%d,%d,%d,%d,%d,%u,%d,%d,%d,%d,%d,%d,%lu,%d,%d,%d,%d,%d,%d,%d,%d,%s",
            tick,program,cursor,start,end,s.si_timer,s.si_dev_y,s.si_dev_dy,s.si_dev_dest_y,s.si_dev_dy_count,
            flip_state.ae_action_number,flip_state.ae_cel_number,(unsigned long)MRRnd_seed,
            mi.mi_colour_scale.r,mi.mi_colour_scale.g,mi.mi_colour_scale.b,mi.mi_custom_ambient.r,mi.mi_custom_ambient.g,mi.mi_custom_ambient.b,
            (l.le_flags&LIVE_ENTITY_NO_SCREEN_FADE)!=0,drown,*captured_requests?captured_requests:"-");
        for(int cb=0;cb<2;cb++) {
            int id=-1;for(int j=0;j<9;j++)if(s.si_script_callback[cb]==script_callback_functions[j])id=j;
            printf(",%d:%ld:%d:%d",id,(long)s.si_script_callback_condition[cb],s.si_script_callback_type[cb],s.si_script_callback_called[cb]);
        }
        MRSND_MOVING_SOUND *sound=l.le_moving_sound;
        printf(",%d,%d,%d\n",sound?sound->ms_sound:-1,sound?sound->ms_min_radius:-1,sound?sound->ms_max_radius:-1);
    }
    fclose(in);return 0;
}
