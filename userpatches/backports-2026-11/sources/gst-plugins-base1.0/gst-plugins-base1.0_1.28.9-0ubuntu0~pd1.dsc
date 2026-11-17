Format: 3.0 (quilt)
Source: gst-plugins-base1.0
Binary: gstreamer1.0-plugins-base-apps, libgstreamer-plugins-base1.0-0, libgstreamer-plugins-base1.0-dev, libgstreamer-gl1.0-0, gstreamer1.0-alsa, gstreamer1.0-plugins-base, gstreamer1.0-x, gstreamer1.0-gl, gir1.2-gst-plugins-base-1.0
Architecture: any
Version: 1.28.9-0ubuntu0~pd1
Maintainer: Ubuntu Developers <ubuntu-devel-discuss@lists.ubuntu.com>
Uploaders: Sebastian Dröge <slomo@debian.org>, Sjoerd Simons <sjoerd@debian.org>, Marc Leeman <marc.leeman@gmail.com>
Homepage: https://gstreamer.freedesktop.org
Standards-Version: 4.7.3
Vcs-Browser: https://salsa.debian.org/gstreamer-team/gst-plugins-base1.0/
Vcs-Git: https://salsa.debian.org/gstreamer-team/gst-plugins-base1.0.git
Build-Depends: debhelper-compat (= 13), dh-sequence-gir, dpkg-dev (>= 1.15.1), gir1.2-gio-2.0-dev, gir1.2-gmodule-2.0-dev, gir1.2-gobject-2.0-dev, gir1.2-gst-1.0-dev, gir1.2-gstbase-1.0-dev, gobject-introspection (>= 1.80), pkgconf (>= 0.11.0), meson (>= 1.4.0), xvfb, xauth, libglib2.0-dev (>= 2.62), libgstreamer1.0-dev (>= 1.28.9), liborc-0.4-dev (>= 1:0.4.24), zlib1g-dev (>= 1:1.1.4), libgl-dev, gstreamer1.0-tools, libegl-dev, libgles-dev, libgraphene-1.0-dev, libtheora-dev (>= 1.1), libvorbis-dev (>= 1.3.1), libopus-dev (>= 0.9.4), libogg-dev (>= 1.0), libpango1.0-dev (>= 1.22), libbrotli-dev, libpng-dev, libjpeg-dev, libcdparanoia-dev (>= 3.10.2) [!hurd-any], libvisual-0.4-dev (>= 0.4.0), libx11-xcb-dev, libxi-dev, libxv-dev (>= 6.8.2.dfsg.1-3), libxt-dev (>= 6.8.2.dfsg.1-3), libasound2-dev (>= 0.9.1) [linux-any], libdrm-dev (>= 2.4.55) [linux-any], libgbm-dev [linux-any], libgudev-1.0-dev (>= 147) [linux-any], libwayland-dev (>= 1.11) [linux-any], wayland-protocols (>= 1.15) [linux-any], iso-codes, gir1.2-glib-2.0, gir1.2-freedesktop, gir1.2-gstreamer-1.0
Package-List:
 gir1.2-gst-plugins-base-1.0 deb introspection optional arch=any
 gstreamer1.0-alsa deb libs optional arch=linux-any
 gstreamer1.0-gl deb libs optional arch=any
 gstreamer1.0-plugins-base deb libs optional arch=any
 gstreamer1.0-plugins-base-apps deb utils optional arch=any
 gstreamer1.0-x deb libs optional arch=any
 libgstreamer-gl1.0-0 deb libs optional arch=any
 libgstreamer-plugins-base1.0-0 deb libs optional arch=any
 libgstreamer-plugins-base1.0-dev deb libdevel optional arch=any
Checksums-Sha1:
 29285961bc3218eea584d635527cbaa19470b237 2579548 gst-plugins-base1.0_1.28.9.orig.tar.xz
 664b04d66d1cd5fa9390ebd1da7accf84d60638c 58828 gst-plugins-base1.0_1.28.9-0ubuntu0~pd1.debian.tar.xz
Checksums-Sha256:
 c1fda668b520e6aef763c0eb962c032c9fe52bce322e8b00c69b4e9e847bddc1 2579548 gst-plugins-base1.0_1.28.9.orig.tar.xz
 daf7f2bb91568c29e2d193af43126d98772b558460a074e3ee9122c72ff0e4f3 58828 gst-plugins-base1.0_1.28.9-0ubuntu0~pd1.debian.tar.xz
Files:
 0d5e25e233a28d1089e97aaf68d170ce 2579548 gst-plugins-base1.0_1.28.9.orig.tar.xz
 ae2bd1a1ff812f77344b79cd69cf4f93 58828 gst-plugins-base1.0_1.28.9-0ubuntu0~pd1.debian.tar.xz
Original-Maintainer: Maintainers of GStreamer packages <gst-plugins-base1.0@packages.debian.org>
