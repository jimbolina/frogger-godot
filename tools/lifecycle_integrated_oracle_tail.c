static MR_SVEC life_vertices[96*4];
static MAP_F4 life_polygons[96];
static GRID_SQUARE life_squares[96];
static GRID_STACK life_stacks[96];
static MAP_GROUP life_groups[1024];
static ENTITY life_roots[1024];

static void life_grid(void) {
    Grid_xnum=24; Grid_znum=4;
    Grid_xlen=Grid_zlen=256;
    Grid_base_x=Grid_base_z=-512;
    Grid_xshift=Grid_zshift=8;
    Grid_squares=life_squares;
    Grid_stacks=life_stacks;
    Map_vertices=life_vertices;
    Map_view_basepoint.vx=-8192;
    Map_view_basepoint.vz=-8192;
    Map_view_xnum=Map_view_znum=32;
    Map_view_xlen=Map_view_zlen=512;
    Map_groups=life_groups;
    memset(life_groups,0,sizeof(life_groups));
    memset(life_roots,0,sizeof(life_roots));
    for(int i=0;i<1024;i++) life_groups[i].mg_entity_root_ptr=&life_roots[i];
    for(int i=0;i<96;i++) {
        int x=-512+(i%24)*256,z=-512+(i/24)*256;
        int xs[4]={x,x+256,x,x+256},zs[4]={z+256,z+256,z,z};
        for(int j=0;j<4;j++) {
            life_vertices[i*4+j].vx=xs[j];
            life_vertices[i*4+j].vy=0;
            life_vertices[i*4+j].vz=zs[j];
            life_polygons[i].mp_vertices[j]=i*4+j;
        }
        life_squares[i].gs_map_poly=&life_polygons[i];
        life_squares[i].gs_flags=GRID_SQUARE_USABLE|GRID_SQUARE_SAFE;
        life_stacks[i].gs_numsquares=1;
        life_stacks[i].gs_index=i;
    }
    Frogs[0].fr_grid_square=&life_squares[25];
}

int main(void) {
    SetErrorMode(3);
    setvbuf(stdout,NULL,_IONBF,0);
    MRStub_GpuInit(NULL,0);
    setup(0);
    life_grid();
    animation_setup(0);
    Game_total_viewports=0;
    Frogs[0].fr_lives=3;
    Game_map=0;
    Cheat_collision_toggle=FALSE;
    Cheat_infinite_lives_toggle=FALSE;
    Fade_top_left_pos.vx=-32767;
    Fade_top_left_pos.vz=32767;
    Fade_bottom_right_pos.vx=32767;
    Fade_bottom_right_pos.vz=-32767;
    Theme_library[Game_map_theme].tb_death_height=30000;
    memset(&camera_matrix,0,sizeof(camera_matrix));
    Cameras[0].ca_matrix=&camera_matrix;
    ResetCamera(Cameras);
    Cameras[0].ca_mode=CAMERA_MODE_FOLLOW_FROG;
    Cameras[0].ca_move_timer=0;
    general_header.gh_default_camera_source_ofs.vx=0;
    general_header.gh_default_camera_source_ofs.vy=-512;
    general_header.gh_default_camera_source_ofs.vz=-512;
    general_header.gh_default_camera_target_ofs.vx=0;
    general_header.gh_default_camera_target_ofs.vy=0;
    general_header.gh_default_camera_target_ofs.vz=0;
    Cameras[0].ca_current_source_ofs=general_header.gh_default_camera_source_ofs;
    Cameras[0].ca_current_target_ofs=general_header.gh_default_camera_target_ofs;
    Cameras[0].ca_current.vx=matrix.t[0];
    Cameras[0].ca_current.vy=matrix.t[1];
    Cameras[0].ca_current.vz=matrix.t[2];
    UpdateCamera(Cameras);
    puts("tick,frog_x,frog_y,frog_z,source_x,source_y,source_z,r00,r01,r02,r10,r11,r12,r20,r21,r22");
    for(int tick=0;tick<336;tick++) {
        MR_ULONG east=Frogs[0].fr_control_method->fc_right_control;
        MR_ULONG west=Frogs[0].fr_control_method->fc_left_control;
        MR_ULONG key=0;
        if(tick>=16 && tick<144 && ((tick-16)%8)==0) key=east;
        if(tick>=176 && tick<304 && ((tick-176)%8)==0) key=west;
        MRInput[0].in_pad_down=key;
        MRInput[0].in_pad_new=key;
        MRFrame_number=tick;
        ControlFrog(Frogs);
        MoveFrog(Frogs);
        CollideFrog(Frogs);
        UpdateCamera(Cameras);
        UpdateFrogAnimationScripts();
        MR_USHORT saved=env.ae_flags;
        env.ae_flags&=~MR_ANIM_ENV_UPDATE;
        MRAnimUpdateEnvironments();
        env.ae_flags=saved;
        printf("%d,%ld,%ld,%ld,%ld,%ld,%ld,%d,%d,%d,%d,%d,%d,%d,%d,%d\n",
            tick,Frogs[0].fr_lwtrans->t[0],Frogs[0].fr_lwtrans->t[1],
            Frogs[0].fr_lwtrans->t[2],camera_matrix.t[0],camera_matrix.t[1],
            camera_matrix.t[2],camera_matrix.m[0][0],camera_matrix.m[0][1],
            camera_matrix.m[0][2],camera_matrix.m[1][0],camera_matrix.m[1][1],
            camera_matrix.m[1][2],camera_matrix.m[2][0],camera_matrix.m[2][1],
            camera_matrix.m[2][2]);
    }
    return 0;
}
