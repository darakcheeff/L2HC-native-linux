#!/bin/bash
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build_deb"
PKG_DIR="${BUILD_DIR}/l2hc-native-linux_1.0.0_amd64"

echo "=== Building Debian Package for L2HC-native-linux 1.0.0 ==="
# Build native library
make -C "${ROOT_DIR}" clean
make -C "${ROOT_DIR}" all

rm -rf "${BUILD_DIR}"
mkdir -p "${PKG_DIR}/DEBIAN"
mkdir -p "${PKG_DIR}/usr/lib/x86_64-linux-gnu/spa-0.2/bluez5"
mkdir -p "${PKG_DIR}/usr/lib/x86_64-linux-gnu"
mkdir -p "${PKG_DIR}/usr/include"
mkdir -p "${PKG_DIR}/usr/share/doc/l2hc-native-linux" 
mkdir -p "${PKG_DIR}/etc/sysctl.d"

# Copy files
cp "${ROOT_DIR}/spa/libspa-codec-bluez5-l2hc.so" "${PKG_DIR}/usr/lib/x86_64-linux-gnu/spa-0.2/bluez5/"
cp "${ROOT_DIR}/spa/libspa-bluez5.so" "${PKG_DIR}/usr/lib/x86_64-linux-gnu/spa-0.2/bluez5/"
cp "${ROOT_DIR}/libl2hc.so" "${PKG_DIR}/usr/lib/x86_64-linux-gnu/"
cp "${ROOT_DIR}/include/l2hc_native.h" "${PKG_DIR}/usr/include/"

cat << 'EOF' > "${PKG_DIR}/etc/sysctl.d/99-bluetooth-audio.conf"
# Socket buffers for high-bitrate Bluetooth audio (L2HC / LDAC)
net.core.wmem_max = 2097152
net.core.wmem_default = 524288
EOF

# Documentation
cp "${ROOT_DIR}/README.md" "${PKG_DIR}/usr/share/doc/l2hc-native-linux/" || true
cp "${ROOT_DIR}/LICENSE" "${PKG_DIR}/usr/share/doc/l2hc-native-linux/copyright" || true

# Control file
cat << 'EOF' > "${PKG_DIR}/DEBIAN/control"
Package: l2hc-native-linux
Version: 1.0.0
Section: sound
Priority: optional
Architecture: amd64
Depends: pipewire (>= 0.3.65), wireplumber, libspa-0.2-bluetooth
Conflicts: l2hc-linux
Replaces: l2hc-linux
Maintainer: darakcheeff <darakcheeff@users.noreply.github.com>
Homepage: https://github.com/darakcheeff/L2HC-native-linux
Description: Native Huawei L2HC Bluetooth High-Resolution Audio Codec for Linux
 Provides a 100% native clean-room implementation in C of the Huawei L2HC
 audio codec for Linux PipeWire and BlueZ 5 on Debian, Ubuntu, Linux Mint and derivatives.
 .
 Features:
  - 100% native x86_64 implementation in pure C99
  - No QEMU, no Android Bionic, no proprietary binaries
  - 40x+ real-time encoding performance
  - Bit-budget verification loop (EncodeMDCTCountBits) eliminating audio artifacts
  - Bitrates: 320 kbps, 640 kbps, 960 kbps, Auto
  - Seamless integration with PipeWire, WirePlumber, Blueman, and desktop audio settings
EOF

# preinst script (dpkg-divert for libspa-bluez5.so)
cat << 'EOF' > "${PKG_DIR}/DEBIAN/preinst"
#!/bin/bash
set -e

if [ "$1" = "install" ] || [ "$1" = "upgrade" ]; then
    # Clear any leftover diversions from previous l2hc-linux package
    if dpkg-divert --list /usr/lib/x86_64-linux-gnu/spa-0.2/bluez5/libspa-bluez5.so 2>/dev/null | grep -q "l2hc-linux"; then
        dpkg-divert --package l2hc-linux --remove --rename \
            --divert /usr/lib/x86_64-linux-gnu/spa-0.2/bluez5/libspa-bluez5.so.orig \
            /usr/lib/x86_64-linux-gnu/spa-0.2/bluez5/libspa-bluez5.so 2>/dev/null || true
    fi
    if ! dpkg-divert --list /usr/lib/x86_64-linux-gnu/spa-0.2/bluez5/libspa-bluez5.so 2>/dev/null | grep -q "l2hc-native-linux"; then
        dpkg-divert --package l2hc-native-linux --add --rename \
            --divert /usr/lib/x86_64-linux-gnu/spa-0.2/bluez5/libspa-bluez5.so.orig \
            /usr/lib/x86_64-linux-gnu/spa-0.2/bluez5/libspa-bluez5.so
    fi
fi
exit 0
EOF
chmod 755 "${PKG_DIR}/DEBIAN/preinst"

# postinst script
cat << 'EOF' > "${PKG_DIR}/DEBIAN/postinst"
#!/bin/bash
set -e

# Update dynamic linker cache
ldconfig 2>/dev/null || true

# Restart user services for currently logged in users
for uid in $(loginctl --no-legend list-users 2>/dev/null | awk '{print $1}'); do
    if [ -d "/run/user/${uid}" ]; then
        su - $(id -nu ${uid}) -c "export XDG_RUNTIME_DIR=/run/user/${uid}; systemctl --user daemon-reload; systemctl --user restart wireplumber.service pipewire.service 2>/dev/null" || true
    fi
done

# Apply sysctl settings
sysctl --system >/dev/null 2>&1 || true

echo "=== L2HC-native-linux installed successfully ==="
echo "Huawei L2HC codec (320k / 640k / 960k / Auto) is now active in PipeWire."
exit 0
EOF
chmod 755 "${PKG_DIR}/DEBIAN/postinst"

# postrm script (restore original libspa-bluez5.so)
cat << 'EOF' > "${PKG_DIR}/DEBIAN/postrm"
#!/bin/bash
set -e

if [ "$1" = "remove" ] || [ "$1" = "abort-install" ] || [ "$1" = "disappear" ]; then
    if dpkg-divert --list /usr/lib/x86_64-linux-gnu/spa-0.2/bluez5/libspa-bluez5.so 2>/dev/null | grep -q "l2hc-native-linux"; then
        dpkg-divert --package l2hc-native-linux --remove --rename \
            --divert /usr/lib/x86_64-linux-gnu/spa-0.2/bluez5/libspa-bluez5.so.orig \
            /usr/lib/x86_64-linux-gnu/spa-0.2/bluez5/libspa-bluez5.so || true
    fi
fi

ldconfig 2>/dev/null || true

for uid in $(loginctl --no-legend list-users 2>/dev/null | awk '{print $1}'); do
    if [ -d "/run/user/${uid}" ]; then
        su - $(id -nu ${uid}) -c "export XDG_RUNTIME_DIR=/run/user/${uid}; systemctl --user daemon-reload; systemctl --user restart wireplumber.service pipewire.service 2>/dev/null" || true
    fi
done
exit 0
EOF
chmod 755 "${PKG_DIR}/DEBIAN/postrm"

# Build .deb
mkdir -p "${ROOT_DIR}/dist"
dpkg-deb --build --root-owner-group "${PKG_DIR}" "${ROOT_DIR}/dist/l2hc-native-linux_1.0.0_amd64.deb"

echo "=== Package built: ${ROOT_DIR}/dist/l2hc-native-linux_1.0.0_amd64.deb ==="
