#include "map_reader.h"
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

static uint32_t u32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1]<<8) | ((uint32_t)p[2]<<16) | ((uint32_t)p[3]<<24);
}

int main(void) {
    size_t length=0,capacity=65536,n;
    uint8_t *data=malloc(capacity);
    MapCensusInfo c;
    MapRgbCensus rgb;
    uint32_t square_count=0;
    uint16_t counts[9];
#ifdef _WIN32
    _setmode(_fileno(stdin),_O_BINARY);
#endif
    if (!data) return 2;
    while ((n=fread(data+length,1,capacity-length,stdin))>0) {
        length+=n;
        if (length==capacity) {
            uint8_t *grown=realloc(data,capacity*2);
            if (!grown) {free(data);return 2;}
            data=grown;capacity*=2;
        }
    }
    if (ferror(stdin) || map_read_census_info(data,length,&c)!=0 || !c.ok ||
        map_read_rgb_component_census(data,length,&c,&rgb)!=0 ||
        map_grid_count_squares(data,length,&c.grid,c.graphical.gh_grid_header_ofs,&square_count)!=0) {
        free(data);return 1;
    }
    printf("H\t%u\t%u\t%u\t%u\t%u\t%u\t%u\t%u\t%d\n",
           c.header.mh_file_length,c.vertex.vh_numverts,c.entity.eh_numentities,
           c.form.fh_numforms,c.path.ph_numpaths,c.grid.gh_xnum,c.grid.gh_znum,
           square_count,map_read_max_local_texture_index(data,length,&c));
    printf("G\t%d\t%d\t%d\t%u\t%u\t%u\t%u\n",c.group.gh_basepoint_x,
           c.group.gh_basepoint_y,c.group.gh_basepoint_z,c.group.gh_xnum,c.group.gh_znum,
           c.group.gh_xlen,c.group.gh_zlen);
    printf("N\t%u\t%u\t%u\t%u",c.general.gh_start_x,c.general.gh_start_z,c.general.gh_rotation,c.general.gh_theme);
    for (int i=0;i<5;i++) printf("\t%u",c.general.gh_trigger_timers[i]);
    printf("\t%u\n",c.general.gh_perspective);
    counts[0]=c.poly.ph_num_f3;counts[1]=c.poly.ph_num_f4;counts[2]=c.poly.ph_num_ft3;
    counts[3]=c.poly.ph_num_ft4;counts[4]=c.poly.ph_num_g3;counts[5]=c.poly.ph_num_g4;
    counts[6]=c.poly.ph_num_gt3;counts[7]=c.poly.ph_num_gt4;counts[8]=c.poly.ph_num_g2;
    printf("P");for(int i=0;i<9;i++)printf("\t%u",counts[i]);printf("\n");
    printf("R\t%d\t%u\t%u\t%u\n",rgb.max_component,rgb.count_gt_128,rgb.count_eq_128,rgb.components_scanned);
    uint32_t ao=c.graphical.gh_anim_header_ofs;
    if ((uint64_t)ao+12>length) {free(data);return 1;}
    uint32_t ac=u32(data+ao+4);
    printf("C\t%u\n",ac);
    for(uint32_t i=0;i<ac;i++) {
        MapAnimRaw a;
        if(map_read_anim_raw(data,length,&c,ac,i,&a)!=0){free(data);return 1;}
        printf("A\t%u\t%u\t%u\t%u\t%u\t%u\n",i,a.ma_flags,a.ma_numcels,
               a.ma_cel_list_ofs,a.ma_numpolys,a.ma_map_uv_info_ofs);
        if(a.ma_flags&2) {
            printf("T\t%u",i);
            for(uint16_t k=0;k<a.ma_numcels;k++) {
                uint16_t cel;
                if(map_read_anim_raw_cel(data,length,a.ma_cel_list_ofs,k,&cel)!=0){free(data);return 1;}
                printf("\t%u",cel);
            }
            printf("\n");
        }
    }
    for(uint32_t i=0;i<c.entity.eh_numentities;i++) {
        MapEntityRaw e;
        if(map_read_entity(data,length,&c.entity,c.header.mh_entity_header_ofs,i,&e)!=0){free(data);return 1;}
        printf("E\t%u\t%u\t%u\t%u\t%u\n",i,e.en_form_grid_id,e.en_unique_id,e.en_form_book_id,e.en_flags);
    }
    free(data);return 0;
}
