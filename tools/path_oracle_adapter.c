/* Transport for unchanged frozen PATH.C and MR_SPLIN.C objects. */
#include "PATH.H"
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Backend initialization builds the exact rcossin table used by arc sampling. */
extern void MRStub_GpuInit(void *renderer, int use_gl);

static int scan_long(MR_LONG *v) { return scanf("%ld", v) == 1; }
static int scan_vec(MR_SVEC *v) {
    MR_LONG x, y, z;
    if (!scan_long(&x) || !scan_long(&y) || !scan_long(&z)) return 0;
    v->vx = (MR_SHORT)x; v->vy = (MR_SHORT)y; v->vz = (MR_SHORT)z;
    return 1;
}
static void emit(int tick, const PATH_RUNNER *r) {
    printf("%d %ld %lu %ld %ld %ld %ld %ld %lu %ld %ld %ld %ld %ld %ld\n",
           tick, r->pr_segment_index, r->pr_segment_type,
           r->pr_segment_dist, r->pr_segment_length, r->pr_segment_param,
           r->pr_total_dist, r->pr_speed, r->pr_flags,
           r->pr_position.vx, r->pr_position.vy, r->pr_position.vz,
           r->pr_tangent.vx, r->pr_tangent.vy, r->pr_tangent.vz);
}
int main(void) {
    MRStub_GpuInit(NULL, 0);
    MR_LONG n, index, distance, speed, flags, ticks;
    if (!scan_long(&n) || !scan_long(&index) || !scan_long(&distance) ||
        !scan_long(&speed) || !scan_long(&flags) || !scan_long(&ticks)) return 2;
    if (n < 1 || n > 32 || index < 0 || index >= n || ticks < 0 || ticks > 256) return 2;
    PATH_SEGMENT **segments = calloc((size_t)n, sizeof(*segments));
    if (!segments) return 2;
    for (int i = 0; i < n; ++i) {
        MR_LONG kind, length;
        if (!scan_long(&kind) || !scan_long(&length) || kind < 0 || kind > 2 || length <= 0) return 2;
        /* Frozen code casts the address of ps_segment_ptr to the inline body. */
        segments[i] = calloc(1, offsetof(PATH_SEGMENT, ps_segment_ptr) + sizeof(PATH_SPLINE));
        if (!segments[i]) return 2;
        segments[i]->ps_type = (MR_ULONG)kind;
        void *body = &segments[i]->ps_segment_ptr;
        if (kind == PATH_SEGMENT_SPLINE) {
            PATH_SPLINE *s = body;
            s->ps_length = length;
            for (int row = 0; row < 4; ++row)
                for (int col = 0; col < 3; ++col)
                    if (!scan_long(&s->ps_matrix.sm_m[row][col])) return 2;
            for (int j = 0; j < 4; ++j) if (!scan_long(&s->ps_smooth_t[j])) return 2;
            for (int row = 0; row < 4; ++row)
                for (int col = 0; col < 3; ++col)
                    if (!scan_long(&s->ps_smooth_c[row][col])) return 2;
        } else if (kind == PATH_SEGMENT_ARC) {
            PATH_ARC *a = body;
            a->pa_length = length;
            if (!scan_vec(&a->pa_start) || !scan_vec(&a->pa_centre) || !scan_vec(&a->pa_normal) ||
                !scan_long(&a->pa_radius) || !scan_long(&a->pa_pitch)) return 2;
        } else {
            PATH_LINE *line = body;
            line->pl_length = length;
            if (!scan_vec(&line->pl_start) || !scan_vec(&line->pl_end)) return 2;
        }
    }
    PATH_RUNNER runner;
    memset(&runner, 0, sizeof(runner));
    runner.pr_segments = segments;
    runner.pr_numsegments = (MR_ULONG)n;
    runner.pr_segment_index = index;
    runner.pr_segment_dist = distance;
    runner.pr_speed = speed;
    runner.pr_flags = (MR_ULONG)flags;
    runner.pr_segment_type = segments[index]->ps_type;
    runner.pr_segment_ptr = &segments[index]->ps_segment_ptr;
    runner.pr_segment_length = *(MR_LONG *)runner.pr_segment_ptr;
    EvaluatePathRunnerPosition(&runner);
    EvaluatePathRunnerTotalDistance(&runner);
    emit(0, &runner);
    for (int tick = 0; tick < ticks; ++tick) {
        UpdatePathRunner(&runner);
        emit(tick + 1, &runner);
    }
    for (int i = 0; i < n; ++i) free(segments[i]);
    free(segments);
    return 0;
}
