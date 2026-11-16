#include <cups/raster.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
int main(int argc,char **argv) {
    if(argc==4&&!strcmp(argv[1],"--generate")) {
        int count=atoi(argv[2]), depth=atoi(argv[3]);
        cups_raster_t *r=cupsRasterOpen(1,CUPS_RASTER_WRITE);
        for(int n=1;n<=count;n++) {
            cups_page_header2_t h={0};
            h.cupsWidth=depth==1?9:3; h.cupsHeight=2;
            h.cupsBitsPerColor=depth; h.cupsBitsPerPixel=depth;
            h.cupsBytesPerLine=depth==1?2:4;
            h.cupsColorSpace=depth==1?CUPS_CSPACE_K:CUPS_CSPACE_W;
            h.cupsColorOrder=CUPS_ORDER_CHUNKED; h.NumCopies=1;
            h.HWResolution[0]=h.HWResolution[1]=600;
            h.PageSize[0]=h.PageSize[1]=1;
            cupsRasterWriteHeader2(r,&h);
            unsigned char a[]={n,0x80,0x33,0xff},b[]={0x80+n,0,0x55,0xff};
            cupsRasterWritePixels(r,a,h.cupsBytesPerLine); cupsRasterWritePixels(r,b,h.cupsBytesPerLine);
        }
        cupsRasterClose(r); return 0;
    }
    // Stand-in for rasterToHPZJS: emit a readable record, never contact a printer.
    FILE *file=argc==7?fopen(argv[6],"rb"):stdin;
    cups_raster_t *r=cupsRasterOpen(fileno(file),CUPS_RASTER_READ);
    cups_page_header2_t h;
    printf("PASS copies=%s\n",argv[4]);
    while(cupsRasterReadHeader2(r,&h)) {
        printf("PAGE %u %u %u %u ",h.cupsWidth,h.cupsHeight,h.NumCopies,h.Duplex);
        unsigned char *line=malloc(h.cupsBytesPerLine);
        for(unsigned y=0;y<h.cupsHeight;y++) {
            if(cupsRasterReadPixels(r,line,h.cupsBytesPerLine)!=h.cupsBytesPerLine) return 2;
            for(unsigned x=0;x<h.cupsBytesPerLine;x++) printf("%02x",line[x]);
        }
        puts(""); free(line);
    }
    cupsRasterClose(r); fflush(stdout); return 0;
}
