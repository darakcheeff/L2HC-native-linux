#!/bin/bash
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
BUILD_DIR="${ROOT_DIR}/build_multiabi"
PKG_DIR="${BUILD_DIR}/pkg"

echo "=========================================================="
echo " Building L2HC Multi-ABI Fat Package (Auto-Detection)      "
echo "=========================================================="

# Build native library
make -C "${ROOT_DIR}" clean
make -C "${ROOT_DIR}" all

rm -rf "${BUILD_DIR}"
mkdir -p "${PKG_DIR}/DEBIAN"
mkdir -p "${PKG_DIR}/usr/lib/x86_64-linux-gnu"
mkdir -p "${PKG_DIR}/usr/include"
mkdir -p "${PKG_DIR}/usr/share/doc/l2hc-native-linux-multiabi"
mkdir -p "${PKG_DIR}/etc/sysctl.d"
mkdir -p "${PKG_DIR}/usr/lib/l2hc-native-linux/abi"
mkdir -p "${DIST_DIR}"

# 1. Native library & headers
cp "${ROOT_DIR}/libl2hc.so" "${PKG_DIR}/usr/lib/x86_64-linux-gnu/"
strip --strip-unneeded "${PKG_DIR}/usr/lib/x86_64-linux-gnu/libl2hc.so"
cp "${ROOT_DIR}/include/l2hc_native.h" "${PKG_DIR}/usr/include/"
cp "${ROOT_DIR}/README.md" "${PKG_DIR}/usr/share/doc/l2hc-native-linux-multiabi/" || true
cp "${ROOT_DIR}/LICENSE" "${PKG_DIR}/usr/share/doc/l2hc-native-linux-multiabi/copyright" || true

# 2. Sysctl config
cat << 'EOF' > "${PKG_DIR}/etc/sysctl.d/99-bluetooth-audio.conf"
# Socket buffers for high-bitrate Bluetooth audio (L2HC / LDAC)
net.core.wmem_max = 2097152
net.core.wmem_default = 524288
EOF

# 3. Prebuilt Multi-ABI plugins (0.3, 1.0, 1.2, 1.4, 1.6)
for abi in pw-0.3 pw-1.0 pw-1.2 pw-1.4 pw-1.6; do
    if [ -d "${ROOT_DIR}/prebuilt/${abi}" ]; then
        echo "Bundling prebuilt ABI: ${abi}..."
        mkdir -p "${PKG_DIR}/usr/lib/l2hc-native-linux/abi/${abi}"
        cp "${ROOT_DIR}/prebuilt/${abi}/libspa-bluez5.so" "${PKG_DIR}/usr/lib/l2hc-native-linux/abi/${abi}/"
        cp "${ROOT_DIR}/prebuilt/${abi}/libspa-codec-bluez5-l2hc.so" "${PKG_DIR}/usr/lib/l2hc-native-linux/abi/${abi}/"
        strip --strip-unneeded "${PKG_DIR}/usr/lib/l2hc-native-linux/abi/${abi}/"*.so
    fi
done

# 4. Control file
cat << 'EOF' > "${PKG_DIR}/DEBIAN/control"
Package: l2hc-native-linux-multiabi
Version: 1.0.0
Section: sound
Priority: optional
Architecture: amd64
Provides: l2hc-native-linux
Conflicts: l2hc-linux, l2hc-native-linux-dkms
Replaces: l2hc-linux, l2hc-native-linux, l2hc-native-linux-dkms
Depends: pipewire (>= 0.3.19), wireplumber | pipewire-media-session, libspa-0.2-bluetooth
Maintainer: darakcheeff <darakcheeff@users.noreply.github.com>
Homepage: https://github.com/darakcheeff/L2HC-native-linux
Description: Native Huawei L2HC High-Resolution Audio Codec for Linux (Multi-ABI Fat Package)
 Provides a 100% native clean-room implementation in C of the Huawei L2HC
 audio codec for Linux PipeWire and BlueZ 5 with automatic PipeWire version detection.
 .
 Features:
  - 100% native x86_64 implementation in pure C99
  - No QEMU, no Android Bionic, no proprietary binaries
  - 40x+ real-time encoding performance
  - Bit-budget verification loop eliminating audio artifacts
  - Bitrates: 320 kbps, 480 kbps, 640 kbps, 960 kbps, Auto
  - Multi-ABI support: bundles precompiled modules for PipeWire 0.3.x, 1.0.x, 1.2.x, 1.4.x, 1.6.x
  - Automatically detects PipeWire version upon installation and activates matching plugin
EOF

# 5. preinst script
cat << 'EOF' > "${PKG_DIR}/DEBIAN/preinst"
#!/bin/bash
set -e

if [ "$1" = "install" ] || [ "$1" = "upgrade" ]; then
    if ! dpkg-divert --list /usr/lib/x86_64-linux-gnu/spa-0.2/bluez5/libspa-bluez5.so 2>/dev/null | grep -q "libspa-bluez5.so.orig"; then
        dpkg-divert --package l2hc-native-linux --no-rename --add \
            --divert /usr/lib/x86_64-linux-gnu/spa-0.2/bluez5/libspa-bluez5.so.orig \
            /usr/lib/x86_64-linux-gnu/spa-0.2/bluez5/libspa-bluez5.so
    fi
fi
exit 0
EOF
chmod 755 "${PKG_DIR}/DEBIAN/preinst"

# 6. postinst script
cat << 'EOF' > "${PKG_DIR}/DEBIAN/postinst"
#!/bin/bash
set -e

# Detect PipeWire version
PW_VERSION=$(pipewire --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -n1 || echo "")
if [ -z "${PW_VERSION}" ]; then
    PW_VERSION=$(dpkg-query -W -f='${Version}\n' pipewire 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+' | head -n1 || echo "")
fi
echo "Detected PipeWire version: ${PW_VERSION}"

TARGET_DIR="/usr/lib/x86_64-linux-gnu/spa-0.2/bluez5"
mkdir -p "${TARGET_DIR}"

case "${PW_VERSION}" in
    0.3*)
        ABI="pw-0.3"
        ;;
    1.0*)
        ABI="pw-1.0"
        ;;
    1.2*)
        ABI="pw-1.2"
        ;;
    1.4*)
        ABI="pw-1.4"
        ;;
    1.5*|1.6*|*)
        ABI="pw-1.6"
        ;;
esac

echo "Activating PipeWire BlueZ5 ABI: ${ABI}..."
SOURCE_DIR="/usr/lib/l2hc-native-linux/abi/${ABI}"

if [ -d "${SOURCE_DIR}" ]; then
    ln -sf "${SOURCE_DIR}/libspa-bluez5.so" "${TARGET_DIR}/libspa-bluez5.so"
    ln -sf "${SOURCE_DIR}/libspa-codec-bluez5-l2hc.so" "${TARGET_DIR}/libspa-codec-bluez5-l2hc.so"
else
    echo "Warning: ABI directory ${SOURCE_DIR} not found, falling back to pw-1.0"
    ln -sf "/usr/lib/l2hc-native-linux/abi/pw-1.0/libspa-bluez5.so" "${TARGET_DIR}/libspa-bluez5.so"
    ln -sf "/usr/lib/l2hc-native-linux/abi/pw-1.0/libspa-codec-bluez5-l2hc.so" "${TARGET_DIR}/libspa-codec-bluez5-l2hc.so"
fi

ldconfig 2>/dev/null || true
sysctl --system >/dev/null 2>&1 || true

if [ -f /usr/share/spa-0.2/bluez5/bluez-hardware.conf ] && [ ! -f /usr/local/share/spa-0.2/bluez5/bluez-hardware.conf ]; then
    mkdir -p /usr/local/share/spa-0.2/bluez5
    ln -sf /usr/share/spa-0.2/bluez5/bluez-hardware.conf /usr/local/share/spa-0.2/bluez5/bluez-hardware.conf
fi

for uid in $(loginctl --no-legend list-users 2>/dev/null | awk '{print $1}'); do
    if [ -d "/run/user/${uid}" ]; then
        su - $(id -nu ${uid}) -c "export XDG_RUNTIME_DIR=/run/user/${uid}; systemctl --user daemon-reload; systemctl --user restart wireplumber.service pipewire.service 2>/dev/null" || true
    fi
done

echo "=== L2HC Multi-ABI (${ABI}) installed and activated successfully ==="
exit 0
EOF
chmod 755 "${PKG_DIR}/DEBIAN/postinst"

# 7. postrm script
cat << 'EOF' > "${PKG_DIR}/DEBIAN/postrm"
#!/bin/bash
set -e

if [ "$1" = "remove" ] || [ "$1" = "abort-install" ] || [ "$1" = "disappear" ]; then
    rm -f /usr/lib/x86_64-linux-gnu/spa-0.2/bluez5/libspa-codec-bluez5-l2hc.so
    rm -f /usr/lib/x86_64-linux-gnu/spa-0.2/bluez5/libspa-bluez5.so
    if dpkg-divert --list /usr/lib/x86_64-linux-gnu/spa-0.2/bluez5/libspa-bluez5.so 2>/dev/null | grep -q "libspa-bluez5.so.orig"; then
        dpkg-divert --package l2hc-native-linux --no-rename --remove \
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

OUTPUT_DEB="${DIST_DIR}/l2hc-native-linux-multiabi_1.0.0_amd64.deb"
dpkg-deb --build --root-owner-group "${PKG_DIR}" "${OUTPUT_DEB}"

echo "=========================================================="
echo " Successfully created: ${OUTPUT_DEB} "
echo " Size: $(du -h "${OUTPUT_DEB}" | awk '{print $1}')"
echo "=========================================================="
