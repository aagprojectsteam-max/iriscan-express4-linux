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
/*
 * v2.6:
 * Linux usb-storage/SG_IO reports a deterministic 78-byte residual
 * for the scanner's 65536-byte C3 transfer.  The device queue allows
 * 120 KiB, but 65536 is exactly max_segment_size.
 *
 * Stay safely below that boundary.  We still require every C3 read
 * to return the complete requested payload, so no image bytes are
 * silently discarded.
 */
#define C3_CHUNK 32768U
#define POLL_TIMEOUT_SEC 120

static volatile sig_atomic_t g_stop = 0;
static int g_fd = -1;
static bool g_scan_started = false;
static char g_finish_ops[4096];

static void on_signal(int sig) {
    (void)sig;
    g_stop = 1;
}

static uint32_t le32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static void put_be32(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)(v >> 24);
    p[1] = (uint8_t)(v >> 16);
    p[2] = (uint8_t)(v >> 8);
    p[3] = (uint8_t)v;
}

static uint64_t fnv1a64(const uint8_t *buf, size_t n) {
    uint64_t h = UINT64_C(14695981039346656037);
    for (size_t i = 0; i < n; ++i) {
        h ^= buf[i];
        h *= UINT64_C(1099511628211);
    }
    return h;
}

struct sg_observation {
    int ioctl_rc;
    int resid;
    unsigned char status;
    unsigned short host_status;
    unsigned short driver_status;
    unsigned int info;
    unsigned int duration_ms;
    unsigned char sense_len;
    uint8_t sense[SENSE_LEN];
};

static void dump_sense(const uint8_t *s, int n) {
    if (n <= 0) return;
    fprintf(stderr, "sense(%d):", n);
    for (int i = 0; i < n; ++i) fprintf(stderr, " %02x", s[i]);
    fputc('\n', stderr);
    if (n >= 14) {
        int key = s[2] & 0x0f;
        int asc = s[12];
        int ascq = s[13];
        fprintf(stderr, "sense_key=0x%x asc=0x%02x ascq=0x%02x\n", key, asc, ascq);
    }
}

static int sg_cmd(int fd, const uint8_t *cdb, int cdb_len,
                  int dxfer_dir, void *buf, uint32_t len,
                  unsigned timeout_ms, uint32_t *actual_out,
                  bool quiet, struct sg_observation *observation) {
    sg_io_hdr_t io;
    uint8_t sense[SENSE_LEN];
    memset(&io, 0, sizeof(io));
    memset(sense, 0, sizeof(sense));
    io.interface_id = 'S';
    io.cmdp = (unsigned char *)cdb;
    io.cmd_len = (unsigned char)cdb_len;
    io.dxfer_direction = dxfer_dir;
    io.dxferp = buf;
    io.dxfer_len = len;
    io.sbp = sense;
    io.mx_sb_len = sizeof(sense);
    io.timeout = timeout_ms;

    int rc;
    do {
        rc = ioctl(fd, SG_IO, &io);
    } while (rc < 0 && errno == EINTR && !g_stop);

    if (observation) {
        memset(observation, 0, sizeof(*observation));
        observation->ioctl_rc = rc;
        observation->resid = io.resid;
        observation->status = io.status;
        observation->host_status = io.host_status;
        observation->driver_status = io.driver_status;
        observation->info = io.info;
        observation->duration_ms = io.duration;
        observation->sense_len = io.sb_len_wr;
        if (observation->sense_len > SENSE_LEN)
            observation->sense_len = SENSE_LEN;
        memcpy(observation->sense, sense, observation->sense_len);
    }

    if (actual_out) {
        *actual_out = (io.resid >= 0 && (uint32_t)io.resid <= len)
                          ? len - (uint32_t)io.resid
                          : 0;
    }

    if (rc < 0) {
        if (!quiet) fprintf(stderr, "SG_IO ioctl failed: %s\n", strerror(errno));
        return -1;
    }

    if ((io.info & SG_INFO_OK_MASK) != SG_INFO_OK || io.status != 0 ||
        io.host_status != 0 || io.driver_status != 0) {
        if (!quiet) {
            fprintf(stderr,
                    "SG_IO failed: status=0x%02x host=0x%04x driver=0x%04x info=0x%08x resid=%d\n",
                    io.status, io.host_status, io.driver_status, io.info, io.resid);
            dump_sense(sense, io.sb_len_wr);
        }
        return -2;
    }
    return 0;
}

static int hex_nibble(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static int hex_decode(const char *s, uint8_t *out, size_t cap) {
    size_t n = strlen(s);
    if ((n & 1U) != 0 || n / 2 > cap) return -1;
    for (size_t i = 0; i < n / 2; ++i) {
        int hi = hex_nibble(s[i * 2]);
        int lo = hex_nibble(s[i * 2 + 1]);
        if (hi < 0 || lo < 0) return -1;
        out[i] = (uint8_t)((hi << 4) | lo);
    }
    return (int)(n / 2);
}

static int run_ops_file(int fd, const char *path, const char *phase,
                        bool best_effort) {
    FILE *f = fopen(path, "r");
    if (!f) {
        fprintf(stderr, "Cannot open transcript %s: %s\n", path, strerror(errno));
        return -1;
    }
    printf("[%s] transcript=%s\n", phase, path);
    char line[MAX_LINE];
    unsigned long line_no = 0, op_no = 0;
    int result = 0;
    while (fgets(line, sizeof(line), f)) {
        ++line_no;
        if (line[0] == '#' || line[0] == '\n' || line[0] == '\r') continue;
        unsigned delay_us = 0, xfer = 0, original_tx = 0;
        char dir[8], cdb_hex[128], data_hex[MAX_LINE];
        int got = sscanf(line, "%u %7s %u %127s %4095s %u",
                         &delay_us, dir, &xfer, cdb_hex, data_hex, &original_tx);
        if (got != 6) {
            fprintf(stderr, "%s:%lu malformed transcript line\n", path, line_no);
            result = -1;
            break;
        }
        if (g_stop && !best_effort) {
            result = -2;
            break;
        }
        if (delay_us > 0) usleep(delay_us);
        if (xfer > MAX_TRANSFER) {
            fprintf(stderr, "%s:%lu transfer too large: %u\n", path, line_no, xfer);
            result = -1;
            break;
        }
        uint8_t cdb[CDB_LEN];
        memset(cdb, 0, sizeof(cdb));
        int clen = hex_decode(cdb_hex, cdb, sizeof(cdb));
        if (clen <= 0) {
            fprintf(stderr, "%s:%lu invalid CDB\n", path, line_no);
            result = -1;
            break;
        }
        uint8_t *buf = NULL;
        if (xfer) {
            buf = calloc(1, xfer);
            if (!buf) {
                fprintf(stderr, "Out of memory allocating %u bytes\n", xfer);
                result = -1;
                break;
            }
        }
        int sgdir = SG_DXFER_NONE;
        if (strcmp(dir, "IN") == 0) {
            sgdir = SG_DXFER_FROM_DEV;
        } else if (strcmp(dir, "OUT") == 0) {
            sgdir = SG_DXFER_TO_DEV;
            if (strcmp(data_hex, "-") == 0) {
                if (xfer != 0) {
                    fprintf(stderr, "%s:%lu OUT missing data\n", path, line_no);
                    free(buf);
                    result = -1;
                    break;
                }
            } else {
                int dlen = hex_decode(data_hex, buf, xfer);
                if (dlen < 0 || (unsigned)dlen != xfer) {
                    fprintf(stderr, "%s:%lu OUT data size mismatch (%d != %u)\n",
                            path, line_no, dlen, xfer);
                    free(buf);
                    result = -1;
                    break;
                }
            }
        } else {
            fprintf(stderr, "%s:%lu bad direction %s\n", path, line_no, dir);
            free(buf);
            result = -1;
            break;
        }
        uint32_t actual = 0;
        int rc = sg_cmd(fd, cdb, clen, sgdir, buf, xfer, 30000, &actual,
                        best_effort, NULL);
        ++op_no;
        if (rc != 0) {
            fprintf(stderr,
                    "[%s] op=%lu original_tx=%u failed rc=%d cdb=%s\n",
                    phase, op_no, original_tx, rc, cdb_hex);
            free(buf);
            if (!best_effort) {
                result = rc;
                break;
            }
        } else {
            if (strcmp(dir, "OUT") == 0 && xfer >= 6 && buf != NULL &&
                buf[0] == 0x1b && (buf[5] & 0x80) != 0) {
                g_scan_started = true;
                printf("[%s] scanner START command accepted (original_tx=%u)\n",
                       phase, original_tx);
            }
            if (strcmp(dir, "OUT") == 0 && xfer >= 1 && buf != NULL &&
                buf[0] == 0x17) {
                g_scan_started = false;
                printf("[%s] scanner RELEASE command accepted (original_tx=%u)\n",
                       phase, original_tx);
            }
            if ((op_no % 100UL) == 0UL) {
                printf("[%s] completed %lu operations\n", phase, op_no);
                fflush(stdout);
            }
            /* Strong bridge identity marker. */
            if (strcmp(dir, "IN") == 0 && xfer == 4 && actual == 4 &&
                memcmp(buf, "NOVA", 4) == 0) {
                printf("[%s] bridge signature: NOVA\n", phase);
            }
            free(buf);
        }
    }
    fclose(f);
    printf("[%s] operations=%lu result=%d\n", phase, op_no, result);
    return result;
}

static void make_c5(uint8_t cdb[16], uint32_t len,
                    uint8_t s0, uint8_t s1, uint8_t s2) {
    memset(cdb, 0, 16);
    cdb[0] = 0xc5;
    cdb[1] = 0x07;
    cdb[8] = (uint8_t)(len >> 8);
    cdb[9] = (uint8_t)len;
    cdb[10] = s0;
    cdb[11] = s1;
    cdb[12] = s2;
}

static int c5_in(int fd, uint32_t len, uint8_t s0, uint8_t s1, uint8_t s2,
                 uint8_t *out, uint32_t *actual) {
    uint8_t cdb[16];
    make_c5(cdb, len, s0, s1, s2);
    memset(out, 0, len);
    return sg_cmd(fd, cdb, 16, SG_DXFER_FROM_DEV, out, len, 10000, actual,
                  false, NULL);
}

struct scan_status {
    uint32_t code;
    uint32_t width;
    uint32_t plane_rows;
    uint32_t address;
    uint8_t side1[24];
    uint8_t side2[24];
};

/*
 * v2.2 timed polling + exact diagnostics.
 */
static void poll_dump_bytes(const char *label,
                            const uint8_t *buf, uint32_t n) {
    fprintf(stderr, "%s data(%u):", label, n);
    for (uint32_t i = 0; i < n; ++i)
        fprintf(stderr, " %02x", buf[i]);
    fputc('\n', stderr);
}

static int poll_c5_step(int fd,
                        const char *label,
                        unsigned delay_us,
                        uint32_t len,
                        uint8_t s0, uint8_t s1, uint8_t s2,
                        uint8_t *buf) {
    uint32_t actual = 0;

    if (delay_us != 0)
        usleep(delay_us);

    int rc = c5_in(fd, len, s0, s1, s2, buf, &actual);

    if (rc != 0) {
        fprintf(stderr,
                "POLL_FAIL step=%s rc=%d expected=%u actual=%u "
                "selector=%02x/%02x/%02x\n",
                label, rc, len, actual, s0, s1, s2);
        if (actual != 0)
            poll_dump_bytes("POLL_PARTIAL", buf, actual);
        return -1;
    }

    /*
     * v2.5:
     * usb-storage/SG_IO resid is not reliable for these private C5
     * bridge transfers.  We already proved this for DATA-OUT, and the
     * transcript executor successfully performs hundreds of identical
     * C5 IN commands without treating resid as a byte-count contract.
     *
     * rc==0 already means ioctl/SCSI/host/driver status succeeded.
     * Do not reject a C5 command solely because resid-derived "actual"
     * is zero or short.
     */
    if (actual != len) {
        fprintf(stderr,
                "POLL_RESID step=%s requested=%u resid_derived_actual=%u "
                "selector=%02x/%02x/%02x -- continuing\n",
                label, len, actual, s0, s1, s2);
    }

    return 0;
}

static int poll_status_once(int fd, struct scan_status *st,
                            bool include_initial_sync) {
    uint8_t tmp16[16], tmp24[24];

    if (include_initial_sync) {
        /*
         * v2.4: issue scanner READ (0x28) here, immediately followed
         * by the captured NOVA ff04/ff06 synchronization.
         *
         * Do not return to main between READ and synchronization:
         * the Windows capture starts ff04 about 0.33 ms after READ.
         */
        uint8_t outer[16];
        uint8_t inner_read[10] = {
            0x28, 0x00, 0x00, 0x00, 0x0a,
            0x0d, 0x1f, 0xea, 0xe0, 0x00
        };
        uint32_t read_actual = 0;

        make_c5(outer, sizeof(inner_read), 0x02, 0x03, 0x00);

        int read_rc = sg_cmd(fd,
                             outer, 16,
                             SG_DXFER_TO_DEV,
                             inner_read, sizeof(inner_read),
                             10000,
                             &read_actual,
                             false,
                             NULL);

        /*
         * SG_DXFER_TO_DEV:
         *
         * sg_cmd() already validates ioctl/SCSI/host/driver status.
         * A successful data-out command is therefore rc == 0.
         *
         * Do NOT require len-resid == transfer length here.  resid is
         * not a reliable byte-count acknowledgement for this outbound
         * command on this usb-storage/SG_IO path.
         */
        if (read_rc != 0) {
            fprintf(stderr,
                    "POLL_READ_FAIL rc=%d resid_derived_actual=%u\n",
                    read_rc, read_actual);
            return -1;
        }

        /* Windows capture: READ -> ff04 is approximately 0.33 ms. */
        usleep(330);

        if (poll_c5_step(fd, "initial.ff04",
                         0,
                         16, 0xff, 0x04, 0x00, tmp16) != 0)
            return -1;

        if (poll_c5_step(fd, "initial.ff06",
                         5350,
                         16, 0xff, 0x06, 0x00, tmp16) != 0)
            return -1;
    }

    if (poll_c5_step(fd, "body.ff04.1",
                     750,
                     16, 0xff, 0x04, 0x00, tmp16) != 0)
        return -1;

    if (poll_c5_step(fd, "body.ff03.1",
                     450,
                     16, 0xff, 0x03, 0x00, tmp16) != 0)
        return -1;

    if (poll_c5_step(fd, "body.ff03.2",
                     450,
                     16, 0xff, 0x03, 0x00, tmp16) != 0)
        return -1;

    if (poll_c5_step(fd, "body.ff05",
                     450,
                     16, 0xff, 0x05, 0x00, tmp16) != 0)
        return -1;

    if (poll_c5_step(fd, "descriptor.side1",
                     450,
                     24, 0x02, 0x01, 0x02, tmp24) != 0)
        return -1;

    memcpy(st->side1, tmp24, 24);
    poll_dump_bytes("DESCRIPTOR_SIDE1", st->side1, 24);

    if (poll_c5_step(fd, "between.ff04",
                     450,
                     16, 0xff, 0x04, 0x00, tmp16) != 0)
        return -1;

    if (poll_c5_step(fd, "descriptor.side2",
                     450,
                     24, 0x02, 0x02, 0x02, tmp24) != 0)
        return -1;

    memcpy(st->side2, tmp24, 24);
    poll_dump_bytes("DESCRIPTOR_SIDE2", st->side2, 24);

    if (poll_c5_step(fd, "tail.ff04",
                     450,
                     16, 0xff, 0x04, 0x00, tmp16) != 0)
        return -1;

    if (poll_c5_step(fd, "tail.ff06",
                     450,
                     16, 0xff, 0x06, 0x00, tmp16) != 0)
        return -1;

    st->code       = le32(st->side2 + 0);
    st->width      = le32(st->side2 + 12);
    st->plane_rows = le32(st->side2 + 16);
    st->address    = le32(st->side2 + 20);

    return 0;
}

static int read_c3_range(int fd, uint32_t address, uint32_t total,
                         uint8_t *dest) {
    uint32_t done = 0;
    while (done < total) {
        if (g_stop) return -2;
        uint32_t chunk = total - done;
        if (chunk > C3_CHUNK) chunk = C3_CHUNK;
        uint8_t cdb[16];
        memset(cdb, 0, sizeof(cdb));
        cdb[0] = 0xc3;
        cdb[1] = 0x07;
        put_be32(cdb + 2, address + done);
        put_be32(cdb + 6, chunk);
        uint32_t actual = 0;
        int rc = -1;
        for (int attempt = 1; attempt <= 3; ++attempt) {
            /*
             * Evidence-first transfer accounting: initialize every byte to a
             * deterministic sentinel, then record exactly which buffer region
             * SG_IO changed. A matching payload byte can look unchanged, so
             * this is forensic evidence rather than an inferred byte count.
             */
            uint8_t *sentinel = malloc(chunk);
            if (!sentinel) {
                fprintf(stderr, "Out of memory allocating C3 sentinel\n");
                return -1;
            }
            for (uint32_t i = 0; i < chunk; ++i)
                sentinel[i] = (uint8_t)(0xa5U ^ (uint8_t)i ^
                                        (uint8_t)((address + done) >> 8));
            memcpy(dest + done, sentinel, chunk);
            struct sg_observation observation;
            rc = sg_cmd(fd, cdb, 16, SG_DXFER_FROM_DEV,
                        dest + done, chunk, 30000, &actual, false,
                        &observation);
            uint32_t changed = 0;
            uint32_t first_changed = chunk;
            uint32_t last_changed = 0;
            for (uint32_t i = 0; i < chunk; ++i) {
                if (dest[done + i] != sentinel[i]) {
                    if (first_changed == chunk) first_changed = i;
                    last_changed = i;
                    ++changed;
                }
            }
            uint32_t unchanged_suffix = changed == 0 ? chunk : chunk - last_changed - 1U;
            uint64_t full_hash = fnv1a64(dest + done, chunk);
            uint64_t derived_hash = fnv1a64(dest + done, actual <= chunk ? actual : 0);
            uint64_t sense_hash = fnv1a64(observation.sense,
                                          observation.sense_len);
            fprintf(stderr,
                    "C3_OBSERVATION attempt=%d address=0x%08x requested=%u "
                    "resid=%d derived_actual=%u ioctl_rc=%d status=0x%02x "
                    "host=0x%04x driver=0x%04x info=0x%08x duration_ms=%u "
                    "sense_len=%u sense_fnv1a64=%016" PRIx64 " changed=%u "
                    "first_changed=%s last_changed=%s unchanged_suffix=%u "
                    "buffer_fnv1a64=%016" PRIx64 " derived_fnv1a64=%016" PRIx64 "\n",
                    attempt, address + done, chunk, observation.resid, actual,
                    observation.ioctl_rc, observation.status,
                    observation.host_status, observation.driver_status,
                    observation.info, observation.duration_ms,
                    observation.sense_len, sense_hash, changed,
                    first_changed == chunk ? "NONE" : "SET",
                    changed == 0 ? "NONE" : "SET", unchanged_suffix,
                    full_hash, derived_hash);
            if (changed != 0) {
                fprintf(stderr,
                        "C3_MODIFICATION_BOUNDARY first=%u last=%u requested=%u\n",
                        first_changed, last_changed, chunk);
            }
            free(sentinel);
            if (rc == 0 && actual == chunk) break;
            fprintf(stderr,
                    "C3 read retry %d: addr=0x%08x requested=%u actual=%u rc=%d\n",
                    attempt, address + done, chunk, actual, rc);
            usleep(20000);
        }
        if (rc != 0 || actual != chunk) {
            fprintf(stderr,
                    "C3 read failed permanently: addr=0x%08x requested=%u actual=%u\n",
                    address + done, chunk, actual);
            return -1;
        }
        done += chunk;
    }
    return 0;
}

static int verify_device(int fd) {
    uint8_t cdb[6] = {0x12, 0, 0, 0, 36, 0};
    uint8_t data[36];
    uint32_t actual = 0;
    memset(data, 0, sizeof(data));
    if (sg_cmd(fd, cdb, 6, SG_DXFER_FROM_DEV, data, sizeof(data),
               10000, &actual, false, NULL) != 0 || actual < 36) {
        fprintf(stderr, "Standard INQUIRY failed\n");
        return -1;
    }
    char vendor[9], model[17], rev[5];
    memcpy(vendor, data + 8, 8); vendor[8] = 0;
    memcpy(model, data + 16, 16); model[16] = 0;
    memcpy(rev, data + 32, 4); rev[4] = 0;
    printf("INQUIRY vendor='%s' model='%s' rev='%s' PDT=%u\n",
           vendor, model, rev, data[0] & 0x1f);
    if (memcmp(data + 8, "IRIS    ", 8) != 0 ||
        memcmp(data + 16, "IRIScanExpress4 ", 16) != 0) {
        fprintf(stderr, "Refusing: device is not the verified IRIScan Express 4\n");
        return -1;
    }
    return 0;
}

static int write_ppm_from_line_planar(const char *raw_path, const char *ppm_path,
                                      uint32_t width, uint64_t height) {
    FILE *in = fopen(raw_path, "rb");
    if (!in) return -1;
    FILE *out = fopen(ppm_path, "wb");
    if (!out) { fclose(in); return -1; }
    fprintf(out, "P6\n%u %" PRIu64 "\n255\n", width, height);
    size_t planar_len = (size_t)width * 3U;
    uint8_t *planar = malloc(planar_len);
    uint8_t *rgb = malloc(planar_len);
    if (!planar || !rgb) {
        free(planar); free(rgb); fclose(in); fclose(out); return -1;
    }
    for (uint64_t y = 0; y < height; ++y) {
        if (fread(planar, 1, planar_len, in) != planar_len) {
            fprintf(stderr, "Unexpected EOF converting line %" PRIu64 "\n", y);
            free(planar); free(rgb); fclose(in); fclose(out); return -1;
        }
        for (uint32_t x = 0; x < width; ++x) {
            rgb[x * 3U + 0] = planar[x];
            rgb[x * 3U + 1] = planar[width + x];
            rgb[x * 3U + 2] = planar[width * 2U + x];
        }
        if (fwrite(rgb, 1, planar_len, out) != planar_len) {
            free(planar); free(rgb); fclose(in); fclose(out); return -1;
        }
    }
    free(planar); free(rgb); fclose(in); fclose(out);
    return 0;
}

static int join_path(char *out, size_t cap, const char *a, const char *b) {
    int n = snprintf(out, cap, "%s/%s", a, b);
    return (n > 0 && (size_t)n < cap) ? 0 : -1;
}

static void usage(const char *argv0) {
    fprintf(stderr,
            "Usage: %s --device /dev/sgX --ops-dir DIR --output-dir DIR [--skip-init]\n",
            argv0);
}

int main(int argc, char **argv) {
    const char *device = NULL, *ops_dir = NULL, *out_dir = NULL;
    bool skip_init = false;
    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--device") == 0 && i + 1 < argc) device = argv[++i];
        else if (strcmp(argv[i], "--ops-dir") == 0 && i + 1 < argc) ops_dir = argv[++i];
        else if (strcmp(argv[i], "--output-dir") == 0 && i + 1 < argc) out_dir = argv[++i];
        else if (strcmp(argv[i], "--skip-init") == 0) skip_init = true;
        else { usage(argv[0]); return 2; }
    }
    if (!device || !ops_dir || !out_dir) { usage(argv[0]); return 2; }

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = on_signal;
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);

    char init_ops[4096], setup_ops[4096], next_ops[4096];
    char raw_path[4096], ppm_path[4096], meta_path[4096], batch_log_path[4096];
    if (join_path(init_ops, sizeof(init_ops), ops_dir, "init.ops") ||
        join_path(setup_ops, sizeof(setup_ops), ops_dir, "scan-setup-300dpi-color.ops") ||
        join_path(next_ops, sizeof(next_ops), ops_dir, "next-batch.ops") ||
        join_path(g_finish_ops, sizeof(g_finish_ops), ops_dir, "scan-finish.ops") ||
        join_path(raw_path, sizeof(raw_path), out_dir, "IRIScan-300dpi-color-line-planar.raw") ||
        join_path(ppm_path, sizeof(ppm_path), out_dir, "IRIScan-300dpi-color.ppm") ||
        join_path(meta_path, sizeof(meta_path), out_dir, "scan-metadata.json") ||
        join_path(batch_log_path, sizeof(batch_log_path), out_dir, "scan-batches.tsv")) {
        fprintf(stderr, "Path too long\n"); return 2;
    }

    if (mkdir(out_dir, 0775) != 0 && errno != EEXIST) {
        fprintf(stderr, "Cannot create output dir %s: %s\n", out_dir, strerror(errno));
        return 1;
    }

    g_fd = open(device, O_RDWR | O_CLOEXEC);
    if (g_fd < 0) {
        fprintf(stderr, "Cannot open %s: %s\n", device, strerror(errno));
        return 1;
    }
    if (flock(g_fd, LOCK_EX | LOCK_NB) != 0) {
        fprintf(stderr, "Cannot lock %s exclusively: %s\n", device, strerror(errno));
        close(g_fd); return 1;
    }
    int reserve = 1024 * 1024;
    (void)ioctl(g_fd, SG_SET_RESERVED_SIZE, &reserve);

    printf("IRIScan Express 4 Linux experimental protocol PoC\n");
    printf("device=%s\nops_dir=%s\noutput_dir=%s\n", device, ops_dir, out_dir);
    if (verify_device(g_fd) != 0) { close(g_fd); return 1; }

    int rc = 0;
    uint32_t width = 0;
    uint64_t total_rgb_rows = 0, total_bytes = 0;
    unsigned batch_no = 0;
    if (!skip_init) {
        rc = run_ops_file(g_fd, init_ops, "INIT", false);
        if (rc != 0) goto cleanup;
    } else {
        printf("[INIT] skipped by request\n");
    }

    rc = run_ops_file(g_fd, setup_ops, "SCAN_SETUP_300DPI_RGB", false);
    if (rc != 0) goto cleanup;
    g_scan_started = true;

    FILE *raw = fopen(raw_path, "wb");
    FILE *batch_log = fopen(batch_log_path, "w");
    if (!raw || !batch_log) {
        fprintf(stderr, "Cannot create output files: %s\n", strerror(errno));
        if (raw) fclose(raw);
        if (batch_log) fclose(batch_log);
        rc = 1; goto cleanup;
    }
    fprintf(batch_log, "batch\tstatus_code\twidth\tplane_rows\trgb_rows\taddress\tbytes\tfnv1a64\n");

    time_t scan_deadline = time(NULL) + POLL_TIMEOUT_SEC;
    /*
     * v2.3:
     * scan-setup transcript already ends with the captured post-START
     * synchronization and the first inner READ (0x28).
     * Therefore the first descriptor poll must enter directly at the
     * descriptor-poll body; replaying ff04/ff06 here advances the NOVA
     * bridge state incorrectly and returns a zero-length ff04 response.
     */
    bool include_initial_status_sync = true;
    unsigned status_poll_no = 0;

    while (!g_stop) {
        if (time(NULL) > scan_deadline) {
            fprintf(stderr, "Timed out waiting for scan completion\n");
            rc = 1; break;
        }
        struct scan_status st;
        memset(&st, 0, sizeof(st));
        ++status_poll_no;
        if (poll_status_once(g_fd, &st, include_initial_status_sync) != 0) {
            fprintf(stderr,
                    "Status polling failed at poll=%u initial_sync=%u\n",
                    status_poll_no, include_initial_status_sync ? 1U : 0U);
            rc = 1; break;
        }
        include_initial_status_sync = false;
        if (status_poll_no == 1U || st.code != 0U ||
            (status_poll_no % 100U) == 0U) {
            printf("STATUS poll=%u code=%u width=%u plane_rows=%u address=0x%08x\n",
                   status_poll_no, st.code, st.width, st.plane_rows, st.address);
            fflush(stdout);
        }

        if (st.code == 3) {
            printf("SCAN_COMPLETE status=3\n");
            break;
        }
        if (st.code == 0 || st.address == 0 || st.plane_rows == 0) {
            usleep(2000);
            continue;
        }
        if (st.code != 1) {
            fprintf(stderr,
                    "Unexpected scan status code=%u width=%u plane_rows=%u address=0x%08x\n",
                    st.code, st.width, st.plane_rows, st.address);
            usleep(5000);
            continue;
        }
        if (st.width == 0 || st.width > 20000 || st.plane_rows > 20000 ||
            (st.plane_rows % 3U) != 0U) {
            fprintf(stderr,
                    "Refusing invalid buffer descriptor: width=%u plane_rows=%u address=0x%08x\n",
                    st.width, st.plane_rows, st.address);
            rc = 1; break;
        }
        if (width == 0) width = st.width;
        if (st.width != width) {
            fprintf(stderr, "Width changed from %u to %u\n", width, st.width);
            rc = 1; break;
        }
        uint64_t bytes64 = (uint64_t)st.width * st.plane_rows;
        if (bytes64 == 0 || bytes64 > 128ULL * 1024ULL * 1024ULL) {
            fprintf(stderr, "Invalid batch size=%" PRIu64 "\n", bytes64);
            rc = 1; break;
        }
        uint32_t bytes = (uint32_t)bytes64;
        uint8_t *batch = malloc(bytes);
        if (!batch) { fprintf(stderr, "Out of memory for batch %u\n", bytes); rc = 1; break; }
        if (read_c3_range(g_fd, st.address, bytes, batch) != 0) {
            free(batch); rc = 1; break;
        }
        uint64_t hash = fnv1a64(batch, bytes);
        if (fwrite(batch, 1, bytes, raw) != bytes) {
            fprintf(stderr, "Failed writing raw output\n");
            free(batch); rc = 1; break;
        }
        free(batch);
        ++batch_no;
        uint32_t rgb_rows = st.plane_rows / 3U;
        total_rgb_rows += rgb_rows;
        total_bytes += bytes;
        fprintf(batch_log,
                "%u\t%u\t%u\t%u\t%u\t0x%08x\t%u\t%016" PRIx64 "\n",
                batch_no, st.code, st.width, st.plane_rows, rgb_rows,
                st.address, bytes, hash);
        fflush(batch_log); fflush(raw);
        printf("BATCH=%u address=0x%08x bytes=%u rgb_rows=%u total_rows=%" PRIu64 "\n",
               batch_no, st.address, bytes, rgb_rows, total_rgb_rows);
        fflush(stdout);

        if (run_ops_file(g_fd, next_ops, "NEXT_BUFFER", false) != 0) {
            fprintf(stderr, "Failed requesting next buffer\n"); rc = 1; break;
        }

        /*
         * NEXT_BUFFER now ends immediately before the next inner READ.
         * The next poll must perform READ + ff04 + ff06 atomically.
         */
        include_initial_status_sync = true;
    }
    fclose(raw);
    fclose(batch_log);

    if (g_stop) {
        fprintf(stderr, "Interrupted by user\n"); rc = 130;
    }

cleanup:
    if (g_scan_started) {
        printf("[CLEANUP] sending captured normal RELEASE sequence\n");
        (void)run_ops_file(g_fd, g_finish_ops, "SCAN_FINISH", true);
        g_scan_started = false;
    }
    if (g_fd >= 0) {
        flock(g_fd, LOCK_UN);
        close(g_fd);
        g_fd = -1;
    }

    if (rc == 0) {
        struct stat st;
        if (stat(raw_path, &st) != 0 || width == 0 || total_rgb_rows == 0 ||
            (uint64_t)st.st_size != total_bytes ||
            total_bytes != (uint64_t)width * total_rgb_rows * 3ULL) {
            fprintf(stderr, "Output consistency check failed\n");
            rc = 1;
        } else if (write_ppm_from_line_planar(raw_path, ppm_path, width,
                                              total_rgb_rows) != 0) {
            fprintf(stderr, "PPM conversion failed\n");
            rc = 1;
        } else {
            FILE *m = fopen(meta_path, "w");
            if (m) {
                fprintf(m,
                        "{\n"
                        "  \"device\": \"IRIScan Express 4\",\n"
                        "  \"usb_id\": \"0a38:0161\",\n"
                        "  \"mode\": \"Color\",\n"
                        "  \"resolution_dpi\": 300,\n"
                        "  \"width_pixels\": %u,\n"
                        "  \"height_pixels\": %" PRIu64 ",\n"
                        "  \"channels\": 3,\n"
                        "  \"raw_layout\": \"per-line planar R,G,B\",\n"
                        "  \"batches\": %u,\n"
                        "  \"raw_bytes\": %" PRIu64 ",\n"
                        "  \"raw_file\": \"%s\",\n"
                        "  \"ppm_file\": \"%s\"\n"
                        "}\n",
                        width, total_rgb_rows, batch_no, total_bytes,
                        raw_path, ppm_path);
                fclose(m);
            }
            printf("RESULT=SCAN_CAPTURED_AND_DECODED\n");
            printf("WIDTH=%u\nHEIGHT=%" PRIu64 "\nBATCHES=%u\nRAW=%s\nPPM=%s\nMETADATA=%s\n",
                   width, total_rgb_rows, batch_no, raw_path, ppm_path, meta_path);
        }
    }
    return rc;
}
