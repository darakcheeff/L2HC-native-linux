# Huawei L2HC Bitstream Structure & Wire Format Reference

This document provides a bit-level and byte-level breakdown of the encoded Huawei L2HC audio frame bitstream. It serves as a direct reference for understanding, analyzing, parsing, or implementing L2HC encoders and decoders.

---

## 1. Frame Overview

An L2HC frame corresponds to a 10 ms audio segment (480 samples @ 48 kHz or 960 samples @ 96 kHz).
The frame length in bytes is determined strictly by the target bitrate:

| Bitrate | Frame Duration | Target Frame Size | Total Bit Budget |
| :--- | :--- | :--- | :--- |
| **320 kbps** | 10.0 ms | **400 bytes** | 3,200 bits |
| **640 kbps** | 10.0 ms | **800 bytes** | 6,400 bits |
| **960 kbps** | 10.0 ms | **1200 bytes** | 9,600 bits |

All bitstream packing uses **Big-Endian / MSB-First bit packing**.

---

## 2. Bitstream Top-Level Syntax

A serialized L2HC frame consists of the following sequential sections:

```
+-------------------------------------------------------------+
| 1. Frame Header & Metadata Flags (21 bits)                  |
+-------------------------------------------------------------+
| 2. Scale Factors (Channels 0 & 1)                           |
+-------------------------------------------------------------+
| 3. Huffman Table Selectors (6 bits per channel)             |
+-------------------------------------------------------------+
| 4. Quantized MDCT Spectral Data                             |
|    - 1-Tuple MSB Huffman Codes                              |
|    - 1-Tuple LSB Raw Bits                                   |
|    - 2-Tuple Huffman Codes                                  |
|    - 4-Tuple Huffman Codes                                  |
|    - Sign Bits (1 bit per non-zero coefficient)             |
+-------------------------------------------------------------+
| 5. Fine Spectral Residuals (PackMDCTResBranch)              |
+-------------------------------------------------------------+
| 6. Zero Padding (to exact frame byte size)                  |
+-------------------------------------------------------------+
```

---

## 3. Header & Metadata Fields (Bits 0 to 20)

```
 0                   1                   2
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|   Sync/Hdr  |L|M| GlobalGain  |FracG|Bnd|D|
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

### Field Definitions

| Bit Offset | Field Name | Width | Range / Format | Description |
| :---: | :--- | :---: | :--- | :--- |
| **0 .. 6** | `sync_header` | 7 bits | `0x2E` (at 48 kHz / 2 ch) | Frame synchronization and format token. Encoded as: `(1 << 5) \| (sr_idx << 3) \| (ch_idx << 2) \| fl_idx`. |
| **7** | `low_bitrate` | 1 bit | `0` or `1` | `0` for normal bitrates ($\ge 320$ kbps), `1` for low bitrates. |
| **8** | `ms_flag` | 1 bit | `0` or `1` | Frequency-Domain Stereo Mode: `1` = Mid/Side (M/S), `0` = Left/Right (L/R). *(Stereo streams only)*. |
| **9 .. 13** | `global_gain` | 5 bits | `0 .. 31` | Quantized global scale factor bias: $\text{transmitted} = g + 8$, where $g \in [-8, 23]$. |
| **14 .. 16** | `frac_gain` | 3 bits | `0 .. 7` | Sub-step fractional gain: $\text{step} = 2^{g + \text{fg}/8}$. |
| **17 .. 19** | `band_table` | 3 bits | `0 .. 7` | Index of active sub-band grouping partition table (typically `0`). |
| **20** | `diff_sf_flag`| 1 bit | `0` or `1` | Scale factor encoding mode: `1` = Differential Huffman, `0` = 5-bit Absolute. |

---

## 4. Scale Factors Section

For each channel ($c \in [0, \text{channels}-1]$), the 32 Bark-scale band scale factors $\text{sf}[b]$ are written:

### Case A: Differential Mode (`diff_sf_flag == 1`)
- **Band 0:** 5-bit absolute value ($\text{sf}[0] + 8 \in [0, 31]$).
- **Bands 1 .. 31:** Huffman-encoded differential $\Delta = \text{sf}[b] - \text{sf}[b-1]$.
  Diff values are mapped via `DIFF_SF_CODES` (range $[-6, +6]$).

### Case B: Absolute Mode (`diff_sf_flag == 0`)
- **Bands 0 .. 31:** Each band transmits a 5-bit raw integer: $(\text{sf}[b] + 8) \in [0, 31]$.

---

## 5. Huffman Table Selectors Section

For each channel, 6 bits are transmitted to select the optimal Huffman codebooks for spectral decoding:

```
+-+-+-+-+-+-+
|4T |2T |1T |
+-+-+-+-+-+-+
 0 1 2 3 4 5
```

- **Bits 0..1:** Index of 4-tuple Huffman Table (`0 .. 3`).
- **Bits 2..3:** Index of 2-tuple Huffman Table (`0 .. 3`).
- **Bits 4..5:** Index of 1-tuple Huffman Table (`0 .. 3`).

---

## 6. Spectral Quantization & Huffman Serialization

MDCT frequency bins $k \in [0, N-1]$ are quantized according to their sub-band bit depth $bd[b]$:

$$bd[b] = \max(0, \text{sf}[b] - g) \quad \text{demoted by fractional gain}$$

Quantized coefficients $Q[k]$ are then packed sequentially by tuple tier:

### 6.1 1-Tuple Coding ($bd[b] \ge 3$)
1. **Pass 1 - MSB Huffman:** For each bin in the band:
   $$\text{msb} = \min(7, Q[k] \gg (bd[b] - 3))$$
   Symbol $\text{msb} \in [0, 7]$ is written using the channel's 1-tuple Huffman table.
2. **Pass 2 - LSB Raw Bits:** The lower $(bd[b] - 3)$ bits are written directly as uncompressed bits.

### 6.2 2-Tuple Coding ($bd[b] == 2$)
Coefficients (values in $\{0, 1, 2, 3\}$) are grouped into consecutive pairs $(Q_{2i}, Q_{2i+1})$:
$$\text{symbol} = (Q_{2i} \ll 2) \mid Q_{2i+1} \in [0, 15]$$
The symbol is written using the selected 2-tuple Huffman table. If 1 sample remains at the end of the bands, it is written as a 2-bit raw integer.

### 6.3 4-Tuple Coding ($bd[b] == 1$)
Coefficients (values in $\{0, 1\}$) are grouped into 4-tuples:
$$\text{symbol} = (Q_{4i} \ll 3) \mid (Q_{4i+1} \ll 2) \mid (Q_{4i+2} \ll 1) \mid Q_{4i+3} \in [0, 15]$$
The symbol is written using the selected 4-tuple Huffman table. Residual bins ($< 4$) are written as 1-bit raw integers.

### 6.4 Sign Bits
Immediately following the magnitude data of all active bands ($bd[b] > 0$):
- For every bin where $Q[k] > 0$, exactly **1 sign bit** is written:
  - `1`: Positive coefficient ($X[k] > 0$)
  - `0`: Negative coefficient ($X[k] < 0$)
- Zero coefficients ($Q[k] = 0$) do **not** write sign bits.

---

## 7. Fine Residual Packing (`PackMDCTResBranch`)

After the spectral Huffman codes and sign bits are written, remaining bit budget is used for fine quantization residuals:

1. Bands with $bd[b] \ge 1$ are prioritized.
2. For each candidate bin $k$, residual comparison is evaluated:
   - For $bd[b] == 1$: $\text{threshold} = \text{step} \cdot (0.125 + Q[k])$
   - For $bd[b] \ge 2$: $\text{threshold} = \text{step} \cdot (0.000 + Q[k])$
3. If $|X[k]| \ge \text{threshold}$, bit `1` is written; otherwise bit `0`.
4. Packing terminates when target frame bits ($3200, 6400, 9600$) are reached.
5. If residual candidates are exhausted before budget, zero bits (`0`) pad the stream to the end of the frame.

---

## 8. Summary Table: Bitstream Field Ordering

```
+========================================================================+
| Bit Offset   | Length (bits) | Field Description                       |
+========================================================================+
| 0            | 7             | Sync & Format Header (0x2E)             |
| 7            | 1             | Low Bitrate Flag                        |
| 8            | 1             | M/S Stereo Flag (0 = LR, 1 = MS)        |
| 9            | 5             | Global Gain (bias +8)                   |
| 14           | 3             | Fractional Gain (0..7)                  |
| 17           | 3             | Sub-Band Partition Table Index          |
| 20           | 1             | Differential Scale Factor Flag          |
| 21           | Variable      | Scale Factors Ch 0 (5b abs or Huff diff)|
| Variable     | Variable      | Scale Factors Ch 1 (if stereo)          |
| Variable     | 6             | Huffman Table Selectors Ch 0 (4T/2T/1T) |
| Variable     | 6             | Huffman Table Selectors Ch 1 (if stereo)|
| Variable     | Variable      | 1-Tuple MSB Huffman Codes               |
| Variable     | Variable      | 1-Tuple LSB Raw Bits                    |
| Variable     | Variable      | 2-Tuple Huffman Codes                   |
| Variable     | Variable      | 4-Tuple Huffman Codes                   |
| Variable     | Variable      | Sign Bits (1 bit per Q[k] > 0)          |
| Variable     | Variable      | Fine Residual Bits (PackMDCTResBranch)  |
| Variable     | Variable      | Zero Padding (to exact frame length)    |
+========================================================================+
```
