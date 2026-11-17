Format: 3.0 (quilt)
Source: gst-plugins-bad1.0
Binary: gstreamer1.0-plugins-bad-apps, gstreamer1.0-plugins-bad, gstreamer1.0-opencv, libgstreamer-plugins-bad1.0-0, libgstreamer-opencv1.0-0, libgstreamer-plugins-bad1.0-dev, gir1.2-gst-plugins-bad-1.0, gstreamer1.0-plugins-extra, libgstreamer-plugins-extra1.0-0, libgstreamer-plugins-extra1.0-dev, gir1.2-gst-plugins-extra-1.0
Architecture: any
Version: 1.28.9-0ubuntu0~pd1
Maintainer: Ubuntu Developers <ubuntu-devel-discuss@lists.ubuntu.com>
Uploaders: Sebastian Dröge <slomo@debian.org>, Sjoerd Simons <sjoerd@debian.org>, Marc Leeman <marc.leeman@gmail.com>
Homepage: https://gstreamer.freedesktop.org
Standards-Version: 4.7.3
Vcs-Browser: https://salsa.debian.org/gstreamer-team/gst-plugins-bad1.0/
Vcs-Git: https://salsa.debian.org/gstreamer-team/gst-plugins-bad1.0.git
Testsuite: autopkgtest
Testsuite-Triggers: @builddeps@, build-essential, gstreamer1.0-validate, python3-gi, xauth, xvfb
Build-Depends: debhelper-compat (= 13), dh-sequence-gir, flite-dev, gir1.2-gobject-2.0-dev, gir1.2-gst-1.0-dev, gir1.2-gstaudio-1.0-dev, gir1.2-gstbase-1.0-dev, gir1.2-gstgl-1.0-dev, gir1.2-gstpbutils-1.0-dev, gir1.2-gstsdp-1.0-dev, gir1.2-gsttag-1.0-dev, gir1.2-gstvideo-1.0-dev, gir1.2-vulkan-1.0-dev, glslc, gobject-introspection (>= 1.80), gstreamer1.0-plugins-base (>= 1.28.0), gstreamer1.0-plugins-good (>= 1.28.0) <!nocheck>, gstreamer1.0-tools, ladspa-sdk, libaom-dev, libasound2-dev (>= 0.9.1) [linux-any], libass-dev (>= 0.10.4), libavtp-dev, libbluetooth-dev (>= 5) [linux-any], libbs2b-dev (>= 3.1.0), libbz2-dev, libcairo2-dev, libchromaprint-dev, libcurl4-gnutls-dev (>= 7.55.0), libdc1394-dev (>= 2.2.5) [linux-any], libdca-dev, libde265-dev (>= 0.9), libdrm-dev (>= 2.4.98) [linux-any], libdvdnav-dev (>= 4.1.2) [!hurd-any], libexempi-dev, libexif-dev (>= 0.6.16), libfaad-dev (>= 2.7), libfluidsynth-dev (>= 1.0), libfreeaptx-dev (>= 0.1.1) [!i386], libglib2.0-dev (>= 2.68), libgme-dev, libgnutls28-dev (>= 2.11.3), libgsm1-dev, libgstreamer-plugins-base1.0-dev (>= 1.28.9), libgstreamer1.0-dev (>= 1.28.9), libgtk-3-dev (>= 3.15.0), libgudev-1.0-dev (>= 143) [linux-any], libjson-glib-dev, libkate-dev (>= 0.1.7), liblc3-dev, liblcms2-dev (>= 2.7), libldacbt-enc-dev [!s390x !hppa !m68k !powerpc !ppc64 !sparc64], liblilv-dev (>= 0.22), liblrdf0-dev [!i386], libltc-dev (>= 1.1.4) [!i386], libmjpegtools-dev (>= 2.0.0), libmodplug-dev, libmpcdec-dev, libneon27-dev [!i386], libnice-dev (>= 0.1.20), libonnxruntime-dev [amd64 arm64 armhf riscv64], libopenal-dev (>= 1:1.14), libopencv-dev (>= 3.0.0) [amd64 arm64 armel armhf mips64el ppc64el riscv64 s390x alpha powerpc ppc64 sparc64], libopenexr-dev, libopenh264-dev (>= 1.3.0), libopenjp2-7-dev (>= 2.2), libopenmpt-dev, libopenni2-dev (>= 0.26) [!i386], libopus-dev (>= 0.9.4), liborc-0.4-dev (>= 1:0.4.24), libpango1.0-dev (>= 1.22), libpng-dev, libqrencode-dev [!i386], librsvg2-dev (>= 2.36.2), librtmp-dev, libsbc-dev (>= 1.1) [linux-any], libsndfile1-dev (>= 1.0.16), libsoundtouch-dev (>= 1.5.0), libspandsp-dev (>= 0.0.6), libsrt-gnutls-dev, libsrtp2-dev (>= 2.1), libssh2-1-dev (>= 1.4.3), libssl-dev (>= 1.1), libsvtav1enc-dev, libtensorflow-lite-dev [!i386], libusb-1.0-0-dev [linux-any], libva-dev (>= 1.8) [linux-any], libvo-aacenc-dev, libvo-amrwbenc-dev, libvulkan-dev [!i386], libwayland-dev (>= 1.11.0) [linux-any], libwebp-dev (>= 0.2.1), libwebrtc-audio-processing-dev (>= 0.2), libwildmidi-dev (>= 0.4.2), libx11-dev, libx11-xcb-dev, libx265-dev, libxkbcommon-x11-dev, libxml2-dev (>= 2.8), libxvidcore-dev, libzbar-dev (>= 0.9), libzvbi-dev, libzxing-dev (>= 1.4.0) [amd64 arm64 armel armhf mips64el ppc64el riscv64 s390x alpha hppa hurd-i386 m68k powerpc ppc64 sparc64], meson (>= 1.4.0), nettle-dev (>= 3), opencv-data [amd64 arm64 armel armhf mips64el ppc64el riscv64 s390x alpha powerpc ppc64 sparc64], wayland-protocols (>= 1.4) [linux-any], xauth, xvfb
Build-Conflicts: libopenaptx-dev
Package-List:
 gir1.2-gst-plugins-bad-1.0 deb introspection optional arch=any
 gir1.2-gst-plugins-extra-1.0 deb introspection optional arch=any
 gstreamer1.0-opencv deb libs optional arch=amd64,arm64,armel,armhf,mips64el,ppc64el,riscv64,s390x,alpha,powerpc,ppc64,sparc64
 gstreamer1.0-plugins-bad deb libs optional arch=any
 gstreamer1.0-plugins-bad-apps deb utils optional arch=any
 gstreamer1.0-plugins-extra deb libs optional arch=any
 libgstreamer-opencv1.0-0 deb libs optional arch=amd64,arm64,armel,armhf,mips64el,ppc64el,riscv64,s390x,alpha,powerpc,ppc64,sparc64
 libgstreamer-plugins-bad1.0-0 deb libs optional arch=any
 libgstreamer-plugins-bad1.0-dev deb libdevel optional arch=any
 libgstreamer-plugins-extra1.0-0 deb libs optional arch=any
 libgstreamer-plugins-extra1.0-dev deb libdevel optional arch=any
Checksums-Sha1:
 7a5f87dc5996cd8d9415a6075320b5663bce16ef 8394184 gst-plugins-bad1.0_1.28.9.orig.tar.xz
 5faa9e7f3f76884b9e37521d680cca7ec620b080 62404 gst-plugins-bad1.0_1.28.9-0ubuntu0~pd1.debian.tar.xz
Checksums-Sha256:
 4a4e0b7bf84f868378c48f143a7ac3a98923b488a5b74f1a35ba46bc3c43f6b1 8394184 gst-plugins-bad1.0_1.28.9.orig.tar.xz
 29af4140bbc62186dab218f59300a92272221de2fb19847a8aec3eed4f1b7cfa 62404 gst-plugins-bad1.0_1.28.9-0ubuntu0~pd1.debian.tar.xz
Files:
 36b4522c7a19448c78e2baffe040dbe9 8394184 gst-plugins-bad1.0_1.28.9.orig.tar.xz
 b1055d0ed34d123a660ff7b14270bd62 62404 gst-plugins-bad1.0_1.28.9-0ubuntu0~pd1.debian.tar.xz
Original-Maintainer: Maintainers of GStreamer packages <gst-plugins-bad1.0@packages.debian.org>
