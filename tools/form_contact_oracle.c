/* Transport for the unchanged frozen CollideFrog geometry gate. */
#define main frozen_main_unused
#include "COLLIDE.H"
#include "ENTITY.H"
#include "FORM.H"
#include "GRID.H"
#include "MAPLOAD.H"
#include "MAPVIEW.H"
#include "LIBRARY.H"
#include "MAIN.H"
#include "GAMESYS.H"
#undef main
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern void MRStub_GpuInit(void *renderer, int use_gl);

static int read_long(MR_LONG *out) { return scanf("%ld", out) == 1; }
static int read_int(int *out) {
    MR_LONG value;
    if (!read_long(&value)) return 0;
    *out = (int)value;
    return 1;
}

int main(void) {
    MRStub_GpuInit(NULL, 0);
    int count;
    if (!read_int(&count) || count < 0 || count > 4096) return 2;
    for (int case_index = 0; case_index < count; ++case_index) {
        MR_LONG matrix[12], frog_xyz[3];
        MR_LONG xofs, zofs, xnum, znum, height, max_y, radius2;
        int entity_flags, live_enabled, current_entity, forbidden_entity, form_data_count;
        for (int i = 0; i < 12; ++i) if (!read_long(&matrix[i])) return 2;
        for (int i = 0; i < 3; ++i) if (!read_long(&frog_xyz[i])) return 2;
        if (!read_long(&xofs) || !read_long(&zofs) || !read_long(&xnum) ||
            !read_long(&znum) || !read_long(&height) || !read_long(&max_y) ||
            !read_long(&radius2) || !read_int(&entity_flags) ||
            !read_int(&live_enabled) || !read_int(&current_entity) ||
            !read_int(&forbidden_entity) || !read_int(&form_data_count)) return 2;
        if (xnum < 1 || xnum > 16 || znum < 1 || znum > 16 ||
            frog_xyz[0] < -30000 || frog_xyz[0] > 30000 ||
            frog_xyz[1] < -30000 || frog_xyz[1] > 30000 ||
            frog_xyz[2] < -30000 || frog_xyz[2] > 30000 ||
            (form_data_count != 0 && form_data_count != 1)) return 2;

        /* FORM's trailing word is treated as a pointer slot by resolved C. */
        FORM *form = calloc(1, offsetof(FORM, fo_formdata_ptrs) + sizeof(FORM_DATA *));
        MR_USHORT *grid_flags = calloc((size_t)(xnum * znum), sizeof(*grid_flags));
        if (!form || !grid_flags) return 2;
        FORM_DATA data = {0};
        data.fd_height_type = FORM_DATA_HEIGHT_TYPE_GRID;
        data.fd_height = (MR_SHORT)height;
        data.fd_grid_squares = grid_flags;
        for (int i = 0; i < xnum * znum; ++i)
            grid_flags[i] = GRID_SQUARE_USABLE | GRID_SQUARE_SLIPPY;
        FORM_DATA *data_ptr = &data;
        memcpy(&form->fo_formdata_ptrs, &data_ptr, sizeof(data_ptr));
        form->fo_numformdatas = (MR_USHORT)form_data_count;
        form->fo_max_y = (MR_SHORT)max_y;
        form->fo_xnum = (MR_SHORT)xnum;
        form->fo_znum = (MR_SHORT)znum;
        form->fo_xofs = (MR_SHORT)xofs;
        form->fo_zofs = (MR_SHORT)zofs;

        FORM_BOOK book = {0};
        book.fb_radius2 = radius2;
        Form_library_ptrs[0] = &book;
        FORM *form_ptrs[1] = {form};
        Map_form_ptrs = form_ptrs;

        MR_MAT entity_matrix = {0}, frog_matrix = {0};
        for (int row = 0; row < 3; ++row)
            for (int col = 0; col < 3; ++col)
                entity_matrix.m[row][col] = (MR_SHORT)matrix[row * 3 + col];
        for (int axis = 0; axis < 3; ++axis) {
            entity_matrix.t[axis] = matrix[9 + axis];
            frog_matrix.t[axis] = frog_xyz[axis];
        }
        LIVE_ENTITY live = {0};
        ENTITY entity = {0}, root = {0};
        entity.en_form_grid_id = 0;
        entity.en_form_book_id = 0;
        entity.en_flags = (MR_USHORT)entity_flags;
        entity.en_live_entity = live_enabled ? &live : NULL;
        entity.en_next = NULL;
        live.le_entity = &entity;
        live.le_lwtrans = &entity_matrix;
        live.le_api_item0 = NULL;
        root.en_next = &entity;

        MAP_GROUP group = {0};
        group.mg_entity_root_ptr = &root;
        Map_groups = &group;
        Map_view_basepoint.vx = -32768;
        Map_view_basepoint.vz = -32768;
        Map_view_xlen = 100000;
        Map_view_zlen = 100000;
        Map_view_xnum = Map_view_znum = 1;
        Fade_top_left_pos.vx = -32767;
        Fade_top_left_pos.vz = 32767;
        Fade_bottom_right_pos.vx = 32767;
        Fade_bottom_right_pos.vz = -32767;
        Game_map_theme = 0;
        Theme_library[0].tb_death_height = 32767;
        Game_total_players = 0;
        Cheat_collision_toggle = FALSE;

        FROG frog = {0};
        frog.fr_frog_id = 0;
        frog.fr_mode = FROG_MODE_STATIONARY;
        frog.fr_lwtrans = &frog_matrix;
        frog.fr_api_item = &frog_matrix; /* Non-null for the collprim assertion. */
        frog.fr_entity = current_entity ? &entity : NULL;
        frog.fr_forbid_entity = forbidden_entity ? &entity : NULL;
        MR_SVEC displacement = {0};
        displacement.vx = (MR_SHORT)(frog_xyz[0] - matrix[9]);
        displacement.vy = (MR_SHORT)(frog_xyz[1] - matrix[10]);
        displacement.vz = (MR_SHORT)(frog_xyz[2] - matrix[11]);
        MR_LONG distance_squared = MR_SVEC_MOD_SQR(&displacement);
        MR_MAT transposed = {0};
        MR_VEC local = {0};
        MRTransposeMatrix(&entity_matrix, &transposed);
        MRApplyMatrix(&transposed, &displacement, &local);
        CollideFrog(&frog);
        printf("%d %ld %ld %ld %ld\n", !!(live.le_flags & LIVE_ENTITY_HIT_FROG_0),
               distance_squared, local.vx, local.vy, local.vz);
        free(grid_flags);
        free(form);
    }
    return 0;
}
