/*
 * rocm-skip-legacy-gpu.c - LD_PRELOAD shim that stops a pre-Vega AMD GPU from
 * aborting hsa_init() on a mixed-GPU host.
 *
 * Why this exists
 * ---------------
 * ROCr 7.x refuses to create an agent for any KFD node whose doorbell type is
 * not 2 (64-bit PCIe doorbells), in:
 *
 *   projects/rocr-runtime/runtime/hsa-runtime/core/runtime/amd_gpu_agent.cpp:124
 *     if (node_props.Capability.ui32.DoorbellType != 2)
 *       throw AMD::hsa_exception(HSA_STATUS_ERROR,
 *                                "Agent creation failed.\n"
 *                                "The GPU node uses a deprecated doorbell type\n");
 *
 * DiscoverGpu() (amd_topology.cpp) drops a node only for
 * HSA_STATUS_ERROR_INVALID_ISA. A generic HSA_STATUS_ERROR is rethrown, so
 * AMD::Load() fails and hsa_init() returns "a generic error has occurred" for
 * every GPU on the machine, including fully supported ones.
 *
 * KFD reports doorbell type 1 (bits 12..13 of the "capability" word) for
 * Polaris and older ASICs: kfd_topology.c maps CHIP_POLARIS10/11/12 to
 * HSA_CAP_DOORBELL_TYPE_1_0, and kfd_device.c hard-codes doorbell_size 4 for
 * every pre-SOC15 family. No kernel release changes that, and no environment
 * variable of the runtime changes the check (ROCR_VISIBLE_DEVICES filters
 * agents only after the node has been constructed).
 *
 * What it does
 * ------------
 * It rewrites the text of
 *
 *   /sys/class/kfd/kfd/topology/nodes/<N>/properties
 *   /sys/devices/virtual/kfd/kfd/topology/nodes/<N>/properties   (same file)
 *
 * in memory, for the calling process only, before the runtime parses it. It
 * intercepts the sysfs read path (fopen/fopen64 and open/open64/openat/
 * openat64), serves a memfd-backed copy for KFD node property files, and
 * forwards every other call unchanged. Nothing on disk changes and no other
 * process is affected. Only paths that end in
 *
 *   /kfd/topology/nodes/<digits>/properties
 *
 * are touched; memory-bank, cache, io-link and p2p-link properties are not.
 *
 * Modes, selected by ROCM_SKIP_LEGACY_GPU_MODE:
 *
 *   skip (default)
 *       Set "simd_count" to 0, so DiscoverGpu() ignores the node because
 *       NumFComputeCores == 0. Only supported GPUs are enumerated. Proved on
 *       brys: rocminfo lists gfx1201 only, and hipGetDeviceCount returns 1.
 *       This is the default because HIP refuses to enumerate any device while
 *       the legacy agent is present, even after its doorbell bits are fixed.
 *
 *   doorbell
 *       Set the doorbell bits (12..13) of "capability" to 2. The legacy GPU
 *       stays visible as an agent, and hsa_init() succeeds (proved: rocminfo
 *       then lists gfx1201 and the gfx803 card). HIP still reports zero
 *       devices in this mode, so use it only for tools that need HSA up and
 *       want the legacy card in the agent list.
 *
 * Both modes act only on nodes that are GPUs (gfx_target_version != 0) whose
 * doorbell type is already not 2, so a healthy machine is untouched.
 *
 * Build:
 *   cc -shared -fPIC -O2 -o /tmp/rocm-skip.so hack/rocm-skip-legacy-gpu.c -ldl
 *
 * Use:
 *   LD_PRELOAD=/tmp/rocm-skip.so rocminfo
 *   ROCM_SKIP_LEGACY_GPU_MODE=doorbell LD_PRELOAD=/tmp/rocm-skip.so rocminfo
 *   ROCM_SKIP_LEGACY_GPU_DEBUG=1 LD_PRELOAD=/tmp/rocm-skip.so rocminfo  (stderr)
 *
 * Origin: docs/tasks/2026-11/rocm-on-brys/definition.md. Upstream defect:
 * ROCm/rocm-systems issue #8801, fixed by PR #4936 (throw INVALID_ISA instead).
 * Remove this shim once the runtime in use carries that fix.
 */

#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define DOORBELL_SHIFT 12
#define DOORBELL_MASK 0x00003000u
#define DOORBELL_TYPE_2 0x00002000u

typedef int (*open_fn)(const char *, int, ...);
typedef int (*openat_fn)(int, const char *, int, ...);
typedef FILE *(*fopen_fn)(const char *, const char *);

static open_fn real_open;
static open_fn real_open64;
static openat_fn real_openat;
static openat_fn real_openat64;
static fopen_fn real_fopen;
static fopen_fn real_fopen64;

static int shim_debug;

/* Log each rewritten node once per process: libhsakmt opens the file many times. */
static char logged_nodes[16][32];
static int logged_count;

static int already_logged(const char *node) {
  int i;
  for (i = 0; i < logged_count; i++)
    if (strcmp(logged_nodes[i], node) == 0)
      return 1;
  if (logged_count < 16) {
    snprintf(logged_nodes[logged_count], sizeof(logged_nodes[0]), "%s", node);
    logged_count++;
  }
  return 0;
}

static void resolve_real(void) {
  if (real_open && real_open64 && real_openat && real_openat64 && real_fopen &&
      real_fopen64)
    return;
  if (!real_open)
    real_open = (open_fn)dlsym(RTLD_NEXT, "open");
  if (!real_open64)
    real_open64 = (open_fn)dlsym(RTLD_NEXT, "open64");
  if (!real_openat)
    real_openat = (openat_fn)dlsym(RTLD_NEXT, "openat");
  if (!real_openat64)
    real_openat64 = (openat_fn)dlsym(RTLD_NEXT, "openat64");
  if (!real_fopen)
    real_fopen = (fopen_fn)dlsym(RTLD_NEXT, "fopen");
  if (!real_fopen64)
    real_fopen64 = (fopen_fn)dlsym(RTLD_NEXT, "fopen64");
  if (!real_open)
    real_open = real_open64;
  if (!real_open64)
    real_open64 = real_open;
  if (!real_openat)
    real_openat = real_openat64;
  if (!real_openat64)
    real_openat64 = real_openat;
  if (!real_fopen)
    real_fopen = real_fopen64;
  if (!real_fopen64)
    real_fopen64 = real_fopen;
}

/* True only for /sys/.../kfd/topology/nodes/<digits>/properties. */
static int is_node_properties(const char *path) {
  const char *p;
  const char *digits;

  if (!path)
    return 0;
  p = strstr(path, "/kfd/topology/nodes/");
  if (!p)
    return 0;
  digits = p + strlen("/kfd/topology/nodes/");
  p = digits;
  while (*p >= '0' && *p <= '9')
    p++;
  if (p == digits)
    return 0;
  return strcmp(p, "/properties") == 0;
}

static int read_file(const char *path, char *buf, size_t cap, size_t *len) {
  int fd;
  ssize_t n;
  size_t used = 0;

  resolve_real();
  if (!real_open) {
    errno = ENOSYS;
    return -1;
  }
  fd = real_open(path, O_RDONLY);
  if (fd < 0)
    return -1;
  while (used + 1 < cap) {
    n = read(fd, buf + used, cap - used - 1);
    if (n < 0) {
      if (errno == EINTR)
        continue;
      close(fd);
      return -1;
    }
    if (n == 0)
      break;
    used += (size_t)n;
  }
  close(fd);
  buf[used] = '\0';
  *len = used;
  return 0;
}

/* Return the value of "<key> <int>" from a properties file, or 0 if absent. */
static unsigned long long prop_value(const char *buf, const char *key) {
  const char *p = buf;
  size_t klen = strlen(key);

  while (p && *p) {
    if (strncmp(p, key, klen) == 0 && p[klen] == ' ') {
      return strtoull(p + klen + 1, NULL, 0);
    }
    p = strchr(p, '\n');
    if (p)
      p++;
  }
  return 0;
}

/* Replace "<key> <old>" with "<key> <new>" in place. Returns 1 on success. */
static int prop_replace(char *buf, size_t cap, const char *key,
                        unsigned long long value) {
  char *p = buf;
  size_t klen = strlen(key);
  char line[128];
  int n;

  while (p && *p) {
    if (strncmp(p, key, klen) == 0 && p[klen] == ' ') {
      char *eol = strchr(p, '\n');
      n = snprintf(line, sizeof(line), "%s %llu", key, value);
      if (n <= 0 || (size_t)n >= sizeof(line))
        return 0;
      if (eol) {
        size_t old_len = (size_t)(eol - p);
        size_t new_len = (size_t)n;
        if (old_len != new_len) {
          size_t tail = strlen(eol);
          if (strlen(buf) - old_len + new_len + 1 > cap)
            return 0;
          memmove(p + new_len, eol, tail + 1);
        }
        memcpy(p, line, new_len);
      } else {
        if (strlen(buf) + (size_t)n + 2 > cap)
          return 0;
        memcpy(p, line, (size_t)n);
        p[n] = '\n';
        p[n + 1] = '\0';
      }
      return 1;
    }
    p = strchr(p, '\n');
    if (p)
      p++;
  }
  return 0;
}

static int shim_mode_doorbell(void) {
  const char *mode = getenv("ROCM_SKIP_LEGACY_GPU_MODE");
  return mode && strcmp(mode, "doorbell") == 0;
}

/*
 * Build the patched copy of a node properties file. Returns 0 when the file is
 * not a legacy GPU node and no change is needed.
 */
static int build_patched(const char *path, char *out, size_t cap, size_t *outlen) {
  char buf[8192];
  size_t len = 0;
  unsigned long long gfx, capability, simd, doorbell;
  int node_skip;
  char node[32];

  if (read_file(path, buf, sizeof(buf), &len) != 0)
    return 0;

  gfx = prop_value(buf, "gfx_target_version");
  simd = prop_value(buf, "simd_count");
  capability = prop_value(buf, "capability");
  doorbell = (capability & DOORBELL_MASK) >> DOORBELL_SHIFT;

  /* CPU node, already hidden node, or already a 64-bit-doorbell GPU: no-op. */
  if (gfx == 0 || simd == 0 || doorbell == 2)
    return 0;

  if (len + 1 > cap)
    return 0;
  memcpy(out, buf, len + 1);
  node_skip = !shim_mode_doorbell();

  if (node_skip) {
    if (!prop_replace(out, cap, "simd_count", 0))
      return 0;
  } else {
    unsigned long long patched =
        (capability & ~(unsigned long long)DOORBELL_MASK) | DOORBELL_TYPE_2;
    if (!prop_replace(out, cap, "capability", patched))
      return 0;
  }

  *outlen = strlen(out);
  if (shim_debug) {
    const char *p = strstr(path, "/nodes/");
    size_t i = 0;
    if (p) {
      p += strlen("/nodes/");
      while (p[i] && p[i] != '/' && i + 1 < sizeof(node)) {
        node[i] = p[i];
        i++;
      }
    }
    node[i] = '\0';
    if (already_logged(node))
      return 1;
    if (node_skip)
      fprintf(stderr,
              "[rocm-skip] node %s (gfx %llu, doorbell %llu): simd_count -> 0\n",
              node, gfx, doorbell);
    else
      fprintf(stderr,
              "[rocm-skip] node %s (gfx %llu): doorbell %llu -> 2, "
              "capability 0x%llx -> 0x%llx\n",
              node, gfx, doorbell, capability,
              (capability & ~(unsigned long long)DOORBELL_MASK) |
                  DOORBELL_TYPE_2);
  }
  return 1;
}

/* Serve the patched copy as an anonymous fd, or -1 when nothing to do. */
static int patched_fd(const char *path) {
  char out[8192];
  size_t len = 0;
  int fd;
  ssize_t written;
  const char *dbg = getenv("ROCM_SKIP_LEGACY_GPU_DEBUG");

  shim_debug = dbg && *dbg && strcmp(dbg, "0") != 0;
  if (!is_node_properties(path))
    return -1;
  if (!build_patched(path, out, sizeof(out), &len))
    return -1;

  fd = memfd_create("rocm-skip-legacy-gpu", MFD_CLOEXEC);
  if (fd < 0)
    return -1;
  written = write(fd, out, len);
  if (written < 0 || (size_t)written != len) {
    close(fd);
    return -1;
  }
  if (lseek(fd, 0, SEEK_SET) < 0) {
    close(fd);
    return -1;
  }
  return fd;
}

static int is_read_only(int flags) { return (flags & O_ACCMODE) == O_RDONLY; }

int open(const char *path, int flags, ...) {
  mode_t mode = 0;
  int fd;

  resolve_real();
  if (is_read_only(flags)) {
    fd = patched_fd(path);
    if (fd >= 0) {
      if (flags & O_CLOEXEC)
        fcntl(fd, F_SETFD, FD_CLOEXEC);
      return fd;
    }
  }
  if (flags & (O_CREAT | O_TMPFILE)) {
    va_list ap;
    va_start(ap, flags);
    mode = va_arg(ap, mode_t);
    va_end(ap);
  }
  if (!real_open) {
    errno = ENOSYS;
    return -1;
  }
  return real_open(path, flags, mode);
}

int open64(const char *path, int flags, ...) {
  mode_t mode = 0;
  int fd;

  resolve_real();
  if (is_read_only(flags)) {
    fd = patched_fd(path);
    if (fd >= 0) {
      if (flags & O_CLOEXEC)
        fcntl(fd, F_SETFD, FD_CLOEXEC);
      return fd;
    }
  }
  if (flags & (O_CREAT | O_TMPFILE)) {
    va_list ap;
    va_start(ap, flags);
    mode = va_arg(ap, mode_t);
    va_end(ap);
  }
  if (!real_open64) {
    errno = ENOSYS;
    return -1;
  }
  return real_open64(path, flags, mode);
}

int openat(int dirfd, const char *path, int flags, ...) {
  mode_t mode = 0;
  int fd;

  resolve_real();
  if (is_read_only(flags)) {
    fd = patched_fd(path);
    if (fd >= 0) {
      if (flags & O_CLOEXEC)
        fcntl(fd, F_SETFD, FD_CLOEXEC);
      return fd;
    }
  }
  if (flags & (O_CREAT | O_TMPFILE)) {
    va_list ap;
    va_start(ap, flags);
    mode = va_arg(ap, mode_t);
    va_end(ap);
  }
  if (!real_openat) {
    errno = ENOSYS;
    return -1;
  }
  return real_openat(dirfd, path, flags, mode);
}

int openat64(int dirfd, const char *path, int flags, ...) {
  mode_t mode = 0;
  int fd;

  resolve_real();
  if (is_read_only(flags)) {
    fd = patched_fd(path);
    if (fd >= 0) {
      if (flags & O_CLOEXEC)
        fcntl(fd, F_SETFD, FD_CLOEXEC);
      return fd;
    }
  }
  if (flags & (O_CREAT | O_TMPFILE)) {
    va_list ap;
    va_start(ap, flags);
    mode = va_arg(ap, mode_t);
    va_end(ap);
  }
  if (!real_openat64) {
    errno = ENOSYS;
    return -1;
  }
  return real_openat64(dirfd, path, flags, mode);
}

static FILE *fopen_patched(const char *path, const char *mode, fopen_fn real) {
  FILE *f;
  int fd;

  resolve_real();
  if ((mode[0] == 'r') && strchr(mode, '+') == NULL) {
    fd = patched_fd(path);
    if (fd >= 0) {
      f = fdopen(fd, mode);
      if (f)
        return f;
      close(fd);
    }
  }
  if (!real) {
    errno = ENOSYS;
    return NULL;
  }
  return real(path, mode);
}

FILE *fopen(const char *path, const char *mode) {
  resolve_real();
  return fopen_patched(path, mode, real_fopen);
}

FILE *fopen64(const char *path, const char *mode) {
  resolve_real();
  return fopen_patched(path, mode, real_fopen64);
}
