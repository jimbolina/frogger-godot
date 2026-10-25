/* Invented numeric frog part/root and static cuboid facts only. No retail data.
 * Linked unchanged frozen matrix operations and collision checker own outputs. */
#define main frozen_main_unused
#include "FROG.H"
#undef main
#include "gpu/mr_stub_gpu.h"
#undef main
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int number(FILE *input) {
    int value;
    if (fscanf(input, "%d", &value) != 1) exit(2);
    return value;
}
static void matrix(FILE *input, MR_MAT *output) {
    int r,c;
    memset(output,0,sizeof(*output));
    for(r=0;r<3;r++)for(c=0;c<3;c++)output->m[r][c]=(MR_SHORT)number(input);
    for(r=0;r<3;r++)output->t[r]=number(input);
}
int main(int argc,char **argv) {
    int count,index,r;
    FILE *input;
    if(argc!=2 || !(input=fopen(argv[1],"r")))return 2;
    count=number(input);
    puts("case,x,y,z,hit");
    for(index=0;index<count;index++) {
        MR_MAT root,part,owner,lw;
        MR_SVEC vertex,translation,world;
        MR_VEC rotated;
        MR_COLLPRIM primitive;
        matrix(input,&root);matrix(input,&part);
        vertex.vx=(MR_SHORT)number(input);vertex.vy=(MR_SHORT)number(input);vertex.vz=(MR_SHORT)number(input);
        matrix(input,&owner);
        memset(&primitive,0,sizeof(primitive));
        primitive.cp_type=MR_COLLPRIM_CUBOID;
        primitive.cp_offset.vx=(MR_SHORT)number(input);
        primitive.cp_offset.vy=(MR_SHORT)number(input);
        primitive.cp_offset.vz=(MR_SHORT)number(input);
        primitive.cp_xlen=(MR_USHORT)number(input);
        primitive.cp_ylen=(MR_USHORT)number(input);
        primitive.cp_zlen=(MR_USHORT)number(input);
        primitive.cp_flags=(MR_USHORT)number(input);
        primitive.cp_user=(MR_USHORT)number(input);
        memset(&lw,0,sizeof(lw));
        MRMulMatrixABC(&root,&part,&lw);
        translation.vx=(MR_SHORT)part.t[0];translation.vy=(MR_SHORT)part.t[1];translation.vz=(MR_SHORT)part.t[2];
        MRApplyMatrix(&root,&translation,&rotated);
        lw.t[0]=rotated.vx+root.t[0];lw.t[1]=rotated.vy+root.t[1];lw.t[2]=rotated.vz+root.t[2];
        MRApplyMatrixSVEC(&lw,&vertex,&world);
        world.vx+=lw.t[0];world.vy+=lw.t[1];world.vz+=lw.t[2];
        /* The checker caches by pointer, while stack addresses repeat here. */
        MRColl_lw_ptr=NULL;MRColl_matrix_ptr=NULL;
        r=MRCheckCollPrimWithWorldPoint(&primitive,&world,&owner,NULL);
        printf("%d,%d,%d,%d,%d\n",index,world.vx,world.vy,world.vz,r?1:0);
    }
    fclose(input);
    return 0;
}
