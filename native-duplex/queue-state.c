// SPDX-License-Identifier: MIT
// Numeric IPP state: macOS lpstat remains localized even with LC_ALL=C.
#include <cups/cups.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static int jobs(const char *queue) {
    cups_job_t *list=NULL;
    int n=cupsGetJobs(&list,queue,0,CUPS_WHICHJOBS_ACTIVE);
    if(n>=0) cupsFreeJobs(n,list);
    else fprintf(stderr,"Cannot query jobs: %s\n",cupsLastErrorString());
    return n;
}
int main(int argc,char **argv) {
    if(argc!=2 && argc!=3) return 1;
    const char *queue=argv[argc-1];
    if(argc==3 && !strcmp(argv[1],"--job-count")) {
        int count=jobs(queue); if(count<0) return 1; printf("%d\n",count); return 0;
    }
    cups_dest_t *dest=cupsGetNamedDest(CUPS_HTTP_DEFAULT,queue,NULL);
    if(!dest) { fprintf(stderr,"Cannot query queue: %s\n",cupsLastErrorString()); return 1; }
    const char *value=cupsGetOption("printer-state",dest->num_options,dest->options);
    int state=value?atoi(value):0;
    cupsFreeDests(1,dest);
    if(argc==3) {
        if(strcmp(argv[1],"--state")) return 1;
        printf("%d\n",state); return state?0:1;
    }
    if(state==IPP_PSTATE_IDLE || state==IPP_PSTATE_STOPPED) return 0;
    if(state==IPP_PSTATE_PROCESSING && jobs(queue)==0) {
        fputs("Queue has stale processing state but no active jobs; safe to refresh during update.\n",stderr);
        return 0;
    }
    fprintf(stderr,"Queue is processing or its state is unavailable (IPP state %d).\n",state);
    return 1;
}
