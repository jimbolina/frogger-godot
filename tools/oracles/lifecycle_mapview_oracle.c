#include "MR_ALL.H"
#include "gamesys.H"
#include "MAPVIEW.H"
#include "mapdisp.H"
#include "CAMERA.H"
#include "gpu/mr_stub_gpu.h"
#undef main
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

__declspec(dllimport) unsigned long __stdcall SetErrorMode(unsigned long);
extern MR_LONG Map_view_region_minx[];
extern MR_LONG Map_view_region_maxx[];

int main(int argc, char **argv) {
    static MR_VIEWPORT viewport;
    static MR_MAT camera;
    long a[18];
    if (argc == 10 && strcmp(argv[1], "--line") == 0) {
        long line[8];
        for (int i = 0; i < 8; ++i) {
            char *end = NULL;
            line[i] = strtol(argv[i + 2], &end, 10);
            if (!end || *end) return 2;
        }
        Map_view_xnum = line[0]; Map_view_znum = line[1];
        Map_view_xlen = line[2]; Map_view_zlen = line[3];
        if (Map_view_xnum < 1 || Map_view_znum < 1 || Map_view_znum > 64 || Map_view_xlen < 1 || Map_view_zlen < 1) return 2;
        for (int z = 0; z < Map_view_znum; ++z) {
            Map_view_region_minx[z] = 0x7fffffff;
            Map_view_region_maxx[z] = -0x7fffffff;
        }
        MapViewDrawLine(line[4],line[5],line[6],line[7]);
        for (int z = 0; z < Map_view_znum; ++z) {
            if (Map_view_region_minx[z] == 0x7fffffff) continue;
            printf("%d:%ld:%ld\n",z,Map_view_region_minx[z],Map_view_region_maxx[z]);
        }
        return 0;
    }
    if (argc != 19) {
        fprintf(stderr, "usage: oracle base_x base_z x_count z_count x_size z_size source_xyz matrix9\n");
        return 2;
    }
    for (int i = 0; i < 18; ++i) {
        char *end = NULL;
        a[i] = strtol(argv[i + 1], &end, 10);
        if (!end || *end) return 2;
    }
    if (a[2] < 1 || a[2] > 64 || a[3] < 1 || a[3] > 64 || a[4] < 1 || a[5] < 1) return 2;
    SetErrorMode(3);
    MRStub_GpuInit(NULL, 0);
    Map_view_basepoint.vx = (short)a[0];
    Map_view_basepoint.vz = (short)a[1];
    Map_view_xnum = a[2]; Map_view_znum = a[3];
    Map_view_xlen = a[4]; Map_view_zlen = a[5];
    for (int i = 0; i < 3; ++i) camera.t[i] = a[6 + i];
    for (int i = 0; i < 9; ++i) camera.m[i / 3][i % 3] = (short)a[9 + i];
    Cameras[0].ca_matrix = &camera;
    Game_viewports[0] = &viewport;
    Game_total_viewports = 1;
    Game_perspective = 256;
    InitialiseMapView();
    CreateMapViewList(0);
    for (MR_SHORT *p = Map_group_view_list[0]; *p >= 0; ++p) {
        if (p != Map_group_view_list[0]) putchar(',');
        printf("%d", (int)*p);
    }
    putchar('\n');
    return 0;
}
