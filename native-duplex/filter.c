// SPDX-License-Identifier: MIT
// CUPS raster wrapper. Both vendor invocations share ONE backend/job.
#include <cups/cups.h>
#include <cups/raster.h>
#include <cups/sidechannel.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <pwd.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <errno.h>
#ifndef HP_FILTER
#define HP_FILTER "/Library/Printers/hp/laserjet/hplaserjetzjs.bundle/Contents/MacOS/rasterToHPZJS"
#endif
#ifndef IPC_BASE
#define IPC_BASE "/Users/Shared/hp1020-duplex-"
#endif
#ifndef WAIT_SECONDS
#define WAIT_SECONDS 1800
#endif
#ifndef VENDOR_TIMEOUT_SECONDS
#define VENDOR_TIMEOUT_SECONDS 1800
#endif
#ifndef CANCEL_GRACE_SECONDS
#define CANCEL_GRACE_SECONDS 2
#endif
#define MAX_PAGES 5000
#define MAX_BYTES (4ULL*1024*1024*1024)
static volatile sig_atomic_t stopped, child_pid;
static int ipc = -1;
static char request[80], reply[80];
static void stop(int sig) { (void)sig; stopped = 1; if (child_pid > 0) kill(-child_pid, SIGTERM); }
static void cleanup(void) {
    if (ipc >= 0) { if (*request) unlinkat(ipc, request, 0); if (*reply) unlinkat(ipc, reply, 0); close(ipc); }
}
static void fail(const char *message) { fprintf(stderr,"ERROR: HP1020 Duplex: %s\n",message); exit(stopped ? 0 : 1); }
static FILE *temporary(void) {
    char path[1024];
    const char *base = getenv("TMPDIR"); if (!base) base = "/private/tmp";
    if (snprintf(path,sizeof(path),"%s/hp1020-XXXXXX",base) >= (int)sizeof(path)) fail("Temporary path too long");
    int fd = mkstemp(path); if (fd < 0) fail("Cannot create private spool file");
    unlink(path); fcntl(fd,F_SETFD,FD_CLOEXEC);
    FILE *file = fdopen(fd,"w+b"); if (!file) { close(fd); fail("Cannot open spool"); } return file;
}
static int number(const char *s, int max) {
    if (!s || !*s) return -1;
    long n=0; for (; *s; ++s) { if (*s<'0'||*s>'9') return -1; n=n*10+*s-'0'; if(n>max) return -1; }
    return n>0 ? (int)n : -1;
}
static void connect_agent(const char *user) {
    struct passwd *pw=getpwnam(user); if (!pw || pw->pw_uid == 0) fail("A local logged-in user is required");
    char path[256]; snprintf(path,sizeof(path),"%s%u",IPC_BASE,pw->pw_uid);
    ipc=open(path,O_SEARCH|O_NOFOLLOW|O_CLOEXEC);
    struct stat st;
    if(ipc<0) { fprintf(stderr,"ERROR: HP1020 Duplex: Cannot open confirmation directory: %s\n",strerror(errno)); exit(1); }
    if(fstat(ipc,&st) || st.st_uid!=pw->pw_uid || (st.st_mode&07777)!=01733) fail("Invalid confirmation directory owner or mode");
    int fd=openat(ipc,"heartbeat",O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC);
    if(fd<0 || fstat(fd,&st) || !S_ISREG(st.st_mode) || st.st_uid!=pw->pw_uid || time(NULL)-st.st_mtime>15 || st.st_mtime>time(NULL)+5) fail("Confirmation agent is not running; no pages were printed");
    close(fd);
}
static int confirmation(const char *user, int job, int pages, int copy, int copies) {
    uid_t uid=getpwnam(user)->pw_uid;
    unsigned char random[16]; arc4random_buf(random,sizeof(random));
    char token[33]; for(int i=0;i<16;i++) snprintf(token+2*i,3,"%02x",random[i]);
    snprintf(request,sizeof(request),"%s.request",token); snprintf(reply,sizeof(reply),"%s.reply",token);
    // Publish only complete data, via atomic rename from a non-request filename.
    char pending[80]; snprintf(pending,sizeof(pending),"%s.pending",token);
    int fd=openat(ipc,pending,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0644);
    if(fd<0) fail("Cannot create reload request");
    char message[128]; int len=snprintf(message,sizeof(message),"%d\t%d\t%d\t%d\n",job,pages,copy,copies);
    if(fchmod(fd,0644) || write(fd,message,len)!=len) { close(fd); unlinkat(ipc,pending,0); fail("Cannot write reload request"); }
    close(fd);
    if(renameat(ipc,pending,ipc,request)) { unlinkat(ipc,pending,0); fail("Cannot publish reload request"); }
    fprintf(stderr,"INFO: Waiting for paper reload confirmation (copy %d/%d).\n",copy,copies);
    struct timespec start, now; clock_gettime(CLOCK_MONOTONIC,&start);
    while(!stopped) {
        fd=openat(ipc,reply,O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC);
        if(fd>=0) {
            struct stat st; char response[32]={0};
            int valid=!fstat(fd,&st) && S_ISREG(st.st_mode) && st.st_nlink==1 && st.st_uid==uid && st.st_size<32;
            ssize_t n= valid ? read(fd,response,sizeof(response)-1) : -1; close(fd);
            if(n==9 && !memcmp(response,"continue\n",9)) { unlinkat(ipc,request,0); unlinkat(ipc,reply,0); *request=*reply=0; return 1; }
            if(n==7 && !memcmp(response,"cancel\n",7)) return 0;
            fail("Invalid confirmation response");
        }
        if(errno!=ENOENT) fail("Cannot read confirmation response");
        clock_gettime(CLOCK_MONOTONIC,&now); if(now.tv_sec-start.tv_sec>=WAIT_SECONDS) fail("Paper reload confirmation timed out");
        usleep(200000);
    }
    return 0;
}
typedef struct { cups_page_header2_t header; off_t offset; } Page;
static Page pages[MAX_PAGES];
static unsigned char reverse_byte(unsigned char b) { b=(b>>4)|(b<<4); b=((b&0xcc)>>2)|((b&0x33)<<2); return ((b&0xaa)>>1)|((b&0x55)<<1); }
static FILE *make_pass(FILE *spool, int count, int back, int rotate) {
    FILE *out=temporary(); cups_raster_t *r=cupsRasterOpen(fileno(out),CUPS_RASTER_WRITE);
    if(!r) fail("Cannot open raster writer");
    int sheets=(count+1)/2;
    for(int pos=0;pos<sheets && !stopped;pos++) {
        int index=back ? 2*(sheets-1-pos)+1 : 2*pos;
        int blank=index>=count; Page *p=&pages[blank ? count-1 : index];
        cups_page_header2_t h=p->header; h.Duplex=0; h.Tumble=0; h.NumCopies=1; h.Collate=0;
        if(!cupsRasterWriteHeader2(r,&h)) fail("Cannot write raster header");
        unsigned char *line=malloc(h.cupsBytesPerLine), *flipped=malloc(h.cupsBytesPerLine);
        if(!line||!flipped) fail("Out of memory");
        int white=h.cupsColorSpace==CUPS_CSPACE_K ? 0 : 255;
        for(unsigned y=0;y<h.cupsHeight && !stopped;y++) {
            if(blank) memset(line,white,h.cupsBytesPerLine);
            else {
                unsigned row=(back&&rotate)?h.cupsHeight-1-y:y;
                if(fseeko(spool,p->offset+(off_t)row*h.cupsBytesPerLine,SEEK_SET) || fread(line,1,h.cupsBytesPerLine,spool)!=h.cupsBytesPerLine) fail("Cannot read raster spool");
                if(back&&rotate) {
                    memset(flipped,white,h.cupsBytesPerLine);
                    if(h.cupsBitsPerPixel==8) for(unsigned x=0;x<h.cupsWidth;x++) flipped[x]=line[h.cupsWidth-1-x];
                    else if(h.cupsWidth%8==0) for(unsigned x=0;x<h.cupsWidth/8;x++) flipped[x]=reverse_byte(line[h.cupsWidth/8-1-x]);
                    else for(unsigned x=0;x<h.cupsWidth;x++) {
                        unsigned src=h.cupsWidth-1-x, mask=0x80>>(x%8);
                        if(line[src/8] & (0x80>>(src%8))) flipped[x/8]|=mask; else flipped[x/8]&=~mask;
                    }
                    memcpy(line,flipped,h.cupsBytesPerLine);
                }
            }
            if(cupsRasterWritePixels(r,line,h.cupsBytesPerLine)!=h.cupsBytesPerLine) fail("Cannot write raster pixels");
        }
        free(line); free(flipped);
    }
    cupsRasterClose(r); if(fflush(out)||ferror(out)) fail("Cannot flush raster spool (disk full)"); rewind(out); return out;
}
static void vendor(FILE *raster, char **argv) {
    rewind(raster);
    pid_t pid=fork(); if(pid<0) fail("Cannot start HP converter");
    if(pid==0) {
        if(setpgid(0,0)) _exit(1);
        signal(SIGTERM,SIG_DFL); signal(SIGINT,SIG_DFL);
        if(dup2(fileno(raster),STDIN_FILENO)<0) _exit(1);
        char *args[]={HP_FILTER,argv[1],argv[2],argv[3],"1",argv[5],NULL};
        execv(HP_FILTER,args); _exit(127);
    }
    // Isolate the converter and any descendants so cancellation reaches all of them.
    if(setpgid(pid,pid) && errno!=EACCES && errno!=ESRCH) { kill(pid,SIGKILL); waitpid(pid,NULL,0); fail("Cannot isolate HP converter"); }
    child_pid=pid;
    struct timespec started, now, terminating={0}; clock_gettime(CLOCK_MONOTONIC,&started);
    int status=0, timedout=0, sent_term=0, sent_kill=0;
    for(;;) {
        pid_t result=waitpid(pid,&status,WNOHANG);
        if(result==pid) break;
        if(result<0 && errno!=EINTR) { kill(-pid,SIGKILL); fail("Cannot wait for HP converter"); }
        clock_gettime(CLOCK_MONOTONIC,&now);
        if(!sent_term && (stopped || now.tv_sec-started.tv_sec>=VENDOR_TIMEOUT_SECONDS)) {
            timedout=!stopped; sent_term=1; terminating=now;
            kill(-pid,SIGTERM);
            fprintf(stderr,"INFO: Stopping HP converter (%s).\n",timedout?"timeout":"job cancelled");
        }
        if(sent_term && !sent_kill && now.tv_sec-terminating.tv_sec>=CANCEL_GRACE_SECONDS) {
            sent_kill=1; kill(-pid,SIGKILL);
        }
        usleep(100000);
    }
    // Do not leave descendants behind if the converter exits before its children.
    kill(-pid,SIGKILL);
    child_pid=0;
    if(stopped) return;
    if(timedout) fail("HP converter timed out; remaining pages were not printed");
    if(!WIFEXITED(status)||WEXITSTATUS(status)!=0) fail("HP converter failed; cancel the job and check the printer before retrying");
}
int main(int argc, char **argv) {
    if(argc==3 && !strcmp(argv[1],"--check-agent")) {
        atexit(cleanup); connect_agent(argv[2]);
        puts("PASS: confirmation agent directory and heartbeat are accessible"); return 0;
    }
    if(argc!=6 && argc!=7) { fprintf(stderr,"Usage: filter job user title copies options [raster]\n"); return 1; }
    signal(SIGPIPE,SIG_IGN);
    struct sigaction sa={0}; sa.sa_handler=stop; sigaction(SIGTERM,&sa,NULL); sigaction(SIGINT,&sa,NULL);
    atexit(cleanup);
    cups_option_t *options=NULL; int n=cupsParseOptions(argv[5],0,&options);
    const char *mode=cupsGetOption("HPManualDuplex",n,options);
    if(!mode) mode="LongEdge"; // Also apply the default to command-line jobs without an explicit option.
    if(!strcmp(mode,"Off")) { argv[0]=(char *)HP_FILTER; execv(HP_FILTER,argv); fail("Cannot execute original HP converter"); }
    if(strcmp(mode,"LongEdge") && strcmp(mode,"ShortEdge")) fail("Unknown manual duplex option");
    int rotate=!strcmp(mode,"ShortEdge"), copies=number(argv[4],100), job=number(argv[1],2147483647);
    if(copies<0||job<0) fail("Invalid job ID or copy count (maximum 100)");
    connect_agent(argv[2]);
    FILE *spool=temporary();
    int input=argc==7?open(argv[6],O_RDONLY):STDIN_FILENO; if(input<0) fail("Cannot open input");
    cups_raster_t *r=cupsRasterOpen(input,CUPS_RASTER_READ); if(!r) fail("Cannot read CUPS raster");
    cups_page_header2_t h; int count=0; uint64_t bytes=0;
    while(!stopped && cupsRasterReadHeader2(r,&h)) {
        uint64_t size=(uint64_t)h.cupsBytesPerLine*h.cupsHeight;
        if(count==MAX_PAGES || !h.cupsHeight || !h.cupsWidth || !h.cupsBytesPerLine || h.cupsBytesPerLine>1024*1024 || size>MAX_BYTES-bytes) fail("Job exceeds raster spool limits");
        if(h.cupsColorOrder!=CUPS_ORDER_CHUNKED || (h.cupsBitsPerPixel!=1 && h.cupsBitsPerPixel!=8) || h.cupsBitsPerColor!=h.cupsBitsPerPixel || (h.cupsColorSpace!=CUPS_CSPACE_K && h.cupsColorSpace!=CUPS_CSPACE_W && h.cupsColorSpace!=CUPS_CSPACE_SW) || ((uint64_t)h.cupsWidth*h.cupsBitsPerPixel+7)/8>h.cupsBytesPerLine) fail("Manual duplex currently requires 1-bit or 8-bit monochrome raster");
        pages[count++]=(Page){h,ftello(spool)}; bytes+=size;
        unsigned char *line=malloc(h.cupsBytesPerLine); if(!line) fail("Out of memory");
        for(unsigned y=0;y<h.cupsHeight && !stopped;y++) if(cupsRasterReadPixels(r,line,h.cupsBytesPerLine)!=h.cupsBytesPerLine || fwrite(line,1,h.cupsBytesPerLine,spool)!=h.cupsBytesPerLine) fail("Truncated raster or full spool disk");
        free(line);
    }
    cupsRasterClose(r); if(input!=STDIN_FILENO) close(input);
    if(stopped) return 0;
    if(!count) fail("No raster pages");
    fflush(spool);
    FILE *front=make_pass(spool,count,0,0), *back=count>1?make_pass(spool,count,1,rotate):NULL;
    for(int copy=1;copy<=copies&&!stopped;copy++) {
        vendor(front,argv); if(stopped) break;
        if(back) {
            // Drain means bytes delivered to USB, not physical pages completed.
            char data[1]; int len=sizeof(data);
            cups_sc_status_t status=cupsSideChannelDoRequest(CUPS_SC_CMD_DRAIN_OUTPUT,data,&len,30.0);
            if(status!=CUPS_SC_STATUS_OK) fprintf(stderr,"WARNING: Backend drain unavailable; verify all sheets have exited before confirming.\n");
            if(!confirmation(argv[2],job,count,copy,copies)) { fprintf(stderr,"INFO: Second pass cancelled.\n"); break; }
            vendor(back,argv);
        }
    }
    fclose(front); if(back) fclose(back); fclose(spool); cupsFreeOptions(n,options); return 0;
}
