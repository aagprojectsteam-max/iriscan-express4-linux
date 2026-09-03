#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <scsi/sg.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#define SENSE_LEN 64
#define MAX_LINE 4096
#define CDB_LEN 16
#define MAX_TRANSFER (1024U * 1024U)
#define C3_CHUNK 32768U
#define POLL_TIMEOUT_SEC 120

static volatile sig_atomic_t g_stop = 0;
static int g_fd = -1;
static bool g_scan_started = false;
static char g_finish_ops[4096];
static char g_c3_forensic_dump[4096];

static void on_signal(int sig) { (void)sig; g_stop = 1; }
static uint32_t le32(const uint8_t *p) { return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24); }
static void put_be32(uint8_t *p, uint32_t v) { p[0]=(uint8_t)(v>>24); p[1]=(uint8_t)(v>>16); p[2]=(uint8_t)(v>>8); p[3]=(uint8_t)v; }
static uint64_t fnv1a64(const uint8_t *buf, size_t n) { uint64_t h=UINT64_C(1469598103934665603); for(size_t i=0;i<n;++i){h^=buf[i];h*=UINT64_C(1099511628211);} return h; }

static void dump_sense(const uint8_t *s, int n) {
    if (n <= 0) return;
    fprintf(stderr, "sense(%d):", n);
    for (int i = 0; i < n; ++i) fprintf(stderr, " %02x", s[i]);
    fputc('\n', stderr);
    if (n >= 14) fprintf(stderr, "sense_key=0x%x asc=0x%02x ascq=0x%02x\n", s[2] & 0x0f, s[12], s[13]);
}

static int sg_cmd(int fd, const uint8_t *cdb, int cdb_len, int dxfer_dir, void *buf, uint32_t len, unsigned timeout_ms, uint32_t *actual_out, bool quiet) {
    sg_io_hdr_t io; uint8_t sense[SENSE_LEN]; memset(&io,0,sizeof(io)); memset(sense,0,sizeof(sense));
    io.interface_id='S'; io.cmdp=(unsigned char*)cdb; io.cmd_len=(unsigned char)cdb_len; io.dxfer_direction=dxfer_dir; io.dxferp=buf; io.dxfer_len=len; io.sbp=sense; io.mx_sb_len=sizeof(sense); io.timeout=timeout_ms;
    int rc; do { rc=ioctl(fd,SG_IO,&io); } while(rc<0 && errno==EINTR && !g_stop);
    if(actual_out) *actual_out=(io.resid>=0 && (uint32_t)io.resid<=len)?len-(uint32_t)io.resid:0;
    if(rc<0){ if(!quiet) fprintf(stderr,"SG_IO ioctl failed: %s\n",strerror(errno)); return -1; }
    if((io.info & SG_INFO_OK_MASK)!=SG_INFO_OK || io.status!=0 || io.host_status!=0 || io.driver_status!=0){ if(!quiet){fprintf(stderr,"SG_IO failed: status=0x%02x host=0x%04x driver=0x%04x info=0x%08x resid=%d\n",io.status,io.host_status,io.driver_status,io.info,io.resid);dump_sense(sense,io.sb_len_wr);} return -2; }
    return 0;
}

static int hex_nibble(char c){ if(c>='0'&&c<='9')return c-'0'; if(c>='a'&&c<='f')return c-'a'+10; if(c>='A'&&c<='F')return c-'A'+10; return -1; }
static int hex_decode(const char *s,uint8_t*out,size_t cap){size_t n=strlen(s);if((n&1U)!=0||n/2>cap)return -1;for(size_t i=0;i<n/2;++i){int hi=hex_nibble(s[i*2]),lo=hex_nibble(s[i*2+1]);if(hi<0||lo<0)return -1;out[i]=(uint8_t)((hi<<4)|lo);}return(int)(n/2);}

static int run_ops_file(int fd,const char*path,const char*phase,bool best_effort){
    FILE*f=fopen(path,"r"); if(!f){fprintf(stderr,"Cannot open transcript %s: %s\n",path,strerror(errno));return -1;} printf("[%s] transcript=%s\n",phase,path);
    char line[MAX_LINE]; unsigned long line_no=0,op_no=0; int result=0;
    while(fgets(line,sizeof(line),f)){++line_no;if(line[0]=='#'||line[0]=='\n'||line[0]=='\r')continue;unsigned delay_us=0,xfer=0,original_tx=0;char dir[8],cdb_hex[128],data_hex[MAX_LINE];int got=sscanf(line,"%u %7s %u %127s %4095s %u",&delay_us,dir,&xfer,cdb_hex,data_hex,&original_tx);if(got!=6){fprintf(stderr,"%s:%lu malformed transcript line\n",path,line_no);result=-1;break;}if(g_stop&&!best_effort){result=-2;break;}if(delay_us>0)usleep(delay_us);if(xfer>MAX_TRANSFER){result=-1;break;}uint8_t cdb[CDB_LEN];memset(cdb,0,sizeof(cdb));int clen=hex_decode(cdb_hex,cdb,sizeof(cdb));if(clen<=0){result=-1;break;}uint8_t*buf=xfer?calloc(1,xfer):NULL;if(xfer&&!buf){result=-1;break;}int sgdir=SG_DXFER_NONE;if(strcmp(dir,"IN")==0)sgdir=SG_DXFER_FROM_DEV;else if(strcmp(dir,"OUT")==0){sgdir=SG_DXFER_TO_DEV;if(strcmp(data_hex,"-")!=0){int dlen=hex_decode(data_hex,buf,xfer);if(dlen<0||(unsigned)dlen!=xfer){free(buf);result=-1;break;}}}else{free(buf);result=-1;break;}uint32_t actual=0;int rc=sg_cmd(fd,cdb,clen,sgdir,buf,xfer,30000,&actual,best_effort);++op_no;if(rc!=0){fprintf(stderr,"[%s] op=%lu original_tx=%u failed rc=%d cdb=%s\n",phase,op_no,original_tx,rc,cdb_hex);free(buf);if(!best_effort){result=rc;break;}}else{if(strcmp(dir,"OUT")==0&&xfer>=6&&buf&&buf[0]==0x1b&&(buf[5]&0x80)!=0){g_scan_started=true;printf("[%s] scanner START command accepted (original_tx=%u)\n",phase,original_tx);}if(strcmp(dir,"OUT")==0&&xfer>=1&&buf&&buf[0]==0x17){g_scan_started=false;printf("[%s] scanner RELEASE command accepted (original_tx=%u)\n",phase,original_tx);}if((op_no%100UL)==0UL){printf("[%s] completed %lu operations\n",phase,op_no);fflush(stdout);}if(strcmp(dir,"IN")==0&&xfer==4&&actual==4&&memcmp(buf,"NOVA",4)==0)printf("[%s] bridge signature: NOVA\n",phase);free(buf);}}
    fclose(f);printf("[%s] operations=%lu result=%d\n",phase,op_no,result);return result;
}

static void make_c5(uint8_t cdb[16],uint32_t len,uint8_t s0,uint8_t s1,uint8_t s2){memset(cdb,0,16);cdb[0]=0xc5;cdb[1]=0x07;cdb[8]=(uint8_t)(len>>8);cdb[9]=(uint8_t)len;cdb[10]=s0;cdb[11]=s1;cdb[12]=s2;}
static int c5_in(int fd,uint32_t len,uint8_t s0,uint8_t s1,uint8_t s2,uint8_t*out,uint32_t*actual){uint8_t cdb[16];make_c5(cdb,len,s0,s1,s2);memset(out,0,len);return sg_cmd(fd,cdb,16,SG_DXFER_FROM_DEV,out,len,10000,actual,false);}

struct scan_status { uint32_t code,width,plane_rows,address; uint8_t side1[24],side2[24]; };
static void poll_dump_bytes(const char*label,const uint8_t*buf,uint32_t n){fprintf(stderr,"%s data(%u):",label,n);for(uint32_t i=0;i<n;++i)fprintf(stderr," %02x",buf[i]);fputc('\n',stderr);}
static int poll_c5_step(int fd,const char*label,unsigned delay_us,uint32_t len,uint8_t s0,uint8_t s1,uint8_t s2,uint8_t*buf){uint32_t actual=0;if(delay_us)usleep(delay_us);int rc=c5_in(fd,len,s0,s1,s2,buf,&actual);if(rc!=0){fprintf(stderr,"POLL_FAIL step=%s rc=%d expected=%u actual=%u selector=%02x/%02x/%02x\n",label,rc,len,actual,s0,s1,s2);if(actual)poll_dump_bytes("POLL_PARTIAL",buf,actual);return -1;}return 0;}
