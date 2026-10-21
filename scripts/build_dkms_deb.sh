#!/bin/bash
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
BUILD_DIR="${ROOT_DIR}/build_dkms"
PKG_DIR="${BUILD_DIR}/pkg"
VERSION="${1:-1.1.1}"
SRC_DIR_NAME="l2hc-native-linux-${VERSION}"

echo "=========================================================="
echo " Building L2HC DKMS / Local Source Builder Package         "
echo " Version: ${VERSION}"
echo "=========================================================="

make -C "${ROOT_DIR}" clean

rm -rf "${BUILD_DIR}"
mkdir -p "${PKG_DIR}/DEBIAN"
mkdir -p "${PKG_DIR}/usr/src/${SRC_DIR_NAME}/src"
mkdir -p "${PKG_DIR}/usr/src/${SRC_DIR_NAME}/spa"
mkdir -p "${PKG_DIR}/usr/src/${SRC_DIR_NAME}/include"
mkdir -p "${PKG_DIR}/usr/lib/l2hc-native-linux"
mkdir -p "${PKG_DIR}/usr/bin"
mkdir -p "${PKG_DIR}/etc/sysctl.d"
mkdir -p "${PKG_DIR}/etc/apt/apt.conf.d"
mkdir -p "${PKG_DIR}/usr/share/doc/l2hc-native-linux-dkms"
mkdir -p "${DIST_DIR}"

# 1. Copy source code
cp -r "${ROOT_DIR}/src/"* "${PKG_DIR}/usr/src/${SRC_DIR_NAME}/src/"
cp "${ROOT_DIR}/spa/a2dp-codec-l2hc.c" "${PKG_DIR}/usr/src/${SRC_DIR_NAME}/spa/"
cp "${ROOT_DIR}/spa/l2hc_bridge.c" "${PKG_DIR}/usr/src/${SRC_DIR_NAME}/spa/"
cp "${ROOT_DIR}/spa/l2hc_bridge.h" "${PKG_DIR}/usr/src/${SRC_DIR_NAME}/spa/"
cp -r "${ROOT_DIR}/include/"* "${PKG_DIR}/usr/src/${SRC_DIR_NAME}/include/"
cp "${ROOT_DIR}/Makefile" "${PKG_DIR}/usr/src/${SRC_DIR_NAME}/"

# 2. Sysctl config
cat << 'EOF' > "${PKG_DIR}/etc/sysctl.d/99-bluetooth-audio.conf"
# Socket buffers for high-bitrate Bluetooth audio (L2HC / LDAC)
net.core.wmem_max = 2097152
net.core.wmem_default = 524288
EOF

# 3. Documentation
cp "${ROOT_DIR}/README.md" "${PKG_DIR}/usr/share/doc/l2hc-native-linux-dkms/" || true
cp "${ROOT_DIR}/LICENSE" "${PKG_DIR}/usr/share/doc/l2hc-native-linux-dkms/copyright" || true

# 4. Builder script (installed to /usr/lib/l2hc-native-linux/l2hc-builder.sh)
cat << 'BUILDER_EOF' > "${PKG_DIR}/usr/lib/l2hc-native-linux/l2hc-builder.sh"
#!/bin/bash
set -e

SRC_DIR=$(ls -d /usr/src/l2hc-native-linux-* 2>/dev/null | tail -n 1)
WORK_DIR="/var/lib/l2hc-native-linux"
LOG_FILE="/var/log/l2hc-build.log"

action="${1:-build}"

if [ "${action}" = "status" ]; then
    echo "=== L2HC Driver Status ==="
    PW_VER=$(pipewire --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 || echo "unknown")
    echo "Current PipeWire version: ${PW_VER}"
    if [ -f /usr/lib/x86_64-linux-gnu/spa-0.2/bluez5/libspa-codec-bluez5-l2hc.so ]; then
        echo "L2HC SPA Codec Plugin: INSTALLED"
    else
        echo "L2HC SPA Codec Plugin: NOT INSTALLED"
    fi
    exit 0
fi

if [ "${action}" = "clean" ]; then
    echo "Cleaning up L2HC build cache..."
    rm -rf "${WORK_DIR}"
    exit 0
fi

echo "=========================================================="
echo " Building L2HC Native Codec and PipeWire BlueZ5 Plugin   "
echo "=========================================================="

mkdir -p "${WORK_DIR}"
exec > >(tee -a "${LOG_FILE}") 2>&1

# 1. Build and install native libl2hc.so
echo "[1/4] Building native libl2hc.so..."
cd "${SRC_DIR}"
make -B libl2hc.so
LIB_TARGET_DIR="/usr/lib/x86_64-linux-gnu"
if [ ! -d "${LIB_TARGET_DIR}" ]; then
    LIB_TARGET_DIR="/usr/lib64"
    if [ ! -d "${LIB_TARGET_DIR}" ]; then
        LIB_TARGET_DIR="/usr/lib"
    fi
fi
mkdir -p "${LIB_TARGET_DIR}"
cp "${SRC_DIR}/libl2hc.so" "${LIB_TARGET_DIR}/"
strip --strip-unneeded "${LIB_TARGET_DIR}/libl2hc.so"
mkdir -p /usr/include
cp "${SRC_DIR}/include/l2hc_native.h" /usr/include/
ldconfig 2>/dev/null || true

# 2. Detect PipeWire version & obtain source
echo "[2/4] Detecting PipeWire environment..."
PW_VER=$(pipewire --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 || echo "")
if [ -z "${PW_VER}" ]; then
    PW_VER=$(dpkg-query -W -f='${Version}\n' pipewire 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 || echo "1.0.0")
fi
echo "PipeWire version: ${PW_VER}"

# Check for existing sources or download
BUILD_PW_DIR="${WORK_DIR}/pipewire-${PW_VER}"
if [ ! -d "${BUILD_PW_DIR}/spa/plugins/bluez5" ]; then
    echo "Downloading PipeWire sources for version ${PW_VER}..."
    cd "${WORK_DIR}"
    rm -rf "pipewire-${PW_VER}"*
    # Try gitlab freedesktop archive first
    if ! curl -fL -s -o "pipewire-${PW_VER}.tar.gz" "https://gitlab.freedesktop.org/pipewire/pipewire/-/archive/${PW_VER}/pipewire-${PW_VER}.tar.gz" 2>/dev/null; then
        # Try apt-get source
        echo "GitLab download unavailable, attempting 'apt-get source pipewire'..."
        apt-get update -qq || true
        apt-get source -y pipewire || true
        APT_SRC=$(find "${WORK_DIR}" -mindepth 1 -maxdepth 1 -type d -name "pipewire*" | head -n1)
        if [ -n "${APT_SRC}" ]; then
            BUILD_PW_DIR="${APT_SRC}"
        fi
    else
        tar -xzf "pipewire-${PW_VER}.tar.gz"
        BUILD_PW_DIR="${WORK_DIR}/pipewire-${PW_VER}"
    fi
fi

if [ ! -d "${BUILD_PW_DIR}/spa/plugins/bluez5" ]; then
    echo "ERROR: Could not locate PipeWire sources for ${PW_VER}." >&2
    exit 1
fi

# 3. Patch PipeWire tree
echo "[3/4] Patching PipeWire BlueZ5 plugins..."
cp "${SRC_DIR}/spa/a2dp-codec-l2hc.c" "${BUILD_PW_DIR}/spa/plugins/bluez5/"
cp "${SRC_DIR}/spa/l2hc_bridge.c" "${BUILD_PW_DIR}/spa/plugins/bluez5/"
cp "${SRC_DIR}/spa/l2hc_bridge.h" "${BUILD_PW_DIR}/spa/plugins/bluez5/"
cp "${SRC_DIR}/src/l2hc_native.c" "${BUILD_PW_DIR}/spa/plugins/bluez5/"
cp "${SRC_DIR}/src/l2hc_native.h" "${BUILD_PW_DIR}/spa/plugins/bluez5/"
cp "${SRC_DIR}/src/l2hc_tables.h" "${BUILD_PW_DIR}/spa/plugins/bluez5/"

python3 -c "
pw_dir = '${BUILD_PW_DIR}'

# a2dp-codec-caps.h
caps_path = f'{pw_dir}/spa/plugins/bluez5/a2dp-codec-caps.h'
with open(caps_path, 'r') as f:
    caps = f.read()

if 'L2HC_VENDOR_ID' not in caps:
    caps += '''
#ifndef A2DP_CODEC_VENDOR_L2HC
#define A2DP_CODEC_VENDOR_L2HC          0x3500
#endif
#define L2HC_VENDOR_ID                  0x0000027d
#define L2HC_CODEC_ID                   0x4c35

#define L2HC_BIT_DEPTH_16               0x01
#define L2HC_BIT_DEPTH_24               0x02
#define L2HC_BIT_DEPTH_32               0x04

#define L2HC_SAMPLING_FREQ_32000        0x01
#define L2HC_SAMPLING_FREQ_44100        0x02
#define L2HC_SAMPLING_FREQ_48000        0x04
#define L2HC_SAMPLING_FREQ_88200        0x08
#define L2HC_SAMPLING_FREQ_96000        0x10
#define L2HC_SAMPLING_FREQ_192000       0x20

#define L2HC_BITRATE_320K               0x01
#define L2HC_BITRATE_480K               0x02
#define L2HC_BITRATE_640K               0x04
#define L2HC_BITRATE_960K               0x08

#define L2HC_FRAME_10MS                 0x00
#define L2HC_FRAME_7_5MS                0x01
#define L2HC_FRAME_5MS                  0x02

#define L2HC_BITRATE_96K                0x10
#define L2HC_BITRATE_128K               0x20
#define L2HC_BITRATE_192K               0x40
#define L2HC_BITRATE_256K               0x80

#define L2HC_CH_MODE_STEREO             0x01
#define L2HC_CH_MODE_DUAL               0x02
#define L2HC_CH_MODE_MONO               0x04

#ifndef A2DP_L2HC_T_DEFINED
#define A2DP_L2HC_T_DEFINED
typedef struct {
    a2dp_vendor_codec_t info;
    uint8_t bits_per_sample;
    uint8_t frequency;
    uint8_t bitrate_high;
    uint8_t bitrate_low_frame_len;
} __attribute__ ((packed)) a2dp_l2hc_t;
#endif
'''
    with open(caps_path, 'w') as f:
        f.write(caps)

# audio.h
audio_h = f'{pw_dir}/spa/include/spa/param/bluetooth/audio.h'
with open(audio_h, 'r') as f:
    c = f.read()
if 'SPA_BLUETOOTH_AUDIO_CODEC_L2HC' not in c:
    target = 'SPA_BLUETOOTH_AUDIO_CODEC_CVSD'
    rep = '''\tSPA_BLUETOOTH_AUDIO_CODEC_L2HC = 0x70,
\tSPA_BLUETOOTH_AUDIO_CODEC_L2HC_320 = 0x71,
\tSPA_BLUETOOTH_AUDIO_CODEC_L2HC_480 = 0x72,
\tSPA_BLUETOOTH_AUDIO_CODEC_L2HC_640 = 0x73,
\tSPA_BLUETOOTH_AUDIO_CODEC_L2HC_960 = 0x74,

\t''' + target
    c = c.replace(target, rep, 1)
    with open(audio_h, 'w') as f:
        f.write(c)

# type-info.h
type_info_h = f'{pw_dir}/spa/include/spa/param/bluetooth/type-info.h'
with open(type_info_h, 'r') as f:
    c = f.read()
if 'SPA_BLUETOOTH_AUDIO_CODEC_L2HC' not in c:
    target = '{ SPA_BLUETOOTH_AUDIO_CODEC_CVSD,'
    rep = '''\t{ SPA_BLUETOOTH_AUDIO_CODEC_L2HC, SPA_TYPE_Int, SPA_TYPE_INFO_BLUETOOTH_AUDIO_CODEC_BASE \"l2hc\", NULL },
\t{ SPA_BLUETOOTH_AUDIO_CODEC_L2HC_320, SPA_TYPE_Int, SPA_TYPE_INFO_BLUETOOTH_AUDIO_CODEC_BASE \"l2hc_320\", NULL },
\t{ SPA_BLUETOOTH_AUDIO_CODEC_L2HC_480, SPA_TYPE_Int, SPA_TYPE_INFO_BLUETOOTH_AUDIO_CODEC_BASE \"l2hc_480\", NULL },
\t{ SPA_BLUETOOTH_AUDIO_CODEC_L2HC_640, SPA_TYPE_Int, SPA_TYPE_INFO_BLUETOOTH_AUDIO_CODEC_BASE \"l2hc_640\", NULL },
\t{ SPA_BLUETOOTH_AUDIO_CODEC_L2HC_960, SPA_TYPE_Int, SPA_TYPE_INFO_BLUETOOTH_AUDIO_CODEC_BASE \"l2hc_960\", NULL },

\t''' + target
    c = c.replace(target, rep, 1)
    with open(type_info_h, 'w') as f:
        f.write(c)

# bluez5-dbus.c
dbus_c = f'{pw_dir}/spa/plugins/bluez5/bluez5-dbus.c'
with open(dbus_c, 'r') as f:
    c = f.read()
if 'SPA_BLUETOOTH_AUDIO_CODEC_L2HC' not in c:
    target = 'case SPA_BLUETOOTH_AUDIO_CODEC_LDAC:'
    rep = '''case SPA_BLUETOOTH_AUDIO_CODEC_LDAC:
\tcase SPA_BLUETOOTH_AUDIO_CODEC_L2HC:
\tcase SPA_BLUETOOTH_AUDIO_CODEC_L2HC_320:
\tcase SPA_BLUETOOTH_AUDIO_CODEC_L2HC_480:
\tcase SPA_BLUETOOTH_AUDIO_CODEC_L2HC_640:
\tcase SPA_BLUETOOTH_AUDIO_CODEC_L2HC_960:'''
    c = c.replace(target, rep, 1)
    with open(dbus_c, 'w') as f:
        f.write(c)

# codec-loader.c
loader_c = f'{pw_dir}/spa/plugins/bluez5/codec-loader.c'
with open(loader_c, 'r') as f:
    c = f.read()
if '\"l2hc\"' not in c:
    for macro in ['MEDIA_CODEC_FACTORY_LIB', 'A2DP_CODEC_FACTORY_LIB']:
        if macro in c:
            target = f'{macro}(\"faststream\"),'
            if target in c:
                c = c.replace(target, target + f'\n\t\t{macro}(\"l2hc\"),')
            else:
                target2 = f'{macro}(\"sbc\"),'
                c = c.replace(target2, f'{macro}(\"l2hc\"),\n\t\t' + target2)
            break
    order_target = 'SPA_BLUETOOTH_AUDIO_CODEC_LC3,'
    order_rep = '''SPA_BLUETOOTH_AUDIO_CODEC_LC3,
\t\tSPA_BLUETOOTH_AUDIO_CODEC_L2HC,
\t\tSPA_BLUETOOTH_AUDIO_CODEC_L2HC_960,
\t\tSPA_BLUETOOTH_AUDIO_CODEC_L2HC_640,
\t\tSPA_BLUETOOTH_AUDIO_CODEC_L2HC_480,
\t\tSPA_BLUETOOTH_AUDIO_CODEC_L2HC_320,'''
    if order_target in c:
        c = c.replace(order_target, order_rep, 1)
    with open(loader_c, 'w') as f:
        f.write(c)

# meson.build
meson_b = f'{pw_dir}/spa/plugins/bluez5/meson.build'
with open(meson_b, 'r') as f:
    c = f.read()
if 'spa-codec-bluez5-l2hc' not in c:
    entry = '''
bluez_codec_l2hc = shared_library('spa-codec-bluez5-l2hc',
  [ 'a2dp-codec-l2hc.c', 'l2hc_bridge.c', 'l2hc_native.c', 'media-codecs.c' ],
  include_directories : [ configinc ],
  c_args : codec_args,
  dependencies : [ spa_dep, mathlib ],
  install : true,
  install_dir : spa_plugindir / 'bluez5')
'''
    c += entry
    with open(meson_b, 'w') as f:
        f.write(c)
"

# 4. Compile with meson & ninja
echo "[4/4] Compiling SPA BlueZ5 plugins..."
cd "${BUILD_PW_DIR}"
meson setup build -Dbluez5=enabled -Dsession-managers=[] -Ddocs=disabled -Dman=disabled -Dgstreamer=disabled -Dpipewire-v4l2=disabled -Dpipewire-alsa=disabled -Dsystemd=disabled || meson setup build -Dbluez5=enabled -Dsession-managers=[] -Ddocs=disabled -Dman=disabled -Dgstreamer=disabled || meson setup build -Dbluez5=enabled || true
ninja -C build spa/plugins/bluez5/libspa-bluez5.so spa/plugins/bluez5/libspa-codec-bluez5-l2hc.so

SPA_SO=$(find "${BUILD_PW_DIR}/build" -name "libspa-bluez5.so" | head -n1)
L2HC_SO=$(find "${BUILD_PW_DIR}/build" -name "libspa-codec-bluez5-l2hc.so" | head -n1)

if [ -z "${SPA_SO}" ] || [ -z "${L2HC_SO}" ]; then
    echo "ERROR: Failed to compile SPA plugins." >&2
    exit 1
fi

SPA_DEST_DIR="/usr/lib/x86_64-linux-gnu/spa-0.2/bluez5"
if [ ! -d "${SPA_DEST_DIR}" ]; then
    SPA_DEST_DIR="/usr/lib64/spa-0.2/bluez5"
    if [ ! -d "${SPA_DEST_DIR}" ]; then
        SPA_DEST_DIR="/usr/lib/spa-0.2/bluez5"
    fi
fi
mkdir -p "${SPA_DEST_DIR}"

# Remove symlink if left over from multiabi
if [ -L "${SPA_DEST_DIR}/libspa-bluez5.so" ]; then
    rm -f "${SPA_DEST_DIR}/libspa-bluez5.so"
fi

# Ensure dpkg-divert exists for stock library backup
if [ -f "${SPA_DEST_DIR}/libspa-bluez5.so" ] && ! [ -L "${SPA_DEST_DIR}/libspa-bluez5.so" ]; then
    if ! dpkg-divert --list "${SPA_DEST_DIR}/libspa-bluez5.so" 2>/dev/null | grep -q "libspa-bluez5.so.orig"; then
        dpkg-divert --package l2hc-native-linux-dkms --no-rename --add \
            --divert "${SPA_DEST_DIR}/libspa-bluez5.so.orig" \
            "${SPA_DEST_DIR}/libspa-bluez5.so"
        cp -p "${SPA_DEST_DIR}/libspa-bluez5.so" "${SPA_DEST_DIR}/libspa-bluez5.so.orig" 2>/dev/null || true
    fi
fi

cp "${SPA_SO}" "${SPA_DEST_DIR}/libspa-bluez5.so"
cp "${L2HC_SO}" "${SPA_DEST_DIR}/libspa-codec-bluez5-l2hc.so"
strip --strip-unneeded "${SPA_DEST_DIR}/libspa-bluez5.so" "${SPA_DEST_DIR}/libspa-codec-bluez5-l2hc.so"

if [ -f /usr/share/spa-0.2/bluez5/bluez-hardware.conf ] && [ ! -f /usr/local/share/spa-0.2/bluez5/bluez-hardware.conf ]; then
    mkdir -p /usr/local/share/spa-0.2/bluez5
    ln -sf /usr/share/spa-0.2/bluez5/bluez-hardware.conf /usr/local/share/spa-0.2/bluez5/bluez-hardware.conf
fi

for uid in $(loginctl --no-legend list-users 2>/dev/null | awk '{print $1}'); do
    if [ -d "/run/user/${uid}" ]; then
        su - $(id -nu ${uid}) -c "export XDG_RUNTIME_DIR=/run/user/${uid}; systemctl --user daemon-reload; systemctl --user restart wireplumber.service pipewire.service 2>/dev/null" || true
    fi
done

echo "=========================================================="
echo " L2HC Native Codec built and activated successfully!     "
echo "=========================================================="
BUILDER_EOF
chmod 755 "${PKG_DIR}/usr/lib/l2hc-native-linux/l2hc-builder.sh"

# 5. CLI symlink /usr/bin/l2hc-rebuild
ln -sf /usr/lib/l2hc-native-linux/l2hc-builder.sh "${PKG_DIR}/usr/bin/l2hc-rebuild"

# 6. APT Post-Invoke hook
cat << 'EOF' > "${PKG_DIR}/etc/apt/apt.conf.d/99l2hc-rebuild"
DPkg::Post-Invoke {"if [ -x /usr/bin/l2hc-rebuild ] && ls -d /usr/src/l2hc-native-linux-* >/dev/null 2>&1; then /usr/bin/l2hc-rebuild >/var/log/l2hc-apt-rebuild.log 2>&1 || true; fi";};
EOF

# 7. Control file
cat << EOF > "${PKG_DIR}/DEBIAN/control"
Package: l2hc-native-linux-dkms
Version: ${VERSION}
Section: sound
Priority: optional
Architecture: all
Provides: l2hc-native-linux
Conflicts: l2hc-linux, l2hc-native-linux-multiabi, l2hc-native-linux
Replaces: l2hc-linux, l2hc-native-linux-multiabi, l2hc-native-linux
Depends: pipewire (>= 0.3.19), libspa-0.2-bluetooth, build-essential, meson, ninja-build, pkg-config, python3, curl, ca-certificates, libglib2.0-dev, libdbus-1-dev, libbluetooth-dev, libsbc-dev
Suggests: libpipewire-0.3-dev, libspa-0.2-dev
Maintainer: darakcheeff <darakcheeff@users.noreply.github.com>
Homepage: https://github.com/darakcheeff/L2HC-native-linux
Description: Native Huawei L2HC High-Resolution Audio Codec for Linux (DKMS / Dynamic Builder)
 Provides source code and automated local build scripts for the Huawei L2HC
 audio codec on Linux PipeWire and BlueZ 5.
 .
 Features:
  - 100% dynamic local compilation against the host's exact PipeWire version
  - Automatic rebuild hook on PipeWire APT package upgrades
  - Includes CLI utility: 'sudo l2hc-rebuild'
  - Bitrates: 320 kbps, 480 kbps, 640 kbps, 960 kbps, Auto
EOF

# 8. postinst script
cat << 'EOF' > "${PKG_DIR}/DEBIAN/postinst"
#!/bin/bash
set -e

sysctl --system >/dev/null 2>&1 || true

echo "=== Compiling L2HC Native Codec for host PipeWire ==="
/usr/lib/l2hc-native-linux/l2hc-builder.sh build || {
    echo "WARNING: Initial compilation failed. Check /var/log/l2hc-build.log" >&2
    echo "You can re-run 'sudo l2hc-rebuild' once required build packages are installed." >&2
}

exit 0
EOF
chmod 755 "${PKG_DIR}/DEBIAN/postinst"

# 9. postrm script
cat << 'EOF' > "${PKG_DIR}/DEBIAN/postrm"
#!/bin/bash
set -e

if [ "$1" = "remove" ] || [ "$1" = "abort-install" ] || [ "$1" = "disappear" ]; then
    SPA_DEST_DIR="/usr/lib/x86_64-linux-gnu/spa-0.2/bluez5"
    if [ ! -d "${SPA_DEST_DIR}" ]; then
        SPA_DEST_DIR="/usr/lib64/spa-0.2/bluez5"
        if [ ! -d "${SPA_DEST_DIR}" ]; then
            SPA_DEST_DIR="/usr/lib/spa-0.2/bluez5"
        fi
    fi
    rm -f "${SPA_DEST_DIR}/libspa-codec-bluez5-l2hc.so"
    if [ -f "${SPA_DEST_DIR}/libspa-bluez5.so.orig" ]; then
        cp -f "${SPA_DEST_DIR}/libspa-bluez5.so.orig" "${SPA_DEST_DIR}/libspa-bluez5.so"
    fi
    if dpkg-divert --list "${SPA_DEST_DIR}/libspa-bluez5.so" 2>/dev/null | grep -q "libspa-bluez5.so.orig"; then
        dpkg-divert --package l2hc-native-linux-dkms --no-rename --remove \
            "${SPA_DEST_DIR}/libspa-bluez5.so" || true
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

OUTPUT_DEB="${DIST_DIR}/l2hc-native-linux-dkms_${VERSION}_all.deb"
dpkg-deb --build --root-owner-group "${PKG_DIR}" "${OUTPUT_DEB}"

echo "=========================================================="
echo " Successfully created: ${OUTPUT_DEB} "
echo " Size: $(du -h "${OUTPUT_DEB}" | awk '{print $1}')"
echo "=========================================================="
