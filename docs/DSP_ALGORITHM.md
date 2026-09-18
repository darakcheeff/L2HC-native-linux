# Huawei L2HC DSP Architecture & Reverse-Engineering Technical Notes

This document contains detailed engineering notes, algorithm descriptions, and mapping between the reverse-engineered ARM64 functions in `libl2hc.so` (analyzed via Ghidra) and our clean-room C implementation in `L2HC-native-linux`.

---

## 1. Ghidra Function Mapping Table

| Original Ghidra Function | Offset in ELF | Purpose in L2HC Architecture | Native Implementation in `l2hc_native.c` |
| :--- | :--- | :--- | :--- |
| `AudioL2hcEncInit` | `0x390b8` | Allocates & initializes encoder state | `AudioL2hcEncInit` / `l2hc_native_create` |
| `AudioL2hcEncSetParam` | `0x39420` | Configures sample rate, bit depth, channels, bitrate | `AudioL2hcEncSetParam` / `l2hc_native_set_param` |
| `AudioL2hcEncApply` | `0x390b8` | Main frame entry point | `AudioL2hcEncApply` / `l2hc_native_encode` |
| `CodecTypeCheckGetMdctValues` | `0x3d55c` | Windowing + Fast MDCT with $1/\sqrt{2N}$ scaling | `compute_fast_mdct` with precomputed cosine tables |
| `GetBandInfo` | `0x33260` | Retrieves 32-band sub-band partition bins | `BAND_480` and `BAND_960` lookup tables |
| `GetScaleFactor` | `0x3bf80` | Log2 peak estimation clamped to $[-8, 23]$ | `select_band_table_and_compute_sf` |
| `UpdateBandIdAndSF` | `0x3c254` | Evaluates band partition table bit costs | `select_band_table_and_compute_sf` |
| `CheckMS` | `0x3c62c` | Forward M/S transform & bit-cost evaluation | Frequency-domain M/S check in `AudioL2hcEncApply` |
| `MdctMS` / `MdctInvMS` | `0x330b8` | Forward & inverse Mid/Side spectral matrix | Forward and revert loops in `AudioL2hcEncApply` |
| `CountBitsRough` | `0x3d1f0` | Fast floating-point bit budget estimator | `count_bits_rough` |
| `EncodeMDCTMainLoop` | `0x3de5c` | Binary search over global gain ($g$) and frac gain ($\\text{fg}$) | Stage 1 in `optimize_and_quantize` |
| `UpdatePsyQuantScaleQuater` | `0x33d54` | Fractional gain backward demotion | Demotion loop in `quantize_spectrum` |
| `QuantMDCT` | `0x340ec` | Spectral bin quantization with 0.375/0.500 rounding | `quantize_spectrum` |
| `CountBitsExact` | `0x3d060` | Accurate bit counting with table selection | `count_frame_exact_bits` |
| `EncodeMDCTCountBits` | `0x3e084` | Exact bit-budget verification loop | Feedback loop in `optimize_and_quantize` |
| `Count1TupThree` | `0x3cef8` | Evaluates 4 candidate 1-tuple Huffman tables | `select_1tup_table` |
| `Count2TupTwo` | `0x3cd3c` | Evaluates 4 candidate 2-tuple Huffman tables | `select_2tup_table` |
| `Count4TupOne` | `0x3cb80` | Evaluates 4 candidate 4-tuple Huffman tables | `select_4tup_table` |
| `PackSignBit` | `0x402dc` | Packs sign bits for non-zero coefficients | Spectral packing step 5e in `pack_frame` |
| `PackMDCTResBranch` | `0x3e648` | Packs fine residuals using residual headroom | Residual packing step 6 in `pack_frame` |
| `WordsToBytes` | `0x2e2a0` | Big-endian 64-bit word accumulator flush | `bw_flush` |

---

## 2. Low-Delay Asymmetric MDCT

L2HC utilizes an asymmetric, low-delay MDCT window $W[n]$ of length $2N$:
- Unlike standard symmetric sine windows where $W[n] = \sin\left(\frac{\pi}{2N}(n + 0.5)\right)$, L2HC uses an asymmetric design with zero-padding in the initial 30 samples.
- The window is partitioned into three segments:
  1. Lead-in zero padding ($n \in [0, 29]$): provides lookahead efficiency.
  2. Steep rising slope ($n \in [30, N-1]$): provides sharp time localization for transient suppression.
  3. Smooth falling slope ($n \in [N, 2N-1]$): provides optimal frequency resolution.

### Overlap-Add Buffer Management
```c
for (int i = 0; i < N; i++) {
    win_in[i]     = st->prev_samples[ch][i] * st->window[i];
    win_in[N + i] = curr_samples[ch][i]     * st->window[N + i];
}
memcpy(st->prev_samples[ch], curr_samples[ch], sizeof(float) * N);
```
Preserving `prev_samples` continuously across consecutive frames ensures perfect Time-Domain Aliasing Cancellation (TDAC) in the decoder.

---

## 3. Scale Factor Computation & Huffman Differential Encoding

For each sub-band $b \in [0, 31]$:
```c
float peak = 1e-10f;
for (int k = start_bin; k < end_bin; k++) {
    float a = fabsf(spec[k]);
    if (a > peak) peak = a;
}
int sf = (int)(log(peak) * 1.4426950216293335); // log2(peak)
if (sf < -8) sf = -8;
if (sf > 23) sf = 23;
```

### Delta Criteria
The condition for Huffman differential scale factor encoding:
$$\\max_{b \in [1, 31]} |\\text{sf}[b] - \\text{sf}[b-1]| \le 6$$
If any adjacent difference exceeds 6, differential mode is disabled and 5-bit absolute values are transmitted.

---

## 4. Rate-Distortion Optimization & The Overflow Defect

In earlier iterations of clean-room encoders, the global gain was selected purely by analytical estimation (`count_bits_rough`). However, `count_bits_rough` does not account for:
1. Signal sparsity variations (dense transients vs pure tones).
2. Distribution of sign bits (each non-zero bin costs 1 bit).
3. Residual packing threshold transitions.

When actual packed Huffman bits exceeded 3200 bits, the bitstream writer was cut off at byte 400, destroying the high-frequency sign bits and causing audible crackling/swishing artifacts.

### The Solution: `EncodeMDCTCountBits` Feedback Loop
Our implementation models the exact behavior discovered in Ghidra `EncodeMDCTCountBits_0013e084.c`:
```c
for (;;) {
    for (int ch = 0; ch < st->channels; ch++) {
        quantize_spectrum(st, ch);
    }

    int exact_bits = count_frame_exact_bits(st);
    if (exact_bits <= st->target_frame_bits || (st->global_gain >= 23 && st->frac_gain >= 7)) {
        break; // Frame is guaranteed to fit without truncation!
    }

    st->frac_gain++;
    if (st->frac_gain == 8) {
        st->frac_gain = 0;
        st->global_gain++;
    }
    if (st->global_gain > 23) {
        st->global_gain = 23;
        st->frac_gain = 7;
        break;
    }
}
```
This guarantees that the actual bit count is **strictly less than or equal to 3200 bits**, leaving clean headroom for `PackMDCTResBranch` and zero padding.
