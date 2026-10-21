# L2HC-native-linux

> **100% Clean-Room Native Implementation of Huawei L2HC High-Resolution Bluetooth Audio Codec for Linux (PipeWire / BlueZ)**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/darakcheeff/L2HC-native-linux)](https://github.com/darakcheeff/L2HC-native-linux/releases)
[![Platform](https://img.shields.io/badge/platform-Linux%20x86__64-lightgrey)](https://github.com/darakcheeff/L2HC-native-linux)

[Русская версия документации](README_RU.md)

---

## 🎧 Overview

**L2HC-native-linux** is a standalone, clean-room C implementation of the **Huawei L2HC** (Low-Latency High-Definition Codec) audio encoder, providing audiophile-grade Bluetooth audio streaming (up to **960 kbps, 24-bit / 48–96 kHz**) for Linux systems running **PipeWire** and **BlueZ**.

Unlike bridge or emulation-based solutions, **L2HC-native-linux** runs entirely natively as a compiled C library and PipeWire SPA plugin. **No QEMU, no Android Bionic libc, and no proprietary binaries are required.**

---

## ✨ Features

- **100% Clean-Room Native C99:** Written from reverse-engineered mathematical specifications without binary emulation.
- **Blazing Fast (>40x Realtime):** Encodes a 10 ms audio frame in ~0.23 ms on standard x86_64 CPUs (<2.5% single-core load).
- **EMUI-Matched 960 kbps Framing:** Implements strict MTU-aware packet fragmentation (`layer_specific = 1` for Fragment 1, `0` for Fragment 2) identical to Huawei Fluoride (`L2hcConstructMtuOrganizedBtBufferRecords`), completely eliminating background crackle and audio distortion.
- **Huawei Fluoride TXQ Congestion Protection:** Replicates the transmit queue manager (`L2hcA2dpSetTransmitQueueLength`): monitors socket buffer pressure (`unsent > 2400` bytes ≈ 2 packets), briefly stepping down to 640 kbps during 2.4 GHz RF collisions to prevent dropped frames (`EAGAIN`), and recovering back to full 960 kbps within 100 ms of clean transmission. Delivers rock-solid, stutter-free 960 kbps playback identical to EMUI/HarmonyOS devices.
- **Artifact-Free Bit Allocation (`EncodeMDCTCountBits`):** Exact bit-budget feedback loop ensuring zero frame truncation and crystal-clear high-frequency reproduction.
- **Dynamic Spectral Coding:** Adaptive 4-tuple, 2-tuple, and 1-tuple Huffman tables with fine residual enhancement (`PackMDCTResBranch`).
- **Universal PipeWire Compatibility (0.3, 1.0, 1.2, 1.4, 1.6):** Shipped both as a self-detecting Multi-ABI package and as an automated DKMS local source builder.
- **Desktop Integration:** Seamlessly integrates with WirePlumber, Blueman, `pavucontrol`, and GNOME/MATE sound settings.
- **Supported Profiles:**
  - `L2HC (960 kbps)`: Audiophile studio master quality (120 KB/s transfer rate).
  - `L2HC (640 kbps)`: Very high resolution with extra wireless stability.
  - `L2HC (480 kbps)`: High definition audio.
  - `L2HC (320 kbps)`: High quality, maximum wireless range.
  - `L2HC (Auto)`: Fully dynamic ABR based on RF channel condition.

---

## 📦 Quick Installation (Debian / Ubuntu / Linux Mint / Deepin)

Download the latest `.deb` packages from [Releases](https://github.com/darakcheeff/L2HC-native-linux/releases/latest):

### Option 1: Multi-ABI Fat Package (Recommended — instant offline install)
Bundles precompiled modules for PipeWire **0.3.x, 1.0.x, 1.2.x, 1.4.x, and 1.6.x**. Automatically detects your active PipeWire version on installation and links the corresponding binary:

```bash
wget https://github.com/darakcheeff/L2HC-native-linux/releases/download/v1.1.1/l2hc-native-linux-multiabi_1.1.1_amd64.deb
sudo dpkg -i l2hc-native-linux-multiabi_1.1.1_amd64.deb
```

### Option 2: DKMS Local Source Builder
Compiles the SPA plugin locally against your distribution's installed PipeWire headers and automatically recompiles on system updates:

```bash
wget https://github.com/darakcheeff/L2HC-native-linux/releases/download/v1.1.1/l2hc-native-linux-dkms_1.1.1_all.deb
sudo dpkg -i l2hc-native-linux-dkms_1.1.1_all.deb
```

---

## 🎧 Headphone Setup Note (Important!)

If your Huawei headphones (e.g. FreeBuds Studio, FreeBuds Pro 2/3/4/5) only advertise **SBC** and **AAC** during Bluetooth pairing on Linux:

1. Connect the headphones to the **Huawei AI Life** mobile app (on Android or iOS) or to a Huawei smartphone first.
2. In the headphone settings, navigate to **Sound Quality** / **Bluetooth Audio Codec** and toggle **"Smart HD Audio / L2HC"** to **ON**.
3. Once enabled, the headphones store this configuration in non-volatile memory and will advertise their vendor L2HC endpoint (`Vendor ID: 0x027D, Codec ID: 0x0001–0x0004`) to BlueZ on Linux.

---

## 🛠️ Building from Source

### Prerequisites

```bash
sudo apt-get install build-essential libspa-0.2-dev
```

### Build & Run Test Suite:

```bash
git clone https://github.com/darakcheeff/L2HC-native-linux.git
cd L2HC-native-linux
make check
```

### Build Packages:

- **Build Multi-ABI Fat Package:**
  ```bash
  ./scripts/build_multiabi_deb.sh
  ```
- **Build DKMS Package:**
  ```bash
  ./scripts/build_dkms_deb.sh
  ```

Packages will be generated in `dist/`.

---

## 🔬 Architecture & Signal Pipeline

```
  PCM Audio (24-bit / 48–96 kHz Stereo)
                 │
                 ▼
  [ Continuous Low-Delay Windowing ]  <-- MDCT_HRA_WINDOW_480 / 960 (10ms)
                 │
                 ▼
      [ Fast Type-IV MDCT ]           <-- 480 / 960 frequency bins
                 │
                 ▼
  [ Band Energy & Scale Factors ]     <-- 32 Bark-scale sub-bands
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
   [ L2CAP MTU Fragmentation & TXQ ]  <-- layer_specific headers & adaptive queue relief
                 │
                 ▼
       Bluetooth Radio (HCI)          <-- Pristine 960 kbps stream (120 KB/s)
```

---

## 📚 Technical Documentation & Specifications

- **[L2HC Complete Specification](docs/L2HC_SPECIFICATION.md):** Full mathematical and architectural specification covering AVDTP capability negotiation, MDCT filterbank, Bark-scale sub-bands, differential scale factors, and psychoacoustic quantization.
- **[DSP Architecture & Reverse-Engineering Notes](docs/DSP_ALGORITHM.md):** Detailed mapping of original Ghidra/IDA functions (`EncodeMDCTMainLoop`, `EncodeMDCTCountBits`, `CountBitsRough`, `QuantMDCT`, `L2hcConstructMtuOrganizedBtBufferRecords`, `L2hcA2dpSetTransmitQueueLength`) to clean-room native C implementation.
- **[Bitstream Structure & Wire Format Reference](docs/BITSTREAM_FORMAT.md):** Exact bit-by-bit and byte-by-byte wire layout diagram and parsing instructions.

---

## 🎧 Supported Devices

- **Huawei FreeBuds Studio**
- **Huawei FreeBuds Pro / Pro 2 / Pro 3 / Pro 4 / Pro 5**
- **Huawei FreeClip**
- Any other Bluetooth audio device advertising L2HC vendor codec capabilities (`Vendor ID: 0x027D`).

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
