#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 defcom5-rockchip
"""ffmali-probe.py — drive libpidesktop-ffmali the way Firefox's DMABufSurfaceYUV does, and check a grid of sampled texels.

Usage:  python3 ffmali-probe.py [path/to/lib]       (default: the Firefox-private copy in /usr/local/lib/...)
        PIDESKTOP_FFMALI=0 python3 ffmali-probe.py  shows the stock behaviour through the same library

One linear dma-buf holds a known pattern (16-bit texel v(x,y) = ((x + 5y) mod 1024) << 6, little-endian, as in a
P010 luma plane).  It is imported as each plane format Firefox uses and bound exactly like Firefox does:
  glGenTextures, glBindTexture(TEXTURE_2D), CLAMP + LINEAR, glEGLImageTargetTexture2DOES, then glGetError == 0
and sampled with an ordinary sampler2D (what WebRender does).  Expected values come from the same bytes:
  R16    (10-bit luma)        .r = v / 65535
  GR88   (8-bit NV12 chroma)  .r = low byte / 255, .g = high byte / 255
  RG88                         .r = high byte / 255, .g = low byte / 255
  GR1616 (10-bit chroma)      .r = v(2x) / 65535, .g = v(2x+1) / 65535   (half width)
  R8     (8-bit luma)         .r = byte(x) / 255                           (double width)
Also times the 4K R16 path with a fresh import + texture per frame (Firefox's shape).
"""
import ctypes as C, array, mmap, os, sys, time

LIB = sys.argv[1] if len(sys.argv) > 1 else '/usr/local/lib/pidesktop-firefox-mali/libEGL.so'
os.environ.setdefault('PIDESKTOP_FFMALI', '1')   # the library only acts in Firefox's processes unless told to
W, H = 1920, 1088                     # R16 texels; pitch W*2
PITCH = W * 2
FW, FH = 240, 16


def fourcc(s):
    return ord(s[0]) | ord(s[1]) << 8 | ord(s[2]) << 16 | ord(s[3]) << 24


R16, GR88, RG88, GR1616, R8 = fourcc('R16 '), fourcc('GR88'), fourcc('RG88'), fourcc('GR32'), fourcc('R8  ')
EGL_OPENGL_ES_API, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT, EGL_NONE = 0x30A0, 0x3040, 0x40, 0x3038
EGL_CONTEXT_CLIENT_VERSION, EGL_WIDTH, EGL_HEIGHT = 0x3098, 0x3057, 0x3056
EGL_LINUX_DMA_BUF_EXT, EGL_LINUX_DRM_FOURCC_EXT = 0x3270, 0x3271
EGL_FD, EGL_OFF, EGL_PITCH, EGL_MLO, EGL_MHI = 0x3272, 0x3273, 0x3274, 0x3443, 0x3444
GL_TEXTURE_2D, GL_TEXTURE0, GL_RGBA32F, GL_RGBA, GL_FLOAT = 0x0DE1, 0x84C0, 0x8814, 0x1908, 0x1406
GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_FRAMEBUFFER_COMPLETE, GL_TRIANGLES = 0x8D40, 0x8CE0, 0x8CD5, 4
GL_MIN, GL_MAG, GL_WS, GL_WT, GL_LINEAR, GL_CLAMP = 0x2801, 0x2800, 0x2802, 0x2803, 0x2601, 0x812F
GL_IFMT, GL_VS, GL_FS, GL_CS, GL_LS = 0x1003, 0x8B31, 0x8B30, 0x8B81, 0x8B82
IFMT = {0x822A: 'R16', 0x8234: 'R16UI', 0x822C: 'RG16', 0x823A: 'RG16UI', 0x8229: 'R8', 0x822B: 'RG8', 0x8232: 'R8UI'}


def log(s=''):
    print(s, flush=True)


lib = C.CDLL(LIB)                     # libEGL and libGL in Firefox's eyes: one object
gbm = C.CDLL('libgbm.so.1')
P, I, U, F = C.c_void_p, C.c_int, C.c_uint, C.c_float


def sig(l, name, res, *args):
    f = getattr(l, name); f.restype = res; f.argtypes = list(args); return f


for n, r, a in (('eglGetDisplay', P, (P,)), ('eglInitialize', U, (P, P, P)), ('eglBindAPI', U, (U,)),
                ('eglGetProcAddress', P, (C.c_char_p,)), ('eglGetError', I, ()),
                ('eglChooseConfig', U, (P, C.POINTER(C.c_int32), C.POINTER(P), I, C.POINTER(C.c_int32))),
                ('eglCreateContext', P, (P, P, P, C.POINTER(C.c_int32))), ('eglMakeCurrent', U, (P, P, P, P)),
                ('glGenTextures', None, (I, C.POINTER(U))), ('glDeleteTextures', None, (I, C.POINTER(U))),
                ('glBindTexture', None, (U, U)), ('glTexParameteri', None, (U, U, I)),
                ('glTexStorage2D', None, (U, I, U, I, I)), ('glGenFramebuffers', None, (I, C.POINTER(U))),
                ('glBindFramebuffer', None, (U, U)), ('glFramebufferTexture2D', None, (U, U, U, U, I)),
                ('glCheckFramebufferStatus', U, (U,)), ('glReadPixels', None, (I, I, I, I, U, U, P)),
                ('glGetTexLevelParameteriv', None, (U, I, U, C.POINTER(I))), ('glGetError', U, ()),
                ('glFinish', None, ()), ('glCreateShader', U, (U,)),
                ('glShaderSource', None, (U, I, C.POINTER(C.c_char_p), P)), ('glCompileShader', None, (U,)),
                ('glGetShaderiv', None, (U, U, C.POINTER(I))), ('glCreateProgram', U, ()),
                ('glAttachShader', None, (U, U)), ('glLinkProgram', None, (U,)), ('glUseProgram', None, (U,)),
                ('glGetUniformLocation', I, (U, C.c_char_p)), ('glUniform1i', None, (I, I)),
                ('glUniform2f', None, (I, F, F)), ('glActiveTexture', None, (U,)), ('glViewport', None, (I, I, I, I)),
                ('glDrawArrays', None, (U, I, I)), ('glGenVertexArrays', None, (I, C.POINTER(U))),
                ('glBindVertexArray', None, (U,))):
    sig(lib, n, r, *a)

dpy = lib.eglGetDisplay(None)
if not dpy or not lib.eglInitialize(dpy, None, None):
    log('no EGL display'); sys.exit(2)
lib.eglBindAPI(EGL_OPENGL_ES_API)
cfg, n = P(), C.c_int32()
lib.eglChooseConfig(dpy, (C.c_int32 * 3)(EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT, EGL_NONE), C.byref(cfg), 1, C.byref(n))
ctx = lib.eglCreateContext(dpy, cfg, None, (C.c_int32 * 3)(EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE))
if not ctx or not lib.eglMakeCurrent(dpy, None, None, ctx):
    log('no surfaceless GLES 3 context'); sys.exit(2)


def proc(name, res, *args):        # Firefox's pfnLoader: eglGetProcAddress only
    a = lib.eglGetProcAddress(name.encode())
    return C.CFUNCTYPE(res, *args)(a) if a else None


createKHR = proc('eglCreateImageKHR', P, P, P, U, P, C.POINTER(C.c_int32))
destroyKHR = proc('eglDestroyImageKHR', U, P, P)
target_gpa = proc('glEGLImageTargetTexture2DOES', None, U, P)
target_dl = C.CFUNCTYPE(None, U, P)(C.cast(lib.glEGLImageTargetTexture2DOES, P).value)   # Firefox's GL loader: dlsym

# ---- the buffer --------------------------------------------------------------------------------------------
vals = array.array('H', [(((x + 5 * y) % 1024) << 6) for y in range(H) for x in range(W)])
raw = vals.tobytes()                  # little-endian host
sig(gbm, 'gbm_create_device', P, I); sig(gbm, 'gbm_bo_create', P, P, U, U, U, U); sig(gbm, 'gbm_bo_get_fd', I, P)
sig(gbm, 'gbm_bo_get_stride', U, P)
dev = gbm.gbm_create_device(os.open('/dev/dri/renderD128', os.O_RDWR))
bo = gbm.gbm_bo_create(dev, PITCH, H, R8, 4 | 16)
if not bo or gbm.gbm_bo_get_stride(bo) != PITCH:
    log('gbm bo allocation failed'); sys.exit(2)
fd = gbm.gbm_bo_get_fd(bo)
m = mmap.mmap(fd, len(raw), mmap.MAP_SHARED, mmap.PROT_WRITE | mmap.PROT_READ); m[:] = raw; m.close()


def v(x, y):
    return vals[y * W + x]


def byte(xb, y):
    return raw[y * PITCH + xb]


# ---- render target + sampler2D program ------------------------------------------------------------------------
rt, fbo, vao = U(), U(), U()
lib.glGenTextures(1, C.byref(rt)); lib.glBindTexture(GL_TEXTURE_2D, rt.value)
lib.glTexStorage2D(GL_TEXTURE_2D, 1, GL_RGBA32F, FW, FH)
lib.glGenFramebuffers(1, C.byref(fbo)); lib.glBindFramebuffer(GL_FRAMEBUFFER, fbo.value)
lib.glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, rt.value, 0)
if lib.glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE:
    log('render target incomplete'); sys.exit(2)
lib.glGenVertexArrays(1, C.byref(vao)); lib.glBindVertexArray(vao.value); lib.glViewport(0, 0, FW, FH)
VS = b'''#version 300 es
void main() { vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2)); gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0); }'''
FS = b'''#version 300 es
precision highp float; uniform highp sampler2D t; uniform vec2 tsize; uniform vec2 stp; out vec4 o;
void main() { o = texture(t, (floor(gl_FragCoord.xy) * stp + 0.5) / tsize); }'''


def shader(kind, src):
    s = lib.glCreateShader(kind); arr = (C.c_char_p * 1)(src); lib.glShaderSource(s, 1, arr, None); lib.glCompileShader(s)
    return s


prog = lib.glCreateProgram(); lib.glAttachShader(prog, shader(GL_VS, VS)); lib.glAttachShader(prog, shader(GL_FS, FS))
lib.glLinkProgram(prog)


def import_img(fmt, tw):
    a = (C.c_int32 * 17)(EGL_WIDTH, tw, EGL_HEIGHT, H, EGL_LINUX_DRM_FOURCC_EXT, fmt, EGL_FD, fd, EGL_OFF, 0,
                         EGL_PITCH, PITCH, EGL_MLO, 0, EGL_MHI, 0, EGL_NONE)
    return createKHR(dpy, None, EGL_LINUX_DMA_BUF_EXT, None, a)


def firefox_bind(img, use_dlsym=False):
    t = U(); lib.glGenTextures(1, C.byref(t)); lib.glBindTexture(GL_TEXTURE_2D, t.value)
    for p_, val in ((GL_WS, GL_CLAMP), (GL_WT, GL_CLAMP), (GL_MAG, GL_LINEAR), (GL_MIN, GL_LINEAR)):
        lib.glTexParameteri(GL_TEXTURE_2D, p_, val)
    (target_dl if use_dlsym else target_gpa)(GL_TEXTURE_2D, img)
    return t, lib.glGetError()


def sample(tex, tw, step):
    lib.glUseProgram(prog); lib.glActiveTexture(GL_TEXTURE0); lib.glBindTexture(GL_TEXTURE_2D, tex)
    lib.glUniform1i(lib.glGetUniformLocation(prog, b't'), 0)
    lib.glUniform2f(lib.glGetUniformLocation(prog, b'tsize'), float(tw), float(H))
    lib.glUniform2f(lib.glGetUniformLocation(prog, b'stp'), float(step[0]), float(step[1]))
    lib.glBindFramebuffer(GL_FRAMEBUFFER, fbo.value); lib.glDrawArrays(GL_TRIANGLES, 0, 3)
    out = (C.c_float * (FW * FH * 4))(); lib.glReadPixels(0, 0, FW, FH, GL_RGBA, GL_FLOAT, out)
    return out


def ifmt(tex):
    r = I(0); lib.glBindTexture(GL_TEXTURE_2D, tex)
    lib.glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_IFMT, C.byref(r)); lib.glGetError()
    return IFMT.get(r.value, hex(r.value))


CASES = [  # name, fourcc, texture width, sample step, [(channel, expected(tx, ty))]
    ('R16    10-bit luma', R16, W, (8, 68), [(0, lambda x, y: v(x, y) / 65535)]),
    ('GR88   8-bit chroma (NV12 plane 1)', GR88, W, (8, 68), [(0, lambda x, y: byte(2 * x, y) / 255), (1, lambda x, y: byte(2 * x + 1, y) / 255)]),
    ('RG88   8-bit chroma, swapped', RG88, W, (8, 68), [(0, lambda x, y: byte(2 * x + 1, y) / 255), (1, lambda x, y: byte(2 * x, y) / 255)]),
    ('GR1616 10-bit chroma (P010 plane 1)', GR1616, W // 2, (4, 68), [(0, lambda x, y: v(2 * x, y) / 65535), (1, lambda x, y: v(2 * x + 1, y) / 65535)]),
    ('R8     8-bit luma (NV12 plane 0)', R8, PITCH, (16, 68), [(0, lambda x, y: byte(x, y) / 255)]),
]
log(f'library: {LIB}   PIDESKTOP_FFMALI={os.environ.get("PIDESKTOP_FFMALI", "(unset)")}')
ok_all = True
for name, fmt, tw, step, chans in CASES:
    for use_dl in (False, True):
        img = import_img(fmt, tw)
        if not img:
            log(f'  ✘ {name:<38} import refused (EGL error 0x{lib.eglGetError():x})'); ok_all = False; break
        tex, err = firefox_bind(img, use_dl)
        px = sample(tex.value, tw, step)
        bad, worst = 0, 0.0
        for fy in range(FH):
            for fx in range(FW):
                for ch, exp in chans:
                    d = abs(px[(fy * FW + fx) * 4 + ch] - exp(fx * step[0], fy * step[1])); worst = max(worst, d)
                    bad += d > 2e-4
        total = FW * FH * len(chans); good = bad == 0 and err == 0
        ok_all &= good
        log(f'  {"✔" if good else "✘"} {name:<38} via {"dlsym           " if use_dl else "eglGetProcAddress"}  '
            f'texture {ifmt(tex.value):<6} glGetError {err:#x}  {total - bad}/{total} exact  max err {worst:.4f}')
        lib.glDeleteTextures(1, C.byref(tex)); destroyKHR(dpy, img)

# ---- cost: Firefox's shape, 4K luma, fresh import + texture each frame ------------------------------------------
W4, H4 = 3840, 2160
bo4 = gbm.gbm_bo_create(dev, W4 * 2, H4, R8, 4 | 16); fd4 = gbm.gbm_bo_get_fd(bo4)
a4 = (C.c_int32 * 17)(EGL_WIDTH, W4, EGL_HEIGHT, H4, EGL_LINUX_DRM_FOURCC_EXT, R16, EGL_FD, fd4, EGL_OFF, 0,
                      EGL_PITCH, W4 * 2, EGL_MLO, 0, EGL_MHI, 0, EGL_NONE)
N = 60; lib.glFinish(); t0 = time.perf_counter()
for _ in range(N):
    im = createKHR(dpy, None, EGL_LINUX_DMA_BUF_EXT, None, a4); t, _e = firefox_bind(im)
    lib.glDeleteTextures(1, C.byref(t)); destroyKHR(dpy, im)
lib.glFinish()
log(f'  4K R16 plane, fresh import + bind each frame: {(time.perf_counter() - t0) * 1000 / N:.2f} ms/frame')
log('RESULT: ' + ('all exact' if ok_all else 'MISMATCH'))
sys.exit(0 if ok_all else 1)
