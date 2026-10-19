/* SPDX-License-Identifier: LGPL-2.1-or-later
 * Copyright (C) 2026 defcom5-rockchip
 *
 * libpidesktop-ffmali — lets an unmodified Firefox use the hardware video decoder with Arm's proprietary Mali GL driver.
 * Not part of Firefox; not made or endorsed by Mozilla.
 *
 * Firefox imports each plane of a VA-API video frame as its own EGLImage and samples it with an ordinary float
 * sampler.  Arm's libmali (g24p0 on RK3588) breaks that two ways:
 *   8-bit  — it offers no two-channel 8-bit dma-buf format: the NV12 chroma plane (DRM_FORMAT_GR88, or RG88)
 *            does not import at all (EGL_BAD_MATCH), and Firefox falls back to software decoding.
 *   10-bit — it imports a DRM_FORMAT_R16 plane (P010 luma) as GL_R16UI, an integer texture, which a float sampler
 *            reads as 0: the picture is dark with only colour left.  (A newer driver, g29p1, also imported GR1616
 *            as GL_RG16UI when tested on 2026-10-09.)
 * This library sits between Firefox and libmali and works around both without touching Firefox:
 *   eglCreateImage(KHR)          a GR88/RG88 import the driver refuses is retried as R16 (same two bytes per
 *                                texel, same pitch) and remembered;
 *   glEGLImageTargetTexture2DOES binding a remembered image to a TEXTURE_2D first binds it to a scratch texture
 *                                and asks the driver what it made; an integer texture is copied with
 *                                glCopyImageSubData into storage of the normalised format of the same texel size
 *                                (R16UI->R16, RG16UI->RG16, and a retried GR88->RG8) on the caller's own texture.
 * Everything else passes straight through, and a plane that cannot be fixed up raises a GL error instead of binding
 * an integer texture, so Firefox fails cleanly (software decode) rather than drawing a dark or green frame.
 *
 * It is installed only in /usr/local/lib/pidesktop-firefox-mali, which Plaid Pi's Firefox launcher puts first on
 * LD_LIBRARY_PATH, under the names libEGL.so and libGL.so: Firefox tries those names first (before the .so.1 ones
 * that programs normally load), gets eglGetProcAddress from it (which this library wraps) and dlsym()s GL functions
 * from it.  Programs Firefox starts inherit the directory but load libEGL.so.1 / libGL.so.1, which are not this
 * library; and the library only acts inside processes whose executable is under /usr/lib/firefox/ — anywhere else
 * it is a pure pass-through.  Like the libEGL stub in Rockchip's libmali package it depends on libmali-hook.so.1 and
 * then libmali.so.1, so every symbol it does not define resolves exactly as it would through the stub.
 *
 * What it relies on in Firefox (checked against Firefox 157 and upstream's 159 sources): EGL and GL are loaded by the
 * names above; eglCreateImageKHR/eglDestroyImageKHR come from eglGetProcAddress and GL functions from a dlsym on the
 * same object; each decoded frame's planes get a fresh EGLImage and TEXTURE_2D texture, bound once and only sampled
 * (never rendered into: Plaid Pi's Firefox policy locks off the two settings that would render into them,
 * media.ffmpeg.vaapi.force-surface-zero-copy and gfx.webrender.compositor); images are destroyed through the pointers
 * this library hands out.  If a future Firefox changes this, re-test with ffmali-probe.py and in Firefox.
 *
 * Environment: PIDESKTOP_FFMALI=0 turns it into a pure pass-through; PIDESKTOP_FFMALI=1 enables it in any process
 * (for tests); PIDESKTOP_FFMALI_LOG=1 logs every action to stderr (otherwise only the first substitution and the first
 * copy of each kind are logged, once per process).
 *
 * Build: see build.sh next to this file (links -Bsymbolic-functions against libmali-hook.so.1 and libmali.so.1).
 * Measured 2026-10-12 on an Orange Pi 5B (libmali g24p0, Firefox 157.0 from Ubuntu's Mozilla Team PPA, unmodified):
 * ffmali-probe.py imports R16, GR88, RG88, GR1616 and R8 planes the way Firefox does and every sampled texel matches
 * the source bytes through both eglGetProcAddress and dlsym, glGetError 0 (with PIDESKTOP_FFMALI=0, R16 reads ~0 and
 * GR88/RG88 are refused).  In Firefox, 1080p 24 fps H.264 (8-bit), VP9 and AV1 (8- and 10-bit) clips decode on the
 * VPU.  A 4K luma plane's import and copy take ~2.2-2.5 ms per frame in the probe.  Not yet measured: Firefox's
 * picture against a reference (checked by eye only), 4K and 10-bit 4K60 pacing in Firefox, HEVC.
 *
 * Written with an LLM assistant (Anthropic's Claude), which drafted this library, build.sh and ffmali-probe.py and
 * ran the probe and the Firefox tests on the board; the maintainer directs and reviews the work and decides what
 * ships.
 */
const char pidesktop_ffmali_version[] = "libpidesktop-ffmali 1.1";
#define _GNU_SOURCE
#include <dlfcn.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* ---- the few EGL/GL types and constants needed (no system headers: builds anywhere) ---------------------- */
typedef void *EGLDisplay, *EGLContext, *EGLImage, *EGLClientBuffer;
typedef int32_t EGLint;
typedef unsigned int EGLenum, EGLBoolean;
typedef intptr_t EGLAttrib;
typedef unsigned int GLenum, GLuint;
typedef int GLint, GLsizei;
typedef void (*fn_t)(void);

#define EGL_NONE                   0x3038
#define EGL_LINUX_DMA_BUF_EXT      0x3270
#define EGL_LINUX_DRM_FOURCC_EXT   0x3271
#define GL_TEXTURE_2D              0x0DE1
#define GL_TEXTURE_BINDING_2D      0x8069
#define GL_TEXTURE_WIDTH           0x1000
#define GL_TEXTURE_HEIGHT          0x1001
#define GL_TEXTURE_INTERNAL_FORMAT 0x1003
#define GL_TEXTURE_MAG_FILTER      0x2800
#define GL_TEXTURE_MIN_FILTER      0x2801
#define GL_NEAREST                 0x2600
#define GL_TEXTURE_IMMUTABLE_FORMAT 0x912F
#define GL_TEXTURE_SWIZZLE_R       0x8E42
#define GL_TEXTURE_SWIZZLE_G       0x8E43
#define GL_RED                     0x1903
#define GL_GREEN                   0x1904
#define GL_R8                      0x8229
#define GL_RG8                     0x822B
#define GL_R16                     0x822A
#define GL_RG16                    0x822C
#define GL_R8UI                    0x8232
#define GL_RG8UI                   0x8238
#define GL_R16UI                   0x8234
#define GL_RG16UI                  0x823A
#define GL_R8I                     0x8231
#define GL_R16I                    0x8233
#define GL_RG8I                    0x8237
#define GL_RG16I                   0x8239
#define EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT 0x3443
#define EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT 0x3444

#define FOURCC(a, b, c, d) ((uint32_t)(a) | (uint32_t)(b) << 8 | (uint32_t)(c) << 16 | (uint32_t)(d) << 24)
#define DRM_R16    FOURCC('R', '1', '6', ' ')
#define DRM_GR88   FOURCC('G', 'R', '8', '8')
#define DRM_RG88   FOURCC('R', 'G', '8', '8')
#define DRM_GR1616 FOURCC('G', 'R', '3', '2')
#define DRM_RG1616 FOURCC('R', 'G', '3', '2')

/* ---- real entry points ----------------------------------------------------------------------------------- */
typedef fn_t (*PFN_getproc)(const char *);
typedef EGLImage (*PFN_createKHR)(EGLDisplay, EGLContext, EGLenum, EGLClientBuffer, const EGLint *);
typedef EGLImage (*PFN_create15)(EGLDisplay, EGLContext, EGLenum, EGLClientBuffer, const EGLAttrib *);
typedef EGLBoolean (*PFN_destroy)(EGLDisplay, EGLImage);
typedef void (*PFN_target)(GLenum, void *);
typedef void (*PFN_gen)(GLsizei, GLuint *);
typedef void (*PFN_bind)(GLenum, GLuint);
typedef void (*PFN_texpi)(GLenum, GLenum, GLint);
typedef void (*PFN_getiv)(GLenum, GLint *);
typedef void (*PFN_getlevel)(GLenum, GLint, GLenum, GLint *);
typedef void (*PFN_gettexiv)(GLenum, GLenum, GLint *);
typedef void (*PFN_storage)(GLenum, GLsizei, GLenum, GLsizei, GLsizei);
typedef void (*PFN_copy)(GLuint, GLenum, GLint, GLint, GLint, GLint, GLuint, GLenum, GLint, GLint, GLint, GLint,
                         GLsizei, GLsizei, GLsizei);

static struct {
    PFN_getproc getproc;
    PFN_createKHR create_khr;
    PFN_create15 create15;
    PFN_destroy destroy_khr, destroy15;
    PFN_target target;
    PFN_gen gen, del;
    PFN_bind bindtex;
    PFN_texpi texpi;
    PFN_getiv getiv;
    PFN_getlevel getlevel;
    PFN_gettexiv gettexiv;
    PFN_storage storage;
    PFN_copy copy;
} R;

static int enabled = 1, verbose = 0;
static pthread_once_t once = PTHREAD_ONCE_INIT;

#define LOG(...) fprintf(stderr, "pidesktop-ffmali: " __VA_ARGS__)
#define LOG_ONCE(flag, ...) do { static int flag; if (verbose || !__atomic_exchange_n(&flag, 1, __ATOMIC_RELAXED)) LOG(__VA_ARGS__); } while (0)

static void init(void)
{
    const char *e = getenv("PIDESKTOP_FFMALI_LOG");
    if (e && e[0] && e[0] != '0') verbose = 1;
    e = getenv("PIDESKTOP_FFMALI");
    if (e && e[0] == '0') enabled = 0;
    else if (!(e && e[0] == '1')) {                         /* default: only inside Firefox's own processes */
        char exe[256];
        ssize_t n = readlink("/proc/self/exe", exe, sizeof exe - 1);
        if (n <= 0) enabled = 0;
        else { exe[n] = 0; if (strncmp(exe, "/usr/lib/firefox/", 17) != 0) enabled = 0; }
        if (verbose) LOG("pid %d: %s -> %s\n", (int)getpid(), n > 0 ? exe : "?", enabled ? "active" : "pass-through");
    }
    /* Our DT_NEEDED entries are libmali-hook.so.1 then libmali.so.1, so these are already loaded; dlsym on the
       hook's handle searches the hook first, then libmali — the same resolution Arm's libEGL stub gives. */
    void *h = dlopen("libmali-hook.so.1", RTLD_NOW | RTLD_NOLOAD);
    if (!h) h = dlopen("libmali.so.1", RTLD_NOW | RTLD_NOLOAD);
    if (!h) { LOG("libmali not loaded — pass-through only\n"); enabled = 0; return; }
    R.getproc = (PFN_getproc)dlsym(h, "eglGetProcAddress");
    if (!R.getproc) { LOG("no eglGetProcAddress — pass-through only\n"); enabled = 0; return; }
#define REAL(field, type, name) R.field = (type)R.getproc(name)
    REAL(create_khr, PFN_createKHR, "eglCreateImageKHR");
    REAL(create15, PFN_create15, "eglCreateImage");
    REAL(destroy_khr, PFN_destroy, "eglDestroyImageKHR");
    REAL(destroy15, PFN_destroy, "eglDestroyImage");
    REAL(target, PFN_target, "glEGLImageTargetTexture2DOES");
    REAL(gen, PFN_gen, "glGenTextures");
    REAL(del, PFN_gen, "glDeleteTextures");
    REAL(bindtex, PFN_bind, "glBindTexture");
    REAL(texpi, PFN_texpi, "glTexParameteri");
    REAL(getiv, PFN_getiv, "glGetIntegerv");
    REAL(getlevel, PFN_getlevel, "glGetTexLevelParameteriv");
    REAL(gettexiv, PFN_gettexiv, "glGetTexParameteriv");
    REAL(storage, PFN_storage, "glTexStorage2D");
    REAL(copy, PFN_copy, "glCopyImageSubData");
    if (!R.copy) REAL(copy, PFN_copy, "glCopyImageSubDataEXT");
    if (!R.copy) REAL(copy, PFN_copy, "glCopyImageSubDataOES");
#undef REAL
    if (verbose) LOG("init in pid %d: getproc=%p create_khr=%p target=%p copy=%p\n", (int)getpid(), (void *)R.getproc, (void *)R.create_khr, (void *)R.target, (void *)R.copy);
    if (!R.target || !R.gen || !R.del || !R.bindtex || !R.texpi || !R.getiv || !R.getlevel || !R.gettexiv ||
        !R.storage || !R.copy) {
        LOG("GL entry points missing (glCopyImageSubData needs GLES 3.2) — pass-through only\n");
        enabled = 0;
    }
}
static inline void ensure(void) { pthread_once(&once, init); }

/* ---- images we may have to fix up at bind time ------------------------------------------------------------ */
/* A growing table (never evicts a live entry: an evicted image would be bound raw — dark or green).  Firefox keeps a
   few dozen images alive; thousands mean images the caller never destroyed, which is logged once. */
struct ent { EGLImage img; uint32_t asked; int retried; };
static struct ent *tab;
static size_t tabcap;
static pthread_mutex_t tab_lock = PTHREAD_MUTEX_INITIALIZER;

static void remember(EGLImage img, uint32_t asked, int retried)
{
    pthread_mutex_lock(&tab_lock);
    size_t free_i = (size_t)-1;
    for (size_t i = 0; i < tabcap; i++) {
        if (tab[i].img == img) { tab[i].asked = asked; tab[i].retried = retried; pthread_mutex_unlock(&tab_lock); return; }
        if (!tab[i].img && free_i == (size_t)-1) free_i = i;
    }
    if (free_i == (size_t)-1) {
        size_t ncap = tabcap ? tabcap * 2 : 64;
        struct ent *n = realloc(tab, ncap * sizeof *n);
        if (!n) { pthread_mutex_unlock(&tab_lock); return; }  /* out of memory: the bind then fails cleanly */
        memset(n + tabcap, 0, (ncap - tabcap) * sizeof *n);
        free_i = tabcap; tab = n; tabcap = ncap;
        if (tabcap > 4096) LOG_ONCE(leak, "more than 4096 live images: the caller is not destroying them\n");
    }
    tab[free_i].img = img; tab[free_i].asked = asked; tab[free_i].retried = retried;
    pthread_mutex_unlock(&tab_lock);
}
static struct ent lookup(EGLImage img)
{
    struct ent r = { 0 };
    pthread_mutex_lock(&tab_lock);
    for (size_t i = 0; i < tabcap; i++) if (tab[i].img == img) { r = tab[i]; break; }
    pthread_mutex_unlock(&tab_lock);
    return r;
}
static void forget(EGLImage img)
{
    pthread_mutex_lock(&tab_lock);
    for (size_t i = 0; i < tabcap; i++) if (tab[i].img == img) { tab[i].img = NULL; tab[i].asked = 0; tab[i].retried = 0; }
    pthread_mutex_unlock(&tab_lock);
}

/* Formats whose import we watch: the two-channel 8-bit ones (retried as R16) and the 16-bit ones the driver may
   import as integer textures. */
static int watched(uint32_t f) { return f == DRM_R16 || f == DRM_GR1616 || f == DRM_RG1616 || f == DRM_GR88 || f == DRM_RG88; }

/* ---- eglCreateImage(KHR) ---------------------------------------------------------------------------------- */
/* Scan an attribute list (at most 64 pairs): the index of the fourcc's value, the list length (pairs*2, pointing at
   EGL_NONE; -1 if unterminated) and whether plane 0 is linear (no modifier given, or modifier 0 = LINEAR) — R16 is
   only a safe reinterpretation of GR88/RG88 for a linear buffer. */
#define SCAN_ATTRS(T, a, k, n, linear) do { k = -1; n = -1; linear = 1;                                    \
        if (a) for (int i_ = 0; i_ < 128; i_ += 2) {                                                        \
            if (a[i_] == EGL_NONE) { n = i_; break; }                                                       \
            if (a[i_] == EGL_LINUX_DRM_FOURCC_EXT) k = i_ + 1;                                              \
            if ((a[i_] == EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT || a[i_] == EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT)  \
                && a[i_ + 1] != 0) linear = 0;                                                              \
        } } while (0)

EGLImage eglCreateImageKHR(EGLDisplay dpy, EGLContext ctx, EGLenum target, EGLClientBuffer buf, const EGLint *attrs)
{
    ensure();
    if (!R.create_khr) return NULL;
    EGLImage img = R.create_khr(dpy, ctx, target, buf, attrs);
    if (!enabled || target != EGL_LINUX_DMA_BUF_EXT) return img;
    int k, n, linear;
    SCAN_ATTRS(EGLint, attrs, k, n, linear);
    if (k < 0) { if (img) forget(img); return img; }
    uint32_t f = (uint32_t)attrs[k];
    int retried = 0;
    if (verbose) LOG("eglCreateImageKHR fourcc %.4s -> %p\n", (const char *)&f, img);
    if (!img && (f == DRM_GR88 || f == DRM_RG88) && linear && n >= 0) {
        EGLint a2[130]; memcpy(a2, attrs, (size_t)(n + 1) * sizeof(EGLint)); a2[k] = (EGLint)DRM_R16;
        img = R.create_khr(dpy, ctx, target, buf, a2);
        retried = img != NULL;
        if (verbose) LOG("  retried as R16 -> %p\n", img);
        if (img) LOG_ONCE(sub8, "two-channel 8-bit plane refused by the driver; imported as R16 (copied into RG8 at bind)\n");
    }
    if (img) { if (watched(f)) remember(img, f, retried); else forget(img); }   /* forget: a recycled handle */
    return img;
}

EGLImage eglCreateImage(EGLDisplay dpy, EGLContext ctx, EGLenum target, EGLClientBuffer buf, const EGLAttrib *attrs)
{
    ensure();
    if (!R.create15) return NULL;
    EGLImage img = R.create15(dpy, ctx, target, buf, attrs);
    if (!enabled || target != EGL_LINUX_DMA_BUF_EXT) return img;
    int k, n, linear;
    SCAN_ATTRS(EGLAttrib, attrs, k, n, linear);
    if (k < 0) { if (img) forget(img); return img; }
    uint32_t f = (uint32_t)attrs[k];
    int retried = 0;
    if (verbose) LOG("eglCreateImage fourcc %.4s -> %p\n", (const char *)&f, img);
    if (!img && (f == DRM_GR88 || f == DRM_RG88) && linear && n >= 0) {
        EGLAttrib a2[130]; memcpy(a2, attrs, (size_t)(n + 1) * sizeof(EGLAttrib)); a2[k] = (EGLAttrib)DRM_R16;
        img = R.create15(dpy, ctx, target, buf, a2);
        retried = img != NULL;
        if (verbose) LOG("  retried as R16 -> %p\n", img);
        if (img) LOG_ONCE(sub8b, "two-channel 8-bit plane refused by the driver; imported as R16 (copied into RG8 at bind)\n");
    }
    if (img) { if (watched(f)) remember(img, f, retried); else forget(img); }
    return img;
}

EGLBoolean eglDestroyImageKHR(EGLDisplay dpy, EGLImage img)
{
    ensure();
    forget(img);
    return R.destroy_khr ? R.destroy_khr(dpy, img) : 0;
}

EGLBoolean eglDestroyImage(EGLDisplay dpy, EGLImage img)
{
    ensure();
    forget(img);
    return R.destroy15 ? R.destroy15(dpy, img) : 0;
}

/* ---- glEGLImageTargetTexture2DOES ------------------------------------------------------------------------- */
void glEGLImageTargetTexture2DOES(GLenum target, void *image)
{
    ensure();
    if (!R.target) return;
    struct ent e = (enabled && target == GL_TEXTURE_2D) ? lookup(image) : (struct ent){ 0 };
    uint32_t asked = e.asked;
    if (!asked) { R.target(target, image); return; }

    GLint t = 0;
    R.getiv(GL_TEXTURE_BINDING_2D, &t);
    if (!t) { R.target(target, image); return; }
    GLuint dst = (GLuint)t, src = 0;

    /* Bind the image to a scratch texture to see what the driver made of it.  NEAREST: an integer texture with
       the default (mipmapped) or LINEAR filters is incomplete, and glCopyImageSubData then copies nothing. */
    R.gen(1, &src);
    R.bindtex(GL_TEXTURE_2D, src);
    R.texpi(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    R.texpi(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    R.target(GL_TEXTURE_2D, image);
    GLint ifmt = 0, w = 0, h = 0;
    R.getlevel(GL_TEXTURE_2D, 0, GL_TEXTURE_INTERNAL_FORMAT, &ifmt);
    R.getlevel(GL_TEXTURE_2D, 0, GL_TEXTURE_WIDTH, &w);
    R.getlevel(GL_TEXTURE_2D, 0, GL_TEXTURE_HEIGHT, &h);

    GLenum norm = 0; int swap_rg = 0;
    if (asked == DRM_GR88 || asked == DRM_RG88) {           /* imported as R16 by us, or natively as a 2x8 format */
        if (ifmt == GL_R16UI || ifmt == GL_R16 || ifmt == GL_RG8UI) { norm = GL_RG8; swap_rg = (asked == DRM_RG88); }
    } else if (ifmt == GL_R16UI || ifmt == GL_R16I)   norm = GL_R16;    /* same view class: raw copy is exact */
    else if (ifmt == GL_RG16UI || ifmt == GL_RG16I)  norm = GL_RG16;
    else if (ifmt == GL_R8UI || ifmt == GL_R8I)      norm = GL_R8;
    else if (ifmt == GL_RG8UI || ifmt == GL_RG8I)    norm = GL_RG8;
    int integer = ifmt == GL_R16UI || ifmt == GL_R16I || ifmt == GL_RG16UI || ifmt == GL_RG16I ||
                  ifmt == GL_R8UI || ifmt == GL_R8I || ifmt == GL_RG8UI || ifmt == GL_RG8I;

    if (!norm || w <= 0 || h <= 0) {
        R.del(1, &src);
        R.bindtex(GL_TEXTURE_2D, dst);
        if (e.retried || integer) {                         /* cannot be fixed up: fail the bind, never bind raw */
            R.bindtex(0, 0);                                /* raises GL_INVALID_ENUM for Firefox's glGetError check */
            LOG_ONCE(nofix, "plane (fourcc %.4s, driver format 0x%x, %dx%d) cannot be fixed up; bind failed on purpose\n",
                     (const char *)&asked, (unsigned)ifmt, w, h);
            return;
        }
        R.target(target, image);                            /* a normalised import: bind it as asked */
        if (verbose) LOG("bind: format 0x%x for fourcc %.4s, no copy needed\n", (unsigned)ifmt, (const char *)&asked);
        return;
    }

    R.bindtex(GL_TEXTURE_2D, dst);
    GLint immutable = 0;
    R.gettexiv(GL_TEXTURE_2D, GL_TEXTURE_IMMUTABLE_FORMAT, &immutable);
    if (!immutable) R.storage(GL_TEXTURE_2D, 1, norm, w, h);
    R.copy(src, GL_TEXTURE_2D, 0, 0, 0, 0, dst, GL_TEXTURE_2D, 0, 0, 0, 0, w, h, 1);
    if (swap_rg) {                                         /* RG88: R is the second byte */
        R.texpi(GL_TEXTURE_2D, GL_TEXTURE_SWIZZLE_R, GL_GREEN);
        R.texpi(GL_TEXTURE_2D, GL_TEXTURE_SWIZZLE_G, GL_RED);
    }
    R.del(1, &src);
    R.bindtex(GL_TEXTURE_2D, dst);
    if (norm == GL_RG8) LOG_ONCE(c8, "8-bit chroma plane copied into RG8 (%dx%d)\n", w, h);
    else LOG_ONCE(c16, "driver imported a plane as integer format 0x%x; copied into normalised 0x%x (%dx%d)\n",
                  (unsigned)ifmt, (unsigned)norm, w, h);
}

/* ---- eglGetProcAddress: hand out the wrappers above, everything else from the hook/driver ---------------- */
/* Linked -Bsymbolic-functions: inside Firefox libmali is already in the global scope, and without it the
   references below to our own exported functions would be interposed by libmali's — Firefox would be handed the
   driver's eglCreateImageKHR and the wrappers would never run (seen on the board, 2026-10-12). */
fn_t eglGetProcAddress(const char *name)
{
    ensure();
    if (verbose && name && (strstr(name, "Image") || strstr(name, "GetProc"))) LOG("eglGetProcAddress(%s)\n", name);
    if (name) {
        if (!strcmp(name, "eglCreateImageKHR"))            return (fn_t)eglCreateImageKHR;
        if (!strcmp(name, "eglCreateImage"))               return (fn_t)eglCreateImage;
        if (!strcmp(name, "eglDestroyImageKHR"))           return (fn_t)eglDestroyImageKHR;
        if (!strcmp(name, "eglDestroyImage"))              return (fn_t)eglDestroyImage;
        if (!strcmp(name, "glEGLImageTargetTexture2DOES")) return (fn_t)glEGLImageTargetTexture2DOES;
    }
    return R.getproc ? R.getproc(name) : NULL;
}
