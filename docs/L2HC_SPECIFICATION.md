# Huawei L2HC (Low-Latency High-Definition Audio Codec) Complete Technical Specification

**Version:** 1.0.0  
**Author:** darakcheeff  
**Date:** September 2026  
**Status:** Reverse-Engineered Clean-Room Specification (Ghidra analysis of `libl2hc.so` & AVDTP protocol analysis)

---

## 1. Executive Summary & Overview

Huawei L2HC (Low-Latency High-Definition Codec) is a proprietary Bluetooth A2DP audio codec developed by Huawei Technologies. It provides high-fidelity, low-latency audio transmission with bitrates ranging from **320 kbps to 960 kbps** at sample rates up to **96 kHz** and sample resolutions up to **24-bit**.

This document provides a comprehensive, mathematically rigorous technical specification of the entire L2HC codec architecture, covering:
1. Bluetooth A2DP Transport & Capability Negotiation (AVDTP).
2. Time-to-Frequency Analysis Filterbank (Low-Delay Type-IV MDCT & Asymmetric Windowing).
3. Psychoacoustic Sub-Band Grouping & Scale Factor Estimation.
4. Frequency-Domain Mid/Side (M/S) Stereo Processing.
5. Dual-Stage Rate-Distortion Optimization & Exact Bit Allocation.
6. Multi-Tuple Adaptive Huffman Spectral Quantization & Encoding.
7. Fine-Grain Residual Encoding (`PackMDCTResBranch`).
8. Frame Serialization & Bitstream Wire Format.

---

## 2. Bluetooth A2DP Transport Identification (Vendor-Specific Codec)

In the Bluetooth AVDTP / A2DP specification, L2HC is registered as an A2DP Vendor-Specific Codec:

| Field | Value | Description |
| :--- | :--- | :--- |
| **Media Type** | `0x00` | Audio |
| **Codec Type** | `0xFF` | Non-A2DP / Vendor-Specific Codec |
| **Vendor ID (Company ID)** | `0x0000027D` | **Huawei Technologies Co., Ltd.** (Bluetooth SIG Company Identifier 637) |
| **Codec ID** | `0x3500` / `0x4C35` | In Little-Endian: `0x35, 0x4C` (ASCII '5L') or `0x3500` (Huawei internal) |
| **CIE Length (LOSC)** | `12` bytes | Length of Codec Information Elements in AVDTP Service Capabilities |

### 2.1 A2DP Codec Information Elements (12-Octet Structure)

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|  LOSC (0x0C)  |Media Type(0x0)|CodecType(0xFF)| Vendor ID [0] |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|       Vendor ID [1..3]        |         Codec ID (0x3500)     |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|BitsPerSample  | Sampling Freq | Bitrates High |BitratesLow&Dur|
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

#### Octet Details:
- **Octet 0:** `0x0C` (Length of subsequent descriptor = 12 bytes).
- **Octet 1:** `0x00` (Audio Media Type).
- **Octet 2:** `0xFF` (Non-A2DP Vendor Codec).
- **Octets 3..6:** `0x7D, 0x02, 0x00, 0x00` (Company ID `0x0000027D`, Huawei Technologies).
- **Octets 7..8:** `0x00, 0x35` / `0x35, 0x4C` (Codec ID).
- **Octet 9 (Bits Per Sample):**
  - Bit 7 (`0x80`): Reserved
  - Bit 6 (`0x40`): Reserved
  - Bit 5 (`0x20`): 32-bit audio resolution
  - Bit 4 (`0x10`): **24-bit audio resolution** (Recommended)
  - Bit 3 (`0x08`): **16-bit audio resolution**
  - Bit 2..0: Reserved
- **Octet 10 (Sampling Frequency):**
  - Bit 7 (`0x80`): Reserved
  - Bit 6 (`0x40`): Reserved
  - Bit 5 (`0x20`): **96.0 kHz**
  - Bit 4 (`0x10`): **88.2 kHz**
  - Bit 3 (`0x08`): **48.0 kHz**
  - Bit 2 (`0x04`): **44.1 kHz**
  - Bit 1..0: Reserved
- **Octet 11 (Bitrates High):**
  - Bit 7 (`0x80`): Reserved
  - Bit 6 (`0x40`): Reserved
  - Bit 5 (`0x20`): **960 kbps**
  - Bit 4 (`0x10`): **640 kbps**
  - Bit 3 (`0x08`): Reserved
  - Bit 2 (`0x04`): **320 kbps**
  - Bit 1..0: Reserved
- **Octet 12 (Bitrates Low & Frame Duration):**
  - Bit 7 (`0x80`): **Adaptive Bitrate (Auto)**
  - Bit 6 (`0x40`): Reserved
  - Bit 5 (`0x20`): Reserved
  - Bit 4 (`0x10`): Reserved
  - Bit 3 (`0x08`): **10.0 ms Frame Duration** (Standard, 480 samples @ 48kHz)
  - Bit 2 (`0x04`): **5.0 ms Frame Duration** (Low-latency mode)
  - Bit 1 (`0x02`): **2.5 ms Frame Duration** (Ultra-low-latency mode)
  - Bit 0 (`0x01`): Reserved

---

## 3. Framing Parameters & Bit Budgets

L2HC operates with fixed frame sizes depending on the negotiated frame duration and sample rate. For the standard 10 ms frame duration:

| Sample Rate | Samples/Frame ($N$) | Bitrate | Bytes/Frame | Total Bits/Frame | PCM Input Bytes (24-bit 2ch) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **48 kHz** | 480 | 320 kbps | 400 B | 3200 bits | 2880 bytes |
| **48 kHz** | 480 | 640 kbps | 800 B | 6400 bits | 2880 bytes |
| **48 kHz** | 480 | 960 kbps | 1200 B | 9600 bits | 2880 bytes |
| **96 kHz** | 960 | 640 kbps | 800 B | 6400 bits | 5760 bytes |
| **96 kHz** | 960 | 960 kbps | 1200 B | 9600 bits | 5760 bytes |

---

## 4. Time-to-Frequency Filterbank: Fast Type-IV MDCT

L2HC decomposes time-domain audio samples into frequency sub-band coefficients using an asymmetric, low-delay Modified Discrete Cosine Transform (Type-IV MDCT).

### 4.1 Windowing & Overlap-Add
For a frame of length $N$ (e.g. 480 samples), a window of length $2N$ (960 samples) is applied across the previous frame's samples and current frame's samples:
$$w_{	ext{in}}[n] = x[n] \cdot W[n], \quad n \in [0, 2N-1]$$
where $W[n]$ is the precomputed asymmetric window table `MDCT_HRA_WINDOW_480_10MS` (or `MDCT_HRA_WINDOW_960_10MS` for 96 kHz).

Notice that the first 30 bins of the low-delay window are zero, providing lookahead optimization without introducing algorithmic buffer delay.

### 4.2 MDCT Transform Formula
The Type-IV MDCT transforms $2N$ windowed time-domain samples into $N$ spectral coefficients:
$$X[k] = 	ext{norm} \sum_{n=0}^{2N-1} w_{	ext{in}}[n] \cos\left[ rac{\pi}{N} \left( n + rac{1}{2} + rac{N}{2} ight) \left( k + rac{1}{2} ight) ight]$$

### 4.3 Normalization Factor
To match the original reference implementation and psychoacoustic scale factors, the normalization factor is:
$$	ext{norm} = rac{2.0}{N}$$
For $N = 480$: $	ext{norm} = rac{2.0}{480.0} = rac{1.0}{240.0}$.  
For $N = 960$: $	ext{norm} = rac{2.0}{960.0} = rac{1.0}{480.0}$.

---

## 5. Psychoacoustic Sub-Bands & Scale Factor Estimation

The $N$ spectral bins are partitioned into **32 non-uniform psychoacoustic sub-bands** corresponding to the Bark scale / Equivalent Rectangular Bandwidth (ERB):

### 5.1 Band Table (480 Bins / 32 Bands)
`BAND_480` partition index table:
```c
{ 0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 56, 64, 72, 80, 
  92, 104, 116, 128, 144, 160, 180, 200, 224, 252, 284, 320, 360, 400, 440, 480 }
```
Each band $b \in [0, 31]$ spans spectral bins $k \in [	ext{tbl}[b], 	ext{tbl}[b+1])$.

### 5.2 Scale Factor Calculation
For each band $b$, the maximum peak magnitude is identified:
$$	ext{peak}[b] = \max_{k \in [	ext{tbl}[b], 	ext{tbl}[b+1])} |X[k]|$$
The base scale factor is computed as the base-2 logarithm of the peak:
$$	ext{sf}[b] = 	ext{clamp}\left( \left\lfloor \log_2(	ext{peak}[b]) ightfloor, -8, 23 ight)$$
Implemented as:
```c
int sf = (int)(log(peak) * 1.4426950216293335); // 1.0 / ln(2)
if (sf < -8) sf = -8;
if (sf > 23) sf = 23;
```

### 5.3 Huffman Differential Scale Factor Encoding
L2HC evaluates whether scale factors can be encoded differentially between consecutive bands:
1. Compute deltas: $\Delta[b] = 	ext{sf}[b] - 	ext{sf}[b-1]$ for $b \in [1, 31]$.
2. If $\max_{b} |\Delta[b]| \le 6$:
   - `diff_sf_flag = 1`.
   - Band 0 is encoded with 5 bits: $(	ext{sf}[0] + 8) \in [0, 31]$.
   - Bands 1..31 are encoded using Huffman table `HUF_ENC_DIFF_SF`:
     - $|\Delta| \in [0, 6]$ maps to a Huffman codeword of length 1 to 6 bits.
     - If $|\Delta| > 0$, 1 sign bit follows (1 for positive delta, 0 for negative).
3. If any $|\Delta[b]| > 6$:
   - `diff_sf_flag = 0`.
   - All 32 bands are written as raw 5-bit integers: $(	ext{sf}[b] + 8)$.

---

## 6. Frequency-Domain Mid/Side (M/S) Stereo Processing

To maximize coding efficiency across stereo audio, L2HC evaluates Mid/Side (M/S) transform dynamically in the frequency domain.

### 6.1 Forward M/S Transform
For spectral coefficients $L[k]$ and $R[k]$:
$$M[k] = 0.5 \cdot (L[k] + R[k])$$
$$S[k] = 0.5 \cdot (L[k] - R[k])$$

### 6.2 Exact Bit-Cost Evaluation (`CheckMS`)
The encoder calculates the scale factor bit costs:
$$	ext{cost}_{	ext{lr}} = \sum_{ch=0}^{1} \sum_{b=0}^{31} 	ext{width}[b] \cdot 	ext{sf}_{	ext{lr}}[ch][b]$$
$$	ext{cost}_{	ext{ms}} = \sum_{ch=0}^{1} \sum_{b=0}^{31} 	ext{width}[b] \cdot 	ext{sf}_{	ext{ms}}[ch][b]$$
- If $	ext{cost}_{	ext{ms}} < 	ext{cost}_{	ext{lr}}$:
  - Adopt M/S mode (`ms_flag = 1`).
  - Use $M$ and $S$ spectral buffers.
- Otherwise:
  - Revert to discrete L/R (`ms_flag = 0`):
    $$L[k] = M[k] + S[k], \quad R[k] = M[k] - S[k]$$

---

## 7. Dual-Stage Rate-Distortion Optimization & Quantization

L2HC employs a two-stage global gain search to ensure maximum audio resolution while guaranteeing that compressed bits strictly fit within the target frame budget.

### 7.1 Bit Depth per Band
For global gain $g \in [-8, 23]$:
$$	ext{bd}[ch][b] = \max(0, 	ext{sf}[ch][b] - g)$$
$$	ext{quant\_scale}[ch][b] = g$$

### 7.2 Fractional Gain Demotion (`UpdatePsyQuantScaleQuater`)
To provide fine sub-dB bit-rate control without adjusting the global gain by an entire integer step, L2HC defines a 3-bit fractional gain parameter $	ext{fg} \in [0, 7]$:
$$	ext{demote\_samples} = (	ext{active\_samples} \cdot 	ext{fg}) \gg 3$$
The encoder sweeps backwards from the highest frequency band ($b = 31$ down to 0). For each active band with $	ext{bd}[ch][b] > 0$:
$$	ext{bd}[ch][b] \leftarrow 	ext{bd}[ch][b] - 1$$
$$	ext{quant\_scale}[ch][b] \leftarrow 	ext{quant\_scale}[ch][b] + 1$$
$$	ext{demote\_samples} \leftarrow 	ext{demote\_samples} - 	ext{width}[b]$$

### 7.3 Quantization Formula
For each bin $k$ in active band $b$:
$$	ext{step} = 2^{	ext{quant\_scale}[ch][b]}$$
$$	ext{inv\_step} = 2^{-	ext{quant\_scale}[ch][b]} = 	ext{ldexpf}(1.0, -	ext{quant\_scale})$$
$$	ext{rounding} = egin{cases} 0.375, & 	ext{if } 	ext{bd} = 1 \ 0.500, & 	ext{if } 	ext{bd} \ge 2 \end{cases}$$
$$Q[k] = 	ext{clamp}\left( \left\lfloor |X[k]| \cdot 	ext{inv\_step} + 	ext{rounding} ightfloor, 0, 2^{	ext{bd}} - 1 ight)$$
$$	ext{sign}[k] = egin{cases} 1, & 	ext{if } X[k] > 0 \ 0, & 	ext{if } X[k] \le 0 \end{cases}$$

### 7.4 Exact Bit-Budget Verification Loop (`EncodeMDCTCountBits`)
1. An initial fast binary search finds the candidate $(g, 	ext{fg})$ using rough bit estimation (`count_bits_rough`).
2. The encoder quantizes both channels and calculates the **exact bit count**:
   $$	ext{exact\_bits} = 	ext{bits}_{	ext{header}} + 	ext{bits}_{	ext{sf}} + 	ext{bits}_{	ext{tables}} + \sum_{ch=0}^{1} 	ext{exact\_spectral\_bits}(ch)$$
3. If $	ext{exact\_bits} > 	ext{target\_frame\_bits}$:
   - Increment $	ext{fg} \leftarrow 	ext{fg} + 1$.
   - If $	ext{fg} = 8$: reset $	ext{fg} \leftarrow 0$, and increment $g \leftarrow g + 1$.
   - Re-quantize and repeat until $	ext{exact\_bits} \le 	ext{target\_frame\_bits}$.

This feedback loop guarantees that the spectral data is **never truncated**, completely eliminating crackles and high-frequency artifacts.

---

## 8. Multi-Tuple Adaptive Entropy Coding

Quantized spectral coefficients are encoded using tuple grouping based on the band's bit depth:

| Bit Depth ($	ext{bd}$) | Tuple Grouping | Huffman Codebooks | Residuals / Leaves |
| :--- | :--- | :--- | :--- |
| $	ext{bd} \ge 3$ | **1-tuple** (individual bins) | `HUF_ENC_1TUP_THREE_1..4` (3 MSBs) | $(	ext{bd} - 3)$ raw LSBs |
| $	ext{bd} = 2$ | **2-tuple** (pairs of bins) | `HUF_ENC_2TUP_TWO_1..4` | 2-bit raw fallback |
| $	ext{bd} = 1$ | **4-tuple** (groups of 4 bins)| `HUF_ENC_4TUP_ONE_1..4` | 1-bit raw fallback |

### 8.1 1-Tuple Coding ($	ext{bd} \ge 3$)
- **Pass 1 (MSBs):** Each coefficient is shifted right by $(	ext{bd} - 3)$ bits:
  $$	ext{msb} = \min(7, Q[k] \gg (	ext{bd} - 3))$$
  Encoded using the channel's selected 1-tuple Huffman table.
- **Pass 2 (LSBs):** The remaining $(	ext{bd} - 3)$ least significant bits are written directly as raw bits.

### 8.2 2-Tuple Coding ($	ext{bd} = 2$)
Coefficients (taking values in $\{0, 1, 2, 3\}$) are grouped in pairs $(Q_{2i}, Q_{2i+1})$:
$$	ext{symbol} = (Q_{2i} \ll 2) \mid Q_{2i+1} \in [0, 15]$$
Encoded using the selected 2-tuple Huffman table. If 1 sample remains at the end of the bands, it is written as a 2-bit raw value.

### 8.3 4-Tuple Coding ($	ext{bd} = 1$)
Binary coefficients ($Q_k \in \{0, 1\}$) are grouped into 4-tuples:
$$	ext{symbol} = (Q_{4i} \ll 3) \mid (Q_{4i+1} \ll 2) \mid (Q_{4i+2} \ll 1) \mid Q_{4i+3} \in [0, 15]$$
Encoded using the selected 4-tuple Huffman table. Any leftover samples ($< 4$) are written directly as raw bits.

### 8.4 Sign Bits
For every active band ($	ext{bd} > 0$), each non-zero quantized coefficient ($Q[k] > 0$) writes exactly **1 sign bit**:
- `1` = positive ($X[k] > 0$)
- `0` = negative ($X[k] < 0$)

---

## 9. Fine Residual Packing (`PackMDCTResBranch`)

Any unused headroom bits between the spectral bit count and the target frame budget are filled with fine-grain residual bits to improve audio resolution:

1. Bands are sorted by priority (energy / scale factor).
2. For each ranked band, the quantizer threshold is tested against the original MDCT magnitude:
   - For $	ext{bd} = 1$: $	ext{threshold} = 	ext{step} \cdot (0.125 + Q[k])$
   - For $	ext{bd} \ge 2$: $	ext{threshold} = 	ext{step} \cdot (0.000 + Q[k])$
   - If $|X[k]| \ge 	ext{threshold}$, bit `1` is appended; otherwise bit `0`.
3. If bits remain after all residuals, zero bits (`0ULL`) pad the frame to the exact target byte boundary.

---

## 10. Bitstream Wire Format Reference

Every L2HC frame begins with sync byte `0x5C`:

| Offset (Bits) | Field Name | Size (Bits) | Description / Value |
| :--- | :--- | :--- | :--- |
| `0..6` | **Header** | 7 bits | `(1 << 5) \| (sr_idx << 3) \| (ch_idx << 2) \| fl_idx` (`0x2E` for 48kHz/stereo/10ms) |
| `7` | **Low Bitrate Flag** | 1 bit | `0` for $\ge 320	ext{ kbps}$ |
| `8` | **M/S Stereo Flag** | 1 bit | `1` = Mid/Side, `0` = Discrete L/R (stereo only) |
| `9..13` | **Global Gain** | 5 bits | $(g + 8) \in [0, 31]$ |
| `14..16`| **Fractional Gain**| 3 bits | $	ext{fg} \in [0, 7]$ |
| `17..19`| **Band Table Index**| 3 bits| Index of active band partition table |
| `20` | **Diff SF Flag** | 1 bit | `1` = Huffman delta SF, `0` = 5-bit absolute SF |
| Variable | **Scale Factors** | Variable | Ch0 and Ch1 scale factors |
| Variable | **Table Indices** | 6 bits / ch | 2 bits (4tup) + 2 bits (2tup) + 2 bits (1tup) |
| Variable | **Spectral Data** | Variable | 1tup MSB, 1tup LSB, 2tup, 4tup, signs |
| Variable | **Residuals** | Variable | Fine-grain residual bits |
| Variable | **Zero Padding** | Variable | Padded to target frame bytes (400, 800, or 1200 B) |

---

## 11. Reference C API Specification

```c
typedef struct {
    uint32_t sample_rate;   // 44100, 48000, 88200, 96000
    int16_t  bps;           // 16, 24
    int16_t  channels;      // 1, 2
    int16_t  frame_samples; // 480 (48k), 960 (96k)
    int16_t  bitrate_kbps;  // 320, 640, 960
} L2hcEncParam;

typedef struct {
    const uint8_t *in_buffer;
    uint32_t       in_bytes;
    uint8_t       *out_buffer;
    uint32_t       out_bytes;
} L2hcEncIo;

// Core Lifecycle
l2hc_native_t l2hc_native_create(void);
int l2hc_native_set_param(l2hc_native_t enc, const L2hcEncParam *param);
int l2hc_native_encode(l2hc_native_t enc, const uint8_t *pcm_in, uint32_t in_bytes, uint8_t *out_buf, uint32_t *out_len);
void l2hc_native_destroy(l2hc_native_t enc);
```
