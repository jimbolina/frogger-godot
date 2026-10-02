/* Thin transport only: all answers come from frozen GRID.C and math objects. */
#include "GRID.H"
#include <stdio.h>
#include <stdlib.h>
MR_SVEC *Map_vertices;
/* Unused trig dependency of the frozen math object; no queried function reads it. */
MR_COSSIN rcossin_tbl[4096];
int main(void) {
    int n, q, count, index, x, y, z;
    if (scanf("%ld %ld %ld %ld %d %d", &Grid_base_x, &Grid_base_z,
              &Grid_xnum, &Grid_znum, &n, &q) != 6) return 2;
    Grid_xlen=Grid_zlen=256; Grid_xshift=Grid_zshift=8;
    Map_vertices=calloc(n*4,sizeof(*Map_vertices));
    MAP_F4 *polys=calloc(n,sizeof(*polys));
    Grid_squares=calloc(n,sizeof(*Grid_squares));
    Grid_stacks=calloc(Grid_xnum*Grid_znum,sizeof(*Grid_stacks));
    for (int i=0;i<Grid_xnum*Grid_znum;i++) {
        if(scanf("%d %d",&count,&index)!=2) return 2;
        Grid_stacks[i].gs_numsquares=count; Grid_stacks[i].gs_index=index;
    }
    for (int i=0;i<n;i++) {
        Grid_squares[i].gs_map_poly=&polys[i];
        for(int j=0;j<4;j++) {
            if(scanf("%d %d %d",&x,&y,&z)!=3) return 2;
            Map_vertices[i*4+j].vx=x; Map_vertices[i*4+j].vy=y;
            Map_vertices[i*4+j].vz=z; polys[i].mp_vertices[j]=i*4+j;
        }
        MR_SVEC centre; MR_VEC normal;
        GetGridSquareCentre(&Grid_squares[i],&centre);
        GetGridSquareAverageNormal(&Grid_squares[i],&normal);
        printf("S %d %ld %d %d %d %ld %ld %ld\n",i,
            GetGridSquareHeight(&Grid_squares[i]),centre.vx,centre.vy,centre.vz,
            normal.vx,normal.vy,normal.vz);
    }
    for(int i=0;i<q;i++) {
        if(scanf("%d %d %d",&x,&y,&z)!=3) return 2;
        int gx=GET_GRID_X_FROM_WORLD_X(x),gz=GET_GRID_Z_FROM_WORLD_Z(z);
        if(gx<0 || gx>=Grid_xnum || gz<0 || gz>=Grid_znum) {
            /* Only source macro arithmetic is observed outside the board. */
            printf("W %d %d %d\n",i,gx,gz);continue;
        }
        GRID_SQUARE *square=NULL; GRID_INFO info;
        long height=GetHeightFromWorldXYZ(x,y,z,&square);
        int selected=square ? (int)(square-Grid_squares) : -1;
        if(Grid_stacks[gz*Grid_xnum+gx].gs_numsquares) {
            GetGridInfoFromWorldXZ(x,z,&info);
            printf("Q %d %ld %d %ld %ld %ld %ld %ld %ld %ld\n",i,height,selected,
                info.gi_y,info.gi_xslope.vx,info.gi_xslope.vy,info.gi_xslope.vz,
                info.gi_zslope.vx,info.gi_zslope.vy,info.gi_zslope.vz);
        } else printf("Q %d %ld %d\n",i,height,selected);
    }
    return 0;
}
