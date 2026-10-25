#include "PATH.H"
#include "ENTITY.H"
#include "CAMERA.H"
#include "formlib.H"
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern void MRStub_GpuInit(void *renderer, int use_gl);

typedef struct {
    int kind, index, unique_id, flags;
    ENTITY entity;
    LIVE_ENTITY live;
    PATH_RUNNER runner;
    PATH_SEGMENT **segments;
} TEST_ENTITY;

static int scan_long(MR_LONG *v) { return scanf("%ld", v) == 1; }
static int scan_int(int *v) { MR_LONG x; if (!scan_long(&x)) return 0; *v = (int)x; return 1; }
static int scan_vec(MR_SVEC *v) {
    MR_LONG x, y, z;
    if (!scan_long(&x) || !scan_long(&y) || !scan_long(&z)) return 0;
    v->vx = (MR_SHORT)x; v->vy = (MR_SHORT)y; v->vz = (MR_SHORT)z;
    return 1;
}

static int read_segment(PATH_SEGMENT **out) {
    MR_LONG kind, length;
    if (!scan_long(&kind) || !scan_long(&length) || kind < 0 || kind > 2 || length <= 0) return 0;
    PATH_SEGMENT *segment = calloc(1, offsetof(PATH_SEGMENT, ps_segment_ptr) + sizeof(PATH_SPLINE));
    if (!segment) return 0;
    segment->ps_type = (MR_ULONG)kind;
    void *body = &segment->ps_segment_ptr;
    if (kind == PATH_SEGMENT_SPLINE) {
        PATH_SPLINE *s = body;
        s->ps_length = length;
        for (int row = 0; row < 4; ++row)
            for (int col = 0; col < 3; ++col)
                if (!scan_long(&s->ps_matrix.sm_m[row][col])) return 0;
        for (int j = 0; j < 4; ++j) if (!scan_long(&s->ps_smooth_t[j])) return 0;
        for (int row = 0; row < 4; ++row)
            for (int col = 0; col < 3; ++col)
                if (!scan_long(&s->ps_smooth_c[row][col])) return 0;
    } else if (kind == PATH_SEGMENT_ARC) {
        PATH_ARC *a = body;
        a->pa_length = length;
        if (!scan_vec(&a->pa_start) || !scan_vec(&a->pa_centre) || !scan_vec(&a->pa_normal) ||
            !scan_long(&a->pa_radius) || !scan_long(&a->pa_pitch)) return 0;
    } else {
        PATH_LINE *line = body;
        line->pl_length = length;
        if (!scan_vec(&line->pl_start) || !scan_vec(&line->pl_end)) return 0;
    }
    *out = segment;
    return 1;
}

static void update_matrix(TEST_ENTITY *e) {
    ENTSTRUpdateMovingMOF(&e->live);
}

static void emit(int tick, const TEST_ENTITY *e) {
    const MR_MAT *m = &e->live.le_matrix;
    printf("%d %d %d", tick, e->index, e->unique_id);
    for (int row = 0; row < 3; ++row)
        for (int col = 0; col < 3; ++col)
            printf(" %d", m->m[row][col]);
    for (int axis = 0; axis < 3; ++axis) printf(" %ld", m->t[axis]);
    if (!e->kind) {
        for (int i = 0; i < 14; ++i) printf(" -1");
    } else {
        const PATH_RUNNER *r = &e->runner;
        printf(" %ld %lu %ld %ld %ld %ld %ld %lu %ld %ld %ld %ld %ld %ld",
            r->pr_segment_index, r->pr_segment_type, r->pr_segment_dist,
            r->pr_segment_length, r->pr_segment_param, r->pr_total_dist,
            r->pr_speed, r->pr_flags, r->pr_position.vx, r->pr_position.vy,
            r->pr_position.vz, r->pr_tangent.vx, r->pr_tangent.vy, r->pr_tangent.vz);
    }
    putchar('\n');
}

int main(void) {
    MRStub_GpuInit(NULL, 0);
    MR_MAT camera_matrix;
    MR_INIT_MAT(&camera_matrix);
    Cameras[0].ca_matrix = &camera_matrix;
    static FORM_BOOK form;
    form.fb_entity_type = 1;
    Form_library_ptrs[0] = &form;
    int ticks, count;
    while (scan_int(&ticks)) {
        if (!scan_int(&count) || count < 1 || count > 32 || ticks < 0 || ticks > 256) return 2;
        TEST_ENTITY *entities = calloc((size_t)count, sizeof(*entities));
        if (!entities) return 2;
        for (int i = 0; i < count; ++i) {
            TEST_ENTITY *e = &entities[i];
            if (!scan_int(&e->kind) || !scan_int(&e->index) || !scan_int(&e->unique_id) ||
                !scan_int(&e->flags) || e->kind < 0 || e->kind > 1) return 2;
            e->entity.en_flags = (MR_USHORT)e->flags;
            e->entity.en_form_book_id = 0;
            e->entity.en_path_runner = &e->runner;
            e->live.le_entity = &e->entity;
            e->live.le_lwtrans = &e->live.le_matrix;
            MR_INIT_MAT(&e->live.le_matrix);
            if (!e->kind) {
                for (int row = 0; row < 3; ++row)
                    for (int col = 0; col < 3; ++col) {
                        MR_LONG value;
                        if (!scan_long(&value)) return 2;
                        e->live.le_matrix.m[row][col] = (MR_SHORT)value;
                    }
                for (int axis = 0; axis < 3; ++axis)
                    if (!scan_long(&e->live.le_matrix.t[axis])) return 2;
            } else {
                MR_LONG n, index, distance, speed, flags;
                if (!scan_long(&n) || !scan_long(&index) || !scan_long(&distance) ||
                    !scan_long(&speed) || !scan_long(&flags) || n < 1 || n > 32 || index < 0 || index >= n) return 2;
                e->segments = calloc((size_t)n, sizeof(*e->segments));
                if (!e->segments) return 2;
                for (int j = 0; j < n; ++j) if (!read_segment(&e->segments[j])) return 2;
                PATH_RUNNER *r = &e->runner;
                r->pr_segments = e->segments;
                r->pr_numsegments = (MR_ULONG)n;
                r->pr_segment_index = index;
                r->pr_segment_dist = distance;
                r->pr_speed = speed;
                r->pr_flags = (MR_ULONG)flags;
                r->pr_segment_type = e->segments[index]->ps_type;
                r->pr_segment_ptr = &e->segments[index]->ps_segment_ptr;
                r->pr_segment_length = *(MR_LONG *)r->pr_segment_ptr;
                EvaluatePathRunnerPosition(r);
                EvaluatePathRunnerTotalDistance(r);
                update_matrix(e);
            }
        }
        for (int tick = 0; tick <= ticks; ++tick) {
            if (tick) {
                for (int i = count - 1; i >= 0; --i)
                    if (entities[i].kind)
                        UpdatePathRunner(&entities[i].runner);
                for (int i = count - 1; i >= 0; --i)
                    if (entities[i].kind)
                        update_matrix(&entities[i]);
            }
            for (int i = 0; i < count; ++i) emit(tick, &entities[i]);
        }
        for (int i = 0; i < count; ++i) {
            for (int j = 0; j < (int)entities[i].runner.pr_numsegments; ++j) free(entities[i].segments[j]);
            free(entities[i].segments);
        }
        free(entities);
    }
    return 0;
}
