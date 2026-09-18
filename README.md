# L2HC-native-linux

> **100% Clean-Room Native Implementation of Huawei L2HC High-Resolution Bluetooth Audio Codec for Linux (PipeWire / BlueZ)**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/darakcheeff/L2HC-native-linux)](https://github.com/darakcheeff/L2HC-native-linux/releases)
[![Platform](https://img.shields.io/badge/platform-Linux%20x86__64-lightgrey)](https://github.com/darakcheeff/L2HC-native-linux)

[Русская версия документации](README_RU.md)

---

## 🎧 Overview

**L2HC-native-linux** is a standalone, clean-room C implementation of the **Huawei L2HC** (Low-Latency High-Definition Codec) audio encoder, providing high-resolution Bluetooth audio streaming (up to **960 kbps, 24-bit / 48–96 kHz**) for Linux systems running **PipeWire** and **BlueZ**.

Unlike bridge or emulation-based solutions, **L2HC-native-linux** runs entirely natively as a compiled C library and PipeWire SPA plugin. **No QEMU, no Android Bionic libc, and no ARM64 proprietary binaries are required.**

---

## ✨ Features

- **100% Clean-Room Native C99:** Written from reverse-engineered mathematical specifications without binary emulation.
- **Blazing Fast (>40x Realtime):** Encodes a 10 ms audio frame in ~0.23 ms on standard x86_64 CPUs (<2.5% single-core load).
- **Artifact-Free Bit Allocation (`EncodeMDCTCountBits`):** Implements an exact bit-budget feedback loop ensuring zero frame truncation and crystal-clear high-frequency reproduction.
- **Dynamic Spectral Coding:** Adaptive 4-tuple, 2-tuple, and 1-tuple Huffman tables for maximum coding efficiency.
- **Lossless Residual Enhancement (`PackMDCTResBranch`):** Headroom bits are dynamically allocated to fine-grain spectral residuals.
- **Standard Linux Audio Integration:** Seamlessly integrates with PipeWire 0.3 / 1.x, WirePlumber, Blueman, `pavucontrol`, and GNOME/MATE sound settings.
- **Supported Bitrates:**
  - `320 kbps` (High quality, maximum wireless range)
  - `640 kbps` (Very high quality)
  - `960 kbps` (Ultra high-definition / audiophile grade)
  - `Auto` (Adaptive bitrate based on RF channel condition)

---

## 📦 Quick Installation (Debian / Ubuntu / Linux Mint)

1. Download the latest `.deb` release package from [Releases](https://github.com/darakcheeff/L2HC-native-linux/releases):
   ```bash
   wget https://github.com/darakcheeff/L2HC-native-linux/releases/download/v1.0.0/l2hc-native-linux_1.0.0_amd64.deb
   ```
2. Install the package:
   ```bash
   sudo dpkg -i l2hc-native-linux_1.0.0_amd64.deb
   sudo apt-get install -f # in case of any missing dependencies
   ```
3. Connect your Huawei headphones (e.g. FreeBuds Studio, FreeBuds Pro 2/3) and select **L2HC** in your sound settings or Bluetooth manager.

---

## 🛠️ Building from Source

### Prerequisites

- GCC or Clang (supporting C99)
- `make`
- `libspa-0.2-dev` and `pipewire` development headers (optional, for compiling SPA plugin)

### Build `libl2hc.so` and run tests:

```bash
git clone https://github.com/darakcheeff/L2HC-native-linux.git
cd L2HC-native-linux
make check
```

### Build Debian Package:

```bash
./scripts/build_deb.sh
```
The resulting `.deb` package will be generated in `dist/l2hc-native-linux_1.0.0_amd64.deb`.

---

## 🔬 Architecture & Signal Pipeline

```
  PCM Audio (24-bit / 48 kHz Stereo)
                 │
                 ▼
  [ Continuous Low-Delay Windowing ]  <-- MDCT_HRA_WINDOW_480_10MS
                 │
                 ▼
     [ Fast Type-IV MDCT ]           <-- 480 / 960 frequency bins
                 │
                 ▼
  [ Band Energy & Scale Factors ]     <-- 32 Bark-scale bands
                 │
                 ▼
     [ Cost-Based Mid/Side Check ]    <-- Dynamic L/R vs M/S selection
                 │
                 ▼
   [ Fast Rough Gain Search ]        <-- Binary search on global_gain
                 │
                 ▼
 [ Exact Bit-Budget Feedback Loop ]   <-- EncodeMDCTCountBits (Zero Overflows)
                 │
                 ▼
  [ Quantization & Huffman Coding ]   <-- 4tup, 2tup, 1tup + Signs
                 │
                 ▼
  [ Fine Residual Packing ]           <-- PackMDCTResBranch (Headroom fill)
                 │
                 ▼
      Output L2HC Bitstream           <-- Sync byte 0x5c, 400 bytes/frame
```

---


---

## 📚 Technical Documentation & Specifications

For an in-depth understanding of the codec internals, reverse-engineering methodology, and bitstream structure, refer to the documentation in [`docs/`](docs/):

- **[L2HC Complete Specification](docs/L2HC_SPECIFICATION.md):** Full mathematical and architectural specification covering AVDTP capability negotiation, MDCT filterbank, Bark-scale sub-bands, differential scale factors, and psychoacoustic quantization.
- **[DSP Architecture & Reverse-Engineering Notes](docs/DSP_ALGORITHM.md):** Detailed mapping of original Ghidra functions (`EncodeMDCTMainLoop`, `EncodeMDCTCountBits`, `CountBitsRough`, `QuantMDCT`, etc.) to clean-room native C implementation.
- **[Bitstream Structure & Wire Format Reference](docs/BITSTREAM_FORMAT.md):** Exact bit-by-bit and byte-by-byte wire layout diagram and parsing instructions.

## 🎧 Supported Devices

Tested and confirmed working with:
- **Huawei FreeBuds Studio**
- **Huawei FreeBuds Pro / Pro 2 / Pro 3**
- **Huawei FreeClip**
- Any other A2DP device advertising L2HC vendor codec capabilities (`Vendor ID: 0x027d`, `Codec ID: 0x3500`).

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
